function result=extractIphoneCaf27(out)
%EXTRACTIPHONECAF27 State-conditioned complex midpoint CAF from native IQ.
arguments
 out (1,1) string
end
lab=string(fileparts(mfilename('fullpath')));
addpath(fullfile(lab,'signal_processing'));
assert(~isfolder(out),'Refuse to overwrite output.');
mkdir(out);
previous=load(fullfile(lab,'results/iphone6_dsi3_codebook_20261027_v3/native_fold.mat'),'raster','fs','f0');
[labels,rowMeta,rowFeatures]=buildIphoneRowLabelsCaf27(previous.raster{1},out);
fs=previous.fs;f0=previous.f0;fc=100e6;N=1100;frameRows=1881;
lags=[0 1 2 3 4 6 8 12 16];orders=(1:32)';
starts=round([.2 1.1 1.8]*fs);numberSamples=16777600;
raw="C:/Users/leechanghoon/Downloads/black글_fc100MHz.rIs";
info=dir(raw);assert(info.bytes==1158300000);
pre=load(fullfile(lab,'results/iphone6_fc100_fam_20261026/preflight.mat'),'dc');
profiles=complex(zeros(N,numel(lags),3,3));
halfProfiles=complex(zeros(N,numel(lags),3,2,3));
profileCounts=zeros(size(profiles));images=cell(3,1);rawMeanPower=zeros(3,1);
readMetadata=cell(3,1);
for bb=1:3
 fid=fopen(raw,'r','ieee-be');assert(fid>=0);clean=onCleanup(@()fclose(fid));
 sums=complex(zeros(N*3,numel(lags),2));counts=zeros(size(sums));
 imageSums=complex(zeros(frameRows*N,2));imageCounts=zeros(frameRows*N,2);
 normSums=zeros(frameRows*N,1);totalPower=0;
 for done=0:2^20:numberSamples-1
  take=min(2^20,numberSamples-done);
  fseek(fid,4*(starts(bb)+done),'bof');
  iq=fread(fid,[2 take+max(lags)],'int16=>double');
  assert(size(iq,2)==take+max(lags));
  z=complex(iq(1,:),-iq(2,:)).'-pre.dc;
  n=starts(bb)+done+(0:take-1)';
  local=(0:take-1)';halves=1+double(done+local>=numberSamples/2);
  totalPower=totalPower+sum(abs(z(1:take)).^2);
  rowA=floor(n*f0/fs);classA=double(labels(mod(rowA,frameRows)+1));
  for dd=1:numel(lags)
   d=lags(dd);
   midpoint=(n+d/2)*f0/fs;
   phase=mod(midpoint,1)*N;bin=floor(phase)+1;fraction=mod(phase,1);
   row=floor(midpoint);rowB=floor((n+d)*f0/fs);
   cls=double(labels(mod(row,frameRows)+1));
   classB=double(labels(mod(rowB,frameRows)+1));
   pair=z(1+d:take+d).*conj(z(1:take));
   valid=cls>0 & cls==classA & cls==classB;
   for hh=1:2
    keep=valid&halves==hh;
    b0=bin(keep);b1=mod(b0,N)+1;c=cls(keep);a=fraction(keep);v=pair(keep);
    ind0=b0+(c-1)*N;ind1=b1+(c-1)*N;
    sums(:,dd,hh)=sums(:,dd,hh)+accumarray(ind0,v.*(1-a),[N*3 1])+accumarray(ind1,v.*a,[N*3 1]);
    counts(:,dd,hh)=counts(:,dd,hh)+accumarray(ind0,1-a,[N*3 1])+accumarray(ind1,a,[N*3 1]);
   end
   if d<=1
    ri=mod(row,frameRows)+1;idx=ri+(bin-1)*frameRows;column=d+1;
    imageSums(:,column)=imageSums(:,column)+accumarray(idx,pair,[frameRows*N 1]);
    imageCounts(:,column)=imageCounts(:,column)+accumarray(idx,1,[frameRows*N 1]);
    if d==1
     normSums=normSums+accumarray(idx,(abs(z(2:take+1)).^2+abs(z(1:take)).^2)/2,[frameRows*N 1]);
    end
   end
  end
 end
 clear clean
 rawMeanPower(bb)=totalPower/numberSamples;
 full=sum(sums,3)./max(sum(counts,3),1);
 for cls=1:3
  profiles(:,:,cls,bb)=full((cls-1)*N+(1:N),:);
  profileCounts(:,:,cls,bb)=sum(counts((cls-1)*N+(1:N),:,:),3);
  for hh=1:2
   halfProfiles(:,:,cls,hh,bb)=sums((cls-1)*N+(1:N),:,hh)./max(counts((cls-1)*N+(1:N),:,hh),1);
  end
 end
 images{bb}=struct('power',reshape(real(imageSums(:,1))./max(imageCounts(:,1),1),frameRows,N), ...
   'caf1',reshape(imageSums(:,2)./max(imageCounts(:,2),1),frameRows,N), ...
   'caf1_norm',reshape(normSums./max(imageCounts(:,2),1),frameRows,N), ...
   'count',reshape(imageCounts(:,1),frameRows,N));
 readMetadata{bb}=struct('first_sample_zero_based',starts(bb),'samples',numberSamples, ...
  'extra_lookahead_samples',max(lags),'start_seconds',starts(bb)/fs, ...
  'duration_seconds',numberSamples/fs,'byte_offset',4*starts(bb));
 fprintf('Complex CAF block%d complete; %d class bins without observations.\n',bb,sum(profileCounts(:,:,:,bb)==0,'all'));
end
scale=rawMeanPower(1);profiles=profiles/scale;halfProfiles=halfProfiles/scale;
for bb=1:3
 images{bb}.power=images{bb}.power/scale;images{bb}.caf1=images{bb}.caf1/scale;
 images{bb}.caf1_norm=images{bb}.caf1_norm/scale;
end
transform=exp(-2i*pi*orders*(0:N-1)/N)/N;
caf=complex(zeros(numel(orders),numel(lags),3,3));
halfCaf=complex(zeros(numel(orders),numel(lags),3,2,3));
for bb=1:3
 for cls=1:3
  caf(:,:,cls,bb)=transform*profiles(:,:,cls,bb);
  for hh=1:2,halfCaf(:,:,cls,hh,bb)=transform*halfProfiles(:,:,cls,hh,bb);end
 end
end
metadata=struct('native_fs_hz',fs,'rf_center_hz',fc,'frozen_frequency_hz',f0, ...
 'phase_bins',N,'lag_samples',lags,'lag_seconds',lags/fs,'harmonic_orders',orders, ...
 'raw',raw,'raw_bytes',info.bytes,'iq_convention','I-jQ','endian','ieee-be', ...
 'dtype','interleaved int16 I,Q','dc_real',real(pre.dc),'dc_imag',imag(pre.dc), ...
 'dc_scope','Frozen preflight value for all blocks','normalization_power_adc2',scale, ...
 'row_labels',rowMeta,'block_reads',{readMetadata}, ...
 'caf_convention','x[n+d]*conj(x[n]); alpha weighting at midpoint (n+d/2)/Fs', ...
 'phase_deposition','Linear deposition on neighboring phase nodes, count normalized before Fourier transform.', ...
 'pair_selection','Both endpoints and midpoint must have same nonzero frozen row class.', ...
 'raw_modified',false,'cfo_corrected',false,'clock_resampled',false);
save(fullfile(out,'complex_caf.mat'),'profiles','halfProfiles','profileCounts','caf','halfCaf', ...
 'images','labels','rowMeta','rowFeatures','metadata','fs','f0','fc','lags','orders','-v7.3');
fid=fopen(fullfile(out,'caf_metadata.json'),'w','n','UTF-8');clean=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(metadata,'PrettyPrint',true),'char');
result=metadata;
end
