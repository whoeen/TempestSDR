function report = analyzeFamPeriodicity26(resultRoot, outputDirectory, options)
%ANALYZEFAMPERIODICITY26 Training-only harmonic families and frozen-period folds.
% Uses existing refined FAM and AA-only subband.mat files; no raw alteration.
% First block per RF center fits candidate frequencies. Later blocks only
% assess those frozen candidates. Whole-record cyclic phases use original
% native sample timestamps. Optional circular alignment is DISPLAY ONLY and
% its fitted shift is recorded; unaligned results remain the primary output.
% A radiation periodicity or a paired waveform is not a decoded HS packet.
arguments
    resultRoot (1,1) string = ""
    outputDirectory (1,1) string = ""
    options (1,1) struct = struct()
end
lab=fileparts(mfilename('fullpath'));
if resultRoot==""
    resultRoot=fullfile(lab,"results","iphone6_fc100_fam_20261026");
end
if outputDirectory==""
    outputDirectory=fullfile(resultRoot,"periodicity");
end
o=struct('MaxHarmonic',12,'TopPeaks',64,'MinPeakCoherence',0.05, ...
    'FamilyToleranceBins',1.5,'MinFamilyHarmonics',3,'MaxFamilies',6, ...
    'FoldBins',128,'TimeChunks',16,'DisplayAlign',true, ...
    'RefineFundamental',true,'RefinementGridPoints',33);
for field=string(fieldnames(options)).'
    assert(isfield(o,field),'Unknown option: %s',field);
    o.(field)=options.(field);
end
for name=["MaxHarmonic","TopPeaks","MinFamilyHarmonics","MaxFamilies", ...
        "FoldBins","TimeChunks","RefinementGridPoints"]
    validateattributes(o.(name),{'numeric'},{'scalar','integer','positive','real','finite'});
end
assert(mod(o.FoldBins,2)==0 && o.RefinementGridPoints>=3);
validateattributes(o.MinPeakCoherence,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(o.FamilyToleranceBins,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(o.DisplayAlign,{'logical'},{'scalar'});
validateattributes(o.RefineFundamental,{'logical'},{'scalar'});
assert(~isfolder(outputDirectory) && ~isfile(outputDirectory),'Refuse overwrite.');
dirs=dir(fullfile(resultRoot,"refined","rf*_block1"));
assert(~isempty(dirs),'No refined training block found.');
mkdir(outputDirectory);
centerRecords=cell(numel(dirs),1);
for cc=1:numel(dirs)
    trainFolder=fullfile(dirs(cc).folder,dirs(cc).name);
    loaded=load(fullfile(trainFolder,'fam.mat'),'result','context');
    train=loaded.result; context=loaded.context;
    delta=train.metadata.alpha_bin_spacing_hz;
    peaks=train.nc.separated_profile_peaks;
    peaks=peaks(1:min(o.TopPeaks,numel(peaks)));
    peaks=peaks([peaks.alpha_hz]>0 & [peaks.max_pair_coherence]>=o.MinPeakCoherence);
    assert(numel(peaks)>=o.MinFamilyHarmonics,'Insufficient training peaks.');
    families=fitFamilies(peaks,delta,o);
    assert(~isempty(families),'No supported integer harmonic family.');
    seed=families(1).fundamental_hz;
    trainingWave=load(fullfile(trainFolder,'subband.mat'),'iq','front');
    fs=trainingWave.front.output_fs_hz;
    refinement=refinePowerFrequency(trainingWave.iq,fs,seed,delta,o);
    frequency=refinement.used_frequency_hz;
    split=halfOrderGroups(peaks,seed,delta,o);
    slowPeaks=peaks([peaks.alpha_hz]<seed/o.MaxHarmonic);
    centerTag=regexprep(string(dirs(cc).name),'_block1$','');
    available=dir(fullfile(resultRoot,"refined",centerTag+"_block*"));
    [~,idx]=sort(arrayfun(@(d)str2double(extractAfter(string(d.name),"_block")),available));
    available=available(idx);
    folds=cell(numel(available),2);
    blockReports=cell(numel(available),1);
    referencePower=[];
    for bb=1:numel(available)
        folder=fullfile(available(bb).folder,available(bb).name);
        current=load(fullfile(folder,'fam.mat'),'result','context');
        wave=load(fullfile(folder,'subband.mat'),'iq','front');
        assert(wave.front.output_fs_hz==fs,'Mixed sample rates.');
        firstTime=current.context.first_sample_zero_based/wave.front.native_fs_hz;
        if bb==1
            referencePower=mean(abs(wave.iq).^2);
        end
        for pp=1:2
            % F/2 is an explicit two-cycle hypothesis, not an observed peak.
            foldFrequency=frequency/pp;
            folds{bb,pp}=foldWave(wave.iq,fs,firstTime,foldFrequency,o);
            folds{bb,pp}.power_relative_to_training_mean= ...
                folds{bb,pp}.mean_power/referencePower;
            folds{bb,pp}.amplitude_relative_to_training_rms= ...
                folds{bb,pp}.mean_amplitude/sqrt(referencePower);
            folds{bb,pp}.chunk_power_relative_to_training_mean= ...
                folds{bb,pp}.chunk_mean_power/referencePower;
        end
        matching=matchFrozenFamily(current.result.nc.separated_profile_peaks, ...
            families(1),delta*o.FamilyToleranceBins);
        record=struct('block',current.context.block,'source_folder',folder, ...
            'first_sample_zero_based',current.context.first_sample_zero_based, ...
            'native_fs_hz',wave.front.native_fs_hz,'sample_rate_hz',fs, ...
            'first_time_seconds',firstTime,'is_frequency_fit_block',bb==1, ...
            'frequency_hz_frozen',frequency,'period_seconds_frozen',1/frequency, ...
            'family_frequency_fitted_on_this_block',false, ...
            'frozen_family_matches',matching, ...
            'family_match_scope',"Nearest later-block CDP peak to a frozen family frequency; descriptive proximity, not frozen k/l/q confirmation.", ...
            'fold_metrics',[]);
        if bb==1
            record.family_frequency_fitted_on_this_block=true;
        end
        metrics=repmat(struct(),2,1);
        for pp=1:2
            ref=folds{1,pp}.mean_power; currentPower=folds{bb,pp}.mean_power;
            [displayShift,displayCorrelation]=displayAlign(ref,currentPower);
            originalCorrelation=vectorCorrelation(ref,currentPower);
            half=o.FoldBins/2;
            metrics(pp).fold_frequency_hz=frequency/pp;
            metrics(pp).fold_period_seconds=pp/frequency;
            metrics(pp).period_multiplier=pp;
            metrics(pp).unaligned_power_correlation_to_training=originalCorrelation;
            metrics(pp).relative_fold_modulation_rms= ...
                std(currentPower)/max(mean(currentPower),realmin);
            metrics(pp).half_cycle_power_correlation= ...
                vectorCorrelation(currentPower(1:half),currentPower(half+1:end));
            metrics(pp).half_cycle_difference_relative_to_mean= ...
                sqrt(mean((currentPower(1:half)-currentPower(half+1:end)).^2))/ ...
                max(mean(currentPower),realmin);
            metrics(pp).display_only_shift_bins=displayShift;
            metrics(pp).display_only_shift_cycles=displayShift/o.FoldBins;
            metrics(pp).display_only_shift_seconds=displayShift/o.FoldBins*pp/frequency;
            metrics(pp).display_only_aligned_correlation=displayCorrelation;
            metrics(pp).display_alignment_used_for_validation=false;
            folds{bb,pp}.display_only_shift_bins=displayShift;
        end
        record.fold_metrics=metrics;
        blockReports{bb}=record;
        clear wave current
    end
    summary=struct('rf_center_hz',context.nominal_center_hz, ...
        'training_source',trainFolder,'training_alpha_grid_hz',delta, ...
        'integer_family_search_minimum_hz',max([peaks.alpha_hz])/o.MaxHarmonic, ...
        'discovery_peaks',peaks,'integer_harmonic_families',families, ...
        'selected_family_is_unique_physical_fundamental',false, ...
        'refinement',refinement,'odd_half_order_groups',split, ...
        'low_frequency_candidates',slowPeaks,'blocks',{blockReports}, ...
        'inference_scope',"Radiation periodicity and sideband hypotheses; no bit/byte/lane/packet decoding.", ...
        'two_cycle_scope',"F/2 folding is a derived comparison; a split odd-half-order family need not have a peak at F/2.", ...
        'uncertainty_scope',"FFT spacing, tolerance intervals and DTFT optimization are not statistical confidence intervals.");
    target=fullfile(outputDirectory,centerTag);
    mkdir(target);
    save(fullfile(target,'folds.mat'),'folds','summary','o','-v7.3');
    writeJson(fullfile(target,'summary.json'),summary);
    makeFigures(train,summary,folds,target,o);
    centerRecords{cc}=summary;
    fprintf('%s: FAM family %.9f Hz, fold %.9f Hz, period %.9f us.\n', ...
        centerTag,seed,frequency,1e6/frequency);
    clear train trainingWave folds loaded
end
report=struct('status',"completed",'result_root',resultRoot, ...
    'training_only_selection',true,'options',o,'centers',{centerRecords}, ...
    'packet_identified',false,'new_sampling_rate_or_bit_rate_measured',false);
writeJson(fullfile(outputDirectory,'summary.json'),report);
end

function families=fitFamilies(peaks,delta,o)
alpha=[peaks.alpha_hz].'; weights=[peaks.max_pair_coherence].'.^2;
tolerance=delta*o.FamilyToleranceBins;
frequencyFloor=max(alpha)/o.MaxHarmonic;
template=struct('fundamental_hz',0,'support_harmonics',[], ...
    'observed_alpha_hz',[],'residual_hz',[],'coherence',[], ...
    'score',0,'weighted_rms_hz',0,'divided_harmonic_gcd',1, ...
    'tolerance_intersection_hz',[NaN NaN]);
families=repmat(template,0,1);
for origin=1:numel(alpha)
    for divisor=1:o.MaxHarmonic
        frequency=alpha(origin)/divisor;
        if frequency<frequencyFloor
            continue
        end
        selected=[]; harmonic=[];
        for iteration=1:4
            selected=[]; harmonic=[];
            for hh=1:o.MaxHarmonic
                possible=find(abs(alpha-hh*frequency)<=tolerance);
                if isempty(possible),continue,end
                [~,best]=max(weights(possible));
                selected(end+1,1)=possible(best); %#ok<AGROW>
                harmonic(end+1,1)=hh; %#ok<AGROW>
            end
            if numel(selected)<o.MinFamilyHarmonics,break,end
            frequency=sum(weights(selected).*harmonic.*alpha(selected))/ ...
                sum(weights(selected).*harmonic.^2);
        end
        if numel(selected)<o.MinFamilyHarmonics,continue,end
        common=harmonic(1);
        for jj=2:numel(harmonic),common=gcd(common,harmonic(jj));end
        frequency=frequency*common; harmonic=harmonic/common;
        residual=alpha(selected)-harmonic*frequency;
        if any(abs(residual)>tolerance),continue,end
        record=template;
        record.fundamental_hz=frequency;
        record.support_harmonics=harmonic.';
        record.observed_alpha_hz=alpha(selected).';
        record.residual_hz=residual.';
        record.coherence=sqrt(weights(selected)).';
        record.weighted_rms_hz=sqrt(sum(weights(selected).*residual.^2)/sum(weights(selected)));
        record.score=sum(weights(selected))/(1+record.weighted_rms_hz/delta);
        record.divided_harmonic_gcd=common;
        record.tolerance_intersection_hz=[max((alpha(selected)-tolerance)./harmonic), ...
            min((alpha(selected)+tolerance)./harmonic)];
        families(end+1,1)=record; %#ok<AGROW>
    end
end
if isempty(families),return,end
[~,order]=sort([families.score],'descend'); families=families(order);
keep=[];
for ii=1:numel(families)
    if isempty(keep)||all(abs([families(keep).fundamental_hz]-families(ii).fundamental_hz)>delta)
        keep(end+1)=ii; %#ok<AGROW>
        if numel(keep)>=o.MaxFamilies,break,end
    end
end
families=families(keep);
end

function ref=refinePowerFrequency(iq,fs,seed,delta,o)
ref=struct('enabled',o.RefineFundamental,'seed_frequency_hz',seed, ...
    'search_limits_hz',seed+[-0.5 0.5]*delta,'used_frequency_hz',seed, ...
    'optimum_frequency_hz',seed,'boundary_optimum',false, ...
    'normalized_cyclic_power_magnitude',NaN,'seed_magnitude',NaN, ...
    'frequency_grid_hz',[],'objective_grid',[], ...
    'frequency_label',"Training power-optimized fold frequency; not a precision clock estimate.", ...
    'objective',"Magnitude of Hann-weighted DTFT of mean-subtracted |IQ|^2; training block only.", ...
    'assumptions',"A detectable cyclic-power component shares the FAM harmonic-family frequency; sub-bin optimization supplies no confidence interval.");
if ~o.RefineFundamental,return,end
power=abs(double(iq(:))).^2; N=numel(power);
window=0.5-0.5*cos(2*pi*(0:N-1).'/(N-1));
weighted=(power-mean(power)).*window;
normalization=sum(window)*mean(power);
time=(0:N-1).'/fs;
frequencies=linspace(seed-delta/2,seed+delta/2,o.RefinementGridPoints);
objective=zeros(size(frequencies));
for ii=1:numel(frequencies)
    objective(ii)=abs(sum(weighted.*exp(-2i*pi*frequencies(ii)*time)))/ ...
        max(normalization,realmin);
end
[bestValue,best]=max(objective);
ref.frequency_grid_hz=frequencies;ref.objective_grid=objective;
ref.seed_magnitude=abs(sum(weighted.*exp(-2i*pi*seed*time)))/max(normalization,realmin);
ref.boundary_optimum=best==1||best==numel(frequencies);
if ~ref.boundary_optimum
    loss=@(f)-abs(sum(weighted.*exp(-2i*pi*f*time)))/max(normalization,realmin);
    [optimum,negative]=fminbnd(loss,frequencies(best-1),frequencies(best+1), ...
        optimset('Display','off','TolX',1e-5));
    ref.optimum_frequency_hz=optimum;
    ref.normalized_cyclic_power_magnitude=-negative;
    ref.used_frequency_hz=optimum;
else
    ref.optimum_frequency_hz=frequencies(best);
    ref.normalized_cyclic_power_magnitude=bestValue;
    % An edge optimum is unresolved by this bounded search; retain the seed.
end
end

function groups=halfOrderGroups(peaks,frequency,delta,o)
alpha=[peaks.alpha_hz].'; coherence=[peaks.max_pair_coherence].';
order=round(alpha/frequency-0.5)+0.5;
residual=alpha-order*frequency;
selected=order>=0.5 & abs(residual)<=min(frequency/8,20*delta);
alpha=alpha(selected);coherence=coherence(selected);
order=order(selected);residual=residual(selected);
template=struct('offset_hz',0,'offset_tolerance_hz',delta*o.FamilyToleranceBins, ...
    'half_orders',[],'observed_alpha_hz',[],'residual_hz',[], ...
    'coherence',[],'score',0);
groups=repmat(template,0,1);remaining=true(size(alpha));
while any(remaining)
    candidates=find(remaining);
    [~,best]=max(coherence(candidates));
    anchor=candidates(best);
    chosen=remaining & abs(residual-residual(anchor))<=delta*o.FamilyToleranceBins;
    ii=find(chosen); w=coherence(ii).^2;
    record=template;record.offset_hz=sum(w.*residual(ii))/sum(w);
    record.half_orders=order(ii).';record.observed_alpha_hz=alpha(ii).';
    record.residual_hz=residual(ii).';record.coherence=coherence(ii).';
    record.score=sum(w);
    groups(end+1,1)=record; %#ok<AGROW>
    remaining(chosen)=false;
end
if ~isempty(groups)
    [~,index]=sort([groups.score],'descend');groups=groups(index);
end
end

function matches=matchFrozenFamily(peaks,family,tolerance)
a=[peaks.alpha_hz]; c=[peaks.max_pair_coherence];
h=family.support_harmonics;
matches=repmat(struct('harmonic',0,'predicted_alpha_hz',0,'observed_alpha_hz',NaN, ...
    'residual_hz',NaN,'pair_coherence',NaN,'within_training_tolerance',false),numel(h),1);
for ii=1:numel(h)
    predicted=h(ii)*family.fundamental_hz;
    [distance,index]=min(abs(a-predicted));
    matches(ii).harmonic=h(ii);matches(ii).predicted_alpha_hz=predicted;
    matches(ii).observed_alpha_hz=a(index);matches(ii).residual_hz=a(index)-predicted;
    matches(ii).pair_coherence=c(index);matches(ii).within_training_tolerance=distance<=tolerance;
end
end

function fold=foldWave(iq,fs,firstTime,frequency,o)
N=numel(iq);n=(0:N-1).';
phase=mod(mod(firstTime*frequency,1)+n*(frequency/fs),1);
bin=min(o.FoldBins,floor(phase*o.FoldBins)+1);
amplitude=abs(double(iq(:)));power=amplitude.^2;
count=accumarray(bin,1,[o.FoldBins 1],@sum,0);
sumPower=accumarray(bin,power,[o.FoldBins 1],@sum,0);
sumAmplitude=accumarray(bin,amplitude,[o.FoldBins 1],@sum,0);
chunk=min(o.TimeChunks,floor(n/N*o.TimeChunks)+1);
chunkCount=accumarray([chunk bin],1,[o.TimeChunks o.FoldBins],@sum,0);
chunkPower=accumarray([chunk bin],power,[o.TimeChunks o.FoldBins],@sum,0);
fold=struct('frequency_hz',frequency,'phase_cycles',((0:o.FoldBins-1).'+0.5)/o.FoldBins, ...
    'mean_power',sumPower./max(count,1),'mean_amplitude',sumAmplitude./max(count,1), ...
    'sample_count',count,'empty_phase_bins',sum(count==0), ...
    'chunk_mean_power',chunkPower./max(chunkCount,1),'chunk_sample_count',chunkCount, ...
    'chunk_duration_seconds',N/fs/o.TimeChunks,'first_time_seconds',firstTime, ...
    'raw_power_preview',power(1:min(N,ceil(12*fs/frequency))), ...
    'raw_preview_time_seconds',(0:min(N,ceil(12*fs/frequency))-1).'/fs);
end

function [shift,score]=displayAlign(reference,current)
r=reference-mean(reference);v=current-mean(current);
cc=real(ifft(fft(r).*conj(fft(v))));
[~,index]=max(cc);shift=index-1;
if shift>numel(r)/2,shift=shift-numel(r);end
score=vectorCorrelation(reference,circshift(current,shift));
end

function value=vectorCorrelation(a,b)
a=a(:)-mean(a);b=b(:)-mean(b);
den=norm(a)*norm(b);value=NaN;
if den>0,value=real(a'*b)/den;end
end

function makeFigures(train,summary,folds,target,o)
fig=figure('Visible','off','Color','w','Position',[50 50 1450 900]);
tiledlayout(2,2,'TileSpacing','compact');
nexttile;plot(train.nc.alpha_hz/1e3,train.nc.max_pair_coherence);hold on
family=summary.integer_harmonic_families(1);
for h=family.support_harmonics,xline(h*family.fundamental_hz/1e3,'--');end
xlabel('Cycle frequency (kHz)');ylabel('Max channel-pair correlation');
title('Training discovery; fitted integer family');grid on
nexttile;hold on
for ii=1:numel(summary.odd_half_order_groups)
    g=summary.odd_half_order_groups(ii);
    scatter(g.half_orders,g.residual_hz,25+100*g.coherence,'filled');
end
xlabel('Odd half-order relative to integer family');ylabel('Offset from half-order (Hz)');
title('Split half-orders; no packet attribution');grid on
labels=compose("block %d",1:size(folds,1));
for pp=1:2
    nexttile;hold on
    for bb=1:size(folds,1)
        plot(folds{bb,pp}.phase_cycles/(summary.refinement.used_frequency_hz/pp)*1e6, ...
            folds{bb,pp}.power_relative_to_training_mean,'DisplayName',labels(bb));
    end
    xlabel('Within frozen period (microseconds)');ylabel('Mean power / training mean');
    title(sprintf('Frozen fold: %.6f us | absolute sample-time phase', ...
        pp/summary.refinement.used_frequency_hz*1e6));
    legend('Location','best');grid on
end
sgtitle(sprintf('RF %.3f MHz | training-only periodicity model | no decoded HS packets', ...
    summary.rf_center_hz/1e6));
exportgraphics(fig,fullfile(target,'periodicity_folds.png'),'Resolution',145);close(fig);
fig=figure('Visible','off','Color','w','Position',[50 50 1400 850]);
tiledlayout(size(folds,1),2,'TileSpacing','compact');
for bb=1:size(folds,1)
    nexttile;f=folds{bb,2};
    imagesc(f.phase_cycles*2/summary.refinement.used_frequency_hz*1e6, ...
        ((0:o.TimeChunks-1)+0.5)*f.chunk_duration_seconds*1e3, ...
        f.chunk_power_relative_to_training_mean);
    trainingChunk=folds{1,2}.chunk_power_relative_to_training_mean;
    limits=[min(trainingChunk,[],'all') max(trainingChunk,[],'all')];
    if limits(2)>limits(1),clim(limits);end
    axis xy;colorbar;xlabel('Within doubled-period hypothesis (microseconds)');
    ylabel('Time within block (ms)');title(sprintf('Block %d: chunk power, unaligned',bb));
    nexttile;plot(f.raw_preview_time_seconds*1e6,f.raw_power_preview);
    xlabel('Time from block start (microseconds)');ylabel('Instantaneous |IQ|^2');
    title(sprintf('Block %d: unwarped AA subband power',bb));grid on
end
exportgraphics(fig,fullfile(target,'temporal_pulse_structure.png'),'Resolution',145);close(fig);
fig=figure('Visible','off','Color','w','Position',[50 50 1350 550]);
tiledlayout(1,2);
for pp=1:2
    nexttile;hold on
    for bb=1:size(folds,1)
        plot(folds{bb,pp}.phase_cycles,folds{bb,pp}.amplitude_relative_to_training_rms, ...
            'DisplayName',sprintf('block %d',bb));
    end
    xlabel('Cycle phase');ylabel('Mean |IQ| / training RMS');
    title(sprintf('Unaligned envelope fold | period multiplier %d',pp));
    legend('Location','best');grid on
end
sgtitle('Frozen frequency and absolute sample-time phase; amplitude envelope');
exportgraphics(fig,fullfile(target,'envelope_folds.png'),'Resolution',145);close(fig);
if o.DisplayAlign
    fig=figure('Visible','off','Color','w','Position',[50 50 1350 550]);
    tiledlayout(1,2);
    for pp=1:2
        nexttile;hold on
        for bb=1:size(folds,1)
            f=folds{bb,pp};
            plot(f.phase_cycles,circshift(f.power_relative_to_training_mean, ...
                f.display_only_shift_bins),'DisplayName', ...
                sprintf('block %d, shift %+d bins',bb,f.display_only_shift_bins));
        end
        xlabel('Cycle phase');ylabel('Mean power / training mean');
        title(sprintf('DISPLAY ONLY alignment | period multiplier %d',pp));
        legend('Location','best');grid on
    end
    sgtitle('Per-block display shifts use assessment waveform; not frozen validation');
    exportgraphics(fig,fullfile(target,'display_only_aligned_folds.png'),'Resolution',145);close(fig);
end
end

function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
