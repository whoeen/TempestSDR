# RF cycle candidate audit — implementation note

## Entry point

`auditIphoneRfCycleCandidates.m` reads the 11 immutable iPhone 6 sweep captures through `resolveIphoneSweepCapture` and `readRisIqBlock`. Authoring/static review is complete; this agent did not run MATLAB.

```matlab
addpath('path/to/matlab_agentic_lab');
report = auditIphoneRfCycleCandidates();
% Short smoke run or an independent new output directory:
report = auditIphoneRfCycleCandidates(CentersMHz=[100 160], ...
    SampleCount=2^20, OutputDirectory="new/path/rf_cycle_smoke");
```

An existing output directory is refused. Default output is `results/iphone6_followup_20261024/rf_cycle_candidates`.

## Fixed measurements and diagnostic references

- Fs = 124,082,800 complex samples/s, user reported. Acquisition bandwidth = 120 MHz, user reported. No receiver calibration accuracy was provided.
- Row guide = 1100 samples = 8.8650481775 microseconds; guide frequency = 112,802.545455 Hz. The reconstruction analysis raster has 1881 such lines/frame, giving 2,069,100 samples/frame. These are observed reconstruction timing guides, not authenticated panel/packet timing.
- Both `fc + f_baseband` and `fc - f_baseband` are recorded as RF coordinate alternatives. No choice of I/Q polarity is forced.
- DC is retained in every PSD. Peaks within 20 kHz of baseband DC are flagged as DC/LO candidates and excluded from comb fitting, without claiming their physical origin.

## Analysis

Default train and holdout blocks contain 2^22 samples each; the holdout starts near 65% of each capture and must be disjoint. Welch uses a periodic Hann window of 2^17 samples and 50% overlap. A second Hann estimate over the entire block refines selected peak positions. Integrated long-window PSD must agree with window-weighted time power within 1e-5.

Training peaks use a local median/MAD threshold and bilateral flank-median excess, followed by 20 kHz minimum separation. They are paired once to independently detected heldout peaks. Overlapping receivers group repeated absolute RF peaks within 8 kHz. Each group records its source centers, frequency spread and heldout persistence.

Pair differences divided by integer candidates produce free-offset comb and zero-offset harmonic fits. The 60.03 MHz, 20.01 MHz and 240.12 MHz candidates are explicitly labelled conditional protocol hypotheses. Their inclusion is not measurement evidence. Final inlier fits are recomputed before reporting conditional standard errors; candidates that fail the final residual gate are rejected. Heldout data never select the training model or refit its spacing, intercept or tooth indices. Per-center fits give a separate consistency check.

## Outputs

Each center has training/heldout peak CSVs, Welch PSD MAT, metadata JSON and a PSD/modulation-guide PNG. Each RF polarity has peak CSVs, cross-center-group CSV, comb-candidate CSV, independent-center-fit CSV, JSON including tooth memberships and residuals, and a combined PSD/comb PNG. Raw IQ is not copied into results.

## Limits and expected cost

- Default raw input read: 352 MiB across 22 blocks. Temporary memory is expected to be a few hundred MiB. Runtime is unmeasured; approximately 2–5 minutes plus plotting is a planning estimate, depending on MATLAB and storage.
- Default long FFT bin spacing is about 29.58 Hz, but Hann mainlobe width is about 118.34 Hz. A roughly 60 Hz frame sideband is not cleanly resolved by this block. Fractional peak interpolation does not add spectral resolution.
- The local excess is neither topographic prominence nor SNR. Peak error floors and conditional fit standard errors omit absolute receiver calibration and model-search uncertainty.
- Detection thresholds can miss weak, dense or broad information-bearing structure. A stable comb can belong to periodic clutter; neither its presence nor the largest score proves MIPI, a byte clock, a D-PHY lane count, screen synchronization or useful stitching coherence. Subharmonic aliases remain possible.
- Cross-center overlap consistency and temporal persistence are separate checks. A partially available heldout group can average a subset of receivers; its same-subset frequency change is reported separately.

## Static review

The row/column timing reference was corrected to 1100 samples/line and 1881 lines/frame. A reserved MATLAB keyword variable was renamed before execution. Reader/resolver/PSD helper signatures were checked. No MATLAB invocation or raw-file mutation was performed by the authoring agent.
