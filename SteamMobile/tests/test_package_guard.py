#!/usr/bin/env python3
"""Host regression tests for the optimized IPA safety gate (synthetic fixtures)."""
import plistlib
import tempfile
import zipfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify_optimized_ipa import InvalidOptimizedIPA, MARKER, validate

ROOT = "Payload/Madeira.app/"


def fixture(path, *, marker=True, crt=True, helper=True, fex=True, pairing=True):
    main = b"\xcf\xfa\xed\xfe" + (b"A" * 8192) + (MARKER if marker else b"")
    jit = b"\xcf\xfa\xed\xfe" + b"B" * 8192
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
        z.writestr(ROOT + "PlugIns/MadeiraJITHelper.appex/Info.plist",
                   plistlib.dumps({"CFBundleIdentifier": "com.steammobile.engine.JITHelper"}))
        if helper:
            z.writestr(ROOT + "PlugIns/MadeiraJITHelper.appex/MadeiraJITHelper", jit)
        if crt:
            z.writestr(ROOT + "x86_64-vcruntime/vcruntime140.dll", b"valid-nonempty-placeholder-for-structural-test")
        if fex:
            z.writestr(ROOT + "arm64ec-windows/xtajit64.dll", b"valid-nonempty-placeholder-for-structural-test")


with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "test.ipa"
    fixture(p)
    assert validate(p)["crt_dll_count"] == 1
    for label, flags in [
        ("unpatched engine", {"marker": False}),
        ("missing licensed CRT", {"crt": False}),
        ("missing JIT helper", {"helper": False}),
        ("missing FEX translator", {"fex": False}),
        ("mismatched pairing background IDs", {"pairing": False}),
    ]:
        fixture(p, **flags)
        try:
            validate(p)
        except InvalidOptimizedIPA:
            pass
        else:
            raise AssertionError(f"Safety gate accepted {label}")
print("Optimized IPA structural acceptance/rejection regression PASS")
