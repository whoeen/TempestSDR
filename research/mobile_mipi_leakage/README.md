# Smartphone MIPI/display-leakage reconstruction

This directory is the cloud-portable record of the September 2026 smartphone
TEMPEST analysis. It contains the analysis programs, Korean lab-meeting notes,
metrics, and rendered results for iPhone 6/6s, LG X2, Galaxy S4 LTE, and three
antenna captures.

## Start here

- [`LAB_MEETING_COHERENT_HSV_KR.md`](LAB_MEETING_COHERENT_HSV_KR.md): full lab-meeting narrative.
- [`provided_restoration_analysis/ANALYSIS_KR.md`](provided_restoration_analysis/ANALYSIS_KR.md): original-versus-restored and P=1/32/100/200 image analysis.
- [`TF_DRIVER_STUDY_KR.md`](TF_DRIVER_STUDY_KR.md): row/column STFT and display-driver interpretation.
- [`REPORT_KR.md`](REPORT_KR.md): RPCA and matched-subspace study.
- [`coherent_results/index.html`](coherent_results/index.html): generated result gallery.

## Result provenance

Two result families are retained deliberately:

1. `coherent_results/*_big_endian` and the current raw-IQ readers use
   interleaved big-endian signed int16 I/Q (`>i2`), matching `RIS2IQ.m`.
2. `results/`, `tf_results/`, and `provided_restoration_analysis/` preserve
   historical figures used in the comparison. The legacy generation path used
   little-endian `<i2`; these figures are useful for image-domain diagnostics
   but must not be used alone to attribute a physical emission source.

## Python environment

```bash
python -m venv .venv
python -m pip install -r requirements.txt
python provided_restoration_analysis/analyze_images.py
python validate_outputs.py
```

The committed images and tables allow the image analysis to run without raw
IQ. Raw-IQ reconstruction requires the laboratory captures listed in
[`DATASETS.md`](DATASETS.md).

## Dataset configuration

The preferred cloud layout is:

```text
data/
  238M_60M_124.08571M_topleft_iphone6.rIs
  311m_55.05487m_20m.rIs
  LGX22019_344.8M_60M_136.56551M.rIs
  111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs
  171.5mhz_20m_55.81679m_galaxS4lte.rIs
  antenna1.rIs
  antenna2.rIs
  antenna3.rIs
```

Set `TEMPEST_DATA_ROOT` to another directory when the captures are mounted
elsewhere. The raw files are ignored by Git because they contain laboratory
measurements and are too large for ordinary Git transport.

## Repository contents

- Root Python files: acquisition timing, coherent averaging, fractional
  resampling, antenna restoration, separation, and STFT analysis.
- `coherent_results/`: validated big-endian result images and metadata.
- `provided_restoration_analysis/`: supplied-screen comparison and measured
  phase-stripe metrics.
- `results/`: historical RPCA and matched-subspace outputs.
- `chamber_plan/`: chamber experiment plan and expected signatures.
- `EXCLUDED_ARTIFACTS_SHA256.csv`: every omitted `.npy`, `.npz`, and Python
  cache file with original relative path, size, and SHA-256.

Large numerical arrays total about 1.6 GiB and are excluded from Git. They are
derived artifacts; their manifest provides integrity and reconstruction
bookkeeping while the portable PNG/CSV/JSON outputs remain in the repository.
