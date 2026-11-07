"""Package verified inputs deterministically and check a fresh extraction."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
from project_manifest import source_files

root = Path(__file__).resolve().parents[1]
report_path = root / 'build' / 'verification' / 'report.json'
report = json.loads(report_path.read_text())
if report['status'] != 'passed':
    raise RuntimeError('Run make verify successfully before packaging')
inputs = {str(p.relative_to(root)): p.read_bytes() for p in source_files(root)}
hashes = {name: hashlib.sha256(data).hexdigest() for name, data in inputs.items()}
if hashes != report['source_sha256']:
    raise RuntimeError('Verified source hashes do not match current project; run make verify again')
source_id = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()[:12]
# Retain final summary and all unified-stage logs. Large per-case traces remain local.
for path in sorted((root / 'build' / 'verification').glob('*')):
    if path.is_file() and path.suffix in ('.json', '.log'):
        inputs[str(path.relative_to(root))] = path.read_bytes()
for name in ('campaign', 'formal', 'formal_port', 'lint', 'verilator'):
    path = root / 'build' / name / 'report.json'
    if path.exists():
        inputs[str(path.relative_to(root))] = path.read_bytes()
for latency in (0, 1):
    path = root / 'build' / 'demo' / f'latency_{latency}' / 'report.json'
    inputs[str(path.relative_to(root))] = path.read_bytes()
inputs['docs/results.json'] = (root / 'docs/results.json').read_bytes()
manifest = {'source_id': source_id, 'verification_status': report['status'], 'skipped': report['skipped'],
            'files': {name: {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
                      for name, data in sorted(inputs.items())}}
inputs['MANIFEST.json'] = (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode()
dist = root / 'dist'
dist.mkdir(exist_ok=True)
archive = dist / f'mbist-bisr-{source_id}.tar.gz'
# Stable ordering, gzip timestamp, ownership, permissions and tar timestamps.
with archive.open('wb') as output:
    with gzip.GzipFile(filename='', mode='wb', fileobj=output, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as tar:
            for name, data in sorted(inputs.items()):
                info = tarfile.TarInfo('mbist-bisr/' + name)
                info.size, info.mode, info.mtime = len(data), 0o644, 0
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                tar.addfile(info, io.BytesIO(data))
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix(archive.suffix + '.sha256').write_text(f'{checksum}  {archive.name}\n')
# This is a locally created archive; nevertheless reject any unexpected members.
with tempfile.TemporaryDirectory(prefix='mbist-package-', dir=root / 'build') as temporary:
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar.getmembers():
            if not member.isfile() or Path(member.name).is_absolute() or '..' in Path(member.name).parts:
                raise RuntimeError('Unexpected archive member')
            destination = Path(temporary) / member.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(tar.extractfile(member).read())
    extracted = Path(temporary) / 'mbist-bisr'
    for name, data in inputs.items():
        if (extracted / name).read_bytes() != data:
            raise RuntimeError(f'Extraction mismatch: {name}')
    with (dist / 'extraction_check.log').open('w') as log:
        checked = subprocess.run(['make', 'test', 'synth'], cwd=extracted,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=180)
    if checked.returncode:
        raise RuntimeError(f'Extracted project failed; see {dist / "extraction_check.log"}')
(dist / 'package_check.json').write_text(json.dumps({'archive': archive.name, 'sha256': checksum,
    'source_id': source_id, 'extraction_matches': True, 'fresh_test_and_synthesis': 'passed'}, indent=2) + '\n')
print(f'PASS fresh extraction: make test synth\nArchive: {archive}\nSHA256: {checksum}')
