function result = compareParametricPsd(iq, fs, outputDir, figureVisible)
%COMPAREPARAMETRICPSD AR order sweep with chronological held-out prediction.
%   The AR model describes the observed mixture, not a decoded screen source.
%   Uses built-in Burg when present, otherwise explicit Yule-Walker equations.
arguments
    iq (:,1) {mustBeNumeric}
    fs (1,1) double {mustBePositive}
    outputDir (1,1) string
    figureVisible (1,1) string = "off"
end
count = min(numel(iq),65536);
x = double(iq(1:count));
split = floor(count/2);
trainingMean = mean(x(1:split));
training = x(1:split)-trainingMean;
validation = x(split+1:end)-trainingMean;
orders = [4 8 16 32];
nfft = 8192;
frequency = (-nfft/2:nfft/2-1).'*fs/nfft;
models = repmat(struct('order',0,'method',"",'innovation_variance',0, ...
    'holdout_error_power_ratio',0,'coefficients_real',[],'coefficients_imag',[]),numel(orders),1);
spectra = zeros(nfft,numel(orders));
for k=1:numel(orders)
    order = orders(k);
    if exist('arburg','file')>0
        [a,innovation] = arburg(training,order);
        method = "Signal Processing Toolbox Burg";
    else
        transformLength = 2^nextpow2(2*numel(training)-1);
        covariance = ifft(abs(fft(training,transformLength)).^2)/numel(training);
        covariance(1) = real(covariance(1));
        matrix = toeplitz(covariance(1:order));
        ridge = max(real(covariance(1)),eps)*1e-9;
        a = [1;-(matrix+ridge*eye(order))\covariance(2:order+1)].';
        residual = filter(a,1,training);
        innovation = mean(abs(residual(order+1:end)).^2);
        method = "base MATLAB regularized Yule-Walker; ridge=1e-9*r0";
    end
    heldoutResidual = filter(a,1,validation);
    heldoutRatio = mean(abs(heldoutResidual(order+1:end)).^2)/mean(abs(validation(order+1:end)).^2);
    spectra(:,k) = fftshift(innovation./max(abs(fft(a,nfft)).'.^2,realmin))/fs;
    models(k) = struct('order',order,'method',method,'innovation_variance',innovation, ...
        'holdout_error_power_ratio',heldoutRatio,'coefficients_real',real(a), ...
        'coefficients_imag',imag(a));
end
[welch,welchFrequency,welchMetadata] = estimateWelchPsd(x-trainingMean,periodicHann(8192),4096,8192,fs,"centered");
result = struct('training_samples',split,'validation_samples',numel(validation), ...
    'fs_hz',fs,'mean_removed_real',real(trainingMean),'mean_removed_imag',imag(trainingMean), ...
    'models',models,'welch',welchMetadata, ...
    'interpretation','Compare held-out errors and order stability; sharp AR peaks do not demonstrate screen information or true super-resolution.');
f = figure('Visible',figureVisible,'Position',[50 50 1200 550]);
plot(welchFrequency/1e6,powerDb(welch),'k','LineWidth',1.4);
hold on;
plot(frequency/1e6,powerDb(spectra));
hold off;
xlabel('Baseband frequency (MHz)');
ylabel('PSD (dB re ADC-count^2/Hz)');
legend('Welch','AR4','AR8','AR16','AR32');
title('Observed-mixture AR comparison, training mean removed');
exportgraphics(f,fullfile(outputDir,'05_parametric_psd.png'),Resolution=140);
close(f);
writeJsonFile(fullfile(outputDir,'05_parametric_models.json'),result);
end
