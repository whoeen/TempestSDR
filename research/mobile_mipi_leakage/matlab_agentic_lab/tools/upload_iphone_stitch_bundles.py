"""Upload the sealed 2026-10-23 result bundles using the existing repository uploader."""
from pathlib import Path
import hashlib, json, subprocess, sys
from datetime import datetime, timezone

lab = Path(__file__).resolve().parents[1]
result = lab / 'results' / 'iphone6_stitch_20261023'
bundles = result / 'cache' / 'release_bundles'
prefix = 'iphone6_stitch_20261023_v1'
manifest_path = bundles / (prefix + '_manifest.json')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
assert manifest['status'] == 'built_and_verified'
records = list(manifest['archives']) + [{'name': manifest_path.name}]
receipt_path = result / 'RESULT_PUBLICATION_RECEIPT.json'
receipt = {'status':'running', 'started_utc':datetime.now(timezone.utc).isoformat(), 'assets':[], 'cloud_matlab_executed':False}

def checkpoint():
    receipt_path.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')

checkpoint()
for record in records:
    name = record['name']
    assert Path(name).name == name and name.startswith(prefix)
    asset = bundles / name
    sha = hashlib.file_digest(asset.open('rb'), 'sha256').hexdigest()
    size = asset.stat().st_size
    if 'sha256' in record:
        assert sha == record['sha256'] and size == record['bytes']
    print(json.dumps({'uploading':name,'bytes':size}), flush=True)
    run = subprocess.run([sys.executable, '-X', 'utf8', str(lab/'tools'/'upload_baseline_asset.py'), str(asset)], capture_output=True, text=True, encoding='utf-8')
    if run.returncode:
        receipt.update(status='failed', failed_asset=name, error=run.stderr.strip() or run.stdout.strip())
        checkpoint()
        raise SystemExit('Bundle upload failed; see receipt for diagnostic.')
    uploaded = json.loads(run.stdout)
    assert uploaded['remote_verified'] and uploaded['digest'] == 'sha256:'+sha and uploaded['bytes'] == size
    receipt['assets'].append(uploaded)
    checkpoint()
    print(json.dumps(uploaded), flush=True)
receipt.update(status='complete',completed_utc=datetime.now(timezone.utc).isoformat())
checkpoint()
(result/'RESULT_BUNDLE_MANIFEST.json').write_bytes(manifest_path.read_bytes())
print(json.dumps({'status':'complete','verified_assets':len(receipt['assets']),'receipt':str(receipt_path)}),flush=True)
