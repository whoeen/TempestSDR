function result = analyzeIqBlock(iq, device, cfg, outputDir, notePath)
%ANALYZEIQBLOCK Baseline diagnostics without identifying the emitter by power.
arguments
    iq (:,1) {mustBeNumeric}
    device (1,1) struct
    cfg (1,1) struct
    outputDir (1,1) string
    notePath (1,1) string
end
fs = device.fs_hz;
x = double(iq);
result = struct('diagnostics',diagnoseIq(x),'duration_s',numel(x)/fs, ...
    'samples_per_prior_line',fs/device.prior_line_hz, ...
    'samples_per_raster_column',fs/device.prior_line_hz/device.raster_columns, ...
    'raster_column_time_s',1/device.prior_line_hz/device.raster_columns, ...
    'prior_line_time_s',1/device.prior_line_hz, ...
    'prior_frame_time_s',device.prior_frame_samples/fs, ...
    'prior_frame_hz',fs/device.prior_frame_samples);
disp(struct('device',device.title,'preliminary',result));
appendResearchNote(notePath,'raw_diagnostics',result);
amplitude = abs(x);
threshold = sampleQuantile(amplitude,cfg.phase_amplitude_quantile);
valid = amplitude>threshold;
deltaPhase = angle(x(2:end).*conj(x(1:end-1)));
validPair = valid(2:end)&valid(1:end-1);
deltaPhase(~validPair) = NaN;
result.phase = struct('amplitude_mask_threshold_counts',threshold, ...
    'amplitude_mask_quantile',cfg.phase_amplitude_quantile, ...
    'retained_adjacent_pair_fraction',mean(validPair), ...
    'median_adjacent_phase_rad',median(deltaPhase,'omitnan'), ...
    'circular_resultant_adjacent',abs(mean(exp(1j*deltaPhase),'omitnan')), ...
    'status','Mixture phase increments; not verified DSI phase or calibrated PM. Amplitude mask is a heuristic, not a noise-calibrated probability.');
plotN = min(numel(x),round(8*fs/device.prior_line_hz));
f = figure('Visible',cfg.figure_visible,'Position',[50 50 1200 760]);
tiledlayout(f,3,1);
nexttile; plot((0:plotN-1)/fs*1e6,real(x(1:plotN))); hold on;
plot((0:plotN-1)/fs*1e6,imag(x(1:plotN))); hold off;
xlabel('Time (us)'); ylabel('ADC counts'); legend('I','Q'); title(device.title,'Interpreter','none');
nexttile; plot((0:plotN-1)/fs*1e6,amplitude(1:plotN));
xlabel('Time (us)'); ylabel('|IQ| (ADC counts)'); title('Observed envelope, before conditioning');
nexttile; plot((1:plotN-1)/fs*1e6,deltaPhase(1:plotN-1),'.');
xlabel('Time (us)'); ylabel('Adjacent phase (rad)'); ylim([-pi pi]);
title('Relative mixture phase; low-amplitude sample pairs masked');
exportgraphics(f,fullfile(outputDir,'01_iq_am_phase.png'),Resolution=140); close(f);
appendResearchNote(notePath,'relative_phase',result.phase);
segment = min(2^14,2^floor(log2(numel(x))));
window = periodicHann(segment); overlap = floor(segment/2);
[psd,freq,psdMeta] = estimateWelchPsd(x,window,overlap,segment,fs,'centered');
[psdCentered,~] = estimateWelchPsd(x-mean(x),window,overlap,segment,fs,'centered');
df = fs/segment;
enbwHz = fs*sum(window.^2)/sum(window)^2;
result.spectrum = struct('method',psdMeta.implementation,'window','periodic Hann', ...
    'segment_samples',segment,'overlap_samples',overlap,'fft_samples',segment, ...
    'bin_spacing_hz',df,'enbw_hz',enbwHz,'window_time_s',segment/fs, ...
    'frequency_axis','signed baseband Hz, RF = stated center + baseband (IQ convention assumed)', ...
    'psd_units','ADC-count squared per Hz','integrated_psd_counts2',sum(psd)*df, ...
    'time_mean_power_counts2',mean(abs(x).^2), ...
    'parseval_relative_difference',sum(psd)*df/mean(abs(x).^2)-1, ...
    'spectral_flatness',exp(mean(log(max(psd,realmin))))/mean(psd));
peakIndices = find(psd(2:end-1)>psd(1:end-2)&psd(2:end-1)>=psd(3:end))+1;
[~,order] = sort(psd(peakIndices),'descend');
peakIndices = peakIndices(order(1:min(10,numel(order))));
result.spectrum.strong_peaks = struct('baseband_hz',num2cell(freq(peakIndices)), ...
    'psd_counts2_per_hz',num2cell(psd(peakIndices)));
writetable(table(freq,psd,psdCentered,'VariableNames', ...
    {'baseband_hz','raw_psd_counts2_per_hz','dc_removed_psd_counts2_per_hz'}), ...
    fullfile(outputDir,'02_welch_psd.csv'));
f = figure('Visible',cfg.figure_visible,'Position',[50 50 1200 500]);
plot(freq/1e6,powerDb(max(psd,realmin))); hold on;
plot(freq/1e6,powerDb(max(psdCentered,realmin))); hold off; grid on;
xlabel('Signed baseband frequency (MHz)'); ylabel('PSD (dB re ADC-count^2/Hz)');
legend('Raw IQ','Mean DC removed diagnostic'); title(device.title,'Interpreter','none');
exportgraphics(f,fullfile(outputDir,'02_welch_psd.png'),Resolution=140); close(f);
appendResearchNote(notePath,'welch_psd',result.spectrum);

% Explicit row-scale windows. No zero padding is represented as resolution.
lineSamples = fs/device.prior_line_hz;
windowLengths = max(16,round(lineSamples*[0.25 1 16]));
tf = struct([]);
f = figure('Visible',cfg.figure_visible,'Position',[50 50 1250 950]);
tiledlayout(f,3,1);
for k = 1:numel(windowLengths)
    lengthWindow = min(windowLengths(k),floor(numel(x)/2));
    hop = max(1,round(lengthWindow/4));
    count = min(numel(x),lengthWindow+(cfg.max_stft_frames-1)*hop);
    w = periodicHann(lengthWindow);
    nfft = 2^nextpow2(lengthWindow);
    [p,sf,st,tfMeta] = estimateSpectrogram(x(1:count),w,lengthWindow-hop,nfft,fs);
    tf(k).implementation = tfMeta.implementation;
    tf(k).window_samples = lengthWindow;
    tf(k).window_s = lengthWindow/fs;
    tf(k).hop_samples = hop;
    tf(k).fft_samples = nfft;
    tf(k).bin_spacing_hz = fs/nfft;
    tf(k).enbw_hz = fs*sum(w.^2)/sum(w)^2;
    tf(k).window_resolution_scale_hz = fs/lengthWindow;
    tf(k).time_frames = numel(st);
    tf(k).used_samples = count;
    tf(k).window_in_prior_lines = lengthWindow/lineSamples;
    nexttile; imagesc(st*1e6,sf/1e6,powerDb(max(p,realmin))); axis xy;
    xlabel('Time (us)'); ylabel('Baseband (MHz)'); colorbar;
    title(sprintf('Hann %.3g us = %.3g prior lines; ENBW %.3g kHz', ...
        lengthWindow/fs*1e6,lengthWindow/lineSamples,tf(k).enbw_hz/1e3));
end
exportgraphics(f,fullfile(outputDir,'03_multiscale_stft.png'),Resolution=140); close(f);
result.stft = tf;
appendResearchNote(notePath,'multiscale_stft',struct('windows',tf, ...
    'units','PSD in ADC-count squared/Hz','caveat', ...
    'Quarter-row, row and 16-row windows cannot resolve frame-rate sidebands. Columns separated across rows are not contiguous RF samples.'));

% Envelope periodicities are candidates, not emitter identities.
envelope = amplitude-mean(amplitude);
[ep,ef] = estimateWelchPsd(envelope,window,overlap,segment,fs,'onesided');
lineLagRange = round(fs./[200e3 20e3]);
maxLag = min(numel(x)-1,lineLagRange(2));
acFftLength = 2^nextpow2(2*numel(envelope)-1);
acAll = real(ifft(abs(fft(envelope,acFftLength)).^2));
ac = acAll(1:maxLag+1)/max(acAll(1),eps);
lags = (0:maxLag).';
keep = lags>=lineLagRange(1) & lags<=maxLag;
ac = ac(keep); lags = lags(keep);
locations = find(ac(2:end-1)>ac(1:end-2)&ac(2:end-1)>=ac(3:end))+1;
[~,order] = sort(ac(locations),'descend');
locations = locations(order(1:min(12,numel(order))));
result.periodicity = struct('envelope_line_candidates', ...
    struct('lag_samples',num2cell(lags(locations)), ...
    'candidate_hz',num2cell(fs./lags(locations)), ...
    'envelope_autocorrelation',num2cell(ac(locations))), ...
    'search_hz',[20e3 200e3], ...
    'caveat','Autocorrelation maxima include harmonics, subharmonics and clutter. No unique row clock is established.');
alpha = device.prior_line_hz*[0.99 0.995 1 1.005 1.01];
probeLag = round(lineSamples);
cyclicValues = zeros(numel(alpha),1);
cyclicInput = x(1:end-probeLag).*conj(x(1+probeLag:end));
time = ((0:numel(cyclicInput)-1).'+probeLag/2)/fs;
denom = sqrt(mean(abs(x(1:end-probeLag)).^2)*mean(abs(x(1+probeLag:end)).^2));
for k=1:numel(alpha)
    cyclicValues(k) = abs(mean(cyclicInput.*exp(-1j*2*pi*alpha(k)*time)))/max(denom,eps);
end
result.periodicity.cyclic_probe = struct('definition', ...
    'abs mean{x[n] conj(x[n+lag]) exp(-j2pi alpha (n+lag/2)/Fs)} normalized by RMS powers', ...
    'alpha_hz',alpha,'lag_samples',probeLag,'normalized_magnitude',cyclicValues, ...
    'observation_s',numel(cyclicInput)/fs,'nominal_alpha_resolution_hz',fs/numel(cyclicInput));
f = figure('Visible',cfg.figure_visible,'Position',[50 50 1200 700]);
tiledlayout(f,2,1); nexttile;
plot(ef/1e3,powerDb(max(ep,realmin))); xlim([0 300]); grid on;
xlabel('Envelope frequency (kHz)'); ylabel('PSD (dB re count^2/Hz)');
nexttile; plot(lags/fs*1e6,ac); grid on;
xlabel('Envelope lag (us)'); ylabel('Normalized autocorrelation');
exportgraphics(f,fullfile(outputDir,'04_envelope_candidates.png'),Resolution=140); close(f);
appendResearchNote(notePath,'periodicity_candidates',result.periodicity);
end
