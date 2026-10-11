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
from inspect_binary import device_executable, windows_dll, windows_exe

MARKER = b"STEAM_MOBILE_NATIVE_ENGINE_SM002"


class InvalidOptimizedIPA(ValueError):
    pass


def validate(path: Path, bundle_id: str = "com.steammobile.engine") -> dict:
    with zipfile.ZipFile(path, "r") as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            raise InvalidOptimizedIPA("Duplicate ZIP members are not permitted")
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
        engine = main
        engine_member = required[1]
        for label, binary, member in (("Main app", main, required[1]), ("JIT helper", jit, required[3])):
            try:
                dependencies = device_executable(binary)
                # Xcode Debug can put the executable's code into a linked dylib.
                # Only follow the exact app/helper dependency, not arbitrary files
                # that happen to contain the marker in an unrelated bundle path.
                debug_name = member.rsplit('/', 1)[-1] + '.debug.dylib'
                if '@rpath/' + debug_name in dependencies:
                    debug_member = member.rsplit('/', 1)[0] + '/' + debug_name
                    if debug_member not in names:
                        raise ValueError("Missing linked Debug code library")
                    code = z.read(debug_member)
                    device_executable(code, dylib=True)
                    if member == required[1]:
                        engine, engine_member = code, debug_member
            except ValueError as error:
                raise InvalidOptimizedIPA(f"{label}: {error}") from error
        if MARKER not in engine:
            raise InvalidOptimizedIPA("Native patch marker missing from executable: stock Madeira or patch not linked")
        dlls = [n for n in names if n.lower().startswith((root + "x86_64-vcruntime/").lower())
                and n.lower().endswith(".dll")]
        if not dlls or any(z.getinfo(name).file_size == 0 for name in dlls):
            raise InvalidOptimizedIPA("Licensed x64 VC runtime DLLs are absent or empty")
        required_crt = {"vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"}
        if not required_crt.issubset({n.rsplit("/", 1)[-1].lower() for n in dlls}):
            raise InvalidOptimizedIPA("Missing required x64 VC runtime DLL set")
        for name in dlls:
            try:
                windows_dll(z.read(name))
            except ValueError as error:
                raise InvalidOptimizedIPA(f"{name}: {error}") from error
        dock_host = root + "arm64ec-windows/dockhost.exe"
        dock_notice = root + "arm64ec-windows/dock-notices.txt"
        if dock_host not in names or dock_notice not in names:
            raise InvalidOptimizedIPA("Native Steam Dock missing: account library/download UI would remain hidden")
        try:
            windows_exe(z.read(dock_host))
        except ValueError as error:
            raise InvalidOptimizedIPA(f"Native Steam Dock: {error}") from error
        if z.getinfo(dock_notice).file_size < 100:
            raise InvalidOptimizedIPA("Missing required Dock redistributable notices")
        fex_dll = root + "arm64ec-windows/xtajit64.dll"
        if fex_dll not in names or z.getinfo(fex_dll).file_size == 0:
            raise InvalidOptimizedIPA("Missing ARM64EC FEX guest translator")
        try:
            # ARM64EC hybrid images can use AMD64 in the PE COFF header.
            windows_dll(z.read(fex_dll), machines=(0x8664, 0xA641, 0xA64E))
        except ValueError as error:
            raise InvalidOptimizedIPA(f"FEX guest translator: {error}") from error
        if any("/_CodeSignature/" in n or n.endswith("embedded.mobileprovision") for n in names):
            raise InvalidOptimizedIPA("Stale signature resources remain: output must be re-signed")
        bad = z.testzip()
        if bad is not None:
            raise InvalidOptimizedIPA(f"Corrupt IPA ZIP member: {bad}")
        return {"bundle_id": bundle_id, "main_bytes": len(main), "engine_member": engine_member,
                "engine_bytes": len(engine),
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
