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
IQ. All laboratory captures listed in [`DATASETS.md`](DATASETS.md) are also
available as verified, split assets in the linked GitHub Release.

## Dataset configuration

The preferred cloud layout is:

```text
data/
  20260625_fs55.05487m_fc311m_25m_smallh_iphoneergentcallidisplay.rIs
  230mhz_20m_119.67847m_left_middle top_LGX22019.rIs
  238M_60M_124.08571_topleft_iphone6_book34page_.rIs
  238M_60M_124.08571M_bottom middle_iphone6.rIs
  238M_60M_124.08571M_topleft_iphone6.rIs
  238M_60M_124.08571M_topmiddle_book93page_iphone6.rIs
  308M_60M_124.08571M_bageung hwameon_iphone6.rIs
  311m_23m_110.11059m.rIs
  311m_55.05487m_20m.rIs
  312M_49M_124.08571M_baeung.rIs
  313.9m_25m_110.11059m.rIs
  444Page.rIs
  LGX22019_344.8M_60M_136.56551M.rIs
  111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs
  171.5mhz_20m_55.81679m_galaxS4lte.rIs
  390M_60M_124.08571M_topmiddle.rIs
  antenna1.rIs
  antenna2.rIs
  antenna3.rIs
```

Set `TEMPEST_DATA_ROOT` to another directory when the captures are mounted
elsewhere. To recreate the layout above from the public release:

```bash
python raw_iq/download_raw_iq.py --parts-dir raw_iq_parts
python raw_iq/assemble_raw_iq.py --parts-dir raw_iq_parts --output-dir data
```

The raw files remain ignored by ordinary Git because their combined size is
44.37 GiB. Release asset integrity and the original-file integrity are both
checked against [`raw_iq/RAW_IQ_RELEASE_MANIFEST.json`](raw_iq/RAW_IQ_RELEASE_MANIFEST.json).

## Repository contents

- Root Python files: acquisition timing, coherent averaging, fractional
  resampling, antenna restoration, separation, and STFT analysis.
- `coherent_results/`: validated big-endian result images and metadata.
- `provided_restoration_analysis/`: supplied-screen comparison and measured
  phase-stripe metrics.
- `results/`: historical RPCA and matched-subspace outputs.
- `chamber_plan/`: chamber experiment plan and expected signatures.
- `raw_iq/`: release manifest plus download, split, reconstruction, and
  verification tools for all eight `.rIs` captures.
- `EXCLUDED_ARTIFACTS_SHA256.csv`: every omitted `.npy`, `.npz`, and Python
  cache file with original relative path, size, and SHA-256.

Large numerical arrays total about 1.6 GiB and are excluded from Git. They are
derived artifacts; their manifest provides integrity and reconstruction
bookkeeping while the portable PNG/CSV/JSON outputs remain in the repository.
