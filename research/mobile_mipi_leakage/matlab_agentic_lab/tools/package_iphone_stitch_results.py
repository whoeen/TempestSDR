#!/usr/bin/env python3
"""Package only the 2026-10-23 iPhone 6 stitching experiment; never upload.

Default execution prints a plan and creates nothing. Run --build only after
MATLAB outputs and the report/gallery are final. Numeric MAT ZIPs use stored
entries (MAT v7 files are already compressed); PNGs are also stored, while
textual views and source snapshots use DEFLATE. All archive members start at
results/iphone6_stitch_20261023/, so extracting every ZIP into the same lab
root restores the result tree and its relative offline gallery links.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import zipfile
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Iterable

EXPERIMENT = "iphone6_stitch_20261023"
PREFIX = "iphone6_stitch_20261023_v1"
LAB_ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = LAB_ROOT / "results" / EXPERIMENT
OUTPUT_ROOT = RESULT_ROOT / "cache" / "release_bundles"
ARCHIVE_PREFIX = f"results/{EXPERIMENT}/"
MAX_MAT_GROUP_BYTES = 1_500_000_000
MAX_ARCHIVE_BYTES = 2_000_000_000
CHUNK_BYTES = 1024 * 1024
FIXED_ZIP_DATETIME = (2026, 10, 23, 0, 0, 0)
VIEW_SUFFIXES = {".png", ".json", ".csv", ".md", ".html"}

# Deliberate allowlist: no other experiments, credentials, raw IQ or PDF text.
ROOT_SOURCE_NAMES = (
    "IPHONE_SWEEP_REPRODUCTION.md",
    "auditIphoneStitchClutter.m", "buildIphoneStitchTemplates.m",
    "createIphoneStitchPhaseEvidence.m", "estimateStitchFrameModel.m",
    "inspectIphoneStitchSweep.m", "previewIphoneStitchSweep.m",
    "reproduceIphoneSweep.m", "runIphoneAmplitudeRefinement.m",
    "runIphoneSingleFrameStitchControl.m", "runIphoneStitchExperiment.m",
)
GENERIC_DEPENDENCIES = (
    "diagnoseIq.m", "estimateWelchPsd.m", "periodicHann.m", "powerDb.m",
    "readRisIqBlock.m", "resolveIphoneSweepCapture.m",
    "sampleQuantile.m", "writeJsonFile.m",
)
TOOL_NAMES = ("make_iphone_stitch_gallery.py", "package_iphone_stitch_results.py")
KNOWLEDGE_NAMES = (
    "CAPTURE_INVENTORY.json", "CAPTURE_INVENTORY.md",
    "CHAPTER_ALGORITHM_AUDIT.md", "chapter_source_identity.json",
    "lr_response_audit.json", "PERIODIC_TEMPLATE_HARMONIC_MAP.md",
    "TEMPLATE_BUILDER_REVIEW.md", "VALIDATION_DESIGN.md",
)


@dataclass(frozen=True)
class Entry:
    source: Path | None
    archive_name: str
    size: int
    mtime_ns: int | None
    kind: str
    generated: bytes | None = None


def within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def validate_archive_name(name: str) -> None:
    parsed = PurePosixPath(name)
    if (not name.startswith(ARCHIVE_PREFIX) or parsed.is_absolute()
            or ".." in parsed.parts or "\\" in name or ":" in name
            or any(part in {"cache", ".git"} for part in parsed.parts)):
        raise ValueError(f"Unsafe or out-of-experiment archive member: {name}")
    if parsed.suffix.lower() in {".pdf", ".ris", ".rIs", ".iq", ".bin"}:
        raise ValueError(f"Raw/copyright-source format is forbidden: {name}")


def entry_from_file(source: Path, archive_name: str, kind: str) -> Entry:
    validate_archive_name(archive_name)
    if source.is_symlink() or not within(source, LAB_ROOT):
        raise ValueError(f"Source is a symlink or outside the laboratory: {source}")
    stat = source.stat()
    if not source.is_file():
        raise ValueError(f"Not a regular source file: {source}")
    return Entry(source, archive_name, stat.st_size, stat.st_mtime_ns, kind)


def excluded_result_file(relative: Path) -> bool:
    lowered = relative.name.lower()
    return (lowered == ".gitignore"
            or any(part.lower() in {"cache", ".git"} for part in relative.parts)
            or ("publication" in lowered and "receipt" in lowered))


def collect_result_entries() -> tuple[list[Entry], list[Entry], list[str]]:
    if not RESULT_ROOT.is_dir():
        raise FileNotFoundError(f"Experiment directory is absent: {RESULT_ROOT}")
    views: list[Entry] = []
    numeric: list[Entry] = []
    skipped: list[str] = []
    for directory, subdirs, filenames in os.walk(RESULT_ROOT, followlinks=False):
        current = Path(directory)
        retained = []
        for name in sorted(subdirs):
            child = current / name
            if name.lower() in {"cache", ".git"} or child.is_symlink() or not within(child, RESULT_ROOT):
                skipped.append(child.relative_to(RESULT_ROOT).as_posix() + "/")
            else:
                retained.append(name)
        subdirs[:] = retained
        for filename in sorted(filenames):
            source = current / filename
            relative = source.relative_to(RESULT_ROOT)
            if source.is_symlink() or not within(source, RESULT_ROOT) or excluded_result_file(relative):
                skipped.append(relative.as_posix())
                continue
            suffix = source.suffix.lower()
            if suffix == ".mat":
                numeric.append(entry_from_file(source, ARCHIVE_PREFIX + relative.as_posix(), "result_mat"))
            elif suffix in VIEW_SUFFIXES:
                views.append(entry_from_file(source, ARCHIVE_PREFIX + relative.as_posix(), "result_view"))
            else:
                skipped.append(relative.as_posix())
    return sorted(views, key=lambda e: e.archive_name), sorted(numeric, key=lambda e: e.archive_name), skipped


def collect_reproducibility_entries() -> tuple[list[Entry], list[str]]:
    sources: list[Path] = [LAB_ROOT / name for name in ROOT_SOURCE_NAMES]
    stitch_root = LAB_ROOT / "stitch"
    if stitch_root.is_dir():
        sources.extend(sorted(path for path in stitch_root.iterdir()
                              if path.is_file() and path.suffix.lower() in {".m", ".md"}))
    sources.extend(LAB_ROOT / "signal_processing" / name for name in GENERIC_DEPENDENCIES)
    sources.extend(LAB_ROOT / "tools" / name for name in TOOL_NAMES)
    note_root = LAB_ROOT / "knowledge" / "stitching" / "iphone6_sweep_20261023"
    sources.extend(note_root / name for name in KNOWLEDGE_NAMES)
    entries: list[Entry] = []
    missing: list[str] = []
    for source in sorted(set(sources), key=lambda p: p.as_posix()):
        relative = source.relative_to(LAB_ROOT).as_posix()
        if not source.is_file():
            missing.append(relative)
            continue
        arcname = ARCHIVE_PREFIX + "reproducibility/source_snapshot/" + relative
        entries.append(entry_from_file(source, arcname, "authored_source_snapshot"))
    readme = (
        "# iPhone 6 stitching release extraction\n\n"
        "Extract the views ZIP and every numeric ZIP into the same MATLAB laboratory root. "
        "Each member begins with results/iphone6_stitch_20261023/. "
        "Open results/iphone6_stitch_20261023/gallery/index.html afterwards.\n\n"
        "The source_snapshot folder contains an explicitly selected snapshot of authored "
        "MATLAB helpers, their generic dependencies, Python gallery/packaging tools and "
        "research notes. It does not overwrite the working source files. "
        "Its inner paths are relative to matlab_agentic_lab.\n\n"
        "Raw RIS/IQ, PDFs, extracted source-text caches, publication receipts and all cache "
        "directories are excluded. Raw capture delivery remains separate. "
        "These numerical artifacts do not establish successful full-band physical recovery; "
        "consult REPORT.md for validated results and limitations.\n"
    ).encode("utf-8")
    arcname = ARCHIVE_PREFIX + "reproducibility/README.md"
    entries.append(Entry(None, arcname, len(readme), None, "generated_packaging_note", readme))
    return entries, missing


def partition_numeric(entries: Iterable[Entry]) -> list[list[Entry]]:
    groups: list[list[Entry]] = []
    current: list[Entry] = []
    current_bytes = 0
    for entry in sorted(entries, key=lambda e: e.archive_name):
        if entry.size > MAX_MAT_GROUP_BYTES:
            raise ValueError(f"Single MAT exceeds the 1.5 GB uncompressed group cap: {entry.archive_name} ({entry.size})")
        if current and current_bytes + entry.size > MAX_MAT_GROUP_BYTES:
            groups.append(current)
            current, current_bytes = [], 0
        current.append(entry)
        current_bytes += entry.size
    if current:
        groups.append(current)
    return groups


def make_plan() -> tuple[dict, list[tuple[str, list[Entry]]]]:
    views, numeric, skipped = collect_result_entries()
    source_entries, missing = collect_reproducibility_entries()
    views = sorted(views + source_entries, key=lambda e: e.archive_name)
    all_names = [entry.archive_name for entry in views + numeric]
    if len(all_names) != len(set(all_names)):
        raise ValueError("Archive entry names collide; refusing an ambiguous extraction.")
    if sum(entry.size for entry in views) > MAX_ARCHIVE_BYTES - 10_000_000:
        raise ValueError("Views bundle is too large for the conservative 2 GB archive limit.")
    groups = partition_numeric(numeric)
    archives = [(f"{PREFIX}_views.zip", views)]
    archives.extend((f"{PREFIX}_numeric_{index:03d}.zip", group)
                    for index, group in enumerate(groups, 1))
    result_view_count = sum(entry.kind == "result_view" for entry in views)
    plan = {
        "schema": "iphone-stitch-release-bundles/1", "experiment": EXPERIMENT,
        "prefix": PREFIX, "status": "planned_not_built",
        "result_root": str(RESULT_ROOT), "output_directory": str(OUTPUT_ROOT),
        "numeric_uncompressed_group_cap_bytes": MAX_MAT_GROUP_BYTES,
        "archive_size_cap_bytes": MAX_ARCHIVE_BYTES,
        "entry_root": ARCHIVE_PREFIX,
        "result_view_file_count": result_view_count,
        "result_mat_file_count": len(numeric),
        "result_mat_total_bytes": sum(entry.size for entry in numeric),
        "reproducibility_entry_count": len(source_entries),
        "missing_optional_source_snapshots": missing,
        "excluded_paths": sorted(skipped),
        "compression": "MAT and PNG stored; JSON/CSV/MD/HTML/authored source DEFLATE level 6",
        "determinism": "POSIX archive-path sort; fixed ZIP timestamp; sequential greedy MAT partition",
        "archives": [{"name": name, "file_count": len(entries),
                      "uncompressed_bytes": sum(entry.size for entry in entries)}
                     for name, entries in archives],
        "scope_audit": {
            "outside_experiment_results_included": False,
            "raw_iq_included": False, "pdfs_or_fulltext_caches_included": False,
            "all_members_under_expected_root": True,
            "all_selected_result_mats_partitioned_once": sum(map(len, groups)) == len(numeric),
        },
    }
    return plan, archives


def assert_snapshot_unchanged(entry: Entry) -> None:
    if entry.source is None:
        return
    stat = entry.source.stat()
    if stat.st_size != entry.size or stat.st_mtime_ns != entry.mtime_ns:
        raise RuntimeError(f"Source changed since planning; stop writers before packaging: {entry.source}")


def write_entry(archive: zipfile.ZipFile, entry: Entry) -> dict:
    assert_snapshot_unchanged(entry)
    validate_archive_name(entry.archive_name)
    info = zipfile.ZipInfo(entry.archive_name, date_time=FIXED_ZIP_DATETIME)
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.compress_type = (zipfile.ZIP_STORED if PurePosixPath(entry.archive_name).suffix.lower()
                          in {".mat", ".png"} else zipfile.ZIP_DEFLATED)
    info.file_size = entry.size
    digest = hashlib.sha256()
    copied = 0
    with archive.open(info, "w", force_zip64=False) as target:
        if entry.source is None:
            block = entry.generated or b""
            target.write(block)
            digest.update(block)
            copied = len(block)
        else:
            with entry.source.open("rb") as source:
                while block := source.read(CHUNK_BYTES):
                    target.write(block)
                    digest.update(block)
                    copied += len(block)
    if copied != entry.size:
        raise RuntimeError(f"Source size changed while copying: {entry.archive_name}")
    assert_snapshot_unchanged(entry)
    return {
        "archive_name": entry.archive_name, "bytes": copied,
        "sha256": digest.hexdigest(), "kind": entry.kind,
        "source_relative_to_lab": (entry.source.relative_to(LAB_ROOT).as_posix()
                                   if entry.source else None),
        "compression": "stored" if info.compress_type == zipfile.ZIP_STORED else "deflate",
    }


def verify_archive(path: Path, expected_entries: list[dict]) -> dict:
    expected = {entry["archive_name"]: entry for entry in expected_entries}
    if len(expected) != len(expected_entries):
        raise ValueError("Duplicate expected member names.")
    verified = 0
    uncompressed_bytes = 0
    with zipfile.ZipFile(path, "r") as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError(f"Archive member set mismatch: {path.name}")
        for info in infos:
            validate_archive_name(info.filename)
            record = expected[info.filename]
            if info.is_dir() or info.file_size != record["bytes"]:
                raise ValueError(f"Archive member size/type mismatch: {info.filename}")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"Symlink archive member is forbidden: {info.filename}")
            digest = hashlib.sha256()
            crc = 0
            size = 0
            with archive.open(info, "r") as source:
                while block := source.read(CHUNK_BYTES):
                    digest.update(block)
                    crc = zlib.crc32(block, crc)
                    size += len(block)
            if (digest.hexdigest() != record["sha256"] or size != record["bytes"]
                    or (crc & 0xFFFFFFFF) != info.CRC):
                raise ValueError(f"Archive content verification failed: {info.filename}")
            verified += 1
            uncompressed_bytes += size
    return {
        "status": "passed", "expected_entry_count": len(expected_entries),
        "verified_entry_count": verified, "uncompressed_bytes": uncompressed_bytes,
        "member_names_exact": True, "unique_names": True,
        "safe_relative_paths": True, "entry_sha256_match": True,
        "entry_crc32_match": True, "raw_pdf_cache_entries_absent": True,
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(CHUNK_BYTES):
            digest.update(block)
    return digest.hexdigest()


def build() -> dict:
    plan, archive_plans = make_plan()
    if not within(OUTPUT_ROOT, RESULT_ROOT / "cache"):
        raise ValueError("Release output must remain inside this experiment's cache.")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUTPUT_ROOT / f"{PREFIX}_manifest.json"
    targets = [manifest_path]
    for name, _ in archive_plans:
        targets.extend([OUTPUT_ROOT / name, OUTPUT_ROOT / (name + ".partial")])
    existing = [str(path) for path in targets if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite existing release artifacts: " + ", ".join(existing))
    archive_records = []
    for name, entries in archive_plans:
        partial = OUTPUT_ROOT / (name + ".partial")
        final = OUTPUT_ROOT / name
        print(f"Building {name}: {len(entries)} entries, {sum(e.size for e in entries):,} input bytes", flush=True)
        with zipfile.ZipFile(partial, "x", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=6, allowZip64=True, strict_timestamps=True) as archive:
            records = [write_entry(archive, entry) for entry in entries]
        archive_bytes = partial.stat().st_size
        if archive_bytes >= MAX_ARCHIVE_BYTES:
            raise ValueError(f"Archive exceeds conservative 2 GB limit: {partial} ({archive_bytes})")
        checks = verify_archive(partial, records)
        archive_hash = sha256_file(partial)
        partial.rename(final)
        archive_records.append({
            "name": name, "bytes": archive_bytes, "sha256": archive_hash,
            "file_count": len(records), "entry_checks": checks, "entries": records,
        })
        print(f"Verified {name}: {archive_bytes:,} bytes, SHA-256 {archive_hash}", flush=True)
    manifest = dict(plan)
    manifest.update({
        "status": "built_and_verified", "created_utc": datetime.now(timezone.utc).isoformat(),
        "archives": archive_records, "upload_performed": False,
        "restore_instructions": "Extract every ZIP into the same matlab_agentic_lab root, then open results/iphone6_stitch_20261023/gallery/index.html.",
    })
    with manifest_path.open("x", encoding="utf-8", newline="\n") as target:
        json.dump(manifest, target, ensure_ascii=False, indent=2)
        target.write("\n")
    print(f"Manifest: {manifest_path}", flush=True)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true",
                        help="Build and verify archives after all result writers have stopped; default is plan only.")
    args = parser.parse_args()
    if args.build:
        manifest = build()
        print(json.dumps({"status": manifest["status"], "archive_count": len(manifest["archives"]),
                          "output_directory": str(OUTPUT_ROOT)}, indent=2))
    else:
        plan, _ = make_plan()
        print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        print(f"Packaging stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
