function report = applyIphoneTemplates27(outputDirectory)
%APPLYIPHONETEMPLATES27 Learn power/AM templates and test delayed observations.
% Native input is immutable BE int16 IQ at the USER-reported 124.0828 MS/s.
% The short template is learned from the existing AA-only RF78 training block.
% The frame template is learned from the first 24 frames of native AM.
% Held-out timing estimates and training-predicted corrections are distinct.
% No packet bits, carrier CFO, image pixels, or RGB colors are inferred here.
arguments
    outputDirectory (1,1) string
end
lab = string(fileparts(mfilename('fullpath')));
sourceRoot = fullfile(lab,'results','iphone6_fc100_fam_20261026');
assert(~isfolder(outputDirectory),'Refuse to overwrite a previous run.');
mkdir(outputDirectory);
% Numerical sign check: a delayed observation must be sampled later to align.
checkPhase=(0:127)'/128;
checkReference=cos(2*pi*checkPhase)+0.35*cos(6*pi*checkPhase+0.3);
checkDelayed=periodicShift(checkReference,-3.25);
[~,checkLag]=circularMatch(checkReference,checkDelayed);
assert(abs(checkLag-3.25)<0.01 && ...
    correlation(checkReference,periodicShift(checkDelayed,checkLag))>0.99999, ...
    'Fractional correlation sign check failed.');
summary = jsondecode(fileread(fullfile(sourceRoot,'RESULTS_SUMMARY.json')));
f0 = summary.training_cyclic_power_refinement.used_frequency_hz;
nativeFs = summary.native_fs_hz;
bins = 128;
short = cell(3,1);
shortRecords = repmat(struct(),3,1);
chunkRecords = zeros(0,9);
template = [];
for block = 1:3
    folder = fullfile(sourceRoot,'refined',sprintf('rf78_block%d',block));
    data = load(fullfile(folder,'subband.mat'),'iq','front');
    startTime = data.front.retained_original_first_sample/nativeFs;
    fs = data.front.output_fs_hz;
    t = startTime+(0:numel(data.iq)-1)'/fs;
    power = abs(data.iq).^2;
    [profile,count] = foldPower(power,t,f0,bins);
    if block==1
        template = profile;
        trainingPower = mean(power);
    end
    [g,lag,score] = circularMatch(template,profile);
    short{block} = struct('profile',profile,'count',count,'g',g, ...
        'lag_bins',lag,'matched_profile',periodicShift(profile,lag), ...
        'start_seconds',startTime,'duration_seconds',numel(power)/fs);
    shortRecords(block).block = block;
    shortRecords(block).is_training = block==1;
    shortRecords(block).first_native_sample = data.front.retained_original_first_sample;
    shortRecords(block).unshifted_correlation = correlation(template,profile);
    shortRecords(block).best_correlation_integer = score;
    shortRecords(block).fitted_delay_bins = lag;
    shortRecords(block).fitted_delay_ns = lag/bins/f0*1e9;
    shortRecords(block).aligned_correlation_same_data = ...
        correlation(template,short{block}.matched_profile);
    shortRecords(block).empty_phase_bins = sum(count==0);
    phase = zeros(1,4);
    magnitude = zeros(1,4);
    w = hann(numel(power));
    for h = 1:4
        z = sum(w.*power.*exp(-2i*pi*mod(h*f0*t,1)))/sum(w);
        phase(h) = angle(z);
        magnitude(h) = abs(z)/mean(power);
    end
    shortRecords(block).cyclic_power_phase_global_rad = phase;
    shortRecords(block).cyclic_power_relative_magnitude = magnitude;
    if block>1
        edges = round(linspace(1,numel(power)+1,33));
        for chunk = 1:32
            first = edges(chunk); last = edges(chunk+1)-1;
            middle = floor((first+last)/2);
            estimation = first:middle;
            validation = middle+1:last;
            estimateProfile = foldPower(power(estimation),t(estimation),f0,bins);
            validateProfile = foldPower(power(validation),t(validation),f0,bins);
            [~,delay] = circularMatch(template,estimateProfile);
            alignedValidation = periodicShift(validateProfile,delay);
            chunkRecords(end+1,:) = [block chunk mean(t(validation)) delay, ...
                correlation(template,validateProfile), ...
                correlation(template,alignedValidation), ...
                correlation(diff(template),diff(validateProfile)), ...
                correlation(diff(template),diff(alignedValidation)), ...
                delay/bins/f0*1e9]; %#ok<AGROW>
        end
    end
end
shortTable = array2table(chunkRecords,'VariableNames', ...
    {'Block','Chunk','TimeSeconds','DelayBinsEstimatedOnFirstHalf', ...
    'ValidationCorrBefore','ValidationCorrAfter','ValidationEdgeCorrBefore', ...
    'ValidationEdgeCorrAfter','EstimatedDelayNs'});
writetable(shortTable,fullfile(outputDirectory,'short_template_heldout.csv'));
shortMeta = struct('template_type','empirical RF78 cyclic-power waveform', ...
    'training_block',1,'frozen_frequency_hz',f0,'period_us',1e6/f0, ...
    'native_samples_per_period',nativeFs/f0,'analysis_samples_per_period',fs/f0, ...
    'phase_bins',bins,'bin_width_ns',1e9/f0/bins,'training_mean_power',trainingPower, ...
    'blocks',shortRecords, ...
    'heldout_validation_median_correlation_before',median(chunkRecords(:,5)), ...
    'heldout_validation_median_correlation_after',median(chunkRecords(:,6)), ...
    'heldout_validation_median_edge_correlation_before',median(chunkRecords(:,7)), ...
    'heldout_validation_median_edge_correlation_after',median(chunkRecords(:,8)), ...
    'median_abs_estimated_delay_ns',median(abs(chunkRecords(:,9))), ...
    'scope','Same recording, disjoint time segments. No known DSI header; no CFO correction.');
makeShortFigures(short,template,shortTable,shortMeta,outputDirectory);
save(fullfile(outputDirectory,'short_template.mat'),'template','short','shortTable','shortMeta');
fprintf('Short template: held-out median correlation %.6f -> %.6f.\n', ...
    shortMeta.heldout_validation_median_correlation_before, ...
    shortMeta.heldout_validation_median_correlation_after);

% A separate frame template makes the historical G(k) convention explicit.
raw = "C:/Users/leechanghoon/Downloads/black글_fc100MHz.rIs";
identity = jsondecode(fileread(fullfile(sourceRoot,'RAW_IDENTITY.json')));
fileInfo = dir(raw);
assert(fileInfo.bytes==identity.bytes,'Raw file size changed.');
q = nativeFs/f0;
[rowMean,rowCounts,readMeta] = streamRowEnvelope(raw,q);
trainFrames = 24;
priorLines = 1881; % Previously found ACF candidate; verify on training data.
trainingRows = rowMean(1:trainFrames*priorLines);
lags = (1850:1910)';
acf = zeros(size(lags));
for ii=1:numel(lags)
    a=trainingRows(1:end-lags(ii)); b=trainingRows(1+lags(ii):end);
    acf(ii)=correlation(a,b);
end
[~,peak]=max(acf); lines=lags(peak);
assert(peak>1 && peak<numel(lags),'Training ACF reached search boundary.');
numberFrames=floor(numel(rowMean)/lines);
assert(numberFrames>trainFrames+8,'Insufficient independent test frames.');
trainRaster=reshape(rowMean(1:trainFrames*lines),lines,trainFrames);
frameTemplate=mean(trainRaster,2);
search=(-8:8)';
frameLag=zeros(numberFrames,1); frameCorr=zeros(numberFrames,1);
allScores=nan(numel(search),numberFrames);
for pp=0:numberFrames-1
    [frameLag(pp+1),frameCorr(pp+1),allScores(:,pp+1)] = ...
        linearFrameMatch(rowMean,frameTemplate,pp*lines,search);
end
fitIndex=(1:trainFrames-1)'; % Exclude the boundary-limited very first frame.
design=[fitIndex ones(size(fitIndex))];
fit=design\frameLag(fitIndex+1);
predictedDelay=(0:numberFrames-1)'*fit(1)+fit(2);
before=zeros(numberFrames,1); after=before; edgeBefore=before; edgeAfter=before;
profileBefore=zeros(lines,numberFrames); profileAfter=profileBefore;
rowCoordinate=(0:numel(rowMean)-1)';
for pp=0:numberFrames-1
    nominal=pp*lines+(0:lines-1)';
    u=interp1(rowCoordinate,rowMean,nominal,'linear',NaN);
    v=interp1(rowCoordinate,rowMean,nominal+predictedDelay(pp+1),'linear',NaN);
    profileBefore(:,pp+1)=u; profileAfter(:,pp+1)=v;
    before(pp+1)=correlation(frameTemplate,u);
    after(pp+1)=correlation(frameTemplate,v);
    edgeBefore(pp+1)=correlation(diff(frameTemplate),diff(u));
    edgeAfter(pp+1)=correlation(diff(frameTemplate),diff(v));
end
% One complete guard frame separates training lag searches from validation.
test=(trainFrames+2:numberFrames)';
frameMeta=struct('training_frames',trainFrames,'tested_frames',numel(test), ...
    'guard_frames',1,'first_test_frame_zero_based',trainFrames+1, ...
    'native_fs_hz',nativeFs,'row_frequency_prior_from_FAM_hz',f0, ...
    'row_samples',q,'training_acf_lines',lines,'training_acf_peak',acf(peak), ...
    'lag_units','row; positive means sample later in the current frame', ...
    'training_delay_slope_lines_per_frame',fit(1),'training_delay_intercept_lines',fit(2), ...
    'predicted_frame_period_lines',lines+fit(1), ...
    'predicted_frame_period_samples',(lines+fit(1))*q, ...
    'predicted_frame_rate_hz',f0/(lines+fit(1)), ...
    'heldout_median_correlation_before',median(before(test),'omitnan'), ...
    'heldout_median_correlation_after_training_prediction',median(after(test),'omitnan'), ...
    'heldout_median_edge_correlation_before',median(edgeBefore(test),'omitnan'), ...
    'heldout_median_edge_correlation_after_training_prediction',median(edgeAfter(test),'omitnan'), ...
    'heldout_measured_minus_predicted_delay_rms_lines', ...
        rms(frameLag(test)-predictedDelay(test)), ...
    'boundary_peak_count',sum(abs(frameLag)>=max(search)-0.5), ...
    'raw_read',readMeta,'raw_identity_prior_verification',identity, ...
    'correction_scope','Only first 24 frames fit correction. Later-frame optimum lags are diagnostics, not fitted correction.', ...
    'physical_scope','AM row-profile timing, no packet or horizontal pixel recovery.');
frameTable=table((0:numberFrames-1)',(0:numberFrames-1)'*lines*q/nativeFs, ...
    (0:numberFrames-1)'<trainFrames,(0:numberFrames-1)'==trainFrames, ...
    frameLag,predictedDelay,before,after,edgeBefore,edgeAfter, ...
    'VariableNames',{'FrameIndexZeroBased','TimeSeconds','IsTraining','IsGuard', ...
    'MeasuredLagLines','PredictedLagFromTrainingLines','CorrelationBefore', ...
    'CorrelationAfterTrainingPrediction','EdgeCorrelationBefore','EdgeCorrelationAfter'});
writetable(frameTable,fullfile(outputDirectory,'frame_template_heldout.csv'));
save(fullfile(outputDirectory,'frame_template.mat'),'frameTemplate','rowMean','rowCounts', ...
    'frameTable','frameMeta','allScores','search','lags','acf','profileBefore','profileAfter');
makeFrameFigures(frameTemplate,frameTable,frameMeta,allScores,search,lags,acf, ...
    profileBefore,profileAfter,outputDirectory);
report=struct('status','complete','short',shortMeta,'frame',frameMeta, ...
    'packet_identified',false,'carrier_phase_corrected',false, ...
    'code',string(mfilename('fullpath'))+'.m','matlab_version',version);
writeJson(fullfile(outputDirectory,'metrics.json'),report);
fprintf('Frame template: N=%d, training slope %+.9f line/frame; validation %.6f -> %.6f.\n', ...
    lines,fit(1),frameMeta.heldout_median_correlation_before, ...
    frameMeta.heldout_median_correlation_after_training_prediction);
end

function [profile,count]=foldPower(power,t,frequency,bins)
phase=mod(t*frequency,1);
bin=min(bins,floor(phase*bins)+1);
count=accumarray(bin,1,[bins 1]);
profile=accumarray(bin,power,[bins 1])./max(count,1);
assert(all(count>0),'Insufficient phase coverage.');
end

function [g,lag,score]=circularMatch(reference,current)
a=reference(:)-mean(reference); b=current(:)-mean(current);
g=real(ifft(conj(fft(a)).*fft(b)))/(norm(a)*norm(b));
[score,index]=max(g); N=numel(g);
left=g(mod(index-2,N)+1); right=g(mod(index,N)+1);
den=left-2*score+right; delta=0;
if den<0,delta=max(-0.5,min(0.5,0.5*(left-right)/den));end
lag=index-1+delta;
if lag>N/2,lag=lag-N;end
end

function shifted=periodicShift(v,lag)
N=numel(v); frequency=ifftshift((-floor(N/2):ceil(N/2)-1)');
shifted=real(ifft(fft(v).*exp(2i*pi*frequency*lag/N)));
end

function r=correlation(a,b)
valid=isfinite(a)&isfinite(b);a=a(valid);b=b(valid);
a=a-mean(a);b=b-mean(b);
r=real(a'*b)/max(norm(a)*norm(b),realmin);
end

function [rowMean,counts,meta]=streamRowEnvelope(path,samplesPerRow)
info=dir(path); total=info.bytes/4;
assert(mod(info.bytes,4)==0,'Not a complete interleaved int16 IQ file.');
rows=ceil(total/samplesPerRow); sums=zeros(rows,1); counts=sums;
fid=fopen(path,'r','ieee-be');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
chunk=2^20; first=0; clock=tic;
while first<total
    count=min(chunk,total-first);
    iq=fread(fid,[2 count],'int16=>single');
    assert(size(iq,2)==count,'Short read.');
    envelope=double(hypot(iq(1,:),iq(2,:))).';
    row=floor((first+(0:count-1)')/samplesPerRow)+1;
    lo=row(1); hi=row(end); local=row-lo+1;
    sums(lo:hi)=sums(lo:hi)+accumarray(local,envelope,[hi-lo+1 1]);
    counts(lo:hi)=counts(lo:hi)+accumarray(local,1,[hi-lo+1 1]);
    first=first+count;
    if mod(first,32*chunk)==0,fprintf('Native AM: %.1f%% read.\n',100*first/total);end
end
fullRows=floor(total/samplesPerRow);
sums=sums(1:fullRows);counts=counts(1:fullRows);rowMean=sums./counts;
meta=struct('path',path,'bytes',info.bytes,'complex_samples',total, ...
    'endianness','ieee-be','scalars','int16 I,Q','envelope','sqrt(I^2+Q^2)', ...
    'mean_subtraction_before_envelope',false,'block_complex_samples',chunk, ...
    'row_assignment','floor(native_sample_zero_based / fractional_samples_per_row)', ...
    'full_rows',fullRows,'elapsed_seconds',toc(clock),'raw_modified',false);
end

function [lag,score,scores]=linearFrameMatch(signal,template,start,search)
scores=nan(size(search));N=numel(template);
for ii=1:numel(search)
    index=start+search(ii)+(1:N);
    if index(1)>=1 && index(end)<=numel(signal)
        scores(ii)=correlation(template,signal(index));
    end
end
[score,index]=max(scores);delta=0;
if index>1&&index<numel(scores)&&all(isfinite(scores(index-1:index+1)))
    den=scores(index-1)-2*score+scores(index+1);
    if den<0,delta=max(-0.5,min(0.5,0.5*(scores(index-1)-scores(index+1))/den));end
end
lag=search(index)+delta;
end

function makeShortFigures(short,template,records,meta,out)
fig=figure('Name','Short-period template and G(k)','Color','w','Position',[40 40 1350 900]);
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout);hold(ax,'on');
time=((0:numel(template)-1)'+0.5)/numel(template)*meta.period_us;
for bb=1:3,plot(ax,time,short{bb}.profile/meta.training_mean_power,'DisplayName',sprintf('Block %d',bb));end
xlabel(ax,'Within-period time (us)');ylabel(ax,'Mean power / training mean');
title(ax,'Frozen empirical template; no lag adjustment');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
delay=(-64:63)'/128*meta.period_us;
for bb=1:3,plot(ax,delay,fftshift(short{bb}.g),'DisplayName',sprintf('Block %d',bb));end
xlabel(ax,'Circular delay k (us)');ylabel(ax,'Normalized G(k)');
title(ax,'G(k): peak position estimates relative delay');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
plot(ax,records.TimeSeconds,records.EstimatedDelayNs,'.');yline(ax,0,'--');
xlabel(ax,'Absolute recording time (s)');ylabel(ax,'Estimated delay (ns)');
title(ax,'Estimate delay on first half of each test chunk');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
plot(ax,records.TimeSeconds,records.ValidationCorrBefore,'.','DisplayName','Before');
plot(ax,records.TimeSeconds,records.ValidationCorrAfter,'.','DisplayName','After first-half estimate');
xlabel(ax,'Absolute recording time (s)');ylabel(ax,'Second-half template correlation');
title(ax,'Independent second half: improvement is not guaranteed');legend(ax,'Location','best');grid(ax,'on');
title(layout,sprintf('100 MHz capture / RF78 subband | T = %.9f us | packet identity unknown',meta.period_us));
exportgraphics(fig,fullfile(out,'short_template_gk.png'),'Resolution',150);
savefig(fig,fullfile(out,'short_template_gk.fig'));
fig=figure('Name','Cyclic phase is timing phase','Color','w','Position',[60 60 1200 530]);
layout=tiledlayout(fig,1,2,'TileSpacing','compact');
ax=nexttile(layout);hold(ax,'on');
for bb=1:3,plot(ax,1:4,meta.blocks(bb).cyclic_power_relative_magnitude,'-o','DisplayName',sprintf('Block %d',bb));end
xlabel(ax,'Harmonic order h');ylabel(ax,'|cyclic power coefficient| / mean power');
title(ax,'Power waveform harmonics at h f_0');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
reference=meta.blocks(1).cyclic_power_phase_global_rad;
for bb=2:3
    difference=angle(exp(1i*(meta.blocks(bb).cyclic_power_phase_global_rad-reference)))*180/pi;
    plot(ax,1:4,difference,'-o','DisplayName',sprintf('Block %d minus block 1',bb));
end
xlabel(ax,'Harmonic order h');ylabel(ax,'Global-epoch cyclic phase difference (deg)');
title(ax,'Timing observable; not recovered RF carrier phase');legend(ax,'Location','best');grid(ax,'on');
exportgraphics(fig,fullfile(out,'cyclic_power_phase.png'),'Resolution',150);
savefig(fig,fullfile(out,'cyclic_power_phase.fig'));
end

function makeFrameFigures(template,records,meta,scores,search,lags,acf,before,after,out)
fig=figure('Name','Frame template and historical G(k)','Color','w','Position',[80 50 1350 900]);
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout);plot(ax,lags,acf,'-o','MarkerSize',3);
xline(ax,meta.training_acf_lines,'--');xlabel(ax,'Candidate frame period (rows)');
ylabel(ax,'Training row-profile correlation');title(ax,'Select frame length using training rows only');grid(ax,'on');
ax=nexttile(layout);plot(ax,0:numel(template)-1,template);
xlabel(ax,'Within-frame row index');ylabel(ax,'Mean native AM (ADC counts)');
title(ax,sprintf('Template averaged over first %d frames',meta.training_frames));grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
chosen=min(height(records),[26 70 130]);
for pp=chosen,plot(ax,search,scores(:,pp),'-o','DisplayName',sprintf('Frame %d',pp-1));end
xlabel(ax,'Delay k (rows)');ylabel(ax,'Normalized G_p(k)');
title(ax,'Held-out correlation curves: fractional peak fit');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
plot(ax,records.FrameIndexZeroBased,records.MeasuredLagLines,'.','DisplayName','Measured test lag');
plot(ax,records.FrameIndexZeroBased,records.PredictedLagFromTrainingLines,'-','DisplayName','Training-only linear prediction');
xline(ax,meta.training_frames-0.5,'--','Training ends','HandleVisibility','off');
xline(ax,meta.training_frames+0.5,':','Test starts','HandleVisibility','off');
xlabel(ax,'Frame index p');ylabel(ax,'Lag estimate (rows)');
title(ax,'Peak drift versus frame index: this axis is p, not k');legend(ax,'Location','best');grid(ax,'on');
title(layout,'Native BE IQ -> AM -> row profile -> learned frame template');
exportgraphics(fig,fullfile(out,'frame_template_gk.png'),'Resolution',150);
savefig(fig,fullfile(out,'frame_template_gk.fig'));
fig=figure('Name','Held-out template alignment validation','Color','w','Position',[100 70 1350 900]);
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
for ii=1:2
    ax=nexttile(layout);if ii==1,data=before;else,data=after;end
    imagesc(ax,records.FrameIndexZeroBased,0:numel(template)-1,data);axis(ax,'xy');
    clim(ax,prctile(template,[1 99]));colorbar(ax);
    xline(ax,meta.training_frames-0.5,'w--');xlabel(ax,'Frame index');ylabel(ax,'Within-frame row');
    if ii==1,title(ax,'Before: row-profile stack');else,title(ax,'After: training-predicted timing');end
end
ax=nexttile(layout);hold(ax,'on');
plot(ax,records.FrameIndexZeroBased,records.CorrelationBefore,'DisplayName','Before');
plot(ax,records.FrameIndexZeroBased,records.CorrelationAfterTrainingPrediction,'DisplayName','Training-predicted correction');
xline(ax,meta.training_frames-0.5,'--');xlabel(ax,'Frame index');ylabel(ax,'Profile correlation');
title(ax,'Held-out frames: full-profile agreement');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
plot(ax,records.FrameIndexZeroBased,records.EdgeCorrelationBefore,'DisplayName','Before');
plot(ax,records.FrameIndexZeroBased,records.EdgeCorrelationAfter,'DisplayName','Training-predicted correction');
xline(ax,meta.training_frames-0.5,'--');xlabel(ax,'Frame index');ylabel(ax,'First-difference correlation');
title(ax,'Edge agreement checks more than broad brightness');legend(ax,'Location','best');grid(ax,'on');
title(layout,'These are temporal row profiles, not reconstructed 2D phone images');
exportgraphics(fig,fullfile(out,'frame_template_validation.png'),'Resolution',150);
savefig(fig,fullfile(out,'frame_template_validation.fig'));
end

function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
