%[text] # Smartphone leakage: auditable MATLAB baseline
%[text] This notebook starts from complex raw IQ and keeps amplitude, phase, sampling rate, receiver bandwidth and timing hypotheses distinct. A stable vertical stripe may be desired modulation or clutter; stability alone cannot identify its physical source.
%[text] Open this notebook with signal\_processing on the MATLAB path. The first run reads LG X2, iPhone 6s and Galaxy S4 LTE captures from TEMPEST\_DATA\_ROOT or the configured local folders. It writes new timestamped results and JSONL notes.
cfg = mobileBaselineConfig();
disp(struct2table(cfg.devices))
%%
%[text] ## Verify the byte order and numerical conventions
%[text] These tests check signed big-endian IQ, PSD power calibration, fractional time evaluation and complex phase through downconversion. They do not establish image fidelity.
testResults = runtests("testMobileBaseline.m");
disp(table(testResults))
assert(all([testResults.Passed]),"Resolve numerical tests before interpreting measurements.")
%%
%[text] ## Run and inspect intermediate results
summary = runMobileBaseline();
disp(summary.run_root)
%%
%[text] ## Known weak AM/PM in strong clutter
%[text] The synthetic experiment knows its carrier and repeating pattern. Those quantities must be estimated and independently validated for real smartphone measurements. Phase HSV is a visualization of complex IQ, not recovered display RGB.
demoImage = imread(fullfile(summary.run_root,"synthetic","synthetic_weak_am_pm.png"));
image(demoImage)
axis image off
%%
%[text] ## Continue with evidence
%[text] Inspect each device's 01 IQ plot, 02 calibrated PSD, 03 multiscale STFT, 04 line candidates, 05 held-out AR comparison, 06 slow-envelope candidates and P001/P004/P008 rasters. Each notes.jsonl records exact parameters and byte ranges; metrics.json distinguishes mixture coherence from image fidelity.

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
