function runIphone100Fam26(stage, centersMHz)
%RUNIPHONE100FAM26 Actual native and AA-subband FAM, no raster time warping.
if nargin<1,stage="coarse";end
if nargin<2,centersMHz=106;end
lab=fileparts(mfilename('fullpath'));
addpath(lab,fullfile(lab,'signal_processing'));
out=fullfile(lab,'results','iphone6_fc100_fam_20261026');
base=load(fullfile(out,'preflight.mat'),'x','dc','fsHz','fcHz','metrics');
fsHz=base.fsHz;
switch string(stage)
    case "coarse"
        verifyFam26(fullfile(out,'verification'));
        destination=fullfile(out,'coarse');
        assert(~isfolder(destination),'Refuse overwrite');mkdir(destination);
        options=struct('M',64,'L',16,'P',65536, ...
            'AlphaLimitsHz',[0 1e6],'ConjugateAlphaLimitsHz',[0 1e6], ...
            'FrequencyLimitsHz',[-57e6 57e6],'PowerFloorRelativeDb',-45, ...
            'TopCandidates',128,'TopPerPair',4,'ExcludeNcAlphaHz',2*fsHz/2^20, ...
            'HeatmapAlphaBins',1024);
        fprintf('Native coarse FAM start: no time warp, no amplitude demodulation.\n');
        tic
        result=famCycleScout26(base.x,fsHz,options);
        seconds=toc;
        context=struct('stage','native coarse discovery','nominal_center_hz',100e6, ...
            'first_sample_zero_based',base.metrics.first_sample_zero_based, ...
            'sample_rate_hz',fsHz,'elapsed_seconds',seconds, ...
            'dc_real_counts',real(base.dc),'dc_imag_counts',imag(base.dc), ...
            'time_warp_applied',false,'frame_folding_applied',false, ...
            'packet_identified',false);
        save(fullfile(destination,'fam.mat'),'result','context','-v7.3');
        exportResult(result,context,destination);
        fprintf('Native coarse complete: %.2fs. Leading NC alpha=%.6fHz, RF=%.6fMHz, C=%.6f\n', ...
            seconds,result.nc.separated_profile_peaks(1).alpha_hz, ...
            (1e8+result.nc.separated_profile_peaks(1).argmax_f_hz)/1e6, ...
            result.nc.separated_profile_peaks(1).max_pair_coherence);
    case "refined"
        [capture,resolution]=resolveIphoneSweepCapture(100);
        q=16;M=32;L=8;P=131072;need=(P-1)*L+M;
        options=struct('M',M,'L',L,'P',P,'AlphaLimitsHz',[0 500e3], ...
            'ConjugateAlphaLimitsHz',[-6e6 6e6], ...
            'FrequencyLimitsHz',[-3e6 3e6],'PowerFloorRelativeDb',-45, ...
            'TopCandidates',128,'TopPerPair',4,'ExcludeNcAlphaHz',4*(fsHz/q)/2^20, ...
            'HeatmapAlphaBins',1024);
        starts=[0.2 1.1 1.8];
        for centerMHz=centersMHz(:).'
            for block=1:numel(starts)
                tag=sprintf('rf%g_block%d',centerMHz,block);
                destination=fullfile(out,'refined',tag);
                assert(~isfolder(destination),'Refuse overwrite');mkdir(destination);
                firstSample=round(starts(block)*fsHz);
                [iq,front]=readSubband(capture,firstSample,need,q,fsHz, ...
                    centerMHz*1e6-1e8,base.dc);
                fprintf('Refined FAM %s: t=%.3fs, N=%d, rate=%.6fMS/s.\n', ...
                    tag,starts(block),numel(iq),fsHz/q/1e6);
                tic
                result=famCycleScout26(iq,fsHz/q,options);
                seconds=toc;
                context=struct('stage','AA subband unwarped FAM', ...
                    'nominal_center_hz',centerMHz*1e6,'block',block, ...
                    'first_sample_zero_based',firstSample,'sample_rate_hz',fsHz/q, ...
                    'elapsed_seconds',seconds,'front_end',front,'capture',resolution, ...
                    'selected_on_discovery_block',true,'time_warp_applied',false, ...
                    'frame_folding_applied',false,'packet_identified',false);
                save(fullfile(destination,'fam.mat'),'result','context','-v7.3');
                save(fullfile(destination,'subband.mat'),'iq','front','-v7.3');
                exportResult(result,context,destination);
                fprintf('%s complete %.1fs. NC alpha=%.6fHz C=%.5f; conjugate alpha=%.6fHz C=%.5f\n', ...
                    tag,seconds,result.nc.separated_profile_peaks(1).alpha_hz, ...
                    result.nc.separated_profile_peaks(1).max_pair_coherence, ...
                    result.conjugate.separated_profile_peaks(1).alpha_hz, ...
                    result.conjugate.separated_profile_peaks(1).max_pair_coherence);
                clear result iq
            end
        end
    otherwise
        error('Unknown stage');
end
fprintf('FAM stage %s completed.\n',string(stage));
end

function [iq,info]=readSubband(capture,firstSample,need,q,fsHz,offsetHz,dc)
guard=8192;
assert(mod(guard,q)==0 && firstSample>=guard);
nativeCount=need*q+2*guard;
[x,readInfo]=readRisIqBlock(capture,firstSample-guard,nativeCount);
x=double(conj(x))-double(dc);
n=(firstSample-guard+(0:numel(x)-1)).';
x=x.*exp(-2i*pi*offsetHz*n/fsHz);
[y,b]=resample(x,1,q,32,8);
take=guard/q+(1:need);
iq=y(take);
[h,f]=freqz(b,1,32768,fsHz);
newFs=fsHz/q;
pass=f<=3e6;stop=f>=newFs-3e6;
assert(max(abs(h(stop)))<1e-3,'Insufficient AA stopband');
info=struct('read',readInfo,'native_fs_hz',fsHz,'output_fs_hz',newFs, ...
    'mixer_offset_hz',offsetHz,'mixer_reference','absolute original sample index', ...
    'decimation',q,'resample_n',32,'resample_beta',8,'native_guard_each_side',guard, ...
    'retained_samples',need,'retained_original_first_sample',firstSample, ...
    'fir_coefficients',b,'passband_min_magnitude',min(abs(h(pass))), ...
    'passband_max_magnitude',max(abs(h(pass))), ...
    'alias_stopband_max_magnitude',max(abs(h(stop))), ...
    'output_description','AA resampling only; no fitted clock/CFO/row correction');
end

function exportResult(result,context,destination)
summary=struct('status','complete','context',context,'metadata',result.metadata, ...
    'psd',result.psd,'nc',smallPart(result.nc), ...
    'conjugate',smallPart(result.conjugate), ...
    'interpretation','Exploratory pair cyclic correlation; not packet decoding or calibrated significance.');
writeJson(fullfile(destination,'summary.json'),jsonSafe(summary));
for name=["nc","conjugate"]
    r=result.(name);
    writetable(struct2table(r.separated_profile_peaks),fullfile(destination,name+"_peaks.csv"));
end
fig=figure('Visible','off','Color','w','Position',[50 50 1450 950]);
tiledlayout(2,2,'TileSpacing','compact');
for k=1:2
    if k==1,r=result.nc;label="Non-conjugate";else,r=result.conjugate;label="Conjugate";end
    nexttile((k-1)*2+1);
    if k==1,y=(r.heatmap.f_hz+context.nominal_center_hz)/1e6;
    else,y=r.heatmap.f_hz/1e6;end
    imagesc(r.heatmap.alpha_hz/1e3,y,r.heatmap.max_pair_coherence);
    axis xy;colorbar;clim([0 max(0.02,max(r.heatmap.max_pair_coherence,[],'all'))]);
    xlabel('Cycle frequency alpha (kHz)');
    if k==1,ylabel('Nominal RF pair center (MHz)');else,ylabel('Half-difference pair coordinate f (MHz)');end
    title(label+" FAM | max smoothed pair correlation");
    nexttile((k-1)*2+2);
    plot(r.alpha_hz/1e3,r.max_pair_coherence);grid on
    xlabel('Cycle frequency alpha (kHz)');ylabel('max_f |pair cyclic correlation|');
    if k==1
        xline(112802.551754/1e3,'--r','prior row candidate');
    end
    title(label+" cyclic-domain profile");
end
sgtitle(sprintf('%s | RF center %.4fMHz | T=%.3fms, alpha grid %.4fHz', ...
    context.stage,context.nominal_center_hz/1e6, ...
    result.metadata.alpha_fft_time_seconds*1e3,result.metadata.alpha_bin_spacing_hz));
exportgraphics(fig,fullfile(destination,'fam_maps.png'),'Resolution',145);close(fig);
end

function r=smallPart(part)
r=struct('stats',part.stats,'separated_profile_peaks',part.separated_profile_peaks, ...
    'top_candidates',part.top_candidates);
end
function out=jsonSafe(in)
if isstruct(in)
    out=in;fields=fieldnames(in);
    for k=1:numel(in),for j=1:numel(fields)
        out(k).(fields{j})=jsonSafe(in(k).(fields{j}));
    end,end
elseif iscell(in),out=cellfun(@jsonSafe,in,'UniformOutput',false);
elseif isnumeric(in)&&~isreal(in),out=struct('real',real(in),'imag',imag(in));
else,out=in;end
end
function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
