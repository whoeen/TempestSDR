# iPhone 6 sweep: raw release migration plan

Status: prepared locally; **no network request, credential lookup, or upload has been run by this preparation task**. A default dry run of the script passed and checked the planned source sizes.

## Destination and contents

Existing release: https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21

- 11 original RIS files, 11,107,800,000 bytes total.
- One 750 x 1334 reference screenshot, 105,197 bytes.
- Total upload payload: 11,107,905,197 bytes (12 assets).
- All raw assets are below 2,000,000,000 bytes, so no part splitting or extra raw copies are needed.
- Stable ASCII asset names: iphone6_black_text_sweep_20261023_fc100MHz.rIs through fc700MHz.rIs, plus iphone6_black_text_sweep_20261023_reference.png.
- Original Unicode filenames are retained in manifest metadata; local originals are not renamed.

CLOUD_UPLOAD_PLAN.json contains source paths, full SHA-256 values, sizes, and the 11 authored dataset entries. RAW_IQ_RELEASE_MANIFEST.planned.json is a review artifact only. It is not the primary published manifest and explicitly says the new uploads are pending. The current primary manifest was not changed.

The planned merge grows the repository manifest from 20 to 31 datasets and total raw bytes from 48,262,539,072 to 59,370,339,072. The screenshot is ancillary and does not count as an IQ dataset. Metadata records user-confirmed complex Fs=124,082,800 samples/s, RF bandwidth=120 MHz, each fc, probe geometry fixed by clamp, no external LNA or BPF, and reference-image hash. The date in the dataset ID is the ingest date; it is not asserted as the physical acquisition timestamp.

## Run commands

From this plan folder, local review (no network, no credentials):

    python -X utf8 upload_sweep_assets.py

Optional complete local rehash without network:

    python -X utf8 upload_sweep_assets.py --verify-local

Root may execute the following after reviewing this concrete plan. It performs network writes and therefore belongs in the authorized/escalated command path:

    python -X utf8 upload_sweep_assets.py --execute --apply-manifest

The script loads the existing configured Git credential only in execute mode, keeps it in memory, disables interactive prompting, and never prints it. It creates no new credential. Uploads are sequential. Before each upload it rechecks the full local hash and verifies that the file stays unchanged during transfer. The existing release is used; no new release is created.

On the server, both size and SHA-256 digest must match. A same-name mismatched, incomplete, or unverifiable asset stops the run; it is never deleted or replaced. After an interrupted/unknown result, rerun the same command: it reconciles exact same-name assets and continues. Every completed asset gets a fresh GitHub API verification and a record in CLOUD_UPLOAD_RECEIPT.json.

Only after all 12 assets verify does --apply-manifest merge the 11 datasets into the current primary repository manifest. This merge preserves unrelated additions made since this plan was prepared, rejects conflicting dataset IDs, and recalculates total counts. It writes atomically through a temporary file. The primary manifest update is local; root must commit/push it using the existing research workflow.

## Versioned release-manifest artifact

After successful upload and primary-manifest merge, a versioned metadata asset can be added using the existing lab/tools/upload_baseline_asset.py, copying only the small JSON manifest to a new distinct name such as RAW_IQ_RELEASE_MANIFEST_20261023_iphone6_sweep.json. Do not replace the older release-manifest asset under its existing name. The repository manifest is the authoritative evolving catalog used by raw_iq/download_raw_iq.py and raw_iq/assemble_raw_iq.py.

## Cloud download

After the repository manifest update reaches the cloud checkout, the existing download/assemble scripts work unchanged. For example use --dataset iphone6_black_text_sweep_20261023_fc100m. All 11 entries contain parts arrays with one complete RIS asset each and the original filename; assembly checks the full hash. Reference-image metadata contains its release URL and SHA-256 for separate ground-truth/control access.

No statement that an asset is available remotely should be made until the execute receipt records remote_verified=true. Raw RIS bytes must remain release assets, never regular Git blobs.
