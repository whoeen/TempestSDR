function audit = auditDsiCodebook27(outputDirectory)
%AUDITDSICODEBOOK27 Independent Fourier/sampling checks for protocol run.
arguments
 outputDirectory (1,1) string
end
data=load(fullfile(outputDirectory,'candidate_results.mat'));
native=load(fullfile(outputDirectory,'native_fold.mat'),'fs','f0','bins','starts','numberSamples');
book=data.book; f0=native.f0;
model=dsi3LanePowerModel27(book.dcs(1),800e6,f0,32768);
idx=[1 100 500 1000]; f=model.frequencyHz(idx);
levels=(2*double(book.dcs(1).hsBits)-1).*book.dcs(1).hsValid;
time=((0:size(levels,1)-1)+0.5)/800e6;
independent=(exp(-2i*pi*f*time)*levels).* ...
    (sinc(f/800e6)*f0/800e6).*model.bandWeights(idx);
rectangleError=norm(independent-model.coefficients{1}(idx,:),'fro')/norm(independent,'fro');
assert(rectangleError<1e-10,'Analytic edge integral disagrees with NRZ rectangle integral.');
derivativeError=norm(model.coefficients{2}-model.coefficients{1}.*(1i*model.frequencyHz/100e6),'fro')/norm(model.coefficients{2},'fro');
assert(derivativeError<1e-12);
reference=dsi3LanePowerModel27(book.dcs(1),1365e6,f0,32768);
swapped=dsi3LanePowerModel27(book.matchedControls(25),1365e6,f0,32768);
degeneracy=zeros(1,3);
for ee=1:3
 a=sum(reference.waveforms{ee},2);b=sum(swapped.waveforms{ee},2);
 degeneracy(ee)=norm(a-b)/norm(a);
end
% Timestamp-derived histogram, independently rebuilt with 64 subphase bins.
N=native.bins;Q=64;histogram=zeros(N,Q,3);
for bb=1:3
 for start=0:2^20:native.numberSamples-1
  take=min(2^20,native.numberSamples-start);
  phase=mod((native.starts(bb)+start+(0:take-1)')*(f0/native.fs),1)*N;
  bin=floor(phase)+1;
  sub=min(Q,floor(mod(phase,1)*Q)+1);
  histogram(:,:,bb)=histogram(:,:,bb)+accumarray([bin sub],1,[N Q]);
 end
 histogram(:,:,bb)=histogram(:,:,bb)./sum(histogram(:,:,bb),2);
end
packets=[book.videoWhite book.videoBlack book.dcs book.matchedControls book.geometryControls];
winners=[data.validWinner,data.controlWinner];
checks=cell(1,2);predictions=cell(1,2);
for ii=1:2
 pp=winners(ii);v=data.validation(pp);
 model=dsi3LanePowerModel27(packets(pp),v.rate_hz,f0,32768);
 ee=find(model.emissionNames==v.emission);wave=model.waveforms{ee};
 phase=mod(((0:N-1)'+((0:Q-1)+.5)/Q-v.lag_bins)/N,1);
 z=zeros(N,Q,3);
 for lane=1:3
  z(:,:,lane)=reshape(interp1([model.phaseGrid;1],[wave(:,lane);wave(1,lane)], ...
      phase(:),'pchip'),N,Q);
 end
 if v.coupling=="equal_coherent",power=abs(sum(z,3)).^2;else,power=sum(abs(z).^2,3);end
 prediction=zeros(N,3);correlations=zeros(1,3);centeredError=zeros(1,3);
 for bb=1:3
  prediction(:,bb)=v.offset+v.gain*sum(power.*histogram(:,:,bb),2)*1e6;
  correlations(bb)=corrLocal(prediction(:,bb),data.y(:,bb));
  centeredError(bb)=norm(prediction(:,bb)-v.prediction(:,bb))/ ...
      norm(v.prediction(:,bb)-mean(v.prediction(:,bb)));
 end
 checks{ii}=struct('label',v.label,'grid_size',32768,'subphase_bins',Q, ...
     'interpolator','pchip on complex RF before power','refitted_parameters',false, ...
     'correlation',correlations,'change_rms_over_original_centered_prediction_rms',centeredError);
 predictions{ii}=prediction;
end
audit=struct('nrZ_rectangle_integral_relative_error',rectangleError, ...
 'derivative_relative_error',derivativeError, ...
 'dcs2C_header_byte_swap_equal_coherent_waveform_relative_error',degeneracy, ...
 'degeneracy_meaning','In this coupling hypothesis, distinct valid/invalid headers can have identical received waveforms.', ...
 'fine_sampling_checks',[checks{:}],'test_ranking_reversed',false, ...
 'measurement_ecc_crc_decoded',false);
audit.test_ranking_reversed=any(checks{1}.correlation(2:3)>checks{2}.correlation(2:3));
fid=fopen(fullfile(outputDirectory,'numerical_audit.json'),'w','n','UTF-8');
clean=onCleanup(@()fclose(fid));fwrite(fid,jsonencode(audit,'PrettyPrint',true),'char');
V=data.validation;labels=string({V.label})';rates=[V.rate_hz]';lag=[V.lag_bins]';
corr=vertcat(V.correlation);r2=vertcat(V.r_squared);coarse=[V.coarse_train_correlation]';
summary=table(labels,rates,lag,coarse,corr(:,1),corr(:,2),corr(:,3),r2(:,2),r2(:,3), ...
 'VariableNames',{'Candidate','RateHypothesisHz','DelayBins','CoarseTrainCorr','RefinedTrainCorr','Test2Corr','Test3Corr','Test2R2','Test3R2'});
writetable(summary,fullfile(outputDirectory,'candidate_validation.csv'));
% Show the cyclic harmonics of measured and predicted POWER, not RF phase.
f=figure('Name','Cyclic power harmonics and codebook identifiability','Color','w','Position',[90 70 1400 850]);
tl=tiledlayout(f,2,2,'TileSpacing','compact');h=(1:24)';time=(0:N-1)'/N;
signals=[data.y(:,2),predictions{1}(:,2),predictions{2}(:,2),data.gatePrediction];
coef=exp(-2i*pi*h*time.')*signals/N;
ax=nexttile(tl);semilogy(ax,h*f0/1e6,abs(coef),'-o','MarkerSize',3);
xlabel(ax,'Cyclic frequency alpha = h f_0 (MHz)');ylabel(ax,'|Power Fourier coefficient|');
title(ax,'Measured power harmonics versus protocol/gate models');grid(ax,'on');
legend(ax,'Measured B2','Protocol','Wrong codeword','Modulo gate');
ax=nexttile(tl);hold(ax,'on');
for jj=2:4
 phase=angle(coef(:,jj).*conj(coef(:,1)))*180/pi;
 phase(abs(coef(:,1))<.01|abs(coef(:,jj))<.01)=NaN;
 plot(ax,h,phase,'-o','MarkerSize',3);
end
xlabel(ax,'Harmonic order h');ylabel(ax,'Power-harmonic phase residual (degrees)');
title(ax,'Timing-related cyclic phase; not carrier phase');grid(ax,'on');
legend(ax,'Protocol minus measured','Control minus measured','Gate minus measured');
ax=nexttile(tl);t=model.phaseGrid/f0*1e9;
plot(ax,t,real(sum(reference.waveforms{1},2)),t,real(sum(swapped.waveforms{1},2)),'--');
xlim(ax,[0 60]);xlabel(ax,'Time after assumed SoT start (ns)');ylabel(ax,'Synthetic RF, arbitrary units');
title(ax,'Different header bytes, same equal-coupled RF waveform');
legend(ax,'DCS 2C white','DI/WC-low swapped');grid(ax,'on');
ax=nexttile(tl);axis(ax,'off');
text(ax,0,1,{ ...
 'g(t) = 1{ mod(t-tau,T) < D T }', ...
 'x(t) = g(t) s(t), with stationary s(t)', ...
 'R_x(t,lag) = g(t+lag/2) g*(t-lag/2) R_s(lag)', ...
 'alpha = h/T: cyclic harmonics of periodic statistics', ...
 '', ...
 'WSS alone has no nonzero-alpha second-order components.', ...
 'g is a gate; R_x is a correlation; G(k) is a matching score.', ...
 'Cyclic power is only the lag=0 slice.', ...
 'A periodic power match does not uniquely identify packet bits.'}, ...
 'VerticalAlignment','top','FontSize',12,'Interpreter','none');
exportgraphics(f,fullfile(outputDirectory,'05_cyclic_harmonics_and_ambiguity.png'),'Resolution',140);
savefig(f,fullfile(outputDirectory,'05_cyclic_harmonics_and_ambiguity.fig'));
save(fullfile(outputDirectory,'numerical_audit.mat'),'audit','coef','h','predictions','summary');
disp(audit);
end
function r=corrLocal(a,b)
 a=a(:)-mean(a);b=b(:)-mean(b);r=real(a'*b)/(norm(a)*norm(b));
end
