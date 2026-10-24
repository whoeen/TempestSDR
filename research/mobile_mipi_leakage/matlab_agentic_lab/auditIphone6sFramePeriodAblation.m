function report = auditIphone6sFramePeriodAblation(options)
%AUDITIPHONE6SFRAMEPERIODABLATION Six-arm frame-period and interpolator control.
%   Six arms: precise period / saved aligned / rounded period, each sampled with
%   nearest / cubic interpolation. No phase fitting, DC removal, gain fitting,
%   screenshot matching, contrast optimization or column-profile removal.
%   Prior origins were estimated using the full received mixture; these are
%   conditional ablations, not independent ground-truth image validation.
arguments
    options.FrameCount (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive} = 32
    options.RawPath (1,1) string = ""
    options.OutputFolder (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
priorRoot = fullfile(labRoot,'results','iphone_recovery_20261023','iphone6s_P032');
prior = load(fullfile(priorRoot,'raster_final.mat'),'device','activeRows','activeCols', ...
    'normalization','am','nearestAm');
records = readtable(fullfile(priorRoot,'frame_parameters.csv'),TextType='string');
count = double(options.FrameCount);
assert(mod(count,2)==0 && count<=height(records), 'audit:FrameCount', ...
    'FrameCount must be even and no greater than the saved 32-frame run.');
assert(all(records.frame(1:count)==(1:count).'), 'audit:FrameOrder','Saved frame order is inconsistent.');
d = prior.device;
assert(string(d.key)=="iphone6s",'audit:Device','This control is specific to the iPhone 6s prior capture.');
rawPath = options.RawPath;
if strlength(rawPath)==0
    rawPath = fullfile(getenv('USERPROFILE'),'Desktop','mobile','0625',d.filename);
end
rawInfo = dir(rawPath);
assert(~isempty(rawInfo) && rawInfo.bytes==1069200000,'audit:SourceSize', ...
    'Expected the immutable 1,069,200,000-byte iPhone 6s capture.');
out = options.OutputFolder;
if strlength(out)==0
    out = fullfile(labRoot,'results','iphone6_followup_20261024', ...
        sprintf('iphone6s_frame_period_P%03d',count));
end
assert(~isfolder(out) && ~isfile(out),'audit:Exists','Refuse overwrite: %s',out);
rows = d.raster_rows; cols = d.raster_columns;
lineSamples = d.fs_hz/d.prior_line_hz;
step = lineSamples/cols;
linearIndex = (0:rows*cols-1).';
relative = floor(linearIndex/cols)*lineSamples+mod(linearIndex,cols)*step;
labels = ["fixed_prior_nearest","fixed_prior_cubic","saved_aligned_nearest","saved_aligned_cubic","rounded_frame_nearest","rounded_frame_cubic"];
methods = ["nearest","cubic"];
sums = zeros(rows,cols,6,'single');
oddSums = sums; evenSums = sums;
firstOrigin = records.start_sample(1);
blockRecords = struct([]);
for frameIndex=1:count
    starts = [firstOrigin+(frameIndex-1)*d.prior_frame_samples,records.start_sample(frameIndex),firstOrigin+(frameIndex-1)*round(d.prior_frame_samples)];
    first = floor(min(starts))-2;
    last = ceil(max(starts)+relative(end))+2;
    [iq,info] = readRisIqBlock(rawPath,first,last-first+1);
    hash = sha256FileRange(rawPath,info.byte_offset,info.byte_count);
    for originIndex=1:3
        positions = starts(originIndex)+relative-first;
        for methodIndex=1:2
            arm = 2*(originIndex-1)+methodIndex;
            z = sampleFractionalRaster(iq,positions,[rows cols],methods(methodIndex));
            a = abs(z);
            sums(:,:,arm) = sums(:,:,arm)+a;
            if mod(frameIndex,2)==1
                oddSums(:,:,arm) = oddSums(:,:,arm)+a;
            else
                evenSums(:,:,arm) = evenSums(:,:,arm)+a;
            end
        end
    end
    item = struct('frame',frameIndex,'fixed_start_sample',starts(1), ...
        'saved_aligned_start_sample',starts(2),'rounded_frame_start_sample',starts(3),'common_raw_block_first_sample',first, ...
        'common_raw_block_sample_count',last-first+1,'raw_block_sha256',hash);
    if isempty(blockRecords),blockRecords=item;else,blockRecords(end+1)=item;end %#ok<AGROW>
end
am = sums/count;
oddAm = oddSums/(count/2); evenAm = evenSums/(count/2);
activeRows = prior.activeRows; activeCols = prior.activeCols;
normalization = prior.normalization;
metrics = struct([]);
for arm=1:6
    a = double(am(activeRows,activeCols,arm));
    odd = double(oddAm(activeRows,activeCols,arm));
    even = double(evenAm(activeRows,activeCols,arm));
    item = struct('arm',labels(arm),'frames',count,'mean_amplitude_counts',mean(a,'all'), ...
        'odd_even_active_am_correlation',centeredCorrelation(odd,even), ...
        'odd_even_active_row_difference_correlation',centeredCorrelation(diff(odd,1,1),diff(even,1,1)), ...
        'fixed_scale_clipped_low_fraction',mean(a<normalization(1),'all'), ...
        'fixed_scale_clipped_high_fraction',mean(a>normalization(2),'all'));
    if isempty(metrics),metrics=item;else,metrics(end+1)=item;end %#ok<AGROW>
end
comparisons = struct( ...
    'interpolation_fixed_origin_relative_rms',relativeRms(am(:,:,1),am(:,:,2)), ...
    'interpolation_saved_origin_relative_rms',relativeRms(am(:,:,3),am(:,:,4)), ...
    'alignment_nearest_relative_rms',relativeRms(am(:,:,1),am(:,:,3)), ...
    'alignment_cubic_relative_rms',relativeRms(am(:,:,2),am(:,:,4)), ...
    'round_frame_nearest_relative_rms',relativeRms(am(:,:,5),am(:,:,1)), ...
    'round_frame_cubic_relative_rms',relativeRms(am(:,:,6),am(:,:,2)));
if count==32
    comparisons.replay_saved_cubic_relative_rms = relativeRms(am(:,:,4),prior.am);
    comparisons.replay_saved_nearest_relative_rms = relativeRms(am(:,:,3),prior.nearestAm);
end
report = struct('status','complete','source',rawPath,'source_bytes',rawInfo.bytes, ...
    'source_format','big-endian int16 interleaved I+jQ','frames',count, ...
    'frame_indices_one_based',1:count,'fs_hz',d.fs_hz,'rf_center_hz',d.rf_center_hz, ...
    'receiver_bandwidth_hz',d.receiver_bandwidth_hz,'line_samples',lineSamples, ...
    'rounded_frame_samples',round(d.prior_frame_samples), ...
    'rounded_last_frame_drift_input_samples',(count-1)*(round(d.prior_frame_samples)-d.prior_frame_samples), ...
    'rounded_last_frame_drift_output_columns',(count-1)*(round(d.prior_frame_samples)-d.prior_frame_samples)/step, ...
    'frame_samples',d.prior_frame_samples,'samples_per_output_column',step, ...
    'dc_removed_counts',[0 0],'gain_applied',1,'phase_correction','none; all arms are AM averages', ...
    'normalization_counts',normalization,'normalization_origin','same prior frame1 cubic active-crop 1/99 percentiles', ...
    'metrics',metrics,'comparisons',comparisons, ...
    'timing_origin','Six arms: precise frame period, saved per-frame timing, rounded frame period; nearest/cubic each. Line period and raster mapping are identical in all arms.', ...
    'no_new_estimation',true,'raw_full_hash_recomputed',false, ...
    'caveat','Same-N conditional ablation. Prior shifts used full mixture/reference. Correlation and row differences may reward clutter; differences are not fidelity improvements.');
mkdir(out);
for arm=1:6
    a = double(am(activeRows,activeCols,arm));
    shown = min(1,max(0,(a-normalization(1))/max(diff(normalization),eps)));
    imwrite(shown,fullfile(out,labels(arm)+"_shared_scale.png"));
end
save(fullfile(out,'paired_am_arrays.mat'),'am','oddAm','evenAm','labels', ...
    'activeRows','activeCols','normalization','report','-v7');
writeJsonFile(fullfile(out,'metrics.json'),report);
writeJsonFile(fullfile(out,'raw_blocks.json'),blockRecords);
writetable(struct2table(metrics),fullfile(out,'arm_metrics.csv'));
writetable(struct2table(blockRecords),fullfile(out,'frame_origins.csv'));
end

function value = centeredCorrelation(a,b)
a=double(a(:)); b=double(b(:));a=a-mean(a);b=b-mean(b);
value=dot(a,b)/max(norm(a)*norm(b),eps);
end

function value = relativeRms(a,reference)
a=double(a(:));reference=double(reference(:));
value=norm(a-reference)/max(norm(reference),eps);
end
