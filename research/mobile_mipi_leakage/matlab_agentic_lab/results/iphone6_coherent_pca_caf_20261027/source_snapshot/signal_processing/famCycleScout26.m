function out = famCycleScout26(x, fsHz, options)
%FAMCYCLESCOUT26 Memory-bounded NC/conjugate FAM cycle discovery.
% OUT = famCycleScout26(X,FS,OPTIONS) uses complete, uniformly sampled
% complex IQ blocks; it does not conjugate, subtract DC, resample or pad X.
% OPTIONS is a scalar struct. M=64, L=16, P=16384 by default; input must
% contain at least (P-1)*L+M samples. PL/M must be integer for the CDP grid.
%
% AlphaLimitsHz controls NC; ConjugateAlphaLimitsHz defaults to the same
% range. Use [-FS FS] for a full principal-domain search. Modes defaults to
% ["nc","conjugate"]. FrequencyLimitsHz limits signed BASEBAND frequencies.
% ProbePoints rows [mode, fHz, alphaHz], mode=1 NC or 2 conjugate, return
% nearest channel-pair/slow-FFT samples, including trivial NC alpha=0.
% Probes are evaluated independently of Modes and alpha search limits.
%
% ChannelWindow and SlowWindow accept "hamming", "hann", "rectangular", or
% nonnegative real vectors of lengths M and P. Hamming/Hann are symmetric.
% Returned coherence is a finite, smoothed CHANNEL-PAIR cyclic correlation;
% it is not an unbiased pointwise population spectral coherence estimate.
% PSD/SCF are two-sided input-units^2/Hz, without one-sided doubling.
% All cyclic phases refer to X(1) at time zero, not an invented shared epoch.
%
% Storage: O(M*P) channelizer plus one O(P) pair FFT, not an M*M*P cube.
% CDP is max over tested f, hence has search-selection bias; no FAP claim.
% References: Spooner FAM (2018), equations 1,3,6-10; Roberts et al. (1991),
% DOI 10.1109/79.81008. See knowledge/signal_processing/fam_20261026.
arguments
    x {mustBeNumeric, mustBeVector, mustBeFinite, mustBeNonempty}
    fsHz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
    options (1,1) struct = struct()
end
defaults = struct('M',64,'L',16,'P',16384, ...
    'AlphaLimitsHz',[0 500e3],'ConjugateAlphaLimitsHz',[], ...
    'FrequencyLimitsHz',[-fsHz/2 fsHz/2], ...
    'Modes',["nc","conjugate"],'TopCandidates',256,'TopPerPair',3, ...
    'PowerFloorRelativeDb',-60,'PowerFloorAbsolute',0, ...
    'ChannelWindow',"hamming",'SlowWindow',"rectangular", ...
    'ResidualHalfWidthBins',1,'ProbePoints',zeros(0,3), ...
    'HeatmapAlphaBins',512,'PeakSeparationBins',4, ...
    'ExcludeNcAlphaHz',0,'ChannelBatchSize',512);
names = fieldnames(options);
for ii = 1:numel(names)
    assert(isfield(defaults,names{ii}), 'famCycleScout26:UnknownOption', ...
        'Unknown option: %s',names{ii});
    defaults.(names{ii}) = options.(names{ii});
end
o = defaults;
if isempty(o.ConjugateAlphaLimitsHz)
    o.ConjugateAlphaLimitsHz = o.AlphaLimitsHz;
end
countNames = {'M','L','P','TopCandidates','TopPerPair','HeatmapAlphaBins', ...
    'PeakSeparationBins','ChannelBatchSize'};
for ii = 1:numel(countNames)
    validateattributes(o.(countNames{ii}),{'numeric'}, ...
        {'scalar','real','finite','integer','positive'},mfilename,countNames{ii});
    o.(countNames{ii}) = double(o.(countNames{ii}));
end
M=o.M; L=o.L; P=o.P; fsHz=double(fsHz);
assert(mod(M,2)==0 && M>=4 && L<=M/2 && P>=4, ...
    'famCycleScout26:Grid','Need even M>=4, L<=M/2, and P>=4.');
assert(mod(P*L,M)==0,'famCycleScout26:Grid', ...
    'P*L/M must be integer for an exact common alpha grid.');
validateattributes(o.ResidualHalfWidthBins,{'numeric'}, ...
    {'scalar','real','finite','positive','<=',1});
validateattributes(o.PowerFloorRelativeDb,{'numeric'}, ...
    {'scalar','real','finite'});
validateattributes(o.PowerFloorAbsolute,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(o.ExcludeNcAlphaHz,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
o.AlphaLimitsHz=checkLimits(o.AlphaLimitsHz,[-fsHz fsHz],'AlphaLimitsHz');
o.ConjugateAlphaLimitsHz=checkLimits(o.ConjugateAlphaLimitsHz, ...
    [-fsHz fsHz],'ConjugateAlphaLimitsHz');
o.FrequencyLimitsHz=checkLimits(o.FrequencyLimitsHz, ...
    [-fsHz/2 fsHz/2],'FrequencyLimitsHz');
o.Modes=string(o.Modes);
assert(all(ismember(o.Modes,["nc","conjugate"])) && ~isempty(o.Modes), ...
    'famCycleScout26:Modes','Modes must contain nc and/or conjugate.');
validateattributes(o.ProbePoints,{'numeric'},{'2d','real','finite'});
assert(size(o.ProbePoints,2)==3 && ...
    all(ismember(o.ProbePoints(:,1),[1 2])), ...
    'famCycleScout26:Probes','ProbePoints must be Q-by-3: [mode,f,alpha].');
availableSamples=numel(x);
need=(P-1)*L+M;
assert(numel(x)>=need,'famCycleScout26:Length', ...
    'Need %d samples, received %d. No zero padding is performed.',need,numel(x));
a=makeWindow(o.ChannelWindow,M); g=makeWindow(o.SlowWindow,P).';
Ua=sum(a.^2); G0=sum(g);
df=fsHz/M; da=fsHz/(P*L);
k=(-M/2:M/2-1).'; fk=k*df;
q=(-floor(P/2):ceil(P/2)-1);
residual=q*da;
qKeep=abs(residual)<=o.ResidualHalfWidthBins*df+8*eps(fsHz);
qUse=q(qKeep); residualUse=residual(qKeep);
% Numeric conversion is explicit and restricted to the consumed prefix.
x=double(x(1:need)); x=x(:);
D=complex(zeros(M,P));
inputWeightedEnergy=0;
for first=1:o.ChannelBatchSize:P
    rr=first:min(P,first+o.ChannelBatchSize-1);
    starts=(rr-1)*L;
    indices=(0:M-1).'+starts+1;
    blocks=x(indices);
    weighted=blocks.*a;
    U=fftshift(fft(weighted,[],1),1);
    % Integer modulo avoids unnecessarily large complex-exponential phases.
    phase=exp(-2i*pi*mod(k*starts,M)/M);
    D(:,rr)=U.*phase;
    inputWeightedEnergy=inputWeightedEnergy+ ...
        sum(g(rr).*sum(abs(weighted).^2,1));
end
clear blocks weighted U phase indices
channelEnergy=sum(abs(D).^2.*g,2);
psd=channelEnergy/(fsHz*Ua*G0);
maxPsd=max(psd);
floorPsd=max(o.PowerFloorAbsolute,maxPsd*10^(o.PowerFloorRelativeDb/10));
frequencyMask=fk>=o.FrequencyLimitsHz(1) & fk<=o.FrequencyLimitsHz(2);
powerMask=psd>floorPsd & channelEnergy>0 & frequencyMask;
out=struct();
out.psd=struct('f_hz',fk,'density',psd,'power_mask',powerMask, ...
    'floor_density',floorPsd,'relative_to_max',psd/max(maxPsd,realmin), ...
    'integrated_power',sum(psd)*df, ...
    'window_weighted_input_power',inputWeightedEnergy/(Ua*G0));
out.metadata=struct('fs_hz',fsHz,'M',M,'L',L,'P',P, ...
    'input_samples_used',need,'input_samples_available',availableSamples, ...
    'alpha_fft_time_seconds',P*L/fsHz,'actual_record_seconds',need/fsHz, ...
    'channel_bin_spacing_hz',df,'alpha_bin_spacing_hz',da, ...
    'channel_window_energy',Ua,'slow_window_sum',G0, ...
    'slow_window_energy',sum(g.^2), ...
    'channel_window_enbw_hz',fsHz*Ua/sum(a)^2, ...
    'slow_window_enbw_hz',(fsHz/L)*sum(g.^2)/G0^2, ...
    'density_scale',1/(fsHz*Ua*G0), ...
    'residual_half_width_hz',o.ResidualHalfWidthBins*df, ...
    'phase_reference',"Input first sample is local time zero.", ...
    'normalization',"Finite weighted smoothed channel-pair cyclic correlation; not pointwise population coherence.", ...
    'configuration_nc',"D(k)*conj(D(l)); f=(fk+fl)/2; alpha=fk-fl+q*Fs/(P*L)", ...
    'configuration_conjugate',"D(k)*D(l); f=(fk-fl)/2; alpha=fk+fl+q*Fs/(P*L)", ...
    'no_dc_subtraction',true,'no_input_conjugation',true,'no_zero_padding',true, ...
    'one_sided_doubling',false,'maximum_dense_pair_fft_values',P, ...
    'search_bias',"CDP maxima and top candidates are discovery statistics, not significance or packet identity.", ...
    'options',o);
out.nc=runConfiguration(1,o.AlphaLimitsHz,any(o.Modes=="nc"));
out.conjugate=runConfiguration(2,o.ConjugateAlphaLimitsHz, ...
    any(o.Modes=="conjugate"));
out.probes=repmat(probeTemplate(),size(o.ProbePoints,1),1);
for pp=1:size(o.ProbePoints,1)
    request=o.ProbePoints(pp,:);
    probeMode=request(1); fWanted=request(2); alphaWanted=request(3);
    f1=fWanted+alphaWanted/2;
    if probeMode==1
        f2=fWanted-alphaWanted/2;
    else
        f2=alphaWanted/2-fWanted;
    end
    [~,probeIk]=min(abs(fk-f1)); [~,probeIl]=min(abs(fk-f2));
    [probeCenter,probeAlpha0]=pairCoordinates(probeMode,probeIk,probeIl);
    qProbe=round((alphaWanted-probeAlpha0)/da);
    alphaActual=probeAlpha0+qProbe*da;
    rec=probeTemplate();
    rec.configuration=modeName(probeMode);
    rec.requested_f_hz=fWanted; rec.requested_alpha_hz=alphaWanted;
    rec.f_hz=probeCenter; rec.alpha_hz=alphaActual;
    rec.k_bin=k(probeIk); rec.l_bin=k(probeIl); rec.q_bin=qProbe;
    rec.power_mask_pass=powerMask(probeIk)&&powerMask(probeIl);
    geometry=isGeometryValid(probeMode,probeCenter,alphaActual);
    rec.valid=geometry && qProbe>=q(1) && qProbe<=q(end) && ...
        abs(qProbe*da)<=o.ResidualHalfWidthBins*df+8*eps(fsHz);
    if rec.valid
        probeFft=pairFft(probeMode,probeIk,probeIl);
        probeValue=probeFft(qProbe+floor(P/2)+1);
        probeDenominator=sqrt(channelEnergy(probeIk)*channelEnergy(probeIl));
        rec.scf_complex=probeValue/(fsHz*Ua*G0);
        if probeDenominator>0
            rec.pair_coherence_complex=probeValue/probeDenominator;
            rec.pair_coherence_magnitude=abs(probeValue)/probeDenominator;
        end
    end
    out.probes(pp)=rec;
end

    function result=runConfiguration(mode,limits,enabled)
        bins=(ceil(limits(1)/da):floor(limits(2)/da)).';
        assert(numel(bins)<=4e6,'famCycleScout26:ProfileSize', ...
            'Requested alpha profile exceeds four million points.');
        nA=numel(bins);
        result=struct('configuration',modeName(mode),'enabled',enabled, ...
            'alpha_hz',bins*da,'max_pair_coherence',zeros(nA,1), ...
            'max_abs_scf',zeros(nA,1),'argmax_f_hz',nan(nA,1), ...
            'contributing_pairs',zeros(nA,1),'top_candidates',[], ...
            'separated_profile_peaks',[]);
        nHeat=o.HeatmapAlphaBins;
        edges=linspace(limits(1),limits(2),nHeat+1);
        result.heatmap=struct('f_hz',(-M:M).'*df/2, ...
            'alpha_hz',((edges(1:end-1)+edges(2:end))/2), ...
            'max_pair_coherence',zeros(2*M+1,nHeat), ...
            'counts',zeros(2*M+1,nHeat), ...
            'aggregation',"Maximum and number of channel-pair/alpha-bin estimates per display cell.");
        stats=struct('total_channel_pairs',M*M,'evaluated_channel_pairs',0, ...
            'skipped_power_or_frequency_pairs',0,'skipped_alpha_support_pairs',0, ...
            'retained_estimates',0,'coherence_over_one_count',0, ...
            'maximum_pair_coherence',0);
        if ~enabled || nA==0
            result.stats=stats; return
        end
        buffer=complex(zeros(0,10));
        qLocations=find(qKeep);
        minAlphaBin=bins(1);
        for ik=1:M
            for il=1:M
                if ~powerMask(ik) || ~powerMask(il)
                    stats.skipped_power_or_frequency_pairs= ...
                        stats.skipped_power_or_frequency_pairs+1;
                    continue
                end
                [fCenter,alpha0]=pairCoordinates(mode,ik,il);
                if alpha0+residualUse(end)<limits(1) || ...
                        alpha0+residualUse(1)>limits(2)
                    stats.skipped_alpha_support_pairs= ...
                        stats.skipped_alpha_support_pairs+1;
                    continue
                end
                alpha=alpha0+residualUse;
                valid=alpha>=limits(1)-8*eps(fsHz) & ...
                    alpha<=limits(2)+8*eps(fsHz) & ...
                    isGeometryValid(mode,fCenter,alpha);
                if mode==1
                    valid=valid & abs(alpha)>o.ExcludeNcAlphaHz;
                end
                if ~any(valid)
                    continue
                end
                stats.evaluated_channel_pairs=stats.evaluated_channel_pairs+1;
                z=pairFft(mode,ik,il);
                z=z(qLocations(valid));
                aa=alpha(valid); qq=qUse(valid);
                coh=z/sqrt(channelEnergy(ik)*channelEnergy(il));
                cv=abs(coh);
                s=z/(fsHz*Ua*G0);
                stats.coherence_over_one_count=stats.coherence_over_one_count+ ...
                    sum(cv>1+1e-10);
                stats.maximum_pair_coherence=max(stats.maximum_pair_coherence,max(cv));
                jj=round(aa/da)-minAlphaBin+1;
                previous=result.max_pair_coherence(jj).';
                take=cv>previous;
                result.max_pair_coherence(jj)=max(previous,cv).';
                result.argmax_f_hz(jj(take))=fCenter;
                result.max_abs_scf(jj)=max(result.max_abs_scf(jj),abs(s).');
                result.contributing_pairs(jj)=result.contributing_pairs(jj)+1;
                stats.retained_estimates=stats.retained_estimates+numel(jj);
                hf=round(2*fCenter/df)+M+1;
                ha=min(nHeat,max(1, ...
                    floor((aa-limits(1))/(limits(2)-limits(1))*nHeat)+1));
                hm=accumarray(ha(:),cv(:),[nHeat 1],@max,0);
                hc=accumarray(ha(:),1,[nHeat 1],@sum,0);
                result.heatmap.max_pair_coherence(hf,:)= ...
                    max(result.heatmap.max_pair_coherence(hf,:),hm.');
                result.heatmap.counts(hf,:)=result.heatmap.counts(hf,:)+hc.';
                local=cv>=[-Inf cv(1:end-1)] & cv>[cv(2:end) -Inf];
                candidates=find(local);
                if ~isempty(candidates)
                    [~,order]=maxk(cv(candidates),min(o.TopPerPair,numel(candidates)));
                    pick=candidates(order);
                    ratio=min(psd(ik),psd(il))/max(maxPsd,realmin);
                    rows=[repmat(fCenter,numel(pick),1),aa(pick).', ...
                        s(pick).',coh(pick).',repmat(k(ik),numel(pick),1), ...
                        repmat(k(il),numel(pick),1),qq(pick).', ...
                        repmat(psd(ik),numel(pick),1), ...
                        repmat(psd(il),numel(pick),1), ...
                        repmat(ratio,numel(pick),1)];
                    buffer=[buffer;rows]; %#ok<AGROW>
                    if size(buffer,1)>o.TopCandidates+512
                        [~,keep]=maxk(abs(buffer(:,4)),o.TopCandidates);
                        buffer=buffer(keep,:);
                    end
                end
            end
        end
        if ~isempty(buffer)
            [~,keep]=maxk(abs(buffer(:,4)),min(o.TopCandidates,size(buffer,1)));
            result.top_candidates=candidateRecords(buffer(keep,:),mode);
        end
        result.separated_profile_peaks=profilePeaks(result,o.TopCandidates,o.PeakSeparationBins);
        result.stats=stats;
    end

    function [fCenter,alpha0]=pairCoordinates(mode,ik,il)
        if mode==1
            fCenter=(fk(ik)+fk(il))/2; alpha0=fk(ik)-fk(il);
        else
            fCenter=(fk(ik)-fk(il))/2; alpha0=fk(ik)+fk(il);
        end
    end

    function valid=isGeometryValid(mode,fCenter,alpha)
        fOne=fCenter+alpha/2;
        if mode==1
            fTwo=fCenter-alpha/2;
        else
            fTwo=alpha/2-fCenter;
        end
        lower=o.FrequencyLimitsHz(1); upper=o.FrequencyLimitsHz(2);
        valid=fOne>=lower & fOne<=upper & fTwo>=lower & fTwo<=upper & ...
            fOne>=-fsHz/2 & fOne<fsHz/2 & fTwo>=-fsHz/2 & fTwo<fsHz/2;
    end

    function z=pairFft(mode,ik,il)
        if mode==1
            product=D(ik,:).*conj(D(il,:));
        else
            product=D(ik,:).*D(il,:);
        end
        z=fftshift(fft(product.*g,[],2),2);
    end
end

function limits=checkLimits(value,bounds,label)
validateattributes(value,{'numeric'},{'vector','numel',2,'real','finite'},mfilename,label);
limits=double(value(:).');
assert(limits(1)<limits(2) && limits(1)>=bounds(1) && limits(2)<=bounds(2), ...
    'famCycleScout26:Limits','%s must increase within [%g,%g].',label,bounds(1),bounds(2));
end

function w=makeWindow(spec,n)
if isnumeric(spec)
    validateattributes(spec,{'numeric'},{'vector','numel',n,'real','finite','nonnegative'});
    w=double(spec(:));
else
    name=string(spec);
    assert(isscalar(name),'famCycleScout26:Window','Window name must be scalar.');
    t=(0:n-1).'/(n-1);
    switch lower(name)
        case "hamming"
            w=0.54-0.46*cos(2*pi*t);
        case "hann"
            w=0.5-0.5*cos(2*pi*t);
        case "rectangular"
            w=ones(n,1);
        otherwise
            error('famCycleScout26:Window','Unknown window: %s',name);
    end
end
assert(sum(w)>0,'famCycleScout26:Window','Window must have positive energy.');
end

function name=modeName(mode)
if mode==1
    name="nc";
else
    name="conjugate";
end
end

function rec=probeTemplate()
rec=struct('configuration',"",'requested_f_hz',NaN,'requested_alpha_hz',NaN, ...
    'f_hz',NaN,'alpha_hz',NaN,'scf_complex',complex(NaN,NaN), ...
    'pair_coherence_complex',complex(NaN,NaN),'pair_coherence_magnitude',NaN, ...
    'k_bin',NaN,'l_bin',NaN,'q_bin',NaN,'valid',false,'power_mask_pass',false);
end

function records=candidateRecords(matrix,mode)
template=struct('configuration',modeName(mode),'f_hz',0,'alpha_hz',0, ...
    'scf_complex',complex(0),'pair_coherence_complex',complex(0), ...
    'pair_coherence_magnitude',0,'k_bin',0,'l_bin',0,'q_bin',0, ...
    'channel1_psd',0,'channel2_psd',0,'min_channel_power_ratio_to_max',0);
records=repmat(template,size(matrix,1),1);
for ii=1:size(matrix,1)
    row=matrix(ii,:);
    records(ii).f_hz=real(row(1)); records(ii).alpha_hz=real(row(2));
    records(ii).scf_complex=row(3); records(ii).pair_coherence_complex=row(4);
    records(ii).pair_coherence_magnitude=abs(row(4));
    records(ii).k_bin=real(row(5)); records(ii).l_bin=real(row(6));
    records(ii).q_bin=real(row(7)); records(ii).channel1_psd=real(row(8));
    records(ii).channel2_psd=real(row(9));
    records(ii).min_channel_power_ratio_to_max=real(row(10));
end
end

function records=profilePeaks(result,limit,separationBins)
v=result.max_pair_coherence;
local=v>=[-Inf;v(1:end-1)] & v>[v(2:end);-Inf] & ...
    result.contributing_pairs>0 & v>0;
candidates=find(local);
[~,order]=sort(v(candidates),'descend');
selected=zeros(0,1);
for ii=1:numel(order)
    index=candidates(order(ii));
    if isempty(selected) || all(abs(index-selected)>=separationBins)
        selected(end+1,1)=index; %#ok<AGROW>
        if numel(selected)>=limit
            break
        end
    end
end
template=struct('alpha_hz',0,'argmax_f_hz',0,'max_pair_coherence',0, ...
    'max_abs_scf',0,'contributing_pairs',0);
records=repmat(template,numel(selected),1);
for ii=1:numel(selected)
    jj=selected(ii);
    records(ii).alpha_hz=result.alpha_hz(jj);
    records(ii).argmax_f_hz=result.argmax_f_hz(jj);
    records(ii).max_pair_coherence=v(jj);
    records(ii).max_abs_scf=result.max_abs_scf(jj);
    records(ii).contributing_pairs=result.contributing_pairs(jj);
end
end
