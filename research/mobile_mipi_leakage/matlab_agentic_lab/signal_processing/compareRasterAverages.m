function result = compareRasterAverages(filePath, device, cfg, outputDir, notePath)
%COMPARERASTERAVERAGES Stream frames and retain intermediate AM/phase images.
%   Uses prior timing and active crop; it does not fit display contents. Phase
%   alignment follows the observed mixture and can also reinforce clutter.
arguments
    filePath (1,1) string
    device (1,1) struct
    cfg (1,1) struct
    outputDir (1,1) string
    notePath (1,1) string
end
rows = device.raster_rows;
cols = device.raster_columns;
lineSamples = device.fs_hz/device.prior_line_hz;
step = lineSamples/cols;
fileInfo = dir(filePath);
firstOrigin = cfg.first_sample + 4 + device.origin_columns*step;
maximumFrames = min(cfg.max_frames,floor((fileInfo.bytes/4-firstOrigin-8)/device.prior_frame_samples));
assert(maximumFrames>=1,'mobile:TooShortRaster','No complete frame available.');
activeRows = circularIndices(device.active_row_segments);
activeCols = circularIndices(device.active_column_segments);
amSum = zeros(rows,cols,'single');
nearestSum = zeros(rows,cols,'single');
coherentSum = complex(zeros(rows,cols,'single'));
globalSum = complex(zeros(rows,cols,'single'));
uncorrectedSum = complex(zeros(rows,cols,'single'));
oddSum = zeros(rows,cols,'single');
evenSum = zeros(rows,cols,'single');
frameRecords = repmat(struct('frame',0,'start_sample',0,'shift_columns',0, ...
    'profile_correlation',0,'global_phase_rad',0,'row_phase_slope_rad_per_row',0, ...
    'fit_rows',0,'heldout_mixture_coherence',0,'mean_amplitude_counts',0, ...
    'raw_block_sha256',"",'phase_fit_mode',"",'phase_fit_reason',"", ...
    'phase_fit_coherence_threshold',0,'phase_fit_condition',Inf, ...
    'phase_fit_training_rows_disjoint',false),maximumFrames,1);
summaryRecords = struct([]);
linearIndex = (0:rows*cols-1).';
relativePositions = floor(linearIndex/cols)*lineSamples + mod(linearIndex,cols)*step;
reference = [];
normalization = [];
minimumRowCoherence = 0.10;
minimumFitRows = 16;
maximumDesignCondition = 1e3;
if isfield(cfg,'minimum_row_phase_coherence')
    minimumRowCoherence = cfg.minimum_row_phase_coherence;
end
if isfield(cfg,'minimum_row_phase_fit_rows')
    minimumFitRows = cfg.minimum_row_phase_fit_rows;
end
assert(isfinite(minimumRowCoherence) && minimumRowCoherence>=0 && minimumRowCoherence<=1, ...
    'mobile:PhaseThreshold','Minimum row phase coherence must lie in [0,1].');
assert(isfinite(minimumFitRows) && minimumFitRows>=3 && mod(minimumFitRows,1)==0, ...
    'mobile:PhaseRows','Minimum row phase fit count must be an integer of at least three.');
for k=1:maximumFrames
    startSample = firstOrigin + (k-1)*device.prior_frame_samples;
    [frame,nearest,hash] = readFrame(filePath,startSample,relativePositions,[rows cols]);
    currentProfile = mean(abs(frame),1);
    if isempty(reference)
        reference = frame;
        referenceProfile = currentProfile;
        shift = 0;
        profileScore = 1;
        normalization = double(sampleQuantile(abs(frame(activeRows,activeCols)),[0.01 0.99]));
        if normalization(2)<=normalization(1)
            normalization(2) = normalization(1)+max(1e-6,eps(max(1,abs(normalization(1)))));
        end
    else
        [shift,profileScore] = profileShift(currentProfile,referenceProfile,cfg.maximum_alignment_columns);
        startSample = startSample - shift*step;
        [frame,nearest,hash] = readFrame(filePath,startSample,relativePositions,[rows cols]);
    end
    rowCross = sum(double(frame).*conj(double(reference)),2);
    rowPower = sqrt(sum(abs(double(frame)).^2,2).*sum(abs(double(reference)).^2,2));
    rowCoherence = abs(rowCross)./max(rowPower,eps);
    globalPhase = angle(sum(rowCross));
    rowNumber = (0:rows-1).';
    trainingMask = mod(rowNumber,2)==0;
    validationMask = ~trainingMask;
    fitThreshold = max(minimumRowCoherence,sampleQuantile(rowCoherence(trainingMask),0.5));
    fitMask = trainingMask & rowCoherence>=fitThreshold;
    design = [ones(rows,1),rowNumber/max(rows-1,1)];
    % Do not unwrap validation rows before selecting the training samples.
    % Low-coherence phases must not choose the unwrap branch of the fit.
    coefficient = [globalPhase;0];
    fitMode = "global_fallback";
    fitReason = "too_few_reliable_training_rows";
    fitCondition = Inf;
    if nnz(fitMask)>=minimumFitRows
        weight = sqrt(rowCoherence(fitMask));
        weightedDesign = design(fitMask,:).*weight;
        fitCondition = cond(weightedDesign);
        fitReason = "ill_conditioned_training_design";
        if isfinite(fitCondition) && fitCondition<=maximumDesignCondition
            trainingPhase = unwrap(angle(rowCross(fitMask)));
            candidateCoefficient = weightedDesign\(trainingPhase.*weight);
            fitReason = "nonfinite_training_coefficients";
            if all(isfinite(candidateCoefficient))
                coefficient = candidateCoefficient;
                fitMode = "row_linear_train_only";
                fitReason = "reliable_training_rows_and_conditioned_design";
            end
        end
    end
    phaseFit = design*coefficient;
    corrected = frame.*single(exp(-1j*phaseFit));
    globalCorrected = frame*single(exp(-1j*globalPhase));
    heldoutCross = sum(sum(double(corrected(validationMask,:)).*conj(double(reference(validationMask,:)))));
    heldoutNorm = sqrt(sum(abs(double(corrected(validationMask,:))).^2,'all')* ...
        sum(abs(double(reference(validationMask,:))).^2,'all'));
    coherentSum = coherentSum + corrected;
    globalSum = globalSum + globalCorrected;
    uncorrectedSum = uncorrectedSum + frame;
    amSum = amSum + abs(frame);
    nearestSum = nearestSum + abs(nearest);
    if mod(k,2)==1
        oddSum = oddSum + abs(frame);
    else
        evenSum = evenSum + abs(frame);
    end
    frameRecords(k) = struct('frame',k,'start_sample',startSample, ...
        'shift_columns',shift,'profile_correlation',profileScore, ...
        'global_phase_rad',globalPhase, ...
        'row_phase_slope_rad_per_row',coefficient(2)/max(rows-1,1), ...
        'fit_rows',nnz(fitMask),'heldout_mixture_coherence',abs(heldoutCross)/max(heldoutNorm,eps), ...
        'mean_amplitude_counts',mean(abs(frame),'all'),'raw_block_sha256',hash, ...
        'phase_fit_mode',fitMode,'phase_fit_reason',fitReason, ...
        'phase_fit_coherence_threshold',fitThreshold,'phase_fit_condition',fitCondition, ...
        'phase_fit_training_rows_disjoint',fitMode=="row_linear_train_only");
    appendResearchNote(notePath,'raster_frame',frameRecords(k));
    if ismember(k,cfg.checkpoints) || k==maximumFrames
        am = amSum/k;
        nearestAm = nearestSum/k;
        coherent = coherentSum/k;
        globalCoherent = globalSum/k;
        uncorrected = uncorrectedSum/k;
        rowConsistency = min(abs(coherent)./max(am,eps('single')),1);
        if k>1
            repeatability = normalizedCorrelation(oddSum/ceil(k/2),evenSum/floor(k/2));
        else
            repeatability = NaN;
        end
        entry = struct('frames',k,'am_odd_even_correlation',repeatability, ...
            'mean_coherent_over_incoherent',mean(rowConsistency,'all'), ...
            'uncorrected_coherent_power_counts2',mean(abs(uncorrected).^2,'all'), ...
            'global_coherent_power_counts2',mean(abs(globalCoherent).^2,'all'), ...
            'row_coherent_power_counts2',mean(abs(coherent).^2,'all'), ...
            'mean_amplitude_counts',mean(am,'all'), ...
            'fractional_vs_nearest_relative_rms', ...
            sqrt(mean((am-nearestAm).^2,'all'))/max(sqrt(mean(am.^2,'all')),eps));
        if isempty(summaryRecords)
            summaryRecords = entry;
        else
            summaryRecords(end+1) = entry; %#ok<AGROW>
        end
        stem = string(sprintf('P%03d',k));
        fullAm = scaleImage(am,normalization);
        fullCoherent = scaleImage(abs(coherent),normalization);
        fullGlobal = scaleImage(abs(globalCoherent),normalization);
        fullUncorrected = scaleImage(abs(uncorrected),normalization);
        hue = mod(angle(coherent)+pi,2*pi)/(2*pi);
        hsv = hsv2rgb(cat(3,hue,rowConsistency,fullCoherent));
        imwrite(fullAm(activeRows,activeCols),fullfile(outputDir,stem+'_am.png'));
        imwrite(scaleImage(nearestAm(activeRows,activeCols),normalization),fullfile(outputDir,stem+'_nearest_am.png'));
        imwrite(fullCoherent(activeRows,activeCols),fullfile(outputDir,stem+'_coherent.png'));
        imwrite(fullGlobal(activeRows,activeCols),fullfile(outputDir,stem+'_global_coherent.png'));
        imwrite(fullUncorrected(activeRows,activeCols),fullfile(outputDir,stem+'_uncorrected_coherent.png'));
        imwrite(hsv(activeRows,activeCols,:),fullfile(outputDir,stem+'_phase_hsv.png'));
        f = figure('Visible',cfg.figure_visible,'Position',[50 50 1400 1000]);
        tiledlayout(f,2,3);
        nexttile; imagesc(nearestAm(activeRows,activeCols),normalization); axis image off; title('Nearest sample AM');
        nexttile; imagesc(am(activeRows,activeCols),normalization); axis image off; title('Fractional cubic AM');
        nexttile; imagesc(abs(uncorrected(activeRows,activeCols)),normalization); axis image off; title('Uncorrected complex average');
        nexttile; imagesc(abs(globalCoherent(activeRows,activeCols)),normalization); axis image off; title('Global phase coherent amplitude');
        nexttile; imagesc(abs(coherent(activeRows,activeCols)),normalization); axis image off; title('Row fit / global fallback amplitude');
        nexttile; image(hsv(activeRows,activeCols,:)); axis image off; title('Phase HSV (not display RGB)');
        colormap(f,gray(256));
        sgtitle(sprintf('%s | %d frames | prior timing; shared amplitude scale',device.title,k),'Interpreter','none');
        exportgraphics(f,fullfile(outputDir,stem+'_comparison.png'),Resolution=140);
        close(f);
        appendResearchNote(notePath,'raster_checkpoint',entry);
    end
end
save(fullfile(outputDir,'raster_final.mat'),'am','nearestAm','coherent','globalCoherent', ...
    'uncorrected','rowConsistency','activeRows','activeCols','device','normalization','-v7');
writetable(struct2table(frameRecords),fullfile(outputDir,'frame_parameters.csv'));
writetable(struct2table(summaryRecords),fullfile(outputDir,'frame_progression.csv'));
columnPhase = angle(sum(double(coherent),1));
columnCoherence = abs(sum(double(coherent),1))./max(sum(abs(double(coherent)),1),eps);
columnAmplitude = mean(am,1);
writetable(table((1:cols).',columnPhase.',columnCoherence.',columnAmplitude.', ...
    'VariableNames',{'raster_column','phase_rad','vertical_complex_consistency','mean_amplitude_counts'}), ...
    fullfile(outputDir,'column_phase.csv'));
result = struct('frames',maximumFrames,'checkpoints',summaryRecords, ...
    'samples_per_raster_column',step,'frame_period_samples',device.prior_frame_samples, ...
    'line_period_samples',lineSamples,'image_scale_counts',normalization, ...
    'interpolation','Catmull-Rom cubic; nearest control, no new measured bandwidth', ...
    'phase_fit','Select training rows before unwrapping; linear mixture-phase fit, otherwise global phase fallback', ...
    'minimum_row_phase_coherence',minimumRowCoherence,'minimum_row_phase_fit_rows',minimumFitRows, ...
    'maximum_phase_design_condition',maximumDesignCondition, ...
    'phase_fit_fallback_frames',nnz(string({frameRecords.phase_fit_mode})=="global_fallback"), ...
    'validation_caveat','Row fit excludes validation-row phases, but horizontal alignment shares the full reference. Global fallback uses all rows. Frame 1 is self-reference, not validation.', ...
    'caveat','Repeatability and coherence can reward stable clutter. These are not ground-truth image fidelity, RGB recovery, or proof of LCD-driver origin.');
end

function [frame,nearest,hash] = readFrame(filePath,start,relativePositions,shape)
first = floor(start)-2;
last = ceil(start+relativePositions(end))+2;
[iq,info] = readRisIqBlock(filePath,first,last-first+1);
positions = start+relativePositions-first;
frame = sampleFractionalRaster(iq,positions,shape,"cubic");
nearest = sampleFractionalRaster(iq,positions,shape,"nearest");
hash = sha256FileRange(filePath,info.byte_offset,info.byte_count);
end

function indices = circularIndices(segments)
indices = [];
for k=1:size(segments,1)
    indices = [indices,segments(k,1):segments(k,2)]; %#ok<AGROW>
end
end

function [shift,score] = profileShift(profile,reference,maximum)
profile = double(profile-mean(profile));
reference = double(reference-mean(reference));
profile = profile/max(norm(profile),eps);
reference = reference/max(norm(reference),eps);
shifts = -maximum:maximum;
scores = zeros(size(shifts));
for k=1:numel(shifts)
    scores(k) = sum(circshift(profile,shifts(k)).*reference);
end
[score,index] = max(scores);
shift = shifts(index);
if index>1 && index<numel(scores)
    denominator = scores(index-1)-2*scores(index)+scores(index+1);
    if abs(denominator)>eps
        adjustment = 0.5*(scores(index-1)-scores(index+1))/denominator;
        shift = shift + max(-0.5,min(0.5,adjustment));
    end
end
end

function scaled = scaleImage(x,limits)
scaled = min(1,max(0,(double(x)-limits(1))/max(limits(2)-limits(1),eps)));
end

function value = normalizedCorrelation(a,b)
a = double(a(:));
b = double(b(:));
a = a-mean(a);
b = b-mean(b);
value = sum(a.*b)/max(norm(a)*norm(b),eps);
end
