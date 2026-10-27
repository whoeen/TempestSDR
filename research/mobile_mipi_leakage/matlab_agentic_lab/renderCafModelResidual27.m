function summary=renderCafModelResidual27(out)
%RENDERCAFMODELRESIDUAL27 Frozen-channel cyclic-baseline subtraction images.
% This removes a modeled repeatable component; it is not RGB/byte decoding.
arguments
 out (1,1) string
end
data=load(fullfile(out,'complex_caf.mat'),'images','labels','rowMeta','fs','f0','fc');
fits=load(fullfile(out,'caf_channel_fits.mat'));
N=1100;R=1881;phase=((0:N-1)'+.5)/N;
rowIndex=mod(round(data.rowMeta.row_offset_zero_based+data.rowMeta.row_scale*(0:1333)),R)+1;
classes=data.labels; classForRemoval=ones(R,1)*2;classForRemoval(classes==1)=1;
% Text uses WHITE background model, never the screenshot's character pixels.
observed=(data.images{2}.caf1+data.images{3}.caf1)/2;
training=data.images{1}.caf1;
selected=[fits.validWinner fits.matchedWinner];
residual=cell(1,2);baseline=cell(1,2);records=cell(1,2);
empiricalDc=zeros(2,1);
for cls=1:2,empiricalDc(cls)=mean(training(classes==cls,:),'all');end
unmodeled=observed-empiricalDc(classForRemoval);
for kk=1:2
 id=selected(kk);fit=fits.results(id);group=fits.groups(id);
 profile=complex(zeros(2,N));
 for cls=1:2
  packet=group.black;if cls==2,packet=group.white;end
  model=dsi3LanePowerModel27(packet,fit.rate_hz,data.f0,32768);
  coeff=model.coefficients{fit.emission_index}*fit.h;
  tau=1/data.fs;
  plus=zeros(32768,1);minus=plus;
  plus(model.harmonics+1)=coeff.*exp(1i*pi*model.frequencyHz*tau);
  minus(model.harmonics+1)=coeff.*exp(-1i*pi*model.frequencyHz*tau);
  p=ifft(plus)*32768;m=ifft(minus)*32768;
  r=p.*conj(m)*exp(-2i*pi*data.fc*tau);
  shifted=mod(phase-fit.delay_phase,1);
  sampled=interp1([model.phaseGrid;1],[r;r(1)],shifted,'pchip');
  profile(cls,:)=sampled-mean(sampled);
 end
 baseline{kk}=profile(classForRemoval,:);
 residual{kk}=unmodeled-baseline{kk};
 white=classes==2;text=classes==3;
 beforeWhite=sqrt(mean(abs(unmodeled(white,:)).^2,'all'));
 afterWhite=sqrt(mean(abs(residual{kk}(white,:)).^2,'all'));
 records{kk}=struct('candidate',fit.name,'white_residual_rms_before',beforeWhite, ...
  'white_residual_rms_after',afterWhite,'white_residual_rms_ratio',afterWhite/beforeWhite, ...
  'text_residual_rms_after',sqrt(mean(abs(residual{kk}(text,:)).^2,'all')), ...
  'channel_refitted',false,'alpha0_model_used',false, ...
  'scope','Measured B2/B3 minus frozen modeled cyclic profile; empirical B1 state DC retained as separate baseline calibration.');
end
% Display limit derived only from B1 raw CAF after B1 DC, not from test images.
trainResidual=training-empiricalDc(classForRemoval);
trainingView=abs(trainResidual(rowIndex,:));limit=prctile(trainingView(:),99);
limit=max(limit,eps);
f=figure('Name','Frozen channel model residual images','Color','w','Position',[80 60 1450 950]);
tl=tiledlayout(f,1,3,'TileSpacing','compact');
views={unmodeled,residual{1},residual{2}};
titles={'Measured CAF: B1 state DC removed','Valid codeword channel: cyclic profile removed','Wrong codeword channel: cyclic profile removed'};
time=phase/data.f0*1e6;
for k=1:3
 ax=nexttile(tl);imagesc(ax,time,0:1333,abs(views{k}(rowIndex,:)));
 clim(ax,[0 limit]);colormap(ax,'gray');colorbar(ax);
 xlabel(ax,'Within-row time (us)');ylabel(ax,'Reference-calibrated active row');
 title(ax,titles{k});
end
title(tl,'Same fixed B1 display scale; measured data only; no byte decoding');
exportgraphics(f,fullfile(out,'07_channel_model_residual_images.png'),'Resolution',140);
savefig(f,fullfile(out,'07_channel_model_residual_images.fig'));
a=abs(residual{1}(rowIndex,:));b=abs(residual{2}(rowIndex,:));
a=a(:)-mean(a,'all');b=b(:)-mean(b,'all');
summary=struct('candidates',[records{:}], ...
 'valid_wrong_residual_image_correlation',real(a'*b)/(norm(a)*norm(b)), ...
 'display_limit_training_only',limit,'byte_decoded',false, ...
 'text_background_model','White cyclic template; actual glyph pixels never inserted.');
fid=fopen(fullfile(out,'channel_residual_image_metrics.json'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(summary,'PrettyPrint',true),'char');
save(fullfile(out,'channel_residual_images.mat'),'summary','residual','baseline','unmodeled','rowIndex','phase','-v7.3');
end
