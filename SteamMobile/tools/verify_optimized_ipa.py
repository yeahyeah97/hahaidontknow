#!/usr/bin/env python3
"""Fail-closed validation of a *compiled and patched* Steam Mobile IPA.

This is not a signing tool, Wine compatibility test, or FPS benchmark.
It rejects stock Madeira repackaging and obviously incomplete iOS bundles.
"""
import argparse
import plistlib
import sys
import zipfile
from pathlib import Path

MARKER = b"STEAM_MOBILE_NATIVE_ENGINE_SM002"
MACHO_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")


class InvalidOptimizedIPA(ValueError):
    pass


def validate(path: Path, bundle_id: str = "com.steammobile.engine") -> dict:
    with zipfile.ZipFile(path, "r") as z:
        names = z.namelist()
        roots = {x.split("/")[1] for x in names if x.startswith("Payload/")
                 and len(x.split("/")) >= 3 and x.split("/")[1].endswith(".app")}
        if len(roots) != 1:
            raise InvalidOptimizedIPA(f"Expected exactly one iOS app bundle, found {sorted(roots)}")
        root = f"Payload/{next(iter(roots))}/"
        required = (
            root + "Info.plist",
            root + "Madeira",
            root + "PlugIns/MadeiraJITHelper.appex/Info.plist",
            root + "PlugIns/MadeiraJITHelper.appex/MadeiraJITHelper",
        )
        for name in required:
            if name not in names:
                raise InvalidOptimizedIPA(f"Missing required bundle member: {name}")
        metadata = plistlib.loads(z.read(required[0]))
        helper = plistlib.loads(z.read(required[2]))
        if metadata.get("CFBundleIdentifier") != bundle_id:
            raise InvalidOptimizedIPA("Main app bundle identifier does not match optimized engine ID")
        if helper.get("CFBundleIdentifier") != bundle_id + ".JITHelper":
            raise InvalidOptimizedIPA("JIT extension bundle identifier mismatch")
        # A renamed IPA without these runtime-matched background identifiers
        # can install and run yet cannot display the on-device pairing-code
        # continued task. Treat that as incomplete, not release ready.
        if metadata.get("BGTaskSchedulerPermittedIdentifiers") != [
            bundle_id + ".download.*", bundle_id + ".pairing.*"
        ]:
            raise InvalidOptimizedIPA("Pairing/download background IDs do not match signed app ID")
        if "_remotepairing-pairable-host._tcp" not in metadata.get("NSBonjourServices", []):
            raise InvalidOptimizedIPA("Pairing Bonjour service missing")
        if not metadata.get("NSLocalNetworkUsageDescription"):
            raise InvalidOptimizedIPA("Local Network usage declaration missing")
        main = z.read(required[1])
        jit = z.read(required[3])
        if len(main) < 4096 or main[:4] not in MACHO_MAGIC:
            raise InvalidOptimizedIPA("Main binary is missing or not a nontrivial Mach-O")
        if len(jit) < 4096 or jit[:4] not in MACHO_MAGIC:
            raise InvalidOptimizedIPA("JIT helper binary is missing or not a nontrivial Mach-O")
        if MARKER not in main:
            raise InvalidOptimizedIPA("Native patch marker missing from executable: stock Madeira or patch not linked")
        dlls = [n for n in names if n.lower().startswith((root + "x86_64-vcruntime/").lower())
                and n.lower().endswith(".dll")]
        if not dlls or any(z.getinfo(name).file_size == 0 for name in dlls):
            raise InvalidOptimizedIPA("Licensed x64 VC runtime DLLs are absent or empty")
        fex_dll = root + "arm64ec-windows/xtajit64.dll"
        if fex_dll not in names or z.getinfo(fex_dll).file_size == 0:
            raise InvalidOptimizedIPA("Missing ARM64EC FEX guest translator")
        if any("/_CodeSignature/" in n or n.endswith("embedded.mobileprovision") for n in names):
            raise InvalidOptimizedIPA("Stale signature resources remain: output must be re-signed")
        bad = z.testzip()
        if bad is not None:
            raise InvalidOptimizedIPA(f"Corrupt IPA ZIP member: {bad}")
        return {"bundle_id": bundle_id, "main_bytes": len(main),
                "jit_bytes": len(jit), "crt_dll_count": len(dlls)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--bundle-id", default="com.steammobile.engine")
    args = parser.parse_args()
    try:
        info = validate(args.ipa, args.bundle_id)
    except (InvalidOptimizedIPA, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"NOT AN OPTIMIZED IPA: {error}", file=sys.stderr)
        sys.exit(2)
    print("Optimized IPA bundle integrity and native patch marker PASS:", info)
    print("NOTE: signing, JIT access, game runtime and FPS remain device tests.")
