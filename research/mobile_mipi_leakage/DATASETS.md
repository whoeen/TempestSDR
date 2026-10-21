# Raw capture inventory

Raw captures are intentionally not committed. Mount or download them into
`data/`, or set `TEMPEST_DATA_ROOT` to their containing directory.

| Capture | Expected file name | Stored I/Q rate | Notes |
|---|---|---:|---|
| iPhone 6 | `238M_60M_124.08571M_topleft_iphone6.rIs` | 124.085710 MS/s | Current big-endian reconstruction |
| iPhone 6s | `311m_55.05487m_20m.rIs` | 55.054870 MS/s | Historical P=1/32/100/200 comparison |
| LG X2 | `LGX22019_344.8M_60M_136.56551M.rIs` | 136.565510 MS/s | Current and historical comparisons |
| Galaxy S4 LTE | `111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs` | 110.891050 MS/s | Historical keypad capture |
| Galaxy S4 LTE | `171.5mhz_20m_55.81679m_galaxS4lte.rIs` | 55.816790 MS/s | Current big-endian reconstruction |
| Antenna 1 | `antenna1.rIs` | Unknown in file | 60 Hz/iPhone-geometry hypothesis |
| Antenna 2 | `antenna2.rIs` | Unknown in file | 60 Hz/iPhone-geometry hypothesis |
| Antenna 3 | `antenna3.rIs` | Unknown in file | No matching 60 Hz family confirmed |

## Binary format

- No header.
- Interleaved signed 16-bit I, Q.
- Big-endian byte order: NumPy dtype `>i2`.
- Four bytes per complex sample.

The RF center, bandwidth, and stored sample rate are not encoded in `.rIs`.
Treat values inferred only from filenames or neighboring captures as external
metadata, not as facts contained in the file.
