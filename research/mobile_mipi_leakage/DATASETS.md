# Raw capture inventory

All 16 smartphone captures and three antenna captures are published as split
assets in the
[`mobile-mipi-raw-iq-2026-10-21`](https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21)
GitHub Release. The Git tree keeps every byte count and SHA-256 value in
[`raw_iq/RAW_IQ_RELEASE_MANIFEST.json`](raw_iq/RAW_IQ_RELEASE_MANIFEST.json).
Use the scripts in [`raw_iq/`](raw_iq/) to download, verify, and reconstruct
them into `data/`, or set `TEMPEST_DATA_ROOT` to another containing directory.

## Smartphone captures

| Capture | Expected file name | RF center | Receiver BW | Stored I/Q rate | Notes |
|---|---|---:|---:|---:|---|
| iPhone, model unresolved | `20260625_fs55.05487m_fc311m_25m_smallh_iphoneergentcallidisplay.rIs` | 311 MHz | 25 MHz | 55.054870 MS/s | Emergency-call display; filename metadata |
| LG X2 (2019) | `230mhz_20m_119.67847m_left_middle top_LGX22019.rIs` | 230 MHz | 20 MHz | 119.678470 MS/s | Left-middle/top probe position |
| iPhone 6 | `238M_60M_124.08571_topleft_iphone6_book34page_.rIs` | 238 MHz | 60 MHz | 124.085710 MS/s | Book page 34, top-left |
| iPhone 6 | `238M_60M_124.08571M_bottom middle_iphone6.rIs` | 238 MHz | 60 MHz | 124.085710 MS/s | Bottom-middle probe position |
| iPhone 6 | `238M_60M_124.08571M_topleft_iphone6.rIs` | 238 MHz | 60 MHz | 124.085710 MS/s | Current big-endian reconstruction |
| iPhone 6 | `238M_60M_124.08571M_topmiddle_book93page_iphone6.rIs` | 238 MHz | 60 MHz | 124.085710 MS/s | Book page 93, top-middle |
| iPhone 6 | `308M_60M_124.08571M_bageung hwameon_iphone6.rIs` | 308 MHz | 60 MHz | 124.085710 MS/s | Response screen |
| Smartphone, model unresolved | `311m_23m_110.11059m.rIs` | 311 MHz | 23 MHz | 110.110590 MS/s | Device label not encoded in filename |
| iPhone 6s | `311m_55.05487m_20m.rIs` | 311 MHz | 20 MHz | 55.054870 MS/s | Historical P=1/32/100/200 comparison |
| iPhone 6 | `312M_49M_124.08571M_baeung.rIs` | 312 MHz | 49 MHz | 124.085710 MS/s | Response/background experiments |
| Smartphone, model unresolved | `313.9m_25m_110.11059m.rIs` | 313.9 MHz | 25 MHz | 110.110590 MS/s | Device label not encoded in filename |
| Smartphone, model unresolved | `444Page.rIs` | Unknown | Unknown | Unknown | Manual acquisition metadata required |
| LG X2 (2019) | `LGX22019_344.8M_60M_136.56551M.rIs` | 344.8 MHz | 60 MHz | 136.565510 MS/s | Current and historical comparisons |
| Galaxy S4 LTE | `111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs` | 111.9 MHz | 20 MHz | 110.891050 MS/s | Historical keypad capture |
| Galaxy S4 LTE | `171.5mhz_20m_55.81679m_galaxS4lte.rIs` | 171.5 MHz | 20 MHz | 55.816790 MS/s | Current big-endian reconstruction |
| Smartphone, model unresolved | `390M_60M_124.08571M_topmiddle.rIs` | 390 MHz | 60 MHz | 124.085710 MS/s | Top-middle probe position |

The 16 deduplicated smartphone files total 43,005,600,000 bytes (40.05 GiB).
Device labels marked unresolved are retained that way because the filename and
available experiment notes do not establish a model reliably.

## Antenna captures

| Capture | Expected file name | Stored I/Q rate | Notes |
|---|---|---:|---|
| Antenna 1 | `antenna1.rIs` | Unknown in file | 60 Hz/iPhone-geometry hypothesis |
| Antenna 2 | `antenna2.rIs` | Unknown in file | 60 Hz/iPhone-geometry hypothesis |
| Antenna 3 | `antenna3.rIs` | Unknown in file | No matching 60 Hz family confirmed |

All 19 original files total 47,638,800,000 bytes (44.37 GiB). Release assets
are capped at 1,900 MiB per part and can be independently verified before
reconstruction.

## Binary format

- No header.
- Interleaved signed 16-bit I, Q.
- Big-endian byte order: NumPy dtype `>i2`.
- Four bytes per complex sample.

The RF center, bandwidth, and stored sample rate are not encoded in `.rIs`.
Treat values inferred only from filenames or neighboring captures as external
metadata, not as facts contained in the file.
