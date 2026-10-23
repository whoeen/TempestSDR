function result = inspectIphoneStitchSweep(outputDirectory)
%INSPECTIPHONESTITCHSWEEP Diagnose 11 iPhone 6 narrowband IQ recordings.
%   Reads immutable, headerless big-endian int16 I,Q as I+jQ. This function
%   finds envelope repetition candidates; it does not identify a pixel clock,
%   confirm the radiation source, or reconstruct/stitch images.
%   Fs=124.0828 MS/s and receiver bandwidth=120 MHz are user-reported.
arguments
    outputDirectory (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
if strlength(outputDirectory)==0
    outputDirectory = fullfile(labRoot,'results','iphone6_stitch_20261023','diagnostics');
end
assert(~isfolder(outputDirectory) && ~isfile(outputDirectory), ...
    'stitch:OutputExists','Refuse overwrite: %s',outputDirectory);
mkdir(outputDirectory);
fs = 124082800;
receiverBandwidth = 120e6;
centersMHz = 100:60:700;
sampleCount = 2^23;
psdSampleCount = 2^20;
lineFrequencySearch = [70e3 160e3];
frameFrequencySearch = [58 62];
multiples = [64 128 256 512];
refinementHalfWidthFraction = 0.0015;
lineLags = (floor(fs/lineFrequencySearch(2)):ceil(fs/lineFrequencySearch(1))).';
frameLags = (floor(fs/frameFrequencySearch(2)):ceil(fs/frameFrequencySearch(1))).';
inventoryPath = fullfile(labRoot,'knowledge','stitching','iphone6_sweep_20261023', ...
    'CAPTURE_INVENTORY.json');
assert(isfile(inventoryPath),'stitch:InventoryMissing','Missing provenance inventory.');
inventory = jsondecode(fileread(inventoryPath));
result = struct('status','running','started_utc',utcNow(), ...
    'fs_hz',fs,'fs_source','user reported complex IQ sample rate', ...
    'receiver_bandwidth_hz',receiverBandwidth,'receiver_bandwidth_source','user reported', ...
    'rf_center_mhz',centersMHz,'first_sample_zero_based',0, ...
    'requested_complex_sample_count',sampleCount,'diagnostic_duration_s',sampleCount/fs, ...
    'line_search_hz',lineFrequencySearch,'frame_search_hz',frameFrequencySearch, ...
    'line_refinement_multiples',multiples, ...
    'line_refinement_half_width_fraction',refinementHalfWidthFraction, ...
    'signal_convention','big-endian int16 I,Q -> I+jQ; RF spectrum polarity not independently confirmed', ...
    'autocorrelation_method','demean abs(IQ); FFT length >=2N-1; divide each lag by N-lag; normalize to lag zero', ...
    'warning','Repetition can be clutter, a harmonic or packet timing. No pixel or physical source identity is assumed.', ...
    'source_inventory',inventoryPath,'implementation',mfilename('fullpath'),'bands',{{}});
writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
summaryRows = cell(numel(centersMHz),1);
for bandIndex=1:numel(centersMHz)
    fcMHz = centersMHz(bandIndex);
    fprintf('Stitch diagnostic %d/%d: fc=%d MHz, Fs=%.7g MS/s\n', ...
        bandIndex,numel(centersMHz),fcMHz,fs/1e6);
    bandDirectory = fullfile(outputDirectory,sprintf('fc%03dMHz',fcMHz));
    mkdir(bandDirectory);
    rawPath = resolveIphoneSweepCapture(fcMHz);
    [iq,readInfo] = readRisIqBlock(rawPath,0,sampleCount);
    identityIndex = find([inventory.captures.fc_mhz]==fcMHz,1);
    assert(~isempty(identityIndex),'stitch:IdentityMissing','Band absent from inventory.');
    identity = inventory.captures(identityIndex);
    assert(readInfo.bytes==identity.bytes,'stitch:SizeChanged','Raw size differs from inventory.');
    quality = diagnoseIq(iq(1:psdSampleCount));
    quality.statistics_first_sample_zero_based = 0;
    quality.statistics_complex_sample_count = psdSampleCount;
    quality.global_clipping_tested = false;
    [psd,basebandFrequency,welch] = estimateWelchPsd( ...
        iq(1:psdSampleCount),periodicHann(8192),4096,8192,fs,"centered");
    welch.dc_removed = false;
    welch.input_complex_sample_count = psdSampleCount;
    welch.segment_count = 1+floor((psdSampleCount-8192)/4096);
    welch.frequency_bin_spacing_hz = fs/8192;
    welch.integrated_power_count_squared = sum(psd)*(fs/8192);
    welch.unweighted_time_power_count_squared = mean(abs(double(iq(1:psdSampleCount))).^2);
    % The FFT below computes linear autocorrelation, not an unscaled PSD.
    am = double(abs(iq));
    clear iq
    amMean = mean(am);
    am = am-amMean;
    n = numel(am);
    transformLength = 2^nextpow2(2*n-1);
    spectrum = fft(am,transformLength);
    clear am
    correlation = real(ifft(abs(spectrum).^2));
    clear spectrum
    maxLag = max(frameLags)+2;
    acf = correlation(1:maxLag+1);
    clear correlation
    acf = acf./(n-(0:maxLag).');
    lagZeroVariance = acf(1);
    assert(isfinite(lagZeroVariance) && lagZeroVariance>0, ...
        'stitch:ConstantEnvelope','Envelope variance is zero or invalid.');
    acf = acf/lagZeroVariance;
    coarseLines = separatedPeaks(acf,lineLags,3,3);
    assert(~isempty(coarseLines),'stitch:NoLinePeak','No local maximum in line search.');
    lineCount = size(coarseLines,1);
    refinedLines = zeros(lineCount,1);
    spreads = zeros(lineCount,1);
    multipleEstimates = zeros(lineCount,numel(multiples));
    multipleAcf = zeros(size(multipleEstimates));
    multipleBoundary = false(size(multipleEstimates));
    for j=1:lineCount
        for k=1:numel(multiples)
            center = coarseLines(j,1)*multiples(k);
            halfWidth = max(3,ceil(refinementHalfWidthFraction*center));
            lags = (max(1,round(center)-halfWidth):min(maxLag-1,round(center)+halfWidth)).';
            [peakValue,peakIndex] = max(acf(lags+1));
            multipleEstimates(j,k) = parabolicLag(acf,lags(peakIndex))/multiples(k);
            multipleAcf(j,k) = peakValue;
            multipleBoundary(j,k) = peakIndex==1 || peakIndex==numel(lags);
        end
        refinedLines(j) = median(multipleEstimates(j,:));
        spreads(j) = max(multipleEstimates(j,:))-min(multipleEstimates(j,:));
    end
    lineTable = table(coarseLines(:,1),refinedLines,fs./refinedLines, ...
        coarseLines(:,2),spreads,any(multipleBoundary,2), ...
        'VariableNames',{'single_peak_lag_samples','refined_line_samples','line_hz', ...
        'acf','multiple_estimate_spread_samples','any_refinement_at_search_boundary'});
    % Quarter-line separation preserves frame aliases while avoiding adjacent
    % sample bins of the same peak. The strongest line is only a candidate.
    frameSeparation = max(1,round(refinedLines(1)/4));
    frameCandidates = separatedPeaks(acf,frameLags,5,frameSeparation);
    assert(~isempty(frameCandidates),'stitch:NoFramePeak','No local maximum in frame search.');
    frameLineRatios = frameCandidates(:,1)./refinedLines.';
    frameTable = table(frameCandidates(:,1),fs./frameCandidates(:,1), ...
        frameCandidates(:,2),frameLineRatios(:,1), ...
        'VariableNames',{'frame_samples','frame_hz','acf','frame_over_best_line'});
    writetable(lineTable,fullfile(bandDirectory,'line_candidates.csv'));
    writetable(frameTable,fullfile(bandDirectory,'frame_candidates.csv'));
    band = struct('fc_hz',fcMHz*1e6,'source',rawPath, ...
        'full_sha256',identity.full_sha256,'read_info',readInfo, ...
        'fs_hz',fs,'receiver_bandwidth_hz',receiverBandwidth, ...
        'quality',quality,'welch',welch,'envelope_mean_counts',amMean, ...
        'envelope_variance_counts_squared',lagZeroVariance, ...
        'autocorrelation_fft_length',transformLength, ...
        'line_candidates',table2struct(lineTable), ...
        'line_refinement_multiples',multiples, ...
        'multiple_period_estimates',multipleEstimates, ...
        'multiple_acf',multipleAcf,'multiple_boundary_flags',multipleBoundary, ...
        'frame_peak_min_separation_samples',frameSeparation, ...
        'frame_candidates',table2struct(frameTable), ...
        'frame_by_line_ratios',frameLineRatios,'completed_utc',utcNow());
    writeJsonFile(fullfile(bandDirectory,'diagnostic.json'),band);
    % Only correlation and candidate metadata are persisted in MAT, never raw IQ.
    save(fullfile(bandDirectory,'autocorrelation.mat'),'acf','lineLags','frameLags', ...
        'lineTable','frameTable','frameLineRatios','fs','transformLength','n','-v7');
    fig = figure('Visible','off','Color','w','Position',[80 80 1450 950]);
    figCleanup = onCleanup(@() closeOwnedFigure(fig));
    tiledlayout(fig,3,1,'TileSpacing','compact');
    nexttile;
    plot((fcMHz*1e6+basebandFrequency)/1e6,powerDb(psd));grid on;
    xline(fcMHz-60,':');xline(fcMHz+60,':');
    xlabel('Nominal RF frequency (MHz), I+jQ polarity assumption');
    ylabel('PSD (dB re count^2/Hz)');
    title(sprintf('fc=%d MHz | Fs=124.0828 MS/s | raw DC retained | %s',fcMHz,welch.implementation));
    nexttile;
    plot(lineLags,acf(lineLags+1));hold on;
    plot(coarseLines(:,1),coarseLines(:,2),'rv');hold off;grid on;
    xlabel('Lag (complex samples)');ylabel('Normalized AM autocorrelation');
    title('Line candidates in 70-160 kHz prior range; labels do not identify the source');
    nexttile;
    plot(frameLags,acf(frameLags+1));hold on;
    plot(frameCandidates(:,1),frameCandidates(:,2),'rv');hold off;grid on;
    xlabel('Lag (complex samples)');ylabel('Normalized AM autocorrelation');
    title(sprintf('Frame candidates in 58-62 Hz prior range | strongest: %.6f Hz / %.6f line periods', ...
        frameTable.frame_hz(1),frameTable.frame_over_best_line(1)));
    exportgraphics(fig,fullfile(bandDirectory,'diagnostic.png'),Resolution=130);
    clear figCleanup
    result.bands{bandIndex} = band;
    summaryRows{bandIndex} = struct('fc_mhz',fcMHz, ...
        'complex_rms_counts',quality.rms_complex_counts,'dc_power_fraction',quality.dc_power_fraction, ...
        'line_samples',refinedLines(1),'line_hz',fs/refinedLines(1), ...
        'line_acf',coarseLines(1,2),'line_multiple_spread_samples',spreads(1), ...
        'frame_samples',frameTable.frame_samples(1),'frame_hz',frameTable.frame_hz(1), ...
        'frame_acf',frameTable.acf(1),'frame_over_line',frameTable.frame_over_best_line(1));
    writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
    disp(lineTable);disp(frameTable);
    clear acf psd basebandFrequency band lineTable frameTable multipleEstimates multipleAcf
end
summaryTable = struct2table(vertcat(summaryRows{:}));
writetable(summaryTable,fullfile(outputDirectory,'overview.csv'));
result.status = 'complete';
result.completed_utc = utcNow();
result.summary = table2struct(summaryTable);
writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
disp(summaryTable);
end

function peaks = separatedPeaks(acf,lags,count,minDistance)
values = acf(lags+1);
locations = find(values(2:end-1)>values(1:end-2) & values(2:end-1)>=values(3:end))+1;
[~,order] = sort(values(locations),'descend');
accepted = zeros(0,1);
for index=order(:).'
    candidate = lags(locations(index));
    if isempty(accepted) || all(abs(candidate-accepted)>=minDistance)
        accepted(end+1,1) = candidate; %#ok<AGROW>
        if numel(accepted)==count
            break
        end
    end
end
peaks = zeros(numel(accepted),2);
for k=1:numel(accepted)
    peaks(k,:) = [parabolicLag(acf,accepted(k)),acf(accepted(k)+1)];
end
end

function lag = parabolicLag(acf,integerLag)
j = integerLag+1;
lag = integerLag;
if j<=1 || j>=numel(acf)
    return
end
denominator = acf(j-1)-2*acf(j)+acf(j+1);
if abs(denominator)>eps
    delta = 0.5*(acf(j-1)-acf(j+1))/denominator;
    lag = integerLag+max(-0.5,min(0.5,delta));
end
end

function closeOwnedFigure(fig)
if isgraphics(fig)
    close(fig);
end
end

function stamp = utcNow()
stamp = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end
