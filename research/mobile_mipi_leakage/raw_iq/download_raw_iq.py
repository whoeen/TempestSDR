#!/usr/bin/env python3
"""Download and verify raw-IQ GitHub Release assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import urllib.request
from pathlib import Path


COPY_BLOCK = 8 * 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(COPY_BLOCK):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path, expected_bytes: int, expected_hash: str) -> None:
    if destination.is_file() and destination.stat().st_size == expected_bytes:
        if sha256_file(destination) == expected_hash:
            print(f"already verified: {destination.name}")
            return

    temporary = destination.with_name(destination.name + ".download")
    offset = temporary.stat().st_size if temporary.exists() else 0
    headers = {"User-Agent": "TempestSDR-raw-IQ-downloader"}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request) as response:
        append = offset > 0 and response.status == 206
        mode = "ab" if append else "wb"
        with temporary.open(mode) as handle:
            shutil.copyfileobj(response, handle, COPY_BLOCK)

    if temporary.stat().st_size != expected_bytes:
        raise ValueError(f"downloaded size mismatch: {destination.name}")
    if sha256_file(temporary) != expected_hash:
        raise ValueError(f"downloaded SHA-256 mismatch: {destination.name}")
    temporary.replace(destination)
    print(f"verified download: {destination.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("RAW_IQ_RELEASE_MANIFEST.json"))
    parser.add_argument("--parts-dir", type=Path, required=True)
    parser.add_argument("--dataset", action="append", dest="datasets")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    selected = set(args.datasets or [])
    known = {dataset["id"] for dataset in manifest["datasets"]}
    unknown = selected - known
    if unknown:
        parser.error("unknown dataset IDs: " + ", ".join(sorted(unknown)))

    args.parts_dir.mkdir(parents=True, exist_ok=True)
    base_url = manifest["release"]["asset_base_url"]
    for dataset in manifest["datasets"]:
        if selected and dataset["id"] not in selected:
            continue
        for part in dataset["parts"]:
            download(
                f"{base_url}/{part['name']}",
                args.parts_dir / part["name"],
                part["bytes"],
                part["sha256"],
            )


if __name__ == "__main__":
    main()
