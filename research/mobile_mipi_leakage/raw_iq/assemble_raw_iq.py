#!/usr/bin/env python3
"""Reassemble and verify raw .rIs captures from downloaded release assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


COPY_BLOCK = 8 * 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(COPY_BLOCK):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("RAW_IQ_RELEASE_MANIFEST.json"))
    parser.add_argument("--parts-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dataset", action="append", dest="datasets")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    selected = set(args.datasets or [])
    known = {dataset["id"] for dataset in manifest["datasets"]}
    unknown = selected - known
    if unknown:
        parser.error("unknown dataset IDs: " + ", ".join(sorted(unknown)))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for dataset in manifest["datasets"]:
        if selected and dataset["id"] not in selected:
            continue
        output = args.output_dir / dataset["filename"]
        temporary = output.with_name(output.name + ".partial")
        full_hash = hashlib.sha256()
        full_bytes = 0

        with temporary.open("wb") as output_handle:
            for part in dataset["parts"]:
                path = args.parts_dir / part["name"]
                if not path.is_file():
                    raise FileNotFoundError(f"missing release asset: {path}")
                if path.stat().st_size != part["bytes"]:
                    raise ValueError(f"size mismatch: {path}")
                if sha256_file(path) != part["sha256"]:
                    raise ValueError(f"SHA-256 mismatch: {path}")
                with path.open("rb") as part_handle:
                    while block := part_handle.read(COPY_BLOCK):
                        output_handle.write(block)
                        full_hash.update(block)
                        full_bytes += len(block)

        if full_bytes != dataset["bytes"] or full_hash.hexdigest() != dataset["sha256"]:
            temporary.unlink(missing_ok=True)
            raise ValueError(f"reassembled capture failed verification: {dataset['id']}")
        os.replace(temporary, output)
        print(f"verified {dataset['id']}: {output} ({full_bytes} bytes)")


if __name__ == "__main__":
    main()
