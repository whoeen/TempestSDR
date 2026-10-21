"""Validate local report/gallery links and generated JSON artifacts."""
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parent


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

    if missing:
        raise SystemExit("Missing local targets:\n" + "\n".join(missing))
    print(
        f"OK: {len(report_links)} report links, {len(html_links)} gallery links, "
        f"{len(json_files)} JSON files"
    )


if __name__ == "__main__":
    main()
