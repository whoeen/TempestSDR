"""Upload the prepared iPhone6 sweep to the established raw-IQ data release.
Default mode is local plan review: no network or credential access.
--execute enables sequential uploads; --apply-manifest updates the repository
manifest only after every planned asset has passed remote size/digest checks.
Original captures are never renamed, changed, split, or copied.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import http.client
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_json(path, value):
    path = Path(path)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    tmp.replace(path)


def local_digest(asset):
    path = Path(asset['source_path'])
    before = path.stat()
    if before.st_size != asset['bytes']:
        raise RuntimeError('Local byte count differs from plan: ' + asset['name'])
    digest = hashlib.sha256()
    with path.open('rb') as source:
        while block := source.read(8 * 1024 * 1024):
            digest.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError('Local input changed during verification: ' + asset['name'])
    if digest.hexdigest() != asset['sha256']:
        raise RuntimeError('Local SHA-256 differs from plan: ' + asset['name'])
    return before.st_mtime_ns


def authorize(repository):
    # Executed only after --execute. Never print the credential-helper result.
    request = 'protocol=https\nhost=github.com\npath=' + repository + '.git\n\n'
    environment = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
    completed = subprocess.run(['git', 'credential', 'fill'], input=request,
                               text=True, capture_output=True, env=environment)
    if completed.returncode:
        raise RuntimeError('Existing Git credential helper unavailable; no upload performed.')
    fields = dict(line.split('=', 1) for line in completed.stdout.splitlines() if '=' in line)
    token = fields.get('password')
    if not token:
        raise RuntimeError('No existing GitHub credential returned; no upload performed.')
    return {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
            'User-Agent': 'TempestSDR-iPhone6-sweep-uploader', 'X-GitHub-Api-Version': '2022-11-28'}


def get_json(url, headers):
    if urllib.parse.urlsplit(url).hostname != 'api.github.com':
        raise RuntimeError('Unexpected API endpoint.')
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError('GitHub API request failed with HTTP ' + str(error.code)) from None


def list_assets(repository, release_id, headers):
    by_name = {}
    page = 1
    while True:
        batch = get_json(f'https://api.github.com/repos/{repository}/releases/{release_id}/assets?per_page=100&page={page}', headers)
        for item in batch:
            if item['name'] in by_name:
                raise RuntimeError('Duplicate remote asset name: ' + item['name'])
            by_name[item['name']] = item
        if len(batch) < 100:
            return by_name
        page += 1


def verify_remote(item, asset):
    expected = 'sha256:' + asset['sha256']
    if item.get('size') != asset['bytes'] or item.get('digest') != expected:
        raise RuntimeError('Remote asset size/digest missing or different; refusing replacement: ' + asset['name'])
    if item.get('name') != asset['name']:
        raise RuntimeError('Server renamed asset unexpectedly: ' + asset['name'])
    if item.get('state') != 'uploaded':
        raise RuntimeError('Remote asset is not in uploaded state: ' + asset['name'])


def upload_one(release, asset, headers, original_mtime_ns):
    endpoint = release['upload_url'].split('{', 1)[0]
    parsed = urllib.parse.urlsplit(endpoint)
    if parsed.scheme != 'https' or parsed.hostname != 'uploads.github.com':
        raise RuntimeError('Unexpected release upload endpoint.')
    query = urllib.parse.urlencode({'name': asset['name']})
    connection = http.client.HTTPSConnection(parsed.hostname, timeout=180)
    try:
        connection.putrequest('POST', parsed.path + '?' + query)
        for key, value in headers.items():
            connection.putheader(key, value)
        connection.putheader('Content-Type', 'image/png' if asset['kind'] == 'reference_image' else 'application/octet-stream')
        connection.putheader('Content-Length', str(asset['bytes']))
        connection.endheaders()
        sent = 0
        next_notice = 256 * 1024 * 1024
        with Path(asset['source_path']).open('rb') as source:
            while block := source.read(4 * 1024 * 1024):
                connection.send(block)
                sent += len(block)
                if sent >= next_notice:
                    print(json.dumps({'name': asset['name'], 'bytes_sent': sent, 'bytes_total': asset['bytes']}), flush=True)
                    next_notice += 256 * 1024 * 1024
        response = connection.getresponse()
        body = response.read()
        if response.status != 201:
            raise RuntimeError('Release upload failed with HTTP ' + str(response.status) + '; rerun reconciles existing assets without replacing them.')
        item = json.loads(body)
    finally:
        connection.close()
    after = Path(asset['source_path']).stat()
    if after.st_size != asset['bytes'] or after.st_mtime_ns != original_mtime_ns:
        raise RuntimeError('Local file changed during upload; uploaded asset requires review: ' + asset['name'])
    verify_remote(item, asset)
    return item


def apply_manifest(plan, receipts):
    planned_names = {asset['name'] for asset in plan['assets']}
    if {entry['name'] for entry in receipts} != planned_names:
        raise RuntimeError('Cannot update manifest until every planned raw and reference asset is verified.')
    manifest_path = Path(plan['base_manifest_path'])
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest['release']['repository'] != plan['repository'] or manifest['release']['tag'] != plan['release_tag']:
        raise RuntimeError('Current manifest points to a different release.')
    existing = {entry['id']: entry for entry in manifest['datasets']}
    for addition in plan['datasets']:
        prior = existing.get(addition['id'])
        if prior:
            if prior['sha256'] != addition['sha256'] or prior['bytes'] != addition['bytes'] or prior['parts'] != addition['parts']:
                raise RuntimeError('Conflicting dataset already present: ' + addition['id'])
        else:
            addition = dict(addition, release_verified_utc=utc_now())
            manifest['datasets'].append(addition)
            existing[addition['id']] = addition
    manifest['dataset_count'] = len(manifest['datasets'])
    manifest['total_bytes'] = sum(entry['bytes'] for entry in manifest['datasets'])
    manifest['updated_utc'] = utc_now()
    write_json(manifest_path, manifest)
    return {'path': str(manifest_path), 'dataset_count': manifest['dataset_count'], 'total_bytes': manifest['total_bytes']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, default=Path(__file__).with_name('CLOUD_UPLOAD_PLAN.json'))
    parser.add_argument('--execute', action='store_true', help='Enable network, existing credential-helper lookup, and uploads.')
    parser.add_argument('--verify-local', action='store_true', help='Rehash all local inputs without requiring network.')
    parser.add_argument('--apply-manifest', action='store_true', help='After complete remote verification, append datasets to primary repository manifest.')
    args = parser.parse_args()
    if args.apply_manifest and not args.execute:
        parser.error('--apply-manifest requires --execute')
    plan = json.loads(args.plan.read_text(encoding='utf-8'))
    if plan['repository'] != 'whoeen/TempestSDR' or plan['release_tag'] != 'mobile-mipi-raw-iq-2026-10-21':
        raise RuntimeError('Plan destination differs from the authorized release.')
    names = [entry['name'] for entry in plan['assets']]
    if len(names) != len(set(names)):
        raise RuntimeError('Plan contains duplicate asset names.')
    for asset in plan['assets']:
        if not asset['name'].isascii() or '/' in asset['name'] or '\\' in asset['name']:
            raise RuntimeError('Asset names must be stable ASCII basenames.')
        if Path(asset['source_path']).stat().st_size != asset['bytes']:
            raise RuntimeError('Local size differs from plan: ' + asset['name'])
        if asset['bytes'] >= 2_000_000_000:
            raise RuntimeError('Asset needs explicit part packaging: ' + asset['name'])
    print(json.dumps({'mode': 'execute' if args.execute else 'local_review', 'release': plan['release_url'],
                      'asset_count': len(names), 'raw_count': plan['raw_dataset_count'],
                      'total_bytes': plan['total_upload_bytes'], 'names': names}), flush=True)
    if not args.execute:
        if args.verify_local:
            for asset in plan['assets']:
                local_digest(asset)
                print(json.dumps({'name': asset['name'], 'local_full_sha256_verified': True}), flush=True)
        return
    headers = authorize(plan['repository'])
    release = get_json('https://api.github.com/repos/' + plan['repository'] + '/releases/tags/' + urllib.parse.quote(plan['release_tag'], safe=''), headers)
    remote = list_assets(plan['repository'], release['id'], headers)
    receipt_path = args.plan.with_name('CLOUD_UPLOAD_RECEIPT.json')
    receipt = {'status': 'running', 'started_utc': utc_now(), 'release_url': plan['release_url'], 'assets': []}
    write_json(receipt_path, receipt)
    for asset in plan['assets']:
        mtime = local_digest(asset)
        item = remote.get(asset['name'])
        if item:
            verify_remote(item, asset)
            action = 'matched_existing'
        else:
            item = upload_one(release, asset, headers, mtime)
            action = 'uploaded'
        # Fresh API state is the confirmation, not just the POST response.
        item = get_json('https://api.github.com/repos/' + plan['repository'] + '/releases/assets/' + str(item['id']), headers)
        verify_remote(item, asset)
        record = {'name': item['name'], 'id': item['id'], 'bytes': item['size'],
                  'sha256': asset['sha256'], 'server_digest': item['digest'],
                  'url': item['browser_download_url'], 'action': action,
                  'remote_verified': True, 'verified_utc': utc_now()}
        receipt['assets'].append(record)
        write_json(receipt_path, receipt)
        print(json.dumps(record), flush=True)
    receipt['status'] = 'complete'
    receipt['completed_utc'] = utc_now()
    if args.apply_manifest:
        receipt['manifest_update'] = apply_manifest(plan, receipt['assets'])
    write_json(receipt_path, receipt)
    print(json.dumps({'status': 'complete', 'receipt': str(receipt_path), 'manifest_updated': args.apply_manifest}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, http.client.HTTPException) as error:
        raise SystemExit(str(error)) from None
