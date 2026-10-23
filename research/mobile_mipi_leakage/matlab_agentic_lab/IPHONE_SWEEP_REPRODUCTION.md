# Portable reproduction of the iPhone 6 sweep

This guide prepares reproduction on another local or cloud MATLAB host. **It does not report a cloud MATLAB run.** Current analysis uses the user's local MATLAB desktop; release upload progress is tracked separately by CLOUD_UPLOAD_RECEIPT.json.

## Requirements

- A checkout containing the updated 31-dataset raw manifest and the portable caller replacements listed below.
- All eleven sweep assets remotely verified before downloading them.
- A runnable, appropriately licensed MATLAB installation on the destination host. A Codex cloud checkout or GitHub release does not supply MATLAB or a license. Configure licensing through the institution's existing deployment method.
- Base MATLAB supports the included DSP implementations. Available Signal Processing Toolbox functions such as pwelch are preferred and logged. No particular cloud toolbox installation is assumed.
- RAM and disk for the 11.1078 GB inputs, per-band templates, and wideband FFT intermediates. Full synthesis is substantially larger than one 2^21-sample input.

## Download naming and original filenames

raw_iq/download_raw_iq.py stores manifest.parts[].name, for example:

    iphone6_black_text_sweep_20261023_fc100MHz.rIs

raw_iq/assemble_raw_iq.py writes manifest.filename, restoring:

    black글_fc100MHz.rIs

Each sweep dataset has one part containing the entire original capture. MATLAB can directly use the verified ASCII downloads without a second 11.1 GB copy. The resolver also accepts the assembled Unicode names.

## Download exactly these eleven datasets

From the repository root, Bash example after upload verification and manifest publication:

    dataset_args=()
    for fc in 100 160 220 280 340 400 460 520 580 640 700; do
      dataset_args+=(--dataset "iphone6_black_text_sweep_20261023_fc${fc}m")
    done
    python research/mobile_mipi_leakage/raw_iq/download_raw_iq.py \
      --parts-dir "$PWD/raw_iq_parts" "${dataset_args[@]}"

The downloader checks complete-file size and SHA-256. Optional original-name assembly:

    python research/mobile_mipi_leakage/raw_iq/assemble_raw_iq.py \
      --parts-dir "$PWD/raw_iq_parts" --output-dir "$PWD/data" "${dataset_args[@]}"

Use a new data destination when preserving an existing dataset: assembly replaces a same-name destination after verification. The reproduction driver never invokes assembly or modifies raw files.

## Capture resolver

signal_processing/resolveIphoneSweepCapture.m accepts only fc=100:60:700 MHz. It reads, never changes, environment variables. Search order:

1. TEMPEST_IQ_ROOT when externally configured.
2. USERPROFILE/Downloads on Windows, HOME/Downloads elsewhere.
3. Existing current/repository data and raw_iq_parts directories.

Within each directory, the original Unicode name is preferred over the stable ASCII release name. The helper validates existence, positive length divisible by four, and inventory byte count when available. Full SHA verification belongs to the downloader/assembler and is not repeated on every block access. A same-name file with an incorrect recorded size causes an error rather than silently falling through.

## Preflight and fresh reproduction

Process-scoped Bash invocation example; these commands were NOT executed while preparing this guide:

    TEMPEST_IQ_ROOT="$PWD/raw_iq_parts" matlab -batch \
      "addpath('research/mobile_mipi_leakage/matlab_agentic_lab'); reproduceIphoneSweep();"

Preflight reports resolved paths, MATLAB version/function availability, and whether all raw-reading callers use the resolver. It performs no reconstruction.

Full mode requires a NEW directory and an externally configured TEMPEST_IQ_ROOT. It stages MATLAB code and the identity inventory, preserving historical results without copying raw IQ:

    TEMPEST_IQ_ROOT="$PWD/raw_iq_parts" matlab -batch \
      "addpath('research/mobile_mipi_leakage/matlab_agentic_lab'); reproduceIphoneSweep('/workspace/iphone6-sweep-run-01',Mode='all');"

Replace the run path with a writable new directory on that host. Existing run directories are rejected. The driver serially runs synthetic gates and ten analysis stages: diagnostics, integer controls, train/holdout timing, templates, both polarity stitching experiments, single-frame controls, AM refinement, phase/time-frequency evidence, and the clutter audit. The last two stages consume the saved templates and stitching outputs. It writes reproduction.json and verification.json; final evidence is under results/iphone6_stitch_20261023/phase_tf and clutter_audit. It does not infer that the executing host is a cloud host.

On Windows, direct functions and preflight can resolve Downloads automatically. For staged reproduction configure TEMPEST_IQ_ROOT in the launching environment and supply a new Windows run path. The helper and driver do not call setenv.

## Portable raw-reader integration

The following five functions now resolve raw files through the shared helper. Each change replaces only the source-path assignment; its DSP remains unchanged.

| File / line | Installed assignment |
|---|---|
| inspectIphoneStitchSweep.m:53 | rawPath = resolveIphoneSweepCapture(fcMHz); |
| previewIphoneStitchSweep.m:14 | filename = resolveIphoneSweepCapture(fc); |
| estimateStitchFrameModel.m:57 | source = resolveIphoneSweepCapture(fcMHz); |
| buildIphoneStitchTemplates.m:21 | filename = resolveIphoneSweepCapture(fc); |
| runIphoneAmplitudeRefinement.m:13 | filename = resolveIphoneSweepCapture(fc); |

All five add signal_processing to the MATLAB path. Template-only readers need no raw replacement. Preflight checks current code readiness; full mode refuses to run if any caller lacks the resolver.

## Staged dependency coverage

The driver copies all root-level MATLAB files plus the direct .m files in signal_processing and stitch into the new run directory. This includes:

- signal_processing/resolveIphoneSweepCapture.m and signal_processing/writeJsonFile.m.
- stitch/sampleGuardedIqFftTest.m, its sampleGuardedIqFft.m implementation, and the four named unit-test classes.
- createIphoneStitchPhaseEvidence.m and auditIphoneStitchClutter.m at the lab root. Their shared resamplePeriodicAm and alignPeriodicOverlap helpers are in stitch; their other helper functions are local.
- knowledge/stitching/iphone6_sweep_20261023/CAPTURE_INVENTORY.json for capture-size checks.

No results, raw captures, or external workstation directories are copied. These dependency locations were inspected statically; a destination-host preflight and actual MATLAB execution remain separate verification steps. A completed clutter-audit call can report pending sources or failed edges in its own status, so inspect clutter_audit/overview.json rather than treating mere driver termination as proof of a valid stitch.

## Interpretation

Fs=124.0828 MS/s and bandwidth=120 MHz remain user-reported metadata. The screenshot is ground truth/control, not reconstruction input. Stable timing or coherence alone does not establish a valid physical stitch. Preserve heldout and ambiguity diagnostics.
