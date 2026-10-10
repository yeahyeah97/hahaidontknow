#!/usr/bin/env python3
"""Repair incremental-only upstream build recipes in the disposable source tree.

No engine behavior changes here. Retain upstream iOS replacements and symbol
renames; compile the remaining Wine server sources instead of using a base .a.
"""
import argparse
import re
from pathlib import Path


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected exactly one build anchor: {old[:90]!r}")
    return text.replace(old, new, 1)


def server_sources(makefile):
    if makefile.count("SOURCES =") != 1:
        raise ValueError("Wine server source list missing or ambiguous")
    block = makefile.split("SOURCES =", 1)[1].split("\n\n", 1)[0]
    names = re.findall(r"\b([a-z0-9_]+)\.c\b", block)
    if not names or len(names) != len(set(names)):
        raise ValueError("Invalid Wine server source list")
    return names


def patch_server(script, makefile):
    if script.count("PATCHED_FILES=(") != 1:
        raise ValueError("Wine server override list missing or ambiguous")
    start = script.index("# Copy the base library")
    end = script.index("CC_FLAGS=(", start)
    script = script[:start] + script[end:]
    entries = re.findall(r'^    "([^"\n]+:[^"\n]+:[^"\n]+)"',
                         script.split("PATCHED_FILES=(", 1)[1].split("\n)", 1)[0], re.M)
    if not entries:
        raise ValueError("No upstream server overrides found")
    replaced = {e.rsplit(":", 1)[1].removesuffix(".o") for e in entries}
    remaining = [s for s in server_sources(makefile) if s not in replaced]
    objects = remaining + [e.split(":", 1)[0] for e in entries] + ["wineserver_ios_kill"]
    if len(objects) != len(set(objects)):
        raise ValueError("Duplicate server object names")
    script = once(script, 'case "${1:-all}" in',
                  '# Steam Mobile: a complete source build; partial updates are forbidden.\n'
                  '[ "${1:-all}" = all ] || { echo "Clean build requires all" >&2; exit 1; }\n'
                  'case "${1:-all}" in')
    script = once(script, '        echo "=== Building all patched wineserver files ==="',
                  '        # Build every unmodified module listed by Wine, with the same iOS flags.\n'
                  '        for name in ' + " ".join(remaining) + '; do\n'
                  '            compile_one "$WINE_SRC/server/$name.c" "$name"\n'
                  '        done\n'
                  '        echo "=== Building all patched wineserver files ==="')
    start = script.index('# Map of patched .o files')
    end = script.index('echo "=== Renaming colliding symbols', start)
    fresh = ('# Fresh archive from this build only; no inherited or stale objects.\n'
             'rm -f "$OBJ_DIR/libwineserver.a"\n'
             'xcrun --sdk iphoneos ar rcs "$OBJ_DIR/libwineserver.a" \\\n' +
             ' \\\n'.join(f'    "$OBJ_DIR/{o}.o"' for o in objects) + '\n\n')
    script = script[:start] + fresh + script[end:]
    return script, objects


def patch_dxmt(script):
    # DXMT Meson generates three embedded Metal AIR headers before compiling
    # airconv_context.cpp. The upstream hand-written iOS script didn't copy
    # that generator edge; without it the first unit fails on air_msad.h.
    shader_step = r'''echo "=== Steam Mobile: generate embedded airconv Metal shader headers ==="
# These AIR blobs are linked as LLVM modules by airconv_context.cpp.
# Follow dxmt/src/airconv/meson.build: metal3.1 + macOS14 AIR target,
# then the Meson hexdump_generator: xxd -n <basename> -i <air> <header>.
mkdir -p "$BUILD_DIR/shader-headers"
for name in air_msad air_samplepos air_tessellation; do
    src="$DXMT_SRC/airconv/shaders/$name.metal"
    air="$BUILD_DIR/shader-headers/$name.air"
    hdr="$BUILD_DIR/shader-headers/$name.h"
    test -s "$src"
    xcrun -sdk macosx metal -std=metal3.1 --target=air64-apple-macos14.0 -o "$air" -c "$src"
    test -s "$air"
    xxd -n "$name" -i "$air" "$hdr"
    test -s "$hdr"
    grep -Fq "unsigned char $name[]" "$hdr" || {
        echo "Malformed DXMT AIR header $hdr" >&2; exit 1;
    }
    echo "  $name.h generated ($(wc -c < "$air" | tr -d ' ') AIR bytes)"
done

echo "=== airconv (C++ 20, needs LLVM headers) ==="'''
    script = once(script, 'echo "=== airconv (C++ 20, needs LLVM headers) ==="', shader_step)
    # Print the actual failed object's stderr in Actions; the old DXMT
    # script reported only its object name and buried the error in artifacts.
    script = once(
        script,
        '    echo "See .err files in $OBJ_DIR/"',
        '''    echo "See .err files in $OBJ_DIR/"
    for failed_object in $FAILED_FILES; do
        if [ -s "$OBJ_DIR/$failed_object.err" ]; then
            echo "==== $failed_object compiler diagnostics ===="
            sed -n '1,100p' "$OBJ_DIR/$failed_object.err"
        fi
    done''',
    )
    start = script.index('# The app links libdxmt_combined.a')
    return script[:start] + '''# Steam Mobile: create the combined archive on a clean checkout as documented
# in upstream build/dxmt-ios/README.md. Do not refresh a pre-existing binary.
COMBINED="$BUILD_DIR/libdxmt_combined.a"
test -s "$LLVM_BUILD/lib/libLLVMCore.a"
test -s "$LLVM_BUILD/lib/libLLVMSupport.a"
xcrun --sdk iphoneos libtool -static -o "$COMBINED.tmp" \\
    "$OUT_LIB" "$LLVM_BUILD"/lib/libLLVM*.a
mv "$COMBINED.tmp" "$COMBINED"
cp "$COMBINED" "$REPO_ROOT/app/Madeira/libdxmt_combined.a"
'''

def prepare(root):
    pending = {}
    path = root / "build/wineserver/build.sh"
    pending[path], objects = patch_server(path.read_text(encoding="utf-8"), (root / "wine/server/Makefile.in").read_text(encoding="utf-8"))
    # ntdll used to continue to archiving after compile errors, potentially
    # picking up an old object on incremental builds.
    path = root / "build/ntdll-unix/build.sh"
    pending[path] = once(path.read_text(encoding="utf-8"),
        '    echo "Failed:$FAILED_FILES"\nfi',
        '    echo "Failed:$FAILED_FILES"\n    exit 1\nfi')
    # This header is generated in the configured host tree too; an unrelated
    # ARM64EC configured tree is not needed to compile native dwrite.
    pending[path] = once(pending[path], '-I"$REPO_ROOT/wine/build-arm64ec/include"',
                         '-I"$WINE_BUILD/include"')
    path = root / "toolchains/llvm-project/llvm/cmake/modules/AddLLVM.cmake"
    text = path.read_text(encoding="utf-8")
    if 'MATCHES "Darwin"' not in text:
        raise ValueError("LLVM Darwin platform rule absent")
    pending[path] = text.replace('MATCHES "Darwin"', 'MATCHES "Darwin|iOS"')
    path = root / "build/dxmt-ios/build.sh"
    text = path.read_text(encoding="utf-8")
    pending[path] = patch_dxmt(text)
    # Xcode 27 changed the internal Metal atomic builtin signature (4 -> 5
    # arguments). The source-pinned shader is older than that implementation.
    # Use the supported Metal C++ atomic API instead of private builtins.
    # Preserve threadgroup memory scope and relaxed ordering.
    path = root / "dxmt/src/airconv/shaders/air_tessellation.metal"
    source = path.read_text(encoding="utf-8")
    pending[path] = once(
        source,
        'return __metal_atomic_fetch_add_explicit(out_count, 1, int(memory_order_relaxed), __METAL_MEMORY_SCOPE_THREADGROUP__);',
        'return atomic_fetch_add_explicit((threadgroup atomic_int *)out_count, 1, memory_order_relaxed);',
    )
    # Validate all anchors before modifying any source.
    for path, text in pending.items():
        path.write_text(text, encoding="utf-8", newline="\n")
    print(f"Prepared clean Wine server build: {len(objects)} source objects")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", type=Path)
    prepare(ap.parse_args().root)
