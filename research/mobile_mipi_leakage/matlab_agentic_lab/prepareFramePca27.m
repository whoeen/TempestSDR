function summary=prepareFramePca27(out)
%PREPAREFRAMEPCA27 Frozen frame-axis complex PCA, then component CAF selection.
arguments
 out (1,1) string
end
lab=string(fileparts(mfilename('fullpath')));addpath(fullfile(lab,'signal_processing'));
priorOut=fullfile(lab,'results/iphone6_complex_caf_channels_20261027');
assert(~isfile(fullfile(out,'pca_summary.json')),'Refuse to overwrite completed results.');if ~isfolder(out),mkdir(out);end
d=load(fullfile(priorOut,'complex_caf.mat'),'metadata','labels','rowMeta','rowFeatures','fs','f0','fc');
N=1100;R=1881;K=8;M=N*R;fsGrid=N*d.f0;Tf=R/d.f0;
starts=[.2 1.1 1.8];frame0=ceil(starts/Tf);raw=string(d.metadata.raw);
assert(dir(raw).bytes==d.metadata.raw_bytes);
scale=d.metadata.normalization_power_adc2;
dc=complex(d.metadata.dc_real,d.metadata.dc_imag);
orders=(1:128)';lags=[1 2 3 4 6 8 12 16]';
observations=struct('fs',fsGrid,'fc',d.fc,'f0',d.f0,'orders',orders,'lags',lags, ...
 'labels',d.labels,'rowFeatures',d.rowFeatures,'rowMeta',d.rowMeta,'methods',struct([]));
iqMethods=struct([]);cafMethods=struct([]);imageData=struct('labels',d.labels,'rowMeta',d.rowMeta,'f0',d.f0);
allComponentImages=cell(3,1);
for bb=1:3
 X=complex(zeros(M,K,'single'));
 for kk=1:K
  frameIndex=frame0(bb)+kk-1;
  [x,alignMeta]=readFrame(raw,frameIndex,N,R,d.fs,d.f0,dc,4096);
  phase=exp(2i*pi*mod(d.fc*frameIndex*Tf,1));
  X(:,kk)=single(x*phase/sqrt(scale));
 end
 if bb==1
  % Numerical resampling check at wider guard, same measurement samples.
  [wide,~]=readFrame(raw,frame0(1),N,R,d.fs,d.f0,dc,8192);
  wide=single(wide*exp(2i*pi*mod(d.fc*frame0(1)*Tf,1))/sqrt(scale));
  interpolationGuardRelativeError=norm(double(X(:,1)-wide))/norm(double(wide));
  clear wide
  G=zeros(K,K);
  for first=1:131072:M
   q=double(X(first:min(M,first+131071),:));G=G+q'*q;
  end
  G=(G+G')/2;[V,D]=eig(G);[lambda,idx]=sort(real(diag(D)),'descend');V=V(:,idx);
  lambda=max(lambda,0);singularEnergy=lambda/sum(lambda);
  Y=X*single(V)/sqrt(K);
  YA=X(:,1:4)*single(V(1:4,:))*sqrt(2/K);
  YB=X(:,5:8)*single(V(5:8,:))*sqrt(2/K);
  [scores,details]=scoreFramePcaCaf27(Y,YA,YB,d.labels,N,fsGrid,d.f0);
  selected=details.primaryComponent;top2=details.secondaryComponents;
  selectionPositive=~isempty(selected);
  if isempty(selected)
   eligible=find(scores.Eligible);[~,best]=max(scores.ContrastHalfRealCosine(eligible));selected=eligible(best);
   top2=selected;
  end
  if isempty(top2),top2=selected;end
  selected=selected(1);top2=top2(:)';
  clear Y YA YB
  weights={eye(K)/sqrt(K),ones(K,1)/K,V(:,1)/sqrt(K),V(:,selected)/sqrt(K),V(:,top2)/sqrt(K)};
  names=["rawgrid","coherentmean","PC1","selected","top2"];
  for mm=1:numel(names)
   w=weights{mm};mix=struct('weights',w.*exp(2i*pi*mod(d.fc*(0:K-1)'*Tf,1)), ...
    'timeOffsetsSeconds',(0:K-1)'*Tf,'periodicRfGridInvariant',true);
   obsRec=struct('name',names(mm),'target',complex(zeros(128,8,3,3)), ...
    'halves',complex(zeros(128,8,3,2)),'mix',mix);
   iqRec=struct('name',names(mm),'iq',{{[],[],[]}});
   cafRec=struct('name',names(mm),'caf',{{[],[],[]}},'power',{{[],[],[]}});
   if mm==1,observations.methods=obsRec;iqMethods=iqRec;cafMethods=cafRec;
   else,observations.methods(mm)=obsRec;iqMethods(mm)=iqRec;cafMethods(mm)=cafRec;end
  end
  % Linear temporal mixing commutes with a common sample-position permutation.
  q=double(X(1:8192,:));perm=circshift((1:8192)',137);w=weights{4};
  lhs=q(perm,:)*w;rhs=q*w;rhs=rhs(perm,:);
  antiImprintRelativeError=norm(lhs-rhs)/max(norm(rhs),eps);
  DD=diag(exp(1i*(0:K-1)*.71));phaseEigen=sort(real(eig(DD'*G*DD)),'descend');
  globalPhaseSpectrumError=norm(phaseEigen-lambda)/norm(lambda);
  writetable(scores,fullfile(out,'component_scores.csv'));
  save(fullfile(out,'training_pca.mat'),'V','lambda','singularEnergy','scores','details', ...
   'selected','top2','selectionPositive','G','frame0','Tf','alignMeta','interpolationGuardRelativeError', ...
   'antiImprintRelativeError','globalPhaseSpectrumError','-v7.3');
  fprintf('PCA trained. selected PC%d, top %s; guard error %.5g.\n',selected,mat2str(top2),interpolationGuardRelativeError);
 end
 % Retain all component power maps for the PC1/stripe diagnosis.
 allY=X*single(V)/sqrt(K);pcImages=zeros(R,N,K,'single');
 for kk=1:K,pcImages(:,:,kk)=reshape(abs(allY(:,kk)).^2,N,R).';end
 allComponentImages{bb}=pcImages;clear allY pcImages
 for mm=1:numel(names)
  w=weights{mm};Z=X*single(w);
  [target,cafImage,powerImage]=frameCafStats27(Z,d.labels,N,lags,orders);
  observations.methods(mm).target(:,:,:,bb)=target;
  cafMethods(mm).caf{bb}=single(cafImage);cafMethods(mm).power{bb}=single(powerImage);
  if bb==1
   ZA=X(:,1:4)*single(w(1:4,:))*sqrt(2);
   ZB=X(:,5:8)*single(w(5:8,:))*sqrt(2);
   observations.methods(mm).halves(:,:,:,1)=frameCafStats27(ZA,d.labels,N,lags,orders);
   observations.methods(mm).halves(:,:,:,2)=frameCafStats27(ZB,d.labels,N,lags,orders);
   clear ZA ZB
  end
  % Rawgrid has 8 individual-frame features; the requested baseline is coherentmean.
  if mm>1
   features=reshape(Z,N,R,size(Z,2));features=permute(features,[2 1 3]);
   rowPhase=single(exp(2i*pi*mod(d.fc*(0:R-1)'/d.f0,1)));
   iqMethods(mm).iq{bb}=features.*rowPhase;
  end
  clear Z
 end
 % Coherence-breaking control: independent shifts per input frame; same frozen weights.
 if bb>=2
  Znull=complex(zeros(M,1,'single'));w=weights{4};shifts=round(linspace(0,.45*M,K));
  for kk=1:K,Znull=Znull+circshift(X(:,kk),shifts(kk))*single(w(kk));end
  [~,nullCaf,nullPower]=frameCafStats27(Znull,d.labels,N,lags,orders);
  save(fullfile(out,sprintf('null_B%d.mat',bb)),'nullCaf','nullPower','shifts','-v7.3');
 end
 fprintf('Aligned and projected B%d: frames %d through %d.\n',bb,frame0(bb),frame0(bb)+K-1);
 clear X
end
iqMethods=iqMethods(2:end);
summary=struct('fs_native_hz',d.fs,'fs_grid_hz',fsGrid,'f0_hz',d.f0,'fc_hz',d.fc, ...
 'frame_rows_hypothesis',R,'phase_samples_per_row',N,'frames_per_block',K, ...
 'first_absolute_frame_index',frame0,'block_start_seconds',frame0*Tf,'block_duration_seconds',K*Tf, ...
 'raw',raw,'raw_bytes',d.metadata.raw_bytes,'endian','ieee-be','iq_convention','I-jQ', ...
 'scale_power_adc2',scale,'dc_real',real(dc),'dc_imag',imag(dc), ...
 'raw_modified',false,'pca_matrix','within-frame sample positions x 8 measured frames', ...
 'operator','Frozen right singular vectors. Output y_j=X*v_j/sqrt(8); no spatial U projection.', ...
 'frame_phase_correction','Known absolute exp(+j2pi fc frameStartTime); no test-fitted phase correction.', ...
 'iq_feature_extra_reference','Known exp(+j2pi fc rowIndex/f0), before binary IQ projection only.', ...
 'selected_component',selected,'top2_components',top2,'selection_positive_evidence',selectionPositive, ...
 'singular_energy_fraction',singularEnergy,'component_scores',table2struct(scores), ...
 'anti_imprint_permutation_relative_error',antiImprintRelativeError, ...
 'global_phase_singular_spectrum_relative_error',globalPhaseSpectrumError, ...
 'interpolation_guard_relative_error_4096_vs8192',interpolationGuardRelativeError,'alignment',alignMeta, ...
 'selection_scope','B1 only; class labels are reference-calibrated priors; no pixel labels used.', ...
 'binary_scope','Complex IQ features projected onto a B1 black-white discriminant, then signed threshold; not a power or absolute CAF threshold.');
save(fullfile(out,'pca_caf_observations.mat'),'observations','-v7.3');
save(fullfile(out,'pca_image_data.mat'),'imageData','cafMethods','allComponentImages','summary','-v7.3');
save(fullfile(out,'pca_iq_features.mat'),'imageData','iqMethods','summary','-v7.3');
fid=fopen(fullfile(out,'pca_summary.json'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));fwrite(fid,jsonencode(summary,'PrettyPrint',true),'char');
end

function [x,meta]=readFrame(path,frameIndex,N,R,fs,f0,dc,nfft)
% FFT fractional delay independently per row, with wide measured guards.
% Within-row sample-rate slope is held at its midpoint; its maximum error is logged.
ratio=fs/(N*f0);rowStarts=(frameIndex*R+(0:R-1))*fs/f0;
base=floor(rowStarts);delta=rowStarts-base+(N-1)/2*(ratio-1);
guard=floor((nfft-N)/2);first=base(1)-guard;last=base(end)-guard+nfft-1;
assert(first>=0);fid=fopen(path,'r','ieee-be');assert(fid>=0);c=onCleanup(@()fclose(fid));
fseek(fid,4*first,'bof');iq=fread(fid,[2 last-first+1],'int16=>double');
assert(size(iq,2)==last-first+1);z=complex(iq(1,:),-iq(2,:)).'-dc;
x=complex(zeros(N,R));frequency=ifftshift((-nfft/2:nfft/2-1)')/nfft;
for rr=1:96:R
 ids=rr:min(R,rr+95);index=(0:nfft-1)'+(base(ids)-guard-first+1);
 slab=z(index);shifted=ifft(fft(slab,[],1).*exp((2i*pi*frequency)*delta(ids)),[],1);
 x(:,ids)=shifted(guard+(1:N),:);
end
x=x(:);
meta=struct('method','FFT fractional delay per row with measured guards; midpoint affine-clock approximation', ...
 'fft_length',nfft,'guard_samples',guard,'native_to_grid_step',ratio, ...
 'max_within_row_timing_approximation_samples',abs(ratio-1)*(N-1)/2, ...
 'max_within_row_phase_approximation_at_nyquist_rad',pi*abs(ratio-1)*(N-1)/2, ...
 'first_native_sample',first,'native_samples_read',last-first+1, ...
 'guard_comparison_scope','One training frame at nfft4096 and8192; empirical sensitivity, not strict interpolation bound.');
end
