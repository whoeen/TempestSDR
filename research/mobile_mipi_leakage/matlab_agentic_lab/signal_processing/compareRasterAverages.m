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
    'raw_block_sha256',""),maximumFrames,1);
summaryRecords = struct([]);
linearIndex = (0:rows*cols-1).';
relativePositions = floor(linearIndex/cols)*lineSamples + mod(linearIndex,cols)*step;
reference = [];
normalization = [];
for k=1:maximumFrames
    startSample = firstOrigin + (k-1)*device.prior_frame_samples;
    [frame,nearest,hash] = readFrame(filePath,startSample,relativePositions,[rows cols]);
    currentProfile = mean(abs(frame),1);
    if isempty(reference)
        reference = frame;
        referenceProfile = currentProfile;
        shift = 0;
        profileScore = 1;
        normalization = sampleQuantile(abs(frame(activeRows,activeCols)),[0.01 0.99]);
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
    phase = unwrap(angle(rowCross));
    fitMask = mod(rowNumber,2)==0 & rowCoherence>=sampleQuantile(rowCoherence,0.5);
    design = [ones(rows,1),rowNumber/max(rows-1,1)];
    weight = sqrt(rowCoherence(fitMask));
    coefficient = (design(fitMask,:).*weight)\(phase(fitMask).*weight);
    phaseFit = design*coefficient;
    corrected = frame.*single(exp(-1j*phaseFit));
    globalCorrected = frame*single(exp(-1j*globalPhase));
    validationMask = mod(rowNumber,2)==1;
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
        'mean_amplitude_counts',mean(abs(frame),'all'),'raw_block_sha256',hash);
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
        summaryRecords(end+1) = entry; %#ok<AGROW>
        stem = string(sprintf('P%03d',k));
        fullAm = scaleImage(am,normalization);
        fullCoherent = scaleImage(abs(coherent),normalization);
        hue = mod(angle(coherent)+pi,2*pi)/(2*pi);
        hsv = hsv2rgb(cat(3,hue,rowConsistency,fullCoherent));
        imwrite(fullAm(activeRows,activeCols),fullfile(outputDir,stem+'_am.png'));
        imwrite(scaleImage(nearestAm(activeRows,activeCols),normalization),fullfile(outputDir,stem+'_nearest_am.png'));
        imwrite(fullCoherent(activeRows,activeCols),fullfile(outputDir,stem+'_coherent.png'));
        imwrite(hsv(activeRows,activeCols,:),fullfile(outputDir,stem+'_phase_hsv.png'));
        f = figure('Visible',cfg.figure_visible,'Position',[50 50 1400 750]);
        tiledlayout(f,1,4);
        nexttile; imagesc(nearestAm(activeRows,activeCols),normalization); axis image off; title('Nearest sample AM');
        nexttile; imagesc(am(activeRows,activeCols),normalization); axis image off; title('Fractional cubic AM');
        nexttile; imagesc(abs(coherent(activeRows,activeCols)),normalization); axis image off; title('Row-phase coherent amplitude');
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
    'phase_fit','Linear unwrapped mixture phase over rows; fit even-index rows, evaluate remaining rows', ...
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
