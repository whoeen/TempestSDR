function result = measureFrameCandidates(filePath, device, cfg, outputDir)
%MEASUREFRAMECANDIDATES Bounded streaming envelope integration for slow timing.
%   Integrate-and-dump is explicitly a rectangular prefilter. Residual aliases
%   can produce false candidates; no output is declared the display refresh.
arguments
    filePath (1,1) string
    device (1,1) struct
    cfg (1,1) struct
    outputDir (1,1) string
end
fs = device.fs_hz;
binSamples = max(1,round(fs/4000));
envelopeFs = fs/binSamples;
fileInfo = dir(filePath);
binCount = min(round(0.4*envelopeFs),floor((fileInfo.bytes/4-cfg.first_sample)/binSamples));
binsPerBlock = max(1,floor(2^20/binSamples));
amplitude = zeros(binCount,1);
for firstBin=0:binsPerBlock:binCount-1
    count = min(binsPerBlock,binCount-firstBin);
    iq = readRisIqBlock(filePath,cfg.first_sample+firstBin*binSamples,count*binSamples);
    amplitude(firstBin+(1:count)) = mean(reshape(double(abs(iq)),binSamples,count),1).';
end
time = ((0:binCount-1).'+0.5)*binSamples/fs;
zeroMean = amplitude-mean(amplitude);
segment = min(1024,2^floor(log2(binCount)));
[psd,frequency,meta] = estimateWelchPsd(zeroMean,periodicHann(segment),floor(segment/2),segment,envelopeFs,"onesided");
lengthFft = 2^nextpow2(2*binCount-1);
ac = real(ifft(abs(fft(zeroMean,lengthFft)).^2));
ac = ac/max(ac(1),eps);
lagLow = ceil(envelopeFs/120);
lagHigh = min(floor(envelopeFs/30),binCount-2);
lag = (lagLow:lagHigh).';
values = ac(lag+1);
peaks = find(values(2:end-1)>values(1:end-2)&values(2:end-1)>=values(3:end))+1;
[~,order] = sort(values(peaks),'descend');
peaks = peaks(order(1:min(8,numel(order))));
candidateLag = double(lag(peaks));
for k=1:numel(candidateLag)
    center = candidateLag(k)+1;
    denominator = ac(center-1)-2*ac(center)+ac(center+1);
    if abs(denominator)>eps
        candidateLag(k) = candidateLag(k)+max(-0.5,min(0.5, ...
            0.5*(ac(center-1)-ac(center+1))/denominator));
    end
end
result = struct('input_first_sample',cfg.first_sample, ...
    'input_samples',binCount*binSamples,'duration_s',binCount*binSamples/fs, ...
    'envelope_bin_samples',binSamples,'envelope_fs_hz',envelopeFs, ...
    'method','rectangular integration of |IQ| then candidate autocorrelation', ...
    'candidate_hz',envelopeFs./candidateLag,'candidate_lag_bins',candidateLag, ...
    'candidate_autocorrelation',values(peaks),'welch',meta, ...
    'prior_frame_hz',fs/device.prior_frame_samples, ...
    'caveat','Finite data, rectangular-prefilter aliases, harmonics and interference can mimic frame peaks; validate with raster drift and independent acquisitions.');
writetable(table(time,amplitude,'VariableNames',{'time_s','mean_amplitude_counts'}),fullfile(outputDir,'06_slow_envelope.csv'));
f = figure('Visible',cfg.figure_visible,'Position',[50 50 1200 750]);
tiledlayout(f,2,1);
nexttile;
plot(time,amplitude);
xlabel('Time (s)');
ylabel('Bin mean |IQ| (ADC counts)');
title('0.4 s bounded stream, rectangular envelope integration');
nexttile;
plot(frequency,powerDb(psd));
xlim([0 300]);
xlabel('Envelope frequency (Hz)');
ylabel('PSD (dB re count^2/Hz)');
title('Slow periodicity candidates; aliases/harmonics remain possible');
exportgraphics(f,fullfile(outputDir,'06_frame_candidates.png'),Resolution=140);
close(f);
end
