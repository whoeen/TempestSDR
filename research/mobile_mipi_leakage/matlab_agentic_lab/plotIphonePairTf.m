function manifest = plotIphonePairTf(rawCell, correctedCell, fsHz, outputDir, metadata, options)
%PLOTIPHONEPAIRTF Bounded toolbox TF and phase controls for an RF capture pair.
% rawCell/correctedCell are two cells of complex vectors on the SAME uniform
% canonical grid. rawCell may already contain interpolation: describe it in
% metadata.raw_description. This function neither estimates nor fits CFO/time.
% fsHz is a scalar or two sample rates in Hz. outputDir must not exist.
% metadata.nominal_fc_hz (two values) is required. Optional native_cell and
% native_fs_hz add a native-rate STFT control. Record upstream processing in metadata.
% options is an optional struct. Defaults select nominal RF 130 MHz, resample
% 1/8 with explicit Kaiser FIR, and bound FSST/CWT to 8192 output samples.
% TF axes after correction use nominal RF coordinates under caller polarity.

if nargin < 6, options = struct; end
if nargin < 5, metadata = struct; end
assert(iscell(rawCell) && iscell(correctedCell) && ...
    numel(rawCell)==2 && numel(correctedCell)==2, 'Expected two input cells.');
assert(isstruct(metadata) && isfield(metadata,'nominal_fc_hz'), ...
    'metadata.nominal_fc_hz is required.');
fcHz = double(metadata.nominal_fc_hz(:).');
assert(numel(fcHz)==2 && all(isfinite(fcHz)), 'Invalid nominal RF centers.');
fsHz = expandTwo(fsHz);
assert(all(isfinite(fsHz) & fsHz>0), 'Invalid sample rates.');
opts = defaults(options);
assert(~isfolder(outputDir) && ~isfile(outputDir), 'Refusing to overwrite outputDir.');
for name = {'stft','fsst','resample','hann','freqz'}
    assert(exist(name{1},'file')~=0, 'Required Signal Processing function missing: %s',name{1});
end
native = {}; nativeFs = [];
if isfield(metadata,'native_cell')
    native = metadata.native_cell;
    assert(iscell(native) && numel(native)==2 && isfield(metadata,'native_fs_hz'), ...
        'Native controls require two cells and native_fs_hz.');
    nativeFs = expandTwo(metadata.native_fs_hz);
    assert(all(isfinite(nativeFs) & nativeFs>0),'Invalid native sample rates.');
    metadata = rmfield(metadata,'native_cell'); % Never serialize raw vectors.
end
if ~isfield(metadata,'raw_description')
    metadata.raw_description = 'Canonical fixed-prior grid control; preprocessing supplied by caller';
end
if ~isfield(metadata,'corrected_description')
    metadata.corrected_description = 'Canonical time/CFO-corrected input supplied by caller';
end
mkdir(outputDir);
manifest = struct('status','running','created_utc',char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss''Z''')),'matlab_version',version, ...
    'toolboxes',ver,'options',opts,'input_metadata',metadata);
manifest.interpretation = [ ...
    "No parameter fitting, image-reference scoring, or RF alignment is done here."; ...
    "Corrected RF axes are nominal coordinates under the supplied IQ polarity; hardware polarity/calibration is not inferred."; ...
    "STFT uses complex two-sided PSD in input-unit squared/Hz, with no factor of two."; ...
    "FSST/CWT magnitude scales are transform-specific and are not STFT PSD."; ...
    "Synchrosqueezing does not create measured bandwidth; narrow subband plots discard RF content."; ...
    "Phase gate is an amplitude heuristic, not a probability/confidence estimate."; ...
    "Time mapping plus CFO changes relative phase; these plots cannot identify sample-clock error from CFO."; ...
    "Native and canonical chunk starts need not be the same physical instant; see caller metadata." ];
writeJson(fullfile(outputDir,'manifest.json'),manifest);

bands = cell(1,2);
for b = 1:2
    raw = finiteColumn(rawCell{b}); corr = finiteColumn(correctedCell{b});
    assert(numel(raw)==numel(corr),'Before/after vectors must share coordinates and length.');
    limit = min([numel(raw),opts.MaxNativeSamples]);
    if ~isempty(native)
        nat = finiteColumn(native{b});
        limit = min(limit,floor(numel(nat)*fsHz(b)/nativeFs(b)));
    end
    assert(limit>=4096,'Insufficient bounded TF input.');
    raw = raw(1:limit); corr = corr(1:limit);
    band = struct('nominal_fc_hz',fcHz(b),'canonical_fs_hz',fsHz(b), ...
        'input_samples',numel(rawCell{b}),'analyzed_samples',limit, ...
        'analyzed_duration_s',limit/fsHz(b));
    band.raw_stft = makeStft(raw,fsHz(b),opts.NativeWindow,opts.NativeHop,opts.NativeFft,0);
    band.corrected_stft = makeStft(corr,fsHz(b),opts.NativeWindow,opts.NativeHop,opts.NativeFft,0);
    if ~isempty(native)
        nNative = min(numel(nat),floor(limit/fsHz(b)*nativeFs(b)));
        nativeWindow = max(8,round(opts.NativeWindow*nativeFs(b)/fsHz(b)));
        nativeHop = max(1,round(opts.NativeHop*nativeFs(b)/fsHz(b)));
        band.native_stft = makeStft(nat(1:nNative),nativeFs(b),nativeWindow,nativeHop, ...
            2^nextpow2(max(nativeWindow,opts.NativeFft)),0);
        band.native_fs_hz = nativeFs(b);
        band.native_analyzed_samples = nNative;
    end
    mixHz = opts.SubbandRfHz-fcHz(b);
    fsSmall = fsHz(b)/opts.Decimation;
    assert(abs(mixHz)+fsSmall/2<fsHz(b)/2, ...
        'Selected subband crosses input Nyquist; choose a valid SubbandRfHz.');
    localTime = (0:limit-1).'/fsHz(b);
    carrier = exp(-1j*2*pi*mixHz*localTime);
    [z0,fir] = resample(raw.*carrier,1,opts.Decimation,opts.ResampleN,opts.ResampleBeta);
    z1 = resample(corr.*carrier,1,opts.Decimation,fir);
    guard = ceil((numel(fir)-1)/(2*opts.Decimation))+2;
    assert(numel(z0)>2*guard+1024,'Insufficient data after FIR transient guard.');
    valid = (guard+1):(numel(z0)-guard);
    count = min(opts.MaxSubbandSamples,numel(valid));
    first = valid(1)+floor((numel(valid)-count)/2);
    select = first:(first+count-1);
    z0 = z0(select); z1 = z1(select);
    startS = (first-1)/fsSmall;
    band.subband = struct('nominal_rf_center_hz',opts.SubbandRfHz, ...
        'mixed_by_hz',mixHz,'fs_hz',fsSmall,'samples',count, ...
        'start_relative_to_canonical_chunk_s',startS,'duration_s',count/fsSmall, ...
        'display_offset_limit_hz',opts.DisplayNyquistFraction*fsSmall/2, ...
        'resample_p',1,'resample_q',opts.Decimation,'fir_order',numel(fir)-1, ...
        'fir_coefficients',fir(:).','fir_n',opts.ResampleN,'fir_beta',opts.ResampleBeta, ...
        'discarded_output_edge_samples_each_side',guard, ...
        'boundary','resample zero extension; FIR support guard discarded; no detrend or DC subtraction');
    band.antialias_test = testResample(fsHz(b),opts,fir,guard);
    [response,responseHz] = freqz(fir,1,4096,fsHz(b));
    band.subband.fir_response_hz = responseHz;
    band.subband.fir_response_magnitude = single(abs(response));
    band.raw_subband_stft = makeStft(z0,fsSmall,opts.SubbandWindow, ...
        opts.SubbandHop,opts.SubbandWindow,startS);
    band.corrected_subband_stft = makeStft(z1,fsSmall,opts.SubbandWindow, ...
        opts.SubbandHop,opts.SubbandWindow,startS);
    band.raw_fsst = makeFsst(z0,fsSmall,opts.SubbandWindow,startS,opts.DisplayTimePool);
    band.corrected_fsst = makeFsst(z1,fsSmall,opts.SubbandWindow,startS,opts.DisplayTimePool);
    band.phase = makePhase(z0,z1,fsSmall,startS,opts.PhaseGateQuantile);
    band.cwt_status = 'disabled_by_options';
    if opts.EnableWavelet
        if exist('cwt','file')==0
            band.cwt_status = 'unavailable';
        else
            try
                band.raw_cwt = makeCwt(z0,fsSmall,startS,opts);
                band.corrected_cwt = makeCwt(z1,fsSmall,startS,opts);
                band.cwt_status = 'success';
            catch err
                band.cwt_status = 'failed';
                band.cwt_error_identifier = err.identifier;
                band.cwt_error_message = err.message;
            end
        end
    end
    bands{b} = band;
end

% Freeze display scales across both frequency bands and both processing states.
psdMax = 0; subPsdMax = 0; fsstMax = 0; cwtMax = 0;
for b=1:2
    v = bands{b};
    psdMax = max([psdMax,max(v.raw_stft.psd,[],'all'),max(v.corrected_stft.psd,[],'all')]);
    if isfield(v,'native_stft'), psdMax=max(psdMax,max(v.native_stft.psd,[],'all')); end
    subPsdMax=max([subPsdMax,max(v.raw_subband_stft.psd,[],'all'),max(v.corrected_subband_stft.psd,[],'all')]);
    fsstMax=max([fsstMax,max(v.raw_fsst.magnitude,[],'all'),max(v.corrected_fsst.magnitude,[],'all')]);
    if strcmp(v.cwt_status,'success')
        cwtMax=max([cwtMax,max(v.raw_cwt.magnitude,[],'all','omitnan'),max(v.corrected_cwt.magnitude,[],'all','omitnan')]);
    end
end
scales=struct('stft_psd_limits_db',10*log10(max(double(psdMax),realmin))+[-opts.DynamicRangeDb 0], ...
    'subband_stft_psd_limits_db',10*log10(max(double(subPsdMax),realmin))+[-opts.DynamicRangeDb 0], ...
    'fsst_magnitude_reference',double(fsstMax),'cwt_magnitude_reference',double(cwtMax), ...
    'magnitude_limits_db',[-opts.DynamicRangeDb 0]);
manifest.scales=scales;
metrics=struct([]);
for b=1:2
    band = bands{b}; prefix = sprintf('band_fc%03d',round(fcHz(b)/1e6));
    plotBand(band,prefix,outputDir,scales,opts);
    save(fullfile(outputDir,[prefix '_tf_numeric.mat']),'band','scales','-v7.3');
    pstate=band.phase;
    phaseTable=table(pstate.time_s(:),pstate.raw_amplitude(:),pstate.corrected_amplitude(:), ...
        pstate.raw_relative_phase_rad(:),pstate.corrected_relative_phase_rad(:), ...
        pstate.change_phase_rad(:),pstate.valid_raw(:),pstate.valid_corrected(:),pstate.valid_pair(:), ...
        'VariableNames',{'relative_time_s','raw_amplitude','corrected_amplitude','raw_relative_phase_rad', ...
        'corrected_relative_phase_rad','change_phase_rad','valid_raw','valid_corrected','valid_pair'});
    writetable(phaseTable,fullfile(outputDir,[prefix '_phase.csv']));
    metrics(b).nominal_fc_hz=fcHz(b);
    metrics(b).canonical_fs_hz=fsHz(b);
    metrics(b).stft_window_us=band.raw_stft.window_s*1e6;
    metrics(b).stft_enbw_hz=band.raw_stft.enbw_hz;
    metrics(b).stft_fft_spacing_hz=band.raw_stft.fft_spacing_hz;
    metrics(b).subband_fs_hz=band.subband.fs_hz;
    metrics(b).subband_duration_us=band.subband.duration_s*1e6;
    metrics(b).fsst_window_us=band.raw_fsst.window_s*1e6;
    metrics(b).fsst_enbw_hz=band.raw_fsst.enbw_hz;
    metrics(b).fsst_fft_spacing_hz=band.raw_fsst.fft_spacing_hz;
    metrics(b).phase_gate_amplitude=pstate.gate_amplitude;
    metrics(b).phase_valid_pair_fraction=mean(pstate.valid_pair);
    metrics(b).cwt_status=band.cwt_status;
    metrics(b).antialias_passed=band.antialias_test.passed;
    metrics(b).antialias_stopband_amplitude=band.antialias_test.stopband_amplitude;
    manifest.bands(b)=struct('nominal_fc_hz',fcHz(b),'analyzed_samples',band.analyzed_samples, ...
        'antialias_test',band.antialias_test,'cwt_status',band.cwt_status,'cwt_error_message','');
    if isfield(band,'cwt_error_message')
        manifest.bands(b).cwt_error_message=band.cwt_error_message;
    end
end
writetable(struct2table(metrics),fullfile(outputDir,'tf_metrics.csv'));
manifest.metrics=metrics;
manifest.status='complete';
manifest.wavelet_complete=all(cellfun(@(v)strcmp(v.cwt_status,'success'),bands));
writeJson(fullfile(outputDir,'manifest.json'),manifest);
fid=fopen(fullfile(outputDir,'README.md'),'w','n','UTF-8');
assert(fid>=0,'Cannot write README.'); cleaner=onCleanup(@()fclose(fid));
fprintf(fid,['# Bounded iPhone pair TF controls\n\n' ...
    'Read manifest.json and tf_metrics.csv before comparing colors. Native ADC, canonical prior-grid control, ' ...
    'and corrected input are explicitly separate. Nominal RF axes follow caller IQ polarity metadata.\n\n' ...
    'STFT colors are input-unit squared/Hz (complex two-sided PSD); FSST and CWT colors are ' ...
    'their own magnitude relative to a shared maximum across both bands/states. Do not compare their color values.\n\n' ...
    'FSST/CWT use an anti-aliased narrow subband and a bounded central excerpt. Only the STFT retains the original ' ...
    'measured digital band. No extra RF bandwidth is synthesized by squeezing. The white CWT lines are the cone of influence; ' ...
    'coefficients nearer zero offset than these lines can be edge-affected.\n\n' ...
    'Phase is wrapped relative measured RF phase after the declared mixer; it is not reconstructed RGB or an ' ...
    'absolute physical phase. The configured raw-amplitude quantile freezes a gate for both states (not a confidence level). ' ...
    'Time correction can change the samples being compared, so phase change alone is not a CFO or clock estimate.\n\n' ...
    'Numeric MATs contain TF magnitudes/PSD, phase vectors, filters, and parameters, without full raw capture copies. ' ...
    'Each PNG uses identical shared scale limits for its transform across both bands and states.\n']);
end

function opts=defaults(user)
opts=struct('MaxNativeSamples',131072,'NativeWindow',1024,'NativeHop',256,'NativeFft',2048, ...
    'SubbandRfHz',130e6,'Decimation',8,'ResampleN',32,'ResampleBeta',8, ...
    'MaxSubbandSamples',8192,'SubbandWindow',256,'SubbandHop',64,'DisplayTimePool',8, ...
    'DisplayNyquistFraction',0.8,'PhaseGateQuantile',0.25,'PhasePlotSamples',1024, ...
    'DynamicRangeDb',60,'EnableWavelet',true,'CwtVoices',12,'CwtTimeBandwidth',60);
assert(isstruct(user) && isscalar(user),'options must be a scalar struct.');
names=fieldnames(user);
for k=1:numel(names)
    assert(isfield(opts,names{k}),'Unknown option: %s',names{k});
    opts.(names{k})=user.(names{k});
end
integers={'MaxNativeSamples','NativeWindow','NativeHop','NativeFft','Decimation','ResampleN', ...
    'MaxSubbandSamples','SubbandWindow','SubbandHop','DisplayTimePool','PhasePlotSamples','CwtVoices'};
for k=1:numel(integers)
    x=opts.(integers{k}); assert(isscalar(x)&&isfinite(x)&&x>=1&&x==round(x),'Invalid integer option.');
end
assert(opts.Decimation>=2 && opts.NativeFft>=opts.NativeWindow && opts.NativeHop<=opts.NativeWindow);
assert(opts.SubbandHop<=opts.SubbandWindow && opts.SubbandWindow>=8);
assert(opts.MaxNativeSamples<=2^20 && opts.MaxSubbandSamples<=16384,'Bounded helper memory limits exceeded.');
assert(opts.DisplayNyquistFraction>0 && opts.DisplayNyquistFraction<1);
assert(opts.PhaseGateQuantile>=0 && opts.PhaseGateQuantile<1);
end

function x=expandTwo(x)
x=double(x(:).'); if isscalar(x),x=[x x];end
assert(numel(x)==2,'Expected a scalar or two-element vector.');
end
function x=finiteColumn(x)
assert(isnumeric(x)&&isvector(x)&&~isempty(x),'Input must be numeric vector.');
x=double(x(:)); assert(all(isfinite(x)),'Input contains nonfinite values.');
x=complex(real(x),imag(x));
end
function result=makeStft(x,fs,nw,hop,nfft,startS)
w=hann(nw,'periodic');
[s,f,t]=stft(x,fs,'Window',w,'OverlapLength',nw-hop,'FFTLength',nfft,'FrequencyRange','centered');
[f,order]=sort(f(:));
result=struct('frequency_offset_hz',f,'time_s',double(t(:).')+startS, ...
    'psd',single(abs(s(order,:)).^2/(fs*sum(w.^2))), ...
    'window','periodic Hann','window_samples',nw,'hop_samples',hop,'fft_length',nfft, ...
    'window_s',nw/fs,'hop_s',hop/fs,'enbw_hz',fs*sum(w.^2)/sum(w)^2, ...
    'fft_spacing_hz',fs/nfft,'units','input-unit squared/Hz; two sided, no factor 2');
end
function result=makeFsst(x,fs,nw,startS,pool)
w=hann(nw,'periodic');
[s,f,t]=fsst(double(x),fs,w);
[f,order]=sort(f(:));
[m,t]=poolTime(abs(s(order,:)),double(t(:).'),pool);
result=struct('frequency_offset_hz',f,'time_s',t+startS,'magnitude',single(m), ...
    'window','periodic Hann','window_samples',nw,'hop_samples',1,'fft_length',nw, ...
    'window_s',nw/fs,'hop_s',1/fs,'enbw_hz',fs*sum(w.^2)/sum(w)^2, ...
    'fft_spacing_hz',fs/nw,'display_time_pool_samples',pool, ...
    'display_pool','arithmetic mean of coefficient magnitudes; not input downsampling', ...
    'units','FSST coefficient magnitude; transform specific, not PSD');
end
function result=makeCwt(x,fs,startS,opts)
fmin=32*fs/numel(x); fmax=opts.DisplayNyquistFraction*fs/2;
assert(fmin<fmax,'CWT input too short for chosen frequency range.');
[c,f,coi]=cwt(double(x),'morse',fs,'TimeBandwidth',opts.CwtTimeBandwidth, ...
    'VoicesPerOctave',opts.CwtVoices,'FrequencyLimits',[fmin fmax],'Boundary','zeropad');
assert(ndims(c)==3 && size(c,3)==2,'Expected complex CWT positive/negative pages.');
f=[f(:);-f(:)]; mag=[abs(c(:,:,1));abs(c(:,:,2))];
[f,order]=sort(f); mag=mag(order,:);
% Insert an explicit missing DC gap so surf never bridges unanalysed scales.
idx=find(f<0,1,'last'); f=[f(1:idx);0;f(idx+1:end)];
mag=[mag(1:idx,:);nan(1,size(mag,2));mag(idx+1:end,:)];
t=(0:numel(x)-1)/fs;
[mag,t]=poolTime(mag,t,opts.DisplayTimePool);
[coi,~]=poolTime(double(coi(:).'),(0:numel(x)-1)/fs,opts.DisplayTimePool);
result=struct('frequency_offset_hz',f,'time_s',t+startS,'magnitude',single(mag), ...
    'cone_of_influence_hz',coi,'requested_frequency_limits_hz',[fmin fmax], ...
    'wavelet','analytic Morse','gamma',3,'time_bandwidth',opts.CwtTimeBandwidth, ...
    'voices_per_octave',opts.CwtVoices,'boundary','zeropad','display_time_pool_samples',opts.DisplayTimePool, ...
    'units','L1-normalized CWT coefficient magnitude; not PSD');
end
function [pooled,t]=poolTime(matrix,t,pool)
count=floor(size(matrix,2)/pool); assert(count>0,'Display pool too large.');
pooled=reshape(mean(reshape(matrix(:,1:count*pool),size(matrix,1),pool,count),2),size(matrix,1),count);
t=mean(reshape(t(1:count*pool),pool,count),1);
end
function result=makePhase(raw,corr,fs,startS,q)
a0=abs(raw); a1=abs(corr); sorted=sort(a0); index=1+(numel(sorted)-1)*q;
lo=floor(index); hi=ceil(index); threshold=sorted(lo)+(index-lo)*(sorted(hi)-sorted(lo));
valid0=a0>max(threshold,0); valid1=a1>max(threshold,0); valid=valid0&valid1;
ref=find(valid0,1,'first');
if isempty(ref), refPhase=0; else, refPhase=angle(raw(ref)); end
p0=angle(raw*exp(-1j*refPhase)); p1=angle(corr*exp(-1j*refPhase)); pc=angle(corr.*conj(raw));
p0(~valid0)=NaN; p1(~valid1)=NaN; pc(~valid)=NaN;
result=struct('time_s',(0:numel(raw)-1).'/fs+startS,'raw_amplitude',single(a0), ...
    'corrected_amplitude',single(a1),'raw_relative_phase_rad',single(p0), ...
    'corrected_relative_phase_rad',single(p1),'change_phase_rad',single(pc), ...
    'valid_raw',valid0,'valid_corrected',valid1,'valid_pair',valid, ...
    'gate_raw_quantile',q,'gate_amplitude',threshold,'reference_index',ref, ...
    'reference_phase_rad',refPhase,'reference','first raw sample above frozen raw-amplitude gate; same reference for corrected');
end
function result=testResample(fs,opts,b,guard)
% Deterministic signed complex tone probes verify gain, time origin, and AA.
q=opts.Decimation; n=(0:4096*q-1).'; fsOut=fs/q;
passHz=0.2*fsOut; stopHz=0.75*fsOut;
y=resample(exp(1j*2*pi*passHz*n/fs),1,q,b);
stop=resample(exp(1j*2*pi*stopHz*n/fs),1,q,b);
keep=(guard+1):(numel(y)-guard); t=(keep(:)-1)/fsOut;
ratio=y(keep).*exp(-1j*2*pi*passHz*t);
gain=mean(ratio); ripple=max(abs(ratio-gain));
stopAmplitude=sqrt(mean(abs(stop(keep)).^2));
result=struct('pass_frequency_hz',passHz,'stop_frequency_hz',stopHz, ...
    'pass_gain',abs(gain),'pass_phase_rad',angle(gain),'pass_ripple',ripple, ...
    'stopband_amplitude',stopAmplitude,'passband_gain_tolerance',1e-3, ...
    'pass_phase_tolerance_rad',1e-6,'stopband_amplitude_limit',1e-3);
result.passed=abs(abs(gain)-1)<1e-3 && abs(angle(gain))<1e-6 && ripple<1e-6 && stopAmplitude<1e-3;
assert(result.passed,'Anti-alias/timing synthetic control failed.');
end

function plotBand(band,prefix,out,scales,opts)
fc=band.nominal_fc_hz;
fig=figure('Visible','off','Color','w','Position',[100 100 1250 900]);
cleanup=onCleanup(@()close(fig));
if isfield(band,'native_stft'), rows=3; else,rows=2;end
lay=tiledlayout(fig,rows,1,'TileSpacing','compact');
if rows==3
    drawTf(nexttile(lay),band.native_stft,fc,scales.stft_psd_limits_db,1,'PSD', ...
        'Native-rate control (no resampling; see preprocessing metadata)',Inf);
end
drawTf(nexttile(lay),band.raw_stft,fc,scales.stft_psd_limits_db,1,'PSD','Canonical prior-grid control (already interpolated)',Inf);
drawTf(nexttile(lay),band.corrected_stft,fc,scales.stft_psd_limits_db,1,'PSD','Canonical timing + CFO correction',Inf);
title(lay,sprintf('fc %.0f MHz | same PSD scale | nominal RF coordinate under assumed IQ polarity',fc/1e6));
exportgraphics(fig,fullfile(out,[prefix '_wide_stft.png']),'Resolution',150); clear cleanup

fig=figure('Visible','off','Color','w','Position',[100 100 1350 850]); cleanup=onCleanup(@()close(fig));
lay=tiledlayout(fig,2,2,'TileSpacing','compact'); rf=band.subband.nominal_rf_center_hz; lim=band.subband.display_offset_limit_hz;
drawTf(nexttile(lay),band.raw_subband_stft,rf,scales.subband_stft_psd_limits_db,1,'PSD','STFT: prior-grid control',lim);
drawTf(nexttile(lay),band.corrected_subband_stft,rf,scales.subband_stft_psd_limits_db,1,'PSD','STFT: corrected',lim);
drawTf(nexttile(lay),band.raw_fsst,rf,scales.magnitude_limits_db,scales.fsst_magnitude_reference,'magnitude','FSST: prior-grid control',lim);
drawTf(nexttile(lay),band.corrected_fsst,rf,scales.magnitude_limits_db,scales.fsst_magnitude_reference,'magnitude','FSST: corrected',lim);
title(lay,sprintf('fc %.0f MHz | AA subband at %.0f MHz | STFT/FSST have different units',fc/1e6,rf/1e6));
exportgraphics(fig,fullfile(out,[prefix '_subband_tf.png']),'Resolution',150); clear cleanup

if strcmp(band.cwt_status,'success')
    fig=figure('Visible','off','Color','w','Position',[100 100 1250 750]); cleanup=onCleanup(@()close(fig));
    lay=tiledlayout(fig,2,1,'TileSpacing','compact');
    drawCwt(nexttile(lay),band.raw_cwt,rf,scales,'CWT: prior-grid control');
    drawCwt(nexttile(lay),band.corrected_cwt,rf,scales,'CWT: corrected');
    title(lay,sprintf('fc %.0f MHz | Morse CWT, signed offsets | white lines: cone of influence',fc/1e6));
    exportgraphics(fig,fullfile(out,[prefix '_cwt.png']),'Resolution',150); clear cleanup
end
fig=figure('Visible','off','Color','w','Position',[100 100 1250 900]); cleanup=onCleanup(@()close(fig));
lay=tiledlayout(fig,3,1,'TileSpacing','compact'); ph=band.phase;
start=floor((numel(ph.time_s)-min(opts.PhasePlotSamples,numel(ph.time_s)))/2)+1;
i=start:(start+min(opts.PhasePlotSamples,numel(ph.time_s))-1); t=ph.time_s(i)*1e6;
ax=nexttile(lay);plot(ax,t,[ph.raw_amplitude(i) ph.corrected_amplitude(i)]);hold(ax,'on');
yline(ax,ph.gate_amplitude,'k:');ylabel(ax,'Input amplitude');legend(ax,'Prior grid','Corrected','Frozen raw gate');grid(ax,'on');
ax=nexttile(lay);plot(ax,t,[ph.raw_relative_phase_rad(i) ph.corrected_relative_phase_rad(i)],'.','MarkerSize',3);
ylim(ax,[-pi pi]);ylabel(ax,'Relative phase (rad)');legend(ax,'Prior grid','Corrected');grid(ax,'on');
ax=nexttile(lay);plot(ax,t,ph.change_phase_rad(i),'.','MarkerSize',3);ylim(ax,[-pi pi]);
ylabel(ax,'angle(corrected conj(raw)) (rad)');xlabel(ax,'Time since canonical chunk start (us)');grid(ax,'on');
title(lay,sprintf('fc %.0f MHz | subband %.0f MHz | wrapped phase, amplitude gate (not confidence)',fc/1e6,rf/1e6));
exportgraphics(fig,fullfile(out,[prefix '_phase.png']),'Resolution',150); clear cleanup
end
function drawTf(ax,data,fc,limits,ref,kind,label,offsetLimit)
if strcmp(kind,'PSD'), db=10*log10(max(double(data.psd),realmin)); units='dB(input-unit^2/Hz)';
else, db=20*log10(max(double(data.magnitude),realmin)/max(ref,realmin));units='dB magnitude / shared transform maximum';end
imagesc(ax,data.time_s*1e6,(data.frequency_offset_hz+fc)/1e6,db);axis(ax,'xy');
if isfinite(offsetLimit),ylim(ax,(fc+[-offsetLimit offsetLimit])/1e6);end
clim(ax,limits);colormap(ax,turbo(256));cb=colorbar(ax);cb.Label.String=units;
xlabel(ax,'Time since input chunk start (us)');ylabel(ax,'Nominal RF coordinate (MHz)');
title(ax,sprintf('%s | window %.3f us; ENBW %.3f kHz',label,data.window_s*1e6,data.enbw_hz/1e3),'Interpreter','none');
end
function drawCwt(ax,data,rf,scales,label)
db=20*log10(max(double(data.magnitude),realmin)/max(scales.cwt_magnitude_reference,realmin));
db(isnan(data.magnitude))=NaN;
surf(ax,data.time_s*1e6,(rf+data.frequency_offset_hz)/1e6,db,'EdgeColor','none');view(ax,2);axis(ax,'tight');
clim(ax,scales.magnitude_limits_db);colormap(ax,turbo(256));hold(ax,'on');
plot3(ax,data.time_s*1e6,(rf+data.cone_of_influence_hz)/1e6,ones(size(data.time_s)),'w--');
plot3(ax,data.time_s*1e6,(rf-data.cone_of_influence_hz)/1e6,ones(size(data.time_s)),'w--');
ylim(ax,(rf+[-max(abs(data.frequency_offset_hz)) max(abs(data.frequency_offset_hz))])/1e6);
cb=colorbar(ax);cb.Label.String='dB magnitude / shared CWT maximum';
xlabel(ax,'Time since canonical chunk start (us)');ylabel(ax,'Nominal RF coordinate (MHz)');title(ax,label);
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot write JSON.');cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
