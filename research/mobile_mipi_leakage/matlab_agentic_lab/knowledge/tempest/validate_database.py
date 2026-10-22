"""Check research-note references and the integrity of available PDF caches."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
def read_jsonl(name):
    return [json.loads(line) for line in (root / name).read_text(encoding="utf-8").splitlines() if line.strip()]

sources = read_jsonl("sources.jsonl")
claims = read_jsonl("claims.jsonl")
logs = read_jsonl("reading_log.jsonl")
ids = {row["source_id"] for row in sources}
assert len(ids) == len(sources), "Duplicate source_id"
assert len({row["claim_id"] for row in claims}) == len(claims), "Duplicate claim_id"
for row in claims:
    assert set(row["source_ids"]) <= ids, row["claim_id"]
for row in logs:
    assert row["source_id"] in ids
    assert row["complete_paper_read"] is False, "This cycle does not assert full paper audits"
cached = 0
for row in json.loads((root / "cache_manifest.json").read_text(encoding="utf-8")):
    if row["status"] == "cached":
        path = root / "cache" / "pdf" / (row["source_id"] + ".pdf")
        assert path.stat().st_size == row["bytes"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row["sha256"]
        cached += 1
print(json.dumps({"sources": len(sources), "claims": len(claims), "reading_logs": len(logs), "verified_pdf_caches": cached}))
