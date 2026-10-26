function report = stitchIphonePair26(bandA,bandB,translationCycles,periodSeconds,outputDir,armNames,assessmentAdaptive)
%STITCHIPHONEPAIR26 Frozen-training 100/160 MHz alignment and literal LR IIR.
% Inputs are pilot-referenced frame means, with no within-frame derotation.
% Positive translation moves B spectra into A's nominal RF coordinates.
assert(~isfolder(outputDir),'stitch26:Exists','Refuse overwrite');
mkdir(outputDir);
lab = fileparts(mfilename('fullpath'));
addpath(fullfile(lab,'stitch'),fullfile(lab,'signal_processing'));
n = size(bandA.meanPilotTrain,1);
if nargin<6, armNames = ["raw","phase","time","both"]; end
if nargin<7, assessmentAdaptive=false; end
armNames=string(armNames);
numberOfArms=numel(armNames);
assert(n==2^21 && numel(translationCycles)==numberOfArms);
assert(size(bandA.meanPilotTrain,2)==numberOfArms);
u = (0:n-1)'/n;
records = cell(1,numberOfArms);
images = struct;
for arm = 1:numberOfArms
    fprintf('Stitch26 arm %s\n',armNames(arm));
    q = round(translationCycles(arm));
    fraction = translationCycles(arm)-q;
    shift = exp(1i*2*pi*fraction*u);
    aTrain = fftshift(fft(double(bandA.meanPilotTrain(:,arm))))/n;
    aTest = fftshift(fft(double(bandA.meanPilotTest(:,arm))))/n;
    bTrain = fftshift(fft(double(bandB.meanPilotTrain(:,arm)).*shift))/n;
    bTest = fftshift(fft(double(bandB.meanPilotTest(:,arm)).*shift))/n;
    % Fixed prior-selected 103--109 MHz, never selected on this assessment.
    k = (ceil(3e6*periodSeconds):floor(9e6*periodSeconds))';
    ia = k+n/2+1;
    ib = k-q+n/2+1;
    narrow = fitOverlap(aTrain(ia),bTrain(ib),aTest(ia),bTest(ib),k,periodSeconds,false);
    masked = fitOverlap(aTrain(ia),bTrain(ib),aTest(ia),bTest(ib),k,periodSeconds,true);
    full = alignPeriodicOverlap(aTrain,bTrain,aTest,bTest,0,q,periodSeconds,120e6);
    binsB = (-n/2:n/2-1)'+q;
    correction = exp(1i*2*pi*binsB*narrow.delay_seconds/periodSeconds-1i*narrow.phase_rad);
    bTrain = bTrain.*correction;
    bTest = bTest.*correction;
    [trainImage,filterMeta] = synthesizeLr(aTrain,bTrain,q,periodSeconds);
    [testImage,~] = synthesizeLr(aTest,bTest,q,periodSeconds);
    images.(armNames(arm)+"_train") = trainImage;
    images.(armNames(arm)+"_test") = testImage;
    images.(armNames(arm)+"_am100") = raster(bandA.meanAmTest(:,arm),periodSeconds);
    images.(armNames(arm)+"_am160") = raster(bandB.meanAmTest(:,arm),periodSeconds);
    images.(armNames(arm)+"_coherent100") = raster(abs(bandA.meanPilotTest(:,arm)),periodSeconds);
    images.(armNames(arm)+"_coherent160") = raster(abs(bandB.meanPilotTest(:,arm)),periodSeconds);
    records{arm} = struct('arm',armNames(arm),'translation_cycles',translationCycles(arm), ...
        'integer_center_bin_b',q,'within_frame_fractional_cycles',fraction, ...
        'narrow_106mhz_alignment',narrow,'narrow_training_tone_mask_control',masked, ...
        'full_overlap_alignment',full,'filter',filterMeta, ...
        'parameters_fitted_to_assessment',logical(assessmentAdaptive),'rf_alignment_fitted_to_assessment',false,'synthesis_alignment','narrow106MHz unit gain', ...
        'training_second_peak_ambiguity',narrow.second_peak_ratio>0.9, ...
        'rf_stitch_validated',false);
end
% Display limits derive solely from training waveform and stay fixed across arms.
values = double(images.(armNames(1)+"_train")(:));
limits = quantile(values,[0.01 0.99]);
if limits(2)<=limits(1), limits(2)=limits(1)+1; end
names = fieldnames(images);
for j=1:numel(names)
    name = names{j};
    imwrite(min(1,max(0,(double(images.(name))-limits(1))/diff(limits))), ...
        fullfile(outputDir,[name '_shared.png']));
end
report = struct('status','complete','assessment_time_alignment_uses_input_data',logical(assessmentAdaptive),'period_seconds',periodSeconds, ...
    'input_grid_samples',n,'input_grid_fs_hz',n/periodSeconds, ...
    'nominal_centers_hz',[100e6 160e6], ...
    'nominal_capture_bandwidth_hz',120e6,'records',{records}, ...
    'shared_limits_counts',limits,'scale_source','first arm training stitch 1/99 percentiles', ...
    'delay_model','one-period circular alignment; modulo-frame and comb ambiguity retained', ...
    'filter','MATLAB Butterworth4 SOS + filtfilt; effective zero-phase LR8; actual synthesis Fs', ...
    'resampling','IQ periodic FFT zero-padding onto common synthesis grid; AM anti-alias Fourier truncation to analysis raster', ...
    'interpretation','Numerical synthesis is an attempted stitch, not demonstrated image/payload recovery. No m[i] blanking mask; DSI blanking unverified.', ...
    'screenshot_used_for_parameter_fitting',false);
writeJsonFile(fullfile(outputDir,'overview.json'),report);
save(fullfile(outputDir,'image_arrays.mat'),'images','report','-v7.3');
fig = figure('Visible','off','Color','w','Position',[40 40 1700 1200]);
tiledlayout(fig,2,numberOfArms,'TileSpacing','compact','Padding','compact');
for row=1:2
    for arm=1:numberOfArms
        ax=nexttile;
        if row==1, image=images.(armNames(arm)+"_am100"); else, image=images.(armNames(arm)+"_test"); end
        imagesc(ax,image,limits); axis(ax,'image'); axis(ax,'off');
        if row==1, title(ax,armNames(arm)+" | 100 MHz AM"); else, title(ax,armNames(arm)+" | LR8 stitch attempt"); end
    end
end
colormap(fig,gray(256));
sgtitle(fig,'Matched assessment frames | common ADC-count contrast | RF coherence must validate the stitch');
exportgraphics(fig,fullfile(outputDir,'matched_before_after.png'),Resolution=140);
close(fig);
phaseFig=figure('Visible','off','Color','w','Position',[40 40 1150 460]);
tiledlayout(phaseFig,1,2);
nexttile;
coherenceValues=[cellfun(@(r)r.narrow_106mhz_alignment.train_coherence,records)', ...
    cellfun(@(r)r.narrow_106mhz_alignment.test_coherence,records)', ...
    cellfun(@(r)r.narrow_training_tone_mask_control.test_coherence,records)'];
bar(coherenceValues); ylabel('Complex coherence'); ylim([0 1]); grid on;
if numberOfArms==1
    xticklabels({'Training','Assessment','Assessment masked'});
else
    xticklabels(armNames);
    legend('Training','Assessment','Assessment; training tone mask','Location','best');
end
nexttile;
bar(cellfun(@(r)r.narrow_106mhz_alignment.test_phase_rad,records));
xticklabels(armNames); ylabel('Frozen-fit assessment residual phase (rad)'); ylim([-pi pi]); grid on;
exportgraphics(phaseFig,fullfile(outputDir,'overlap_phase_coherence.png'),Resolution=140);
close(phaseFig);
end

function result = fitOverlap(a,b,at,bt,k,T,maskTones)
keep = true(size(k));
if maskTones
    [~,ix] = sort(abs(a.*b),'descend');
    for j=1:min(10,numel(ix))
        keep(max(1,ix(j)-8):min(numel(k),ix(j)+8))=false;
    end
end
retained=[sum(abs(a(keep)).^2)/sum(abs(a).^2),sum(abs(b(keep)).^2)/sum(abs(b).^2)];
a=a(keep);b=b(keep);at=at(keep);bt=bt(keep);k=k(keep);
c=b.*conj(a);
n=2^nextpow2(max(k)-min(k)+1);
spectrum=complex(zeros(n,1));
spectrum(mod(k,n)+1)=c;
cc=abs(ifft(spectrum)*n);
[peak,index]=max(cc);
delay=mod(index-1+n/2,n)-n/2;
kc=k-round(mean(k));
objective=@(d)-abs(sum(c.*exp(1i*2*pi*kc*(delay+d)/n)));
delta=fminbnd(objective,-1,1,optimset('TolX',1e-8,'Display','off'));
delay=delay+delta;
ramp=exp(1i*2*pi*k*delay/n);
phase=angle(sum(c.*ramp));
correction=ramp*exp(-1i*phase);
guard=max(2,ceil(2*n/(max(k)-min(k)+1)));
distance=abs(mod((0:n-1)'-(index-1)+n/2,n)-n/2);
cc(distance<=guard)=0;
result=struct('train_coherence',abs(sum(b.*correction.*conj(a)))/(norm(a)*norm(b)), ...
    'test_coherence',abs(sum(bt.*correction.*conj(at)))/(norm(at)*norm(bt)), ...
    'test_phase_rad',angle(sum(bt.*correction.*conj(at))), ...
    'test_relative_error',norm(at-bt.*correction)/norm(at), ...
    'delay_seconds',delay*T/n,'phase_rad',phase, ...
    'second_peak_ratio',max(cc)/max(peak,realmin), ...
    'effective_bins',sum(abs(c))^2/sum(abs(c).^2), ...
    'training_tone_mask',maskTones,'retained_training_power',retained);
end

function [image,meta] = synthesizeLr(a,b,centerB,T)
nIn=numel(a);
bandwidth=120e6;
referenceBin=floor(-bandwidth*T/2);
highBin=ceil(centerB+bandwidth*T/2);
n=2^nextpow2(2*(highBin-referenceBin+1));
assert(n<=2^23,'stitch26:Allocation','Unexpected synthesis allocation');
fs=n/T;
cross=(centerB/2-referenceBin)/T;
[z,p,g]=butter(4,cross/(fs/2),'low');
[sosLow,gLow]=zp2sos(z,p,g);
[z,p,g]=butter(4,cross/(fs/2),'high');
[sosHigh,gHigh]=zp2sos(z,p,g);
[low,f]=freqz(sosLow,4096,fs);
high=freqz(sosHigh,4096,fs);
unityError=max(abs(abs(gLow*low).^2+abs(gHigh*high).^2-1));
assert(unityError<1e-10,'stitch26:LRUnity','Complementary response failed');
combined=complex(zeros(n,1));
guard=256;
for branch=1:2
    center=(branch-1)*centerB;
    first=max(ceil(center-bandwidth*T/2),center-nIn/2);
    last=min(ceil(center+bandwidth*T/2)-1,center+nIn/2-1);
    k=(first:last)';
    indices=k-center+nIn/2+1;
    spectrum=complex(zeros(n,1));
    if branch==1, values=a(indices); else, values=b(indices); end
    spectrum(k-referenceBin+1)=values;
    wave=ifft(spectrum)*n;
    padded=[wave(end-guard+1:end);wave;wave(1:guard)];
    if branch==1
        filtered=filtfilt(sosLow,gLow,padded);
    else
        filtered=filtfilt(sosHigh,gHigh,padded);
    end
    combined=combined+filtered(guard+1:guard+n);
end
image=raster(abs(combined),T);
meta=struct('synthesis_fs_hz',fs,'synthesis_samples',n,'crossover_hz',cross, ...
    'periodic_guard_samples',guard,'low_sos',sosLow,'low_gain',gLow, ...
    'high_sos',sosHigh,'high_gain',gHigh, ...
    'complementary_amplitude_unity_error',unityError, ...
    'response_frequency_spacing_hz',mean(diff(f)), ...
    'periodic_boundary_assumed',true,'toolbox_filtfilt_used',true);
end

function image=raster(am,T)
v=resamplePeriodicAm(double(am),1100*1881,PeriodSeconds=T);
image=single(reshape(v,1100,1881)');
end
