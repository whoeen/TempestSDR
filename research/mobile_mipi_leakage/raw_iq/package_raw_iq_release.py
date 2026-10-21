#!/usr/bin/env python3
"""Split raw .rIs captures into GitHub Release assets and write a manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


CHUNK_SIZE = 1900 * 1024 * 1024  # safely below GitHub's 2 GiB asset limit
COPY_BLOCK = 8 * 1024 * 1024

DATASETS = {
    "iphone6_topleft_238m": {
        "capture": "iPhone 6",
        "filename": "238M_60M_124.08571M_topleft_iphone6.rIs",
        "stored_iq_rate_sps": 124_085_710,
    },
    "iphone6s_311m": {
        "capture": "iPhone 6s",
        "filename": "311m_55.05487m_20m.rIs",
        "stored_iq_rate_sps": 55_054_870,
    },
    "lgx2_344p8m": {
        "capture": "LG X2",
        "filename": "LGX22019_344.8M_60M_136.56551M.rIs",
        "stored_iq_rate_sps": 136_565_510,
    },
    "galaxy_s4_lte_111p9m": {
        "capture": "Galaxy S4 LTE",
        "filename": "111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs",
        "stored_iq_rate_sps": 110_891_050,
    },
    "galaxy_s4_lte_171p5m": {
        "capture": "Galaxy S4 LTE",
        "filename": "171.5mhz_20m_55.81679m_galaxS4lte.rIs",
        "stored_iq_rate_sps": 55_816_790,
    },
    "antenna1": {
        "capture": "Antenna 1",
        "filename": "antenna1.rIs",
        "stored_iq_rate_sps": None,
    },
    "antenna2": {
        "capture": "Antenna 2",
        "filename": "antenna2.rIs",
        "stored_iq_rate_sps": None,
    },
    "antenna3": {
        "capture": "Antenna 3",
        "filename": "antenna3.rIs",
        "stored_iq_rate_sps": None,
    },
}


def parse_source(value: str) -> tuple[str, Path]:
    dataset_id, separator, raw_path = value.partition("=")
    if not separator or dataset_id not in DATASETS:
        choices = ", ".join(DATASETS)
        raise argparse.ArgumentTypeError(
            f"expected DATASET_ID=PATH; DATASET_ID must be one of: {choices}"
        )
    path = Path(raw_path).expanduser()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"capture does not exist: {path}")
    return dataset_id, path


def split_capture(dataset_id: str, source: Path, output_dir: Path) -> dict:
    metadata = DATASETS[dataset_id]
    source_hash = hashlib.sha256()
    parts = []
    total_bytes = 0

    with source.open("rb") as source_handle:
        part_number = 1
        while True:
            part_name = f"{dataset_id}.rIs.part{part_number:03d}"
            part_path = output_dir / part_name
            part_hash = hashlib.sha256()
            part_bytes = 0

            with part_path.open("wb") as part_handle:
                while part_bytes < CHUNK_SIZE:
                    block = source_handle.read(min(COPY_BLOCK, CHUNK_SIZE - part_bytes))
                    if not block:
                        break
                    part_handle.write(block)
                    part_hash.update(block)
                    source_hash.update(block)
                    part_bytes += len(block)
                    total_bytes += len(block)

            if part_bytes == 0:
                part_path.unlink()
                break

            parts.append(
                {
                    "name": part_name,
                    "bytes": part_bytes,
                    "sha256": part_hash.hexdigest(),
                }
            )
            print(f"{dataset_id}: wrote {part_name} ({part_bytes} bytes)", flush=True)
            part_number += 1

    return {
        "id": dataset_id,
        **metadata,
        "bytes": total_bytes,
        "sha256": source_hash.hexdigest(),
        "parts": parts,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        action="append",
        required=True,
        type=parse_source,
        metavar="DATASET_ID=PATH",
        help="repeat once for every capture",
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument(
        "--release-tag", default="mobile-mipi-raw-iq-2026-10-21"
    )
    args = parser.parse_args()

    sources = dict(args.source)
    duplicates = len(sources) != len(args.source)
    if duplicates:
        parser.error("each DATASET_ID may appear only once")

    missing = sorted(set(DATASETS) - set(sources))
    if missing:
        parser.error("missing datasets: " + ", ".join(missing))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    datasets = [split_capture(key, sources[key], args.output_dir) for key in DATASETS]
    total_bytes = sum(dataset["bytes"] for dataset in datasets)
    manifest = {
        "schema_version": 1,
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "release": {
            "repository": "whoeen/TempestSDR",
            "tag": args.release_tag,
            "url": f"https://github.com/whoeen/TempestSDR/releases/tag/{args.release_tag}",
            "asset_base_url": (
                "https://github.com/whoeen/TempestSDR/releases/download/"
                f"{args.release_tag}"
            ),
        },
        "binary_format": {
            "header": False,
            "sample_layout": "interleaved I,Q",
            "component_dtype": "signed int16",
            "byte_order": "big-endian",
            "bytes_per_complex_sample": 4,
        },
        "chunk_size_bytes": CHUNK_SIZE,
        "dataset_count": len(datasets),
        "total_bytes": total_bytes,
        "datasets": datasets,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote manifest: {args.manifest}", flush=True)
    print(f"total: {len(datasets)} datasets, {total_bytes} bytes", flush=True)


if __name__ == "__main__":
    main()
