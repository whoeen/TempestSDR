function report=fitIphoneCaf27(out,orientation)
%FITIPHONECAF27 Shared three-lane rank-one channels from black/white CAF.
arguments
 out (1,1) string
 orientation (1,1) string = "I-minus-jQ"
end
lab=string(fileparts(mfilename('fullpath')));addpath(fullfile(lab,'signal_processing'));
data=load(fullfile(out,'complex_caf.mat'));
dest=out;
if orientation=="conjugated-IQ"
 data.profiles=conj(data.profiles);data.halfProfiles=conj(data.halfProfiles);
 dest=fullfile(out,'conjugated_iq_audit');if ~isfolder(dest),mkdir(dest);end
else
 assert(orientation=="I-minus-jQ");
end
book=buildDsi3LaneCodebook27();
lags=data.lags(2:end)';orders=(1:128)';
F=exp(-2i*pi*orders*(0:1099)/1100)/1100;
target=complex(zeros(128,numel(lags),3,3));halves=complex(zeros(128,numel(lags),3,2));
for bb=1:3
 for cls=1:3
  target(:,:,cls,bb)=F*data.profiles(:,2:end,cls,bb);
  if bb==1
   for hh=1:2,halves(:,:,cls,hh)=F*data.halfProfiles(:,2:end,cls,hh,1);end
  end
 end
end
noise=abs(halves(:,:,:,1)-halves(:,:,:,2)).^2/2;
floorVar=max(median(noise(:,:,1:2),'all'),eps)*.1;
weights=1./max(noise,floorVar);
typical=median(weights(:,:,1:2),'all');
weights=min(25*typical,max(typical/25,weights))/typical;
% Approximate linear deposition transfer; exact numerical effect audited later.
deposit=sinc(orders/1100).^2;
coarseOrders=(1:32)';
coarseLagMask=ismember(lags,[1 2 4 8 16]);coarseLags=lags(coarseLagMask);
rates=(685:40:1485)'*1e6;
controlNames=["valid","header-byte-permutation","header-bit-order-reversed","shuffled-sync-header","geometry"];
groups=struct([]);
counter=0;
for family=1:6
 if family<=4,wi=family;bi=family+4;familyName="video-vc"+(family-1);
 elseif family==5,wi=9;bi=10;familyName="dcs-2C-vc0";
 else,wi=11;bi=12;familyName="dcs-3C-vc0";
 end
 basePackets=[book.videoWhite book.videoBlack book.dcs];
 for control=0:4
  counter=counter+1;
  if control==0,w=basePackets(wi);b=basePackets(bi);
  elseif control==4,w=book.geometryControls(wi);b=book.geometryControls(bi);
  else,w=book.matchedControls(3*(wi-1)+control);b=book.matchedControls(3*(bi-1)+control);
  end
  rec=struct('family',family,'control',control,'name',familyName+"-"+controlNames(control+1), ...
   'black',b,'white',w);
  if counter==1,groups=rec;else,groups(counter)=rec;end
 end
end
coarseY=target(1:32,coarseLagMask,1:2,1);coarseY=coarseY(:);
coarseW=weights(1:32,coarseLagMask,1:2);coarseW=coarseW(:);
fullY=target(:,:,1:2,1);fullY=fullY(:);
fullW=weights(:,:,1:2);fullW=fullW(:);
nPhase=512;
candidateLog=zeros(numel(groups)*numel(rates)*3,7);
best=cell(numel(groups),1);row=0;
for gg=1:numel(groups)
 bestHere=struct('nmse',Inf);
 for rr=1:numel(rates)
  mBlack=dsi3LanePowerModel27(groups(gg).black,rates(rr),data.f0,8192);
  mWhite=dsi3LanePowerModel27(groups(gg).white,rates(rr),data.f0,8192);
  for ee=1:3
   B0=dsiCafBasis27(mBlack,ee,data.fs,data.fc,coarseLags,coarseOrders);
   B1=dsiCafBasis27(mWhite,ee,data.fs,data.fc,coarseLags,coarseOrders);
   B=[B0;B1].*repmat(sinc(coarseOrders/1100).^2,numel(coarseLags)*2,1);
   orderVector=repmat(coarseOrders,numel(coarseLags)*2,1);
   delays=coarseDelaySeeds(B,coarseY,coarseW,coarseOrders,numel(coarseLags)*2,nPhase);
   for jj=1:numel(delays)
    phase=delays(jj)/nPhase;
    delayed=B.*exp(-2i*pi*orderVector*phase);
    fit=fitDsiCafChannel27(delayed,coarseY,coarseW,struct('optimize',false));
    if fit.complexResidualNmse<bestHere.nmse
     bestHere=struct('nmse',fit.complexResidualNmse,'rate',rates(rr), ...
      'emission',ee,'delay_phase',phase,'fit',fit);
    end
   end
   row=row+1;
   candidateLog(row,:)=[gg groups(gg).family groups(gg).control rates(rr) ee bestHere.nmse bestHere.delay_phase];
  end
 end
 best{gg}=bestHere;
 fprintf('CAF coarse %d/%d %s: NMSE %.4f rate %.0f Mb/s.\n',gg,numel(groups),groups(gg).name,bestHere.nmse,bestHere.rate/1e6);
end
writetable(array2table(candidateLog,'VariableNames',{'Group','Family','Control','LaneRateHz','Emission','BestSoFarNmse','BestSoFarDelayPhase'}),fullfile(dest,'caf_coarse_scan.csv'));

results=cell(numel(groups),1);predictions=cell(numel(groups),1);
for gg=1:numel(groups)
 coarse=best{gg};
 % Same local rate refinement for every protocol/control group.
 refineRates=unique(max(681e6,coarse.rate+[-10 0 10]*1e6));
 bestFull=struct('complexResidualNmse',Inf);
 for rr=1:numel(refineRates)
  rate=refineRates(rr);ee=coarse.emission;
  mBlack=dsi3LanePowerModel27(groups(gg).black,rate,data.f0,8192);
  mWhite=dsi3LanePowerModel27(groups(gg).white,rate,data.f0,8192);
  B0=dsiCafBasis27(mBlack,ee,data.fs,data.fc,lags,orders);
  B1=dsiCafBasis27(mWhite,ee,data.fs,data.fc,lags,orders);
  B=[B0;B1].*repmat(deposit,numel(lags)*2,1);
  ov=repmat(orders,numel(lags)*2,1);
  phase=coarse.delay_phase;
  for iteration=1:4
   delayed=B.*exp(-2i*pi*ov*phase);
   fit=fitDsiCafChannel27(delayed,fullY,fullW,struct('maxStarts',3,'maxIterations',400));
   H=fit.H;q=hermitianVector(H);
   unshifted=B*q;
   radius=(2/nPhase)/(2^(iteration-1));
   candidates=phase+linspace(-radius,radius,65);
   prediction=unshifted.*exp(-2i*pi*ov*candidates);
   loss=sum(fullW.*abs(prediction-fullY).^2,1)/sum(fullW.*abs(fullY).^2);
   [~,kk]=min(loss);phase=mod(candidates(kk),1);
  end
  delayed=B.*exp(-2i*pi*ov*phase);
  fit=fitDsiCafChannel27(delayed,fullY,fullW,struct('maxStarts',5,'maxIterations',600));
  if fit.complexResidualNmse<bestFull.complexResidualNmse
   bestFull=fit;bestFull.rate_hz=rate;bestFull.emission_index=ee;
   bestFull.emission=mBlack.emissionNames(ee);bestFull.delay_phase=phase;
   bestFull.delay_seconds=phase/data.f0;bestFull.B=delayed;
  end
 end
 pred=bestFull.prediction;predictions{gg}=reshape(pred,128,numel(lags),2);
 metrics=cell(3,1);
 for bb=1:3
  y=target(:,:,1:2,bb);metrics{bb}=compare(pred,y(:),fullW);
 end
 rec=rmfield(bestFull,{'B','prediction'});rec.name=groups(gg).name;
 rec.family=groups(gg).family;rec.control=groups(gg).control;rec.blocks=[metrics{:}];
 rec.channel_shared_between_classes=["black","white"];rec.training_block=1;
 results{gg}=rec;
 fprintf('CAF refined %s: train %.4f; test %.4f %.4f; Jcond %.1f.\n', ...
  rec.name,rec.blocks(1).nmse,rec.blocks(2).nmse,rec.blocks(3).nmse,rec.channelJacobianCondition);
end
results=[results{:}];valid=find([results.control]==0);invalid=find([results.control]~=0);
trainLoss=arrayfun(@(r)r.blocks(1).nmse,results);
[~,i]=min(trainLoss(valid));validWinner=valid(i);
[~,i]=min(trainLoss(invalid));controlWinner=invalid(i);
% Same-family controls are reported separately from the larger control bank.
matched=find([results.family]==results(validWinner).family&[results.control]~=0);
[~,i]=min(trainLoss(matched));matchedWinner=matched(i);
save(fullfile(dest,'caf_channel_fits.mat'),'results','predictions','target','weights','halves', ...
 'orders','lags','groups','rates','best','candidateLog','validWinner','controlWinner','matchedWinner','-v7.3');
summary=struct('valid',jsonSafe(results(validWinner)),'control',jsonSafe(results(controlWinner)), ...
 'matched_control',jsonSafe(results(matchedWinner)), ...
 'iq_orientation',orientation,'groups',numel(groups),'coarse_rate_hz',rates,'fit_lags_samples',lags,'fit_harmonics',orders, ...
 'native_fs_hz',data.fs,'f0_hz',data.f0,'fc_hz',data.fc, ...
 'fit_statistic','Complex weighted residual NMSE; no arbitrary phase rotation.', ...
 'weights','B1 half-difference precision, floored and capped; frozen for test.', ...
 'shared_channels','Black and white stacked; text not used for channel fitting.', ...
 'cfo_correction',false,'actual_hardware_channels_identified',false, ...
 'codeword_decoded',false,'lane_count_verified',false, ...
 'scope','Conditional frequency-flat rank-one three-lane model; nominal RF-to-baseband phase included.');
writeJson(fullfile(dest,'caf_fit_summary.json'),summary);
names=string({results.name})';ratesOut=[results.rate_hz]';delays=[results.delay_seconds]'*1e6;
nmse=zeros(numel(results),3);corr=nmse;phase=nmse;
for gg=1:numel(results)
 for bb=1:3,nmse(gg,bb)=results(gg).blocks(bb).nmse;corr(gg,bb)=results(gg).blocks(bb).real_coherence;phase(gg,bb)=results(gg).blocks(bb).phase_deg;end
end
tableOut=table(names,ratesOut,delays,nmse(:,1),nmse(:,2),nmse(:,3),corr(:,2),corr(:,3),phase(:,2),phase(:,3), ...
 [results.designRank]',[results.channelJacobianCondition]', ...
 'VariableNames',{'Candidate','RateHypothesisHz','DelayUs','TrainNmse','Test2Nmse','Test3Nmse','Test2RealCoherence','Test3RealCoherence','Test2PhaseDeg','Test3PhaseDeg','DesignRank','ChannelJacobianCondition'});
writetable(tableOut,fullfile(dest,'caf_candidate_validation.csv'));
report=summary;
end
function delays=coarseDelaySeeds(B,y,w,orders,nSets,N)
scale=sqrt(sum(w.*abs(B).^2,1));scale=max(scale,realmin);
Bs=B./scale;
G=real(Bs'*(w.*Bs));G=G+1e-7*trace(G)/9*eye(9);
cross=conj(Bs).*(w.*y);
cross=reshape(cross,numel(orders),nSets,9);cross=squeeze(sum(cross,2));
spectrum=complex(zeros(N,9));spectrum(orders+1,:)=cross;
rhs=real(ifft(spectrum,[],1)*N).';
theta=G\rhs;energy=sum(theta.*rhs,1);
[~,order]=sort(energy,'descend');delays=zeros(1,3);count=0;
for k=order
 candidate=k-1;
 if count==0||all(abs(mod(candidate-delays(1:count)+N/2,N)-N/2)>N/48)
  count=count+1;delays(count)=candidate;
  if count==3,break;end
 end
end
delays=delays(1:count);
end
function q=hermitianVector(H)
q=[real(diag(H));real(H(1,2));imag(H(1,2));real(H(1,3));imag(H(1,3));real(H(2,3));imag(H(2,3))];
end
function m=compare(pred,y,w)
inner=sum(w.*conj(y).*pred);den=sqrt(sum(w.*abs(y).^2)*sum(w.*abs(pred).^2));
m=struct('nmse',sum(w.*abs(y-pred).^2)/sum(w.*abs(y).^2), ...
 'real_coherence',real(inner)/max(den,realmin), ...
 'abs_coherence',abs(inner)/max(den,realmin),'phase_deg',angle(inner)*180/pi, ...
 'unweighted_nmse',sum(abs(y-pred).^2)/sum(abs(y).^2));
end
function s=jsonSafe(s)
s.h_real=real(s.h);s.h_imag=imag(s.h);s.H_real=real(s.H);s.H_imag=imag(s.H);
s.relative_channel_real=real(s.relativeChannel);s.relative_channel_imag=imag(s.relativeChannel);
s=rmfield(s,{'h','H','relativeChannel'});
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
