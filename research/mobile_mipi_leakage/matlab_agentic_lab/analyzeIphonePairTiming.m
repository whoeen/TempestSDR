function result = analyzeIphonePairTiming(options)
%ANALYZEIPHONEPAIRTIMING Independent AM timing and common-component CFO study.
% No heldout fitting. Negative IQ conjugation is an explicit working hypothesis.
% Four arms share samples, frame counts, DC and interpolation implementation.
% Raw means fixed-prior-grid control, not unmodified ADC bytes; native TF saved.
arguments
 options.TrainingFrames (1,:) double {mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative} = 0:7
 options.HeldoutFrames (1,:) double {mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative} = 72:79
 options.CfoSeedHz (1,1) double {mustBeReal,mustBeFinite} = 714
 options.OutputFolder (1,1) string = ""
end
lab=fileparts(mfilename('fullpath'));addpath(fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
out=options.OutputFolder;
if strlength(out)==0,out=fullfile(lab,'results','iphone6_cfo_timing_20261026','timing');end
assert(~isfolder(out)&&~isfile(out),'timing:Exists','Refuse overwrite');
train=options.TrainingFrames;test=options.HeldoutFrames;
assert(numel(train)==8&&train(1)==0&&numel(unique(train))==8&&numel(test)==8&&numel(unique(test))==8&&isempty(intersect(train,test)), ...
 'timing:Split','Require 8 unique training frames starting at0, and8 unique disjoint heldout frames.');
assert(issorted(train)&&issorted(test)&&max([train test])<=100,'timing:Frames','Use sorted bounded frame indices.');
mkdir(out);fc=[100e6 160e6];fs=124082800;p0=2069100;n=2^21;origin=8192;left=2048;
indices=[train test];nt=numel(train);nf=numel(indices);blockRows=32;nBlocks=floor(1881/blockRows);
raw=cell(2,nf);readRecords=cell(2,nf);profiles=cell(2,nf);psd=zeros(n,2);dc=zeros(1,2);
win=.5-.5*cos(2*pi*(0:p0-1).'/p0);
for b=1:2
 [path,identity]=resolveIphoneSweepCapture(fc(b)/1e6);identities{b}=identity; %#ok<AGROW>
 for fi=1:nf
  first=origin+indices(fi)*p0-left;
  [x,record]=readRisIqBlock(path,first,n);x=conj(x);
  if fi==1,dc(b)=mean(x(left+1:left+p0),'double');end
  x=x-single(dc(b));raw{b,fi}=x;readRecords{b,fi}=record;
  v=x(left+1:left+p0);am=reshape(abs(v),1100,1881);
  profile=zeros(1100,nBlocks,'single');
  for r=1:nBlocks
   profile(:,r)=mean(am(:,(r-1)*blockRows+(1:blockRows)),2);
  end
  profile=profile-mean(profile,1);profiles{b,fi}=profile;
  if fi<=nt,psd(:,b)=psd(:,b)+abs(fftshift(fft(double(v).*win,n))).^2/nt;end
 end
 fprintf('Native blocks read fc%d MHz: %d frames, fixed DC and conjugation\n',fc(b)/1e6,nf);
end
clear x v am win profile
% Row-periodic AM event proxies. No complex phase enters this fit.
eventRecords=cell(1,2);timeModels=cell(1,2);pfit=zeros(1,2);
for b=1:2
 [eventRecords{b},timeModels{b}]=fitAmEvents(profiles(b,:),indices,nt,p0,blockRows);
 pfit(b)=timeModels{b}.applied_period_samples;
 writetable(eventRecords{b},fullfile(out,sprintf('fc%d_row_events.csv',fc(b)/1e6)));
end
clear profiles
% Select separated common spectral candidates using training average spectra.
components=selectComponents(psd,fc,fs,n,options.CfoSeedHz);clear psd
nComponents=numel(components);toneRecords=struct([]);phaseExamples=cell(2,nComponents,2);
for b=1:2
 for ci=1:nComponents
  center=components(ci).baseband_hz(b);
  for fi=1:nf
   v=raw{b,fi}(left+1:left+p0);
   [tone,trace]=trackTone(v,center,fs);
   tone.band_index=b;tone.fc_hz=fc(b);tone.component=ci;tone.frame_zero_based=indices(fi);tone.training=fi<=nt;
   toneRecords=[toneRecords;tone]; %#ok<AGROW>
   if fi==1,phaseExamples{b,ci,1}=trace;elseif fi==nt+1,phaseExamples{b,ci,2}=trace;end
  end
 end
end
clear v
% Common RF-frequency anchor. Timing-derived clock conversion is kept explicit.
clockRatio=pfit(1)/pfit(2);componentModels=struct([]);
for ci=1:nComponents
 rA=toneRecords([toneRecords.band_index]==1&[toneRecords.component]==ci&[toneRecords.training]);
 rB=toneRecords([toneRecords.band_index]==2&[toneRecords.component]==ci&[toneRecords.training]);
 fA=median([rA.estimated_frequency_hz]);fB=median([rB.estimated_frequency_hz]);
 nominal=fc(2)+fB-fc(1)-fA;
 delta=fB-(fc(1)+fA-fc(2))*clockRatio;
 item=struct('component',ci,'anchor_rf_hz',fc(1)+fA,'native_frequency_a_hz',fA, ...
  'native_frequency_b_hz',fB,'nominal_rf_difference_hz',nominal, ...
  'clock_aware_native_cfo_b_hz',delta,'training_frequency_mad_a_hz',median(abs([rA.estimated_frequency_hz]-fA)), ...
  'training_frequency_mad_b_hz',median(abs([rB.estimated_frequency_hz]-fB)), ...
  'training_median_phase_residual_a_rad',median([rA.phase_residual_rms_rad]), ...
  'training_median_phase_residual_b_rad',median([rB.phase_residual_rms_rad]), ...
  'peak_selection',components(ci));
 componentModels=[componentModels;item]; %#ok<AGROW>
end
% Equal-weight median across distinct candidates: no single strongest line gets
% arbitrary influence. Spectral/phase quality and disagreement are reported.
cfoB=median([componentModels.clock_aware_native_cfo_b_hz]);cfo=[0 cfoB];
pilotRf=componentModels(1).anchor_rf_hz;
nu=[pilotRf-fc(1),(pilotRf-fc(2))*clockRatio];
cfoModel=struct('anchor_band_mhz',100,'seed_hz',options.CfoSeedHz,'applied_native_cfo_hz',cfo, ...
 'clock_ratio_a_over_b',clockRatio,'relative_clock_scale_b_over_a',1/clockRatio,'components',componentModels, ...
 'baseband_sign_convention','All reported baseband frequencies are after conjugating the original I+jQ; +RF=nominal fc+reported fbb.', ...
 'empirical_714hz_offset_applied_separately',false, ...
 'across_component_cfo_mad_hz',median(abs([componentModels.clock_aware_native_cfo_b_hz]-cfoB)), ...
 'pilot_rf_anchor_hz',pilotRf,'expected_native_pilot_baseband_hz',nu, ...
 'correction_formula','conj(raw[n])-fixedDC, multiplied by exp(-j*2*pi*CFO_b*n/Fs) BEFORE fractional sampling', ...
 'clock_aware_formula','deltaB=fB-(fcA+fA-fcB)*PfitA/PfitB; native sample-time units', ...
 'source_identified_as_screen',false,'fit_partition','training only', ...
 'warning','Matched spectral lines may be clutter or aliases. Common CFO is a candidate until distinct lines, phase residuals and heldout data agree.');
% Exact API: no within-frame Floquet derotation in any saved mean.
armNames={'raw','phase','time','both'};usedPeriods=[p0 p0;p0 p0;pfit;pfit];
translation=(nu(1)*usedPeriods(:,1)-nu(2)*usedPeriods(:,2))/fs;
canonicalT=pfit(1)/fs;gridFs=n/canonicalT;
model=struct('fs_native_hz',fs,'canonical_period_seconds',canonicalT,'fs_grid_hz',gridFs, ...
 'grid_length',n,'fc_hz',fc,'iq_polarity',-1,'origin_samples',origin,'baseline_period_samples',p0, ...
 'prior_period_seed_samples',2069099.8670029133,'training_frames_zero_based',train,'heldout_frames_zero_based',test, ...
 'dc_after_conjugation_real',real(dc),'dc_after_conjugation_imag',imag(dc),'time_models',{timeModels},'cfo',cfoModel,'arm_names',{armNames}, ...
 'used_period_samples_by_arm_and_band',usedPeriods,'carrier_translation_cycles_100_to160',translation, ...
 'translation_integer_bins',round(translation),'translation_fractional_cycles',translation-round(translation), ...
 'single_frame_translation','Multiply B(u,k) by exp(+j*2*pi*D*(u+k)) before comparing to A; D is carrier_translation_cycles.', ...
 'pilot_mean_translation','Across-frame pilot derotation already applied; multiply Bmean(u) only by exp(+j*2*pi*D*u).', ...
 'pilot_mean_formula','mean_k z_arm(k,u)*exp(-j*2*pi*nu_b*k*Pused_arm_b/Fs); same physical pilot, clock-converted native units.', ...
 'ordinary_mean_formula','mean_k z_arm(k,u), with no frame-wise phase fit', ...
 'time_mapping','native sample coordinate origin+(k+u)*Pused; common output coordinate (k+u)*canonicalT', ...
 'identities',{identities},'read_records',{readRecords}, ...
 'split_caveat','Training0:7 previously used. Heldout72:79 excluded from this fit, but global prior-access audit/new-screen validation is not claimed.', ...
 'signal_model_caveat','Row-periodic AM events and matched RF lines are proxies. Neither is decoded packet evidence. Conditional pilot means can emphasize clutter.');
save(fullfile(out,'model.mat'),'model','eventRecords','toneRecords','phaseExamples','-v7');
writeJsonFile(fullfile(out,'model.json'),model);
writetable(struct2table(toneRecords),fullfile(out,'tone_tracking.csv'));
% Matched four-arm reconstruction, fixed train/heldout frame counts.
result=struct('status','running','model',model,'bands',{{}});writeJsonFile(fullfile(out,'overview.json'),result);
uGrid=(0:n-1).'/n;tfStart=floor(n*1000/1881);tfCount=131072;
for b=1:2
 meanComplexTrain=complex(zeros(n,4,'single'));meanComplexTest=meanComplexTrain;
 meanPilotTrain=meanComplexTrain;meanPilotTest=meanComplexTrain;
 meanAmTrain=zeros(n,4,'single');meanAmTest=meanAmTrain;
 singleTrain=meanComplexTrain;singleTest=meanComplexTrain;
 perFrame=struct([]);
 for fi=1:nf
  k=indices(fi);x=raw{b,fi};first=readRecords{b,fi}.first_sample_zero_based;
  rawTime=(first+(0:n-1).')/fs;
  if cfo(b)==0,phaseRaw=x;else,phaseRaw=x.*single(exp(-1i*2*pi*cfo(b)*rawTime));end
  qRaw=origin+(k+uGrid)*p0-first;qTime=origin+(k+uGrid)*pfit(b)-first;
  z0=sampleGuardedIqFft(x,qRaw,GuardSamples=512);
  zt=sampleGuardedIqFft(x,qTime,GuardSamples=512);
  if cfo(b)==0,zp=z0;zb=zt;
  else
   zp=sampleGuardedIqFft(phaseRaw,qRaw,GuardSamples=512);
   zb=sampleGuardedIqFft(phaseRaw,qTime,GuardSamples=512);
  end
  values={z0,zp,zt,zb};
  for arm=1:4
   z=values{arm};am=abs(z);
   pilotWeight=single(exp(-1i*2*pi*nu(b)*k*usedPeriods(arm,b)/fs));
   if fi<=nt
    meanComplexTrain(:,arm)=meanComplexTrain(:,arm)+z/nt;
    meanPilotTrain(:,arm)=meanPilotTrain(:,arm)+z*pilotWeight/nt;
    meanAmTrain(:,arm)=meanAmTrain(:,arm)+am/nt;
   else
    meanComplexTest(:,arm)=meanComplexTest(:,arm)+z/nt;
    meanPilotTest(:,arm)=meanPilotTest(:,arm)+z*pilotWeight/nt;
    meanAmTest(:,arm)=meanAmTest(:,arm)+am/nt;
   end
   if fi==1,singleTrain(:,arm)=z;elseif fi==nt+1,singleTest(:,arm)=z;end
   if fi==1,reference=z;else,reference=singleTrain(:,arm);end
   cross=sum(z.*conj(reference),'double');
   rec=struct('frame',k,'training',fi<=nt,'arm',string(armNames{arm}), ...
    'complex_coherence_to_first',abs(cross)/max(double(norm(z))*double(norm(reference)),realmin), ...
    'phase_to_first_rad',angle(cross),'rms_counts',sqrt(mean(abs(z).^2,'double')));
   perFrame=[perFrame;rec]; %#ok<AGROW>
  end
  if fi==1
   tfRaw=z0(tfStart+(1:tfCount));tfBoth=zb(tfStart+(1:tfCount));
   nativeWithin=floor(qRaw(tfStart+1));tfNative=x(nativeWithin+(1:tfCount));
   tfNativeStartSample=first+nativeWithin;
  end
  fprintf('Matched arms fc%d frame%d done\n',fc(b)/1e6,k);
 end
 meta=struct('band_index',b,'fc_hz',fc(b),'fs_grid_hz',gridFs,'fs_native_hz',fs, ...
  'tf_canonical_start_index_zero_based',tfStart,'tf_native_start_sample',tfNativeStartSample, ...
  'tf_first_frame_zero_based',train(1),'tf_raw_description','Fixed baseline-period guarded resampling; no fitted time/CFO correction', ...
  'tf_both_description','Native-time CFO correction then AM-time-model guarded resampling', ...
  'arm_names',{armNames},'training_frames',train,'heldout_frames',test, ...
  'nominal_fc_hz',fc,'used_period_samples',usedPeriods(:,b), ...
  'carrier_translation_cycles_100_to160',translation,'meanPilot_period_seconds',canonicalT, ...
  'training_frames_zero_based',train,'heldout_frames_zero_based',test, ...
  'means_are_fft',false,'within_frame_floquet_derotation',false,'model_path',fullfile(out,'model.mat'));
 bandMetrics=compareArms(meanComplexTrain,meanComplexTest,meanPilotTrain,meanPilotTest,meanAmTrain,meanAmTest,armNames);
 save(fullfile(out,sprintf('band_fc%d.mat',fc(b)/1e6)), ...
  'meanComplexTrain','meanComplexTest','meanPilotTrain','meanPilotTest','meanAmTrain','meanAmTest', ...
  'singleTrain','singleTest','tfRaw','tfBoth','tfNative','meta','bandMetrics','-v7.3');
 writetable(struct2table(perFrame),fullfile(out,sprintf('fc%d_per_frame.csv',fc(b)/1e6)));
 result.bands{b}=struct('fc_hz',fc(b),'metrics',bandMetrics,'meta',meta);
 writeJsonFile(fullfile(out,'overview.json'),result);
 writeArmImages(out,fc(b)/1e6,meanAmTrain,meanAmTest,meanPilotTrain,meanPilotTest,canonicalT,armNames);
 clear meanComplexTrain meanComplexTest meanPilotTrain meanPilotTest meanAmTrain meanAmTest singleTrain singleTest
end
writeDiagnostics(out,eventRecords,timeModels,toneRecords,componentModels,phaseExamples,indices,nt,p0,cfoModel);
result.status='complete';writeJsonFile(fullfile(out,'overview.json'),result);
end

function [events,model]=fitAmEvents(profiles,frames,nt,p0,blockRows)
reference=profiles{1};nb=size(reference,2);nf=numel(frames);lagGrid=(-64:64).';ids=mod(lagGrid,1100)+1;
rf=fft(reference);energy=sum(double(reference).^2,1);lags=zeros(nf,nb);quality=lags;ambiguity=lags;boundary=false(nf,nb);
for f=1:nf
 p=profiles{f};corr=real(ifft(fft(p).*conj(rf)));
 denom=sqrt(sum(double(p).^2,1).*energy);
 for r=1:nb
  scores=double(corr(ids,r))/max(denom(r),realmin);[v,ix]=max(scores);d=lagGrid(ix);
  vals=double(corr(mod(d+[-1 0 1],1100)+1,r));den=vals(1)-2*vals(2)+vals(3);
  frac=0;if abs(den)>eps,frac=max(-.5,min(.5,.5*(vals(1)-vals(3))/den));end
  lags(f,r)=d+frac;quality(f,r)=v;boundary(f,r)=abs(d)==64;
  alternate=scores;alternate(abs(lagGrid-d)<=4)=-inf;
  ambiguity(f,r)=max(alternate)/max(v,realmin);
 end
end
eligible=median(quality(2:nt,:),1)>.2 & median(ambiguity(2:nt,:),1)<.99 & sum(boundary(1:nt,:),1)==0;
if nnz(eligible)<6
 eligible=median(quality(2:nt,:),1)>.05 & sum(boundary(1:nt,:),1)==0;fallback=true;
else,fallback=false;end
assert(nnz(eligible)>=3,'timing:NoAMEvents','Fewer than3 eligible AM row blocks.');
frameLag=median(lags(:,eligible),2);fit=polyfit(frames(1:nt).',frameLag(1:nt),1);
for iteration=1:4
 residual=frameLag(1:nt)-polyval(fit,frames(1:nt).');s=1.4826*median(abs(residual-median(residual)))+1e-5;
 w=min(1,1.5*s./max(abs(residual),eps));X=[frames(1:nt).' ones(nt,1)];
 fit=(X.*sqrt(w))\(frameLag(1:nt).*sqrt(w));fit=fit.';
end
candidate=p0+fit(1);accepted=abs(fit(1))<4;
if accepted,applied=candidate;else,applied=p0;end
prediction=(frames(:))*(applied-p0);residual=frameLag-prediction;
[ff,bb]=ndgrid(frames,1:nb);
% Flatten row coordinates in the same frame-fast ordering.
rowCenters=repmat(((1:nb)-.5)*blockRows,nf,1);
events=table(ff(:),bb(:),rowCenters(:),lags(:),quality(:),ambiguity(:),boundary(:), ...
 reshape(repmat(eligible,nf,1),[],1),VariableNames={'frame','row_block','row_center','lag_samples','normalized_profile_correlation','second_peak_ratio','at_search_boundary','training_selected_block'});
model=struct('method','32-row mean AM profiles correlated against corresponding frame0 block; robust training-only lag slope', ...
 'baseline_period_samples',p0,'fitted_period_samples',candidate,'applied_period_samples',applied, ...
 'slope_samples_per_frame',fit(1),'fit_intercept_samples_diagnostic_only',fit(2), ...
 'origin_intercept_applied',false,'accepted_within_slope_bound',accepted,'slope_bound_samples_per_frame',4, ...
 'eligible_block_count',nnz(eligible),'total_blocks',nb,'training_quality_fallback',fallback, ...
 'frame_indices',frames,'median_lag_samples',frameLag,'frozen_prediction_samples',prediction, ...
 'training_residual_rms_samples',sqrt(mean(residual(1:nt).^2)), ...
 'heldout_residual_rms_samples',sqrt(mean(residual(nt+1:end).^2)), ...
 'heldout_parameters_refitted',false,'implied_line_samples',applied/1881, ...
 'positive_lag_convention','Current AM profile delayed by d => sample current IQ forward by d.', ...
 'within_frame_model','Uniform affine time scaling inferred from frame-period change; not arbitrary per-row warp.', ...
 'event_identity','Row-periodic AM mixture feature; DSI packet identity unverified; column-driver clutter can dominate.');
% Synthetic sign check independent of data.
v=sin(2*pi*(0:1099).'/1100*7)+.4*cos(2*pi*(0:1099).'/1100*13);
c=real(ifft(fft(circshift(v,9)).*conj(fft(v))));[~,ix]=max(c(mod((-20:20),1100)+1));
assert(ix-21==9,'timing:Sign','AM lag correction sign check failed.');
model.synthetic_integer_lag_sign_check_passed=true;
end

function components=selectComponents(power,fc,fs,n,seed)
f=(-n/2:n/2-1).'*fs/n;rfA=fc(1)+f;valid=find(rfA>=104e6&rfA<=156e6);
[~,order]=sort(power(valid,1),'descend');components=struct([]);chosen=[];
for ii=1:numel(order)
 ia=valid(order(ii));fa=rfA(ia);
 if any(abs(fa-chosen)<1e6),continue;end
 predicted=(fa+seed-fc(2))/fs*n+n/2+1;
 ibs=max(2,round(predicted)-ceil(2500/fs*n)):min(n-1,round(predicted)+ceil(2500/fs*n));
 [pb,j]=max(power(ibs,2));ib=ibs(j);
 floorA=median(power(max(1,ia-500):min(n,ia+500),1));floorB=median(power(ibs,2));
 if power(ia,1)<10*max(floorA,eps)||pb<10*max(floorB,eps),continue;end
 va=log(max(power(ia+(-1:1),1),realmin));vb=log(max(power(ib+(-1:1),2),realmin));
 da=peakFraction(va);db=peakFraction(vb);
 base=[f(ia)+da*fs/n,f(ib)+db*fs/n];
 a=struct('baseband_hz',base,'nominal_rf_hz',fc+base,'nominal_difference_hz',diff(fc+base), ...
 'peak_to_local_median_a',power(ia,1)/max(floorA,eps),'peak_to_local_median_b',pb/max(floorB,eps), ...
 'search_seed_hz',seed,'matching_halfwidth_hz',2500,'selection_source','training mean Hann spectra; ≥1MHz between candidate anchor peaks');
 components=[components;a];chosen(end+1)=fa; %#ok<AGROW>
 if numel(components)==3,break;end
end
assert(~isempty(components),'timing:NoCommonPilot','No training-matched isolated spectral candidate found.');
end

function d=peakFraction(v)
den=v(1)-2*v(2)+v(3);d=0;if abs(den)>eps,d=max(-.5,min(.5,.5*(v(1)-v(3))/den));end
end

function [record,trace]=trackTone(x,seed,fs)
% Complex demodulation at fixed training seed, then Hann-weighted blocks.
% No independent strongest-bin selection on heldout data.
L=32768;m=floor(numel(x)/L);nn=(0:m*L-1).';
y=x(1:m*L).*single(exp(-1i*2*pi*seed*nn/fs));
w=single(.5-.5*cos(2*pi*(0:L-1).'/L));
z=sum(reshape(y,L,m).*w,1,'double').'/sum(w,'double');
t=((0:m-1).'*L+(L-1)/2)/fs;phase=unwrap(angle(z));
weight=abs(z).^2;cap=median(weight)*4;weight=min(weight,max(cap,eps));
X=[t-mean(t) ones(m,1)];beta=(X.*sqrt(weight))\(phase.*sqrt(weight));
for k=1:4
 residual=phase-X*beta;s=1.4826*median(abs(residual-median(residual)))+.01;
 robust=min(1,1.5*s./max(abs(residual),eps));ww=weight.*robust;
 beta=(X.*sqrt(ww))\(phase.*sqrt(ww));
end
residual=phase-X*beta;
record=struct('seed_frequency_hz',seed,'estimated_frequency_hz',seed+beta(1)/(2*pi), ...
 'phase_residual_rms_rad',sqrt(sum(weight.*residual.^2)/max(sum(weight),realmin)), ...
 'mean_demodulated_amplitude_counts',mean(abs(z)),'phase_increment_max_rad',max(abs(diff(phase))), ...
 'demodulation_block_samples',L,'demodulation_hann_enbw_hz',fs*sum(double(w).^2)/sum(double(w))^2, ...
 'uncertainty_note','Single-component phase-slope candidate; nearby components, amplitude nulls and unwrap errors can invalidate it.');
trace=struct('time_seconds',t,'phase_unwrapped_rad',phase,'fitted_phase_rad',X*beta, ...
 'residual_phase_rad',residual,'demodulated_complex',z,'seed_frequency_hz',seed);
end

function metrics=compareArms(a,b,pa,pb,aa,ab,names)
metrics=struct([]);
for k=1:4
 cross=sum(pa(:,k).*conj(pb(:,k)),'double');
 item=struct('arm',names{k},'ordinary_train_rms',double(norm(a(:,k)))/sqrt(size(a,1)), ...
 'ordinary_test_rms',double(norm(b(:,k)))/sqrt(size(b,1)), ...
 'pilot_train_rms',double(norm(pa(:,k)))/sqrt(size(pa,1)), ...
 'pilot_test_rms',double(norm(pb(:,k)))/sqrt(size(pb,1)), ...
 'pilot_train_test_coherence',abs(cross)/max(double(norm(pa(:,k)))*double(norm(pb(:,k))),realmin), ...
 'pilot_train_test_residual_phase_rad',-angle(cross), ...
 'am_train_test_correlation',centerCorr(aa(:,k),ab(:,k)), ...
 'metric_caveat','Static mixture repeatability and pilot-referenced energy, not screen fidelity/SNR.');
 metrics=[metrics;item]; %#ok<AGROW>
end
end

function c=centerCorr(x,y)
x=double(x)-mean(double(x));y=double(y)-mean(double(y));c=sum(x.*y)/max(norm(x)*norm(y),realmin);
end

function writeArmImages(out,fc,at,ae,pt,pe,T,names)
folder=fullfile(out,sprintf('fc%d_images',fc));mkdir(folder);images=cell(4,4);
for a=1:4
 images{1,a}=reshape(resamplePeriodicAm(at(:,a),1100*1881,PeriodSeconds=T),1100,1881).';
 images{2,a}=reshape(resamplePeriodicAm(ae(:,a),1100*1881,PeriodSeconds=T),1100,1881).';
 images{3,a}=reshape(resamplePeriodicAm(abs(pt(:,a)),1100*1881,PeriodSeconds=T),1100,1881).';
 images{4,a}=reshape(resamplePeriodicAm(abs(pe(:,a)),1100*1881,PeriodSeconds=T),1100,1881).';
end
limits=double(sampleQuantile(images{1,1},[.01 .99]));labels={'AM train','AM heldout','Pilot coherent train','Pilot coherent heldout'};
f=figure('Visible','off','Color','w','Position',[40 40 1500 1800]);cleanup=onCleanup(@() close(f));tiledlayout(f,4,4);
for r=1:4
 for a=1:4
  imwrite(uint8(255*min(1,max(0,(images{r,a}-limits(1))/max(diff(limits),eps)))),fullfile(folder,sprintf('%s_%s.png',strrep(labels{r},' ','_'),names{a})));
  nexttile;imagesc(images{r,a},limits);axis image off;title([labels{r} ' | ' names{a}]);
 end
end
colormap(f,gray);sgtitle(f,sprintf('fc%dMHz | same8frames | one raw-AM training scale | pilot coherence conditional',fc));
exportgraphics(f,fullfile(folder,'matched_arms.png'),Resolution=100);
writeJsonFile(fullfile(folder,'display.json'),struct('shared_limits',limits,'source','raw AM training 1/99 percentile','per_panel_gain_fit',false));
end

function writeDiagnostics(out,events,models,tones,components,examples,frames,nt,p0,cfoModel)
f=figure('Visible','off','Color','w','Position',[40 40 1400 950]);cleanup=onCleanup(@() close(f));tiledlayout(f,2,2);
for b=1:2
 nexttile;m=models{b};plot(frames(1:nt),m.median_lag_samples(1:nt),'o');hold on;
 plot(frames(nt+1:end),m.median_lag_samples(nt+1:end),'s');plot(frames,m.frozen_prediction_samples,'-');
 xlabel('Frame index');ylabel('AM event lag (native samples)');grid on;title(sprintf('fc%d AM-only P=%.7f',100+60*(b-1),m.applied_period_samples));legend('train','heldout diagnostic','frozen model');
 nexttile;e=events{b};imagesc(1:numel(frames),unique(e.row_center),reshape(e.lag_samples,numel(frames),[]).');axis xy;colorbar;
 xticks(1:numel(frames));xticklabels(string(frames));
 xlabel('Observed frame index; equally spaced observations');ylabel('Row-block center');title('AM event lags; omitted frames are not interpolated');
end
sgtitle(f,sprintf('Time-axis model | baseline P=%d | row/packet identity unverified',p0));exportgraphics(f,fullfile(out,'am_event_timing.png'),Resolution=130);
f2=figure('Visible','off','Color','w','Position',[40 40 1400 850]);cleanup2=onCleanup(@() close(f2));tiledlayout(f2,2,2);
for b=1:2
 nexttile;hold on;
 for ci=1:numel(components)
  rr=tones([tones.band_index]==b&[tones.component]==ci);
  plot([rr.frame_zero_based],[rr.estimated_frequency_hz]-median([rr([rr.training]).estimated_frequency_hz]),'-o');
 end
 xlabel('Frame index');ylabel('Tone frequency minus training median (Hz)');grid on;title(sprintf('fc%d native frequency stability',100+60*(b-1)));
 nexttile;hold on;
 for ss=1:2
  e=examples{b,1,ss};plot(e.time_seconds*1e3,e.residual_phase_rad);
 end
 xlabel('Within-frame time (ms)');ylabel('Phase regression residual (rad)');grid on;legend('first train','first heldout');title('First candidate; diagnostic fits do not tune correction');
end
sgtitle(f2,'Common-component frequency candidates | not proof of common screen signal');exportgraphics(f2,fullfile(out,'cfo_tone_diagnostics.png'),Resolution=130);
f3=figure('Visible','off','Color','w','Position',[40 40 1300 600]);cleanup3=onCleanup(@() close(f3));tiledlayout(f3,1,2);
for b=1:2
 nexttile;hold on;
 for ss=1:2
  e=examples{b,1,ss};t=e.time_seconds;
  before=e.phase_unwrapped_rad+2*pi*(e.seed_frequency_hz-cfoModel.expected_native_pilot_baseband_hz(b))*t;
  before=before-before(1);
  after=before-2*pi*cfoModel.applied_native_cfo_hz(b)*(t-t(1));
  plot(t*1e3,before);plot(t*1e3,after,'--');
 end
 xlabel('Within-frame native time (ms)');ylabel('Phase relative to common pilot (rad)');grid on;
 title(sprintf('fc%d fixed CFO effect; no phase-slope refit',100+60*(b-1)));
 legend('train before','train after','heldout before','heldout after','Location','best');
end
sgtitle(f3,'Fixed training CFO; phase origin set to first chunk for display only; no timing correction here');
exportgraphics(f3,fullfile(out,'frozen_cfo_phase_trace.png'),Resolution=130);
end
