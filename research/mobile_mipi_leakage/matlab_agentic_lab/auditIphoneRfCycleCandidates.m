function report = auditIphoneRfCycleCandidates(options)
%AUDITIPHONERFCYCLECANDIDATES Exploratory RF tones and combs with a frozen holdout.
%   Reads immutable BE int16 IQ in ADC counts. Does not remove DC. The two
%   polarities are alternative RF coordinate conventions, not two datasets.
%   A spectral comb does not identify MIPI, a byte clock, or the lane count.
%   Default input is 2^22 samples near the start and 2^22 samples at 65% of
%   each capture. Long-window peak interpolation is not extra resolution.
arguments
    options.CentersMHz (1,:) double = 100:60:700
    options.SampleCount (1,1) double {mustBeInteger,mustBePositive} = 2^22
    options.TrainFirstSample (1,1) double {mustBeInteger,mustBeNonnegative} = 0
    options.HoldoutFraction (1,1) double = 0.65
    options.WelchLength (1,1) double {mustBeInteger,mustBePositive} = 2^17
    options.MaxPeaksPerBand (1,1) double {mustBeInteger,mustBePositive} = 64
    options.MinLocalExcessDb (1,1) double {mustBePositive} = 7
    options.LocalFloorHalfWidthHz (1,1) double {mustBePositive} = 500e3
    options.MinPeakSeparationHz (1,1) double {mustBePositive} = 20e3
    options.DcGuardHz (1,1) double {mustBePositive} = 20e3
    options.BandEdgeGuardHz (1,1) double {mustBeNonnegative} = 1.5e6
    options.CrossCenterToleranceHz (1,1) double {mustBePositive} = 8e3
    options.HoldoutMatchToleranceHz (1,1) double {mustBePositive} = 4e3
    options.CombSpacingRangeHz (1,2) double = [2e6 300e6]
    options.CombToleranceHz (1,1) double {mustBePositive} = 12e3
    options.MaxCombCandidates (1,1) double {mustBeInteger,mustBePositive} = 12
    options.HypothesisByteRateHz (1,1) double {mustBePositive} = 60.03e6
    options.OutputDirectory (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
assert(all(ismember(options.CentersMHz,100:60:700)) && ...
    numel(unique(options.CentersMHz))==numel(options.CentersMHz), ...
    'stitch:InvalidRfCenters','Use unique centers from 100:60:700 MHz.');
assert(options.SampleCount>=options.WelchLength && options.SampleCount>=2^18, ...
    'stitch:ShortRfAudit','SampleCount must cover the Welch window and be at least 2^18.');
assert(options.HoldoutFraction>0 && options.HoldoutFraction<1, ...
    'stitch:InvalidHoldoutFraction','HoldoutFraction must be strictly between zero and one.');
assert(options.CombSpacingRangeHz(1)>0 && diff(options.CombSpacingRangeHz)>0, ...
    'stitch:InvalidCombRange','Comb spacing bounds must be positive and increasing.');
fs = 124082800;
bandwidthHz = 120e6;
assert(options.BandEdgeGuardHz<bandwidthHz/2,'stitch:InvalidBandGuard','Band edge guard is too large.');
if strlength(options.OutputDirectory)==0
    outputRoot = fullfile(labRoot,'results','iphone6_followup_20261024','rf_cycle_candidates');
else
    outputRoot = options.OutputDirectory;
end
assert(~isfolder(outputRoot) && ~isfile(outputRoot),'stitch:RfAuditOutputExists', ...
    'Refusing to overwrite %s. Select a new OutputDirectory.',outputRoot);
mkdir(outputRoot);
started = tic;
report = struct('status','running','sample_rate_hz',fs,'sample_rate_source','user reported', ...
    'capture_bandwidth_hz',bandwidthHz,'capture_bandwidth_source','user reported', ...
    'options',options,'output_directory',outputRoot,'bands',{{}},'polarity_reports',{{}}, ...
    'dc_removed',false,'raw_modified',false,'matlab_version',version, ...
    'frequency_calibration','No receiver LO/clock accuracy or absolute RF uncertainty supplied.', ...
    'inference','Exploratory RF structure only. No MIPI, lane-count or byte-clock identification.');
report.time_scale_references = struct('nominal_line_samples',1100, ...
    'analysis_lines_per_frame',1881,'nominal_line_seconds',1100/fs, ...
    'nominal_frame_samples',2069100,'line_reference_hz',fs/1100, ...
    'frame_reference_hz',fs/2069100, ...
    'provenance','Previously observed reconstruction periods; not authenticated DSI packet/panel timing.', ...
    'block_seconds',options.SampleCount/fs,'long_fft_bin_hz',fs/options.SampleCount, ...
    'hann_null_to_null_mainlobe_hz',4*fs/options.SampleCount, ...
    'frame_sideband_warning','Default block spans about two frames; Hann cannot cleanly resolve adjacent frame-rate sidebands.');
report.hypothesis = struct('byte_rate_hz',options.HypothesisByteRateHz, ...
    'label','Declared conditional seed, not measured. 750*1334*60 for N=3 and payload duty1.', ...
    'lane_count_measured',false,'seed_only_not_fixed_clock',true);
writeJsonFile(fullfile(outputRoot,'overview.json'),report);
allTrain = repmat(emptyPeak(),0,1);
allHeldout = repmat(emptyPeak(),0,1);
spectra = cell(numel(options.CentersMHz),1);
for bandIndex=1:numel(options.CentersMHz)
    fcMHz = options.CentersMHz(bandIndex);
    fprintf('RF cycle audit %d/%d: fc=%d MHz\n',bandIndex,numel(options.CentersMHz),fcMHz);
    band = struct('fc_mhz',fcMHz,'status','running');
    bandRoot = fullfile(outputRoot,sprintf('fc%dMHz',fcMHz));
    mkdir(bandRoot);
    try
        [rawPath,identity] = resolveIphoneSweepCapture(fcMHz);
        totalSamples = identity.bytes/4;
        trainStart = options.TrainFirstSample;
        heldoutStart = min(floor(options.HoldoutFraction*totalSamples),totalSamples-options.SampleCount);
        assert(heldoutStart>=trainStart+options.SampleCount, ...
            'stitch:OverlappingRfBlocks','Training and held-out blocks must be disjoint.');
        [train,trainPsd,frequency,trainMeta] = inspectBlock(rawPath,trainStart, ...
            fcMHz,'train',fs,bandwidthHz,options);
        [test,testPsd,frequencyTest,testMeta] = inspectBlock(rawPath,heldoutStart, ...
            fcMHz,'heldout',fs,bandwidthHz,options);
        assert(isequal(frequency,frequencyTest),'stitch:RfGridMismatch','Welch frequency grids differ.');
        train = pairHeldout(train,test,options.HoldoutMatchToleranceHz);
        allTrain = [allTrain;train]; %#ok<AGROW>
        allHeldout = [allHeldout;test]; %#ok<AGROW>
        spectra{bandIndex} = struct('fc_mhz',fcMHz,'baseband_hz',frequency, ...
            'train_psd',trainPsd,'heldout_psd',testPsd);
        band.status = 'complete';
        band.identity = identity;
        band.train = trainMeta;
        band.heldout = testMeta;
        band.training_peaks = train;
        band.heldout_peaks = test;
        band.holdout_matching = 'One-to-one nearest refined peak, fixed tolerance; no holdout-driven training peak selection.';
        band.persistent_training_peak_count = sum([train.heldout_matched]);
        band.neighbor_spacing_train_hz = localNeighborSpacings(train);
        writePeakCsv(fullfile(bandRoot,'train_peaks_baseband.csv'),train);
        writePeakCsv(fullfile(bandRoot,'heldout_peaks_baseband.csv'),test);
        save(fullfile(bandRoot,'welch_psd.mat'),'frequency','trainPsd','testPsd','trainMeta','testMeta','-v7');
        plotBandEvidence(spectra{bandIndex},train,report.time_scale_references,bandRoot);
        clear trainPsd testPsd frequency frequencyTest
    catch exception
        band.status = 'failed';
        band.error_identifier = exception.identifier;
        band.error_message = exception.message;
        warning('stitch:RfBandFailed','fc%d MHz: %s',fcMHz,exception.message);
    end
    report.bands{end+1,1} = band;
    writeJsonFile(fullfile(bandRoot,'overview.json'),band);
    writeJsonFile(fullfile(outputRoot,'overview.json'),report);
end
for polarity=[1 -1]
    polarityRoot = fullfile(outputRoot,sprintf('polarity_%+d',polarity));
    mkdir(polarityRoot);
    trainRf = mapToRf(allTrain,polarity);
    heldoutRf = mapToRf(allHeldout,polarity);
    groups = groupIndependentCenters(trainRf,options.CrossCenterToleranceHz);
    [combs,fitMeta] = findCombCandidates(groups,options);
    independentFits = perCaptureCombFits(combs,trainRf);
    writePeakCsv(fullfile(polarityRoot,'training_peaks_rf.csv'),trainRf);
    writePeakCsv(fullfile(polarityRoot,'heldout_peaks_rf.csv'),heldoutRf);
    writeStructCsv(fullfile(polarityRoot,'cross_center_groups.csv'),groups);
    writeStructCsv(fullfile(polarityRoot,'comb_candidates.csv'),stripCombArrays(combs));
    writeStructCsv(fullfile(polarityRoot,'independent_center_fits.csv'),independentFits);
    pReport = struct('polarity',polarity,'rf_mapping','f_RF = fc + polarity*f_baseband', ...
        'cross_center_groups',groups,'comb_candidates',combs,'fit_metadata',fitMeta, ...
        'independent_center_fits',independentFits, ...
        'heldout_policy','All comb seeds, membership and fit parameters use training only. Heldout residuals use frozen training tooth indices.', ...
        'warning','A free-offset comb spacing is not necessarily a clock fundamental. Subharmonic aliases and common periodic clutter remain.');
    report.polarity_reports{end+1,1} = pReport;
    writeJsonFile(fullfile(polarityRoot,'overview.json'),pReport);
    plotRfOverview(spectra,groups,combs,polarity,polarityRoot);
end
report.failed_band_count = sum(cellfun(@(x) ~strcmp(x.status,'complete'),report.bands));
report.status = 'complete';
if report.failed_band_count>0
    report.status = 'completed_with_failed_bands';
end
report.elapsed_seconds = toc(started);
report.actual_read_bytes_expected_for_complete_run = 8*options.SampleCount*numel(options.CentersMHz);
report.notes = {'Local flank-median excess is not MATLAB topographic prominence and not SNR.', ...
    'Peak error floors are resolution/drift diagnostics, not calibrated absolute RF confidence intervals.', ...
    'Formal comb fit standard errors condition on selected tooth assignments; model-search uncertainty is not included.', ...
    'No subtraction, resampling, coherent averaging, demodulation or raw modification was performed.'};
writeJsonFile(fullfile(outputRoot,'overview.json'),report);
fprintf('RF cycle audit %s in %.1f s: %s\n',report.status,report.elapsed_seconds,outputRoot);
end

function [peaks,psd,f,meta] = inspectBlock(rawPath,firstSample,fcMHz,split,fs,bw,opt)
[x,readInfo] = readRisIqBlock(rawPath,firstSample,opt.SampleCount);
assert(all(isfinite(real(x))) && all(isfinite(imag(x))),'stitch:NonfiniteRfInput','IQ contains non-finite values.');
meanIq = mean(x,'double');
powerTime = mean(abs(double(x)).^2);
meta = struct('read',readInfo,'fc_mhz',fcMHz,'split',split, ...
    'mean_i_counts',real(meanIq),'mean_q_counts',imag(meanIq), ...
    'mean_complex_power_fraction',abs(meanIq)^2/max(powerTime,realmin), ...
    'mean_square_counts2',powerTime, ...
    'i_rail_fraction',mean(real(x)==-32768 | real(x)==32767), ...
    'q_rail_fraction',mean(imag(x)==-32768 | imag(x)==32767), ...
    'dc_removed',false,'sample_continuity','No acquisition overflow/late-sample metadata available.');
w = hannPeriodic(opt.WelchLength);
[psd,f,welchMeta] = estimateWelchPsd(x,w,floor(numel(w)/2),numel(w),fs,'centered');
y = safeDb(psd);
df = fs/numel(w);
meta.welch = welchMeta;
meta.welch_integral_counts2 = sum(psd)*df;
meta.welch_integral_relative_to_time_power = sum(psd)*df/max(powerTime,realmin);
[~,dcBin] = min(abs(f));
meta.dc_bin_psd_counts2_per_hz = psd(dcBin);
meta.dc_guard_hz = opt.DcGuardHz;
% Keep DC in every PSD. The guard only marks/excludes peaks from comb fits.
floorHalfBins = max(8,round(opt.LocalFloorHalfWidthHz/df));
baseline = movmedian(y,2*floorHalfBins+1,'Endpoints','shrink');
localSpread = 1.4826*movmedian(abs(y-baseline),2*floorHalfBins+1,'Endpoints','shrink');
isLocalMaximum = [false;y(2:end-1)>y(1:end-2) & y(2:end-1)>=y(3:end);false];
threshold = max(opt.MinLocalExcessDb,4*localSpread);
indices = find(isLocalMaximum & y-baseline>=threshold & abs(f)<bw/2);
excess = zeros(numel(indices),1);
for k=1:numel(indices)
    j=indices(k);
    left=y(max(1,j-floorHalfBins):max(1,j-4));
    right=y(min(numel(y),j+4):min(numel(y),j+floorHalfBins));
    excess(k)=y(j)-max(median(left),median(right));
end
keep=excess>=opt.MinLocalExcessDb;
indices=indices(keep);excess=excess(keep);
[~,order]=sort(excess,'descend');
chosen=zeros(0,1);chosenExcess=zeros(0,1);
for k=reshape(order,1,[])
    j=indices(k);
    if isempty(chosen) || all(abs(f(j)-f(chosen))>=opt.MinPeakSeparationHz)
        chosen(end+1,1)=j; %#ok<AGROW>
        chosenExcess(end+1,1)=excess(k); %#ok<AGROW>
        if numel(chosen)>=opt.MaxPeaksPerBand,break;end
    end
end
% A single long-window Welch segment is a periodogram with exactly the same
% explicit normalization. The helper chooses pwelch or its base MATLAB path.
longWindow=hannPeriodic(numel(x));
[longPsd,longF,longMeta]=estimateWelchPsd(x,longWindow,0,numel(x),fs,'centered');
weightedTime=sum(abs(double(x)).^2.*longWindow.^2)/sum(longWindow.^2);
longDf=fs/numel(x);
parsevalRatio=sum(longPsd)*longDf/max(weightedTime,realmin);
assert(abs(parsevalRatio-1)<1e-5,'stitch:RfPsdNormalization', ...
    'Long-window PSD normalization differs from window-weighted time power.');
meta.long_periodogram=longMeta;
meta.long_periodogram_parseval_ratio=parsevalRatio;
meta.frequency_error_note='Interpolation error floor is half ENBW; no absolute receiver calibration is available.';
longDb=safeDb(longPsd);
peaks=repmat(emptyPeak(),numel(chosen),1);
searchHalfBins=max(2,ceil(2*df/longDf));
for k=1:numel(chosen)
    coarse=chosen(k);
    center=round((f(coarse)-longF(1))/longDf)+1;
    neighborhood=max(2,center-searchHalfBins):min(numel(longPsd)-1,center+searchHalfBins);
    [~,maximum]=max(longPsd(neighborhood));
    j=neighborhood(maximum);
    denominator=longDb(j-1)-2*longDb(j)+longDb(j+1);
    fractional=0;
    if denominator<0
        fractional=max(-0.5,min(0.5,0.5*(longDb(j-1)-longDb(j+1))/denominator));
    end
    frequency=longF(j)+fractional*longDf;
    row=emptyPeak();
    row.peak_id=k;row.fc_mhz=fcMHz;row.split=string(split);
    row.baseband_hz=frequency;
    row.frequency_uncertainty_floor_hz=max(longDf/2,longMeta.enbw_hz/2);
    row.welch_local_excess_db=chosenExcess(k);
    row.welch_psd_counts2_per_hz=psd(coarse);
    row.welch_width_3db_hz=peakWidth(y,coarse,df,128);
    row.refined_psd_counts2_per_hz=longPsd(j);
    row.refined_width_3db_hz=peakWidth(longDb,j,longDf,searchHalfBins*4);
    row.is_dc_or_lo=abs(frequency)<=opt.DcGuardHz;
    row.is_band_edge=abs(frequency)>=bw/2-opt.BandEdgeGuardHz;
    row.is_narrow_tone=row.welch_width_3db_hz<=12*df;
    row.use_for_comb=~row.is_dc_or_lo && ~row.is_band_edge && row.is_narrow_tone;
    peaks(k)=row;
end
meta.detected_peak_count=numel(peaks);
meta.eligible_tone_count=sum([peaks.use_for_comb]);
meta.detection='Local maxima above max(7dB default,4 local robust MAD); bilateral flank median; greedy frequency separation.';
end

function row=emptyPeak()
row=struct('peak_id',0,'fc_mhz',NaN,'split',"",'baseband_hz',NaN, ...
    'rf_hz',NaN,'polarity',0,'frequency_uncertainty_floor_hz',NaN, ...
    'welch_local_excess_db',NaN,'welch_psd_counts2_per_hz',NaN, ...
    'welch_width_3db_hz',NaN,'refined_psd_counts2_per_hz',NaN, ...
    'refined_width_3db_hz',NaN,'is_dc_or_lo',false,'is_band_edge',false, ...
    'is_narrow_tone',false,'use_for_comb',false,'heldout_matched',false, ...
    'heldout_baseband_hz',NaN,'heldout_rf_hz',NaN,'heldout_frequency_change_hz',NaN, ...
    'heldout_local_excess_db',NaN);
end

function train=pairHeldout(train,test,tolerance)
used=false(numel(test),1);
for k=1:numel(train)
    if isempty(test),break;end
    distances=abs([test.baseband_hz].'-train(k).baseband_hz);
    distances(used)=Inf;
    [distance,index]=min(distances);
    if distance<=tolerance
        used(index)=true;
        train(k).heldout_matched=true;
        train(k).heldout_baseband_hz=test(index).baseband_hz;
        train(k).heldout_frequency_change_hz=test(index).baseband_hz-train(k).baseband_hz;
        train(k).heldout_local_excess_db=test(index).welch_local_excess_db;
    end
end
end

function rows=mapToRf(rows,polarity)
for k=1:numel(rows)
    rows(k).polarity=polarity;
    rows(k).rf_hz=rows(k).fc_mhz*1e6+polarity*rows(k).baseband_hz;
    if rows(k).heldout_matched
        rows(k).heldout_rf_hz=rows(k).fc_mhz*1e6+polarity*rows(k).heldout_baseband_hz;
    end
end
end

function values=localNeighborSpacings(peaks)
if isempty(peaks),values=[];return;end
frequencies=sort([peaks([peaks.use_for_comb]).baseband_hz]);
values=diff(frequencies);
values=values(values<1e6);
end

function groups=groupIndependentCenters(peaks,tolerance)
prototype=struct('group_id',0,'rf_hz',NaN,'frequency_error_floor_hz',NaN, ...
    'cross_center_spread_hz',NaN,'source_center_count',0,'source_centers_mhz',"", ...
    'training_peak_count',0,'mean_local_excess_db',NaN,'heldout_center_count',0, ...
    'heldout_rf_hz',NaN,'heldout_frequency_change_hz',NaN);
groups=repmat(prototype,0,1);
if isempty(peaks),return;end
peaks=peaks([peaks.use_for_comb]);
if isempty(peaks),return;end
[~,order]=sort([peaks.rf_hz]);peaks=peaks(order);
first=1;
while first<=numel(peaks)
    last=first;
    while last<numel(peaks) && peaks(last+1).rf_hz-peaks(first).rf_hz<=tolerance
        last=last+1;
    end
    members=peaks(first:last);
    row=prototype;
    row.group_id=numel(groups)+1;
    row.rf_hz=mean([members.rf_hz]);
    row.cross_center_spread_hz=max([members.rf_hz])-min([members.rf_hz]);
    row.frequency_error_floor_hz=max(median([members.frequency_uncertainty_floor_hz]), ...
        max(abs([members.rf_hz]-row.rf_hz)));
    centers=unique([members.fc_mhz]);
    row.source_center_count=numel(centers);
    row.source_centers_mhz=strjoin(string(centers),' ');
    row.training_peak_count=numel(members);
    row.mean_local_excess_db=mean([members.welch_local_excess_db]);
    persistentMembers=members([members.heldout_matched]);
    if ~isempty(persistentMembers)
        row.heldout_center_count=numel(unique([persistentMembers.fc_mhz]));
        row.heldout_rf_hz=mean([persistentMembers.heldout_rf_hz]);
        % Compare the SAME subset of centers, avoiding a changed averaging set.
        row.heldout_frequency_change_hz=mean([persistentMembers.heldout_rf_hz]-[persistentMembers.rf_hz]);
    end
    groups(end+1,1)=row; %#ok<AGROW>
    first=last+1;
end
end

function [models,meta]=findCombCandidates(groups,opt)
models=repmat(emptyComb(),0,1);
meta=struct('fit_split','training only','spacing_range_hz',opt.CombSpacingRangeHz, ...
    'match_tolerance_hz',opt.CombToleranceHz,'minimum_unique_teeth',3, ...
    'search_kind','Pair differences divided by integers1:32; free-offset and zero-offset fits.', ...
    'uncertainty_scope','OLS conditional on selected inliers/integers; not a global hypothesis-test confidence interval.', ...
    'source_identity','Unknown. A repeated comb can be clock, packet structure, periodic clutter or a mixture.');
if numel(groups)<3
    meta.status='insufficient_training_peaks';return
end
replicated=[groups.source_center_count]>=2;
if sum(replicated)>=4
    fitting=groups(replicated);
    meta.training_support_policy='Only RF groups repeated in at least two independently tuned centers.';
else
    fitting=groups;
    meta.training_support_policy='Fallback includes single-center groups; fewer than four cross-center groups available.';
end
priority=100*[fitting.source_center_count]+[fitting.mean_local_excess_db];
[~,order]=sort(priority,'descend');
fitting=fitting(order(1:min(160,numel(order))));
f=[fitting.rf_hz].';
quantum=max(1000,opt.CombToleranceHz/2);
values=zeros(0,1);
for first=1:numel(f)-1
    differences=abs(f(first+1:end)-f(first));
    differences=differences(differences>=max(10e6,2*opt.CombSpacingRangeHz(1)));
    candidates=differences./(1:32);
    values=[values;candidates(:)]; %#ok<AGROW>
end
values=values(values>=opt.CombSpacingRangeHz(1) & values<=opt.CombSpacingRangeHz(2));
seeds=zeros(0,1);seedLabels=strings(0,1);
if ~isempty(values)
    [bins,~,membership]=unique(round(values/quantum));
    votes=accumarray(membership,1);
    [~,order]=sort(votes,'descend');
    for index=reshape(order,1,[])
        candidate=median(values(membership==index));
        if isempty(seeds) || all(abs(seeds-candidate)>=2*quantum)
            seeds(end+1,1)=candidate; %#ok<AGROW>
            seedLabels(end+1,1)="training pair-difference candidate"; %#ok<AGROW>
        end
        if numel(seeds)>=48,break;end
    end
    meta.pair_difference_bin_count=numel(bins);
end
% These are labelled hypotheses even if another data-derived seed is nearby.
for ratio=[1 1/3 4]
    candidate=opt.HypothesisByteRateHz*ratio;
    if candidate>=opt.CombSpacingRangeHz(1) && candidate<=opt.CombSpacingRangeHz(2)
        seeds(end+1,1)=candidate; %#ok<AGROW>
        seedLabels(end+1,1)=sprintf('declared %.9g MHz byte-rate hypothesis times %.6g; not a measured clock',opt.HypothesisByteRateHz/1e6,ratio); %#ok<AGROW>
    end
end
meta.seed_count=numel(seeds);
meta.selected_training_group_count=numel(fitting);
for seedIndex=1:numel(seeds)
    for mode=["free_offset","zero_offset_harmonics"]
        candidate=fitOneComb(fitting,seeds(seedIndex),mode,quantum,opt.CombToleranceHz);
        if candidate.valid
            candidate.seed_hz=seeds(seedIndex);
            candidate.seed_source=seedLabels(seedIndex);
            models(end+1,1)=candidate; %#ok<AGROW>
        end
    end
end
if isempty(models)
    meta.status='no_supported_comb';return
end
[~,order]=sort([models.exploratory_score],'descend');
kept=repmat(emptyComb(),0,1);
for k=reshape(order,1,[])
    candidate=models(k);
    duplicate=false;
    for j=1:numel(kept)
        sameKind=strcmp(candidate.model_kind,kept(j).model_kind);
        sameSpacing=abs(candidate.spacing_hz-kept(j).spacing_hz)<max(2*quantum,3*candidate.spacing_conditional_se_hz);
        offsetDistance=abs(candidate.offset_hz-kept(j).offset_hz);
        offsetDistance=min(offsetDistance,abs(offsetDistance-candidate.spacing_hz));
        if sameKind && sameSpacing && offsetDistance<2*opt.CombToleranceHz
            duplicate=true;break
        end
    end
    if ~duplicate
        candidate.model_id=numel(kept)+1;
        kept(end+1,1)=candidate; %#ok<AGROW>
        if numel(kept)>=opt.MaxCombCandidates,break;end
    end
end
models=kept;
meta.status='exploratory_candidates_available';
meta.alias_warning='Small spacings and their multiples may describe the same finite set. Candidate ranking does not resolve subharmonic aliases.';
end

function best=fitOneComb(groups,seed,mode,quantum,tolerance)
best=emptyComb();
f=[groups.rf_hz].';
errorFloor=[groups.frequency_error_floor_hz].';
if mode=="free_offset"
    anchors=f(1:min(12,numel(f)));
else
    anchors=0;
end
for anchor=reshape(anchors,1,[])
    spacing=seed;offset=anchor;
    selected=[];teeth=[];
    for iteration=1:5
        allTeeth=round((f-offset)/spacing);
        residual=f-offset-allTeeth*spacing;
        activeTolerance=tolerance;
        if iteration==1
            activeTolerance=tolerance+quantum*max(1,rangeBase(f)/spacing);
        end
        selected=find(abs(residual)<=activeTolerance);
        if mode=="zero_offset_harmonics"
            selected=selected(allTeeth(selected)>0);
        end
        selected=onePerTooth(selected,allTeeth,residual);
        if numel(selected)<3,break;end
        teeth=allTeeth(selected);
        if mode=="free_offset"
            fit=[ones(numel(teeth),1),teeth]\f(selected);
            offset=fit(1);spacing=fit(2);
        else
            spacing=(teeth.'*f(selected))/(teeth.'*teeth);
            offset=0;
        end
        if ~isfinite(spacing) || spacing<=0 || abs(spacing-seed)>max(10*quantum,0.005*seed)
            selected=[];break
        end
    end
    if numel(selected)<3,continue;end
    residual=f(selected)-offset-teeth*spacing;
    keep=abs(residual)<=tolerance;
    selected=selected(keep);teeth=teeth(keep);residual=residual(keep);
    if numel(selected)<3 || max(teeth)-min(teeth)<2,continue;end
    % Fit again after trimming so conditional errors describe these final
    % training members. Reject a fit that sends any retained tooth outside
    % tolerance; do not hide a changed membership in the error estimate.
    if mode=="free_offset"
        fit=[ones(numel(teeth),1),teeth]\f(selected);
        offset=fit(1);spacing=fit(2);
    else
        spacing=(teeth.'*f(selected))/(teeth.'*teeth);
        offset=0;
    end
    residual=f(selected)-offset-teeth*spacing;
    if ~isfinite(spacing) || spacing<=0 || ...
            abs(spacing-seed)>max(10*quantum,0.005*seed) || any(abs(residual)>tolerance)
        continue
    end
    % Normalize a free comb's intercept without changing any assigned tooth.
    if mode=="free_offset"
        shift=floor(offset/spacing);
        offset=offset-shift*spacing;teeth=teeth+shift;
        design=[ones(numel(teeth),1),teeth];
        dof=numel(teeth)-2;
        covariance=pinv(design.'*design);
        variance=max(sum(residual.^2)/max(1,dof),median(errorFloor(selected))^2);
        spacingSe=sqrt(variance*covariance(2,2));
        offsetSe=sqrt(variance*covariance(1,1));
    else
        dof=numel(teeth)-1;
        variance=max(sum(residual.^2)/max(1,dof),median(errorFloor(selected))^2);
        spacingSe=sqrt(variance/sum(teeth.^2));offsetSe=0;
    end
    row=emptyComb();row.valid=true;row.model_kind=mode;
    row.spacing_hz=spacing;row.offset_hz=offset;
    row.spacing_conditional_se_hz=spacingSe;row.offset_conditional_se_hz=offsetSe;
    row.training_unique_teeth=numel(selected);
    row.training_rms_residual_hz=sqrt(mean(residual.^2));
    row.training_max_abs_residual_hz=max(abs(residual));
    row.training_frequency_span_hz=max(f(selected))-min(f(selected));
    row.cross_center_replicated_teeth=sum([groups(selected).source_center_count]>=2);
    row.training_group_ids=[groups(selected).group_id];
    row.tooth_indices=teeth.';
    row.training_residuals_hz=residual.';
    row.tolerance_hz=tolerance;
    row.expected_uniform_accidental_matches=numel(f)*min(1,2*tolerance/spacing);
    % Descriptive ranking only; no calibrated p value, no MIPI prior bonus.
    row.exploratory_score=numel(selected)-row.expected_uniform_accidental_matches ...
        +0.25*row.cross_center_replicated_teeth-row.training_rms_residual_hz/tolerance;
    heldout=[groups(selected).heldout_rf_hz].';
    available=isfinite(heldout);
    testResidual=heldout-(offset+teeth*spacing);
    row.heldout_available_teeth=sum(available);
    row.heldout_matching_teeth=sum(available & abs(testResidual)<=tolerance);
    row.heldout_residuals_hz=testResidual.';
    if any(available)
        row.heldout_rms_residual_hz=sqrt(mean(testResidual(available).^2));
        row.heldout_max_abs_residual_hz=max(abs(testResidual(available)));
    end
    row.validation_status="not_validated";
    if row.heldout_matching_teeth>=3
        row.validation_status="at_least_three_frozen_teeth_persist; source unknown";
    end
    if ~best.valid || row.exploratory_score>best.exploratory_score
        best=row;
    end
end
end

function indices=onePerTooth(indices,teeth,residual)
if isempty(indices),return;end
[~,order]=sort(abs(residual(indices)),'ascend');
indices=indices(order);
[~,first]=unique(teeth(indices),'stable');
indices=indices(first);
end

function row=emptyComb()
row=struct('valid',false,'model_id',0,'model_kind',"",'seed_hz',NaN,'seed_source',"", ...
    'spacing_hz',NaN,'offset_hz',NaN,'spacing_conditional_se_hz',NaN, ...
    'offset_conditional_se_hz',NaN,'training_unique_teeth',0, ...
    'training_rms_residual_hz',NaN,'training_max_abs_residual_hz',NaN, ...
    'training_frequency_span_hz',NaN,'cross_center_replicated_teeth',0, ...
    'training_group_ids',[],'tooth_indices',[],'training_residuals_hz',[], ...
    'tolerance_hz',NaN,'expected_uniform_accidental_matches',NaN, ...
    'exploratory_score',-Inf,'heldout_available_teeth',0,'heldout_matching_teeth',0, ...
    'heldout_rms_residual_hz',NaN,'heldout_max_abs_residual_hz',NaN, ...
    'heldout_residuals_hz',[],'validation_status',"");
end

function rows=perCaptureCombFits(models,peaks)
prototype=struct('model_id',0,'model_kind',"",'fc_mhz',NaN,'unique_teeth',0, ...
    'spacing_hz',NaN,'offset_hz',NaN,'spacing_error_floor_hz',NaN, ...
    'rms_residual_hz',NaN,'note',"Local free-offset fit for receiver-center consistency; never used to retune global/heldout model.");
rows=repmat(prototype,0,1);
if isempty(peaks),return;end
peaks=peaks([peaks.use_for_comb]);
for modelIndex=1:numel(models)
    model=models(modelIndex);
    for fc=unique([peaks.fc_mhz])
        p=peaks([peaks.fc_mhz]==fc);
        f=[p.rf_hz].';
        teeth=round((f-model.offset_hz)/model.spacing_hz);
        residual=f-model.offset_hz-teeth*model.spacing_hz;
        selected=find(abs(residual)<=model.tolerance_hz);
        selected=onePerTooth(selected,teeth,residual);
        if numel(selected)<2,continue;end
        k=teeth(selected);f=f(selected);
        design=[ones(numel(k),1),k];fit=design\f;
        residual=f-design*fit;
        floorHz=median([p(selected).frequency_uncertainty_floor_hz]);
        variance=max(mean(residual.^2),floorHz^2);
        covariance=pinv(design.'*design);
        row=prototype;row.model_id=model.model_id;row.model_kind=model.model_kind;row.fc_mhz=fc;
        row.unique_teeth=numel(k);row.spacing_hz=fit(2);row.offset_hz=fit(1);
        row.spacing_error_floor_hz=sqrt(variance*covariance(2,2));
        row.rms_residual_hz=sqrt(mean(residual.^2));
        if numel(k)==2
            row.note=row.note+" Two points determine a line exactly; this is not an independent goodness-of-fit test.";
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end
end

function rows=stripCombArrays(models)
rows=rmfield(models,{'training_group_ids','tooth_indices','training_residuals_hz','heldout_residuals_hz'});
end

function plotBandEvidence(s,train,timeReference,outputRoot)
figureHandle=figure('Visible','off','Position',[50 50 1400 900]);
cleanup=onCleanup(@() close(figureHandle));
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
for polarity=[1 -1]
    nexttile;
    [fTrain,yTrain]=displaySpectrum(s.baseband_hz,s.train_psd,8192);
    [fTest,yTest]=displaySpectrum(s.baseband_hz,s.heldout_psd,8192);
    plot((s.fc_mhz*1e6+polarity*fTrain)/1e6,yTrain,'DisplayName','train');hold on;
    plot((s.fc_mhz*1e6+polarity*fTest)/1e6,yTest,'DisplayName','heldout');
    if ~isempty(train)
        scatter((s.fc_mhz*1e6+polarity*[train.baseband_hz])/1e6, ...
            safeDb([train.welch_psd_counts2_per_hz]),14,'filled','DisplayName','training peaks');
    end
    xline(s.fc_mhz,'k:','LO/DC');grid on;
    xlabel('RF coordinate (MHz)');ylabel('PSD (dB ADC counts^2/Hz)');
    title(sprintf('fc%d, polarity%+d; DC retained',s.fc_mhz,polarity));legend('Location','best');
end
nexttile;
if ~isempty(train)
    eligible=find([train.use_for_comb],1);
    if isempty(eligible),eligible=1;end
    peak=train(eligible).baseband_hz;
    span=6*timeReference.line_reference_hz;
    selected=abs(s.baseband_hz-peak)<=span;
    plot((s.baseband_hz(selected)-peak)/1e3,safeDb(s.train_psd(selected)));hold on;
    plot((s.baseband_hz(selected)-peak)/1e3,safeDb(s.heldout_psd(selected)));
    for integer=-5:5
        xline(integer*timeReference.line_reference_hz/1e3,':','Color',[0.6 0.6 0.6]);
    end
    xlabel('Offset from strongest selected tone (kHz)');ylabel('PSD (dB ADC counts^2/Hz)');
    title('Nominal row-period guide; guides are not detected sidebands');grid on;
else
    text(0.1,0.5,'No prominent training peaks');axis off;
end
nexttile;
spacings=localNeighborSpacings(train);
if ~isempty(spacings)
    histogram(spacings/1e3,0:10:1000);hold on;
    xline(timeReference.line_reference_hz/1e3,'r:','prior row rate');
    xlabel('Adjacent selected-tone difference (kHz)');ylabel('Count');grid on;
    title('Sub-MHz differences; peak selection limits this view');
else
    text(0.1,0.5,'No selected-tone spacings below 1 MHz');axis off;
end
sgtitle(sprintf('Independent raw chunks; %d/%d selected training peaks persist. HSV/RGB not inferred.', ...
    sum([train.heldout_matched]),numel(train)));
exportgraphics(figureHandle,fullfile(outputRoot,'psd_and_modulation_guides.png'),'Resolution',140);
end

function plotRfOverview(spectra,groups,models,polarity,outputRoot)
figureHandle=figure('Visible','off','Position',[50 50 1500 900]);
cleanup=onCleanup(@() close(figureHandle));
tiledlayout(2,1,'Padding','compact','TileSpacing','compact');
nexttile;hold on;
for k=1:numel(spectra)
    if isempty(spectra{k}),continue;end
    s=spectra{k};[f,y]=displaySpectrum(s.baseband_hz,s.train_psd,4096);
    plot((s.fc_mhz*1e6+polarity*f)/1e6,y,'DisplayName',sprintf('fc%d',s.fc_mhz));
end
xlabel('RF coordinate (MHz)');ylabel('PSD (dB ADC counts^2/Hz)');grid on;legend('Location','eastoutside');
title(sprintf('Polarity%+d: independent raw spectra, display max-pooled; no gain equalization',polarity));
nexttile;hold on;
if ~isempty(groups)
    f=[groups.rf_hz]/1e6;
    stem(f,[groups.mean_local_excess_db],'.','DisplayName','training RF groups');
    for k=1:min(3,numel(models))
        m=models(k);low=floor((min(f)*1e6-m.offset_hz)/m.spacing_hz);high=ceil((max(f)*1e6-m.offset_hz)/m.spacing_hz);
        gridHz=m.offset_hz+(low:high)*m.spacing_hz;
        plot(gridHz/1e6,repmat(-3*k,size(gridHz)),'|', ...
            'DisplayName',sprintf('%s %.6f MHz, heldout%d/%d',m.model_kind,m.spacing_hz/1e6,m.heldout_matching_teeth,m.training_unique_teeth));
    end
end
xlabel('RF coordinate (MHz)');ylabel('Local median excess (dB); guides below zero');grid on;legend('Location','best');
title('Exploratory fitted comb guides; clock and MIPI attribution unproved');
exportgraphics(figureHandle,fullfile(outputRoot,'rf_psd_and_comb_candidates.png'),'Resolution',150);
end

function [frequency,decibels]=displaySpectrum(f,p,maxPoints)
block=max(1,ceil(numel(f)/maxPoints));
last=block*floor(numel(f)/block);
frequency=mean(reshape(f(1:last),block,[]),1).';
decibels=safeDb(max(reshape(p(1:last),block,[]),[],1).');
end

function value=peakWidth(y,index,df,limit)
left=index;right=index;threshold=y(index)-3;
while left>max(1,index-limit) && y(left-1)>threshold,left=left-1;end
while right<min(numel(y),index+limit) && y(right+1)>threshold,right=right+1;end
value=(right-left+1)*df;
end

function w=hannPeriodic(n)
w=0.5-0.5*cos(2*pi*(0:n-1).'/n);
end

function y=safeDb(p)
p=max(real(p),realmin('double'));
if exist('pow2db','file')>0
    y=pow2db(p);
else
    % Base-MATLAB fallback requested for portable execution.
    y=10*log10(p);
end
end

function value=rangeBase(x)
value=max(x)-min(x);
end

function writePeakCsv(file,peaks)
writeStructCsv(file,peaks);
end

function writeStructCsv(file,rows)
writetable(struct2table(rows),file);
end
