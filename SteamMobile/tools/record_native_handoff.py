#!/usr/bin/env python3
"""Record a successfully linked CI app awaiting the user's local CRT files."""
import argparse
import hashlib
import json
import os
import shutil
import zipfile
from pathlib import Path
from inspect_binary import device_executable, windows_exe
from verify_optimized_ipa import MARKER


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def record(directory, derived):
    archive = directory / 'native-app.zip'
    binaries = {}
    with zipfile.ZipFile(archive) as source:
        for member in ('Madeira.app/Madeira',
                       'Madeira.app/PlugIns/MadeiraJITHelper.appex/MadeiraJITHelper'):
            data = source.read(member)
            deps = device_executable(data)
            binaries[member] = hashlib.sha256(data).hexdigest()
            debug = member.rsplit('/', 1)[-1] + '.debug.dylib'
            if '@rpath/' + debug in deps:
                member = member.rsplit('/', 1)[0] + '/' + debug
                data = source.read(member)
                device_executable(data, dylib=True)
                binaries[member] = hashlib.sha256(data).hexdigest()
            if member.startswith('Madeira.app/Madeira') and MARKER not in data:
                raise ValueError('Native patch marker missing from linked app')
    # The app's real Steam ownership/depot views are feature-gated on Dock host
    # presence. Without this executable a linked IPA falsely appears successful
    # yet silently hides Steam library and downloads at runtime.
    with zipfile.ZipFile(archive) as source:
        dock = 'Madeira.app/arm64ec-windows/dockhost.exe'
        notices = 'Madeira.app/arm64ec-windows/dock-notices.txt'
        windows_exe(source.read(dock))
        if len(source.read(notices)) < 100:
            raise ValueError('Dock source/license notices missing')
        binaries[dock] = hashlib.sha256(source.read(dock)).hexdigest()
    maps = {}
    for source in derived.rglob('*LinkMap*'):
        if source.is_file():
            relative = Path('link-maps') / source.relative_to(derived)
            dest = directory / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
            maps[relative.as_posix()] = digest(dest)
    if not maps:
        raise ValueError('Xcode link maps missing')
    record = {'schema': 1, 'status': 'linked-app-requires-local-runtime',
              'repository': os.environ['GITHUB_REPOSITORY'],
              'commit': os.environ['GITHUB_SHA'], 'run_id': os.environ['GITHUB_RUN_ID'],
              'app_zip_sha256': digest(archive), 'binaries': binaries, 'link_maps': maps}
    (directory / 'native-handoff.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('directory', type=Path)
    ap.add_argument('derived', type=Path)
    args = ap.parse_args()
    record(args.directory, args.derived)
