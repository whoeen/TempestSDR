"""Seal and append the authorized 2026-10-26 research results to the existing release."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess
import sys
import zipfile

lab = Path(__file__).resolve().parents[1]
result = lab / "results" / "iphone6_cfo_timing_20261026"
manifest_path = result / "ARTIFACT_MANIFEST.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["file_count"] >= 150
cache = result / "cache"
cache.mkdir(exist_ok=True)
archive = cache / "iphone6_cfo_timing_20261026_v1.zip"
members = [entry["path"] for entry in manifest["files"]] + [manifest_path.name]
assert len(members) == len(set(members))
for entry in manifest["files"]:
    source = (result / entry["path"]).resolve()
    assert source.is_relative_to(result.resolve())
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    assert source.stat().st_size == entry["bytes"] and digest == entry["sha256"]
if not archive.exists():
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as bundle:
        for name in members:
            bundle.write(result / name, name)
with zipfile.ZipFile(archive) as bundle:
    assert set(bundle.namelist()) == set(members)
    assert bundle.testzip() is None
print(json.dumps({"stage": "archive_verified", "members": len(members), "bytes": archive.stat().st_size}), flush=True)
run = subprocess.run(
    [sys.executable, "-X", "utf8", str(lab / "tools" / "upload_baseline_asset.py"), str(archive)],
    capture_output=True, text=True, encoding="utf-8"
)
if run.returncode:
    raise SystemExit("Upload failed: " + (run.stderr.strip() or run.stdout.strip()))
uploaded = json.loads(run.stdout)
assert uploaded["remote_verified"]
with archive.open("rb") as stream:
    local_digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
assert uploaded["digest"] == local_digest and uploaded["bytes"] == archive.stat().st_size
receipt = {
    "status": "complete",
    "completed_utc": datetime.now(timezone.utc).isoformat(),
    "archive": uploaded,
    "manifest_file_count": manifest["file_count"],
    "cloud_matlab_executed": False,
    "scope": "Local MATLAB execution; authored code/records in Git and numeric/image results in data release. Raw IQ already exists in prior release."
}
(result / "PUBLICATION_RECEIPT.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps(receipt), flush=True)
