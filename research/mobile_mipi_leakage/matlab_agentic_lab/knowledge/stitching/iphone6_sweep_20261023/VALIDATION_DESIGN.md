# iPhone 6 11-band stitching: validation and implementation design

Date: 2026-10-23. Status: design based on inspected local code and prior source notes; no MATLAB execution or new capture analysis was performed by this reviewer.

## 1. Scope and evidence

The user reports iPhone 6, a static black-text test screen, USRP-2940R with nominal 120 MHz instantaneous bandwidth, probe reception, no LNA/BPF, and clamped phone/probe positions. The eleven requested centers are 100:60:700 MHz. These are user-reported acquisition settings; actual IQ sample rate, readback RF center, useful passband, receiver gain, retune settling, overflow status and IQ format must come from capture records or remain unknown. A fixed clamp reduces position variation but does not lock the phone and receiver clocks or the retuned LO phase.

This design follows the existing authored Chapter 4/5 reading notes and convention audit, not a new claim of reading every page of the newly attached excerpt. Relevant local sources:

- ../reading_061_108.md: Chapter 4, time/phase correction, complex averaging.
- ../reading_109_155.md: Chapter 5, pp. 109–130; Eqs. 5.7, 5.14/5.17/5.20, 5.35 and Algorithm 4; limitations p. 134.
- ../verification/verifyStitchConventions.m and convention_audit.json: integer finite-delay sign and crossover algebra tests only.
- ../../../signal_processing/compareRasterAverages.m, sampleFractionalRaster.m, measureFrameCandidates.m.

## 2. Frequency geometry: quantities that must stay distinct

For nominal rectangular 120 MHz bands:

| Quantity | Value |
|---|---:|
| Center span | 700−100 = 600 MHz |
| Adjacent center shift | 60 MHz |
| Adjacent overlap | 120−60 = 60 MHz |
| Relative nominal overlap | 0.5 |
| First band | 40–160 MHz |
| Last band | 640–760 MHz |
| Full nominal union | 40–760 MHz = 720 MHz |
| Two adjacent bands | 180 MHz union |
| Three adjacent bands | 240 MHz union |
| Five adjacent bands | 360 MHz union |

The useful union is narrower if real RF/DDC edge response is rejected. A 120 MHz RF option does not establish Fs=120 MS/s. The original paper's positive-frequency placement/output rate convention can be reproduced; alternatively a complex output centered at 400 MHz needs an output sample rate exceeding the 720 MHz occupied span with transition margin. These are different output conventions and must be logged.

**Critical implementation point:** a 750- or 1100-column raster at approximately 112.8 kHz row rate has only approximately 84.6 or 124.1 MS/s temporal sampling. Sampling a stitched 720 MHz complex waveform directly on that raster aliases most of the collected spectrum. The existing cubic raster interpolator explicitly supplies no anti-alias filter. Preserve a suitable high-rate complex waveform or equivalent frequency grid through stitching, then perform the chosen demodulation and anti-alias filtering before display resampling. A display width is not evidence for the number of original RF samples per physical pixel.

## 3. Bounded experiment matrix

Keep the original raw captures unchanged. Use a shared manifest and distinct outputs for each case.

1. Eleven individual-band baselines: AM, uncorrected complex average, global-phase/CFO corrected coherent average. Frame progression P=1, 4, 8, 16, 32 where duration allows. Preserve full raster before any active crop.
2. Ten adjacent pairs: (100,160), ..., (640,700). Produce common-overlap diagnostics before full pair synthesis.
3. Prespecified three-band groups: 100/160/220; 340/400/460; 580/640/700. These cover low, middle and high RF regions without selecting on final text readability.
4. Prespecified five-band group: 220/280/340/400/460. Optionally add 100–340 and 460–700 if timing and pair quality support them.
5. Full eleven-band synthesis, including the measured weak overlaps, with every edge quality disclosed. If an overlap is unidentifiable, report the resulting graph split; do not imply that two disconnected sub-unions have a recovered relative phase.
6. A validation-selected contiguous subset can be chosen from all 3/4/5-band windows. Freeze the rule and selected set before opening final test metrics.

Nonadjacent pairs lack nominal shared support when separation is at least 120 MHz. Combining their AM pictures is an image-fusion control, not an overlap-identified complex stitch. An interior leave-one-band test removes the positive-width overlap between its neighbors, so it cannot be treated as ordinary redundant validation.

For fair comparison report frames per band, raw time used per band, total capture time used, output bandwidth, demodulation and normalization. Compare equal P per band and retain the best single-band control; do not hide the extra acquisition cost of multiple bands.

## 4. Split and information flow

Use source-time blocks rather than randomly splitting highly correlated samples. Suggested starting split after settling exclusion: first third for training, middle third for validation, final third for test, with a guard at least as long as the longest filter support. If captures are short, use disjoint frame blocks with explicit ranges and retain enough data for all three roles. Repeated or looped raw samples are never independent frames.

- Training: IQ format decision, timing and carrier model, overlap support, nuisance-tone masks, relative delay/phase/gain, filter parameters and display normalization.
- Validation: select timing candidate, interpolation/filter choice, stable averaging length and optional contiguous subset. Record all candidates, including rejected ones.
- Test: freeze parameters and compute overlap residuals and image comparisons on unused blocks.

A fixed initial drift model can be tested by extrapolation. If an online tracker must update on test data, call it adaptive evaluation; estimate tracking from a designated pilot/time/frequency subset and score disjoint data. Fitting phase separately on the entire tested image and then reporting the same image's peak coherence is not independent validation.

The screenshot must not enter carrier/delay/rate estimation, deconvolution, denoising training or stitch weighting. It is an evaluation reference. Geometry registration, tonal calibration and evaluation masks should be established on calibration output and frozen across candidate methods.

The repeated text lines mean that neighboring rows and odd/even images are not independent scene content. Frame inversion or other multi-frame states may also exist: test one-, two- and longer-frame repetition and retain state labels. Odd/even correlation alone can both reward stable clutter and miss alternating valid states.

## 5. Recommended estimation order

1. Validate raw decoding from records and bounded samples: byte order, interleaved I/Q order, clipping, DC, zero blocks, sample continuity, segment hashes. Do not infer Fs from the 120 MHz bandwidth label.
2. Estimate row/frame/burst candidates separately in every band; store samples per period before converting to Hz. Check fractional drift across disjoint blocks. Agreement on a strong periodicity is necessary evidence, not proof of the desired DSI source.
3. Correct source-time drift with a documented input-coordinate map. For every resampling step record input positions per output sample and output/input rate, avoiding ambiguous variable R. Upsampling cannot create information; downsampling requires anti-alias filtering.
4. Move each band onto a common RF frequency coordinate. Distinguish the known 60 MHz tuning shift from small residual CFO. Time warping also changes the frequency coordinate of complex IQ: verify the complete resample/mix order on a synthetic known RF tone instead of assuming a nominal oscillator remains correct after a time warp.
5. Restrict pair fitting to measured shared support, excluding documented edge transients, DC spurs and invalid bins. Keep an unmasked control. Fit delay/phase/CFO/rate jointly or iteratively with a constrained low-dimensional model.
6. Fit a scalar complex gain if supported; then inspect frequency-dependent residual gain/phase. A free complex gain per FFT bin can force noise into agreement and erase the validation question. Any richer transfer function needs regularization and untouched frequency/time validation.
7. Synthesize with complementary crossover responses on a common rate/grid. Save the aligned overlap before weighting and the actual weights. Preserve the first-band initialization branch rather than correlating a band with an all-zero accumulator.
8. Demodulate after synthesis; compare AM with a separately justified coherent-demodulation carrier. Stitch alignment alone does not remove all source carrier phase or establish PM/RGB information.

## 6. Sign conventions and ambiguity

Choose a single convention throughout. For a measured sequence w[n]=exp(j phi) y[n−d], define r[k]=sum_n w[n+k] conj(y[n]). Then the peak occurs at k=d and angle(r[d])=phi. Correct with w[n+d] exp(−j phi), using finite support. This is the convention already checked in verifyStitchConventions.m. With MATLAB's forward DFT, Y/X has phase phi−2 pi f d/Fs for an integer delayed signal. Fit the slope with those units/signs.

For a delayed signal with residual CFO, w[n]=y[n−d] exp(j(2 pi DeltaF n/Fs+phi)), advancing by d changes the phase intercept. The correction oscillator must use the same original/advanced time origin as the fitted model. Test nonzero delay and CFO simultaneously; testing them separately does not expose this intercept error.

A periodic source can have many correlation peaks separated by a row, frame or packet period. A single sinusoid does not identify delay independently from phase. Save the top competing delays, their peak ratio and separation, and the phase slope across usable overlap frequencies. Use frame/burst boundaries and agreement over disjoint subbands to reject aliases. A broad peak or competing valid aliases should be reported as uncertainty rather than resolved using the known text image.

The eleven nominal bands form a path graph: only adjacent pairs have positive-width overlap. There are no independent overlap cycles for a classical closure test. Global least squares on this path alone adds no new redundant information. Use multiple held-out windows/sub-overlaps as repeated edge constraints, bidirectional synthesis, and physical timing constraints; do not advertise a nonexistent cycle-consistency test.

## 7. Required numerical tests before interpreting real-data success

The existing audit proves integer-lag signs and an infinite-response crossover identity. It does not cover the following concrete risks.

| Test | Injected case | Essential observation |
|---|---|---|
| RF frequency coordinate | tones on both sides of DC and both crossover edges | correct common RF location after resample and nominal center mixing; no spectral mirror |
| Finite integer delay | +/− delay and phase | correct sign; no wrap-around samples |
| Fractional delay | several fractional delays including ±0.5 sample vicinity | residual phase slope and waveform error on untouched interior |
| Joint delay/CFO | nonzero delay plus positive/negative CFO | correct phase intercept and de-rotation time origin |
| Clock-rate error | known ppm drift plus fractional initial delay | predicted end-block timing; no gradual text blur |
| Virtual subbands | split one real wideband capture into three overlapping subbands; add known nuisance transforms | reconstruct original held-out complex waveform within measured filter/interpolation error |
| Complementary merge | common signal with unequal scalar gains and additive independent noise | unity deterministic response after calibration; no double-counted overlap gain |
| Finite filters | impulses near and away from block boundaries | explicit valid region; no circular transient interpreted as text |
| Ambiguous source | single tone and repeated packet waveform | detector must retain ambiguity instead of claiming unique delay |
| Wrong-source control | strong synchronous stripes plus weaker independent text-like modulation | distinguish mixture coherence from recovery of the weaker target |

Use virtual-subband tests on an existing capture without changing the raw file. Those tests validate the numerical path and do not establish stability across the eleven sequential retunes.

## 8. Metrics and plots

### Pair-level signal metrics

For aligned complex overlap vectors a and b in a held-out block:

- Complex normalized correlation: C=|sum a conj(b)| / sqrt(sum|a|^2 sum|b|^2). Preserve both raw and documented DC-removed versions if relevant.
- Residual waveform error: ||a−g b||/||a||, with g fitted on training and frozen for test. Also show a diagnostic test-refitted error clearly labeled as such.
- Residual cross-spectrum phase versus RF frequency; fitted delay and departure from a straight line.
- Per-window phase intercept versus source time and its slope (residual CFO); delay versus source time and its slope (rate mismatch).
- Energy-weighted and uniformly frequency-weighted versions: a single bright tone must not dominate every conclusion.
- Reject/retain mask, effective overlap width, valid sample count, top lag candidates and fit uncertainty.

Frequency-resolved magnitude-squared coherence needs averaging across multiple segments/tapers. A single FFT pair gives a trivial ratio of one wherever both are nonzero and is not a useful coherence estimate. Record segment count, length, overlap, window and effective resolution. Bootstrap disjoint time blocks rather than individual correlated samples when estimating intervals.

### Controls and outputs

For each single/group output retain:

1. Native full raster, AM P progression and uncorrected complex averaging.
2. Aligned AM/coherent output with fixed common normalization plus a separately labeled contrast-enhanced view.
3. Nominal-frequency shift only, phase+delay, then phase+delay+CFO/rate correction. This shows which operation produced an improvement.
4. PSD with per-band and stitched frequency support; overlap before/after gain and phase correction.
5. Residual relative phase and HSV with a low-amplitude/coherence mask and explicit phase reference. HSV is measured relative RF phase, not recovered display RGB.
6. Column/row-subtraction or clutter-removal views as secondary controls; they can erase real vertical/horizontal character strokes.

### Image fidelity against this screenshot

The supplied screen contains a large white rectangle and repeated identical text rows on black. A global correlation, PSNR or SSIM can score well after recovering only the rectangle. Report at least two separate regions: gross panel/rectangle geometry and text-only regions excluding broad borders.

Use the same physically plausible global registration across methods (cyclic raster origin, active crop and axis scaling established on calibration data). Freeze this transform before final testing. Do not use per-letter deformation, local optical flow or method-specific geometry to inflate fidelity. Preserve the unregistered image and registration parameters. Repeated lines create a roughly one-text-line vertical ambiguity; report if the registration remains ambiguous.

Recommended metrics on held-out data: text-ROI normalized correlation; gradient/edge correlation; character stroke contrast and edge spread at predetermined positions; SSIM only when the toolbox exists and after fixed intensity/geometry conventions. Absolute PSNR is secondary because RF amplitude is not calibrated display luminance. OCR character error can be supplementary only if a real OCR engine is available and not constrained to the known sentence. Never synthesize, replace or inpaint letters from the provided target.

## 9. Success conditions and stop labels

- Numerical pass: synthetic/virtual-subband transforms are recovered with declared tolerances and valid support.
- Real pair alignment supported: held-out complex overlap improves over nominal-frequency-only control on more than a dominant single tone; timing/CFO estimates remain consistent across windows.
- Wider waveform supported: each included overlap is identified and the resulting spectrum retains added measured support without unexplained crossover steps.
- Better screen recovery supported: held-out text-ROI/stroke detail improves over the best same-P single band under fixed registration and display scaling.

Any of these can pass while the next fails. Stable vertical lines, high AM correlation and high coherent power alone do not prove improved screen content or a MIPI common-mode source. The current fixed pattern can test reconstruction of that pattern; it cannot establish universal transfer to other content or physically identify the emitting circuit.

## 10. Implementation priorities and resource bounds

P0: capture metadata and endian checks; toolbox inventory; individual-band timing and AM controls; one-frame memory estimate.

P1: numerical sign/frequency/rate tests and virtual-subband control; ten pair diagnostics with held-out ranges.

P2: well-supported pairs and prespecified small groups; high-rate synthesis followed by demodulation and anti-alias display reduction.

P3: full eleven-band result and transparent handling of weak links; frozen image evaluation and gallery/report.

A 1 GS/s, 1/60 s complex single-precision frame is about 133 MB before workspaces, FFT buffers and copies. Eleven simultaneously held frames can exceed 1.4 GB, and double-precision FFT workspaces can multiply that footprint. Prefer single-frame/block streaming, incremental synthesis or frequency-domain accumulation with explicit finite-boundary handling. Retain scalar metrics/CSV and curated PNGs in Git; large MAT/IQ remain local or in the authorized data release.

No new MATLAB function was written or executed for this design. Root owns the shared MATLAB session.
