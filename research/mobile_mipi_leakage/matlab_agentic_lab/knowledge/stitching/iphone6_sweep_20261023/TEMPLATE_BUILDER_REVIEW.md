# Template builder audit and integer-branch search

2026-10-23. Read-only review of buildIphoneStitchTemplates.m, sampleGuardedIqFft.m and estimateStitchFrameModel.m. No MATLAB execution by this reviewer.

## Code conclusions requiring action

1. **No phase-sign correction is needed in the current builder.** With a fixed affine per-band period, removing phasePrediction(k), then multiplying exp(-j theta*u), is consistent. Training frames0:7 and test frames16:23 are separated. Since this builder uses one fixed period and no nonlinear warp, the additional nonlinear LO-warp term discussed in PERIODIC_TEMPLATE_HARMONIC_MAP.md is not missing here.
2. **Model validity must travel with the coefficients.** unwrap(phases(train)) can choose an arbitrary phase history if frame correlations are poor or increments are near the wrap boundary. A returned FFT does not certify one coherent source class. Preserve existing train/test phase residuals and coherence and mark the output provisional/invalid when those fail the selected error budget. Do not silently repair held-out phases.
3. **Fixed first-frame DC removal is not source identification.** The first-frame mean can include wanted energy near the tuned center. Retain this preprocessing as a labelled variant and, where it changes the result materially, compare a no-DC control. The current metadata correctly records the removed complex value; it should not be described as a measured receiver-only spur.
4. The lag-fit intercept need not be added to all start coordinates for this model: omitting a common constant is a source-origin choice, and the builder re-estimates relative phases at its chosen origin. Do not add a varying per-frame held-out timing correction under the guise of applying that intercept.
5. Display interpft/percentile scaling has no effect on the saved FFTs. Those independently scaled images cannot be used as a common-scale amplitude-gain measurement.

## Integer branch seed

Let alpha_b=theta_b/(2*pi). With anchor a, the proposed seed

centerBin_b = round(fc_b*T_b + alpha_b - fc_a*T_a - alpha_a)

is the appropriate **nominal relative harmonic-index guess**. It estimates q_b-q_a under the common-Floquet model. Use frequencies in Hz and periods in seconds. It is not an established branch when actual LO/readback errors are unknown.

A search of +/-16 bins at approximately60 Hz frame rate spans approximately+/-960 Hz; +/-32 spans+/-1920 Hz. If uncertainty exceeds that interval, reaching a boundary is a failed bounded search, not a uniquely estimated answer.

For candidate integer correction h, place the incoming coefficients as

B_h[j] = P_b[j-(centerBin_b+h)].

Use only bins in both bands' valid support. Native usable support is defined by |(k+alpha_b)/T_b| within the accepted analog/DDC band, with edge exclusions. Carry that mask through the integer map. An RF filename center alone does not define a proof of usable support.

## Why magnitude-only top3 can fail

Magnitude spectra discard the very phase information needed to identify a wideband waveform. A concrete counterexample is flat-magnitude coefficients with random phases: every frequency shift has the same magnitude pattern, while only the true shift gives a coherent complex alignment. Repeated line combs also create many near-equivalent magnitude peaks. Receiver passband slopes, narrow spurs and unequal noise floors can instead create a wrong apparently sharp peak.

Magnitude correlation is therefore a useful *ranking heuristic* only. Do not reject all but top3 if the scores are flat, tied, periodic or dominated by one tone. Preserve the seed and expand the complex search in ambiguous cases. Log-spectrum clipping/detrending can reduce envelope/spur dominance but is another explicitly recorded preprocessing choice, not proof of identity.

## Bounded practical search

- Start with the bounded33 or65 integer candidates around the seed.
- For an inexpensive phase-sensitive shortlist, use several fixed contiguous frequency chunks within the usable overlap, rather than magnitude alone. For example, three separated32768-bin chunks cover approximately1.97 MHz each at60 Hz. Compute each candidate's complex cross-correlation on a zero-padded65536-point grid, combine magnitude scores at a common delay, and retain the best few candidates and ties. This remains a heuristic if the selected chunks contain no useful information; expand to the full overlap when scores are ambiguous.
- Alternatively, run full-overlap complex cross-correlation for every integer candidate. Streaming one candidate at a time bounds memory and avoids a branch-shortlisting failure. A full2^21 correlation vector is16 MiB in complex single, before workspace; do not store all candidate vectors.
- For a selected candidate, use the full overlap cross-spectrum and fractional-delay refinement. With

\[
r_h(d)=\sum_j B_h[j]A[j]^*e^{j2\pi jd},
\]

choose d maximizing |r_h| and phi=arg r_h(d). The aligned incoming coefficients are

\[
B_{h,aligned}[j]=B_h[j]e^{j2\pi jd-j\phi}.
\]

When packing a contiguous frequency segment into an FFT, its starting-bin carrier contributes a phase factor. Either restore it when interpreting phi or apply the correction using the same packed-index convention; mixing the two conventions produces a scalar-phase error.

## Held-out score must remain a prediction

Fit branch h, delay d, phase phi, any optional scalar gain, masks and spectral weights on training coefficients only. Freeze all of them for testFFT.

Report at least:

- normalized complex coherence magnitude;
- residual phase angle of the complex inner product;
- normalized complex prediction error, with the training gain/phase still frozen;
- runner-up branch scores and ambiguity gap;
- evidence spread over frequency, not just one tone;
- raw per-frame phase/timing prediction residuals already saved by the builder.

Coherence magnitude alone hides a global phase error. Re-optimizing phase, delay or branch on held-out templates turns validation into another fit. Also, same-screen held-out frames may not distinguish a genuine symmetry of repeated text rows or a clock comb; report that ambiguity even if every repeated frame reproduces it.
