# Guarded fractional IQ sampling

Files: sampleGuardedIqFft.m and sampleGuardedIqFftTest.m. These were authored without invoking MATLAB. Run the test in the shared MATLAB owner session before applying the helper to captures.

## Intended use

    [x,info] = readRisIqBlock(rawFile,firstSampleWithGuards,blockCount);
    q = desiredAbsoluteSamplePositions - firstSampleWithGuards;
    [y,diag] = sampleGuardedIqFft(x,q,GuardSamples=512);

Coordinates are zero-based in the input block, and must be at least GuardSamples away from both ends. Supply double query coordinates to retain fractional precision near index 2 million. Output is complex single, with input I+jQ convention retained. Block length including guards must be at most 2^21 samples (oversampled array at most 2^23). If a requested frame plus guards does not fit, split into overlapping guarded blocks and keep their interior outputs. Never concatenate a raw record cyclically to fabricate guards.

## Method

1. Use measured guard samples on both sides; discard their output.
2. By default taper only the outer guard regions with a quintic smoothstep to zero at the finite-block endpoints. The queried original grid samples are not multiplied by a window.
3. Base MATLAB interpft interpolates the complex data onto a fourfold grid.
4. For each requested coordinate, use the six adjacent grid values at nodes -2 through +3 relative to its floor, with degree-five Lagrange weights. Query chunks of at most 2^17 bound the indexing/weight temporaries.

MATLAB reference: https://www.mathworks.com/help/matlab/ref/interpft.html (accessed 2026-10-23). The vendor describes the uniformly spaced input and periodic-data assumption. Complex single/double input is supported. The finite guard/taper scheme and local Lagrange stage are this project's implementation choices.

## Mathematical limitations

- FFT interpolation implicitly extends a finite input periodically. Measured guards plus taper reduce wrap discontinuity; they are not a universal guarantee of negligible error for arbitrary data. Compare independent raw blocks with 512 and 1024 guard samples before accepting phase-sensitive results, focusing on identical query positions. Increasing the guard must preserve the same measured samples and change only the block margins.
- The six-point Lagrange stage has a frequency-dependent interpolation error. Fourfold upsampling puts a 60 MHz tone at normalized frequency 60/(4*124.0828), roughly 0.121 cycles/grid sample. Synthetic testing reports maximum complex, magnitude, and phase errors across fractional offsets; no unexecuted pass is claimed.
- The original Nyquist endpoints are ambiguous for continuous-time interpolation. Tests stop at +/-60 MHz, below Fs/2=62.0414 MHz. Adding interpolated samples does not add RF bandwidth.
- There is no antialias filter for net downsampling. A small affine timing correction is acceptable only if the occupied band remains below the new Nyquist frequency.
- Conversion to single limits arithmetic precision. Query positions and weight calculations remain double. The diagnostic memory number counts the largest oversampled array, not total peak MATLAB workspace.

## Meaningful verification

Run sampleGuardedIqFftTest(). It checks 11 positive/negative/DC tone frequencies, nine fractional offsets, two +/-60 MHz affine timing cases, integer-grid preservation, and rejection of insufficient guards. Periodic DFT-bin tones isolate local interpolation error; off-bin tones additionally exercise finite-block boundaries. Error limits are unit-amplitude complex-error tolerances: 0.002 periodic and 0.003 finite. These are acceptance gates, not measured performance until MATLAB runs the test.
