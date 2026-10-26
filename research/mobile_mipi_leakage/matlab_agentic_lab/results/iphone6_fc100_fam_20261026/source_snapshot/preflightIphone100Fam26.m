function preflightIphone100Fam26
%PREFLIGHTIPHONE100FAM26 Read an immutable native IQ block and record quality.
lab=fileparts(mfilename('fullpath'));
addpath(lab,fullfile(lab,'signal_processing'));
out=fullfile(lab,'results','iphone6_fc100_fam_20261026');
if ~isfolder(out),mkdir(out);end
assert(~isfile(fullfile(out,'preflight.mat')),'Refuse overwrite');
fsHz=124082800;fcHz=100e6;
M=64;L=16;P=65536;
n=(P-1)*L+M;
firstSample=round(0.2*fsHz);
[capture,resolution]=resolveIphoneSweepCapture(100);
[x,readInfo]=readRisIqBlock(capture,firstSample,n);
clipFraction=mean(abs(real(x))>=32767 | abs(imag(x))>=32767);
x=conj(x);
dc=mean(x);
x=x-dc;
[pxx,f]=pwelch(x,hann(8192,'periodic'),4096,8192,fsHz,'centered');
flatness=exp(mean(log(max(pxx,realmin('single')))))/mean(pxx);
rmsCounts=sqrt(mean(abs(x).^2));
[peakPower,ix]=max(pxx);
metrics=struct('status','complete','sampling_rate_hz',fsHz,'rf_center_hz',fcHz, ...
    'native_samples',n,'first_sample_zero_based',firstSample, ...
    'duration_s',n/fsHz,'dc_real_counts',real(dc),'dc_imag_counts',imag(dc), ...
    'rms_counts',rmsCounts,'clipping_fraction',clipFraction, ...
    'spectral_flatness',flatness,'peak_rf_hz',fcHz+f(ix), ...
    'peak_to_median_psd_db',pow2db(peakPower/median(pxx)), ...
    'peak_to_median_is_snr',false,'missing_samples_detectable_from_header',false, ...
    'polarity','conjugated read I+jQ; RF sign hypothesis I-jQ', ...
    'dc_policy','fixed mean of discovery block; same subtraction in later blocks', ...
    'time_warp_applied',false,'frame_folding_applied',false, ...
    'resolution',resolution,'read',readInfo);
save(fullfile(out,'preflight.mat'),'x','dc','pxx','f','fsHz','fcHz','metrics');
writeJson(fullfile(out,'preflight.json'),metrics);
fig=figure('Visible','off','Color','w','Position',[100 100 1250 500]);
plot((fcHz+f)/1e6,pow2db(pxx));grid on
xlabel('Nominal RF (MHz), I-jQ convention');ylabel('PSD (dB ADC counts^2/Hz)');
title(sprintf('100 MHz capture | native IQ, t=0.2s | Fs=%.4f MS/s',fsHz/1e6));
exportgraphics(fig,fullfile(out,'native_psd.png'),'Resolution',140);close(fig);
fprintf('Preflight complete: samples=%d, duration=%.6fms, RMS=%.3f counts, clip=%.6g, flatness=%.6g\n', ...
    n,n/fsHz*1e3,rmsCounts,clipFraction,flatness);
fprintf('Strongest Welch PSD RF=%.6fMHz, peak/median=%.3fdB (NOT SNR)\n', ...
    metrics.peak_rf_hz/1e6,metrics.peak_to_median_psd_db);
end
function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
