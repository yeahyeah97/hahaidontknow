#!/usr/bin/env python3
"""Steam Mobile SM-001/2: fail-closed DXMT / Wine / FEX engine patcher.

Does not alter game INI files, Steam state, or saved data.
"""
import argparse
import hashlib
import sys
from pathlib import Path

class PatchError(Exception):
    pass

def replace_one(src, old, new, label):
    count = src.count(old)
    if count != 1:
        raise PatchError(f"{label}: expected one original source anchor, got {count}")
    return src.replace(old, new, 1)

def patch_dxmt(src):
    old = """    uint32_t thread_id = ::GetCurrentThreadId();
    uint32_t expected = 0;

    bool status = m_owner.compare_exchange_weak(expected, thread_id, std::memory_order_acquire);"""
    new = """    uint32_t thread_id = ::GetCurrentThreadId();
#ifdef DXMT_MADEIRA
    // Steam Mobile SM-001: owner recursion needs no atomic read-modify-write.
    // The counter is exclusively mutated by the existing owning thread.
    // First ownership acquisition still uses the original acquire CAS.
    if (m_owner.load(std::memory_order_relaxed) == thread_id) {
      m_counter += 1;
      return true;
    }
#endif
    uint32_t expected = 0;

    bool status = m_owner.compare_exchange_weak(expected, thread_id, std::memory_order_acquire);"""
    return replace_one(src, old, new, "DXMT D3D9 recursive fast path")

def patch_winios(src):
    old = """/* Public C entry points for Swift / UIKit gesture handlers.
 * Coordinates are in iOS view-local pixels; we scale to a fixed"""
    new = """/* Steam Mobile SM-001: per-input synchronous logging is opt-in.
 * A logging fflush for every dispatched input adds needless latency. */
static int winios_trace_input(void) {
    static int enabled = -1;
    if (enabled < 0) {
        const char *value = getenv("MADEIRA_INPUT_TRACE");
        enabled = value && value[0] == '1';
    }
    return enabled;
}

/* Public C entry points for Swift / UIKit gesture handlers.
 * Coordinates are in iOS view-local pixels; we scale to a fixed"""
    src = replace_one(src, old, new, "input trace helper")
    changes = [
        (
            '    fprintf(stderr, "[winios] post_touch_down x=%d y=%d\\n", x, y); fflush(stderr);',
            '    if (winios_trace_input()) { fprintf(stderr, "[winios] post_touch_down x=%d y=%d\\n", x, y); fflush(stderr); }',
            "touch-down"
        ),
        (
            '    if ((cnt++ % 30) == 0) {\n        fprintf(stderr, "[winios] post_touch_move x=%d y=%d (n=%u)\\n", x, y, cnt); fflush(stderr);\n    }',
            '    if (winios_trace_input() && (cnt++ % 30) == 0) {\n        fprintf(stderr, "[winios] post_touch_move x=%d y=%d (n=%u)\\n", x, y, cnt); fflush(stderr);\n    }',
            "touch-move"
        ),
        (
            '    fprintf(stderr, "[winios] post_touch_up x=%d y=%d\\n", x, y); fflush(stderr);',
            '    if (winios_trace_input()) { fprintf(stderr, "[winios] post_touch_up x=%d y=%d\\n", x, y); fflush(stderr); }',
            "touch-up"
        ),
        (
            '    fprintf(stderr, "[winios] post_key vk=0x%x down=%d\\n", vk, down); fflush(stderr);',
            '    if (winios_trace_input()) { fprintf(stderr, "[winios] post_key vk=0x%x down=%d\\n", vk, down); fflush(stderr); }',
            "key"
        )
    ]
    for old, new, label in changes:
        src = replace_one(src, old, new, label)
    old = """    BOOL drained = FALSE;
    for (;;) {
        winios_input_event_t e;
        pthread_mutex_lock(&g_input_q.lock);
        if (g_input_q.tail == g_input_q.head) {
            pthread_mutex_unlock(&g_input_q.lock);
            break;
        }
        e = g_input_q.buf[g_input_q.tail];
        g_input_q.tail = (g_input_q.tail + 1) % WINIOS_RING_SIZE;
        pthread_mutex_unlock(&g_input_q.lock);

        fprintf(stderr, "[winios] drain type=%u x=%d y=%d flags=0x%x\\n", e.type, e.x, e.y, e.flags); fflush(stderr);
        if (e.type == WINIOS_EV_KEY)
            winios_drv_post_key((unsigned short)e.x, e.flags);
        else
            winios_drv_post_mouse(e.x, e.y, e.flags, e.data, NULL);
        drained = TRUE;
    }
    return drained;"""
    new = """    BOOL drained = FALSE;
    for (;;) {
        // Steam Mobile SM-001: bounded FIFO drain under one mutex hold.
        // All key/button/motion events and their order are preserved.
        // Callbacks execute AFTER releasing the mutex, as before.
        winios_input_event_t batch[64];
        unsigned n = 0;
        pthread_mutex_lock(&g_input_q.lock);
        while (n < 64 && g_input_q.tail != g_input_q.head) {
            batch[n++] = g_input_q.buf[g_input_q.tail];
            g_input_q.tail = (g_input_q.tail + 1) % WINIOS_RING_SIZE;
        }
        pthread_mutex_unlock(&g_input_q.lock);
        if (n == 0) break;
        for (unsigned i = 0; i < n; i++) {
            winios_input_event_t e = batch[i];
            if (winios_trace_input()) {
                fprintf(stderr, "[winios] drain type=%u x=%d y=%d flags=0x%x\\n", e.type, e.x, e.y, e.flags);
                fflush(stderr);
            }
            if (e.type == WINIOS_EV_KEY)
                winios_drv_post_key((unsigned short)e.x, e.flags);
            else
                winios_drv_post_mouse(e.x, e.y, e.flags, e.data, NULL);
        }
        drained = TRUE;
    }
    return drained;"""
    return replace_one(src, old, new, "Winios input FIFO batching")


def patch_fex_bridge(src):
    """Reduce synchronous JIT-allocation logs without suppressing failures.

    Allocation success can be frequent during startup and JIT activity. Keep
    exhaustion/errors visible; the existing full trace is opt-in for debugging.
    """
    old = '    fex_log("JIT pool alloc: %zu bytes at RX=%p (offset %zu/%zu)", size, rx_ptr, offset + size, g_jit_pool_size);'
    new = """    // Steam Mobile SM-002: no synchronous os_log + stderr per successful JIT allocation.
    // All allocation failures remain unconditionally logged above.
    // Restore full logs explicitly using STEAM_MOBILE_JIT_TRACE=1.
    static const bool trace_allocations = [] {
        const char *v = getenv("STEAM_MOBILE_JIT_TRACE");
        return v && v[0] == '1' && v[1] == '\\0';
    }();
    if (trace_allocations)
        fex_log("JIT pool alloc: %zu bytes at RX=%p (offset %zu/%zu)", size, rx_ptr, offset + size, g_jit_pool_size);"""
    return replace_one(src, old, new, "FEX success-path allocation log gate")

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--madeira", type=Path, required=True)
    ap.add_argument("--dxmt", type=Path)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    targets = [
        ((args.dxmt or (args.madeira / "dxmt")) / "src/d3d9/d3d9_multithread.hpp", patch_dxmt),
        (args.madeira / "app/Madeira/Winios/Winios.m", patch_winios),
        (args.madeira / "app/Madeira/FEXBridge.mm", patch_fex_bridge)
    ]
    staged = []
    try:
        for path, action in targets:
            if not path.is_file():
                raise PatchError(f"missing source file: {path}")
            original = path.read_bytes()
            modified = action(original.decode("utf-8")).encode("utf-8")
            if modified == original:
                raise PatchError(f"no changes in {path}")
            staged.append((path, original, modified))
        if args.apply:
            for path, old, new in staged:
                backup = Path(str(path) + ".steam-mobile-sm001.bak")
                if backup.exists():
                    raise PatchError(f"backup already exists, refusing overwrite: {backup}")
            for path, old, new in staged:
                Path(str(path) + ".steam-mobile-sm001.bak").write_bytes(old)
                path.write_bytes(new)
        for path, old, new in staged:
            print(f"{'PATCHED' if args.apply else 'READY'} {path}: {hashlib.sha256(old).hexdigest()[:12]} -> {hashlib.sha256(new).hexdigest()[:12]}")
        return 0
    except (PatchError, UnicodeError, OSError) as error:
        print(f"SM-001 ABORT: {error}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    sys.exit(main())
