function [powerDensity, frequency, time, metadata] = estimateSpectrogram(x, window, overlap, nfft, fs)
%ESTIMATESPECTROGRAM Centered PSD spectrogram with a base MATLAB fallback.
arguments
    x (:,1) {mustBeNumeric}
    window (:,1) double
    overlap (1,1) double {mustBeInteger,mustBeNonnegative}
    nfft (1,1) double {mustBeInteger,mustBePositive}
    fs (1,1) double {mustBePositive}
end
assert(nfft>=numel(window),'mobile:ShortFFT','FFT must cover the entire window.');
assert(overlap<numel(window),'mobile:BadOverlap','Overlap must be shorter than the window.');
metadata = struct('implementation','spectrogram','nfft',nfft,'fs_hz',fs, ...
    'window_samples',numel(window),'overlap_samples',overlap, ...
    'enbw_hz',fs*sum(window.^2)/sum(window)^2, ...
    'scaling','abs(FFT(window*x))^2 / (Fs*sum(window^2)); no averaging across time');
if exist('spectrogram','file')>0
    [~,frequency,time,powerDensity] = spectrogram(x,window,overlap,nfft,fs,'centered','psd');
    return
end
metadata.implementation = 'base MATLAB explicit STFT PSD fallback';
hop = numel(window) - overlap;
starts = 1:hop:numel(x)-numel(window)+1;
powerDensity = zeros(nfft,numel(starts));
for k=1:numel(starts)
    sampleIndices = starts(k)+(0:numel(window)-1);
    spectrum = fft(double(x(sampleIndices)).*window,nfft);
    powerDensity(:,k) = fftshift(abs(spectrum).^2)/(fs*sum(window.^2));
end
frequency = (-floor(nfft/2):ceil(nfft/2)-1).'*fs/nfft;
time = ((starts-1)+(numel(window)-1)/2)/fs;
end
