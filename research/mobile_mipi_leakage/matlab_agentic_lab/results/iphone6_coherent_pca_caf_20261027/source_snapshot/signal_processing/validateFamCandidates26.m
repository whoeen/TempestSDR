function report = validateFamCandidates26(resultsRoot, outputDirectory, options)
%VALIDATEFAMCANDIDATES26 Confirm discovery-selected NC FAM pairs without search.
% report = validateFamCandidates26(resultsRoot, outputDirectory, options)
% reads refined/rf*_block{1,2,3}/{fam,subband}.mat. Only block1 selects the
% alpha-separated k/l/q triples and line-projection bins. Other blocks are
% evaluated at those exact coordinates. No MATLAB execution is performed by
% authoring agents; the root agent runs this function after the files exist.
%
% The second estimator is a frequency-smoothed cyclic periodogram, evaluated
% at frozen physical (f,alpha), using the first P*L contiguous samples. It
% has a different smoothing kernel; equality with FAM is not expected.
%
% Spectral line projection uses an exact DFT basis of the complete consumed
% block (no zero padding). Its circular projection can remove wanted screen
% periodicity. Neither its removal nor a Gaussian control identifies clutter.
arguments
    resultsRoot (1,1) string
    outputDirectory (1,1) string
    options (1,1) struct = struct()
end
defaults = struct('MaximumCandidates',12,'AlphaSeparationHz',500, ...
    'BlockNumbers',[1 2 3],'LinePeaks',8,'LineHalfWidthBins',2, ...
    'MinimumLinePeakSeparationBins',5,'NoiseSeeds',[26102631 26102632], ...
    'FrequencySmoothingWidthChannels',1);
keys=fieldnames(options);
for ii=1:numel(keys)
    assert(isfield(defaults,keys{ii}), 'Unknown option: %s',keys{ii});
    defaults.(keys{ii})=options.(keys{ii});
end
o=defaults;
assert(o.MaximumCandidates>=1 && o.AlphaSeparationHz>0);
assert(isequal(o.BlockNumbers(:).',[1 2 3]), 'This audit requires blocks1,2,3.');
assert(~isfolder(outputDirectory)&&~isfile(outputDirectory), 'Refuse overwrite.');
folders=dir(fullfile(resultsRoot,'refined','rf*_block1'));
folders=folders([folders.isdir]);
assert(~isempty(folders),'No discovery block1 folders found.');
[~,order]=sort(string({folders.name}));folders=folders(order);
mkdir(outputDirectory);
oldRng=rng;
rngCleanup=onCleanup(@()rng(oldRng)); %#ok<NASGU>
report=struct('status',"running",'options',o,'bands',struct([]));
report.created_utc=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'"));
report.matlab_version=version;
report.results_root=resultsRoot;
report.phase_convention=[ ...
    "NC cyclic product x(t+lag/2)*conj(x(t-lag/2)); cyclic Fourier sign is negative.", ...
    "Local phase uses the first retained sample as time zero.", ...
    "Original-epoch phase multiplies local coefficient by exp(-j*2*pi*alpha*firstNative/FsNative).", ...
    "Absolute DDC mixer phase is already present in subband IQ; it is not applied again.", ...
    "A quantized alpha error can rotate inter-block phase; phase consistency is not asserted."];
flatRows=struct([]);
for bandIndex=1:numel(folders)
    stem=erase(string(folders(bandIndex).name),'_block1');
    discoveryFolder=fullfile(resultsRoot,'refined',folders(bandIndex).name);
    discovery=load(fullfile(discoveryFolder,'fam.mat'),'result','context');
    data=load(fullfile(discoveryFolder,'subband.mat'),'iq','front');
    fam=discovery.result;
    fsHz=fam.metadata.fs_hz;
    need=(fam.metadata.P-1)*fam.metadata.L+fam.metadata.M;
    assert(numel(data.iq)>=need,'Discovery block is shorter than FAM input.');
    selected=selectCandidates(fam.nc.top_candidates,o);
    assert(~isempty(selected),'No non-conjugate discovery candidates.');
    lineModel=selectLineBins(data.iq(1:need),fsHz,o);
    frozen=struct('M',fam.metadata.M,'L',fam.metadata.L,'P',fam.metadata.P, ...
        'ChannelWindow',fam.metadata.options.ChannelWindow, ...
        'SlowWindow',fam.metadata.options.SlowWindow, ...
        'power_floor_density',fam.psd.floor_density, ...
        'frequency_limits_hz',fam.metadata.options.FrequencyLimitsHz);
    band=struct;
    band.tag=stem;
    band.nominal_center_hz=discovery.context.nominal_center_hz;
    band.discovery_context=discovery.context;
    band.selection="Only block1 top_candidates, descending pair coherence with fixed alpha separation; no row prior.";
    band.frozen_candidates=selected;
    band.frozen_fam=frozen;
    band.line_projection=lineModel;
    band.blocks=struct([]);
    referenceNative=data.front.retained_original_first_sample;
    discoveryPower=mean(abs(double(data.iq(1:need))).^2);
    for block=o.BlockNumbers
        location=fullfile(resultsRoot,'refined',stem+"_block"+block);
        input=load(fullfile(location,'subband.mat'),'iq','front');
        saved=load(fullfile(location,'fam.mat'),'context','result');
        assert(saved.result.metadata.fs_hz==fsHz && ...
            saved.result.metadata.M==frozen.M && saved.result.metadata.L==frozen.L && ...
            saved.result.metadata.P==frozen.P, 'FAM grids differ between blocks.');
        assert(input.front.output_fs_hz==fsHz && numel(input.iq)>=need);
        iq=double(input.iq(1:need));iq=iq(:);
        firstNative=input.front.retained_original_first_sample;
        fsNative=input.front.native_fs_hz;
        epochSeconds=double(firstNative)/double(fsNative);
        [projection,residual,projectionStats]=projectLineBins(iq,lineModel);
        original=exactPairDtft(iq,fsHz,frozen,selected,epochSeconds);
        lineOnly=exactPairDtft(projection,fsHz,frozen,selected,epochSeconds);
        remaining=exactPairDtft(residual,fsHz,frozen,selected,epochSeconds);
        independent=frequencySmoothedEstimate(iq,fsHz,frozen,selected, ...
            epochSeconds,o.FrequencySmoothingWidthChannels);
        record=struct('block',block,'context',saved.context, ...
            'native_first_sample',firstNative,'native_fs_hz',fsNative, ...
            'epoch_seconds',epochSeconds,'elapsed_from_discovery_seconds', ...
            (firstNative-referenceNative)/fsNative, ...
            'samples_consumed',need,'time_seconds',need/fsHz, ...
            'selection_repeated',false,'original',original,'line_only',lineOnly, ...
            'line_residual',remaining,'line_projection_metrics',projectionStats, ...
            'independent_frequency_smoothing',independent);
        if block==1
            expected=[selected.pair_coherence_complex].';
            observed=[original.coherence_real].'+1i*[original.coherence_imag].';
            band.discovery_replay_max_absolute_error=max(abs(expected-observed));
            band.discovery_replay_pass=band.discovery_replay_max_absolute_error<1e-8;
        end
        if isempty(band.blocks)
            band.blocks=record;
        else
            band.blocks(end+1)=record; %#ok<AGROW>
        end
        for jj=1:numel(selected)
            row=struct('rf_center_hz',band.nominal_center_hz,'block',block, ...
                'candidate',jj,'f_baseband_hz',selected(jj).f_hz, ...
                'f_nominal_rf_hz',band.nominal_center_hz+selected(jj).f_hz, ...
                'alpha_hz',selected(jj).alpha_hz,'k_bin',selected(jj).k_bin, ...
                'l_bin',selected(jj).l_bin,'q_bin',selected(jj).q_bin, ...
                'original_coherence',original(jj).coherence_magnitude, ...
                'line_only_coherence',lineOnly(jj).coherence_magnitude, ...
                'line_residual_coherence',remaining(jj).coherence_magnitude, ...
                'fsm_coherence',independent.estimates(jj).coherence_magnitude, ...
                'original_phase_local_rad',original(jj).phase_local_radians, ...
                'original_phase_epoch_rad',original(jj).phase_original_epoch_radians, ...
                'heldout_power_floor_pass',original(jj).frozen_power_floor_pass, ...
                'line_power_fraction',projectionStats.power_fraction);
            if isempty(flatRows)
                flatRows=row;
            else
                flatRows(end+1)=row; %#ok<AGROW>
            end
        end
        clear iq projection residual input saved
    end
    % Proper Gaussian controls: independent complex Gaussian DFT coefficients
    % shaped by a periodic interpolation of the discovery coarse PSD. These
    % preserve broad colour/power, not deterministic line amplitude or phase.
    band.gaussian_controls=struct([]);
    for seed=o.NoiseSeeds
        noise=coloredGaussian(need,fsHz,fam.psd,discoveryPower,seed);
        estimates=exactPairDtft(noise,fsHz,frozen,selected,referenceNative/data.front.native_fs_hz);
        control=struct('seed',seed,'model', ...
            "Proper complex Gaussian Fourier coefficients, discovery coarse PSD interpolation, exact N-point IFFT; no zero padding.", ...
            'samples',need,'rms_counts',sqrt(mean(abs(noise).^2)), ...
            'sample_pseudocorrelation',abs(mean(noise.^2))/mean(abs(noise).^2), ...
            'estimates',estimates);
        if isempty(band.gaussian_controls)
            band.gaussian_controls=control;
        else
            band.gaussian_controls(end+1)=control; %#ok<AGROW>
        end
        clear noise
    end
    if isempty(report.bands)
        report.bands=band;
    else
        report.bands(end+1)=band; %#ok<AGROW>
    end
    fprintf('%s frozen validation: %d pairs, replay error %.3g, line bins %d.\n', ...
        stem,numel(selected),band.discovery_replay_max_absolute_error,numel(lineModel.selected_indices));
    clear data discovery fam
end
report.status="complete";
report.all_discovery_replays_passed=all([report.bands.discovery_replay_pass]);
report.limitations=[ ...
    "Only block1 selects NC alpha/channel pairs. Blocks2/3 do not refit or maximize them.", ...
    "The independent estimator uses a different smoothing kernel; magnitudes need not equal FAM.", ...
    "The exact-bin line locations are selected from block1. Their complex coefficients are projected separately within each block.", ...
    "Line projection and residual are circular spectral diagnostics; desired screen periodicity can be removed too.", ...
    "Two Gaussian controls are sanity references, not calibrated family-wise false-alarm thresholds.", ...
    "A repeatable cyclic feature can be a deterministic tone difference; no DSI packet/HS identity is established.", ...
    "These are separated blocks in an existing capture, not a claim that the entire record was previously unseen."];
writetable(struct2table(flatRows),fullfile(outputDirectory,'frozen_candidates.csv'));
save(fullfile(outputDirectory,'validation.mat'),'report','-v7.3');
writeJson(fullfile(outputDirectory,'validation.json'),jsonSafe(report));
assert(report.all_discovery_replays_passed,'validateFamCandidates26:Replay', ...
    'Direct pair-DTFT replay differs from saved discovery FAM. Inspect validation.json.');
end

function selected=selectCandidates(candidates,o)
selected=candidates([]);
if isempty(candidates),return,end
[~,order]=sort([candidates.pair_coherence_magnitude],'descend');
for index=order
    current=candidates(index);
    if ~isfinite(current.pair_coherence_magnitude)||current.alpha_hz<=0,continue,end
    if isempty(selected)||all(abs(current.alpha_hz-[selected.alpha_hz])>=o.AlphaSeparationHz)
        selected(end+1)=current; %#ok<AGROW>
        if numel(selected)>=o.MaximumCandidates,break,end
    end
end
end

function estimates=exactPairDtft(x,fsHz,o,pairs,epochSeconds)
M=o.M;L=o.L;P=o.P;
a=windowVector(o.ChannelWindow,M);g=windowVector(o.SlowWindow,P).';
bins=unique([[pairs.k_bin] [pairs.l_bin]]);
D=complex(zeros(numel(bins),P));
for first=1:512:P
    columns=first:min(P,first+511);starts=(columns-1)*L;
    indices=(0:M-1).'+starts+1;
    spectrum=fftshift(fft(x(indices).*a,[],1),1);
    D(:,columns)=spectrum(bins+M/2+1,:).* ...
        exp(-2i*pi*mod(bins(:)*starts,M)/M);
end
energy=sum(abs(D).^2.*g,2);
Ua=sum(a.^2);G0=sum(g);r=0:P-1;
estimates=repmat(estimateTemplate(),numel(pairs),1);
for jj=1:numel(pairs)
    pair=pairs(jj);
    ik=find(bins==pair.k_bin,1);il=find(bins==pair.l_bin,1);
    assert(abs(pair.q_bin-round(pair.q_bin))<1e-10);
    phasor=exp(-2i*pi*mod(pair.q_bin*r,P)/P);
    value=sum(D(ik,:).*conj(D(il,:)).*g.*phasor);
    denominator=sqrt(energy(ik)*energy(il));
    coherence=value/denominator;
    if denominator==0,coherence=complex(NaN,NaN);end
    psd1=energy(ik)/(fsHz*Ua*G0);psd2=energy(il)/(fsHz*Ua*G0);
    estimates(jj)=packEstimate(pair,value/(fsHz*Ua*G0),coherence, ...
        epochSeconds,psd1,psd2,psd1>o.power_floor_density&&psd2>o.power_floor_density);
end
end

function out=frequencySmoothedEstimate(x,fsHz,o,pairs,epochSeconds,widthChannels)
N=o.P*o.L;
originalSamples=numel(x);
assert(originalSamples>=N);
x=x(1:N);t=(0:N-1)'/fsHz;
w=0.5-0.5*cos(2*pi*(0:N-1)'/N);
U=sum(w.^2);frequencies=(-N/2:N/2-1)'*fsHz/N;
halfWidth=widthChannels*fsHz/o.M/2;
estimates=repmat(estimateTemplate(),numel(pairs),1);
for jj=1:numel(pairs)
    pair=pairs(jj);alpha=pair.alpha_hz;
    % Xplus(f)=X(f+alpha/2), Xminus(f)=X(f-alpha/2).
    Xplus=fftshift(fft(x.*w.*exp(-1i*pi*alpha*t)));
    Xminus=fftshift(fft(x.*w.*exp(1i*pi*alpha*t)));
    keep=abs(frequencies-pair.f_hz)<halfWidth & ...
        frequencies+alpha/2>=o.frequency_limits_hz(1) & ...
        frequencies+alpha/2<=o.frequency_limits_hz(2) & ...
        frequencies-alpha/2>=o.frequency_limits_hz(1) & ...
        frequencies-alpha/2<=o.frequency_limits_hz(2);
    weights=1-abs(frequencies(keep)-pair.f_hz)/halfWidth;
    assert(~isempty(weights)&&sum(weights)>0,'No valid smoothing frequencies.');
    plus=Xplus(keep);minus=Xminus(keep);
    numerator=sum(weights.*plus.*conj(minus));
    energy1=sum(weights.*abs(plus).^2);energy2=sum(weights.*abs(minus).^2);
    coherence=numerator/sqrt(energy1*energy2);
    psd1=energy1/(fsHz*U*sum(weights));psd2=energy2/(fsHz*U*sum(weights));
    estimates(jj)=packEstimate(pair,numerator/(fsHz*U*sum(weights)), ...
        coherence,epochSeconds,psd1,psd2, ...
        psd1>o.power_floor_density&&psd2>o.power_floor_density);
    estimates(jj).frequency_average_bins=numel(weights);
    estimates(jj).frequency_weight_effective_bins=sum(weights)^2/sum(weights.^2);
end
out=struct('method',"Frequency-smoothed cyclic periodogram via explicit +/-alpha/2 modulation", ...
    'input_samples',N,'input_samples_omitted_at_end',originalSamples-N, ...
    'time_seconds',N/fsHz,'fft_spacing_hz',fsHz/N, ...
    'time_window',"periodic Hann",'time_window_enbw_hz',fsHz*U/sum(w)^2, ...
    'frequency_kernel',"triangular, physical bandwidth fixed before confirmation", ...
    'smoothing_full_width_hz',2*halfWidth,'zero_padding',false, ...
    'estimates',estimates);
end

function model=selectLineBins(x,fsHz,o)
x=double(x(:));N=numel(x);X=fft(x);power=abs(X).^2;
peaks=power>=circshift(power,1)&power>circshift(power,-1);
indices=find(peaks);
[~,order]=sort(power(indices),'descend');indices=indices(order);
centers=zeros(0,1);
for index=indices(:).'
    distance=abs(index-centers);distance=min(distance,N-distance);
    if isempty(centers)||all(distance>=o.MinimumLinePeakSeparationBins)
        centers(end+1,1)=index; %#ok<AGROW>
        if numel(centers)>=o.LinePeaks,break,end
    end
end
selected=unique(mod(centers-1+(-o.LineHalfWidthBins:o.LineHalfWidthBins),N)+1);
selected=selected(:);
centerHz=mod((centers-1)*fsHz/N+fsHz/2,fsHz)-fsHz/2;
selectedHz=mod((selected-1)*fsHz/N+fsHz/2,fsHz)-fsHz/2;
model=struct('basis_length',N,'basis',"Exact unpadded N-point DFT of discovery block", ...
    'selected_peak_indices',centers,'selected_peak_frequencies_hz',centerHz, ...
    'selected_indices',selected,'selected_frequencies_hz',selectedHz, ...
    'half_width_bins',o.LineHalfWidthBins, ...
    'minimum_peak_separation_bins',o.MinimumLinePeakSeparationBins, ...
    'selection_source',"block1 periodogram local maxima; no SCF prior", ...
    'discovery_selected_power_fraction',sum(power(selected))/sum(power), ...
    'coefficient_policy',"Same bin indices, coefficients projected separately in each block", ...
    'circular_projection',true,'zero_padding',false);
end

function [projection,residual,stats]=projectLineBins(x,model)
N=numel(x);assert(N==model.basis_length);
X=fft(x);lineSpectrum=complex(zeros(N,1));
lineSpectrum(model.selected_indices)=X(model.selected_indices);
projection=ifft(lineSpectrum);residual=x-projection;
power=mean(abs(x).^2);linePower=mean(abs(projection).^2);
residualPower=mean(abs(residual).^2);
stats=struct('power_fraction',linePower/max(power,realmin), ...
    'original_power_counts_squared',power,'line_power_counts_squared',linePower, ...
    'residual_power_counts_squared',residualPower, ...
    'orthogonal_power_sum_relative_error',abs(power-linePower-residualPower)/max(power,realmin));
end

function x=coloredGaussian(N,fsHz,discoveryPsd,targetPower,seed)
rng(seed,'twister');
f=discoveryPsd.f_hz(:);density=discoveryPsd.density(:);
frequency=(-floor(N/2):ceil(N/2)-1)'*fsHz/N;
shape=interp1([f-fsHz;f;f+fsHz],[density;density;density],frequency,'linear');
shape=max(shape,0);
expectedPower=sum(shape)*fsHz/N;
shape=shape*(targetPower/max(expectedPower,realmin));
Z=(randn(N,1)+1i*randn(N,1))/sqrt(2);
x=ifft(ifftshift(sqrt(N*fsHz*shape).*Z));
end

function value=packEstimate(pair,scf,coherence,epochSeconds,psd1,psd2,powerPass)
rotation=exp(-2i*pi*mod(pair.alpha_hz*epochSeconds,1));
value=estimateTemplate();
value.f_hz=pair.f_hz;value.alpha_hz=pair.alpha_hz;
value.k_bin=pair.k_bin;value.l_bin=pair.l_bin;value.q_bin=pair.q_bin;
value.scf_real=real(scf);value.scf_imag=imag(scf);
value.coherence_real=real(coherence);value.coherence_imag=imag(coherence);
value.coherence_magnitude=abs(coherence);
value.phase_local_radians=angle(coherence);
value.phase_original_epoch_radians=angle(coherence*rotation);
value.scf_original_epoch_real=real(scf*rotation);
value.scf_original_epoch_imag=imag(scf*rotation);
value.channel1_psd=psd1;value.channel2_psd=psd2;
value.frozen_power_floor_pass=logical(powerPass);
end

function value=estimateTemplate()
value=struct('f_hz',0,'alpha_hz',0,'k_bin',0,'l_bin',0,'q_bin',0, ...
    'scf_real',0,'scf_imag',0,'coherence_real',0,'coherence_imag',0, ...
    'coherence_magnitude',0,'phase_local_radians',0, ...
    'phase_original_epoch_radians',0,'scf_original_epoch_real',0, ...
    'scf_original_epoch_imag',0,'channel1_psd',0,'channel2_psd',0, ...
    'frozen_power_floor_pass',false,'frequency_average_bins',0, ...
    'frequency_weight_effective_bins',0);
end

function w=windowVector(spec,N)
if isnumeric(spec)
    w=double(spec(:));assert(numel(w)==N);return
end
switch string(spec)
    case "rectangular",w=ones(N,1);
    case "hamming",w=0.54-0.46*cos(2*pi*(0:N-1)'/(N-1));
    case "hann",w=0.5-0.5*cos(2*pi*(0:N-1)'/(N-1));
    otherwise,error('Unsupported saved window.');
end
end

function out=jsonSafe(in)
if isstruct(in)
    out=in;fields=fieldnames(in);
    for k=1:numel(in)
        for j=1:numel(fields),out(k).(fields{j})=jsonSafe(in(k).(fields{j}));end
    end
elseif iscell(in),out=cellfun(@jsonSafe,in,'UniformOutput',false);
elseif isnumeric(in)&&~isreal(in),out=struct('real',real(in),'imag',imag(in));
else,out=in;end
end

function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot write JSON.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
