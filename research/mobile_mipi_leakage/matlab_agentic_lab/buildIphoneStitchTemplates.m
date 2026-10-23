function overview=buildIphoneStitchTemplates(centersMHz)
%BUILDIPHONESTITCHTEMPLATES Training-only timing and phase normalized frames.
arguments
 centersMHz (1,:) double = 100:60:700
end
labRoot=fileparts(mfilename('fullpath')); addpath(fullfile(labRoot,'signal_processing'),fullfile(labRoot,'stitch'));
root=fullfile(labRoot,'results','iphone6_stitch_20261023'); out=fullfile(root,'templates');
if ~isfolder(out), mkdir(out); end
fs=124082800; n=2^21; rawCount=2^21; origin=8192; frameIndices=[0:7 16:23]; train=1:8; test=9:16;
u=(0:n-1).'/n; overview=struct('fs_hz',fs,'grid_length',n,'training_frames_zero_based',0:7,'heldout_frames_zero_based',16:23,'bands',{{}});
for b=1:numel(centersMHz)
 fc=centersMHz(b); folder=fullfile(out,sprintf('fc%03dMHz',fc));
 assert(~isfolder(folder),'stitch:Exists','Refuse overwrite: %s',folder); mkdir(folder);
 model=jsondecode(fileread(fullfile(root,'timing_model',sprintf('fc%dMHz.json',fc))));
 if model.am_fit.residual_rms_samples<1 && abs(model.am_period_samples-2069100)<1
  period=model.am_period_samples; periodSource='AM lag linear fit on training frames 0:7; training residual <1 sample';
 else
  period=2069100; periodSource='Shared 1881x1100 envelope-period candidate; own-band delay fit unstable';
 end
 assert(abs(period-2069100)<15,'stitch:UnstablePeriod','Period fit departed from supported raster by >15 samples');
 filename=resolveIphoneSweepCapture(fc);
 frames=complex(zeros(n,numel(frameIndices),'single')); readRecords=cell(numel(frameIndices),1); phases=zeros(numel(frameIndices),1); coherence=zeros(size(phases));
 dc=[]; guardConvergence=[];
 for f=1:numel(frameIndices)
  k=frameIndices(f); start=origin+k*period; first=floor(start)-512;
  [raw,ri]=readRisIqBlock(filename,first,rawCount);
  if isempty(dc), dc=mean(raw(513:floor(period)+512)); end
  raw=raw-dc; q=start-first+u*period;
  [z,sd]=sampleGuardedIqFft(raw,q,GuardSamples=512);
  if f==1
   [raw2,~]=readRisIqBlock(filename,first-512,rawCount); raw2=raw2-dc;
   z2=sampleGuardedIqFft(raw2,q+512,GuardSamples=1024);
   guardConvergence=struct('rms_relative_error',double(norm(z-z2)/norm(z2)),'max_error_counts',double(max(abs(z-z2))), ...
      'tested_frame',k,'guards',[512 1024]); clear z2 raw2
  end
  frames(:,f)=z; readRecords{f}=struct('raw',ri,'query_start',q(1),'query_last',q(end),'interpolation',sd);
  if f==1, ref=z; end
  cross=sum(double(z).*conj(double(ref))); phases(f)=angle(cross);
  coherence(f)=abs(cross)/sqrt(sum(abs(double(z)).^2)*sum(abs(double(ref)).^2));
 end
 % The fit uses training frames only. Held-out phase is never refitted.
 phaseUnwrapped=unwrap(phases(train)); phaseFit=polyfit(frameIndices(train).',phaseUnwrapped,1);
 theta=phaseFit(1); phasePrediction=polyval(phaseFit,frameIndices.');
 derotate=single(exp(-1i*theta*u));
 trainMean=complex(zeros(n,1,'single')); testMean=trainMean; oracleTrain=trainMean; oracleTest=trainMean;
 amTrain=zeros(n,1,'single'); amTest=amTrain;
 for f=1:numel(frameIndices)
  corrected=frames(:,f)*single(exp(-1i*phasePrediction(f)));
  if ismember(f,train)
   trainMean=trainMean+corrected/numel(train); amTrain=amTrain+abs(frames(:,f))/numel(train);
   oracleTrain=oracleTrain+frames(:,f)*single(exp(-1i*phases(f)))/numel(train);
  else
   testMean=testMean+corrected/numel(test); amTest=amTest+abs(frames(:,f))/numel(test);
   oracleTest=oracleTest+frames(:,f)*single(exp(-1i*phases(f)))/numel(test);
  end
 end
 trainFFT=fftshift(fft(trainMean.*derotate))/n; testFFT=fftshift(fft(testMean.*derotate))/n;
 oracleTrainFFT=fftshift(fft(oracleTrain.*derotate))/n;
 oracleTestFFT=fftshift(fft(oracleTest.*derotate))/n;
 singleTrain=frames(:,1); singleTest=frames(:,9);
 cross=sum(double(testMean).*conj(double(trainMean)));
 independent=struct('complex_coherence',abs(cross)/(double(norm(trainMean))*double(norm(testMean))), ...
  'residual_phase_rad',angle(cross),'normalized_complex_error',double(norm(trainMean-testMean)/norm(trainMean)));
 phaseResidual=angle(exp(1i*(phases-phasePrediction)));
 meta=struct('fc_mhz',fc,'fs_hz',fs,'period_samples',period,'period_seconds',period/fs, ...
  'period_source',periodSource,'origin_samples',origin, ...
  'frame_indices_zero_based',frameIndices,'grid_length',n,'effective_resampled_rate_hz',n*fs/period, ...
  'phase_advance_rad_per_frame',theta,'phase_fit_intercept_rad',phaseFit(2), ...
  'measured_relative_phase_rad',phases,'phase_fit_residual_rad',phaseResidual, ...
  'per_frame_correlation_to_first',coherence,'train_phase_rms_rad',sqrt(mean(phaseResidual(train).^2)), ...
  'heldout_phase_rms_rad',sqrt(mean(phaseResidual(test).^2)), ...
  'training_dc_removed_real',real(dc),'training_dc_removed_imag',imag(dc), ...
  'guard_convergence',guardConvergence,'independent_template_comparison',independent, ...
  'periodic_spectrum_convention','fftshift(fft(mean_z(u)*exp(-j*theta*u)))/N', ...
  'phase_identifiability','theta is modulo 2pi/frame; global harmonic branch requires overlap validation', ...
  'phase_model_status','provisional; phase fits do not prove shared source coherence', ...
  'median_training_coherence',median(coherence(2:8)), ...
  'dc_removal_caveat','Fixed first-frame complex mean removed; may include genuine signal at receiver center', ...
  'heldout_parameters_refitted',false,'read_records',{readRecords});
 save(fullfile(folder,'templates.mat'),'trainFFT','testFFT','oracleTrainFFT','oracleTestFFT','singleTrain','singleTest','amTrain','amTest','meta','-v7');
 writeJsonFile(fullfile(folder,'metadata.json'),meta);
 % Demodulation precedes antialias raster reduction. interpft on real AM
 % is NOT used for antialiasing: explicit spectrum lowpass precedes reduction.
 cols=1100; rows=1881; nr=cols*rows;
 amImage=reshape(resamplePeriodicAm(amTrain,nr,PeriodSeconds=period/fs),cols,rows).';
 coherentImage=reshape(resamplePeriodicAm(abs(trainMean),nr,PeriodSeconds=period/fs),cols,rows).';
 heldoutImage=reshape(resamplePeriodicAm(abs(testMean),nr,PeriodSeconds=period/fs),cols,rows).';
 oracleImage=reshape(resamplePeriodicAm(abs(oracleTrain),nr,PeriodSeconds=period/fs),cols,rows).';
 imwrite(displayScale(amImage),fullfile(folder,'am_N8.png'));
 imwrite(displayScale(coherentImage),fullfile(folder,'coherent_frozen_N8.png'));
 imwrite(displayScale(heldoutImage),fullfile(folder,'coherent_heldout_N8.png'));
 imwrite(displayScale(oracleImage),fullfile(folder,'coherent_perframe_phase_N8.png'));
 fig=figure('Visible','off','Color','w','Position',[30 30 1400 650]); tiledlayout(fig,1,4,'TileSpacing','compact');
 labels={'AM mean N=8','Coherent train: frozen fit','Coherent held-out: frozen fit','Per-frame phase fit control'}; ims={amImage,coherentImage,heldoutImage,oracleImage};
 for p=1:4, nexttile; imagesc(ims{p}); axis image off; colormap gray; clim(double(sampleQuantile(ims{p}(:),[0.01 .99]))); title(labels{p}); end
 sgtitle(sprintf('fc %d MHz | P=%.5f | test coherence %.3f | test phase RMS %.3f rad',fc,period,independent.complex_coherence,meta.heldout_phase_rms_rad));
 exportgraphics(fig,fullfile(folder,'comparison.png'),Resolution=120); close(fig);
 overview.bands{b}=rmfield(meta,'read_records'); writeJsonFile(fullfile(out,'overview.json'),overview);
 fprintf('Template fc %d MHz P %.5f; train phase RMS %.3f; test phase RMS %.3f; coherence %.3f\n',fc,period,meta.train_phase_rms_rad,meta.heldout_phase_rms_rad,independent.complex_coherence);
 clear frames raw ref trainMean testMean oracleTrain trainFFT testFFT oracleTrainFFT
end
end
function y=displayScale(x)
q=double(sampleQuantile(x(:),[.01 .99])); y=uint8(255*min(1,max(0,(double(x)-q(1))/max(q(2)-q(1),eps))));
end
