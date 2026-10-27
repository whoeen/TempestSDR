from pathlib import Path
import json, hashlib, zipfile
root = Path(__file__).resolve().parents[1]
out = root / 'results/iphone6_coherent_pca_caf_20261027'
excluded = {'artifact_manifest.json','cloud_manifest.json'}
files = sorted(p for p in out.rglob('*') if p.is_file() and p.suffix != '.zip' and p.name not in excluded)
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(1024*1024):
            h.update(chunk)
    return h.hexdigest()
manifest = [{'path':p.relative_to(out).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)} for p in files]
(out/'artifact_manifest.json').write_text(json.dumps({'scope':'Measured derived IQ/CAF/PCA/binary data, plots, authored source snapshot and reference. Original RIS and prior CAF bundle are external dependencies. cloud_manifest.json is an external upload receipt, excluded to avoid a circular archive hash.','files':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
files.append(out/'artifact_manifest.json')
archive = out/'iphone6_coherent_pca_caf_20261027.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=3,allowZip64=True) as z:
    for p in files:
        z.write(p,p.relative_to(out).as_posix())
with zipfile.ZipFile(archive) as z:
    bad=z.testzip()
    if bad:
        raise RuntimeError('CRC failure: '+bad)
receipt={'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest(archive),'members':len(files),'zip_crc_verified':True,'upload_status':'not_yet_uploaded','download_url':'https://github.com/whoeen/TempestSDR/releases/download/mobile-mipi-raw-iq-2026-10-21/iphone6_coherent_pca_caf_20261027.zip'}
(out/'cloud_manifest.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(receipt),flush=True)
