function report=fitDsiCafFir27(out)
%FITDSICAF FIR two-tap-per-lane audit with fixed codeword/rate/timing.
% Six virtual inputs are [lane0 tap0,lane1 tap0,lane2 tap0,
% lane0 tap1,lane1 tap1,lane2 tap1]. Taps are 0 and 1/Fs at complex baseband.
% A single rank-one PSD H=h*h' is shared by black/white classes.
% Text pixels from the known screenshot are used ONLY for forward validation.
arguments
    out (1,1) string
end
lab=string(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(lab,'signal_processing'));
fits=load(fullfile(out,'caf_channel_fits.mat'));
data=load(fullfile(out,'complex_caf.mat'),'fs','f0','fc','labels','rowFeatures');
screen=imread("C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png");
sourceRows=round(data.rowFeatures.source_coordinate(data.labels==3))+1;
pixels=uint8(255*(screen(sourceRows,:,1)>=128));
[patterns,~,whichPattern]=unique(pixels,'rows');
patternWeights=accumarray(whichPattern,1)/size(pixels,1);
selected=unique([fits.validWinner fits.matchedWinner fits.controlWinner],'stable');
controlNames=["valid","header-byte-permutation","header-bit-order-reversed","shuffled-sync-header","geometry"];
orders=fits.orders;lags=fits.lags;Nfeatures=numel(orders)*numel(lags);
ov=repmat(orders,2*numel(lags),1);
deposition=repmat(sinc(orders/1100).^2,2*numel(lags),1);
target=fits.target(:,:,1:2,1);target=target(:);
weights=fits.weights(:,:,1:2);weights=weights(:);
textWeights=fits.weights(:,:,3);textWeights=textWeights(:);
records=cell(1,numel(selected));allFits=cell(size(records));
textPredictions=cell(size(records));predictions=cell(size(records));
lambda=1e-3; % Fixed before observing this audit's fit or validation scores.
for ii=1:numel(selected)
    index=selected(ii);flat=fits.results(index);group=fits.groups(index);
    black=dsi3LanePowerModel27(group.black,flat.rate_hz,data.f0,8192);
    white=dsi3LanePowerModel27(group.white,flat.rate_hz,data.f0,8192);
    Bblack=firBasis(black,flat.emission_index,data.fs,data.fc,lags,orders);
    Bwhite=firBasis(white,flat.emission_index,data.fs,data.fc,lags,orders);
    B=[Bblack;Bwhite].*exp(-2i*pi*ov*flat.delay_phase).*deposition;
    hFlat=[flat.h;zeros(3,1)];
    referencePrediction=fits.predictions{index};
    embeddingError=norm(B*hermitianVector(hFlat*hFlat')-referencePrediction(:))/max(norm(referencePrediction(:)),realmin);
    assert(embeddingError<1e-10,'Flat channel embedding disagrees with prior prediction.');
    fit=fitSix(B,target,weights,hFlat,lambda);
    predictions{ii}=reshape(fit.prediction,numel(orders),numel(lags),2);
    blocks=cell(1,3);
    for bb=1:3
        y=fits.target(:,:,1:2,bb);blocks{bb}=compare(fit.prediction,y(:),weights);
    end
    % Predict known binary text without changing h, timing, bitrate or mode.
    if flat.family<=4
        mode="video";vc=flat.family-1;
    elseif flat.family==5
        mode="2C";vc=0;
    else
        mode="3C";vc=0;
    end
    textBasis=complex(zeros(Nfeatures,36));
    for pp=1:size(patterns,1)
        packet=buildDsiGrayPacketCaf27(patterns(pp,:),mode,vc,controlNames(flat.control+1));
        model=dsi3LanePowerModel27(packet,flat.rate_hz,data.f0,8192);
        textBasis=textBasis+patternWeights(pp)*firBasis(model,flat.emission_index,data.fs,data.fc,lags,orders);
    end
    textPhase=exp(-2i*pi*repmat(orders,numel(lags),1)*flat.delay_phase);
    textDeposit=repmat(sinc(orders/1100).^2,numel(lags),1);
    textPrediction=(textBasis*hermitianVector(fit.h*fit.h')).*textPhase.*textDeposit;
    textPredictions{ii}=reshape(textPrediction,numel(orders),numel(lags));
    textBlocks=cell(1,3);
    for bb=1:3
        y=fits.target(:,:,3,bb);textBlocks{bb}=compare(textPrediction,y(:),textWeights);
    end
    record=rmfield(fit,{'h','H','prediction'});
    record.h_real=real(fit.h);record.h_imag=imag(fit.h);
    record.flat_embedding_relative_error=embeddingError;
    record.name=flat.name;record.group_index=index;record.rate_hz=flat.rate_hz;
    record.emission=flat.emission;record.delay_phase=flat.delay_phase;
    record.black_white_blocks=[blocks{:}];record.text_blocks=[textBlocks{:}];
    record.flat_black_white_nmse=[flat.blocks.nmse];
    record.black_white_channel_shared=true;record.text_used_to_fit_channel=false;
    record.timing_rate_mode_refitted=false;record.physical_channel_identified=false;
    records{ii}=record;allFits{ii}=fit;
    fprintf('FIR %s: BW test NMSE %.4f %.4f; text %.4f %.4f.\n', ...
        flat.name,blocks{2}.nmse,blocks{3}.nmse,textBlocks{2}.nmse,textBlocks{3}.nmse);
end
report=struct('status','complete','tap_delays_seconds',[0 1/data.fs], ...
    'virtual_input_order',["lane0 tap0","lane1 tap0","lane2 tap0","lane0 tap1","lane1 tap1","lane2 tap1"], ...
    'rank_one_complex_channel_dimension',6,'global_phase_fixed_real_dof',11, ...
    'regularization_lambda',lambda, ...
    'regularization_definition','Objective NMSE + lambda*normalized_tap1_energy; normalization is fixed from embedded flat-channel energy, not fitted from validation.', ...
    'selection','Only flat-model valid, same-family control and control-bank winners; no new codeword/rate/timing search.', ...
    'reference_text_scope','Binary screenshot rows predict text CAF only; no screenshot pixels render any reconstruction.', ...
    'unique_binary_text_rows',size(patterns,1),'candidates',[records{:}], ...
    'channel_fits_conditional',true,'packet_decoded',false,'iq_orientation','Inherited I-jQ hypothesis');
writeJson(fullfile(out,'caf_fir_audit.json'),report);
save(fullfile(out,'caf_fir_audit.mat'),'report','allFits','selected','predictions','textPredictions','patternWeights','-v7.3');
makeFigure(out,report,fits,selected);
end

function B=firBasis(model,emissionIndex,fs,fc,lags,orders)
c=model.coefficients{emissionIndex};
delayed=c.*exp(-2i*pi*(model.frequencyHz-fc)/fs);
c=[c delayed];K=6;n=size(c,1);
B=complex(zeros(numel(orders)*numel(lags),K^2));
for dd=1:numel(lags)
    tau=lags(dd)/fs;
    for hh=1:numel(orders)
        order=orders(hh);lo=max(1,1-order);hi=min(n,n-order);
        if lo>hi,continue;end
        lower=(lo:hi)';upper=lower+order;
        phasor=exp(2i*pi*((model.harmonics(lower)+order/2)*model.f0Hz-fc)*tau);
        A=c(upper,:).'*(conj(c(lower,:)).*phasor);
        row=hh+(dd-1)*numel(orders);
        B(row,1:K)=diag(A).';
        col=K+1;
        for a=1:K-1
            for b=a+1:K
                B(row,col)=A(a,b)+A(b,a);
                B(row,col+1)=1i*(A(a,b)-A(b,a));
                col=col+2;
            end
        end
    end
end
end

function fit=fitSix(B,y,w,flatChannel,lambda)
rootW=sqrt(w);bScale=norm(B.*rootW,'fro')/sqrt(numel(B));
yScale=norm(y.*rootW)/sqrt(numel(y));
Bs=B/bScale;ys=y/yScale;
Bw=Bs.*rootW;yw=ys.*rootW;
G=real(Bw'*Bw);cross=real(Bw'*yw);den=sum(abs(yw).^2);
A=[real(Bw);imag(Bw)];
singular=svd(A,'econ');
gramRidge=G+1e-8*trace(G)/36*eye(36);
relaxed=gramRidge\cross;
H=hermitianMatrix(relaxed,6);H=(H+H')/2;
[V,D]=eig(H);[~,ix]=max(real(diag(D)));
physicalScale=sqrt(yScale/bScale);
flat=flatChannel/physicalScale;
referenceEnergy=max(sum(abs(flat).^2),eps);
seeds=[flat,V(:,ix),ones(6,1)/sqrt(6)];
for ss=2:3
    direction=seeds(:,ss)/max(norm(seeds(:,ss)),realmin);
    q=hermitianVector(direction*direction');
    gain=max(0,(q'*cross)/max(q'*G*q,realmin));
    seeds(:,ss)=direction*sqrt(max(gain,eps));
end
bestObjective=Inf;best=zeros(6,1);startObjective=zeros(3,1);finalObjective=startObjective;
exitFlags=zeros(3,1);iterations=zeros(3,1);
settings=optimset('Display','off','MaxIter',1200,'MaxFunEvals',12000, ...
    'TolX',1e-7,'TolFun',1e-9);
for ss=1:3
    seed=seeds(:,ss);[~,ref]=max(abs(seed));seed=fixPhase(seed,ref);
    p=pack(seed,ref);
    objective=@(v) quadraticLoss(v,ref,G,cross,den,lambda,referenceEnergy);
    startObjective(ss)=objective(p);
    [p,value,flag,stats]=fminsearch(objective,p,settings);
    finalObjective(ss)=value;exitFlags(ss)=flag;iterations(ss)=stats.iterations;
    if value<bestObjective,bestObjective=value;best=unpack(p,ref);end
end
[~,ref]=max(abs(best));best=fixPhase(best,ref);
h=best*physicalScale;prediction=B*hermitianVector(h*h');
nmse=sum(w.*abs(y-prediction).^2)/sum(w.*abs(y).^2);
penalty=lambda*sum(abs(best(4:6)).^2)/referenceEnergy;
% Synthetic consistency check: quadratic NMSE equals direct complex residual.
q=hermitianVector(best*best');
quadraticNmse=(q'*G*q-2*q'*cross+den)/den;
assert(abs(quadraticNmse-nmse)<1e-8*(1+nmse),'Quadratic loss mismatch.');
directions=complex(zeros(6,11));directions(ref,1)=1;
others=setdiff(1:6,ref,'stable');kk=2;
for a=others
    directions(a,kk)=1;directions(a,kk+1)=1i;kk=kk+2;
end
J=complex(zeros(size(B,1),11));
for jj=1:11
    dh=directions(:,jj);J(:,jj)=Bw*hermitianVector(dh*best'+best*dh');
end
js=svd([real(J);imag(J)],'econ');
[rankB,condB]=rankCond(singular,size(A,1),36);
[rankJ,condJ]=rankCond(js,2*size(J,1),11);
fit=struct('h',h,'H',h*h','prediction',prediction, ...
    'nmse_training',nmse,'regularization_penalty',penalty,'penalized_objective',bestObjective, ...
    'quadratic_direct_nmse_absolute_error',abs(quadraticNmse-nmse), ...
    'tap0_amplitude',abs(h(1:3)),'tap1_amplitude',abs(h(4:6)), ...
    'relative_amplitude',abs(h)/max(abs(h(ref)),realmin), ...
    'relative_phase_deg',angle(h)*180/pi,'global_phase_reference_virtual_input',ref, ...
    'global_phase_identifiable',false,'start_objective',startObjective, ...
    'final_objective',finalObjective,'exit_flags',exitFlags,'iterations',iterations, ...
    'design_rank',rankB,'design_condition',condB,'design_singular_values',singular, ...
    'channel_jacobian_rank',rankJ,'channel_jacobian_condition',condJ, ...
    'channel_jacobian_singular_values',js, ...
    'flat_seed_energy_scaled',referenceEnergy,'channel_physical_scale',physicalScale);
end

function loss=quadraticLoss(p,ref,G,b,den,lambda,referenceEnergy)
if any(~isfinite(p)),loss=realmax('double')/100;return;end
h=unpack(p,ref);q=hermitianVector(h*h');
residual=(q'*G*q-2*q'*b+den)/den;
loss=max(0,residual)+lambda*sum(abs(h(4:6)).^2)/referenceEnergy;
if ~isfinite(loss),loss=realmax('double')/100;end
end

function q=hermitianVector(H)
K=size(H,1);q=zeros(K^2,1);q(1:K)=real(diag(H));col=K+1;
for a=1:K-1
    for b=a+1:K
        q(col)=real(H(a,b));q(col+1)=imag(H(a,b));col=col+2;
    end
end
end
function H=hermitianMatrix(q,K)
H=diag(q(1:K));col=K+1;
for a=1:K-1
    for b=a+1:K
        H(a,b)=q(col)+1i*q(col+1);H(b,a)=conj(H(a,b));col=col+2;
    end
end
end
function h=fixPhase(h,ref)
if abs(h(ref))>0,h=h*exp(-1i*angle(h(ref)));end
h(ref)=real(h(ref));
end
function p=pack(h,ref)
other=setdiff(1:numel(h),ref,'stable');p=zeros(2*numel(h)-1,1);p(1)=real(h(ref));k=2;
for a=other,p(k)=real(h(a));p(k+1)=imag(h(a));k=k+2;end
end
function h=unpack(p,ref)
K=(numel(p)+1)/2;h=complex(zeros(K,1));h(ref)=p(1);k=2;
for a=setdiff(1:K,ref,'stable'),h(a)=p(k)+1i*p(k+1);k=k+2;end
end
function [r,c]=rankCond(s,n,m)
r=sum(s>max(n,m)*eps(max(s(1),realmin)));
if r<m,c=Inf;else,c=s(1)/max(s(end),realmin);end
end
function m=compare(pred,y,w)
den=sqrt(sum(w.*abs(y).^2)*sum(w.*abs(pred).^2));
coherence=sum(w.*conj(y).*pred)/max(den,realmin);
m=struct('nmse',sum(w.*abs(y-pred).^2)/sum(w.*abs(y).^2), ...
 'real_coherence',real(coherence),'abs_coherence',abs(coherence),'phase_deg',angle(coherence)*180/pi);
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end

function makeFigure(out,report,fits,selected)
f=figure('Name','Two-tap lane channel audit','Color','w','Position',[100 60 1350 850]);
tl=tiledlayout(f,2,2,'TileSpacing','compact');n=numel(selected);
flat=zeros(n,2);fir=flat;textNmse=flat;names=strings(1,n);
for ii=1:n
    r=report.candidates(ii);flat(ii,:)=[fits.results(selected(ii)).blocks(2:3).nmse];
    fir(ii,:)=[r.black_white_blocks(2:3).nmse];textNmse(ii,:)=[r.text_blocks(2:3).nmse];
    names(ii)=erase(r.name,["header-","-vc0"]);
end
ax=nexttile(tl);bar(ax,[mean(flat,2),mean(fir,2)]);ylabel(ax,'Mean B2/B3 weighted complex NMSE');
xticks(ax,1:n);xticklabels(ax,names);xtickangle(ax,12);legend(ax,'Flat 3-gain','2 taps per lane');
title(ax,'Black/white validation; timing/rate/codeword fixed');grid(ax,'on');
ax=nexttile(tl);bar(ax,textNmse);yline(ax,1,'--','Zero predictor','HandleVisibility','off');
xticks(ax,1:n);xticklabels(ax,names);xtickangle(ax,12);ylabel(ax,'Known-text forward prediction NMSE');
legend(ax,'B2','B3');title(ax,'Text never fitted; lower is better');grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');
for ii=1:n,plot(ax,0:5,report.candidates(ii).relative_amplitude,'-o','DisplayName',names(ii));end
xticks(ax,0:5);xticklabels(ax,{'L0 t0','L1 t0','L2 t0','L0 t1','L1 t1','L2 t1'});
ylabel(ax,'Amplitude / strongest virtual channel');title(ax,'Conditional two-tap channels');grid(ax,'on');legend(ax,'Interpreter','none');
ax=nexttile(tl);axis(ax,'off');lines=strings(n+5,1);
lines(1)="Two taps per lane at 0 and 1/Fs.";
lines(2)="Rank-one PSD, 11 real channel degrees of freedom.";
lines(3)="Fixed lambda = 0.001; no test-set tuning.";
lines(4)="Channel, bitrate and delay stay frozen in validation.";
lines(5)="Conditional fit does not establish physical lane channels.";
for ii=1:n,lines(ii+5)=sprintf('%s: J rank %d, cond %.2g',names(ii), ...
    report.candidates(ii).channel_jacobian_rank,report.candidates(ii).channel_jacobian_condition);end
text(ax,0,1,lines,'VerticalAlignment','top','Interpreter','none','FontSize',10);
exportgraphics(f,fullfile(out,'08_two_tap_channel_audit.png'),'Resolution',140);
savefig(f,fullfile(out,'08_two_tap_channel_audit.fig'));
end
