function report = auditIphonePairLiteralIir(options)
%AUDITIPHONEPAIRLITERALIIR Actual pair SOS control; failed alignment unchanged.
% Custom FILTER forward/reverse is not FILTFILT. SOS redesigned at actual
% Fs=N/T (~503MHz), not the earlier source Fs=2B (~360MHz). No RF refitting.
arguments
 options.OutputFolder (1,1) string = ""
end
lab=fileparts(mfilename('fullpath'));
addpath(fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
source=fullfile(lab,'results','iphone6_stitch_20261023');
out=options.OutputFolder;
if strlength(out)==0,out=fullfile(lab,'results','iphone6_followup_20261024','pair_100_160_literal_iir');end
assert(~isfolder(out)&&~isfile(out),'pairIir:Exists','Refuse overwrite: %s',out);
alignmentPath=fullfile(source,'stitch_polarity_+1','pair_100_160','alignment.json');
best=jsondecode(fileread(alignmentPath));a=best.alignment;
centers=[a.center_bin_a,best.selected_center_bin_b];T=a.period_seconds;bw=120e6;
lowEdge=centers(1)/T-bw/2;highEdge=centers(2)/T+bw/2;union=highEdge-lowEdge;
referenceBin=floor(lowEdge*T);gridLow=referenceBin/T;
n=2^nextpow2(max(ceil(2*union*T),2*(ceil(highEdge*T)-referenceBin)));
assert(n<=2^23,'pairIir:Allocation','Adjacent-pair-only bounded allocation.');
fs=n/T;physicalCross=mean(centers)/T;cross=physicalCross-gridLow;
oldFs=2*union;oldCross=physicalCross-lowEdge;
[sosLow,sosHigh]=butter4(fs,cross);guard=256;margin=512;
inputPaths=[string(fullfile(source,'templates','fc100MHz','templates.mat')),string(fullfile(source,'templates','fc160MHz','templates.mat'))];
inputs=cell(1,2);
for b=1:2
 inputs{b}=load(inputPaths(b),'trainFFT','testFFT');
 assert(numel(inputs{b}.trainFFT)==a.fft_length&&numel(inputs{b}.testFFT)==a.fft_length,'pairIir:InputGrid','Input length mismatch.');
end
images=struct();metrics=struct();splits=["train","heldout"];
for s=1:2
 split=splits(s);fprintf('Pair literal SOS %s: N%d, Fs%.6f MS/s\n',split,n,fs/1e6);
 iirSum=complex(zeros(n,1));fftSum=complex(zeros(n,1));branches=cell(1,2);
 for b=1:2
  if s==1,spectrum=inputs{b}.trainFFT;else,spectrum=inputs{b}.testFFT;end
  nin=numel(spectrum);half=bw*T/2;
  first=max(ceil(centers(b)-half),centers(b)-nin/2);
  last=min(ceil(centers(b)+half)-1,centers(b)+nin/2-1);
  k=(first:last).';indices=k-(centers(b)-nin/2)+1;q=k-referenceBin;
  assert(all(q>=0&q<n/2),'pairIir:Mapping','Positive analytic support exceeds Nyquist.');
  c=double(spectrum(indices));
  if b==2,c=c.*exp(1i*2*pi*(k/T)*a.delay_seconds-1i*a.phase_rad);end
  % Unshifted FFT/N on exactly the same grid for both implementations.
  branchFft=complex(zeros(n,1));branchFft(q+1)=c;wave=ifft(branchFft)*n;clear branchFft
  L=lrLow(q/T,cross,fs);
  if b==1,sos=sosLow;w=L;name='low';else,sos=sosHigh;w=1-L;name='high';end
  fftSum(q+1)=fftSum(q+1)+c.*w;
  filtered=customForwardBackward(wave,sos,guard);iirSum=iirSum+filtered;
  branches{b}=struct('nominal_center_mhz',100+60*(b-1),'branch',name, ...
   'first_global_bin',first,'last_global_bin',last,'input_spectral_energy',sum(abs(c).^2), ...
   'filtered_mean_power',sum(abs(filtered).^2)/n);
  clear wave filtered c k indices q L w
 end
 fftWave=ifft(fftSum)*n;clear fftSum
 eq=waveformErrors(iirSum,fftWave,margin);
 [amIir,aa]=resamplePeriodicAm(abs(iirSum),1100*1881,PeriodSeconds=T);clear iirSum
 amFft=resamplePeriodicAm(abs(fftWave),1100*1881,PeriodSeconds=T);clear fftWave
 eq.am_raster_relative_rms=norm(amIir-amFft)/max(norm(amFft),eps);
 eq.passed=eq.full_relative_rms<1e-10&&eq.interior_relative_rms<1e-10&&eq.am_raster_relative_rms<1e-10;
 images.(split+"_iir")=single(reshape(amIir,1100,1881).');
 images.(split+"_fft")=single(reshape(amFft,1100,1881).');clear amIir amFft
 metrics.(split)=struct('equivalence',eq,'antialias',aa,'branches',{branches});
end
limits=double(sampleQuantile(images.train_fft,[.01 .99]));
if limits(2)<=limits(1),limits(2)=limits(1)+1;end
physicalF=linspace(lowEdge,highEdge,4097).';newL=lrLow(physicalF-gridLow,cross,fs);oldL=lrLow(physicalF-lowEdge,oldCross,oldFs);
report=struct('status','complete','method','actual pair custom SOS forward/backward vs same-grid FFT', ...
 'source_alignment',alignmentPath,'source_template_paths',inputPaths, ...
 'train_frames_zero_based',0:7,'heldout_frames_zero_based',16:23,'iq_polarity',1, ...
 'center_bins',centers,'period_seconds',T,'saved_delay_seconds',a.delay_seconds,'saved_phase_rad',a.phase_rad, ...
 'selected_branch_offset_bins',best.selected_offset_bins,'branch_ambiguous',best.branch_ambiguous, ...
 'saved_train_overlap_coherence',a.train_unit_gain.complex_coherence,'saved_heldout_overlap_coherence',a.test_unit_gain.complex_coherence, ...
 'alignment_validated',false,'new_alignment_or_gain_fit',false,'unit_gain',true, ...
 'output_samples',n,'synthesis_and_new_filter_rate_hz',fs,'old_source_filter_rate_hz',oldFs, ...
 'nominal_union_hz',union,'reference_global_bin',referenceBin,'reference_frequency_relative_anchor_hz',gridLow, ...
 'nominal_low_relative_anchor_hz',lowEdge,'reference_rounding_hz',gridLow-lowEdge, ...
 'physical_crossover_relative_anchor_hz',physicalCross,'new_crossover_relative_grid_origin_hz',cross, ...
 'old_crossover_relative_nominal_edge_hz',oldCross,'maximum_new_vs_old_weight_difference',max(abs(newL-oldL)), ...
 'new_filter_is_old_paper_rate_response',false, ...
 'filter_rate_caveat','SOS redesigned at actual Fs=N/T (~503MHz); differs from old source-rate (~360MHz) digital weighting', ...
 'filter_implementation','two Butterworth4 SOS per branch, base FILTER forward/reverse with zero states and periodic guards; NOT FILTFILT', ...
 'sos_low',sosLow,'sos_high',sosHigh,'periodic_guard_samples_each_end',guard,'interior_margin_samples',margin, ...
 'periodic_extension_assumed',true,'splits',metrics,'shared_scale_counts',limits, ...
 'scale_source','training FFT AM 1/99 percentiles fixed across all train/test and IIR/FFT panels', ...
 'train_test_iir_am_correlation',correlation(images.train_iir,images.heldout_iir), ...
 'train_test_fft_am_correlation',correlation(images.train_fft,images.heldout_fft), ...
 'all_numerical_checks_passed',metrics.train.equivalence.passed&&metrics.heldout.equivalence.passed, ...
 'successful_screen_recovery_claimed',false, ...
 'conclusion','Filter equivalence control only. Frozen overlap validation failed; no successful coherent RF recovery claim. Periodic guards do not establish physical seam closure.');
mkdir(out);writeJsonFile(fullfile(out,'audit.json'),report);
names=fieldnames(images);
for j=1:numel(names)
 shown=min(1,max(0,(double(images.(names{j}))-limits(1))/max(diff(limits),eps)));
 imwrite(shown,fullfile(out,string(names{j})+"_shared_scale.png"));
end
save(fullfile(out,'image_arrays.mat'),'images','report','limits','-v7');
writetable(table(physicalF-gridLow,newL,oldL,VariableNames={'new_grid_frequency_hz','new_rate_low_weight','old_source_rate_low_weight'}),fullfile(out,'filter_rate_comparison.csv'));
f=figure('Visible','off','Position',[40 40 1450 1050]);tiledlayout(f,2,2);
for s=1:2
 split=splits(s);ax=nexttile;imagesc(ax,images.(split+"_iir"),limits);axis(ax,'image');axis(ax,'off');title(ax,split+" custom SOS forward/backward");
 ax=nexttile;imagesc(ax,images.(split+"_fft"),limits);axis(ax,'image');axis(ax,'off');title(ax,split+" FFT at same new filter rate");
end
colormap(f,gray(256));sgtitle(f,'100 + 160 MHz | failed overlap alignment reused | filter equivalence control only');
exportgraphics(f,fullfile(out,'comparison_shared_scale.png'),Resolution=140);close(f);
assert(report.all_numerical_checks_passed,'pairIir:Equivalence','Numerical equivalence failed; inspect saved audit.json.');
end

function [low,high]=butter4(fs,fc)
k=tan(pi*fc/fs);Q=1./(2*cos([pi/8,3*pi/8]));low=zeros(2,6);high=zeros(2,6);
for j=1:2
 scale=1/(1+k/Q(j)+k*k);a=[1,2*(k*k-1)*scale,(1-k/Q(j)+k*k)*scale];
 low(j,:)=[k*k*[1 2 1]*scale,a];high(j,:)=[[1 -2 1]*scale,a];
end
end

function y=customForwardBackward(x,sos,guard)
y=[x(end-guard+1:end);x;x(1:guard)];
for j=1:2,y=filter(sos(j,1:3),sos(j,4:6),y);end
y=flipud(y);
for j=1:2,y=filter(sos(j,1:3),sos(j,4:6),y);end
y=flipud(y);y=y(guard+1:guard+numel(x));
end

function L=lrLow(f,fc,fs)
r=abs(tan(pi*f/fs))/tan(pi*fc/fs);L=1./(1+r.^8);L(f<=0)=1;L(f>=fs/2)=0;
end

function eq=waveformErrors(actual,reference,margin)
n=numel(actual);ep=0;rp=0;iep=0;irp=0;eep=0;erp=0;maxError=0;
for first=1:2^18:n
 last=min(n,first+2^18-1);idx=(first:last).';d=actual(idx)-reference(idx);e=abs(d).^2;r=abs(reference(idx)).^2;
 ep=ep+sum(e);rp=rp+sum(r);inside=idx>margin&idx<=n-margin;
 iep=iep+sum(e(inside));irp=irp+sum(r(inside));eep=eep+sum(e(~inside));erp=erp+sum(r(~inside));maxError=max(maxError,max(abs(d)));
end
 eq=struct('full_relative_rms',sqrt(ep/max(rp,eps)),'interior_relative_rms',sqrt(iep/max(irp,eps)), ...
 'edge_relative_rms',sqrt(eep/max(erp,eps)),'max_absolute_error',maxError,'tolerance',1e-10);
end

function value=correlation(x,y)
x=double(x(:));y=double(y(:));x=x-mean(x);y=y-mean(y);value=dot(x,y)/max(norm(x)*norm(y),eps);
end
