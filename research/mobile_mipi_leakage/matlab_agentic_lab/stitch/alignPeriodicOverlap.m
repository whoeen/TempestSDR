function [alignment, bTrainAlignedFFT, bTestAlignedFFT] = alignPeriodicOverlap( ...
    aTrainFFT, bTrainFFT, aTestFFT, bTestFFT, ...
    centerBinA, centerBinB, periodSeconds, usableBandHz)
%ALIGNPERIODICOVERLAP Fit periodic delay and phase on shared RF Fourier bins.
%   Inputs are equal-length, even-N, FFTSHIFT(FFT(x))/N coefficient vectors.
%   Global harmonic index is k=(-N/2:N/2-1)+centerBin; frequency is k/T.
%   The two centers must already lie on the same integer harmonic grid.
%   This function does not estimate CFO, resample clock drift, or use images.
%
%   For B(k)=gain*A(k)*exp(1i*phi-1i*2*pi*k*tau/T), the fitted correction is
%   B(k)*exp(1i*2*pi*k*tau/T)*exp(-1i*phi). Delay is identified modulo T.
%   A fixed 3 MHz edge guard is removed from each nominal usable passband.
%
%   ALIGNMENT stores scalar diagnostics and frozen-training test metrics.
%   Optional second/third outputs apply the UNIT-GAIN phase/delay correction
%   to all N B coefficients. Multiply by alignment.positive_ls_gain only for
%   the separately labeled positive-LS-gain control. No absolute RF phase or
%   physical source identification is implied. Single-tone/comb ambiguity is
%   flagged; a numerical peak alone is not evidence of a valid screen stitch.
arguments
    aTrainFFT {mustBeFloat, mustBeVector, mustBeFinite, mustBeNonempty}
    bTrainFFT {mustBeFloat, mustBeVector, mustBeFinite, mustBeNonempty}
    aTestFFT {mustBeFloat, mustBeVector, mustBeFinite, mustBeNonempty}
    bTestFFT {mustBeFloat, mustBeVector, mustBeFinite, mustBeNonempty}
    centerBinA (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeInteger}
    centerBinB (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeInteger}
    periodSeconds (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
    usableBandHz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
end
sampleCount = numel(aTrainFFT);
assert(mod(sampleCount,2)==0 && sampleCount>=4, ...
    'stitch:EvenFftRequired','An even FFT length of at least four is required.');
assert(all([numel(bTrainFFT),numel(aTestFFT),numel(bTestFFT)]==sampleCount), ...
    'stitch:LengthMismatch','All Fourier coefficient vectors must have equal length.');
periodSeconds = double(periodSeconds);
usableBandHz = double(usableBandHz);
centerBinA = double(centerBinA);
centerBinB = double(centerBinB);
sampleRateHz = sampleCount/periodSeconds;
assert(usableBandHz<=sampleRateHz*(1+1e-12), ...
    'stitch:BandExceedsGrid','Usable bandwidth exceeds the input complex Fourier grid.');
assert(max(abs([centerBinA,centerBinB]))+sampleCount<flintmax, ...
    'stitch:UnrepresentableBins','Global harmonic indices must be exactly representable.');
edgeGuardHz = 3e6;
assert(usableBandHz>2*edgeGuardHz, ...
    'stitch:GuardConsumesBand','Usable band must exceed the two 3 MHz edge guards.');
aTrainFFT = double(aTrainFFT(:));
bTrainFFT = double(bTrainFFT(:));
aTestFFT = double(aTestFFT(:));
bTestFFT = double(bTestFFT(:));
localBins = (-sampleCount/2:sampleCount/2-1).';
globalBinsA = localBins+centerBinA;
globalBinsB = localBins+centerBinB;
halfUsableBins = (usableBandHz/2-edgeGuardHz)*periodSeconds;
lowestBin = ceil(max([globalBinsA(1),globalBinsB(1), ...
    centerBinA-halfUsableBins,centerBinB-halfUsableBins]));
highestBin = floor(min([globalBinsA(end),globalBinsB(end), ...
    centerBinA+halfUsableBins,centerBinB+halfUsableBins]));
assert(highestBin>=lowestBin, ...
    'stitch:NoUsableOverlap','No common Fourier bins remain after the edge guards.');
globalBins = (lowestBin:highestBin).';
indexA = globalBins-globalBinsA(1)+1;
indexB = globalBins-globalBinsB(1)+1;
trainA = aTrainFFT(indexA);
trainB = bTrainFFT(indexB);
testA = aTestFFT(indexA);
testB = bTestFFT(indexB);
crossSpectrum = trainB.*conj(trainA);
weights = abs(crossSpectrum);
weightSum = sum(weights);
assert(isfinite(weightSum) && weightSum>0, ...
    'stitch:NoSharedEnergy','The training overlap has no finite shared spectral energy.');
% Global bins must be used modulo N for the coarse periodic correlation.
% Contiguous support is at most N bins, so this mapping has no collisions.
normalizedCross = crossSpectrum/weightSum;
correlationSpectrum = complex(zeros(sampleCount,1));
correlationSpectrum(mod(globalBins,sampleCount)+1) = normalizedCross;
correlation = ifft(correlationSpectrum)*sampleCount;
correlationMagnitude = abs(correlation);
[coarsePeak,peakIndex] = max(correlationMagnitude);
coarseDelaySamples = peakIndex-1;
if coarseDelaySamples>=sampleCount/2
    coarseDelaySamples = coarseDelaySamples-sampleCount;
end
% Optimize a small offset, avoiding fminbnd's scale tolerance at a large lag.
objective = @(offset) -abs(sum(normalizedCross.*exp( ...
    1i*(2*pi/sampleCount)*globalBins*(coarseDelaySamples+offset))));
options = optimset('TolX',1e-9,'Display','off');
[fractionalOffset,negativePeak,exitFlag] = fminbnd(objective,-1,1,options);
delaySamples = coarseDelaySamples+fractionalOffset;
delaySamples = mod(delaySamples+sampleCount/2,sampleCount)-sampleCount/2;
delaySeconds = delaySamples*periodSeconds/sampleCount;
phaseRamp = exp(1i*(2*pi/sampleCount)*globalBins*delaySamples);
phaseRad = angle(sum(normalizedCross.*phaseRamp));
correction = phaseRamp*exp(-1i*phaseRad);
correctedTrainB = trainB.*correction;
correctedTestB = testB.*correction;
positiveGain = max(0,real(sum(trainA.*conj(correctedTrainB)))/ ...
    max(sum(abs(correctedTrainB).^2),realmin));
% This is a sidelobe/competing-peak diagnostic, not a universal confidence test.
mainLobeGuardSamples = max(2,ceil(2*sampleCount/numel(globalBins)));
coarseLags = (0:sampleCount-1).';
circularDistance = abs(mod(coarseLags-(peakIndex-1)+sampleCount/2, ...
    sampleCount)-sampleCount/2);
otherPeakMask = circularDistance>mainLobeGuardSamples;
if any(otherPeakMask)
    alternateMagnitude = correlationMagnitude;
    alternateMagnitude(~otherPeakMask) = -Inf;
    [secondPeak,secondPeakIndex] = max(alternateMagnitude);
    secondDelaySamples = mod(secondPeakIndex-1+sampleCount/2, ...
        sampleCount)-sampleCount/2;
    secondPeakRatio = secondPeak/max(coarsePeak,realmin);
else
    secondPeakRatio = NaN;
    secondDelaySamples = NaN;
end
effectiveBinCount = weightSum^2/max(sum(weights.^2),realmin);
normalizedWeights = weights/weightSum;
cumulativeWeights = cumsum(normalizedWeights);
lowEnergyIndex = find(cumulativeWeights>=0.05,1);
highEnergyIndex = find(cumulativeWeights>=0.95,1);
frequencyHz = globalBins/periodSeconds;
meanFrequencyHz = sum(normalizedWeights.*frequencyHz);
rmsBandwidthHz = sqrt(sum(normalizedWeights.*(frequencyHz-meanFrequencyHz).^2));
energySpan90Hz = frequencyHz(highEnergyIndex)-frequencyHz(lowEnergyIndex);
geometricSpanHz = (highestBin-lowestBin)/periodSeconds;
lowSpectralDiversity = effectiveBinCount<8;
competingPeriodicPeak = isfinite(secondPeakRatio) && secondPeakRatio>0.90;
alignment = struct();
alignment.status = 'estimated';
if lowSpectralDiversity || competingPeriodicPeak
    alignment.status = 'ambiguous_periodic_estimate';
end
alignment.fft_length = sampleCount;
alignment.period_seconds = periodSeconds;
alignment.input_grid_rate_hz = sampleRateHz;
alignment.center_bin_a = centerBinA;
alignment.center_bin_b = centerBinB;
alignment.usable_band_hz = usableBandHz;
alignment.edge_guard_hz = edgeGuardHz;
alignment.overlap_first_global_bin = lowestBin;
alignment.overlap_last_global_bin = highestBin;
alignment.overlap_bin_count = numel(globalBins);
alignment.overlap_span_hz = geometricSpanHz;
alignment.overlap_bin_measure_hz = numel(globalBins)/periodSeconds;
alignment.coarse_delay_samples = coarseDelaySamples;
alignment.fractional_refinement_samples = fractionalOffset;
alignment.delay_samples = delaySamples;
alignment.delay_seconds = delaySeconds;
alignment.phase_rad = phaseRad;
alignment.positive_ls_gain = positiveGain;
alignment.fminbnd_exit_flag = exitFlag;
alignment.optimized_normalized_cross_peak = -negativePeak;
alignment.second_peak_ratio = secondPeakRatio;
alignment.second_peak_ratio_definition = 'second outside mainlobe / first coarse peak';
alignment.second_peak_delay_samples = secondDelaySamples;
alignment.mainlobe_exclusion_samples = mainLobeGuardSamples;
alignment.effective_bin_count = effectiveBinCount;
alignment.effective_bin_fraction = effectiveBinCount/numel(globalBins);
alignment.energy_90_percent_span_hz = energySpan90Hz;
alignment.energy_90_percent_span_fraction = energySpan90Hz/max(geometricSpanHz,realmin);
alignment.cross_energy_rms_bandwidth_hz = rmsBandwidthHz;
alignment.low_spectral_diversity = lowSpectralDiversity;
alignment.competing_periodic_peak = competingPeriodicPeak;
alignment.train_uncorrected = overlapMetrics(trainA,trainB);
alignment.test_uncorrected = overlapMetrics(testA,testB);
alignment.train_unit_gain = overlapMetrics(trainA,correctedTrainB);
alignment.test_unit_gain = overlapMetrics(testA,correctedTestB);
alignment.train_positive_ls_gain = overlapMetrics(trainA,positiveGain*correctedTrainB);
alignment.test_positive_ls_gain = overlapMetrics(testA,positiveGain*correctedTestB);
alignment.test_parameters_refitted = false;
alignment.delay_identifiability = 'modulo one period; single-tone and comb aliases can remain';
alignment.phase_reference = 'relative B to A on training overlap; no absolute physical RF phase';
alignment.correction_formula = 'B(k)*exp(+1i*2*pi*k*delay_seconds/T)*exp(-1i*phase_rad)';
alignment.scope = 'No CFO/rate fitting, crossover synthesis, or image-based registration';
if nargout>=2
    fullCorrection = exp(1i*(2*pi/sampleCount)*globalBinsB*delaySamples-1i*phaseRad);
    bTrainAlignedFFT = bTrainFFT.*fullCorrection;
end
if nargout>=3
    bTestAlignedFFT = bTestFFT.*fullCorrection;
end
end

function metrics = overlapMetrics(reference,measured)
% No parameters are fitted in this metric computation.
referencePower = sum(abs(reference).^2);
measuredPower = sum(abs(measured).^2);
if referencePower<=0 || measuredPower<=0
    coherence = NaN;
    residualPhase = NaN;
else
    crossValue = sum(measured.*conj(reference));
    coherence = min(1,abs(crossValue)/sqrt(referencePower*measuredPower));
    residualPhase = angle(crossValue);
end
if referencePower<=0
    normalizedError = NaN;
else
    normalizedError = norm(reference-measured)/sqrt(referencePower);
end
metrics = struct('complex_coherence',coherence, ...
    'normalized_complex_error',normalizedError, ...
    'residual_cross_phase_rad',residualPhase, ...
    'reference_spectral_energy',referencePower, ...
    'measured_spectral_energy',measuredPower);
end
