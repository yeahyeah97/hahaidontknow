#!/usr/bin/env python3
"""Add hash-pinned user CRT files to a real CI app and verify the unsigned IPA."""
import argparse
import copy
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path
from inspect_binary import windows_dll
from record_native_handoff import digest
from repack_ipa_for_signing import repack
from verify_optimized_ipa import validate


def assemble(handoff, runtime, output, expected_commit):
    evidence = json.loads((handoff / 'native-handoff.json').read_text())
    if (evidence.get('status') != 'linked-app-requires-local-runtime' or
            evidence.get('repository') != 'yeahyeah97/hahaidontknow' or
            evidence.get('commit') != expected_commit):
        raise ValueError('Unexpected native build provenance')
    archive = handoff / 'native-app.zip'
    if digest(archive) != evidence['app_zip_sha256']:
        raise ValueError('Native app artifact hash mismatch')
    lock = json.loads((Path(__file__).resolve().parents[1] / 'runtime-inputs.lock.json').read_text())
    dlls = {}
    for name, entry in lock['dlls'].items():
        if Path(name).name != name or not name.endswith('.dll'):
            raise ValueError('Invalid runtime lock entry')
        data = (runtime / name).read_bytes()
        windows_dll(data)
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError(f'Runtime hash mismatch: {name}')
        dlls[name] = data
    if output.exists():
        raise ValueError('Output exists; choose a new name')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='steam-mobile-', dir=output.parent) as temp:
        staging = Path(temp) / 'with-runtime.zip'
        final = Path(temp) / 'verified.ipa'
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(staging, 'w') as dest:
            names = source.namelist()
            if len(names) != len(set(names)):
                raise ValueError('Duplicate app ZIP members')
            for item in source.infolist():
                if (not item.filename.startswith('Madeira.app/') or
                        '..' in item.filename.split('/') or '\\' in item.filename):
                    raise ValueError('Unexpected app ZIP member')
                if item.filename.startswith('Madeira.app/x86_64-vcruntime/'):
                    if not item.is_dir():
                        raise ValueError('CI app unexpectedly contains CRT files')
                    continue
                target = copy.copy(item)
                target.filename = 'Payload/' + item.filename
                with source.open(item) as src, dest.open(target, 'w') as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)
            for name, data in dlls.items():
                info = zipfile.ZipInfo('Payload/Madeira.app/x86_64-vcruntime/' + name)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                dest.writestr(info, data)
        repack(staging, final, 'com.steammobile.engine', 'Steam Mobile')
        result = validate(final)
        manifest = {'schema': 1, 'status': 'unsigned-device-tests-pending',
                    'native_build': evidence, 'crt': lock, 'validation': result,
                    'ipa_sha256': digest(final)}
        final.replace(output)
        output.with_suffix('.provenance.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('handoff', type=Path)
    ap.add_argument('runtime', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--expected-commit', required=True)
    args = ap.parse_args()
    print(json.dumps(assemble(args.handoff, args.runtime, args.output, args.expected_commit)['validation']))
