function report = auditIphoneSingle26(options)
%AUDITIPHONESINGLE26 Single-frame control for Oct26 conditional pilot means.
% The timing/CFO model is inherited without refitting. Delay/phase and the
% tone mask use frame0 only and stay frozen on frame72. No image synthesis.
% B's global translation is exp(+j*2*pi*D*(u+k)); integer D cycles are placed
% by FFT indices, so the time-domain factor only needs frac(D)*(u+k).
arguments
    options.RootFolder (1,1) string = ""
    options.OutputFolder (1,1) string = ""
end
lab = fileparts(mfilename('fullpath'));
addpath(fullfile(lab,'signal_processing'));
root = options.RootFolder;
if strlength(root)==0
    root = fullfile(lab,'results','iphone6_cfo_timing_20261026');
end
out = options.OutputFolder;
if strlength(out)==0, out=fullfile(root,'single_frame_control'); end
assert(~isfolder(out)&&~isfile(out),'single26:Exists','Refuse overwrite: %s',out);
timing = fullfile(root,'timing');
loaded = load(fullfile(timing,'model.mat'),'model');
model = loaded.model;
pathA = fullfile(timing,'band_fc100.mat');
pathB = fullfile(timing,'band_fc160.mat');
a = load(pathA,'singleTrain','singleTest','meta');
b = load(pathB,'singleTrain','singleTest','meta');
meanPath = fullfile(root,'stitch','overview.json');
published = jsondecode(fileread(meanPath));
assert(strcmp(published.status,'complete'),'single26:MeanIncomplete','Mean-stitch results incomplete.');
meanA = matfile(pathA); meanB = matfile(pathB);
n = size(a.singleTrain,1);
armNames = string(model.arm_names);
D = model.carrier_translation_cycles_100_to160(:);
T = model.canonical_period_seconds;
kTrain = model.training_frames_zero_based(1);
kTest = model.heldout_frames_zero_based(1);
assert(n==2^21 && size(a.singleTrain,2)==4 && numel(D)==4,'single26:Grid','Unexpected input grid.');
assert(isequal(size(a.singleTrain),size(a.singleTest),size(b.singleTrain),size(b.singleTest)), ...
    'single26:Shape','Single-frame shapes differ.');
assert(isequal(a.meta.training_frames_zero_based,b.meta.training_frames_zero_based) && ...
    isequal(a.meta.heldout_frames_zero_based,b.meta.heldout_frames_zero_based), ...
    'single26:Frames','Band frame identities differ.');
assert(kTrain==0 && kTest==72,'single26:FrameIdentity','This control is declared for frame0 versus72.');
assert(abs(T-published.period_seconds)<1e-14,'single26:Period','Published mean period differs.');
u = (0:n-1)'/n;
k = (ceil(3e6*T):floor(9e6*T))';
ia = k+n/2+1;
mkdir(out);
report = struct('status','running','training_frame_zero_based',kTrain, ...
    'assessment_frame_zero_based',kTest,'frame_average_count',1, ...
    'compared_mean_frame_count',numel(model.training_frames_zero_based), ...
    'comparison_mean_training_frames',model.training_frames_zero_based, ...
    'comparison_mean_assessment_frames',model.heldout_frames_zero_based, ...
    'nominal_rf_window_hz',[103e6 109e6],'period_seconds',T,'input_grid_samples',n, ...
    'translation_formula','B(u,k)*exp(+j*2*pi*D*(u+k)); integer part placed by Fourier indices; fraction includes k.', ...
    'frequency_timing_parameters_refitted',false,'assessment_parameters_refitted',false, ...
    'mean_reference_json',meanPath,'records',{{}}, ...
    'interpretation','Single versus conditional 8-frame means separates averaging sensitivity only conditionally. One assessment frame is not the same statistic as an 8-frame mean; no payload recovery is established.', ...
    'boundary_assumption','Finite one-frame periodic FFT and circular-delay approximation. No IIR filtering or screen registration.');
writeJsonFile(fullfile(out,'overview.json'),report);
rows = cell(4,1);
for arm=1:4
    q = round(D(arm)); frac = D(arm)-q;
    ib = k-q+n/2+1;
    assert(all(ib>=1 & ib<=n),'single26:Overlap','Declared overlap exceeds B grid.');
    shiftTrain = exp(1i*2*pi*frac*(u+kTrain));
    shiftTest = exp(1i*2*pi*frac*(u+kTest));
    aa = fftshift(fft(double(a.singleTrain(:,arm))))/n; aa=aa(ia);
    at = fftshift(fft(double(a.singleTest(:,arm))))/n; at=at(ia);
    bb = fftshift(fft(double(b.singleTrain(:,arm)).*shiftTrain))/n; bb=bb(ib);
    bt = fftshift(fft(double(b.singleTest(:,arm)).*shiftTest))/n; bt=bt(ib);
    [singleFit,keep] = fitSingleOverlap(aa,bb,at,bt,k,T,false);
    [singleMasked,keepMasked] = fitSingleOverlap(aa,bb,at,bt,k,T,true);
    if iscell(published.records), old=published.records{arm}; else, old=published.records(arm); end
    assert(string(old.arm)==armNames(arm),'single26:Arm','Published mean arm order differs.');
    assert(abs(old.translation_cycles-D(arm))<1e-8,'single26:Translation','Published translation differs.');
    % Additional frozen-mean-parameter control avoids hiding an alignment
    % difference between single-frame and 8-frame training correlations.
    oldFit = old.narrow_106mhz_alignment;
    sameMeanFit = evaluateFrozen(aa,bb,at,bt,k,T,keep,oldFit.delay_seconds,oldFit.phase_rad);
    % Recreate the published mask exactly from TRAINING pilot means only.
    ma = fftshift(fft(double(meanA.meanPilotTrain(:,arm))))/n; ma=ma(ia);
    mb = fftshift(fft(double(meanB.meanPilotTrain(:,arm)).*exp(1i*2*pi*frac*u)))/n; mb=mb(ib);
    [meanKeep,meanMaskSeeds] = makeTrainingMask(ma,mb,true);
    oldMasked = old.narrow_training_tone_mask_control;
    sameMeanMasked = evaluateFrozen(aa,bb,at,bt,k,T,meanKeep,oldMasked.delay_seconds,oldMasked.phase_rad);
    sameMeanMasked.mask_source='8-frame TRAINING pilot means; exact published top10-bin +/-8 mask reconstructed';
    sameMeanMasked.mask_seed_global_bins=k(meanMaskSeeds).';
    rec = struct('arm',armNames(arm),'translation_cycles',D(arm),'integer_center_bin_b',q, ...
        'fractional_cycles',frac,'assessment_fractional_frame_phase_rad',angle(exp(1i*2*pi*frac*kTest)), ...
        'single_frame_training_fit',singleFit,'single_frame_training_mask_fit',singleMasked, ...
        'single_frame_with_frozen_mean_alignment',sameMeanFit, ...
        'single_frame_with_frozen_mean_alignment_and_mask',sameMeanMasked, ...
        'published_8frame_mean_alignment',oldFit,'published_8frame_mean_mask_alignment',oldMasked, ...
        'single_minus_mean_assessment_coherence',singleFit.test_coherence-oldFit.test_coherence, ...
        'single_minus_mean_masked_assessment_coherence',singleMasked.test_coherence-oldMasked.test_coherence, ...
        'mask_caveat','Top10 cross-power BINS each +/-8; neighborhoods can overlap. Not guaranteed ten distinct tones.', ...
        'assessment_fit_frozen',true,'screen_signal_identified',false);
    report.records{arm}=rec;
    rows{arm}=struct('arm',armNames(arm),'single_train_coherence',singleFit.train_coherence, ...
        'single_assessment_coherence',singleFit.test_coherence,'single_assessment_phase_rad',singleFit.test_phase_rad, ...
        'single_masked_assessment_coherence',singleMasked.test_coherence, ...
        'mean8_assessment_coherence',oldFit.test_coherence,'mean8_masked_assessment_coherence',oldMasked.test_coherence, ...
        'single_with_mean_fit_assessment_coherence',sameMeanFit.test_coherence, ...
        'single_with_mean_fit_and_mask_assessment_coherence',sameMeanMasked.test_coherence);
    writeJsonFile(fullfile(out,'overview.json'),report);
    fprintf('Single26 %s: train %.6f test %.6f mask %.6f; mean8 %.6f mask %.6f\n', ...
        armNames(arm),singleFit.train_coherence,singleFit.test_coherence,singleMasked.test_coherence, ...
        oldFit.test_coherence,oldMasked.test_coherence);
    clear aa at bb bt ma mb shiftTrain shiftTest keepMasked
end
summary = struct2table(vertcat(rows{:}));
writetable(summary,fullfile(out,'overview.csv'));
report.summary=vertcat(rows{:});report.status='complete';
writeJsonFile(fullfile(out,'overview.json'),report);
fig=figure('Visible','off','Color','w','Position',[40 40 1500 550]);
cleanup=onCleanup(@()close(fig));tiledlayout(fig,1,2);
nexttile;bar([summary.single_assessment_coherence summary.mean8_assessment_coherence ...
    summary.single_masked_assessment_coherence summary.mean8_masked_assessment_coherence]);
xticklabels(armNames);ylabel('Frozen-training assessment coherence');ylim([0 1]);grid on;
legend('Single frame72','8-frame means72:79','Single; training mask','8-frame; training mask','Location','best');
title('Each representation: training delay/phase and mask frozen');
nexttile;bar([summary.single_assessment_coherence summary.single_with_mean_fit_assessment_coherence ...
    summary.single_with_mean_fit_and_mask_assessment_coherence]);
xticklabels(armNames);ylabel('Single-frame72 coherence');ylim([0 1]);grid on;
legend('Single-frame training alignment','Published mean training alignment', ...
    'Published mean alignment + mask','Location','best');
title('Reuse published mean alignment to expose alignment sensitivity');
sgtitle('Single frame versus conditional 8-frame means | global fractional frame phase included');
exportgraphics(fig,fullfile(out,'single_vs_8frame_coherence.png'),Resolution=140);
end

function [result,keep] = fitSingleOverlap(a,b,at,bt,k,T,maskTones)
% Numerical fit matches stitchIphonePair26 fitOverlap for direct comparison.
[keep,seeds]=makeTrainingMask(a,b,maskTones);
ka=k(keep);cross=b(keep).*conj(a(keep));
assert(any(abs(cross)>0),'single26:NoEnergy','No common training energy.');
lengthCorr=2^nextpow2(max(ka)-min(ka)+1);
spectrum=complex(zeros(lengthCorr,1));spectrum(mod(ka,lengthCorr)+1)=cross;
cc=abs(ifft(spectrum)*lengthCorr);[peak,index]=max(cc);
delay=mod(index-1+lengthCorr/2,lengthCorr)-lengthCorr/2;
centeredBins=ka-round(mean(ka));
objective=@(d)-abs(sum(cross.*exp(1i*2*pi*centeredBins*(delay+d)/lengthCorr)));
[delta,~,exitFlag]=fminbnd(objective,-1,1,optimset('TolX',1e-8,'Display','off'));
delay=delay+delta;ramp=exp(1i*2*pi*ka*delay/lengthCorr);
phase=angle(sum(cross.*ramp));
result=evaluateFrozen(a,b,at,bt,k,T,keep,delay*T/lengthCorr,phase);
guard=max(2,ceil(2*lengthCorr/(max(ka)-min(ka)+1)));
distance=abs(mod((0:lengthCorr-1)'-(index-1)+lengthCorr/2,lengthCorr)-lengthCorr/2);
cc(distance<=guard)=0;
result.second_peak_ratio=max(cc)/max(peak,realmin);
result.training_second_peak_ambiguous=result.second_peak_ratio>.9;
result.effective_bins=sum(abs(cross))^2/max(sum(abs(cross).^2),realmin);
result.training_tone_mask=maskTones;
result.mask_seed_global_bins=k(seeds).';
result.mask_seed_count=numel(seeds);result.mask_halfwidth_bins=8;
result.fminbnd_exit_flag=exitFlag;
result.delay_identifiability='Circular one-period delay; comb aliases can remain.';
end

function [keep,seeds] = makeTrainingMask(a,b,maskTones)
keep=true(size(a));seeds=[];
if ~maskTones,return;end
[~,order]=sort(abs(a.*b),'descend');seeds=order(1:min(10,numel(order)));
for j=1:numel(seeds)
    keep(max(1,seeds(j)-8):min(numel(a),seeds(j)+8))=false;
end
end

function result = evaluateFrozen(a,b,at,bt,k,T,keep,delay,phase)
correction=exp(1i*2*pi*k(keep)*delay/T-1i*phase);
trainCross=sum(b(keep).*correction.*conj(a(keep)));
testCross=sum(bt(keep).*correction.*conj(at(keep)));
result=struct('train_coherence',abs(trainCross)/max(norm(a(keep))*norm(b(keep)),realmin), ...
    'test_coherence',abs(testCross)/max(norm(at(keep))*norm(bt(keep)),realmin), ...
    'test_phase_rad',angle(testCross),'test_relative_error',norm(at(keep)-bt(keep).*correction)/max(norm(at(keep)),realmin), ...
    'delay_seconds',delay,'phase_rad',phase,'kept_bin_count',nnz(keep),'removed_bin_count',nnz(~keep), ...
    'retained_training_power',[sum(abs(a(keep)).^2)/max(sum(abs(a).^2),realmin),sum(abs(b(keep)).^2)/max(sum(abs(b).^2),realmin)], ...
    'retained_assessment_power',[sum(abs(at(keep)).^2)/max(sum(abs(at).^2),realmin),sum(abs(bt(keep)).^2)/max(sum(abs(bt).^2),realmin)], ...
    'assessment_parameters_refitted',false,'unit_gain',true);
end
