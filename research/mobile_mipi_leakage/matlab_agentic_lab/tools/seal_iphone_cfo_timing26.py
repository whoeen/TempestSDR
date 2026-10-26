"""Create a hash manifest of the completed local research artifacts."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

lab = Path(__file__).resolve().parents[1]
result = lab / "results" / "iphone6_cfo_timing_20261026"
excluded = {"ARTIFACT_MANIFEST.json", "PUBLICATION_RECEIPT.json", "install/mpm_template_web.txt", "install/mpm_input_r2026b.txt"}
files = []
for source in sorted(result.rglob("*")):
    if not source.is_file():
        continue
    rel = source.relative_to(result).as_posix()
    if rel in excluded or rel.startswith("cache/"):
        continue
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    files.append({"path": rel, "bytes": source.stat().st_size, "sha256": digest})
manifest = {"schema_version": 1, "created_utc": datetime.now(timezone.utc).isoformat(), "file_count": len(files), "total_bytes": sum(x["bytes"] for x in files), "hash_algorithm": "sha256", "files": files}
(result / "ARTIFACT_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k:v for k,v in manifest.items() if k != "files"}))
