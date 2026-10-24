function summary = auditIphoneImageBandFusion(options)
%AUDITIPHONEIMAGEBANDFUSION Training-frozen, image-level AM fusion diagnostic.
%   This is not coherent RF stitching or a literal reproduction of EM Eye.
%   Existing train 0:7 and test 16:23 are reused diagnostic partitions.
%   Fresh frames 64:71 use prior training timing/DC without per-frame fits.
%   No screenshot, reference pixels, neural model, or toolbox is used.
arguments
    options.CandidateCentersMHz (1,:) double {mustBeReal,mustBeFinite,mustBeInteger} = [100 340 520]
    options.ReadFresh (1,1) logical = true
    options.OutputDirectory (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'),fullfile(labRoot,'stitch'));
sourceRoot = fullfile(labRoot,'results','iphone6_stitch_20261023');
outputRoot = options.OutputDirectory;
if strlength(outputRoot)==0
    outputRoot = fullfile(labRoot,'results','iphone6_followup_20261024','image_fusion');
end
assert(~isfolder(outputRoot),'fusion:Exists','Refuse overwrite: %s',outputRoot);
inventoryPath=fullfile(labRoot,'knowledge','stitching','iphone6_sweep_20261023','CAPTURE_INVENTORY.json');
inventory=jsondecode(fileread(inventoryPath));
centers = 100:60:700;
candidates = options.CandidateCentersMHz;
assert(numel(candidates)>=1 && numel(candidates)<=3 && numel(unique(candidates))==numel(candidates));
assert(all(ismember(candidates,centers)) && ismember(100,candidates), ...
    'fusion:Candidates','Use 1-3 unique sweep centers including anchor 100 MHz.');
mkdir(outputRoot); mkdir(fullfile(outputRoot,'bands')); mkdir(fullfile(outputRoot,'fresh'));
rows = 1881; cols = 1100; nBands = numel(centers); anchorIndex = 1;
% Rectangles [first row,last row,first column,last column], one based.
% Selected by inspection of the existing 100-MHz TRAINING AM image only.
% Known uniform-background and text-region assistance is explicitly declared.
flatRectangles = [700 900 120 980;1500 1700 120 980];
structureRectangle = [970 1460 120 980];
flatMask = rectangleMask(rows,cols,flatRectangles);
structureMask = rectangleMask(rows,cols,structureRectangle);
trainImages = cell(1,nBands); testImages = cell(1,nBands);
metadata = cell(1,nBands); registrations = cell(1,nBands);
summary = struct('status','running','method','image-level AM fusion, not RF stitching', ...
    'centers_mhz',centers,'candidate_centers_mhz',candidates,'anchor_fc_mhz',100, ...
    'train_frames_zero_based',0:7,'reused_test_frames_zero_based',16:23, ...
    'fresh_frames_zero_based',64:71,'fresh_requested',options.ReadFresh, ...
    'raster_rows',rows,'raster_columns',cols,'reference_screenshot_used',false, ...
    'roi_assistance','Known test-pattern uniform/background and text regions; manually selected on existing 100-MHz training AM image. No screenshot pixel values.', ...
    'flat_roi_rectangles_one_based',flatRectangles,'structure_roi_rectangle_one_based',structureRectangle, ...
    'validation_status','Existing 0:7 and 16:23 were already inspected in prior experiments; both are reused diagnostics, not blind validation.', ...
    'fresh_status','pending; 64:71 are later static-scene samples, not a new screen pattern or acquisition', ...
    'fresh_prior_access','Some frames in 64:71 already appeared in prior narrowband coherence diagnostics. This is an unused fusion-fit partition, not globally blind data.', ...
    'image_polarity_note','A real-valued grayscale contrast sign is fitted. It is unrelated to IQ conjugation; abs(conj(z)) equals abs(z).', ...
    'timing_note','Each band keeps its original training-derived period, origin and fixed complex DC. No test/fresh timing refit.', ...
    'registration_note','Training-only bounded two-stage cyclic 2D translation. This is an image alignment hypothesis, not a calibrated physical scan mapping.', ...
    'no_pixel_rate_inference',true,'bands',{{}},'methods',{{}});
writeJsonFile(fullfile(outputRoot,'overview.json'),summary);
for bi = 1:nBands
    path = fullfile(sourceRoot,'templates',sprintf('fc%03dMHz',centers(bi)),'templates.mat');
    data = load(path,'amTrain','amTest','meta');
    metadata{bi} = data.meta;
    assert(data.meta.fs_hz==124082800 && data.meta.grid_length==2^21, ...
        'fusion:UnexpectedTemplate','Unexpected sample rate or periodic grid length.');
    assert(isequal(data.meta.frame_indices_zero_based(:).',[0:7 16:23]), ...
        'fusion:UnexpectedSplit','Template split differs from declared train/test frames.');
    train = raster(data.amTrain,data.meta.period_seconds,rows,cols);
    test = raster(data.amTest,data.meta.period_seconds,rows,cols);
    % Each band's affine normalization is frozen on its own training image.
    offset = double(median(train(flatMask)));
    limits = double(sampleQuantile(train(:),[.05 .95]));
    scale = max(limits(2)-limits(1),1e-6);
    train = (train-single(offset))/single(scale);
    test = (test-single(offset))/single(scale);
    if bi==anchorIndex
        anchor = train;
        shift = [0 0]; polarity = 1;
        reg = struct('peak_normalized_correlation',1,'second_peak_ratio',0, ...
            'coarse_shift',[0 0],'fine_residual',[0 0],'quality_warning',false);
    else
        [shift,polarity,reg] = trainingRegistration(anchor,train,structureMask);
    end
    train = single(polarity)*circshift(train,shift);
    test = single(polarity)*circshift(test,shift);
    trainImages{bi} = train; testImages{bi} = test;
    reg.fc_mhz = centers(bi); reg.shift_rows_columns = shift;
    reg.grayscale_sign = polarity; reg.training_offset_adc_counts = offset;
    reg.training_scale_adc_counts = scale; reg.fit_partition = 'train 0:7 only';
    reg.template_path = path; registrations{bi} = reg;
    fprintf('Image fusion fc%d: shift [%d %d], sign %+d, feature correlation %.4f\n', ...
        centers(bi),shift(1),shift(2),polarity,reg.peak_normalized_correlation);
end
% The structure functional is linear and fixed before any test/fresh metrics.
% Select moderate-to-strong anchor vertical gradients, excluding extreme peaks.
anchorGradient = linearStructure(trainImages{anchorIndex});
a = abs(anchorGradient(structureMask));
thresholds = double(sampleQuantile(a,[.60 .98]));
featureMask = structureMask & abs(anchorGradient)>=thresholds(1) & abs(anchorGradient)<=thresholds(2);
anchorVector = double(anchorGradient(featureMask));
anchorEnergy = max(sum(anchorVector.^2),realmin);
projection = zeros(1,nBands);
for bi=1:nBands
    g = linearStructure(trainImages{bi});
    projection(bi) = sum(anchorVector.*double(g(featureMask)))/anchorEnergy;
end
[~,candidateIndices] = ismember(candidates,centers);
K = numel(candidates); covariance = zeros(K,K);
roiColumns = zeros(nnz(flatMask),K);
for k=1:K
    v = double(trainImages{candidateIndices(k)}(flatMask));
    roiColumns(:,k) = v-mean(v);
end
covariance = (roiColumns.'*roiColumns)/max(size(roiColumns,1)-1,1);
clear roiColumns
ridge = .02*max(trace(covariance)/K,eps);
minimumProjection = .8; prior = ones(1,K)/K;
q = projection(candidateIndices);
[optimizedWeights,optimization] = simplexGrid(covariance,q,ridge,prior,minimumProjection,.02);
% Best single is selected only by the same TRAINING objective and gate.
singleObjectives = inf(1,K);
for k=1:K
    w=zeros(1,K); w(k)=1;
    if q(k)>=minimumProjection
        singleObjectives(k)=w*covariance*w.'+ridge*sum((w-prior).^2);
    end
end
[~,bestIndex] = min(singleObjectives);
singleWeights = zeros(1,K); singleWeights(bestIndex)=1;
methodNames = {'best_single_training_choice','equal_mean','simplex_roi_ridge'};
weightRows = [singleWeights;prior;optimizedWeights];
summary.optimization = optimization;
summary.optimization.covariance = covariance;
summary.optimization.structure_projection_per_candidate = q;
summary.optimization.ridge_lambda = ridge;
summary.optimization.minimum_structure_projection = minimumProjection;
summary.optimization.best_single_fc_mhz = candidates(bestIndex);
summary.optimization.selection_note = 'Best single and simplex weights selected exclusively from reused training frames 0:7; never selected by reused-test or fresh score.';
summary.optimization.gate_caveat = 'The gate preserves signed vertical-gradient projection onto the training anchor, including any anchor clutter. It is not OCR, original-image accuracy, or proof of recovery.';
summary.registration = registrations;
summary.feature_mask = struct('count',nnz(featureMask),'anchor_abs_gradient_thresholds',thresholds, ...
    'operation','vertical central difference, then subtract per-row and per-column means; linear operator before fixed mask');
% One shared display scale, fixed from anchor training, for every output.
displayLimits = double(sampleQuantile(trainImages{anchorIndex}(:),[.005 .995]));
if displayLimits(2)<=displayLimits(1), displayLimits(2)=displayLimits(1)+1; end
summary.shared_display_limits = displayLimits;
summary.display_note = 'All normalized bands, splits and fusions use these same anchor-training limits. No panel-specific histogram equalization.';
writeJsonFile(fullfile(outputRoot,'overview.json'),summary);
for bi=1:nBands
    record = struct('fc_mhz',centers(bi),'registration',registrations{bi}, ...
        'period_samples',metadata{bi}.period_samples,'fs_hz',metadata{bi}.fs_hz, ...
        'nominal_rf_bandwidth_hz',120e6,'rf_bandwidth_source','user measurement setup', ...
        'training',imageMetrics(trainImages{bi},flatMask,featureMask,anchorVector,anchorEnergy,displayLimits), ...
        'reused_test',imageMetrics(testImages{bi},flatMask,featureMask,anchorVector,anchorEnergy,displayLimits), ...
        'train_reused_test_correlation',imageCorrelation(trainImages{bi},testImages{bi}), ...
        'correlation_caveat','Repeatability of a static pattern/clutter mixture; not image fidelity or SNR.');
    identityIndex=find([inventory.captures.fc_mhz]==centers(bi),1);
    identity=inventory.captures(identityIndex);
    record.input_identity=struct('original_capture_path',identity.path, ...
        'bytes',identity.bytes,'recorded_sha256',identity.full_sha256, ...
        'sha256_recomputed_by_this_driver',false,'metadata_inventory_path',inventoryPath, ...
        'format','headerless big-endian signed int16 interleaved I,Q', ...
        'template_raw_reads',{metadata{bi}.read_records});
    summary.bands{bi}=record;
    imwrite(displayImage(trainImages{bi},displayLimits),fullfile(outputRoot,'bands',sprintf('fc%03d_train.png',centers(bi))));
    imwrite(displayImage(testImages{bi},displayLimits),fullfile(outputRoot,'bands',sprintf('fc%03d_reused_test.png',centers(bi))));
end
fusionTrain = cell(1,3); fusionTest = cell(1,3); fusionFresh = cell(1,3);
for methodIndex=1:3
    fusionTrain{methodIndex}=combineImages(trainImages,candidateIndices,weightRows(methodIndex,:));
    fusionTest{methodIndex}=combineImages(testImages,candidateIndices,weightRows(methodIndex,:));
    summary.methods{methodIndex}=struct('name',methodNames{methodIndex}, ...
        'weights',weightRows(methodIndex,:),'candidate_centers_mhz',candidates, ...
        'training_structure_gate_passed',weightRows(methodIndex,:)*q.'>=minimumProjection-1e-10, ...
        'training',imageMetrics(fusionTrain{methodIndex},flatMask,featureMask,anchorVector,anchorEnergy,displayLimits), ...
        'reused_test',imageMetrics(fusionTest{methodIndex},flatMask,featureMask,anchorVector,anchorEnergy,displayLimits), ...
        'train_reused_test_correlation',imageCorrelation(fusionTrain{methodIndex},fusionTest{methodIndex}));
    imwrite(displayImage(fusionTrain{methodIndex},displayLimits),fullfile(outputRoot,[methodNames{methodIndex} '_train.png']));
    imwrite(displayImage(fusionTest{methodIndex},displayLimits),fullfile(outputRoot,[methodNames{methodIndex} '_reused_test.png']));
end
% Freeze parameters to disk before opening any fresh frame.
summary.frozen_parameters_saved_before_fresh = true;
writeJsonFile(fullfile(outputRoot,'frozen_parameters.json'),summary);
save(fullfile(outputRoot,'frozen_parameters.mat'),'registrations','candidateIndices','weightRows', ...
    'flatMask','featureMask','anchorVector','anchorEnergy','displayLimits','-v7');
freshAvailable = false(1,nBands);
freshImages = cell(1,nBands);
if options.ReadFresh
    for bi=1:nBands
        try
            [rawImage,freshRead] = freshAmplitude(centers(bi),metadata{bi},rows,cols);
            reg=registrations{bi};
            image=single(reg.grayscale_sign)*circshift( ...
                (rawImage-single(reg.training_offset_adc_counts))/single(reg.training_scale_adc_counts), ...
                reg.shift_rows_columns);
            freshImages{bi}=image; freshAvailable(bi)=true;
            summary.bands{bi}.fresh=imageMetrics(image,flatMask,featureMask,anchorVector,anchorEnergy,displayLimits);
            summary.bands{bi}.train_fresh_correlation=imageCorrelation(trainImages{bi},image);
            summary.bands{bi}.fresh_read=freshRead;
            imwrite(displayImage(image,displayLimits),fullfile(outputRoot,'bands',sprintf('fc%03d_fresh64_71.png',centers(bi))));
            save(fullfile(outputRoot,'fresh',sprintf('fc%03d_fresh64_71.mat',centers(bi))),'image','freshRead','-v7');
            fprintf('Fresh fixed AM fc%d frames64:71 completed\n',centers(bi));
        catch exception
            summary.bands{bi}.fresh_error=struct('identifier',exception.identifier,'message',exception.message);
            fprintf('Fresh fc%d unavailable: %s\n',centers(bi),exception.message);
        end
        writeJsonFile(fullfile(outputRoot,'overview.json'),summary);
    end
    if all(freshAvailable(candidateIndices))
        for methodIndex=1:3
            fusionFresh{methodIndex}=combineImages(freshImages,candidateIndices,weightRows(methodIndex,:));
            summary.methods{methodIndex}.fresh=imageMetrics(fusionFresh{methodIndex},flatMask,featureMask,anchorVector,anchorEnergy,displayLimits);
            summary.methods{methodIndex}.train_fresh_correlation=imageCorrelation(fusionTrain{methodIndex},fusionFresh{methodIndex});
            imwrite(displayImage(fusionFresh{methodIndex},displayLimits),fullfile(outputRoot,[methodNames{methodIndex} '_fresh64_71.png']));
        end
    end
    summary.fresh_status = 'Frames 64:71 evaluated with frozen fusion parameters where read succeeded. Some frames were already used in narrowband diagnostics. Same static scene/acquisition; neither globally blind nor new-pattern validation.';
else
    summary.fresh_status='Not requested. Only reused train/test diagnostics produced.';
end
summary.fresh_available_centers_mhz=centers(freshAvailable);
summary.status='complete';
summary.limitations={ ...
    'Image-domain combination does not recover a coherent 720-MHz RF waveform.', ...
    '2D cyclic registration and relative grayscale polarity may follow repetitive text or clutter; ambiguity scores are reported.', ...
    'Uniform and structure ROIs are known-pattern-assisted and manually fixed from the existing 100-MHz training image.', ...
    'No known screen pixels, OCR loss, neural enhancement, or test-selected weights are used.', ...
    'Simplex plus a linear anchor-gradient gate prevents the zero-weight solution but does not prove character fidelity.', ...
    'ROI standard deviation, edge energy, row/column statistics and repeatability are proxies, not SNR/PSNR/SSIM.', ...
    'Fixed timing may drift at later frames; no fresh-frame adaptive alignment is allowed in this baseline.', ...
    'All bands share a normalized display scale; clipping fractions reveal when this hides dynamic range.'};
writeJsonFile(fullfile(outputRoot,'overview.json'),summary);
save(fullfile(outputRoot,'fusion_images.mat'),'fusionTrain','fusionTest','fusionFresh','weightRows', ...
    'candidateIndices','methodNames','summary','-v7.3');
writeMetricsCsv(fullfile(outputRoot,'metrics.csv'),summary);
writePanels(outputRoot,fusionTrain,fusionTest,fusionFresh,displayLimits,methodNames,structureRectangle);
fprintf('Image fusion complete. Output: %s\n',outputRoot);
end

function image=raster(amplitude,periodSeconds,rows,cols)
image=reshape(resamplePeriodicAm(amplitude,rows*cols,PeriodSeconds=periodSeconds),cols,rows).';
end

function mask=rectangleMask(rows,cols,rectangles)
mask=false(rows,cols);
for k=1:size(rectangles,1)
    r=rectangles(k,:); mask(r(1):r(2),r(3):r(4))=true;
end
end

function small=blockAverage(image)
% Exact nonoverlapping 3-row x 4-column means; 1881x1100 ->627x275.
a=reshape(image,3,627,4,275);
small=reshape(mean(mean(a,1),3),627,275);
end

function f=linearStructure(image)
f=.5*(circshift(image,[-1 0])-circshift(image,[1 0]));
f=f-mean(f,1); f=f-mean(f,2);
end

function f=registrationFeature(image)
f=linearStructure(image);
cut=double(sampleQuantile(abs(f(:)),.98));
f=max(-single(max(cut,eps)),min(single(max(cut,eps)),f));
f=f-mean(f(:));
end

function [shift,polarity,record]=trainingRegistration(anchor,candidate,structureMask)
a=registrationFeature(blockAverage(anchor));
b=registrationFeature(blockAverage(candidate));
c=real(ifft2(fft2(a).*conj(fft2(b))));
denominator=sqrt(sum(double(a(:)).^2)*sum(double(b(:)).^2));
[peak,index]=max(abs(c(:))); [r,col]=ind2sub(size(c),index);
shiftSmall=[r-1 col-1];
for dim=1:2
    if shiftSmall(dim)>floor(size(c,dim)/2), shiftSmall(dim)=shiftSmall(dim)-size(c,dim); end
end
polarity=sign(c(index)); if polarity==0, polarity=1; end
exclude=abs(circshift(c,1-[r col]));
exclude([1:4 end-2:end],[1:4 end-2:end])=0;
second=max(exclude(:));
coarse=shiftSmall.*[3 4];
% Fine search uses a sparse training structure ROI, after coarse matching.
[rr,cc]=find(structureMask); take=1:8:numel(rr); rr=rr(take); cc=cc(take);
aFull=registrationFeature(anchor); bFull=registrationFeature(candidate);
anchorValues=double(aFull(sub2ind(size(anchor),rr,cc))); anchorValues=anchorValues-mean(anchorValues);
best=-inf; residual=[0 0];
for dr=-3:3
    for dc=-4:4
        trial=coarse+[dr dc];
        srcR=mod(rr-1-trial(1),size(candidate,1))+1;
        srcC=mod(cc-1-trial(2),size(candidate,2))+1;
        v=polarity*double(bFull(sub2ind(size(candidate),srcR,srcC))); v=v-mean(v);
        score=sum(anchorValues.*v)/max(norm(anchorValues)*norm(v),realmin);
        if score>best, best=score; residual=[dr dc]; end
    end
end
shift=coarse+residual;
record=struct('peak_normalized_correlation',double(peak)/max(denominator,realmin), ...
    'second_peak_ratio',double(second)/max(double(peak),realmin), ...
    'coarse_shift',coarse,'fine_residual',residual,'fine_roi_correlation',best, ...
    'quality_warning',best<.05 || double(second)/max(double(peak),realmin)>.98, ...
    'coarse_method','Signed normalized FFT cross-correlation of clipped vertical-gradient features on 3x4 block means.', ...
    'fine_search_rows',[-3 3],'fine_search_columns',[-4 4], ...
    'wrap_policy','2D cyclic translation; no scale, rotation, shear or elastic fitting.');
end

function [weights,record]=simplexGrid(C,q,lambda,prior,minGain,step)
K=numel(q); units=round(1/step); best=inf; weights=zeros(1,K); count=0; feasible=0;
for i=0:units
    for j=0:units-i
        if K==1
            if i~=units || j~=0, continue; end
            w=1;
        elseif K==2
            if j~=0, continue; end
            w=[i units-i]/units;
        else
            w=[i j units-i-j]/units;
        end
        count=count+1;
        if w*q.'<minGain-1e-10, continue; end
        feasible=feasible+1;
        value=w*C*w.'+lambda*sum((w-prior).^2);
        if value<best, best=value; weights=w; end
    end
end
assert(isfinite(best),'fusion:NoFeasibleWeights','Anchor must provide a feasible unit weight.');
record=struct('objective','w'' C_uniformROI w + lambda ||w-uniform||^2', ...
    'constraints','w>=0, sum(w)=1, signed anchor-structure projection >=0.8', ...
    'solver','Exhaustive finite simplex lattice; approximate continuous optimum', ...
    'grid_step',1/units,'tested_points',count,'feasible_points',feasible, ...
    'objective_at_solution',best,'weights',weights,'weights_sum',sum(weights));
end

function output=combineImages(images,indices,weights)
output=zeros(size(images{indices(1)}),'single');
for k=1:numel(indices), output=output+single(weights(k))*images{indices(k)}; end
end

function metrics=imageMetrics(image,flatMask,featureMask,anchorVector,anchorEnergy,limits)
v=double(image(flatMask)); g=linearStructure(image);
gx=double(diff(image,1,2)); gy=double(diff(image,1,1));
metrics=struct('uniform_roi_std',std(v),'uniform_roi_mean',mean(v), ...
    'uniform_roi_median_absolute_deviation',median(abs(v-median(v))), ...
    'horizontal_difference_rms',sqrt(mean(gx(:).^2)), ...
    'vertical_difference_rms',sqrt(mean(gy(:).^2)), ...
    'row_mean_std',std(double(mean(image,2))), ...
    'column_mean_std',std(double(mean(image,1))), ...
    'structure_projection_to_training_anchor',sum(anchorVector.*double(g(featureMask)))/anchorEnergy, ...
    'structure_gradient_rms',sqrt(mean(double(g(featureMask)).^2)), ...
    'display_low_clipped_fraction',mean(image(:)<limits(1)), ...
    'display_high_clipped_fraction',mean(image(:)>limits(2)));
end

function value=imageCorrelation(a,b)
x=double(a(:)); y=double(b(:)); x=x-mean(x); y=y-mean(y);
value=sum(x.*y)/max(norm(x)*norm(y),realmin);
end

function image=displayImage(x,limits)
image=uint8(255*min(1,max(0,(x-single(limits(1)))/single(limits(2)-limits(1)))));
end

function [image,record]=freshAmplitude(fc,meta,rows,cols)
[path,resolution]=resolveIphoneSweepCapture(fc);
n=meta.grid_length; u=(0:n-1).'/n;
period=meta.period_samples; origin=meta.origin_samples;
dc=single(complex(meta.training_dc_removed_real,meta.training_dc_removed_imag));
indices=64:71; total=zeros(n,1,'single'); reads=cell(1,numel(indices));
for fi=1:numel(indices)
    firstCoordinate=origin+indices(fi)*period;
    first=floor(firstCoordinate)-512;
    [raw,ri]=readRisIqBlock(path,first,n);
    z=sampleGuardedIqFft(raw-dc,firstCoordinate-first+u*period,GuardSamples=512);
    total=total+abs(z)/numel(indices); reads{fi}=ri;
end
image=raster(total,meta.period_seconds,rows,cols);
record=struct('frame_indices_zero_based',indices,'resolution',resolution, ...
    'reads',{reads},'period_samples',period,'origin_samples',origin, ...
    'dc_removed_real',real(dc),'dc_removed_imag',imag(dc), ...
    'new_timing_fit',false,'new_phase_fit',false,'per_frame_alignment',false, ...
    'input_units','ADC counts','averaging','mean(abs(fractionally sampled IQ))', ...
    'read_policy','Same guarded FFT/interpolation helper as prior templates; fixed original training model.');
end

function writeMetricsCsv(path,summary)
fid=fopen(path,'w'); assert(fid>=0); cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'entity,split,roi_std,roi_mean,edge_horizontal_rms,edge_vertical_rms,row_mean_std,column_mean_std,anchor_structure_projection,display_low_clip,display_high_clip\n');
records=[summary.bands summary.methods];
for k=1:numel(records)
    r=records{k};
    if isfield(r,'fc_mhz'), label=sprintf('fc%dMHz',r.fc_mhz); else, label=r.name; end
    splits={'training','reused_test','fresh'};
    for si=1:numel(splits)
        if ~isfield(r,splits{si}), continue; end
        m=r.(splits{si});
        fprintf(fid,'%s,%s,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g\n', ...
            label,splits{si},m.uniform_roi_std,m.uniform_roi_mean,m.horizontal_difference_rms, ...
            m.vertical_difference_rms,m.row_mean_std,m.column_mean_std, ...
            m.structure_projection_to_training_anchor,m.display_low_clipped_fraction,m.display_high_clipped_fraction);
    end
end
end

function writePanels(root,train,test,fresh,limits,names,rectangle)
sets={train,test}; labels={'Reused train 0:7','Reused test 16:23'};
if ~isempty(fresh{1}), sets{3}=fresh; labels{3}='Later frames 64:71, frozen model'; end
fig=figure('Visible','off','Color','w','Position',[30 30 1350 500*numel(sets)]);
cleanup=onCleanup(@() close(fig));
tiledlayout(fig,numel(sets),3,'TileSpacing','compact');
for s=1:numel(sets)
    for k=1:3
        nexttile; imagesc(sets{s}{k}); axis image off; colormap gray; clim(limits);
        title(sprintf('%s | %s',labels{s},strrep(names{k},'_',' ')),'Interpreter','none');
    end
end
sgtitle('Image-level AM fusion | one shared training scale | not coherent RF stitching');
exportgraphics(fig,fullfile(root,'comparison_full.png'),Resolution=110);
fig2=figure('Visible','off','Color','w','Position',[40 40 1500 300*numel(sets)]);
cleanup2=onCleanup(@() close(fig2));
tiledlayout(fig2,numel(sets),3,'TileSpacing','compact');
r=rectangle;
for s=1:numel(sets)
    for k=1:3
        nexttile; imagesc(sets{s}{k}(r(1):r(2),r(3):r(4))); axis image off; colormap gray; clim(limits);
        title(sprintf('%s | %s',labels{s},strrep(names{k},'_',' ')),'Interpreter','none');
    end
end
sgtitle('Training-defined text crop | no image-specific rescaling or enhancement');
exportgraphics(fig2,fullfile(root,'comparison_text_crop.png'),Resolution=140);
end
