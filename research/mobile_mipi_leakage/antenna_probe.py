"""Read-only forensic probe for the three unnamed antenna IQ captures.

The files contain no self-describing header.  This script therefore reports
the measured structure in sample units.  Frequency conversion is included
only under the explicit 124.085710 MS/s iPhone receiver-timebase hypothesis;
it is not capture metadata.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "coherent_results" / "antenna_probe"
DATA = Path(os.environ.get("TEMPEST_DATA_ROOT", ROOT / "data")).expanduser()
FILES = [DATA / f"antenna{i}.rIs" for i in range(1, 4)]


def read_complex(path: Path, first: int, count: int) -> np.ndarray:
    with path.open("rb") as handle:
        handle.seek(first * 4)
        # These captures and the older mobile/0625 captures follow the
        # laboratory RIS2IQ.m reader: signed 16-bit I,Q in big-endian order.
        raw = np.fromfile(handle, dtype=">i2", count=2 * count)
    raw = raw[: raw.size // 2 * 2].reshape(-1, 2)
    return raw[:, 0].astype(np.float32) + 1j * raw[:, 1].astype(np.float32)


def fft_autocorrelation(x: np.ndarray, max_lag: int) -> np.ndarray:
    x = np.asarray(x)
    x = x - x.mean(dtype=np.complex128 if np.iscomplexobj(x) else np.float64)
    nfft = 1 << (2 * len(x) - 1).bit_length()
    spec = np.fft.fft(x, nfft)
    corr = np.fft.ifft(spec * np.conj(spec))[: max_lag + 1]
    overlap = np.arange(len(x), len(x) - max_lag - 1, -1)
    corr = corr / overlap
    return corr / max(float(np.real(corr[0])), np.finfo(float).eps)


def separated_peaks(score: np.ndarray, first: int, count: int = 20, gap: int = 12):
    order = np.argsort(score[first:])[::-1] + first
    selected: list[int] = []
    for index in order:
        if all(abs(int(index) - previous) >= gap for previous in selected):
            selected.append(int(index))
        if len(selected) == count:
            break
    return selected


def analyze(path: Path) -> dict:
    complex_samples = path.stat().st_size // 4
    assumed_fs = 124.085710e6
    count = min(1_200_000, complex_samples // 12)
    starts = np.linspace(0, complex_samples - count - 1, 5, dtype=np.int64)
    max_lag = min(3500, count // 8)
    amp_corr = np.zeros(max_lag + 1, dtype=np.float64)
    iq_corr = np.zeros(max_lag + 1, dtype=np.complex128)
    rms: list[float] = []
    means: list[complex] = []
    quantiles: list[list[float]] = []
    for start in starts:
        z = read_complex(path, int(start), count)
        means.append(complex(z.mean(dtype=np.complex128)))
        rms.append(float(np.sqrt(np.mean(np.abs(z) ** 2, dtype=np.float64))))
        quantiles.append([float(v) for v in np.percentile(np.abs(z), [1, 50, 95, 99, 99.9])])
        envelope = np.log1p(np.abs(z)).astype(np.float32)
        amp_corr += np.real(fft_autocorrelation(envelope, max_lag))
        iq_corr += fft_autocorrelation(z, max_lag)
    amp_corr /= len(starts)
    iq_corr /= len(starts)

    # Ignore very short ADC/filter correlations. Raster-line candidates for the
    # known phone recordings are expected in the hundreds to low thousands of
    # samples, but all rankings remain in sample units.
    first_peak = 180
    amplitude_peaks = separated_peaks(np.abs(amp_corr), first_peak)
    complex_peaks = separated_peaks(np.abs(iq_corr), first_peak)
    peak_rows = []
    for source, indices, corr in (
        ("log_amplitude", amplitude_peaks, amp_corr),
        ("complex_iq", complex_peaks, iq_corr),
    ):
        for lag in indices:
            peak_rows.append(
                {
                    "source": source,
                    "lag_samples": lag,
                    "magnitude": float(abs(corr[lag])),
                    "phase_deg": float(np.degrees(np.angle(corr[lag]))),
                    "frequency_hz_if_iphone6_timebase": float(assumed_fs / lag),
                }
            )
    return {
        "file": str(path),
        "bytes": path.stat().st_size,
        "complex_samples": complex_samples,
        "format_evidence": (
            "big-endian interleaved signed int16 I,Q; no header; confirmed by "
            "Desktop/mobile/0625/Function/RIS2IQ.m and byte-distribution check"
        ),
        "timebase_hypothesis": {
            "assumption": "same 124.085710 MS/s receiver timebase as the prior iPhone 6 capture; unverified",
            "assumed_sample_rate_sps": assumed_fs,
        },
        "chunk_count": len(starts),
        "chunk_complex_samples": count,
        "mean_i": float(np.mean([v.real for v in means])),
        "mean_q": float(np.mean([v.imag for v in means])),
        "rms_mean": float(np.mean(rms)),
        "magnitude_quantiles_mean": np.mean(quantiles, axis=0).tolist(),
        "peaks": peak_rows,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    result = [analyze(path) for path in FILES]
    (OUT / "probe.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    for item in result:
        print("\n", Path(item["file"]).name)
        print("sample-rate hypothesis", item["timebase_hypothesis"]["assumed_sample_rate_sps"] / 1e6, "MS/s")
        print("rms", item["rms_mean"], "quantiles", item["magnitude_quantiles_mean"])
        for row in item["peaks"][:8]:
            print(row)


if __name__ == "__main__":
    main()
