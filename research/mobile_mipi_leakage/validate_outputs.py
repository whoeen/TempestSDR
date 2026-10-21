"""Validate local report/gallery links and generated JSON artifacts."""
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parent
GITHUB_RELEASE_ASSET_LIMIT = 2 * 1024**3


def local_target(base: Path, value: str) -> Path | None:
    value = unquote(value.split("#", 1)[0].split("?", 1)[0])
    if not value or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", value):
        return None
    return (base / value).resolve()


def main() -> None:
    missing: list[str] = []
    report = ROOT / "LAB_MEETING_COHERENT_HSV_KR.md"
    report_links = re.findall(r"\[[^\]]*\]\(([^)]+)\)", report.read_text(encoding="utf-8"))
    for value in report_links:
        target = local_target(report.parent, value)
        if target is not None and not target.exists():
            missing.append(f"report: {value}")

    gallery = ROOT / "coherent_results" / "index.html"
    html_links = re.findall(r"(?:href|src)=[\"']([^\"']+)", gallery.read_text(encoding="utf-8"))
    for value in html_links:
        target = local_target(gallery.parent, value)
        if target is not None and not target.exists():
            missing.append(f"gallery: {value}")

    json_files = list((ROOT / "coherent_results").rglob("*.json"))
    for path in json_files:
        with path.open(encoding="utf-8") as handle:
            json.load(handle)

    manifest_path = ROOT / "raw_iq" / "RAW_IQ_RELEASE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    datasets = manifest["datasets"]
    if manifest["dataset_count"] != len(datasets):
        raise SystemExit("Raw-IQ manifest dataset count is inconsistent")
    if manifest["total_bytes"] != sum(dataset["bytes"] for dataset in datasets):
        raise SystemExit("Raw-IQ manifest total byte count is inconsistent")
    part_names: list[str] = []
    for dataset in datasets:
        if dataset["bytes"] != sum(part["bytes"] for part in dataset["parts"]):
            raise SystemExit(f"Raw-IQ part byte count is inconsistent: {dataset['id']}")
        if not re.fullmatch(r"[0-9a-f]{64}", dataset["sha256"]):
            raise SystemExit(f"Raw-IQ SHA-256 is malformed: {dataset['id']}")
        for part in dataset["parts"]:
            if part["bytes"] >= GITHUB_RELEASE_ASSET_LIMIT:
                raise SystemExit(f"Raw-IQ release asset is at least 2 GiB: {part['name']}")
            if not re.fullmatch(r"[0-9a-f]{64}", part["sha256"]):
                raise SystemExit(f"Raw-IQ part SHA-256 is malformed: {part['name']}")
            part_names.append(part["name"])
    if len(part_names) != len(set(part_names)):
        raise SystemExit("Raw-IQ release asset names are not unique")

    if missing:
        raise SystemExit("Missing local targets:\n" + "\n".join(missing))
    print(
        f"OK: {len(report_links)} report links, {len(html_links)} gallery links, "
        f"{len(json_files)} result JSON files, {len(datasets)} raw-IQ datasets, "
        f"{len(part_names)} release assets"
    )


if __name__ == "__main__":
    main()
