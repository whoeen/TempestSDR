function report = verifyFam26(outputDirectory)
%VERIFYFAM26 Verify FAM coordinates, conjugation, phase and normalization.
% report = verifyFam26(outputDirectory) runs bounded synthetic fixtures only.
% The root agent is the sole MATLAB execution owner. This function creates no
% figures, preserves the caller's RNG state, and refuses an existing output.
% Definitions: NC uses x(t+lag/2)*conj(x(t-lag/2)); conjugate uses the product
% without conj. Both cyclic transforms use exp(-1i*2*pi*alpha*t).
% These tests do not use a display row/frame prior or any recorded capture.

arguments
    outputDirectory (1,1) string = ""
end
if outputDirectory == ""
    outputDirectory = fullfile(fileparts(mfilename("fullpath")), ...
        "results", "iphone6_fam_20261026", "verification");
end
assert(exist("famCycleScout26", "file") == 2, ...
    "verifyFam26:MissingHelper", "famCycleScout26 must be on the path.");
assert(~isfolder(outputDirectory) && ~isfile(outputDirectory), ...
    "verifyFam26:ExistingOutput", "Refusing to overwrite %s.", outputDirectory);
mkdir(outputDirectory);
oldRng = rng;
rngCleanup = onCleanup(@() rng(oldRng)); %#ok<NASGU>
fsHz = 1e6;
M = 64;
L = 16;
P = 2048;
numberSamples = (P - 1)*L + M;
t = (0:numberSamples-1)'/fsHz;
options = struct("M", M, "L", L, "P", P, ...
    "AlphaLimitsHz", [-fsHz fsHz], ...
    "ConjugateAlphaLimitsHz", [-fsHz fsHz], ...
    "FrequencyLimitsHz", [-fsHz/2 fsHz/2], ...
    "TopCandidates", 12, "TopPerPair", 1, ...
    "ChannelWindow", ones(M,1), "SlowWindow", ones(P,1));
f1 = 5*fsHz/M;
f2 = 13*fsHz/M;
nu = 3*fsHz/M;
phase1 = 0.23;
phase2 = -0.61;
amplitude1 = exp(1i*phase1);
amplitude2 = 0.7*exp(1i*phase2);
x = amplitude1*exp(1i*2*pi*f1*t) + amplitude2*exp(1i*2*pi*f2*t);
fmid = (f1 + f2)/2;
fdiff = f2 - f1;
fhalf = fdiff/2;
fsum = f1 + f2;
% First two NC points are the two signed tone differences. Conjugate points
% contain the tone sum and the self-products. Last two are NC alpha=0 PSD.
probes = [1 fmid fdiff; 1 fmid -fdiff; ...
    2 fhalf fsum; 2 -fhalf fsum; ...
    2 0 2*f1; 2 0 2*f2; 1 f1 0; 1 f2 0];
expected = (M/fsHz)*[amplitude2*conj(amplitude1); ...
    amplitude1*conj(amplitude2); amplitude2*amplitude1; ...
    amplitude1*amplitude2; amplitude1^2; amplitude2^2; ...
    abs(amplitude1)^2; abs(amplitude2)^2];
options.ProbePoints = probes;
base = famCycleScout26(x, fsHz, options);
baseValues = probeValues(base, size(probes,1));
checks = struct("name", {}, "passed", {}, "value", {}, "limit", {});
checks(end+1) = check("two_tone_probe_valid", all([base.probes.valid]), 1, 1);
coordinateError = max([abs([base.probes.f_hz]'-probes(:,2)); ...
    abs([base.probes.alpha_hz]'-probes(:,3))]);
checks(end+1) = check("two_tone_coordinates_hz", coordinateError < 1e-7, coordinateError, 1e-7);
baseError = max(abs(baseValues-expected))/max(abs(expected));
checks(end+1) = check("two_tone_complex_scf_relative_error", baseError < 5e-5, baseError, 5e-5);
baseCoherenceError = max(abs(abs([base.probes.pair_coherence_complex])-1));
checks(end+1) = check("two_tone_pair_coherence_error", baseCoherenceError < 5e-5, baseCoherenceError, 5e-5);
parsevalError = relativeError(base.psd.integrated_power, base.psd.window_weighted_input_power);
checks(end+1) = check("two_tone_psd_parseval_relative_error", parsevalError < 5e-6, parsevalError, 5e-6);
alpha0Error = 0;
for k = 7:8
    [~, index] = min(abs(base.psd.f_hz - probes(k,2)));
    alpha0Error = max(alpha0Error, relativeError(baseValues(k), base.psd.density(index)));
end
checks(end+1) = check("nc_alpha0_matches_psd_relative_error", alpha0Error < 5e-6, alpha0Error, 5e-6);

% A CFO shifts ordinary f by nu and conjugate alpha by 2*nu. Global phases
% at t=0 stay fixed, so the mapped complex SCF coefficients should agree.
shiftedProbes = probes;
shiftedProbes(probes(:,1)==1,2) = shiftedProbes(probes(:,1)==1,2)+nu;
shiftedProbes(probes(:,1)==2,3) = shiftedProbes(probes(:,1)==2,3)+2*nu;
options.ProbePoints = [shiftedProbes; probes(1:6,:)];
shifted = famCycleScout26(x.*exp(1i*2*pi*nu*t), fsHz, options);
shiftedValues = probeValues(shifted, size(options.ProbePoints,1));
shiftError = max(abs(shiftedValues(1:8)-expected))/max(abs(expected));
checks(end+1) = check("cfo_mapped_complex_scf_relative_error", shiftError < 5e-5, shiftError, 5e-5);
shiftCoordinates = max([abs([shifted.probes(1:8).f_hz]'-shiftedProbes(:,2)); ...
    abs([shifted.probes(1:8).alpha_hz]'-shiftedProbes(:,3))]);
checks(end+1) = check("cfo_coordinate_shift_error_hz", shiftCoordinates < 1e-7, shiftCoordinates, 1e-7);
unshiftedResponse = max(abs(shiftedValues(9:end)))/max(abs(expected));
checks(end+1) = check("cfo_old_coordinates_suppressed", unshiftedResponse < 5e-5, unshiftedResponse, 5e-5);

% Delay and constant phase: NC gains exp(-j*2*pi*alpha*tau); conjugate
% additionally gains exp(j*2*phi). This tests the complex sign convention.
tau = 3.25/fsHz;
phi = 0.37;
y = exp(1i*phi)*(amplitude1*exp(1i*2*pi*f1*(t-tau)) + ...
    amplitude2*exp(1i*2*pi*f2*(t-tau)));
options.ProbePoints = probes;
translated = famCycleScout26(y, fsHz, options);
expectedTranslated = expected.*exp(-1i*2*pi*probes(:,3)*tau);
expectedTranslated(probes(:,1)==2) = expectedTranslated(probes(:,1)==2)*exp(2i*phi);
translatedValues = probeValues(translated, size(probes,1));
translationError = max(abs(translatedValues-expectedTranslated))/max(abs(expected));
checks(end+1) = check("delay_and_global_phase_relative_error", translationError < 5e-5, translationError, 5e-5);

% Proper stationary complex Gaussian noise has no population nonzero-alpha
% NC or conjugate SCF. Finite estimates are NOT zero. Fixed probes and two
% fixed seeds provide a broad implementation sanity check, not a calibrated
% detection threshold/FAP or a universal null for deterministic tone pairs.
noiseProbes = makeNoiseProbes(fsHz, M, L, P);
noiseOptions = options;
noiseOptions.ChannelWindow = 0.54-0.46*cos(2*pi*(0:M-1)'/(M-1));
noiseOptions.ProbePoints = noiseProbes;
noiseRecords = repmat(struct, 2, 1);
seeds = [261026 261027];
for k = 1:numel(seeds)
    rng(seeds(k), "twister");
    noise = (randn(numberSamples,1)+1i*randn(numberSamples,1))/sqrt(2);
    noiseOut = famCycleScout26(noise, fsHz, noiseOptions);
    noiseMagnitude = abs([noiseOut.probes.pair_coherence_complex]);
    ncMask = noiseProbes(:,1)==1;
    conjugateMask = ~ncMask;
    maxNc = max(noiseMagnitude(ncMask));
    maxConjugate = max(noiseMagnitude(conjugateMask));
    noiseParsevalError = relativeError(noiseOut.psd.integrated_power, ...
        noiseOut.psd.window_weighted_input_power);
    pseudocorrelation = abs(mean(noise.^2))/mean(abs(noise).^2);
    checks(end+1) = check("gaussian_"+k+"_all_probes_finite", all(isfinite(noiseMagnitude)), double(all(isfinite(noiseMagnitude))), 1);
    checks(end+1) = check("gaussian_"+k+"_nc_fixed_probe_max", maxNc < 0.15, maxNc, 0.15);
    checks(end+1) = check("gaussian_"+k+"_conjugate_fixed_probe_max", maxConjugate < 0.15, maxConjugate, 0.15);
    checks(end+1) = check("gaussian_"+k+"_psd_parseval", noiseParsevalError < 5e-6, noiseParsevalError, 5e-6);
    checks(end+1) = check("gaussian_"+k+"_sample_properness", pseudocorrelation < 0.04, pseudocorrelation, 0.04);
    noiseRecords(k).seed = seeds(k);
    noiseRecords(k).probe_coordinates = noiseProbes;
    noiseRecords(k).pair_coherence_magnitudes = noiseMagnitude;
    noiseRecords(k).nc_max = maxNc;
    noiseRecords(k).conjugate_max = maxConjugate;
    noiseRecords(k).pseudocorrelation_magnitude = pseudocorrelation;
    noiseRecords(k).parseval_relative_error = noiseParsevalError;
end
report = struct;
report.status = "completed";
report.all_passed = all([checks.passed]);
report.created_utc = char(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
report.matlab_version = version;
report.helper_path = which("famCycleScout26");
report.fs_hz = fsHz;
report.short_fft_length = M;
report.hop_samples = L;
report.accumulation_length = P;
report.input_sample_count = numberSamples;
report.input_duration_seconds = numberSamples/fsHz;
report.cycle_bin_spacing_hz = fsHz/(L*P);
report.channel_bin_spacing_hz = fsHz/M;
report.tones_hz = [f1 f2];
report.cfo_hz = nu;
report.delay_seconds = tau;
report.global_phase_radians = phi;
report.base_probe_coordinates = probes;
report.expected_complex_scf = splitComplex(expected);
report.observed_complex_scf = splitComplex(baseValues);
report.shifted_probe_coordinates = shiftedProbes;
report.expected_shifted_complex_scf = splitComplex(expected);
report.observed_shifted_complex_scf = splitComplex(shiftedValues(1:8));
report.expected_delay_phase_complex_scf = splitComplex(expectedTranslated);
report.observed_delay_phase_complex_scf = splitComplex(translatedValues);
report.gaussian = noiseRecords;
report.checks = checks;
report.interpretation = [ ...
    "Synthetic implementation verification only; no smartphone inference.", ...
    "Rectangular windows isolate exact tone algebra; noise uses Hamming short windows.", ...
    "Pair coherence is the finite FAM channel-pair statistic, not a calibrated pointwise population coherence.", ...
    "The fixed 0.15 Gaussian bound is an implementation sanity check, not an experiment-wide false-alarm probability.", ...
    "A deterministic tone pair genuinely creates NC difference and conjugate sum cycles; a detected cycle does not identify DSI packets."];
jsonPath = fullfile(outputDirectory, "verification.json");
fid = fopen(jsonPath, "w", "n", "UTF-8");
assert(fid >= 0, "verifyFam26:WriteFailure", "Cannot create verification.json.");
fileCleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(report, PrettyPrint=true), "char");
clear fileCleanup
save(fullfile(outputDirectory, "verification.mat"), "report");
disp(struct2table(checks));
assert(report.all_passed, "verifyFam26:VerificationFailure", ...
    "One or more FAM verification checks failed. Inspect %s.", jsonPath);
end

function values = probeValues(out, numberProbes)
assert(numel(out.probes)==numberProbes, "verifyFam26:ProbeCount", ...
    "Helper did not preserve the requested probe count.");
values = reshape([out.probes.scf_complex], [], 1);
end

function result = check(name, passed, value, limit)
result = struct("name", string(name), "passed", logical(passed), ...
    "value", double(value), "limit", double(limit));
end

function value = relativeError(actual, expected)
value = abs(actual-expected)/max(abs(expected), realmin("double"));
end

function out = splitComplex(in)
out = struct("real", real(in), "imag", imag(in));
end

function probes = makeNoiseProbes(fsHz, M, L, P)
% Fixed channel pairs plus nonzero residual bins avoid an alpha=0 NC null.
probes = zeros(60,3);
count = 0;
deltaAlpha = fsHz/(L*P);
for k = -24:8:24
    for ell = -16:8:16
        if k == ell
            continue
        end
        count = count+1;
        probes(count,:) = [1, (k+ell)*fsHz/(2*M), ...
            (k-ell)*fsHz/M+3*deltaAlpha];
        count = count+1;
        probes(count,:) = [2, (k-ell)*fsHz/(2*M), ...
            (k+ell)*fsHz/M+5*deltaAlpha];
    end
end
probes = probes(1:count,:);
end
