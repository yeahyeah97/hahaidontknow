#!/usr/bin/env python3
"""Regression: sideload rebranding must preserve working iOS JIT pairing IDs."""
import plistlib
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from repack_ipa_for_signing import repack

APP = "Payload/Madeira.app/"
BEFORE = "com.willfaust.madeira"
AFTER = "com.steammobile.engine"


def make_input(path, *, pairing=True):
    with zipfile.ZipFile(path, "w") as z:
        info = {
            "CFBundleIdentifier": BEFORE,
            "BGTaskSchedulerPermittedIdentifiers": (
                [BEFORE + ".download.*", BEFORE + ".pairing.*"] if pairing else
                [BEFORE + ".download.*"]
            ),
            "NSBonjourServices": ["_remotepairing-pairable-host._tcp"],
            "NSLocalNetworkUsageDescription": "Local pairing requires network access.",
        }
        z.writestr(APP + "Info.plist", plistlib.dumps(info))
        z.writestr(APP + "PlugIns/MadeiraJITHelper.appex/Info.plist",
                   plistlib.dumps({"CFBundleIdentifier": BEFORE + ".JITHelper"}))
        z.writestr(APP + "Madeira", b"test binary")

with tempfile.TemporaryDirectory() as tmp:
    original = Path(tmp) / "original.ipa"
    result = Path(tmp) / "renamed.ipa"
    make_input(original)
    repack(original, result, AFTER, "Steam Mobile")
    with zipfile.ZipFile(result) as z:
        main = plistlib.loads(z.read(APP + "Info.plist"))
        helper = plistlib.loads(z.read(APP + "PlugIns/MadeiraJITHelper.appex/Info.plist"))
        assert main["CFBundleIdentifier"] == AFTER
        assert helper["CFBundleIdentifier"] == AFTER + ".JITHelper"
        assert main["BGTaskSchedulerPermittedIdentifiers"] == [
            AFTER + ".download.*", AFTER + ".pairing.*"
        ]
        assert main["NSBonjourServices"] == ["_remotepairing-pairable-host._tcp"]
    make_input(original, pairing=False)
    try:
        repack(original, result, AFTER, "Steam Mobile")
    except ValueError as exc:
        assert "pairing.*" in str(exc)
    else:
        raise AssertionError("Repacker accepted an IPA with missing pairing task identifier")
print("JIT pairing IPA rebranding and fail-closed checks PASS")
