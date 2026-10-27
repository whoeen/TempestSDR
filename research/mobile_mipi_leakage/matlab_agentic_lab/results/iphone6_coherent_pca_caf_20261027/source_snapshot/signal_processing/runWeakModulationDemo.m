function result = runWeakModulationDemo(outputDir, figureVisible)
%RUNWEAKMODULATIONDEMO Known-ground-truth weak AM/PM in strong RF clutter.
%   It demonstrates identifiability limitations and coherent gain, not measured
%   smartphone performance. All signal/carrier frequencies are known here.
arguments
    outputDir (1,1) string
    figureVisible (1,1) string = "off"
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end
randomState = rng();
cleanup = onCleanup(@() rng(randomState));
rng(70261,'twister');
fs = 200e3;
frameHz = 100;
frames = 32;
samplesPerFrame = fs/frameHz;
sampleCount = samplesPerFrame*frames;
t = (0:sampleCount-1).'/fs;
am = 0.02*sin(2*pi*200*t) + 0.01*cos(2*pi*300*t);
pm = 0.015*sin(2*pi*500*t);
desiredCarrier = 30e3;
clutterCarrier = -50e3;
desired = (1+am).*exp(1j*(2*pi*desiredCarrier*t+pm));
clutter = 20*exp(1j*(2*pi*clutterCarrier*t+0.13*floor(t*frameHz)));
noise = 0.3/sqrt(2)*(randn(sampleCount,1)+1j*randn(sampleCount,1));
observed = desired+clutter+noise;
decimation = 20;
[filtered,filterInfo] = conditionIq(observed,fs,OffsetHz=desiredCarrier,Decimation=decimation);
[truth,~] = conditionIq(desired,fs,OffsetHz=desiredCarrier,Decimation=decimation);
fsOut = fs/decimation;
perFrame = samplesPerFrame/decimation;
folded = reshape(filtered,perFrame,frames);
foldedTruth = reshape(truth,perFrame,frames);
checkpoints = [1 4 16 32];
records = repmat(struct('frames',0,'modulation_error_snr_db',0, ...
    'am_correlation',0,'pm_correlation',0),numel(checkpoints),1);
% Exclude FIR startup and every phase-jumping clutter frame boundary.
valid = (1:perFrame).'>12 & (1:perFrame).'<perFrame-12;
coherentCurves = complex(zeros(perFrame,numel(checkpoints)));
truthCurve = mean(foldedTruth,2);
for k=1:numel(checkpoints)
    count = checkpoints(k);
    estimate = mean(folded(:,1:count),2);
    expected = mean(foldedTruth(:,1:count),2);
    carrier = mean(expected(valid));
    modulationPower = mean(abs(expected(valid)-carrier).^2);
    errorPower = mean(abs(estimate(valid)-expected(valid)).^2);
    records(k).frames = count;
    records(k).modulation_error_snr_db = powerDb(modulationPower/max(errorPower,eps));
    records(k).am_correlation = correlation(abs(estimate(valid)),abs(expected(valid)));
    records(k).pm_correlation = correlation(angle(estimate(valid)),angle(expected(valid)));
    coherentCurves(:,k) = estimate;
end
matrix = reshape(observed,samplesPerFrame,frames);
[u,s,v] = svd(matrix,'econ');
rankOne = u(:,1)*s(1,1)*v(:,1)';
singularEnergy = diag(s).^2;
clutterAgreement = abs(sum(rankOne(:).*conj(clutter)))/(norm(rankOne(:))*norm(clutter));
desiredAgreement = abs(sum(rankOne(:).*conj(desired)))/(norm(rankOne(:))*norm(desired));
result = struct('kind','synthetic with known truth; no smartphone performance claim', ...
    'rng_seed',70261,'fs_hz',fs,'frame_hz',frameHz,'frames',frames, ...
    'sample_count',sampleCount,'desired_carrier_hz',desiredCarrier, ...
    'clutter_carrier_hz',clutterCarrier,'clutter_amplitude',20, ...
    'am_sinusoid_peak_depths',[0.02 0.01],'pm_peak_rad',0.015, ...
    'complex_noise_rms',0.3, ...
    'clutter_to_desired_total_power_db',powerDb(mean(abs(clutter).^2)/mean(abs(desired).^2)), ...
    'rank1_energy_fraction',singularEnergy(1)/sum(singularEnergy), ...
    'rank1_clutter_correlation',clutterAgreement,'rank1_desired_correlation',desiredAgreement, ...
    'filter',filterInfo,'checkpoints',records, ...
    'caveat','Carrier and repeat period are known in this simulation. Real data require identification and held-out validation.');
writetable(struct2table(records),fullfile(outputDir,'synthetic_progression.csv'));
writeJsonFile(fullfile(outputDir,'synthetic_metrics.json'),result);
f = figure('Visible',figureVisible,'Position',[50 50 1300 900]);
tiledlayout(f,2,2);
window = periodicHann(4096);
[psd,freq] = estimateWelchPsd(observed,window,2048,4096,fs,"centered");
nexttile;
plot(freq/1e3,powerDb(psd));
xlabel('Baseband frequency (kHz)');
ylabel('PSD (dB re amplitude^2/Hz)');
title('Strong clutter and weak modulation carrier');
nexttile;
semilogy(singularEnergy/sum(singularEnergy),'o-');
xlabel('Singular component');
ylabel('Energy fraction');
title('Largest singular component follows clutter');
nexttile;
plot((0:perFrame-1)/fsOut*1e3,abs(coherentCurves));
hold on;
plot((0:perFrame-1)/fsOut*1e3,abs(truthCurve),'k--','LineWidth',2);
hold off;
xlabel('Within-frame time (ms)');
ylabel('AM amplitude');
title('Known carrier: coherent average progression');
legend('P1','P4','P16','P32','Truth');
nexttile;
plot((0:perFrame-1)/fsOut*1e3,angle(coherentCurves));
hold on;
plot((0:perFrame-1)/fsOut*1e3,angle(truthCurve),'k--','LineWidth',2);
hold off;
xlabel('Within-frame time (ms)');
ylabel('Relative phase (rad)');
title('PM after complex downconversion');
exportgraphics(f,fullfile(outputDir,'synthetic_weak_am_pm.png'),Resolution=140);
close(f);
save(fullfile(outputDir,'synthetic_arrays.mat'),'observed','desired','clutter', ...
    'filtered','truth','coherentCurves','fs','fsOut','result','-v7');
end

function value = correlation(a,b)
a = double(a(:))-mean(double(a(:)));
b = double(b(:))-mean(double(b(:)));
value = sum(a.*b)/max(norm(a)*norm(b),eps);
end
