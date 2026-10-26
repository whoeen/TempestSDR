function result = analyzeIphoneTracked26(options)
%ANALYZEIPHONETRACKED26 Adaptive per-frame AM alignment with fixed prior CFO.
% This reuses the same training-selected row blocks and already measured lags.
% Assessment frames provide their own AM lag: this is NOT frozen out-of-sample.
% Original affine/CFO models, frame counts, DC and IQ polarity stay fixed.
arguments
 options.OutputFolder (1,1) string = ""
end
lab=fileparts(mfilename('fullpath'));addpath(fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
source=fullfile(lab,'results','iphone6_cfo_timing_20261026','timing');
out=options.OutputFolder;if strlength(out)==0,out=fullfile(lab,'results','iphone6_cfo_timing_20261026','tracked');end
assert(~isfolder(out)&&~isfile(out),'tracked:Exists','Refuse overwrite');
saved=load(fullfile(source,'model.mat'),'model','eventRecords');m=saved.model;
assert(m.iq_polarity==-1,'tracked:Polarity','Expected prior negative-IQ working hypothesis.');
train=m.training_frames_zero_based;test=m.heldout_frames_zero_based;frames=[train test];nt=numel(train);
assert(nt==numel(test)&&train(1)==0,'tracked:Split','Require matched counts and frame0 reference.');
n=m.grid_length;fs=m.fs_native_hz;p0=m.baseline_period_samples;origin=m.origin_samples;
u=(0:n-1).'/n;nu=m.cfo.expected_native_pilot_baseband_hz;cfo=m.cfo.applied_native_cfo_hz;
T=m.canonical_period_seconds;translation=m.carrier_translation_cycles_100_to160(4);
mkdir(out);
result=struct('status','running','arm_name','adaptive_time_fixed_cfo', ...
 'source_model',fullfile(source,'model.mat'),'training_frames_zero_based',train,'assessment_frames_zero_based',test, ...
 'cfo_native_hz',cfo,'canonical_period_seconds',T,'fs_grid_hz',n/T, ...
 'carrier_translation_cycles_100_to160',translation,'global_time_model_refitted',false, ...
 'assessment_am_lag_used',true,'assessment_cfo_or_phase_fitted',false, ...
 'assessment_status','Adaptive assessment: each assessed frame contributes its own AM position; not frozen out-of-sample validation.', ...
 'query_formula','q(k,u)=origin+(k+u)*Pfit+residual_k; residual_k=stored median AM lag-k*(Pfit-P0)', ...
 'pilot_transport','exp(-j*2*pi*nu_b*(k*Pfit+residual_k)/Fs); residual term transports the extra sampled time to the frame0 carrier reference', ...
 'translation_note','Within-frame slope Pfit is unchanged; pilot means retain the original both-arm D. No per-frame residual phase term is applied again in stitching.', ...
 'warning','Adaptive AM alignment can track clutter. The post-resampling profile test is a replay check, not independent evidence of screen fidelity.', ...
 'bands',{{}});
writeJsonFile(fullfile(out,'overview.json'),result);
for b=1:2
 fc=m.fc_hz(b);timeModel=m.time_models{b};P=timeModel.applied_period_samples;
 events=saved.eventRecords{b};selected=unique(events.row_block(events.training_selected_block));
 assert(numel(selected)==timeModel.eligible_block_count,'tracked:Blocks','Selected row-block count differs.');
 base=load(fullfile(source,sprintf('band_fc%d.mat',fc/1e6)), ...
  'meanAmTrain','meanAmTest','meanPilotTrain','meanPilotTest','singleTest','meta');
 [path,identity]=resolveIphoneSweepCapture(fc/1e6);
 dc=single(complex(m.dc_after_conjugation_real(b),m.dc_after_conjugation_imag(b)));
 meanAmTrain=zeros(n,1,'single');meanAmTest=meanAmTrain;
 meanComplexTrain=complex(meanAmTrain);meanComplexTest=meanComplexTrain;
 meanPilotTrain=meanComplexTrain;meanPilotTest=meanComplexTrain;
 singleTrain=meanComplexTrain;singleTest=meanComplexTrain;
 log=struct([]);readRecords=cell(1,numel(frames));
 for fi=1:numel(frames)
  k=frames(fi);rows=events.frame==k&events.training_selected_block;
  measuredLag=median(events.lag_samples(rows));
  modelIndex=find(timeModel.frame_indices==k,1);assert(~isempty(modelIndex),'tracked:FrameMissing','Frame missing from prior lag table.');
  assert(abs(measuredLag-timeModel.median_lag_samples(modelIndex))<1e-8,'tracked:LagMismatch','Lag table/model disagreement.');
  predicted=k*(P-p0);residual=measuredLag-predicted;
  first=origin+k*p0-2048;[x,ri]=readRisIqBlock(path,first,n);x=conj(x)-dc;readRecords{fi}=ri;
  rawTimes=(first+(0:n-1).')/fs;
  corrected=x.*single(exp(-1i*2*pi*cfo(b)*rawTimes));
  q=origin+(k+u)*P+residual-first;
  z=sampleGuardedIqFft(corrected,q,GuardSamples=512);am=abs(z);
  pilotWeight=single(exp(-1i*2*pi*nu(b)*(k*P+residual)/fs));
  if fi<=nt
   meanAmTrain=meanAmTrain+am/nt;meanComplexTrain=meanComplexTrain+z/nt;
   meanPilotTrain=meanPilotTrain+z*pilotWeight/nt;
  else
   meanAmTest=meanAmTest+am/nt;meanComplexTest=meanComplexTest+z/nt;
   meanPilotTest=meanPilotTest+z*pilotWeight/nt;
  end
  % Reconstruct and remeasure AM profiles on the OUTPUT raster. This differs
  % from merely subtracting the applied lag from its own scalar estimate.
  [amRaster,aaMeta]=resamplePeriodicAm(am,p0,PeriodSeconds=T);
  profile=makeProfiles(amRaster); %#ok<ASGLU>
  if fi==1
   referenceProfile=profile;singleTrain=z;
  elseif fi==nt+1
   singleTest=z;
   tfStart=floor(n*1000/1881);tfCount=131072;
   tfAdaptiveTest=z(tfStart+(1:tfCount));
   tfFrozenTest=base.singleTest(tfStart+(1:tfCount),4);
   nativeWithin=floor(q(tfStart+1));tfNativeTest=x(nativeWithin+(1:tfCount));
   tfNativeStartSample=first+nativeWithin;
  end
  [afterLag,afterQuality,afterBoundary]=profileLag(profile,referenceProfile,selected);
  cross=sum(z.*conj(singleTrain),'double');
  item=struct('frame_zero_based',k,'training',fi<=nt,'stored_observed_lag_input_samples',measuredLag, ...
   'frozen_prediction_input_samples',predicted,'adaptive_residual_input_samples',residual, ...
   'extra_pilot_transport_phase_rad',angle(exp(-1i*2*pi*nu(b)*residual/fs)), ...
   'post_resampling_median_profile_lag_raster_samples',median(afterLag), ...
   'post_resampling_profile_lag_rms_raster_samples',sqrt(mean(afterLag.^2)), ...
   'post_resampling_median_profile_correlation',median(afterQuality), ...
   'post_resampling_profile_boundary_fraction',mean(afterBoundary), ...
   'complex_coherence_to_first',abs(cross)/max(double(norm(z))*double(norm(singleTrain)),realmin));
  log=[log;item]; %#ok<AGROW>
  fprintf('Adaptive AM fc%d frame%d residual%+.5f, remeasured lag%+.5f\n',fc/1e6,k,residual,median(afterLag));
 end
 meta=struct('arm_names',{{'adaptive_time_fixed_cfo'}},'fc_hz',fc,'nominal_fc_hz',m.fc_hz, ...
  'grid_length',n,'fs_grid_hz',n/T,'fs_native_hz',fs,'used_period_samples',P, ...
  'carrier_translation_cycles_100_to160',translation,'meanPilot_period_seconds',T, ...
  'training_frames_zero_based',train,'heldout_frames_zero_based',test, ...
  'assessment_status',result.assessment_status,'assessment_am_lag_used',true, ...
  'native_cfo_hz',cfo(b),'expected_native_pilot_hz',nu(b),'within_frame_floquet_derotation',false, ...
  'selected_row_blocks',selected,'identity',identity,'read_records',{readRecords}, ...
  'am_antialias',aaMeta,'tf_canonical_start_index_zero_based',tfStart, ...
  'tf_native_start_sample',tfNativeStartSample,'tf_first_frame_zero_based',test(1), ...
  'tf_raw_description','Frozen both-arm assessment first frame on canonical grid', ...
  'tf_both_description','Same assessment frame with its own AM residual adjustment; fixed training CFO', ...
  'tf_native_description','Native-rate conjugated IQ minus fixed training DC; no resampling or CFO correction');
 metrics=struct('adaptive_am_train_assessment_correlation',centerCorr(meanAmTrain,meanAmTest), ...
  'frozen_am_train_assessment_correlation',centerCorr(base.meanAmTrain(:,4),base.meanAmTest(:,4)), ...
  'adaptive_pilot_train_assessment',complexMetrics(meanPilotTrain,meanPilotTest), ...
  'frozen_pilot_train_assessment',complexMetrics(base.meanPilotTrain(:,4),base.meanPilotTest(:,4)), ...
  'train_residual_rms_input_samples',sqrt(mean([log(1:nt).adaptive_residual_input_samples].^2)), ...
  'assessment_residual_rms_input_samples',sqrt(mean([log(nt+1:end).adaptive_residual_input_samples].^2)), ...
  'train_post_resampling_median_lag_rms',sqrt(mean([log(1:nt).post_resampling_median_profile_lag_raster_samples].^2)), ...
  'assessment_post_resampling_median_lag_rms',sqrt(mean([log(nt+1:end).post_resampling_median_profile_lag_raster_samples].^2)), ...
  'caveat','Mixture repeatability and alignment replay checks; adaptive same-frame estimation, not image fidelity/SNR.');
 adaptiveAmTrain=meanAmTrain;adaptiveAmTest=meanAmTest;
 adaptiveComplexPilotTrain=meanPilotTrain;adaptiveComplexPilotTest=meanPilotTest;
 save(fullfile(out,sprintf('band_fc%d.mat',fc/1e6)), ...
  'meanAmTrain','meanAmTest','meanComplexTrain','meanComplexTest','meanPilotTrain','meanPilotTest', ...
  'adaptiveAmTrain','adaptiveAmTest','adaptiveComplexPilotTrain','adaptiveComplexPilotTest', ...
  'singleTrain','singleTest','tfAdaptiveTest','tfFrozenTest','tfNativeTest','meta','metrics','log','-v7.3');
 writetable(struct2table(log),fullfile(out,sprintf('fc%d_tracking.csv',fc/1e6)));
 result.bands{b}=struct('fc_hz',fc,'metrics',metrics,'meta',meta);
 writeJsonFile(fullfile(out,'overview.json'),result);
 makePlots(out,fc,base,meanAmTrain,meanAmTest,meanPilotTrain,meanPilotTest,log,T,nt);
end
result.status='complete';writeJsonFile(fullfile(out,'overview.json'),result);
end

function profile=makeProfiles(am)
a=reshape(am,1100,1881);profile=zeros(1100,58,'single');
for j=1:58,profile(:,j)=mean(a(:,(j-1)*32+(1:32)),2);end
profile=profile-mean(profile,1);
end
function [lag,quality,boundary]=profileLag(current,reference,selected)
c=real(ifft(fft(current(:,selected)).*conj(fft(reference(:,selected)))));
den=sqrt(sum(double(current(:,selected)).^2,1).*sum(double(reference(:,selected)).^2,1));
lg=(-64:64).';ids=mod(lg,1100)+1;lag=zeros(numel(selected),1);quality=lag;boundary=false(size(lag));
for j=1:numel(selected)
 [quality(j),ix]=max(double(c(ids,j))/max(den(j),realmin));d=lg(ix);
 v=double(c(mod(d+[-1 0 1],1100)+1,j));denom=v(1)-2*v(2)+v(3);delta=0;
 if abs(denom)>eps,delta=max(-.5,min(.5,.5*(v(1)-v(3))/denom));end
 lag(j)=d+delta;boundary(j)=abs(d)==64;
end
end
function value=centerCorr(x,y)
x=double(x(:));y=double(y(:));x=x-mean(x);y=y-mean(y);value=sum(x.*y)/max(norm(x)*norm(y),realmin);
end
function result=complexMetrics(a,b)
c=sum(b.*conj(a),'double');result=struct('coherence',abs(c)/max(double(norm(a))*double(norm(b)),realmin), ...
 'residual_phase_rad',angle(c),'unit_gain_relative_error',double(norm(b-a))/max(double(norm(a)),realmin));
end
function makePlots(out,fc,base,at,ae,pt,pe,log,T,nt)
inputs={base.meanAmTrain(:,4),at,abs(base.meanPilotTrain(:,4)),abs(pt); ...
 base.meanAmTest(:,4),ae,abs(base.meanPilotTest(:,4)),abs(pe)};
scaleRaster=reshape(resamplePeriodicAm(base.meanAmTrain(:,1),2069100,PeriodSeconds=T),1100,1881).';
limits=double(sampleQuantile(scaleRaster,[.01 .99]));if diff(limits)<=0,limits(2)=limits(1)+1;end
f=figure('Visible','off','Color','w','Position',[40 40 1500 1150]);cleanup=onCleanup(@() close(f));tiledlayout(f,2,4);
labels={'Frozen AM','Adaptive AM','Frozen pilot mean','Adaptive pilot mean'};
for row=1:2
 for col=1:4
  im=reshape(resamplePeriodicAm(inputs{row,col},2069100,PeriodSeconds=T),1100,1881).';
  nexttile;imagesc(im,limits);axis image off;title(labels{col});
  imwrite(uint8(255*min(1,max(0,(im-limits(1))/diff(limits)))),fullfile(out,sprintf('fc%d_%s_partition%d.png',fc/1e6,strrep(labels{col},' ','_'),row)));
 end
end
colormap(f,gray);sgtitle(f,sprintf('fc%d | top training; bottom ADAPTIVE assessment | raw training scale fixed',fc/1e6));
exportgraphics(f,fullfile(out,sprintf('fc%d_adaptive_comparison.png',fc/1e6)),Resolution=130);
f2=figure('Visible','off','Color','w','Position',[40 40 1200 450]);cleanup2=onCleanup(@() close(f2));tiledlayout(f2,1,2);
nexttile;plot([log.frame_zero_based],[log.adaptive_residual_input_samples],'-o');grid on;xlabel('Frame');ylabel('Extra AM timing correction (native samples)');
nexttile;plot([log.frame_zero_based],[log.post_resampling_median_profile_lag_raster_samples],'-o');grid on;xlabel('Frame');ylabel('Recomputed output profile lag (raster samples)');
sgtitle(f2,sprintf('fc%d adaptive replay check; first%d training, remaining same-frame adaptive assessment',fc/1e6,nt));
exportgraphics(f2,fullfile(out,sprintf('fc%d_tracking_residuals.png',fc/1e6)),Resolution=130);
end
