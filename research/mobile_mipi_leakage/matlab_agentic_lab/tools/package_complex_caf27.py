from pathlib import Path
import json,hashlib,zipfile
root=Path(__file__).resolve().parents[1]
out=root/'results/iphone6_complex_caf_channels_20261027'
files=[p for p in out.rglob('*') if p.is_file() and p.suffix!='.zip' and p.name not in {'artifact_manifest.json','publication_receipt.json','REPORT_DRAFT.md'}]
manifest=[]
for p in files:
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(1024*1024):h.update(b)
 manifest.append({'path':p.relative_to(out).as_posix(),'bytes':p.stat().st_size,'sha256':h.hexdigest()})
(out/'artifact_manifest.json').write_text(json.dumps({'scope':'Derived outputs, reference input, frozen prior inputs and authored code; original RIS not duplicated.','files':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
files.append(out/'artifact_manifest.json')
archive=out/'iphone6_complex_caf_channels_20261027.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=3,allowZip64=True) as z:
 for p in files:z.write(p,p.relative_to(out).as_posix())
with zipfile.ZipFile(archive) as z:
 bad=z.testzip()
 if bad:raise RuntimeError('CRC failure: '+bad)
h=hashlib.sha256()
with archive.open('rb') as f:
 while b:=f.read(1024*1024):h.update(b)
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':h.hexdigest(),'members':len(files),'zip_crc_verified':True}))
