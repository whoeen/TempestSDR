function [stitchedFFT,meta,diagnostics] = synthesizePeriodicBands(bands,periodSeconds,options)
%SYNTHESIZEPERIODICBANDS Merge aligned periodic RF Fourier-series coefficients.
%   BANDS.spectra is an N-by-B numeric matrix or a cell vector of B spectra.
%   Each spectrum is FFTSHIFT(FFT(x))/N; BANDS.centerBins gives its integer
%   global harmonic center. All spectra represent the same source period T.
%   Relative phase/delay/rate corrections must already have been applied.
%
%   Y is a normalized FFTSHIFT spectrum on a larger positive-analytic grid.
%   Physical global harmonic k maps to q=k-meta.output_reference_global_bin.
%   Reconstruct the periodic analytic signal by IFFT(IFFTSHIFT(Y))*numel(Y).
%   No conjugate spectrum or output/input length multiplier is added.
%
%   Method="raised_cosine" uses support-limited complementary crossfades.
%   Method="paper_lr_w8" implements sequential zero-phase L-R W=8 weights:
%   Y_new=L*Y_old+(1-L)*X_new. It retains attenuation where the complementary
%   input is absent. Use EdgeGuardHz=0 for the literal nominal-passband case.
%   The L-R response is evaluated with the SOURCE filter rate Fs_filter=2*B
%   at each physical analytic frequency, then sampled on the larger power-of-
%   two synthesis grid Fs_grid=Nout/T. These two rates are recorded separately.
%
%   Optional diagnostics stores weights/coverage only across the nominal
%   positive occupied span, not a second full-length output FFT. Neither
%   merge establishes the physical source or improves phase identifiability.
arguments
    bands (1,1) struct
    periodSeconds (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive}
    options.Method (1,1) string {mustBeMember(options.Method,["raised_cosine","paper_lr_w8"])} = "raised_cosine"
    options.NominalBandHz (1,1) double {mustBeReal,mustBeFinite,mustBePositive} = 120e6
    options.EdgeGuardHz (1,1) double {mustBeReal,mustBeFinite,mustBeNonnegative} = 3e6
    options.OutputClass (1,1) string {mustBeMember(options.OutputClass,["single","double"])} = "single"
    options.MaxOutputSamples (1,1) double {mustBeReal,mustBeFinite,mustBeInteger,mustBePositive} = 2^26
end
assert(isfield(bands,'spectra') && isfield(bands,'centerBins'), ...
    'stitch:MissingBandFields','bands requires spectra and centerBins fields.');
centers = bands.centerBins;
assert(isnumeric(centers) && isvector(centers) && isreal(centers) && ...
    all(isfinite(centers)) && all(centers==round(centers)) && ~isempty(centers), ...
    'stitch:InvalidCenters','centerBins must contain finite real integer harmonic indices.');
[centers,sortOrder] = sort(double(centers(:)));
bandCount = numel(centers);
assert(all(diff(centers)>0),'stitch:DuplicateCenters','Band centers must be unique.');
assert(bandCount<=255,'stitch:TooManyBands','Coverage counts support at most 255 bands.');
if iscell(bands.spectra)
    assert(isvector(bands.spectra) && numel(bands.spectra)==bandCount, ...
        'stitch:SpectrumCount','Cell spectra must contain one vector per center.');
else
    assert(isfloat(bands.spectra) && ismatrix(bands.spectra) && ...
        size(bands.spectra,2)==bandCount,'stitch:SpectrumCount', ...
        'Numeric spectra must be a floating-point N-by-bandCount matrix.');
end
periodSeconds = double(periodSeconds);
nominalBandHz = options.NominalBandHz;
edgeGuardHz = options.EdgeGuardHz;
assert(2*edgeGuardHz<nominalBandHz,'stitch:GuardConsumesBand', ...
    'The two edge guards must leave a positive usable passband.');
usableBandHz = nominalBandHz-2*edgeGuardHz;
nominalHalfBins = nominalBandHz*periodSeconds/2;
usableHalfBins = usableBandHz*periodSeconds/2;
% Half-open intervals prevent a positive Nyquist bin from wrapping negative.
supportFirst = ceil(centers-usableHalfBins);
supportLast = ceil(centers+usableHalfBins)-1;
referenceGlobalBin = floor(centers(1)-nominalHalfBins);
nominalUpperExclusiveBin = ceil(centers(end)+nominalHalfBins);
positiveSpanBins = nominalUpperExclusiveBin-referenceGlobalBin;
nominalUnionHz = (centers(end)-centers(1))/periodSeconds+nominalBandHz;
sourceFilterRateHz = 2*nominalUnionHz;
sourceAnalyticLowHz = centers(1)/periodSeconds-nominalBandHz/2;
minimumSamples = max(ceil(2*nominalUnionHz*periodSeconds),2*positiveSpanBins);
outputSamples = 2^nextpow2(max(4,minimumSamples));
assert(outputSamples<=options.MaxOutputSamples,'stitch:SynthesisAllocationLimit', ...
    'Requested output has %g samples; raise MaxOutputSamples explicitly if appropriate.',outputSamples);
outputRateHz = outputSamples/periodSeconds;
assert(max(abs(centers))+outputSamples<flintmax, ...
    'stitch:UnrepresentableBins','Global harmonic indices must be exactly representable.');
% Only the raised-cosine implementation assumes at most two-way overlap.
% Sequential L-R weights remain valid with three or more overlapping bands.
if options.Method=="raised_cosine"
    assert(bandCount<3 || all(supportFirst(3:end)>supportLast(1:end-2)), ...
        'stitch:TripleOverlap','Raised-cosine partition assumes no three-way support overlap.');
end
assert(bandCount<2 || all(supportFirst(2:end)<=supportLast(1:end-1)+1), ...
    'stitch:DisconnectedSupport','Bands must form a contiguous supported union.');
bytesPerReal = 4+4*(options.OutputClass=="double");
estimatedOutputBytes = outputSamples*2*bytesPerReal;
if outputSamples>2^24
    warning('stitch:LargeSynthesis', ...
        'Output FFT alone requires %.1f MiB; input arrays, diagnostics and FFT workspaces are additional.', ...
        estimatedOutputBytes/2^20);
end
% Validate all spectra before allocating the large output.
inputLengths = zeros(bandCount,1);
for bandIndex=1:bandCount
    spectrum = selectSpectrum(bands.spectra,sortOrder(bandIndex));
    assert(isfloat(spectrum) && isvector(spectrum) && ~isempty(spectrum) && ...
        all(isfinite(spectrum(:))),'stitch:InvalidSpectrum', ...
        'Every spectrum must be a finite floating-point vector.');
    inputLengths(bandIndex) = numel(spectrum);
    assert(mod(numel(spectrum),2)==0,'stitch:EvenFftRequired','Input FFT lengths must be even.');
    assert(numel(spectrum)/periodSeconds>=nominalBandHz*(1-1e-12), ...
        'stitch:BandExceedsGrid','An input Fourier grid is narrower than NominalBandHz.');
end
stitchedFFT = complex(zeros(outputSamples,1,char(options.OutputClass)));
weightSum = zeros(positiveSpanBins,1,char(options.OutputClass));
coverageCount = zeros(positiveSpanBins,1,'uint8');
crossoverHz = (centers(1:end-1)+centers(2:end))/(2*periodSeconds)-sourceAnalyticLowHz;
for bandIndex=1:bandCount
    inputCount = inputLengths(bandIndex);
    inputFirstGlobalBin = centers(bandIndex)-inputCount/2;
    firstBin = max(supportFirst(bandIndex),inputFirstGlobalBin);
    lastBin = min(supportLast(bandIndex),inputFirstGlobalBin+inputCount-1);
    globalBins = (firstBin:lastBin).';
    inputIndices = globalBins-inputFirstGlobalBin+1;
    positiveBins = globalBins-referenceGlobalBin;
    outputIndices = positiveBins+outputSamples/2+1;
    assert(all(outputIndices>outputSamples/2 & outputIndices<=outputSamples), ...
        'stitch:PositiveGridBounds','A supported coefficient is outside the positive analytic grid.');
    weights = ones(numel(globalBins),1);
    if options.Method=="raised_cosine"
        if bandIndex>1
            overlapLow = max(supportFirst(bandIndex-1),supportFirst(bandIndex));
            overlapHigh = min(supportLast(bandIndex-1),supportLast(bandIndex));
            mask = globalBins<=overlapHigh;
            if overlapHigh>=overlapLow
                weights(mask) = risingWeight(globalBins(mask),overlapLow,overlapHigh);
            end
        end
        if bandIndex<bandCount
            overlapLow = max(supportFirst(bandIndex),supportFirst(bandIndex+1));
            overlapHigh = min(supportLast(bandIndex),supportLast(bandIndex+1));
            mask = globalBins>=overlapLow;
            if overlapHigh>=overlapLow
                weights(mask) = 1-risingWeight(globalBins(mask),overlapLow,overlapHigh);
            end
        end
    else
        analyticFrequencyHz = globalBins/periodSeconds-sourceAnalyticLowHz;
        if bandIndex>1
            weights = 1-lrLow(analyticFrequencyHz,crossoverHz(bandIndex-1),sourceFilterRateHz);
        end
        for laterBand=bandIndex+1:bandCount
            weights = weights.*lrLow(analyticFrequencyHz,crossoverHz(laterBand-1),sourceFilterRateHz);
        end
    end
    spectrum = selectSpectrum(bands.spectra,sortOrder(bandIndex));
    weightedSpectrum = cast(spectrum(inputIndices),char(options.OutputClass)).* ...
        cast(weights,char(options.OutputClass));
    stitchedFFT(outputIndices) = stitchedFFT(outputIndices)+weightedSpectrum(:);
    denseIndices = positiveBins+1;
    weightSum(denseIndices) = weightSum(denseIndices)+cast(weights,char(options.OutputClass));
    coverageCount(denseIndices) = coverageCount(denseIndices)+uint8(1);
end
covered = coverageCount>0;
coveredWeights = double(weightSum(covered));
firstCovered = find(covered,1);
lastCovered = find(covered,1,'last');
meta = struct();
meta.method = char(options.Method);
meta.input_order = sortOrder.';
meta.center_bins_sorted = centers.';
meta.input_fft_lengths = inputLengths.';
meta.period_seconds = periodSeconds;
meta.nominal_band_hz = nominalBandHz;
meta.edge_guard_hz = edgeGuardHz;
meta.usable_band_hz = usableBandHz;
meta.nominal_union_hz = nominalUnionHz;
meta.nominal_rf_low_hz = centers(1)/periodSeconds-nominalBandHz/2;
meta.nominal_rf_high_hz = centers(end)/periodSeconds+nominalBandHz/2;
meta.source_exact_rate_hz = 2*nominalUnionHz;
meta.source_lr_filter_rate_hz = sourceFilterRateHz;
meta.source_analytic_low_hz = sourceAnalyticLowHz;
meta.output_reference_rounding_hz = referenceGlobalBin/periodSeconds-sourceAnalyticLowHz;
meta.output_rate_hz = outputRateHz;
meta.output_fft_length = outputSamples;
meta.output_rate_is_exact_source_2B = abs(outputRateHz-2*nominalUnionHz)<=1e-10*outputRateHz;
meta.output_reference_global_bin = referenceGlobalBin;
meta.output_reference_rf_hz = referenceGlobalBin/periodSeconds;
meta.frequency_coordinate_caveat = 'Hz fields use supplied integer centers/T; upstream mapping owns the common Floquet offset and absolute RF reference';
meta.positive_nominal_span_bins = positiveSpanBins;
meta.output_spectrum_convention = 'fftshift FFT/N; positive analytic, no conjugate mirror';
meta.coefficient_scaling = 'Fourier-series coefficients preserved; time waveform is ifft(ifftshift(Y))*Nout';
meta.output_class = char(options.OutputClass);
meta.estimated_output_bytes_only = estimatedOutputBytes;
meta.support_first_global_bins = supportFirst.';
meta.support_last_global_bins = supportLast.';
meta.crossover_analytic_hz = crossoverHz.';
meta.covered_bin_count = nnz(covered);
meta.covered_frequency_measure_hz = nnz(covered)/periodSeconds;
meta.internal_gap_bin_count = nnz(~covered(firstCovered:lastCovered));
meta.minimum_weight_sum_on_covered_bins = min(coveredWeights);
meta.maximum_weight_sum_on_covered_bins = max(coveredWeights);
meta.max_abs_weight_sum_minus_one_on_covered_bins = max(abs(coveredWeights-1));
meta.support_limited_partition_unity = options.Method=="raised_cosine";
meta.periodic_boundary_assumption = true;
meta.source_lr_formula = 'L(f)=1/(1+(abs(tan(pi*f/Fs_filter))/tan(pi*fx/Fs_filter))^8); high=1-L; Fs_filter=2*nominal_union_hz';
meta.source_lr_caveat = 'Sequential zero-phase W8 on source Fs_filter=2B, sampled on power2 synthesis grid; absent-band attenuation retained, no renormalization';
meta.phase_alignment_performed = false;
if nargout>=3
    diagnostics = struct('first_global_bin',referenceGlobalBin, ...
        'weight_sum',weightSum,'coverage_count',coverageCount, ...
        'frequency_bin_spacing_hz',1/periodSeconds);
end
end

function spectrum = selectSpectrum(spectra,index)
if iscell(spectra)
    spectrum = spectra{index};
else
    spectrum = spectra(:,index);
end
spectrum = spectrum(:);
end

function weight = risingWeight(bin,firstBin,lastBin)
if lastBin==firstBin
    weight = 0.5*ones(size(bin));
else
    position = (double(bin)-firstBin)/(lastBin-firstBin);
    weight = 0.5-0.5*cos(pi*position);
end
end

function low = lrLow(frequencyHz,crossoverHz,sampleRateHz)
% Fourth-order Butterworth squared magnitude gives zero-phase L-R W=8.
ratio = abs(tan(pi*frequencyHz/sampleRateHz))/tan(pi*crossoverHz/sampleRateHz);
low = 1./(1+ratio.^8);
low(frequencyHz<=0) = 1;
low(frequencyHz>=sampleRateHz/2) = 0;
end
