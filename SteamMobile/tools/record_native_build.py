#!/usr/bin/env python3
"""Record source revisions, applied diffs, actual toolchains and library hashes.

This manifest reports build inputs. Only a successful final app link and IPA
verification can establish that these inputs reached a package.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    return {"exit_code": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def record(root, output):
    lockpath = Path(__file__).resolve().parents[1] / "dependencies.lock.json"
    lock = json.loads(lockpath.read_text())
    sources = {}
    for name, entry in lock["repositories"].items():
        directory = root / entry["path"]
        actual = command("git", "-C", str(directory), "rev-parse", "HEAD")
        diff = subprocess.run(["git", "-C", str(directory), "diff", "--binary", "HEAD"], capture_output=True, check=True).stdout
        if actual["stdout"] != entry["commit"]:
            raise ValueError(f"Source revision mismatch: {name}")
        sources[name] = {**entry, "actual_commit": actual["stdout"], "patch_sha256": hashlib.sha256(diff).hexdigest()}
        (output.parent / f"{name}-applied.patch").write_bytes(diff)
    files = {}
    for pattern in ("app/Madeira/*.a", "FEX/build-ios/**/*.a", "app/Madeira/*-windows/*.dll",
                    "app/Madeira/d3d12/*.dylib", "build/rppairing-ios/Cargo.lock"):
        for path in sorted(root.glob(pattern)):
            files[path.relative_to(root).as_posix()] = {"bytes": path.stat().st_size, "sha256": sha(path)}
    manifest = {"schema": 1, "status": "build-inputs-only", "lock_sha256": sha(lockpath),
                "sources": sources, "files": files,
                "tools": {name: command(*args) for name, args in {
                    "xcode": ("xcodebuild", "-version"), "clang": ("xcrun", "clang", "--version"),
                    "rust": ("rustc", "--version", "--verbose"), "cmake": ("cmake", "--version"),
                    "sdk": ("xcrun", "--sdk", "iphoneos", "--show-sdk-version")}.items()}}
    output.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    record(args.root, args.output)
