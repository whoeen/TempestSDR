# Independent review: stitchIphonePair26

2026-10-26; static read only by stitch_validation_design. No MATLAB execution by this reviewer. File reviewed: lab/stitchIphonePair26.m,189lines at review time.

## Result

No concrete syntax, filter-gain, delay-sign, or FFT-index fault was found in this version. This is not a numerical pass or a successful RF-recovery claim.

- Lines148–151: fourth-order low/high Butterworth filters are created separately at the same physical crossover and actual synthesis sample rate. zp2sos returns a section matrix and separate gain.
- Lines152–155: freqz(sos,4096,fs) is documented for a section matrix. Multiplying by the separate scalar gain before taking magnitude squared is correct. The sum abs(gLow*low)^2+abs(gHigh*high)^2 tests the effective zero-phase forward/backward responses; it is not summing one-pass complex filters.
- Lines170–174: filtfilt(sos,g,padded) is the documented SOS/gain form and applies the gain in both passes. Periodic guards are removed consistently. This is actual toolbox IIR execution, unlike the original Oct23 FFT-only weights.
- Lines113–125: the narrow band's global harmonic span is shorter than its correlation FFT length, so modulo packing has no collisions. Using centered k only in the fractional-lag magnitude objective is valid; returning to actual global k when computing phase preserves phase transport. cross=B*conj(A), positive delay ramp and negative fitted phase match the earlier audited convention.
- Lines142–166: the lower-edge harmonic reference and centerB place both spectra on one positive-analytic synthesis grid. FFT/N coefficients are reconstructed by ifft(...)*N. LP crossover is the physical midpoint of the pair's nominal overlap relative to that grid origin.
- Lines51–65: display limits come from the raw-arm training waveform and remain fixed across arms. Assessment data are not used to select these display limits.

## Limits retained

The IIR is redesigned at actual power-of-two synthesis Fs=N/T (about503MHz), which is not the original paper pair's360MHz digital filter design. The numerical response and metadata must therefore be described as the actual-grid variant. Forward/backward magnitude equivalence does not prove physical continuity across a periodically padded frame. Numerical padded-boundary checks from prior code support the guard choice but are not a new measurement.

The unmasked103–109MHz narrow fit drives synthesis; the training-selected tone mask is a separate diagnostic. A good narrow coherence cannot automatically validate the full54MHz overlap or the entire union. The report correctly preserves rf_stitch_validated=false and explicitly states that the result is an attempted stitch.

Time/phase correction upstream and overlap fitting must retain their train/assessment provenance. This reviewer did not independently execute or inspect all inputs of the timing driver.

## Primary API evidence

Read2026-10-26:

- [MathWorks freqz](https://www.mathworks.com/help/signal/ref/freqz.html), Syntax/Description: SOS input and physical-frequency n,Fs form.
- [MathWorks filtfilt](https://www.mathworks.com/help/signal/ref/filtfilt.html), Syntax/Description: SOS plus separate gain and forward/reverse squared-magnitude response.
