function audit = auditIphoneStitchClutter(options)
%AUDITIPHONESTITCHCLUTTER Test whether a few Fourier bins dominate overlap.
%   AUDIT = AUDITIPHONESTITCHCLUTTER audits completed adjacent-band alignments
%   for both IQ polarities. Missing alignment/template files are PENDING.
%   The ten largest abs(A.*conj(B)) training bins and their +/-8 neighbors
%   are zeroed in both full training and held-out Fourier vectors. The mask
%   is fixed from training; no held-out data choose bins, centers, or delay.
%
%   First, the original saved delay/phase is evaluated before and after the
%   mask. By default the masked training data also refit delay/phase once at
%   the SAME center-bin branch; the held-out data use this fit unchanged.
%   This diagnostic does not refit CFO, integer branches, or template clocks.
%   A coherence improvement after masking is not a screen-source identity.
%
%   Derived reports under clutter_audit are replaced on a repeat invocation,
%   allowing an earlier run with pending edges to be refreshed. Inputs and
%   the original stitch experiment outputs are never modified.
%
%   Example:
%     audit = auditIphoneStitchClutter(Polarities=[1 -1], RefitMasked=true);
arguments
    options.Polarities (1,:) {mustBeNumeric, mustBeReal, mustBeFinite, ...
        mustBeMember(options.Polarities,[-1 1])} = [1 -1]
    options.TopBins (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, ...
        mustBeInteger, mustBePositive} = 10
    options.HalfWidthBins (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, ...
        mustBeInteger, mustBeNonnegative} = 8
    options.RefitMasked (1,1) logical = true
    options.ResultRoot (1,1) string = ""
    options.OutputDirectory (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'stitch'));
resultRoot = options.ResultRoot;
if strlength(resultRoot)==0
    resultRoot = fullfile(labRoot,'results','iphone6_stitch_20261023');
end
outputRoot = options.OutputDirectory;
if strlength(outputRoot)==0
    outputRoot = fullfile(resultRoot,'clutter_audit');
end
if ~isfolder(outputRoot), mkdir(outputRoot); end
polarities = unique(double(options.Polarities),'stable');
assert(~isempty(polarities),'stitch:NoPolarities','At least one polarity is required.');
centersMHz = 100:60:700;
resultCount = numel(polarities)*(numel(centersMHz)-1);
results = cell(resultCount,1);
rows = repmat(emptySummary(),resultCount,1);
entry = 0;
for polarity = polarities
    polarityDirectory = fullfile(outputRoot,sprintf('polarity_%+d',polarity));
    if ~isfolder(polarityDirectory), mkdir(polarityDirectory); end
    for pairIndex = 1:numel(centersMHz)-1
        entry = entry+1;
        firstMHz = centersMHz(pairIndex);
        secondMHz = centersMHz(pairIndex+1);
        pairName = sprintf('pair_%03d_%03d',firstMHz,secondMHz);
        alignmentPath = fullfile(resultRoot,sprintf('stitch_polarity_%+d',polarity), ...
            pairName,'alignment.json');
        templateAPath = fullfile(resultRoot,'templates',sprintf('fc%03dMHz',firstMHz),'templates.mat');
        templateBPath = fullfile(resultRoot,'templates',sprintf('fc%03dMHz',secondMHz),'templates.mat');
        record = struct('status','pending','iq_polarity',polarity, ...
            'center_a_mhz',firstMHz,'center_b_mhz',secondMHz, ...
            'alignment_source',char(alignmentPath), ...
            'template_a_source',char(templateAPath),'template_b_source',char(templateBPath));
        row = emptySummary();
        row.iq_polarity = polarity;
        row.center_a_mhz = firstMHz;
        row.center_b_mhz = secondMHz;
        paths = [string(alignmentPath),string(templateAPath),string(templateBPath)];
        missing = paths(~isfile(paths));
        if ~isempty(missing)
            record.pending_reason = 'Required source files have not been written yet.';
            record.missing_sources = cellstr(missing);
        else
            fprintf('Clutter audit IQ %+d: %d-%d MHz, training mask only\n', ...
                polarity,firstMHz,secondMHz);
            try
                record = evaluateEdge(record,options);
                row = summarizeEdge(record,row);
            catch exception
                record.status = 'failed';
                record.error_identifier = exception.identifier;
                record.error_message = exception.message;
                row.status = "failed";
                row.error_message = string(exception.message);
                warning('stitch:ClutterAuditEdgeFailed','IQ %+d %d-%d MHz: %s', ...
                    polarity,firstMHz,secondMHz,exception.message);
            end
        end
        results{entry} = record;
        rows(entry) = row;
        writeAuditJson(fullfile(polarityDirectory,pairName+".json"),record);
        writetable(struct2table(row),fullfile(polarityDirectory,pairName+".csv"));
        % Checkpoint the summary after every edge, including pending edges.
        writetable(struct2table(rows(1:entry)),fullfile(outputRoot,'overview.csv'));
    end
end
statuses = string({rows.status});
audit = struct();
audit.status = 'complete';
if any(statuses=="failed")
    audit.status = 'completed_with_failures';
elseif any(statuses=="pending")
    audit.status = 'pending_sources';
end
audit.generated_at = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
audit.result_root = char(resultRoot);
audit.output_directory = char(outputRoot);
audit.options = options;
audit.expected_edge_count = resultCount;
audit.completed_edge_count = nnz(statuses=="complete");
audit.pending_edge_count = nnz(statuses=="pending");
audit.failed_edge_count = nnz(statuses=="failed");
audit.failed_refit_count = nnz(string({rows.refit_status})=="failed");
if audit.failed_refit_count>0 && strcmp(audit.status,'complete')
    audit.status = 'completed_with_refit_failures';
end
audit.results = results;
audit.interpretation = ['Diagnostic of spectral concentration and frozen-model generalization, ' ...
    'not a physical source classifier or a proof that every stitching method fails.'];
writeAuditJson(fullfile(outputRoot,'overview.json'),audit);
end

function result = evaluateEdge(result,options)
source = jsondecode(fileread(result.alignment_source));
if isfield(source,'alignment')
    alignment = source.alignment;
else
    alignment = source;
end
required = {'fft_length','period_seconds','center_bin_a','center_bin_b', ...
    'delay_samples','delay_seconds','phase_rad','usable_band_hz', ...
    'overlap_first_global_bin','overlap_last_global_bin'};
assert(all(isfield(alignment,required)),'stitch:IncompleteAlignment', ...
    'Saved alignment is missing required Fourier-grid fields.');
if isfield(source,'selected_center_bin_b')
    assert(source.selected_center_bin_b==alignment.center_bin_b, ...
        'stitch:CenterMismatch','Selected branch and saved alignment center disagree.');
end
first = load(result.template_a_source,'trainFFT','testFFT');
second = load(result.template_b_source,'trainFFT','testFFT');
aTrain = first.trainFFT(:); aTest = first.testFFT(:);
bTrain = second.trainFFT(:); bTest = second.testFFT(:);
clear first second
if result.iq_polarity==-1
    % For even FFTSHIFT grids, time-domain conjugation reverses frequency.
    % Conjugating coefficients without reversal would represent another model.
    aTrain = conj(circshift(flipud(aTrain),1));
    aTest = conj(circshift(flipud(aTest),1));
    bTrain = conj(circshift(flipud(bTrain),1));
    bTest = conj(circshift(flipud(bTest),1));
end
sampleCount = numel(aTrain);
assert(all([numel(aTest),numel(bTrain),numel(bTest),alignment.fft_length]==sampleCount) ...
    && mod(sampleCount,2)==0,'stitch:ClutterGridMismatch', ...
    'Templates and saved alignment must have the same even FFT length.');
assert(all(isfinite(aTrain)) && all(isfinite(aTest)) && ...
    all(isfinite(bTrain)) && all(isfinite(bTest)), ...
    'stitch:NonfiniteTemplate','Template coefficients must be finite.');
globalBins = (alignment.overlap_first_global_bin:alignment.overlap_last_global_bin).';
assert(~isempty(globalBins),'stitch:NoUsableOverlap','Saved overlap is empty.');
indexA = globalBins-(alignment.center_bin_a-sampleCount/2)+1;
indexB = globalBins-(alignment.center_bin_b-sampleCount/2)+1;
assert(all(indexA>=1 & indexA<=sampleCount) && all(indexB>=1 & indexB<=sampleCount), ...
    'stitch:ClutterIndexBounds','Saved overlap falls outside the template vectors.');
trainA = double(aTrain(indexA)); trainB = double(bTrain(indexB));
testA = double(aTest(indexA)); testB = double(bTest(indexB));
weights = abs(trainB.*conj(trainA));
assert(sum(weights)>0,'stitch:NoSharedEnergy','No shared training energy is present.');
[peakWeights,peakIndices] = maxk(weights,min(double(options.TopBins),numel(weights)));
selectedGlobalBins = globalBins(peakIndices);
% Neighbor bins are clipped to the SAME guarded overlap used by the source.
% Their support and the two selected center-bin branches remain unchanged.
mask = false(numel(globalBins),1);
for peakIndex = reshape(peakIndices,1,[])
    firstIndex = max(1,peakIndex-double(options.HalfWidthBins));
    lastIndex = min(numel(mask),peakIndex+double(options.HalfWidthBins));
    mask(firstIndex:lastIndex) = true;
end
maskedGlobalBins = globalBins(mask);
correction = exp(1i*(2*pi/sampleCount)*globalBins*alignment.delay_samples ...
    -1i*alignment.phase_rad);
result.original_fixed.before.train = calculateMetrics(trainA,trainB.*correction);
result.original_fixed.before.test = calculateMetrics(testA,testB.*correction);
result.spectral_diversity_before = spectralDiversity(weights,globalBins,alignment.period_seconds);
result.mask = struct('selection_data','training overlap only', ...
    'score','abs(B_train .* conj(A_train))', ...
    'requested_top_bin_count',double(options.TopBins), ...
    'selected_top_bin_count',numel(peakIndices), ...
    'neighbor_half_width_bins',double(options.HalfWidthBins), ...
    'neighbor_half_width_hz',double(options.HalfWidthBins)/alignment.period_seconds, ...
    'selected_global_bins',selectedGlobalBins.', ...
    'selected_training_cross_magnitudes',peakWeights.', ...
    'masked_global_bins',maskedGlobalBins.', ...
    'masked_bin_count',nnz(mask),'overlap_bin_count',numel(mask), ...
    'mask_scope','Neighbor bins clipped to original guarded common overlap.', ...
    'heldout_mask_refitted',false);
result.retained_power_fraction.full_train_a = retainedFraction(aTrain,indexA(mask));
result.retained_power_fraction.full_train_b = retainedFraction(bTrain,indexB(mask));
result.retained_power_fraction.full_test_a = retainedFraction(aTest,indexA(mask));
result.retained_power_fraction.full_test_b = retainedFraction(bTest,indexB(mask));
trainA(mask) = 0; trainB(mask) = 0; testA(mask) = 0; testB(mask) = 0;
result.original_fixed.after.train = calculateMetrics(trainA,trainB.*correction);
result.original_fixed.after.test = calculateMetrics(testA,testB.*correction);
result.retained_power_fraction.overlap_train_a = safeRatio( ...
    result.original_fixed.after.train.reference_spectral_energy, ...
    result.original_fixed.before.train.reference_spectral_energy);
result.retained_power_fraction.overlap_train_b = safeRatio( ...
    result.original_fixed.after.train.measured_spectral_energy, ...
    result.original_fixed.before.train.measured_spectral_energy);
result.retained_power_fraction.overlap_test_a = safeRatio( ...
    result.original_fixed.after.test.reference_spectral_energy, ...
    result.original_fixed.before.test.reference_spectral_energy);
result.retained_power_fraction.overlap_test_b = safeRatio( ...
    result.original_fixed.after.test.measured_spectral_energy, ...
    result.original_fixed.before.test.measured_spectral_energy);
weights(mask) = 0;
result.spectral_diversity_after = spectralDiversity(weights,globalBins,alignment.period_seconds);
result.original_alignment = alignment;
result.center_bin_a = alignment.center_bin_a;
result.center_bin_b = alignment.center_bin_b;
result.selected_branch_offset_bins = NaN;
if isfield(source,'selected_branch_offset_bins')
    result.selected_branch_offset_bins = source.selected_branch_offset_bins;
end
result.center_branch_refitted = false;
result.additional_cfo_search = false;
result.template_period_or_phase_model_refitted = false;
result.correction_formula = 'B(k)*exp(+1i*2*pi*k*delay_samples/N)*exp(-1i*phase_rad)';
result.unit_gain_only = true;
result.branch_note = ['The original selected center-bin branch is unchanged. The unmasked ' ...
    'training data selected it; masking does not perform another integer/CFO search.'];
result.before_metric_agreement = struct();
if isfield(alignment,'train_unit_gain') && isfield(alignment,'test_unit_gain')
    result.before_metric_agreement.train_coherence_absolute_difference = abs( ...
        result.original_fixed.before.train.complex_coherence-alignment.train_unit_gain.complex_coherence);
    result.before_metric_agreement.test_coherence_absolute_difference = abs( ...
        result.original_fixed.before.test.complex_coherence-alignment.test_unit_gain.complex_coherence);
    result.before_metric_agreement.test_error_absolute_difference = abs( ...
        result.original_fixed.before.test.normalized_complex_error-alignment.test_unit_gain.normalized_complex_error);
end
result.masked_refit = struct('status','not_requested','test_parameters_refitted',false);
if options.RefitMasked
    aTrain(indexA(mask)) = 0; aTest(indexA(mask)) = 0;
    bTrain(indexB(mask)) = 0; bTest(indexB(mask)) = 0;
    if sum(weights)>0
        % Only delay/phase can change here; centers and all template fits stay fixed.
        try
            assert(~isfield(alignment,'edge_guard_hz') || alignment.edge_guard_hz==3e6, ...
                'stitch:AuditRefitGuardMismatch','Refit helper requires the original 3 MHz guard.');
            result.masked_refit = alignPeriodicOverlap(aTrain,bTrain,aTest,bTest, ...
                alignment.center_bin_a,alignment.center_bin_b, ...
                alignment.period_seconds,alignment.usable_band_hz);
            result.masked_refit.center_branch_refitted = false;
            result.masked_refit.additional_cfo_search = false;
        catch exception
            result.masked_refit = struct('status','failed', ...
                'error_identifier',exception.identifier,'error_message',exception.message, ...
                'test_parameters_refitted',false,'center_branch_refitted',false, ...
                'additional_cfo_search',false);
        end
    else
        result.masked_refit.status = 'no_shared_training_energy_after_mask';
    end
end
result.status = 'complete';
result.source_alignment_status = alignment.status;
result.interpretation = ['Coherence magnitude can be high for a single shared tone while delay ' ...
    'remains ambiguous. Compare spectral diversity, fixed held-out phase/error, ' ...
    'and retained energy; this mask is a sensitivity diagnostic, not proven clutter removal.'];
end

function metrics = calculateMetrics(reference,measured)
referencePower = sum(abs(reference).^2);
measuredPower = sum(abs(measured).^2);
crossValue = sum(measured.*conj(reference));
coherence = NaN; residualPhase = NaN; normalizedError = NaN;
if referencePower>0 && measuredPower>0
    coherence = min(1,abs(crossValue)/sqrt(referencePower*measuredPower));
    residualPhase = angle(crossValue);
end
if referencePower>0
    normalizedError = norm(reference-measured)/sqrt(referencePower);
end
metrics = struct('complex_coherence',coherence, ...
    'normalized_complex_error',normalizedError, ...
    'residual_cross_phase_rad',residualPhase, ...
    'reference_spectral_energy',referencePower, ...
    'measured_spectral_energy',measuredPower);
end

function diversity = spectralDiversity(weights,globalBins,periodSeconds)
total = sum(weights);
diversity = struct('cross_magnitude_sum',total,'effective_bin_count',NaN, ...
    'energy_90_percent_span_hz',NaN,'cross_energy_rms_bandwidth_hz',NaN, ...
    'largest_bin_cross_weight_fraction',NaN);
if total<=0, return; end
normalized = weights/total;
cumulative = cumsum(normalized);
low = find(cumulative>=0.05,1); high = find(cumulative>=0.95,1);
frequency = (globalBins-globalBins(1))/periodSeconds;
meanFrequency = sum(normalized.*frequency);
diversity.effective_bin_count = total^2/sum(weights.^2);
diversity.energy_90_percent_span_hz = frequency(high)-frequency(low);
diversity.cross_energy_rms_bandwidth_hz = sqrt(sum(normalized.*(frequency-meanFrequency).^2));
diversity.largest_bin_cross_weight_fraction = max(normalized);
end

function fraction = retainedFraction(vector,removedIndices)
total = sum(abs(double(vector)).^2);
removed = sum(abs(double(vector(removedIndices))).^2);
fraction = safeRatio(max(0,total-removed),total);
end

function value = safeRatio(numerator,denominator)
value = NaN;
if denominator>0, value = numerator/denominator; end
end

function row = emptySummary()
row = struct('iq_polarity',NaN,'center_a_mhz',NaN,'center_b_mhz',NaN, ...
    'status',"pending",'center_bin_a',NaN,'center_bin_b',NaN, ...
    'selected_branch_offset_bins',NaN,'masked_bin_count',NaN, ...
    'effective_bins_before',NaN,'effective_bins_after',NaN, ...
    'span90_before_hz',NaN,'span90_after_hz',NaN, ...
    'largest_bin_fraction_before',NaN,'largest_bin_fraction_after',NaN, ...
    'retained_overlap_train_a',NaN,'retained_overlap_train_b',NaN, ...
    'retained_overlap_test_a',NaN,'retained_overlap_test_b',NaN, ...
    'fixed_before_train_coherence',NaN,'fixed_before_test_coherence',NaN, ...
    'fixed_before_test_phase_rad',NaN,'fixed_before_test_error',NaN, ...
    'fixed_after_train_coherence',NaN,'fixed_after_test_coherence',NaN, ...
    'fixed_after_test_phase_rad',NaN,'fixed_after_test_error',NaN, ...
    'refit_status',"not_run",'refit_train_coherence',NaN,'refit_test_coherence',NaN, ...
    'refit_test_phase_rad',NaN,'refit_test_error',NaN, ...
    'refit_delay_samples',NaN,'refit_second_peak_ratio',NaN, ...
    'error_message',"");
end

function row = summarizeEdge(result,row)
row.status = string(result.status);
row.center_bin_a = result.center_bin_a;
row.center_bin_b = result.center_bin_b;
row.selected_branch_offset_bins = result.selected_branch_offset_bins;
row.masked_bin_count = result.mask.masked_bin_count;
row.effective_bins_before = result.spectral_diversity_before.effective_bin_count;
row.effective_bins_after = result.spectral_diversity_after.effective_bin_count;
row.span90_before_hz = result.spectral_diversity_before.energy_90_percent_span_hz;
row.span90_after_hz = result.spectral_diversity_after.energy_90_percent_span_hz;
row.largest_bin_fraction_before = result.spectral_diversity_before.largest_bin_cross_weight_fraction;
row.largest_bin_fraction_after = result.spectral_diversity_after.largest_bin_cross_weight_fraction;
row.retained_overlap_train_a = result.retained_power_fraction.overlap_train_a;
row.retained_overlap_train_b = result.retained_power_fraction.overlap_train_b;
row.retained_overlap_test_a = result.retained_power_fraction.overlap_test_a;
row.retained_overlap_test_b = result.retained_power_fraction.overlap_test_b;
row.fixed_before_train_coherence = result.original_fixed.before.train.complex_coherence;
row.fixed_before_test_coherence = result.original_fixed.before.test.complex_coherence;
row.fixed_before_test_phase_rad = result.original_fixed.before.test.residual_cross_phase_rad;
row.fixed_before_test_error = result.original_fixed.before.test.normalized_complex_error;
row.fixed_after_train_coherence = result.original_fixed.after.train.complex_coherence;
row.fixed_after_test_coherence = result.original_fixed.after.test.complex_coherence;
row.fixed_after_test_phase_rad = result.original_fixed.after.test.residual_cross_phase_rad;
row.fixed_after_test_error = result.original_fixed.after.test.normalized_complex_error;
row.refit_status = string(result.masked_refit.status);
if isfield(result.masked_refit,'train_unit_gain')
    row.refit_train_coherence = result.masked_refit.train_unit_gain.complex_coherence;
    row.refit_test_coherence = result.masked_refit.test_unit_gain.complex_coherence;
    row.refit_test_phase_rad = result.masked_refit.test_unit_gain.residual_cross_phase_rad;
    row.refit_test_error = result.masked_refit.test_unit_gain.normalized_complex_error;
    row.refit_delay_samples = result.masked_refit.delay_samples;
    row.refit_second_peak_ratio = result.masked_refit.second_peak_ratio;
end
end

function writeAuditJson(path,value)
file = fopen(path,'w','n','UTF-8');
assert(file>=0,'stitch:AuditWriteFailed','Cannot write audit report: %s',path);
cleanup = onCleanup(@() fclose(file));
fprintf(file,'%s\n',jsonencode(value,PrettyPrint=true));
end
