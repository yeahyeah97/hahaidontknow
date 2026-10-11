#!/usr/bin/env python3
"""Add hash-pinned user CRT files to a real CI app and verify the unsigned IPA."""
import argparse
import copy
import hashlib
import json
import struct
import shutil
import tempfile
import zipfile
from pathlib import Path
from inspect_binary import windows_dll
from record_native_handoff import digest
from repack_ipa_for_signing import repack
from verify_optimized_ipa import validate


def assemble(handoff, runtime, output, expected_commit, wow64=None):
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
    # Accept the separately compiled Wine 32-bit farm ONLY when every module
    # agrees with the immutable SHA-256 manifest from its GitHub action. A
    # successful native iOS build without the guest x86 farm is not v4.
    wow_files = {}
    wow_manifest = None
    if wow64 is not None:
        if wow64.is_file() and wow64.suffix.lower() == '.zip':
            wow_zip = zipfile.ZipFile(wow64, 'r')
            wow_zip.__enter__()
            wow_entries = dict((n, wow_zip.read(n)) for n in wow_zip.namelist())
            wow_zip.__exit__(None, None, None)
        elif wow64.is_dir():
            wow_entries = {str(p.relative_to(wow64)).replace('\\', '/'): p.read_bytes()
                           for p in wow64.rglob('*') if p.is_file()}
        else:
            raise ValueError('WoW64 handoff must be the validated artifact ZIP or extracted directory')
        if 'wow64-manifest.json' not in wow_entries:
            raise ValueError('Missing WoW64 build evidence')
        wow_manifest = json.loads(wow_entries['wow64-manifest.json'])
        if (wow_manifest.get('status') != 'verified-32bit-PE-source-build;device-untested'
                or wow_manifest.get('repository') != 'yeahyeah97/hahaidontknow'
                or wow_manifest.get('count', 0) < 700):
            raise ValueError('WoW64 evidence missing, incomplete, or untrusted')
        if wow_manifest.get('wine_source_commit') != '257f271cfffed9f22f7987cac53bc00095d092fe':
            raise ValueError('WoW64 Wine source revision mismatch')
        if wow_manifest.get('dxmt_source_commit') != 'db546ee466ad50ec6463edb5fa183de11db43761':
            raise ValueError('WoW64 DXMT source revision mismatch')
        files = wow_manifest.get('files', {})
        if len(files) != wow_manifest['count']:
            raise ValueError('WoW64 manifest count mismatch')
        for name, info in files.items():
            source_name = 'i386-windows/' + name
            if (name != Path(name).name or '\\' in name or name.startswith('.')
                    or source_name not in wow_entries):
                raise ValueError('Missing or unsafe i386 PE member: ' + name)
            data = wow_entries[source_name]
            if len(data) != info['size'] or hashlib.sha256(data).hexdigest() != info['sha256']:
                raise ValueError('i386 module hash/size mismatch: ' + name)
            if data[:2] != b'MZ':
                raise ValueError('i386 module without MZ: ' + name)
            off = struct.unpack_from('<I', data, 60)[0]
            if off + 24 > len(data) or data[off:off + 4] != bytes([80, 69, 0, 0]):
                raise ValueError('Invalid i386 PE: ' + name)
            if struct.unpack_from('<H', data, off + 4)[0] != 0x14c:
                raise ValueError('WoW64 compiled module is not x86: ' + name)
        for filename, data in wow_entries.items():
            if filename == 'wow64-manifest.json':
                continue
            if (not filename.startswith('i386-windows/') or
                    '..' in filename.split('/') or '\\' in filename or
                    filename.endswith('/')):
                raise ValueError('Unsafe WoW64 artifact path: ' + filename)
            if filename.startswith('i386-windows/') and filename.removeprefix('i386-windows/') in files:
                pass
            elif filename.endswith(('.dll','.exe','.drv','.cpl','.acm','.ax','.ocx')):
                raise ValueError('Unverified extra Windows PE in WoW64 artifact: '+filename)
            wow_files[filename] = data
        if len(wow_files) < wow_manifest['count']:
            raise ValueError('Partial WoW64 artifact')

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
            for name, data in wow_files.items():
                dest_name = 'Payload/Madeira.app/' + name
                if dest_name in dest.namelist():
                    raise ValueError('Duplicate WoW64 member in release: ' + name)
                info = zipfile.ZipInfo(dest_name)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                dest.writestr(info, data)
            for name, data in dlls.items():
                info = zipfile.ZipInfo('Payload/Madeira.app/x86_64-vcruntime/' + name)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                dest.writestr(info, data)
        repack(staging, final, 'com.steammobile.engine', 'Steam Mobile')
        result = validate(final)
        if wow_manifest is not None:
            with zipfile.ZipFile(final) as z:
                for name, details in wow_manifest['files'].items():
                    dst = 'Payload/Madeira.app/i386-windows/' + name
                    if dst not in z.namelist() or hashlib.sha256(z.read(dst)).hexdigest() != details['sha256']:
                        raise ValueError('Verified i386 module missing from assembled IPA: ' + name)
            result['wow64_i386_modules'] = wow_manifest['count']
        manifest = {'schema': 1, 'status': 'unsigned-device-tests-pending',
                    'native_build': evidence, 'crt': lock, 'wow64': wow_manifest,
                    'validation': result,
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
    ap.add_argument('--wow64-handoff', type=Path, help='Validated 32-bit Wine farm artifact ZIP; required for consolidated v4')
    args = ap.parse_args()
    print(json.dumps(assemble(args.handoff, args.runtime, args.output, args.expected_commit, args.wow64_handoff)['validation']))
