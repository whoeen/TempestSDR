# MATLAB RF signal-processing baseline

This folder implements the RF-analysis role of the smartphone leakage study. It
reads the original RIS captures without modifying them. The licensed R2026b runtime has executed **11/11 passing numerical tests and all
three measured baselines**. See `../results/licensed_baseline_20261022/REPORT_KO.md`
for P1/P4/P8 images, intermediate measurements and remaining limitations.

## Run

In MATLAB, add this folder to the path and run:

```matlab
testResults = runtests("testMobileBaseline.m");
assert(all([testResults.Passed]));
summary = runMobileBaseline();
```

`mobileResearchNotebook.m` is the plain-text live notebook. It shows the device
configuration, numerical tests, and resulting synthetic figure in the Live Editor.
`runMobileBaseline(configPath, outputRoot)` accepts a complete JSON configuration.
Create one with `cfg = mobileBaselineConfig(); writeJsonFile("config.json",cfg)`.
The default file search order is `TEMPEST_DATA_ROOT`, the research `data/` folder,
the existing Desktop/mobile/0625 directory, then Downloads. Existing benchmark
images and their parameters are retained.

The three initial captures are LG X2 at 344.8 MHz, iPhone 6s at 311 MHz, and Galaxy
S4 LTE at 111.9 MHz. The 171.5 MHz Galaxy capture remains available in the release;
this baseline intentionally uses the 111.9 MHz capture matching the established
historical three-device benchmark. Galaxy A7 (2018) is a future measurement target,
not an available fourth capture or a source of inferred timing constants.

## What is produced

Every run creates a fresh UTC-named folder beneath `outputs/`:

| Artifact | Meaning |
|---|---|
| `config.json`, `summary.json`, `notes.jsonl` | Inputs, exact parameters, completion/failure status and environment |
| Device `metrics.json`, `notes.jsonl` | Source byte range/hash, acquisition metadata, each processing stage |
| `01_iq_am_phase.png` | Raw I/Q, observed envelope, amplitude-masked adjacent phase |
| `02_welch_psd.png/.csv` | Raw and mean-DC-removed diagnostic PSD, in counts²/Hz |
| `03_multiscale_stft.png` | Quarter-row, row and 16-row windows, explicit ENBW and time span |
| `04_envelope_candidates.png` | Envelope spectrum, autocorrelation candidates, cyclic probes in JSON |
| `05_parametric_psd.png`, models JSON | AR4/8/16/32 and held-out chronological prediction error |
| `06_frame_candidates.png/.csv` | 0.4 s bounded envelope stream; low-rate candidates, including alias caveat |
| `P001/P004/P008_*` | Nearest vs cubic fractional AM, coherent amplitude, phase HSV |
| `frame_parameters.csv` | Per-frame input SHA-256, time shift, global/row phase fit, held-out row consistency |
| `frame_progression.csv` | Coherent/incoherent changes as P increases; no ground-truth fidelity claim |
| `column_phase.csv` | Phase and consistency of each vertical raster column |
| `raster_final.mat` | Numerical arrays and active crop, not just presentation PNGs |
| `synthetic/` | Known weak AM/PM plus strong clutter: SVD failure mode and coherent averages |

Initial raw analysis is bounded to 2²⁰ complex samples. Raster analysis streams up
to eight complete frames, and slow-envelope analysis streams at most 0.4 s. Whole
captures are not loaded into memory. Each initial block and every raster block
gets a SHA-256 of the original bytes. The existing full-file release hash is
recorded as expected provenance, not falsely described as verified during every
run. Set `verify_full_file_hash=true` to verify the entire capture again.

## Toolbox availability

The built-in `pwelch`, `spectrogram`, `arburg`, and `resample` implementations are
used when available. A base MATLAB path is included because the detected local
installation initially contained MATLAB and MATLAB Copilot only:

- Explicit Welch and STFT PSD, periodic Hann, exact `Fs * sum(w.^2)` scaling.
- Yule-Walker AR with a documented small diagonal regularizer and held-out error.
- Windowed-sinc FIR decimation with delay compensation and saved coefficients.
- Base MATLAB `svd`, complex raster interpolation, image export, statistics.

These alternatives are labeled in output metadata; they are not represented as
the corresponding Toolbox implementations. `testMobileBaseline` checks tone
power/PSD integration, one-sided scaling, complex phase preservation, input byte
order, fractional time evaluation, and lossless byte-order export. Static Code
Analyzer success does not replace these runtime checks.

`conditionIq` is an **optional explicit experiment**, not an automatic cleaning
step. It supports signed-frequency DDC, filtered decimation, specified complex
notches, and AR whitening from a separately provided training vector. A strong
spectral line may contain the wanted modulation. No notch or whitening is applied
to real captures by the default driver.

## Optional RPCA and matched-subspace experiments

The baseline retains the full reference outputs. Explicit bounded decomposition
experiments can be run on a chosen matrix with its axes recorded:

```matlab
[lowRank, sparsePart, residual, meta] = separateRpca(double(roi), ...
    MatrixAxes="spatial raster: selected rows x selected columns", ...
    OutputPrefix="rpca_roi");

[clutterBasis, trainingMeta] = learnClutterSubspace(independentBackground, 4, ...
    "independent blank capture ID, SHA and sample range");
[target, nuisance, residual, meta] = separateMatchedSubspace(observations, ...
    targetReferenceBasis, NuisanceBasis=clutterBasis, ...
    TargetProvenance="independent controlled display pattern reference", ...
    NuisanceProvenance=trainingMeta.training_provenance, ...
    OutputPrefix="matched_hypotheses");
```

RPCA is bounded to 65536 matrix entries by default because it iterates SVD. It
exports low-rank, sparse, residual, singular spectra, convergence history and
sparsity diagnostics. These component names do not assign MIPI/panel identity.
Matched subspace requires documented reference bases and rejects non-identifiable
overlapping hypotheses. For nonorthogonal bases, target/nuisance energies need not
add and a high condition number signals sensitivity. No trustworthy independent
target reference has yet been supplied for automatic three-device classification,
so these functions are deliberately explicit, fully callable experiments.
The test suite includes a known two-tone target/clutter separation, rejection of
identical bases, and a low-rank plus sparse synthetic recovery check.

## Interpretation limits

- `Fs / (fh * raster_columns)` is samples per **chosen raster column**. It is not
  a verified number of measured samples per physical display pixel.
- The prior timing/crop comes from the established benchmark; it is a hypothesis
  to validate against drift, alternative periods and independent captures.
- IQ impropriety or I/Q covariance can be real modulation, not receiver error.
- Mixture phase is not calibrated MIPI symbol phase; an amplitude mask is a
  reliability heuristic, not a probability or SNR estimate.
- Phase HSV maps IQ angle to hue. It does not restore the display's original RGB.
- Coherent alignment can reinforce clutter. An odd/even AM correlation measures
  repeatability, not image fidelity. Row-phase fit is assessed on disjoint rows,
  but all rows still share the same observed mixture reference.
- A column sampled down an image crosses many noncontiguous RF times. Its FFT
  must use the row rate if interpreted as a cross-row sequence; it is not a raw
  RF STFT at the original IQ sample rate.
- The slow envelope uses rectangular integration. Its residual aliases and
  harmonics make frame frequencies candidates, never automatic labels.

## TempestSDR byte-order export

On Windows, the existing TempestSDR native int16 input expects little-endian
interleaved IQ. The lab RIS files are big-endian. Convert a bounded copy:

```matlab
metadata = exportRisForTempest(inputRis, outputIq16le, sampleRate, ...
    FirstSample=0, SampleCount=2^24);
```

The function refuses an existing destination or the source path. It preserves
every signed I/Q value, writes a new little-endian file, and adds a sidecar with
sample rate, range, duration and input/output SHA-256. No resampling occurs.

The current native RawFile implementation reads blocks of 512×1024 scalar values,
or **262144 complex samples**, and loops at EOF. For a chosen playback duration,
explicitly use `count = floor(sampleRate*durationSeconds/262144)*262144` and pass
that count. The exporter records any partial trailing block and never silently
pads or trims it. A replay after EOF is the same data, not another independent
measurement frame for coherent averaging or quality metrics.

## Research notebook and sources

See `../knowledge/signal_processing/` for the acquisition/analysis reasoning,
source records, explicit claims and reading log. The downloaded Toolkit's
statement that MATLAB does not support WVD conflicts with current official
MathWorks `wvd` documentation; the correction is recorded there.
