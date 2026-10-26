# iPhone 100/160 MHz pair: toolbox TF controls

Date: 2026-10-26. Code authoring and static review are complete; root owns MATLAB execution. An executed manifest, not this note, establishes that each transform ran.

## Purpose

Compare the same canonical sample coordinates before and after independently fitted timing/CFO processing. Preserve an unresampled ADC STFT control so that interpolation is visible. This helper fits no timing, CFO, delay, phase, display image, or cross-band RF alignment and cannot establish successful stitching by itself.

The Oct26 driver will predeclare nominal RF **106 MHz**, based on the existing narrow-overlap observation, without searching these TF outputs. The general helper default remains130 MHz for geometrical midpoint diagnostics, so the wrapper must pass106 explicitly. Axes follow the caller polarity and nominal receiver centers. This run conjugates original I+jQ (iq_polarity=-1) and subtracts one fixed training-frame DC; even tfNative retains these two preprocessing steps. It is native-rate/unresampled, not original ADC bytes. After CFO derotation they are corrected nominal RF coordinates, not a calibration of hardware frequency/polarity or proof of a source identity.

## API

Function: plotIphonePairTf.m in the laboratory root.

    rawCell = {a.tfRaw,b.tfRaw};
    correctedCell = {a.tfBoth,b.tfBoth};
    metadata = struct;
    metadata.nominal_fc_hz = [100e6 160e6];
    metadata.native_cell = {a.tfNative,b.tfNative};
    metadata.native_fs_hz = [124082800 124082800];
    metadata.raw_description = 'Fixed prior canonical-grid resampling';
    metadata.corrected_description = 'AM time mapping plus per-band CFO';
    options = struct('SubbandRfHz',106e6,'Decimation',16, ...
                     'DisplayNyquistFraction',0.75);
    manifest = plotIphonePairTf(rawCell,correctedCell,Fs_grid, ...
                               outputDir,metadata,options);

This is an API example: the wrapper must use actual fields and actual Fs from the saved timing MATs. Attach source paths/hashes, representation/endian, frames, native/canonical start coordinates, physical query-time mapping, correction units, code revision and input statuses. Each before/after pair must have equal length and the same uniform grid. Fs may be scalar or two-element; no simultaneous cross-band sampling is assumed. Metadata is copied except native_cell (sample data).

An existing output directory is rejected. Actual Signal Processing Toolbox stft, fsst, resample, hann and freqz are required. CWT absence/license/API failure is explicitly logged per band.

| Option | Helper default | Meaning |
|---|---:|---|
| MaxNativeSamples | 131072 | Bound canonical input; native control has same nominal duration |
| NativeWindow/NativeHop/NativeFft | 1024/256/2048 | Periodic Hann STFT |
| SubbandRfHz | 130e6 | Driver overrides106e6 before looking at outputs |
| Decimation | 8 | Driver overrides16 to stay inside shared measured support |
| ResampleN/ResampleBeta | 32/8 | Kaiser FIR order2*n*q |
| MaxSubbandSamples | 8192 | Central retained output after FIR support guard |
| SubbandWindow/SubbandHop | 256/64 | Same Hann for STFT and FSST; FSST compulsory hop1 |
| DisplayTimePool | 8 | Average TF magnitude columns after transform, not signal decimation |
| DisplayNyquistFraction | 0.8 | Driver overrides0.75 to stay inside guarded common support |
| PhaseGateQuantile | 0.25 | Raw quantile freezes one threshold for both states |
| PhasePlotSamples | 1024 | Displayed central phase excerpt; full analyzed phase stored |
| DynamicRangeDb | 60 | Fixed range below shared transform maximum |
| EnableWavelet | true | Optional CWT |
| CwtVoices/CwtTimeBandwidth | 12/60 | Analytic Morse gamma3, zero extension, both signs |

## Definitions

### Wideband STFT

Native-rate means no interpolation in this run; it still has upstream conjugation and fixed DC subtraction, logged in the wrapper. No additional mixer, DC subtraction, detrend, gain normalization, clipping, envelope demodulation, or lowpass is applied. Native ADC, canonical prior-grid and corrected vectors are separately transformed using their actual Fs. Native window/hop sample counts are scaled to approximately match the canonical physical durations.

For complex two-sided coefficients S and window w:

    PSD = abs(S).^2 / (Fs * sum(w.^2))

Units are input amplitude unit squared per hertz, not dBm. There is no factor2. Window duration Nw/Fs, hop/Fs, ENBW=Fs*sum(w.^2)/sum(w)^2, and FFT spacing Fs/Nfft are saved. FFT zero padding changes bin sampling, not resolving power. One scale is shared across both bands/all states.

### Selected subband and antialiasing

At local canonical time t=n/Fs, mix by exp(-j*2*pi*(selectedRf-fc)*t); use the same carrier convention for both states. Toolbox resample designs one FIR and corrected data reuses its exact coefficients. Group delay compensation is not an extra physical timing fit. Discard ceil((Lfir-1)/(2*q))+2 output samples at each edge, then select the same central at-most8192 outputs. Record the time offset (firstOutputIndex-1)/Fs_small. No endpoint detrend or periodic extension is used.

For expected Fs_grid about125.765MS/s, driver q16 gives digital Nyquist halfwidth about3.930MHz. RF106±3.930MHz is inside both nominal120MHz measurements. The displayed 0.75 fraction gives RF103.052–108.948MHz, inside the3MHz-guarded shared region. The FIR transition remains part of the numeric record. These figures discard most of the capture; only wideband STFT retains the original digital band.

A deterministic complex-tone check runs through the same FIR: pass frequency0.2Fs_small and stop frequency0.75Fs_small. Require pass gain within1e-3, phase error below1e-6rad, ripple below1e-6, and stop amplitude below1e-3 after support guards. A failure stops the helper. This validates AA/time-origin accounting, not RF SNR or hardware response.

### FSST

Use actual fsst in double precision with the same256-point periodic Hann as the selected-subband STFT. FSST fixes FFT length=window length and hop1. Its magnitude is displayed relative to one maximum across bands/states. It is not PSD, and its colors must not be numerically compared with STFT colors. Display pooling happens after all transform coefficients are computed.

Squeezing reallocates measured transform information. It does not create missing RF bandwidth or undo AA filtering. No ridge is promoted to a CFO measurement.

### Optional CWT

Use actual cwt: analytic Morse(gamma3,time-bandwidth60),12 voices/octave, Boundary='zeropad'. Request absolute offsets32*Fs_small/N to0.75*Nyquist in the driver. Both complex-input pages are retained (positive and negative frequencies). Plot their signed, nonuniform physical frequency coordinates using surf viewed from above. NaNs explicitly mark the unanalyzed DC gap. Cone-of-influence lines apply to both signs; offsets nearer DC than the boundary are susceptible to edge effects. No periodic closure is assumed.

CWT L1 magnitude has its own shared scale, not PSD. CWT can fail independently; manifest.wavelet_complete and per-band errors preserve this distinction.

### Phase

Analyze the same anti-aliased mixed subband. The raw-amplitude quantile threshold is frozen for both states. Mask phase below it. The first above-threshold raw sample is the reference for both states. Save raw/corrected amplitudes, wrapped relative phases in radians, angle(corrected.*conj(raw)), masks and reference/threshold metadata. The difference is masked unless both amplitudes pass.

This is relative measured RF phase, not screen RGB or absolute physical phase. Time mapping can change the physical samples being compared; phase change combines remapping and CFO derotation and is not by itself a clock or CFO estimator. A gate is a heuristic, not a confidence level.

## Resolution and limits

At expected Fs_grid≈125.765MS/s, the wideband1024 Hann spans≈8.14us (ENBW≈184kHz). With driver q16, the subband256 Hann spans≈32.57us (ENBW≈46.1kHz; FFT spacing≈30.7kHz). These are row-scale exploratory views, not sub-kHz CFO resolution. The source excerpt lasts about1.04ms. The retained q16 output has fewer than8192 samples after guards, and its actual count/duration are recorded. Fine clock/CFO evidence must come from the timing driver's longer observations. Invisible change here does not invalidate a fine CFO estimate; a sharp ridge does not validate it.

Before/after arrays reuse data, so this is a processing control rather than an independent heldout test. Native/canonical axes show time from their respective chunk starts; consult caller physical-query metadata before treating them as simultaneous.

## Outputs / execution checks

Per band: wideband STFT PNG, subband STFT/FSST PNG, optional CWT PNG, wrapped-phase PNG, phase CSV, numeric MAT (TF matrices, FIR, phase/masks, parameters). No full capture is copied. tf_metrics.csv lists actual windows, ENBW, FFT spacing, gates, AA result and CWT status. Manifest starts running and ends complete after writes; complete can coexist with wavelet_complete=false.

Root should run checkcode, execute the wrapper in the toolbox-enabled worker, check AA test/CWT status/shared scale validity, then inspect both100/160 visual outputs. Preserve the outputs alongside the timing/heldout report. Do not relabel TF diagnostics as successful image recovery or successful RF stitching.

## Primary API references

Read2026-10-26, R2026b pages:

- [MathWorks stft](https://www.mathworks.com/help/signal/ref/stft.html): centered complex output; window/overlap/FFT syntax.
- [MathWorks fsst](https://www.mathworks.com/help/signal/ref/fsst.html): centered complex output; window length equals FFT size; hop1.
- [MathWorks resample](https://www.mathworks.com/help/signal/ref/resample.html): FIR AA, delay compensation, coefficient reuse, zero boundary extension.
- [MathWorks cwt](https://www.mathworks.com/help/wavelet/ref/cwt.html): two complex pages, L1 normalization, zero extension supported sinceR2026a, cone of influence.

Local skills: matlab-analyze-time-frequency-content and matlab-prepare-signal-data. API advice was checked against primary sources above. No full documentation or paper text is copied into this note.

## Final wrapper

Run runIphoneTf26 with no arguments after the timing driver. It loads only tfRaw/tfBoth/tfNative/meta from timing/band_fc100.mat and band_fc160.mat, plus the saved model, and writes the new tf/ directory. It passes106MHz, q16 and0.75 display fraction explicitly. Full timing metadata is carried into the TF manifest. Root checkcode passed the first helper version; subsequent labeling edits and this wrapper still require the root execution gate.

## Independent static review

The chapter agent reviewed mixing, exact FIR reuse, two-sided PSD, phase gate, time offsets, native Fs/window scaling and found no concrete math/syntax fault. It flagged original-IQ wording, now corrected: native-rate data have upstream conjugation and fixed DC subtraction. No reviewer executed MATLAB; the root worker owns numerical verification.
