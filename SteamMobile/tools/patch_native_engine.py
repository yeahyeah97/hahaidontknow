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

    src = replace_one(src, old, new, "DXMT D3D9 recursive fast path")
    # Experimental bounded spin policy. Never change third-party DXMT builds.
    # Default retains the original 2000-pause behavior. Opting in to a
    # shorter spin helps test whether DX9 lock contention burns scarce
    # mobile CPU time, with a way to return to stock behavior.
    old = """    if (try_lock())
      return;
    uint32_t rounds = 0;"""
    new = """    if (try_lock())
      return;
#ifdef DXMT_MADEIRA
    // Steam Mobile SM-002: optional low-spin setting for contended DX9 calls.
    // Defaults to original behavior; does not affect uncontended calls.
    static const uint32_t pause_budget =
        env::getEnvVar("STEAM_MOBILE_D9_LOW_SPIN") == "1" ? 128u : 2000u;
#else
    constexpr uint32_t pause_budget = 2000u;
#endif
    uint32_t rounds = 0;"""
    src = replace_one(src, old, new, "DXMT opt-in contention spin budget")
    return replace_one(src, "for (uint32_t i = 0; i < 2000; i++) {",
                       "for (uint32_t i = 0; i < pause_budget; i++) {",
                       "DXMT adjustable contention spin loop")

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
    src = replace_one(src, old, new, "FEX success-path allocation log gate")
    # This marker is emitted by the patched FEX bridge's JIT initialization.
    # It remains in the final Mach-O, allowing packaging checks to reject an
    # unmodified Madeira release masquerading as an optimized engine.
    return replace_one(
        src,
        'fex_log("JIT pool initialized: RX=',
        'fex_log("[STEAM_MOBILE_NATIVE_ENGINE_SM002] JIT pool initialized: RX=',
        "FEX native build provenance marker",
    )


def patch_jit_pairing(src):
    """Register iOS background pairing before launch finishes, not on user tap."""
    old = """    private init() {}

    private func log(_ line: String) { LogStore.shared.log("[jit-pairing] " + line) }"""
    new = """    private init() {}

    // Steam Mobile JIT-001: BGTaskScheduler handlers must be registered
    // during app launch. Doing this when the user taps Start Pairing is too
    // late on iOS and can make the pairing-code background banner vanish.
    func registerContinuedProcessingAtLaunch() {
        if #available(iOS 26.0, *) { registerContinuedProcessing() }
    }

    private func log(_ line: String) { LogStore.shared.log("[jit-pairing] " + line) }"""
    src = replace_one(src, old, new, "JIT initial background task registration hook")

    old = """        guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
            advertisingFailed(error)
            return false
        }
        DNSServiceSetDispatchQueue(ref, .main)
        registration = ref
        return true"""
    new = """        guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
            advertisingFailed(error)
            return false
        }
        // Steam Mobile JIT-001: an unhandled failed dispatch-queue binding
        // previously looked just like successful Bonjour registration.
        let dispatchError = DNSServiceSetDispatchQueue(ref, .main)
        guard dispatchError == DNSServiceErrorType(kDNSServiceErr_NoError) else {
            DNSServiceRefDeallocate(ref)
            advertisingFailed(dispatchError)
            return false
        }
        registration = ref
        log("Bonjour pairing advertisement registered")
        return true"""
    src = replace_one(src, old, new, "JIT Bonjour registration error handling")

    old = """    @available(iOS 26.0, *)
    private func submitContinued() {
        guard let identifier = taskIdentifier else { backgroundLimited = true; return }
        if registered != identifier {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                MainActor.assumeIsolated { OnDevicePairing.shared.attach(task) }
            }
            guard ok else { log("register refused"); backgroundLimited = true; return }
            registered = identifier
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Pairing with Madeira",
                                                       subtitle: "Settings › Privacy & Security › Developer Mode")"""
    new = """    @available(iOS 26.0, *)
    private func registerContinuedProcessing() {
        guard let identifier = taskIdentifier else {
            log("background pairing ID missing from signed app Info.plist")
            backgroundLimited = true
            return
        }
        // The permitted identifier must use the actual post-signing bundle ID.
        guard let bundleID = Bundle.main.bundleIdentifier,
              identifier == bundleID + ".pairing.session" else {
            log("background pairing ID does not match signed bundle identifier")
            backgroundLimited = true
            return
        }
        if registered == identifier { return }
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            MainActor.assumeIsolated { OnDevicePairing.shared.attach(task) }
        }
        guard ok else {
            log("background pairing handler registration refused during app launch")
            backgroundLimited = true
            return
        }
        registered = identifier
        log("background pairing handler registered at launch")
    }

    @available(iOS 26.0, *)
    private func submitContinued() {
        guard let identifier = taskIdentifier, registered == identifier else {
            log("cannot start background PIN banner: pairing handler not registered at launch")
            backgroundLimited = true
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Pairing with Madeira",
                                                       subtitle: "Settings › Privacy & Security › Developer Mode")"""
    src = replace_one(src, old, new, "JIT early-registration vs background request split")

    old = """                if pairing.backgroundLimited {
                    Text("This installation can only wait about 30 seconds in the background, so go to Settings straight away.")
                        .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                cancel"""
    new = """                if pairing.backgroundLimited {
                    Text("iOS denied the continued pairing task, so the top code banner may not appear. The app may stop in the background after about 30 seconds. Check that the IPA's bundle/task identifiers match or import a pairing file.")
                        .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("If Pair with Madeira is absent: allow Local Network for Steam Mobile in Settings, keep Wi-Fi enabled, restart pairing, and return here if the system never shows a code.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                cancel"""
    return replace_one(src, old, new, "JIT pairing troubleshooting on UI")


def patch_app_jit_registration(src):
    old = """        _ = ResolutionChoices.screen
    }"""
    new = """        _ = ResolutionChoices.screen
        // Steam Mobile JIT-001: register iOS pairing's background handler
        // at application launch, before scenes appear, not on a later tap.
        MainActor.assumeIsolated {
            OnDevicePairing.shared.registerContinuedProcessingAtLaunch()
        }
    }"""
    return replace_one(src, old, new, "JIT pairing app launch registration")


def patch_fps_overlay(src):
    """Keep 100 ms present samples but avoid 10 Hz SwiftUI State invalidations."""
    old = """struct FPSOverlay: View {"""
    new = """// Steam Mobile PERF-003: a stable reference store prevents the 100 ms
// sampling timer from marking the entire overlay's SwiftUI view as dirty.
// The visible present count / FPS still refresh every 250 ms.
private final class SteamMobileFpsSampleStore {
    var samples: [(t: CFAbsoluteTime, c: UInt64)] = []
}

struct FPSOverlay: View {"""
    src = replace_one(src, old, new, "FPS overlay private reference sample store")
    src = replace_one(
        src,
        '    @State private var samples: [(t: CFAbsoluteTime, c: UInt64)] = []',
        '    @State private var sampleStore = SteamMobileFpsSampleStore()',
        "FPS overlay samples non-observable",
    )
    src = replace_one(src, '        samples = [(now, c)]',
                      '        sampleStore.samples = [(now, c)]', "FPS overlay reset")
    old = """            samples.append((t, cur))
            if samples.count > bufferCapacity { samples.removeFirst() }
            presentCount = cur"""
    new = """            sampleStore.samples.append((t, cur))
            if sampleStore.samples.count > bufferCapacity { sampleStore.samples.removeFirst() }
            // No @State publication here: avoid waking the SwiftUI view at 10 Hz."""
    src = replace_one(src, old, new, "FPS 100 ms buffer without UI publish")
    src = replace_one(src,
        """        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            fps = computeAdaptiveFPS()""",
        """        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            presentCount = madeira_get_present_count()
            fps = computeAdaptiveFPS()""",
        "FPS visible present display tick")
    src = replace_one(src,
        """    private func computeAdaptiveFPS() -> Double {
        guard samples.count >= 2 else { return 0 }""",
        """    private func computeAdaptiveFPS() -> Double {
        let samples = sampleStore.samples
        guard samples.count >= 2 else { return 0 }""",
        "FPS adaptive window preserved")
    return src

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
        (args.madeira / "app/Madeira/FEXBridge.mm", patch_fex_bridge),
        (args.madeira / "app/Madeira/JITPairing.swift", patch_jit_pairing),
        (args.madeira / "app/Madeira/MadeiraApp.swift", patch_app_jit_registration),
        (args.madeira / "app/Madeira/FPSOverlay.swift", patch_fps_overlay)
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
