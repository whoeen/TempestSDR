"""Package one MATLAB run, source snapshots and review without modifying inputs."""
from pathlib import Path
import argparse, hashlib, json, zipfile

p = argparse.ArgumentParser()
p.add_argument('run_root', type=Path)
p.add_argument('lab_root', type=Path)
p.add_argument('review_root', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
inputs = [(x, 'run/'+str(x.relative_to(a.run_root)).replace('\\','/')) for x in a.run_root.rglob('*') if x.is_file()]
inputs += [(x, 'source/'+str(x.relative_to(a.lab_root)).replace('\\','/')) for x in a.lab_root.rglob('*.m') if 'outputs' not in x.parts and 'results' not in x.parts]
inputs += [(a.review_root/n, 'review/'+n) for n in ['REPORT_KO.md','source_manifest.json','numeric_tests.json','timing_summary.csv']]
manifest = []
with zipfile.ZipFile(a.output,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path, name in inputs:
        digest = hashlib.sha256()
        with path.open('rb') as f:
            while block := f.read(1024*1024): digest.update(block)
        manifest.append({'path':name,'bytes':path.stat().st_size,'sha256':digest.hexdigest()})
        z.write(path,name)
    z.writestr('FILE_MANIFEST.json',json.dumps(manifest,indent=2))
digest = hashlib.sha256()
with a.output.open('rb') as f:
    while block := f.read(1024*1024): digest.update(block)
with a.output.with_suffix(a.output.suffix+'.sha256').open('x') as f:
    f.write(digest.hexdigest()+'  '+a.output.name+'\n')
print(json.dumps({'file':str(a.output),'bytes':a.output.stat().st_size,'sha256':digest.hexdigest(),'entries':len(inputs)+1}))
