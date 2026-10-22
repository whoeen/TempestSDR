"""Append a result archive to the already authorized TempestSDR data release.
Uses the configured Git credential helper in memory; never prints credentials.
"""
from pathlib import Path
import argparse, hashlib, http.client, json, os, subprocess, urllib.parse, urllib.request

p=argparse.ArgumentParser()
p.add_argument('asset',type=Path)
a=p.parse_args()
repo='whoeen/TempestSDR'
tag='mobile-mipi-raw-iq-2026-10-21'
request='protocol=https\nhost=github.com\npath='+repo+'.git\n\n'
env=dict(os.environ,GIT_TERMINAL_PROMPT='0')
c=subprocess.run(['git','credential','fill'],input=request,text=True,capture_output=True,env=env)
if c.returncode: raise SystemExit('Configured Git credential helper unavailable; no upload performed.')
credential=dict(line.split('=',1) for line in c.stdout.splitlines() if '=' in line)
token=credential.get('password')
if not token: raise SystemExit('No GitHub credential returned; no upload performed.')
headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','User-Agent':'TempestSDR-research-uploader','X-GitHub-Api-Version':'2022-11-28'}
url='https://api.github.com/repos/'+repo+'/releases/tags/'+tag
with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=60) as response: release=json.load(response)
digest=hashlib.sha256()
with a.asset.open('rb') as f:
    while block:=f.read(1024*1024):digest.update(block)
expected='sha256:'+digest.hexdigest()
existing=[x for x in release['assets'] if x['name']==a.asset.name]
if existing:
    item=existing[0]
    if item.get('digest')!=expected or item['size']!=a.asset.stat().st_size:
        raise SystemExit('An asset with this name already exists and does not match; refusing replacement.')
else:
    upload=release['upload_url'].split('{')[0]+'?'+urllib.parse.urlencode({'name':a.asset.name})
    parsed=urllib.parse.urlsplit(upload)
    if parsed.scheme!='https' or parsed.hostname!='uploads.github.com':raise SystemExit('Unexpected upload endpoint.')
    conn=http.client.HTTPSConnection(parsed.hostname,timeout=60)
    conn.putrequest('POST',parsed.path+'?'+parsed.query)
    for key,value in headers.items():conn.putheader(key,value)
    conn.putheader('Content-Type','application/octet-stream')
    conn.putheader('Content-Length',str(a.asset.stat().st_size))
    conn.endheaders()
    with a.asset.open('rb') as f:
        while block:=f.read(1024*1024):conn.send(block)
    response=conn.getresponse()
    body=response.read()
    if response.status!=201:raise SystemExit('GitHub upload failed with HTTP '+str(response.status))
    item=json.loads(body)
    conn.close()
    if item['size']!=a.asset.stat().st_size or item.get('digest')!=expected:
        raise SystemExit('Remote asset size/digest verification failed.')
print(json.dumps({'name':item['name'],'bytes':item['size'],'digest':item['digest'],'url':item['browser_download_url'],'remote_verified':True}))
