#!/usr/bin/env python3
"""Fetch exact reviewed source commits into a fresh CI directory."""
import argparse
import json
import subprocess
from pathlib import Path


def run(*args):
    subprocess.run(args, check=True)


def fetch(root, lock):
    for name, source in lock["repositories"].items():
        dest = root / source["path"]
        if (dest / ".git").exists():
            raise ValueError(f"Refusing to overwrite existing checkout: {dest}")
        if dest.exists() and any(dest.iterdir()):
            raise ValueError(f"Source destination is not empty: {dest}")
        dest.mkdir(parents=True, exist_ok=True)
        run("git", "init", "--quiet", str(dest))
        run("git", "-C", str(dest), "remote", "add", "origin", source["url"])
        run("git", "-C", str(dest), "fetch", "--quiet", "--depth=1", "origin", source["commit"])
        run("git", "-C", str(dest), "checkout", "--quiet", "--detach", "FETCH_HEAD")
        actual = subprocess.check_output(["git", "-C", str(dest), "rev-parse", "HEAD"], text=True).strip()
        if actual != source["commit"]:
            raise ValueError(f"{name}: fetched {actual}, expected {source['commit']}")
        print(f"VERIFIED {name} {actual}", flush=True)
    for name in ("wine", "dxmt", "fex"):
        entry = lock["repositories"][name]
        recorded = subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD:" + entry["path"]], text=True).strip()
        if recorded != entry["commit"]:
            raise ValueError(f"{name}: dependency does not match Madeira's gitlink")
    run("git", "-C", str(root / "FEX"), "submodule", "update", "--init", "--depth=1",
        "External/vixl", "External/fmt", "External/xxhash", "External/range-v3", "External/unordered_dense")
    run("git", "-C", str(root / "dxmt"), "submodule", "update", "--init", "--recursive", "--depth=1")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", type=Path)
    args = ap.parse_args()
    lock = json.loads((Path(__file__).resolve().parents[1] / "dependencies.lock.json").read_text())
    fetch(args.root.resolve(), lock)
