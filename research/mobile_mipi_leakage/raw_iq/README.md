# Raw IQ release assets

The eight `.rIs` captures used by this study are published as GitHub Release
assets under [`mobile-mipi-raw-iq-2026-10-21`](https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21).
They are split into parts smaller than 2 GiB, which keeps the Git repository
small and avoids Git LFS storage charges.

`RAW_IQ_RELEASE_MANIFEST.json` records every original byte count and SHA-256,
plus the byte count and SHA-256 of every release asset. The manifest contains
no local workstation paths.

## Download and reconstruct all captures

```bash
python raw_iq/download_raw_iq.py --parts-dir raw_iq_parts
python raw_iq/assemble_raw_iq.py --parts-dir raw_iq_parts --output-dir data
```

Use one or more `--dataset DATASET_ID` options to download or assemble only a
subset. Dataset IDs are listed in the manifest.

## Binary interpretation

- Headerless interleaved I, Q samples
- Big-endian signed 16-bit component values (`>i2` in NumPy)
- Four bytes per complex sample

RF center frequency, receiver bandwidth, and sample rate are not embedded in
the `.rIs` bytes. Rates in the manifest are measurement metadata inferred from
the established filenames and analysis configuration.

## Maintainer packaging command

`package_raw_iq_release.py` accepts one `--source DATASET_ID=PATH` argument per
dataset. It streams the captures, creates 1,900 MiB parts, and generates the
manifest without loading a capture into memory.
