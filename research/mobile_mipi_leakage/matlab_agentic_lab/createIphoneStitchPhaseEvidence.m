function report = createIphoneStitchPhaseEvidence(resultRoot)
%CREATEIPHONESTITCHPHASEEVIDENCE Relative IQ phase and explicit normalized STFT.
%   Reads only singleTrain/meta from the 100, 520 and 640 MHz templates.
%   Outputs are ancillary diagnostics, not recovered display RGB, circuit
%   identification, or a confidence map. Refuses an existing phase_tf folder.
arguments
    resultRoot (1,1) string = fullfile(fileparts(mfilename('fullpath')), ...
        'results','iphone6_stitch_20261023')
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'stitch'));
outputRoot = fullfile(resultRoot,'phase_tf');
assert(~isfolder(outputRoot) && ~isfile(outputRoot),'stitch:PhaseOutputExists', ...
    'Refusing to overwrite %s.',outputRoot);
centersMHz = [100 520 640];
for bandIndex=1:numel(centersMHz)
    inputFile = fullfile(resultRoot,'templates',sprintf('fc%dMHz',centersMHz(bandIndex)),'templates.mat');
    assert(isfile(inputFile),'stitch:MissingPhaseTemplate','Missing input %s.',inputFile);
end
mkdir(outputRoot);
rows = 1881;
columns = 1100;
rasterSamples = rows*columns;
referenceLine = 1050;
report = struct('status','in_progress','source_kind','single stored training frame per band', ...
    'output_folder',char(outputRoot),'bands',{{}}, ...
    'phase_caveat','HSV is relative received IQ phase, not display RGB; amplitude mask is not confidence', ...
    'rf_axis_caveat','Nominal fc+baseband frequency assumes I+jQ; physical spectral polarity is unverified', ...
    'raster_caveat','1881 by 1100 is an analysis timing grid, not a verified pixel or DSI-byte grid');
for bandIndex=1:numel(centersMHz)
    centerMHz = centersMHz(bandIndex);
    inputFile = fullfile(resultRoot,'templates',sprintf('fc%dMHz',centerMHz),'templates.mat');
    saved = load(inputFile,'singleTrain','meta');
    z = saved.singleTrain(:);
    inputMeta = saved.meta;
    assert(isfield(inputMeta,'period_seconds') && isfinite(inputMeta.period_seconds) && inputMeta.period_seconds>0, ...
        'stitch:MissingPhasePeriod','A valid measured period_seconds is required.');
    period = inputMeta.period_seconds;
    sampleRate = numel(z)/period;
    assert(numel(z)>=rasterSamples,'stitch:PhaseRasterUpsampling', ...
        'This phase diagnostic requires only a slight reduction to the raster grid.');
    folder = fullfile(outputRoot,sprintf('fc%dMHz',centerMHz));
    mkdir(folder);
    [realGrid,realFilter] = resamplePeriodicAm(real(z),rasterSamples,PeriodSeconds=period);
    [imagGrid,imagFilter] = resamplePeriodicAm(imag(z),rasterSamples,PeriodSeconds=period);
    complexGrid = complex(realGrid,imagGrid);
    amGrid = resamplePeriodicAm(abs(z),rasterSamples,PeriodSeconds=period);
    amplitude = abs(complexGrid);
    thresholds = localQuantile(amplitude,[0.25 0.75]);
    valid = amplitude>thresholds(1);
    referenceIndex = find(amplitude>=thresholds(2) & amplitude>0,1);
    if isempty(referenceIndex)
        referenceIndex = 1;
    end
    phaseReference = angle(complexGrid(referenceIndex));
    relativePhase = angle(complexGrid*exp(-1i*phaseReference));
    displayLimits = localQuantile(amGrid,[0.01 0.99]);
    brightness = min(1,max(0,(double(amGrid)-displayLimits(1))/max(diff(displayLimits),eps)));
    hue = mod(double(relativePhase)+pi,2*pi)/(2*pi);
    hsvRaster = reshape(hsv2rgb([hue,double(valid),brightness]),columns,rows,3);
    hsvRaster = permute(hsvRaster,[2 1 3]);
    % Gray low-amplitude pixels preserve AM while removing unreliable hue.
    amImage = reshape(brightness,columns,rows).';
    phaseImage = reshape(double(relativePhase),columns,rows).';
    maskImage = reshape(valid,columns,rows).';
    imwrite(amImage,fullfile(folder,'am_single_frame.png'));
    imwrite(hsvRaster,fullfile(folder,'relative_phase_hsv.png'));
    imwrite(maskImage,fullfile(folder,'phase_amplitude_mask.png'));
    xUs = (0:columns-1)*(period/rows/columns)*1e6;
    yMs = (0:rows-1)*(period/rows)*1e3;
    fig = figure('Visible','off','Color','w','Position',[30 30 1600 950]);
    layout = tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
    ax = nexttile(layout);
    imagesc(ax,xUs,yMs,amImage); axis(ax,'ij');
    colormap(ax,gray(256)); clim(ax,[0 1]);
    title(ax,'AM: abs(IQ), then anti-alias reduction');
    xlabel(ax,'Within-row time (us)'); ylabel(ax,'Frame time at row start (ms)');
    ax = nexttile(layout);
    image(ax,xUs,yMs,hsvRaster); set(ax,'YDir','reverse');
    title(ax,'Relative RF phase HSV; not display RGB');
    xlabel(ax,'Within-row time (us)'); ylabel(ax,'Frame time at row start (ms)');
    ax = nexttile(layout);
    phaseHandle = imagesc(ax,xUs,yMs,phaseImage); axis(ax,'ij');
    phaseHandle.AlphaData = double(maskImage);
    ax.Color = [0.75 0.75 0.75]; colormap(ax,hsv(256)); clim(ax,[-pi pi]);
    bar = colorbar(ax); bar.Label.String = 'Relative received phase (rad)';
    title(ax,'Wrapped phase; lower 25% amplitude masked');
    xlabel(ax,'Within-row time (us)'); ylabel(ax,'Frame time at row start (ms)');
    title(layout,sprintf('iPhone 6 | fc %d MHz | one stored frame | T=%.6f ms | mask is not confidence', ...
        centerMHz,period*1e3));
    exportgraphics(fig,fullfile(folder,'phase_comparison.png'),'Resolution',130);
    close(fig);
    % Same-grid nearest sampling is an explicit no-antialias phase control.
    nearestIndices = min(numel(z),round((0:rasterSamples-1).'*numel(z)/rasterSamples)+1);
    nearestGrid = z(nearestIndices);
    nearestPhase = angle(nearestGrid*exp(-1i*phaseReference));
    phaseDifference = angle(complexGrid.*conj(nearestGrid));
    lineIndices = (referenceLine-1)*columns+(1:columns);
    lineTimeUs = (0:columns-1).'*(period/rasterSamples)*1e6;
    lineAmplitude = double(amGrid(lineIndices));
    lineFilteredMagnitude = double(amplitude(lineIndices));
    linePhaseBefore = double(nearestPhase(lineIndices));
    linePhaseAfter = double(relativePhase(lineIndices));
    lineValid = valid(lineIndices);
    trace = table(lineTimeUs,lineAmplitude(:),lineFilteredMagnitude(:), ...
        linePhaseBefore(:),linePhaseAfter(:),lineValid(:), ...
        'VariableNames',{'within_row_time_us','am_after_antialias_counts', ...
        'filtered_iq_magnitude_counts','nearest_phase_rad','filtered_phase_rad','amplitude_mask'});
    writetable(trace,fullfile(folder,'line1050_phase_trace.csv'));
    fig = figure('Visible','off','Color','w','Position',[30 30 1200 720]);
    layout = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
    ax = nexttile(layout);
    plot(ax,lineTimeUs,lineAmplitude(:),'k',lineTimeUs,lineFilteredMagnitude(:),'b');
    xlabel(ax,'Within-row time (us)'); ylabel(ax,'ADC counts'); grid(ax,'on');
    legend(ax,{'AA(abs(IQ))','abs(AA(I)+j AA(Q))'},'Location','best');
    title(ax,'Two different operation orders; nonlinear abs does not commute with filtering');
    ax = nexttile(layout);
    before = linePhaseBefore(:); after = linePhaseAfter(:);
    before(~lineValid(:)) = NaN; after(~lineValid(:)) = NaN;
    plot(ax,lineTimeUs,before,'.','MarkerSize',4); hold(ax,'on');
    plot(ax,lineTimeUs,after,'.','MarkerSize',4); hold(ax,'off');
    ylim(ax,[-pi pi]); xlabel(ax,'Within-row time (us)'); ylabel(ax,'Wrapped relative phase (rad)');
    legend(ax,{'Nearest raw-phase control (no AA)','Phase of anti-aliased I+jQ'},'Location','best');
    grid(ax,'on');
    title(layout,sprintf('fc %d MHz | analysis row %d | start %.6f ms | row time %.6f us', ...
        centerMHz,referenceLine,(referenceLine-1)*period/rows*1e3,period/rows*1e6));
    exportgraphics(fig,fullfile(folder,'line1050_phase_comparison.png'),'Resolution',140);
    close(fig);
    % Native template time grid is used for STFT; no raster reduction enters it.
    firstLine = referenceLine-1;
    firstSample = floor((firstLine-1)*numel(z)/rows);
    lastSampleExclusive = floor((firstLine+2)*numel(z)/rows);
    excerpt = z(firstSample+1:lastSampleExclusive);
    [linePsd,lineTime,lineFreq,lineStft] = explicitStftPsd(excerpt,sampleRate, ...
        256,32,1024,1,1,firstSample/sampleRate);
    [framePsd,frameTime,frameFreq,frameStft] = explicitStftPsd(z,sampleRate, ...
        2048,512,4096,8,4,0);
    plotTf(linePsd,lineTime,lineFreq,centerMHz,lineStft, ...
        fullfile(folder,'stft_three_rows.png'),'Three analysis-row excerpt (1049-1051)',firstSample/sampleRate,1e6);
    plotTf(framePsd,frameTime,frameFreq,centerMHz,frameStft, ...
        fullfile(folder,'stft_whole_frame.png'),'Whole stored frame',0,1e3);
    % Retain compact numerical PSDs, never copies of full raw IQ or templates.
    save(fullfile(folder,'tf_compact.mat'),'linePsd','lineTime','lineFreq','lineStft', ...
        'framePsd','frameTime','frameFreq','frameStft','-v7');
    bandMeta = struct();
    bandMeta.center_mhz = centerMHz;
    bandMeta.input_template = char(inputFile);
    bandMeta.template_variable = 'singleTrain';
    bandMeta.source_frame_zero_based = 0;
    bandMeta.template_sample_count = numel(z);
    bandMeta.template_sample_rate_hz = sampleRate;
    bandMeta.raw_sample_rate_hz = inputMeta.fs_hz;
    bandMeta.period_seconds = period;
    bandMeta.analysis_rows = rows;
    bandMeta.analysis_columns = columns;
    bandMeta.analysis_row_seconds = period/rows;
    bandMeta.analysis_column_time_step_seconds = period/rasterSamples;
    bandMeta.same_column_successive_row_interval_seconds = period/rows;
    bandMeta.same_column_first_to_last_row_span_seconds = (rows-1)*period/rows;
    bandMeta.time_axis_caveat = 'An image column collects samples one row period apart; it is not one contiguous column-duration signal';
    bandMeta.raster_geometry_status = 'analysis grid, not verified DSI pixel geometry';
    bandMeta.phase_reference_rad = double(phaseReference);
    bandMeta.phase_reference_raster_index_one_based = referenceIndex;
    bandMeta.phase_reference_time_seconds = (referenceIndex-1)*period/rasterSamples;
    bandMeta.phase_reference_rule = 'first complex-AA sample at or above amplitude 75th percentile; arbitrary local RF phase origin';
    bandMeta.phase_valid_amplitude_threshold_counts = thresholds(1);
    bandMeta.phase_valid_fraction = nnz(valid)/numel(valid);
    bandMeta.phase_mask_is_confidence = false;
    bandMeta.phase_is_display_rgb = false;
    bandMeta.phase_comparable_absolutely_across_bands = false;
    bandMeta.masked_nearest_to_filtered_phase_difference_rms_rad = ...
        sqrt(mean(double(phaseDifference(valid)).^2));
    bandMeta.am_display_limits_counts = displayLimits;
    bandMeta.real_component_antialias = realFilter;
    bandMeta.imag_component_antialias = imagFilter;
    bandMeta.input_processing = 'singleTrain already had fixed training DC removal and finite-guard fractional time resampling; no additional CFO/phase fit here';
    bandMeta.input_dc_removal_caveat = inputMeta.dc_removal_caveat;
    bandMeta.rf_axis_assumption = 'I+jQ and nominal fc+baseband frequency; IQ polarity and absolute RF frequency not independently verified';
    bandMeta.three_row_start_sample_zero_based = firstSample;
    bandMeta.three_row_sample_count = numel(excerpt);
    bandMeta.line_stft = lineStft;
    bandMeta.frame_stft = frameStft;
    bandMeta.frame_template_heldout_coherence = inputMeta.independent_template_comparison.complex_coherence;
    bandMeta.source_identity_caveat = 'Stable phase/stripes or TF energy cannot identify a column driver or MIPI common-mode source by themselves';
    writeJsonLocal(fullfile(folder,'metadata.json'),bandMeta);
    report.bands{bandIndex} = bandMeta;
    writeJsonLocal(fullfile(outputRoot,'overview.json'),report);
    fprintf('Phase/TF fc %d MHz: row %.6f us, line STFT %.6f us / ENBW %.3f kHz; frame STFT %.6f us / ENBW %.3f kHz\n', ...
        centerMHz,period/rows*1e6,lineStft.window_duration_seconds*1e6,lineStft.enbw_hz/1e3, ...
        frameStft.window_duration_seconds*1e6,frameStft.enbw_hz/1e3);
end
report.status = 'complete';
writeJsonLocal(fullfile(outputRoot,'overview.json'),report);
end

function [psd,timeSeconds,frequencyHz,meta] = explicitStftPsd(signal,fs,windowLength,hop,fftLength,frequencyPool,timePool,offsetSeconds)
% Explicit two-sided PSD for COMPLEX IQ; no one-sided factor of two.
window = 0.5-0.5*cos(2*pi*(0:windowLength-1).'/windowLength);
windowEnergy = sum(window.^2);
windowSum = sum(window);
starts = 0:hop:numel(signal)-windowLength;
segmentCount = numel(starts);
assert(segmentCount>0 && mod(fftLength,frequencyPool)==0,'stitch:StftGeometry','Invalid STFT geometry.');
frequencyCount = fftLength/frequencyPool;
timeCount = ceil(segmentCount/timePool);
psd = zeros(frequencyCount,timeCount,'single');
timeSeconds = zeros(1,timeCount);
frequencyNative = (-fftLength/2:fftLength/2-1).'*fs/fftLength;
frequencyHz = mean(reshape(frequencyNative,frequencyPool,frequencyCount),1).';
% Each outer block is the requested time-pooling block; native hops are all
% evaluated. Pooling is arithmetic mean of LINEAR PSD, never dB averaging.
for timeIndex=1:timeCount
    frameIndices = (timeIndex-1)*timePool+1:min(timeIndex*timePool,segmentCount);
    indices = (0:windowLength-1).'+starts(frameIndices)+1;
    segments = double(signal(indices)).*window;
    spectrum = fftshift(fft(segments,fftLength,1),1);
    nativePsd = abs(spectrum).^2/(fs*windowEnergy);
    if timeIndex==1
        integratedFirstPower = sum(nativePsd(:,1))*fs/fftLength;
        expectedFirstPower = sum(abs(segments(:,1)).^2)/windowEnergy;
        normalizationError = abs(integratedFirstPower-expectedFirstPower)/max(expectedFirstPower,realmin);
    end
    pooledFrequency = reshape(mean(reshape(nativePsd,frequencyPool,frequencyCount,numel(frameIndices)),1), ...
        frequencyCount,numel(frameIndices));
    psd(:,timeIndex) = single(mean(pooledFrequency,2));
    timeSeconds(timeIndex) = offsetSeconds+mean(starts(frameIndices)+(windowLength-1)/2)/fs;
end
meta = struct('implementation','explicit base MATLAB complex FFT, periodic Hann, two-sided PSD', ...
    'input_samples',numel(signal),'input_rate_hz',fs,'window_samples',windowLength, ...
    'window_duration_seconds',windowLength/fs,'window_endpoint_span_seconds',(windowLength-1)/fs, ...
    'hop_samples',hop,'hop_seconds',hop/fs,'overlap_samples',windowLength-hop, ...
    'fft_length',fftLength,'fft_bin_spacing_hz',fs/fftLength, ...
    'unzeropadded_bin_spacing_hz',fs/windowLength, ...
    'enbw_hz',fs*windowEnergy/windowSum^2,'hann_null_to_null_mainlobe_hz',4*fs/windowLength, ...
    'window_coherent_gain',windowSum/windowLength,'window_energy',windowEnergy, ...
    'psd_normalization','abs(FFT(x.*w)).^2/(Fs*sum(w.^2)); no factor of two for complex IQ', ...
    'units','ADC-count^2/Hz; no calibrated dBm conversion', ...
    'native_segment_count',segmentCount,'frequency_pool_bins',frequencyPool, ...
    'time_pool_segments',timePool,'display_frequency_bin_width_hz',frequencyPool*fs/fftLength, ...
    'display_nominal_time_step_seconds',timePool*hop/fs, ...
    'pooling','arithmetic mean of linear PSD; final time block may contain fewer segments', ...
    'zero_padding_improves_true_resolution',false,'segment_mean_removed',false, ...
    'boundary_handling','only complete windows; no wrap and no extra zero-padded time windows');
meta.first_window_integrated_psd_counts2 = integratedFirstPower;
meta.first_window_weighted_time_power_counts2 = expectedFirstPower;
meta.parseval_relative_error = normalizationError;
end

function plotTf(psd,timeSeconds,frequencyHz,centerMHz,meta,path,label,timeOrigin,timeScale)
psdDb = 10*log10(max(double(psd),realmin));
limits = localQuantile(psdDb,[0.01 0.995]);
if limits(2)<=limits(1)
    limits(2) = limits(1)+1;
end
fig = figure('Visible','off','Color','w','Position',[30 30 1400 720]);
ax = axes(fig);
imagesc(ax,(timeSeconds-timeOrigin)*timeScale,centerMHz+frequencyHz/1e6,psdDb);
axis(ax,'xy'); colormap(ax,turbo(256)); clim(ax,limits);
bar = colorbar(ax); bar.Label.String = 'PSD (dB re ADC-count^2/Hz)';
if timeScale==1e6
    xlabel(ax,'Time from excerpt start (us)');
else
    xlabel(ax,'Time from stored frame start (ms)');
end
ylabel(ax,'Nominal RF frequency (MHz), assuming I+jQ');
title(ax,{sprintf('fc %d MHz | %s | Hann %d, hop %d, FFT %d',centerMHz,label,meta.window_samples,meta.hop_samples,meta.fft_length), ...
    sprintf('window %.3f us | ENBW %.3f kHz | FFT spacing %.3f kHz | display pool %d frequency x %d time', ...
    meta.window_duration_seconds*1e6,meta.enbw_hz/1e3,meta.fft_bin_spacing_hz/1e3, ...
    meta.frequency_pool_bins,meta.time_pool_segments)});
exportgraphics(fig,path,'Resolution',140);
close(fig);
end

function q = localQuantile(values,probabilities)
values = sort(double(values(:)));
position = 1+(numel(values)-1)*probabilities;
lo = floor(position); hi = ceil(position);
q = values(lo).'.*(hi-position)+values(hi).'.*(position-lo);
same = lo==hi;
q(same) = values(lo(same));
end

function writeJsonLocal(path,value)
fileId = fopen(path,'w','n','UTF-8');
assert(fileId>=0,'stitch:PhaseMetadataWrite','Cannot open %s.',path);
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId,jsonencode(value,'PrettyPrint',true),'char');
end
