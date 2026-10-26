"""Seal completed FAM artifacts; optionally publish to the existing data release.

Local processing outputs only. Original captures are not copied or uploaded.
Run after render_iphone100_fam26.py and creation of execution/knowledge records.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import subprocess
import sys
import zipfile

lab = Path(__file__).resolve().parents[1]
result = lab / "results" / "iphone6_fc100_fam_20261026"
parser = argparse.ArgumentParser()
parser.add_argument("--publish", action="store_true")
args = parser.parse_args()

verification = json.loads((result / "verification" / "verification.json").read_text(encoding="utf-8"))
assert verification["all_passed"]
validation = json.loads((result / "validation_v2" / "validation.json").read_text(encoding="utf-8"))
periodicity = json.loads((result / "periodicity" / "summary.json").read_text(encoding="utf-8"))
assert validation["all_discovery_replays_passed"]
assert periodicity["status"] == "completed"
assert (result / "gallery" / "index.html").is_file()
assert (result / "EXECUTION_RECORD.json").is_file()

excluded = {"ARTIFACT_MANIFEST.json", "PUBLICATION_RECEIPT.json"}
files = []
for source in sorted(result.rglob("*")):
    if not source.is_file():
        continue
    rel = source.relative_to(result).as_posix()
    if rel in excluded or rel.startswith(("cache/", "failed_periodicity_v1/")):
        continue
    assert source.resolve().is_relative_to(result.resolve())
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    files.append({"path": rel, "bytes": source.stat().st_size, "sha256": digest})
manifest = {"created_utc": datetime.now(timezone.utc).isoformat(),
            "hash_algorithm": "sha256", "file_count": len(files),
            "total_bytes": sum(x["bytes"] for x in files), "files": files,
            "exclusion_note": "Failed partial MAT output omitted; failure logs retained."}
manifest_path = result / "ARTIFACT_MANIFEST.json"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
cache = result / "cache"
cache.mkdir(exist_ok=True)
archive = cache / "iphone6_fc100_fam_20261026_v1.zip"
members = [x["path"] for x in files] + [manifest_path.name]
if not archive.exists():
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as bundle:
        for name in members:
            bundle.write(result / name, name)
with zipfile.ZipFile(archive) as bundle:
    assert set(bundle.namelist()) == set(members)
    assert bundle.testzip() is None
    archived_manifest = json.loads(bundle.read(manifest_path.name))
    assert archived_manifest["files"] == files, "Existing archive differs; use a new version."
print(json.dumps({"stage": "archive_verified", "members": len(members),
                  "bytes": archive.stat().st_size, "path": str(archive)}), flush=True)
if args.publish:
    run = subprocess.run([sys.executable, "-X", "utf8", str(lab / "tools" / "upload_baseline_asset.py"),
                          str(archive)], capture_output=True, text=True, encoding="utf-8")
    if run.returncode:
        raise SystemExit("Upload failed: " + (run.stderr.strip() or run.stdout.strip()))
    uploaded = json.loads(run.stdout)
    assert uploaded["remote_verified"]
    with archive.open("rb") as stream:
        local_digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
    assert uploaded["digest"] == local_digest and uploaded["bytes"] == archive.stat().st_size
    receipt = {"status": "complete", "completed_utc": datetime.now(timezone.utc).isoformat(),
               "archive": uploaded, "manifest_file_count": len(files),
               "cloud_matlab_executed": False,
               "scope": "Local MATLAB analysis; authored code/records in Git and numeric/image artifacts in existing data release."}
    (result / "PUBLICATION_RECEIPT.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt), flush=True)
