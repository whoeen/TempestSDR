function audit=auditIphoneCaf27(out)
%AUDITIPHONECAF27 Numerical, power-only channel, and phase drift diagnostics.
arguments
 out (1,1) string
end
fits=load(fullfile(out,'caf_channel_fits.mat'));
data=load(fullfile(out,'complex_caf.mat'),'fs','f0','fc','profiles');
book=buildDsi3LaneCodebook27();
model=dsi3LanePowerModel27(book.videoWhite(1),1365e6,data.f0,32768);
[B,~]=dsiCafBasis27(model,1,data.fs,data.fc,[1;4;16],(1:8)');
known=[1;.6*exp(.7i);.4*exp(-.9i)];H=known*known';q=hv(H);
direct=zeros(8,3);ds=[1 4 16];
for jj=1:3
 tau=ds(jj)/data.fs;cp=zeros(32768,1);cm=cp;
 cp(model.harmonics+1)=(model.coefficients{1}*known).*exp(1i*pi*model.frequencyHz*tau);
 cm(model.harmonics+1)=(model.coefficients{1}*known).*exp(-1i*pi*model.frequencyHz*tau);
 r=(ifft(cp)*32768).*conj(ifft(cm)*32768)*exp(-2i*pi*data.fc*tau);
 c=fft(r)/32768;direct(:,jj)=c(2:9);
end
basisError=norm(direct(:)-B*q)/norm(direct(:));
fit=fitDsiCafChannel27(B,B*q,ones(size(B,1),1));
assert(basisError<1e-10 && fit.complexResidualNmse<1e-10);
knownRelative=known/known(1);
channelError=norm(fit.relativeChannel-knownRelative)/norm(knownRelative);
% Conditional comparison: same selected codeword/rate/delay; estimate h from
% lag0 only, then predict the held-out nonzero-lag CAF without further fitting.
win=fits.results(fits.validWinner);group=fits.groups(fits.validWinner);
orders=fits.orders;F=exp(-2i*pi*orders*(0:1099)/1100)/1100;
mB=dsi3LanePowerModel27(group.black,win.rate_hz,data.f0,8192);
mW=dsi3LanePowerModel27(group.white,win.rate_hz,data.f0,8192);
BP=[dsiCafBasis27(mB,win.emission_index,data.fs,data.fc,0,orders); ...
 dsiCafBasis27(mW,win.emission_index,data.fs,data.fc,0,orders)];
ov=repmat(orders,2,1);BP=BP.*exp(-2i*pi*ov*win.delay_phase).*repmat(sinc(orders/1100).^2,2,1);
yp=[F*data.profiles(:,1,1,1);F*data.profiles(:,1,2,1)];
powerFit=fitDsiCafChannel27(BP,yp,ones(size(yp)),struct('maxStarts',5,'maxIterations',600));
BN=[dsiCafBasis27(mB,win.emission_index,data.fs,data.fc,fits.lags,orders); ...
 dsiCafBasis27(mW,win.emission_index,data.fs,data.fc,fits.lags,orders)];
ov=repmat(orders,2*numel(fits.lags),1);
BN=BN.*exp(-2i*pi*ov*win.delay_phase).*repmat(sinc(orders/1100).^2,2*numel(fits.lags),1);
prediction=BN*hv(powerFit.H);w=fits.weights(:,:,1:2);w=w(:);
comparison=zeros(3,2);
for bb=1:3
 y=fits.target(:,:,1:2,bb);y=y(:);
 comparison(bb,1)=sum(w.*abs(y-prediction).^2)/sum(w.*abs(y).^2);
 comparison(bb,2)=win.blocks(bb).nmse;
end
% Relative between-block phase model. Diagnostic only; NOT applied to scores,
% images or fitted hardware channels. Does not measure absolute RF phase.
alpha=repmat(orders*data.f0,numel(fits.lags)*2,1);
tau=repmat(repelem(fits.lags/data.fs,numel(orders)),2,1);
reference=fits.target(:,:,1:2,1);reference=reference(:);
phaseDiagnostics=cell(2,1);
for bb=2:3
 current=fits.target(:,:,1:2,bb);current=current(:);
 objective=@(v) phaseLoss(v,reference,current,w,alpha,tau);
 [v,loss]=fminsearch(objective,[0 0],optimset('Display','off','MaxIter',500,'TolX',1e-8));
 phaseDiagnostics{bb-1}=struct('block',bb,'relative_timing_ns',v(1), ...
  'relative_frequency_offset_hz',v(2)*1e3,'normalized_residual',loss, ...
  'scope','Joint timing/CFO-shaped diagnostic relative to B1; not applied; model mismatch can bias.', ...
  'applied',false);
end
audit=struct('direct_time_vs_fourier_caf_relative_error',basisError, ...
 'synthetic_rank1_channel_fit_nmse',fit.complexResidualNmse, ...
 'synthetic_relative_channel_error',channelError, ...
 'power_only_channel_conditional_comparison_nmse',comparison, ...
 'comparison_columns',["lag0-fitted h predicts nonzero lags","nonzero-lag-fitted h"], ...
 'comparison_scope','Same codeword, rate, delay selected by CAF; only h training statistic differs, not independent model selection.', ...
 'between_block_phase_diagnostics',[phaseDiagnostics{:}], ...
 'absolute_rf_phase_identifiable',false,'relative_cfo_correction_applied',false);
fid=fopen(fullfile(out,'caf_numerical_audit.json'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(audit,'PrettyPrint',true),'char');
save(fullfile(out,'caf_numerical_audit.mat'),'audit','powerFit','prediction','fit');
disp(audit);
end
function q=hv(H)
q=[real(diag(H));real(H(1,2));imag(H(1,2));real(H(1,3));imag(H(1,3));real(H(2,3));imag(H(2,3))];
end
function loss=phaseLoss(v,reference,current,w,alpha,tau)
prediction=reference.*exp(-2i*pi*alpha*v(1)*1e-9+2i*pi*tau*v(2)*1e3);
gain=max(0,real(sum(w.*conj(prediction).*current))/sum(w.*abs(prediction).^2));
loss=sum(w.*abs(current-gain*prediction).^2)/sum(w.*abs(current).^2);
end
