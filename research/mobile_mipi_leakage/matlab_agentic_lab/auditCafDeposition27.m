function audit = auditCafDeposition27(outputDirectory)
%AUDITCAFDEPOSITION27 Replay the actual sampling/deposition operator on models.
% Selected protocol and matched-control fits remain FIXED. Reconstruct the full
% positive-RF waveform, form its complex lag product before sample deposition,
% and therefore retain high lag-product harmonics that may alias into low CAF.
% B1 native timestamps and frozen class masks are used; raw IQ is not reread.
% 32/64 subphase comparison is empirical convergence, not a rigorous error bound.
arguments
    outputDirectory (1,1) string
end
lab=string(fileparts(mfilename('fullpath')));
addpath(fullfile(lab,'signal_processing'));
data=load(fullfile(outputDirectory,'complex_caf.mat'),'metadata','labels','fs','fc','f0');
fits=load(fullfile(outputDirectory,'caf_channel_fits.mat'),'results','groups','target', ...
    'weights','validWinner','matchedWinner','lags','orders');
N=data.metadata.phase_bins;Q=64;lags=[1;4;16];orders=(1:128)';
reads=data.metadata.block_reads;
if iscell(reads),read=reads{1};else,read=reads(1);end
firstSample=read.first_sample_zero_based;numberSamples=read.samples;
labels=double(data.labels);frameRows=numel(labels);
lo=cell(numel(lags),1);hi=lo;
for dd=1:numel(lags)
    lo{dd}=zeros(N,Q,2);hi{dd}=zeros(N,Q,2);
end
% Exact lo/hi weights are accumulated, rather than replacing them by subnode
% center weights. Only the model value inside each subnode is approximated.
for done=0:2^20:numberSamples-1
    take=min(2^20,numberSamples-done);
    n=firstSample+done+(0:take-1)';
    rowA=floor(n*data.f0/data.fs);
    classA=labels(mod(rowA,frameRows)+1);
    for dd=1:numel(lags)
        d=lags(dd);
        midpoint=(n+d/2)*data.f0/data.fs;
        phase=mod(midpoint,1)*N;
        bin=floor(phase)+1;fraction=mod(phase,1);
        row=floor(midpoint);rowB=floor((n+d)*data.f0/data.fs);
        cls=labels(mod(row,frameRows)+1);
        classB=labels(mod(rowB,frameRows)+1);
        valid=(cls==1|cls==2)&cls==classA&cls==classB;
        sub=min(Q,floor(fraction(valid)*Q)+1);
        index=bin(valid)+(sub-1)*N+(cls(valid)-1)*N*Q;
        low=accumarray(index,1-fraction(valid),[N*Q*2 1]);
        high=accumarray(index,fraction(valid),[N*Q*2 1]);
        lo{dd}=lo{dd}+reshape(low,N,Q,2);
        hi{dd}=hi{dd}+reshape(high,N,Q,2);
    end
end
F=exp(-2i*pi*orders*(0:N-1)/N)/N;
selected=[fits.validWinner fits.matchedWinner];
records=cell(2,1);predictions=cell(2,1);details=zeros(0,8);
grid=32768;
for which=1:2
    groupIndex=selected(which);fit=fits.results(groupIndex);
    group=fits.groups(groupIndex);
    packets=[group.black group.white];
    prediction64=complex(zeros(numel(orders),numel(lags),2));
    prediction32=prediction64;approximate=prediction64;
    zeroCount=zeros(numel(lags),2);
    for cls=1:2
        model=dsi3LanePowerModel27(packets(cls),fit.rate_hz,data.f0,grid);
        wave=model.waveforms{fit.emission_index}*fit.h;
        [B,meta]=dsiCafBasis27(model,fit.emission_index,data.fs,data.fc,lags,orders);
        delayed=B.*exp(-2i*pi*meta.alphaHz*fit.delay_seconds);
        q=hermitianVector(fit.H);
        approximate(:,:,cls)=reshape(delayed*q,numel(orders),numel(lags)).*sinc(orders/N).^2;
        for dd=1:numel(lags)
            d=lags(dd);
            low=lo{dd}(:,:,cls);high=hi{dd}(:,:,cls);
            [profile,zeroCount(dd,cls)]=replayProfile(wave,model.phaseGrid,low,high, ...
                fit.delay_phase,d,data.fs,data.fc,data.f0,N);
            prediction64(:,dd,cls)=F*profile;
            low32=reshape(sum(reshape(low,N,2,Q/2),2),N,Q/2);
            high32=reshape(sum(reshape(high,N,2,Q/2),2),N,Q/2);
            profile32=replayProfile(wave,model.phaseGrid,low32,high32, ...
                fit.delay_phase,d,data.fs,data.fc,data.f0,N);
            prediction32(:,dd,cls)=F*profile32;
            p64=prediction64(:,dd,cls);p32=prediction32(:,dd,cls);
            pa=approximate(:,dd,cls);
            lagIndex=find(fits.lags==d,1);
            target=fits.target(:,lagIndex,cls,1);weights=fits.weights(:,lagIndex,cls);
            details(end+1,:)=[which cls d,relativeError(pa,p64),relativeError(p32,p64), ...
                nmse(pa,target,weights),nmse(p64,target,weights),zeroCount(dd,cls)]; %#ok<AGROW>
        end
    end
    lagIndices=arrayfun(@(d)find(fits.lags==d,1),lags);
    target=fits.target(:,lagIndices,1:2,1);
    weights=fits.weights(:,lagIndices,1:2);
    records{which}=struct('candidate',fit.name,'group_index',groupIndex, ...
        'rate_hypothesis_hz',fit.rate_hz,'channel_delay_refitted',false, ...
        'approximation_vs_replay64_relative_error',relativeError(approximate,prediction64), ...
        'approximation_vs_replay64_weighted_relative_error',weightedRelativeError(approximate,prediction64,weights), ...
        'subphase32_vs64_relative_error',relativeError(prediction32,prediction64), ...
        'subphase32_vs64_weighted_relative_error',weightedRelativeError(prediction32,prediction64,weights), ...
        'training_weighted_nmse_sinc2',nmse(approximate,target,weights), ...
        'training_weighted_nmse_replay64',nmse(prediction64,target,weights), ...
        'training_weighted_nmse_replay32',nmse(prediction32,target,weights), ...
        'phase_bins_without_pairs',zeroCount);
    predictions{which}=struct('sinc2',approximate,'replay64',prediction64, ...
        'replay32',prediction32,'target',target,'weights',weights);
    fprintf('Deposition audit %s: model change %.5g; 32/64 %.5g; NMSE %.5f -> %.5f.\n', ...
        fit.name,records{which}.approximation_vs_replay64_relative_error, ...
        records{which}.subphase32_vs64_relative_error, ...
        records{which}.training_weighted_nmse_sinc2,records{which}.training_weighted_nmse_replay64);
end
audit=struct('status','complete','block',1,'lag_samples',lags,'harmonic_orders',orders, ...
    'native_fs_hz',data.fs,'f0_hz',data.f0,'phase_bins',N,'subphase_bins',[32 64], ...
    'rf_waveform_grid',grid,'raw_iq_reread',false,'fit_parameters_changed',false, ...
    'first_native_sample',firstSample,'native_sample_count',numberSamples, ...
    'subphase64_max_time_quantization_ns',1e9/(2*Q*N*data.f0), ...
    'operator',"Full RF lag product -> baseband lag phase -> actual B1 class endpoint mask -> exact linear lo/hi deposition weights -> per-node count normalization -> alpha1:128 FFT", ...
    'alias_handling',"Full complex RF waveform is evaluated before the lag product; high positive/negative lag-product harmonics and sampling aliases are retained.", ...
    'convergence_meaning',"32/64 difference is an empirical discretization diagnostic, not a strict total-error bound.", ...
    'scope',"Selected flat-channel black/white models only, B1 only, lag1/4/16; no model reselection or refit.", ...
    'candidates',[records{:}]);
tableOut=array2table(details,'VariableNames',{'SelectedCandidate','ClassBlack1White2','LagSamples', ...
    'Sinc2VsReplayRelativeError','Subphase32Vs64RelativeError','TrainingNmseSinc2','TrainingNmseReplay64','EmptyBins'});
writetable(tableOut,fullfile(outputDirectory,'caf_deposition_audit.csv'));
save(fullfile(outputDirectory,'caf_deposition_audit.mat'),'audit','predictions','details','lags','orders','-v7.3');
fid=fopen(fullfile(outputDirectory,'caf_deposition_audit.json'),'w','n','UTF-8');
assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(audit,'PrettyPrint',true),'char');
end

function [profile,emptyCount]=replayProfile(wave,grid,low,high,delay,d,fs,fc,f0,N)
Q=size(low,2);
phase=((0:N-1)'+((0:Q-1)+.5)/Q)/N;
plus=mod(phase-delay+d*f0/(2*fs),1);
minus=mod(phase-delay-d*f0/(2*fs),1);
zp=reshape(interp1([grid;1],[wave;wave(1)],plus(:),'pchip'),N,Q);
zm=reshape(interp1([grid;1],[wave;wave(1)],minus(:),'pchip'),N,Q);
product=zp.*conj(zm)*exp(-2i*pi*fc*d/fs);
numerator=sum(low.*product,2)+circshift(sum(high.*product,2),1);
denominator=sum(low,2)+circshift(sum(high,2),1);
emptyCount=sum(denominator==0);
profile=numerator./max(denominator,1);
end
function q=hermitianVector(H)
q=[real(diag(H));real(H(1,2));imag(H(1,2));real(H(1,3));imag(H(1,3));real(H(2,3));imag(H(2,3))];
end
function r=relativeError(a,b)
r=norm(a(:)-b(:))/max(norm(b(:)),realmin);
end
function r=weightedRelativeError(a,b,w)
r=sqrt(sum(w(:).*abs(a(:)-b(:)).^2)/max(sum(w(:).*abs(b(:)).^2),realmin));
end
function result=nmse(prediction,target,weights)
result=sum(weights(:).*abs(prediction(:)-target(:)).^2)/max(sum(weights(:).*abs(target(:)).^2),realmin);
end
