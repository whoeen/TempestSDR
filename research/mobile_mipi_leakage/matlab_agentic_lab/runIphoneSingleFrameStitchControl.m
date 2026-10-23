function run = runIphoneSingleFrameStitchControl(outputDirectory)
%RUNIPHONESINGLEFRAMESTITCHCONTROL Finite single-frame stitching control.
%   Uses stored singleTrain/singleTest waveforms, no frame averaging and no
%   fitted Floquet theta derotation. Timing resampling and fixed training DC
%   subtraction already applied by buildIphoneStitchTemplates are retained.
%   Nominal relative RF cycles = fcB*Tb - fcA*Ta. Integer cycles place the B
%   spectrum; fractional cycles modulate B by exp(+j*2*pi*frac*u).
%   Training chooses the branch/delay/phase. Heldout uses those values frozen.
arguments
    outputDirectory (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'),fullfile(labRoot,'stitch'));
root = fullfile(labRoot,'results','iphone6_stitch_20261023');
if strlength(outputDirectory)==0
    outputDirectory = fullfile(root,'single_frame_controls');
end
assert(~isfolder(outputDirectory) && ~isfile(outputDirectory), ...
    'stitch:OutputExists','Refuse overwrite: %s',outputDirectory);
mkdir(outputDirectory);
pairs = [100 160;280 340;520 580];
polarities = [1 -1];
run = struct('status','running','pairs_mhz',pairs,'polarities',polarities, ...
    'control_purpose','Test whether frame averaging and fitted theta derotation suppress shared overlap information.', ...
    'frame_average_count',1,'fitted_floquet_theta_used',false, ...
    'boundary_assumption','Finite single-frame periodic FFT and circular-delay approximation; endpoint mismatch can spread spectral energy.', ...
    'frequency_model','Nominal cycles fcB*Tb-fcA*Ta, q=round(cycles), frac=cycles-q, B*=exp(+j2pi*frac*u).', ...
    'limitations','Nominal translation does not establish independent LO phase/frequency, valid CFO, or a common physical emission source. Single-frame SNR also differs from averaged templates.', ...
    'cases',{{}});
writeJsonFile(fullfile(outputDirectory,'overview.json'),run);
summary = cell(6,1);
caseIndex = 0;
for pairIndex=1:size(pairs,1)
    fcA = pairs(pairIndex,1); fcB = pairs(pairIndex,2);
    pathA = fullfile(root,'templates',sprintf('fc%03dMHz',fcA),'templates.mat');
    pathB = fullfile(root,'templates',sprintf('fc%03dMHz',fcB),'templates.mat');
    originalA = load(pathA,'singleTrain','singleTest','meta');
    originalB = load(pathB,'singleTrain','singleTest','meta');
    n = numel(originalA.singleTrain);
    assert(all([numel(originalA.singleTest),numel(originalB.singleTrain),numel(originalB.singleTest)]==n), ...
        'stitch:SingleFrameLengthMismatch','Single-frame templates need a common grid length.');
    assert(mod(n,2)==0,'stitch:EvenGridRequired','FFT grid must be even.');
    assert(isequal(originalA.meta.frame_indices_zero_based([1 9]),originalB.meta.frame_indices_zero_based([1 9])), ...
        'stitch:FrameIdentityMismatch','Train/test frame indices differ across templates.');
    period = originalA.meta.period_seconds;
    cycles = fcB*1e6*originalB.meta.period_seconds-fcA*1e6*period;
    nominalCenterB = round(cycles);
    fractionalCycles = cycles-nominalCenterB;
    u = (0:n-1).'/n;
    fractionalTranslation = single(exp(1i*2*pi*fractionalCycles*u));
    clear u
    for polarity=polarities
        caseIndex = caseIndex+1;
        folder = fullfile(outputDirectory,sprintf('pair_%03d_%03d_polarity_%+d',fcA,fcB,polarity));
        mkdir(folder);
        fprintf('Single-frame nominal translation %d + %d MHz polarity %+d\n',fcA,fcB,polarity);
        aTrain = originalA.singleTrain; aTest = originalA.singleTest;
        bTrain = originalB.singleTrain; bTest = originalB.singleTest;
        if polarity<0
            aTrain = conj(aTrain); aTest = conj(aTest);
            bTrain = conj(bTrain); bTest = conj(bTest);
        end
        bTrain = bTrain.*fractionalTranslation;
        bTest = bTest.*fractionalTranslation;
        boundary = struct('a_train_endpoint_jump_over_rms',endpointJump(aTrain), ...
            'a_test_endpoint_jump_over_rms',endpointJump(aTest), ...
            'b_train_endpoint_jump_over_rms',endpointJump(bTrain), ...
            'b_test_endpoint_jump_over_rms',endpointJump(bTest));
        aTrainFFT = fftshift(fft(aTrain))/n; aTestFFT = fftshift(fft(aTest))/n;
        bTrainFFT = fftshift(fft(bTrain))/n; bTestFFT = fftshift(fft(bTest))/n;
        clear aTrain aTest bTrain bTest
        [best,bTrainAligned,bTestAligned,branches] = searchPeriodicOverlapBranches( ...
            aTrainFFT,bTrainFFT,aTestFFT,bTestFFT,0,nominalCenterB,period,120e6,-16:16);
        clear bTrainFFT bTestFFT
        trainSpectra = {aTrainFFT;single(bTrainAligned)};
        testSpectra = {aTestFFT;single(bTestAligned)};
        centerBins = [0 best.selected_center_bin_b];
        rendering = renderControl(trainSpectra,testSpectra,centerBins,period,folder, ...
            sprintf('%d + %d MHz | polarity %+d | one frame',fcA,fcB,polarity));
        clear bTrainAligned bTestAligned trainSpectra testSpectra aTrainFFT aTestFFT
        record = struct('fc_a_mhz',fcA,'fc_b_mhz',fcB,'iq_polarity',polarity, ...
            'anchor_period_seconds',period,'period_b_seconds',originalB.meta.period_seconds, ...
            'nominal_relative_cycles',cycles,'nominal_integer_center_b',nominalCenterB, ...
            'nominal_fractional_cycles',fractionalCycles, ...
            'fractional_translation_formula','B(u)*exp(+j*2*pi*frac*u), for both train and heldout', ...
            'conjugation_before_fractional_translation',polarity<0, ...
            'template_path_a',pathA,'template_path_b',pathB, ...
            'template_timing_source_a',originalA.meta.period_source, ...
            'template_timing_source_b',originalB.meta.period_source, ...
            'training_frame_zero_based',originalA.meta.frame_indices_zero_based(1), ...
            'heldout_frame_zero_based',originalA.meta.frame_indices_zero_based(9), ...
            'dc_subtraction_inherited','Fixed first-frame complex mean removed during template construction; not refitted here.', ...
            'frame_average_count',1,'floquet_theta_fit_used',false, ...
            'heldout_parameters_refitted',false,'boundary',boundary, ...
            'alignment',best,'rendering',rendering);
        writeJsonFile(fullfile(folder,'alignment.json'),best);
        writeJsonFile(fullfile(folder,'branch_search.json'),branches);
        writeJsonFile(fullfile(folder,'single_frame_control.json'),record);
        run.cases{caseIndex} = record;
        summary{caseIndex} = struct('fc_a_mhz',fcA,'fc_b_mhz',fcB,'polarity',polarity, ...
            'selected_branch_offset_bins',best.selected_branch_offset_bins, ...
            'delay_samples',best.delay_samples,'phase_rad',best.phase_rad, ...
            'train_complex_coherence',best.train_unit_gain.complex_coherence, ...
            'heldout_complex_coherence',best.test_unit_gain.complex_coherence, ...
            'heldout_normalized_complex_error',best.test_unit_gain.normalized_complex_error, ...
            'effective_bin_count',best.effective_bin_count, ...
            'energy_90_percent_span_hz',best.energy_90_percent_span_hz, ...
            'second_peak_ratio',best.second_peak_ratio,'branch_ambiguous',best.branch_ambiguous, ...
            'selected_at_search_boundary',best.selected_at_search_boundary, ...
            'am_train_test_correlation',rendering.am_train_test_correlation);
        writetable(struct2table(vertcat(summary{1:caseIndex})),fullfile(outputDirectory,'overview.csv'));
        writeJsonFile(fullfile(outputDirectory,'overview.json'),run);
    end
    clear originalA originalB fractionalTranslation
end
run.status = 'complete';
run.summary = vertcat(summary{:});
writeJsonFile(fullfile(outputDirectory,'overview.json'),run);
end

function metrics = renderControl(trainSpectra,testSpectra,centers,period,folder,label)
settings = struct('spectra',{trainSpectra},'centerBins',centers);
[fTrain,trainMeta] = synthesizePeriodicBands(settings,period,Method="raised_cosine",EdgeGuardHz=3e6);
trainPower = sum(abs(fTrain).^2,'double');
wave = ifft(ifftshift(fTrain))*numel(fTrain); clear fTrain
[raster,trainAa] = resamplePeriodicAm(abs(wave),1100*1881,PeriodSeconds=period); clear wave
trainImage = reshape(raster,1100,1881).'; clear raster
settings.spectra = testSpectra;
[fTest,testMeta] = synthesizePeriodicBands(settings,period,Method="raised_cosine",EdgeGuardHz=3e6);
testPower = sum(abs(fTest).^2,'double');
wave = ifft(ifftshift(fTest))*numel(fTest); clear fTest
[raster,testAa] = resamplePeriodicAm(abs(wave),1100*1881,PeriodSeconds=period); clear wave
heldoutImage = reshape(raster,1100,1881).'; clear raster
limits = double(sampleQuantile(trainImage(:),[.01 .99]));
imwrite(scaleUsing(trainImage,limits),fullfile(folder,'raised_cosine_train.png'));
imwrite(scaleUsing(heldoutImage,limits),fullfile(folder,'raised_cosine_heldout.png'));
a = double(trainImage(:)); b = double(heldoutImage(:)); a = a-mean(a); b = b-mean(b);
metrics = struct('am_train_test_correlation',dot(a,b)/max(norm(a)*norm(b),realmin), ...
    'train_power_counts_squared',trainPower,'heldout_power_counts_squared',testPower, ...
    'synthesis',trainMeta,'heldout_synthesis',testMeta, ...
    'antialias',trainAa,'heldout_antialias',testAa, ...
    'display_limits_counts',limits,'display_scaling','Training 1/99 percentiles frozen for both images', ...
    'image_registration','none; same normalized periodic coordinate, 1100x1881 raster', ...
    'control_label','Single frame, no coherent average, no fitted theta; finite periodic boundary approximation');
writeJsonFile(fullfile(folder,'raised_cosine_metrics.json'),metrics);
save(fullfile(folder,'raised_cosine_images.mat'),'trainImage','heldoutImage','metrics','-v7');
fig = figure('Visible','off','Color','w','Position',[100 100 1100 1050]);
cleanup = onCleanup(@() closeFigure(fig));
tiledlayout(fig,1,2,'TileSpacing','compact');
nexttile;imagesc(scaleUsing(trainImage,limits));axis image off;colormap(gray(256));title('Training: frame 0');
nexttile;imagesc(scaleUsing(heldoutImage,limits));axis image off;colormap(gray(256));title('Heldout: frame 16, frozen branch/delay/phase');
sgtitle(string(label)+" | finite periodic FFT control");
exportgraphics(fig,fullfile(folder,'comparison.png'),Resolution=130);
clear cleanup
end

function image = scaleUsing(values,limits)
image = uint8(255*min(1,max(0,(double(values)-limits(1))/max(limits(2)-limits(1),eps))));
end

function ratio = endpointJump(x)
ratio = double(abs(x(end)-x(1)))/max(sqrt(mean(abs(x).^2,'double')),realmin);
end

function closeFigure(fig)
if isgraphics(fig),close(fig);end
end
