"""Cache openly accessible primary-source PDFs for local scholarly reading only.

The cache is excluded from Git: public access does not grant redistribution rights.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import requests
import fitz

ROOT = Path(__file__).resolve().parent
SOURCES = {
    "kuhn2004": "https://www.cl.cam.ac.uk/~mgk25/pet2004-fpd.pdf",
    "erdeljan2024": "https://www.cl.cam.ac.uk/~mgk25/emc2024-coherent-demodulation.pdf",
    "erdeljan2025": "https://www.cl.cam.ac.uk/~mgk25/emc2025-hdmi-classification.pdf",
    "emeye2024": "https://www.ndss-symposium.org/wp-content/uploads/2024-552-paper.pdf",
    "deep2024": "https://arxiv.org/pdf/2407.09717",
    "smartphone2019": "https://eudl.eu/pdf/10.1007/978-3-030-23976-3_9",
    "usbee2016": "https://arxiv.org/pdf/1608.08397",
    "he2008": "https://repository.upenn.edu/bitstreams/43d2a5a2-9e1c-48b5-8ffc-e464fe44621c/download",
    "gleaning2021": "https://arxiv.org/pdf/2011.09877",
}

def cache_one(item):
    sid, url = item
    target = ROOT / "cache" / "pdf" / f"{sid}.pdf"
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        if not target.exists():
            response = requests.get(url, timeout=60)
            response.raise_for_status()
            if not response.content.startswith(b"%PDF"):
                raise ValueError("Response is not PDF")
            target.write_bytes(response.content)
        doc = fitz.open(target)
        text_dir = ROOT / "cache" / "text" / sid
        text_dir.mkdir(parents=True, exist_ok=True)
        for n, page in enumerate(doc, 1):
            (text_dir / f"p{n:03}.txt").write_text(page.get_text(sort=True), encoding="utf-8")
        return {"source_id": sid, "url": url, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                "bytes": target.stat().st_size, "pages": len(doc), "status": "cached", "downloaded_date": "2026-10-22"}
    except Exception as exc:
        return {"source_id": sid, "url": url, "status": "failed", "error": str(exc)}

if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(cache_one, SOURCES.items()))
    (ROOT / "cache_manifest.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    for row in rows:
        print(json.dumps(row))
