function report=validateCafText27(out)
%VALIDATECAFTEXT27 Predict text-row CAF with channels trained on black/white.
% Known screenshot is used only for this forward-model validation. No measured
% reconstruction image is filled with screenshot pixels.
arguments
 out (1,1) string
end
data=load(fullfile(out,'complex_caf.mat'),'labels','rowFeatures','fs','f0','fc');
fits=load(fullfile(out,'caf_channel_fits.mat'));
book=buildDsi3LaneCodebook27();
controlNames=["valid","header-byte-permutation","header-bit-order-reversed","shuffled-sync-header","geometry"];
base=[book.videoWhite book.videoBlack book.dcs];
% Validate generalized generator against all previously audited 60 codewords.
checks=0;
for family=1:6
 if family<=4,mode="video";vc=family-1;indices=[family+4 family];
 elseif family==5,mode="2C";vc=0;indices=[10 9];
 else,mode="3C";vc=0;indices=[12 11];end
 for color=0:1
  index=indices(color+1);
  for control=0:4
   packet=buildDsiGrayPacketCaf27(repmat(uint8(255*color),1,750),mode,vc,controlNames(control+1));
   if control==0,ref=base(index);
   elseif control==4,ref=book.geometryControls(index);
   else,ref=book.matchedControls(3*(index-1)+control);end
   assert(isequal(packet.hsBits,ref.hsBits)&&isequal(packet.hsValid,ref.hsValid),'General codebook mismatch.');
   checks=checks+1;
  end
 end
end
screen=imread("C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png");
sourceRows=round(data.rowFeatures.source_coordinate(data.labels==3))+1;
pixels=uint8(255*(screen(sourceRows,:,1)>=128));
[patterns,~,whichPattern]=unique(pixels,'rows');
patternCounts=accumarray(whichPattern,1);
patternWeights=patternCounts/sum(patternCounts);
selected=unique([fits.validWinner fits.matchedWinner fits.controlWinner],'stable');
predictions=cell(numel(selected),1);records=cell(numel(selected),1);
for ii=1:numel(selected)
 index=selected(ii);r=fits.results(index);
 if r.family<=4,mode="video";vc=r.family-1;
 elseif r.family==5,mode="2C";vc=0;else,mode="3C";vc=0;end
 average=complex(zeros(128*numel(fits.lags),9));
 for pp=1:size(patterns,1)
  packet=buildDsiGrayPacketCaf27(patterns(pp,:),mode,vc,controlNames(r.control+1));
  model=dsi3LanePowerModel27(packet,r.rate_hz,data.f0,8192);
  B=dsiCafBasis27(model,r.emission_index,data.fs,data.fc,fits.lags,fits.orders);
  average=average+patternWeights(pp)*B;
 end
 H=r.H;q=[real(diag(H));real(H(1,2));imag(H(1,2));real(H(1,3));imag(H(1,3));real(H(2,3));imag(H(2,3))];
 ov=repmat(fits.orders,numel(fits.lags),1);
 prediction=(average*q).*exp(-2i*pi*ov*r.delay_phase).*repmat(sinc(fits.orders/1100).^2,numel(fits.lags),1);
 predictions{ii}=reshape(prediction,128,numel(fits.lags));
 w=fits.weights(:,:,3);w=w(:);
 blocks=cell(3,1);
 for bb=1:3
  y=fits.target(:,:,3,bb);y=y(:);
  c=sum(w.*conj(y).*prediction)/sqrt(sum(w.*abs(y).^2)*sum(w.*abs(prediction).^2));
  blocks{bb}=struct('nmse',sum(w.*abs(y-prediction).^2)/sum(w.*abs(y).^2), ...
   'real_coherence',real(c),'abs_coherence',abs(c),'phase_deg',angle(c)*180/pi);
 end
 records{ii}=struct('candidate',r.name,'group_index',index,'blocks',[blocks{:}]);
 fprintf('TEXT no-channel-refit %s: test NMSE %.4f %.4f.\n',r.name,blocks{2}.nmse,blocks{3}.nmse);
end
report=struct('general_packet_checks',checks,'reference_threshold',128, ...
 'source_text_rows',sourceRows,'unique_binary_text_rows',size(patterns,1), ...
 'pattern_counts',patternCounts,'channel_refitted_on_text',false, ...
 'reference_scope','Known-image forward prediction only; no screenshot pixels used to render measured reconstruction.', ...
 'candidates',[records{:}]);
fid=fopen(fullfile(out,'text_forward_validation.json'),'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,'PrettyPrint',true),'char');
save(fullfile(out,'text_forward_validation.mat'),'report','predictions','selected','patternWeights','sourceRows');
end
