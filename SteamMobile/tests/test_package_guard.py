#!/usr/bin/env python3
"""Host regression tests for the optimized IPA safety gate (synthetic fixtures)."""
import plistlib
import tempfile
import zipfile
import struct
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify_optimized_ipa import InvalidOptimizedIPA, MARKER, validate

ROOT = "Payload/Madeira.app/"


def macho(*, platform=2, dylib=False, dependency=None):
    # Structural test data only; never an app or an input to the release workflow.
    data = bytearray(8192)
    struct.pack_into('<8I', data, 0, 0xFEEDFACF, 0x0100000C, 0, 2, 3, 200, 0, 0)
    struct.pack_into('<II16sQQQQIIII', data, 32, 0x19, 152, b'__TEXT',
                     0x100000000, 8192, 0, 8192, 5, 5, 1, 0)
    struct.pack_into('<16s16sQQ8I', data, 104, b'__text', b'__TEXT',
                     0x100001000, 128, 4096, 2, 0, 0, 0x80000400, 0, 0, 0)
    struct.pack_into('<6I', data, 184, 0x32, 24, platform, 0x110000, 0x1B0000, 0)
    struct.pack_into('<IIQQ', data, 208, 0x80000028, 24, 4096, 0)
    count, end = (2, 208) if dylib else (3, 232)
    if dependency:
        name = dependency.encode() + b'\0'
        size = (24 + len(name) + 7) // 8 * 8
        struct.pack_into('<6I', data, end, 0xC, size, 24, 0, 0, 0)
        data[end + 24:end + 24 + len(name)] = name
        count, end = count + 1, end + size
    struct.pack_into('<8I', data, 0, 0xFEEDFACF, 0x0100000C, 0, 6 if dylib else 2, count, end - 32, 0, 0)
    return bytes(data)


def pe_dll(*, machine=0x8664):
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', data, 132, machine, 1, 0, 0, 0, 240, 0x2022)
    struct.pack_into('<H', data, 152, 0x20B)
    struct.pack_into('<8s6I2HI', data, 392, b'.text', 512, 4096, 512, 512, 0, 0, 0, 0, 0x60000020)
    return bytes(data)


def fixture(path, *, marker=True, crt=True, helper=True, fex=True, pairing=True,
            platform=2, crt_machine=0x8664, placeholder_crt=False, placeholder_main=False,
            debug=False, debug_missing=False, unlinked_marker=False):
    main = (b'\xcf\xfa\xed\xfe' + b'A' * 8192 if placeholder_main else
            macho(platform=platform, dependency='@rpath/Madeira.debug.dylib' if debug else None))
    main += MARKER if marker and not debug and not unlinked_marker else b''
    jit = macho()
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(ROOT + "Info.plist", plistlib.dumps({
            "CFBundleIdentifier": "com.steammobile.engine",
            "BGTaskSchedulerPermittedIdentifiers": (
                ["com.steammobile.engine.download.*", "com.steammobile.engine.pairing.*"]
                if pairing else ["com.original.madeira.pairing.*"]
            ),
            "NSBonjourServices": ["_remotepairing-pairable-host._tcp"],
            "NSLocalNetworkUsageDescription": "On-device pairing",
        }))
        z.writestr(ROOT + "Madeira", main)
        if (debug and not debug_missing) or unlinked_marker:
            z.writestr(ROOT + 'Madeira.debug.dylib', macho(dylib=True) + (MARKER if marker else b''))
        z.writestr(ROOT + "PlugIns/MadeiraJITHelper.appex/Info.plist",
                   plistlib.dumps({"CFBundleIdentifier": "com.steammobile.engine.JITHelper"}))
        if helper:
            z.writestr(ROOT + "PlugIns/MadeiraJITHelper.appex/MadeiraJITHelper", jit)
        if crt:
            for dll in ('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll'):
                z.writestr(ROOT + "x86_64-vcruntime/" + dll,
                           b'placeholder' if placeholder_crt else pe_dll(machine=crt_machine))
        if fex:
            z.writestr(ROOT + "arm64ec-windows/xtajit64.dll", pe_dll())


with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "test.ipa"
    fixture(p)
    assert validate(p)["crt_dll_count"] == 3
    fixture(p, debug=True)
    assert validate(p)['engine_member'] == ROOT + 'Madeira.debug.dylib'
    for label, flags in [
        ("unpatched engine", {"marker": False}),
        ("missing licensed CRT", {"crt": False}),
        ("missing JIT helper", {"helper": False}),
        ("missing FEX translator", {"fex": False}),
        ("mismatched pairing background IDs", {"pairing": False}),
        ("macOS executable", {"platform": 1}),
        ("iOS simulator executable", {"platform": 7}),
        ("wrong-architecture CRT", {"crt_machine": 0xAA64}),
        ("nonempty dummy CRT", {"placeholder_crt": True}),
        ("dummy Mach-O with copied marker", {"placeholder_main": True}),
        ("missing linked Debug library", {"debug": True, "debug_missing": True}),
        ("marker in an unlinked library", {"unlinked_marker": True}),
        ("stock Debug library", {"debug": True, "marker": False}),
    ]:
        fixture(p, **flags)
        try:
            validate(p)
        except InvalidOptimizedIPA:
            pass
        else:
            raise AssertionError(f"Safety gate accepted {label}")
print("Optimized IPA structural acceptance/rejection regression PASS")
