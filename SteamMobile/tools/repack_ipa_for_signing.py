#!/usr/bin/env python3
"""Fix Steam Mobile IPA identifiers and prepare for re-signing with a valid certificate.

The resulting IPA is UNSIGNED and will not install until a sideloader signs
the app, JIT extension, frameworks and any nested binaries.
"""
import argparse
import copy
import plistlib
import shutil
import zipfile
from pathlib import Path


def repack(inp: Path, out: Path, bundle_id: str, display_name: str) -> None:
    if not bundle_id or "." not in bundle_id:
        raise ValueError("Expected reverse-DNS bundle ID")
    if inp.resolve() == out.resolve():
        raise ValueError("Input and output must differ")
    with zipfile.ZipFile(inp, "r") as source, zipfile.ZipFile(out, "w", allowZip64=True) as target:
        archive = source.namelist()
        roots = sorted({n.split("/")[1] for n in archive if n.startswith("Payload/")
                        and len(n.split("/")) > 2 and n.split("/")[1].endswith(".app")})
        if len(roots) != 1:
            raise ValueError(f"Expected one app; found {roots}")
        root = f"Payload/{roots[0]}/"
        main = root + "Info.plist"
        helper = root + "PlugIns/MadeiraJITHelper.appex/Info.plist"
        if main not in archive or helper not in archive:
            raise ValueError("Missing main or JIT extension Info.plist")
        signatures = 0
        for item in source.infolist():
            name = item.filename
            if "/_CodeSignature/" in name or name.endswith("/_CodeSignature") or name.endswith("embedded.mobileprovision"):
                signatures += 1
                continue
            modified = None
            if name in (main, helper):
                plist = plistlib.loads(source.read(name))
                if name == main:
                    plist["CFBundleIdentifier"] = bundle_id
                    plist["CFBundleDisplayName"] = display_name
                    plist["CFBundleName"] = "SteamMobile"
                    # BackgroundTasks identifiers must match the *signed* app
                    # bundle identifier. Keeping upstream Madeira's prefix
                    # makes pairing's continued-processing task fail after
                    # re-signing under com.steammobile.*, hiding the PIN banner.
                    identifiers = plist.get("BGTaskSchedulerPermittedIdentifiers", [])
                    if not isinstance(identifiers, list):
                        raise ValueError("Invalid BGTaskSchedulerPermittedIdentifiers")
                    needed = ("download.*", "pairing.*")
                    for suffix in needed:
                        if not any(isinstance(v, str) and v.endswith("." + suffix) for v in identifiers):
                            raise ValueError(f"Missing iOS background task identifier: {suffix}")
                    plist["BGTaskSchedulerPermittedIdentifiers"] = [
                        bundle_id + "." + suffix for suffix in needed
                    ]
                    if "_remotepairing-pairable-host._tcp" not in plist.get("NSBonjourServices", []):
                        raise ValueError("iOS pairing Bonjour service is missing")
                    if not plist.get("NSLocalNetworkUsageDescription"):
                        raise ValueError("Local Network permission explanation is missing")
                else:
                    plist["CFBundleIdentifier"] = bundle_id + ".JITHelper"
                modified = plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)
            # zipfile mutates ZipInfo.header_offset when writing; never pass the
            # same ZipInfo object from source to destination.
            with target.open(copy.copy(item), "w") as dst:
                if modified is not None:
                    dst.write(modified)
                else:
                    with source.open(item) as stream:
                        shutil.copyfileobj(stream, dst, length=1024 * 1024)
        print(f"Main bundle {bundle_id}; JIT helper {bundle_id}.JITHelper")
        print(f"Removed {signatures} stale code-signature resource entries")
    with zipfile.ZipFile(out) as result:
        main_id = plistlib.loads(result.read(main))["CFBundleIdentifier"]
        helper_id = plistlib.loads(result.read(helper))["CFBundleIdentifier"]
        assert helper_id == main_id + ".JITHelper"
        parsed = plistlib.loads(result.read(main))
        assert parsed["BGTaskSchedulerPermittedIdentifiers"] == [
            main_id + ".download.*", main_id + ".pairing.*"
        ]
        assert not any("/_CodeSignature/" in n for n in result.namelist())
        assert result.testzip() is None
    print(f"IPA package verified ({out.stat().st_size} bytes); requires iOS signing")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--bundle-id", default="com.steammobile.baseline")
    ap.add_argument("--name", default="Steam Mobile")
    a = ap.parse_args()
    repack(a.input, a.output, a.bundle_id, a.name)
