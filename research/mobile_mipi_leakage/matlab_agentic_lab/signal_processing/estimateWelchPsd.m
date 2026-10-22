function [powerDensity, frequency, metadata] = estimateWelchPsd(x, window, overlap, nfft, fs, range)
%ESTIMATEWELCHPSD Toolbox Welch or explicitly labeled base MATLAB fallback.
%   PSD integrates to window-weighted mean power. No implicit DC removal.
arguments
    x (:,1) {mustBeNumeric}
    window (:,1) double
    overlap (1,1) double {mustBeInteger,mustBeNonnegative}
    nfft (1,1) double {mustBeInteger,mustBePositive}
    fs (1,1) double {mustBePositive}
    range (1,1) string {mustBeMember(range,["centered","onesided"])} = "centered"
end
assert(nfft>=numel(window),'mobile:ShortFFT','FFT must cover the entire window.');
assert(overlap<numel(window),'mobile:BadOverlap','Overlap must be shorter than the window.');
assert(numel(x)>=numel(window),'mobile:ShortPSD','Need at least one complete segment.');
metadata = struct('implementation','pwelch','nfft',nfft,'fs_hz',fs, ...
    'window_samples',numel(window),'overlap_samples',overlap, ...
    'enbw_hz',fs*sum(window.^2)/sum(window)^2,'frequency_range',range, ...
    'scaling','abs(FFT(window*x))^2 / (Fs*sum(window^2)); average segments');
if exist('pwelch','file')>0
    [powerDensity,frequency] = pwelch(x,window,overlap,nfft,fs,char(range));
    return
end
metadata.implementation = 'base MATLAB explicit Welch fallback';
hop = numel(window) - overlap;
starts = 1:hop:numel(x)-numel(window)+1;
powerDensity = zeros(nfft,1);
for k=1:numel(starts)
    sampleIndices = starts(k)+(0:numel(window)-1);
    spectrum = fft(double(x(sampleIndices)).*window,nfft);
    powerDensity = powerDensity + abs(spectrum).^2;
end
powerDensity = powerDensity/(numel(starts)*fs*sum(window.^2));
metadata.segment_count = numel(starts);
if range=="centered"
    powerDensity = fftshift(powerDensity);
    frequency = (-floor(nfft/2):ceil(nfft/2)-1).'*fs/nfft;
else
    assert(isreal(x),'mobile:ComplexOneSided','Complex IQ requires a two-sided spectrum.');
    powerDensity = powerDensity(1:floor(nfft/2)+1);
    if mod(nfft,2)==0
        powerDensity(2:end-1) = 2*powerDensity(2:end-1);
    else
        powerDensity(2:end) = 2*powerDensity(2:end);
    end
    frequency = (0:floor(nfft/2)).'*fs/nfft;
end
end
