function [labels,metadata,features] = buildIphoneRowLabelsCaf27(trainingRaster,outputDirectory)
%BUILDIPHONEROWLABELSCAF27 Calibrate row labels using the known test screen.
%   [LABELS,META,FEATURES] = buildIphoneRowLabelsCaf27(B1RASTER,OUT)
%   uses TRAINING raster only. Labels: 0=unassigned/boundary, 1=black,
%   2=white, 3=text. This is supervised row-position calibration, not blind
%   color decoding. The screenshot never fills or substitutes measured pixels.
%   Keep returned labels fixed for every validation block.
arguments
    trainingRaster (:,:) double {mustBeReal,mustBeFinite,mustBeNonnegative}
    outputDirectory (1,1) string = ""
end
rowCount=size(trainingRaster,1);
assert(rowCount==1881,'This calibration uses the prior 1881-row frame hypothesis.');
referencePath="C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png";
reference=imread(referencePath);
assert(size(reference,1)==1334&&size(reference,2)==750,'Unexpected reference dimensions.');
if size(reference,3)>1
    isBlack=all(reference(:,:,1:3)==0,3);
    isWhite=all(reference(:,:,1:3)==255,3);
else
    isBlack=reference==0;isWhite=reference==255;
end
referenceLabels=3*ones(size(reference,1),1,'uint8');
referenceLabels(all(isBlack,2))=1;
referenceLabels(all(isWhite,2))=2;
columnMedian=median(trainingRaster,1);
[~,columnOrder]=sort(columnMedian,'ascend');
keep=columnOrder(1:round(0.7*size(trainingRaster,2)));
rowMean=mean(trainingRaster,2);
rowResidualAbs=mean(abs(trainingRaster-columnMedian),2);
rowPayloadStd=std(trainingRaster(:,keep),0,2);
components=[robustFeature(rowMean),robustFeature(rowResidualAbs), ...
    robustFeature(rowPayloadStd)];
feature=mean(components,2);
feature=feature-mean(feature);feature=feature/norm(feature);
rows=(0:rowCount-1)';
scales=(0.98:0.002:1.02)';
scores=zeros(size(scales));offsets=zeros(size(scales));
allG=zeros(rowCount,numel(scales));
for ii=1:numel(scales)
    template=interp1((0:numel(referenceLabels)-1)',double(referenceLabels==3), ...
        rows/scales(ii),'linear',0);
    template=smoothCircular(template);
    template=template-mean(template);template=template/norm(template);
    g=real(ifft(conj(fft(template)).*fft(feature)));
    [scores(ii),ix]=max(g);offsets(ii)=ix-1;allG(:,ii)=g;
end
[bestScore,bestIndex]=max(scores);
[~,unitIndex]=min(abs(scales-1));
% A fixed conservative criterion: retain native-row scale unless improvement
% over scale1 exceeds 0.01 absolute correlation. This is not a confidence test.
minimumScaleGain=0.01;
selected=unitIndex;
if bestScore-scores(unitIndex)>minimumScaleGain,selected=bestIndex;end
scale=scales(selected);offset=offsets(selected);
sourceCoordinate=mod(rows-offset,rowCount)/scale;
active=sourceCoordinate>=0 & sourceCoordinate<=numel(referenceLabels)-1;
rawLabels=zeros(rowCount,1,'uint8');
rawLabels(active)=referenceLabels(round(sourceCoordinate(active))+1);
% Exclude +/-2 capture rows around EVERY class/active-boundary transition.
labels=rawLabels;
for shift=[-2 -1 1 2]
    labels(rawLabels~=circshift(rawLabels,shift))=0;
end
aliases=mod(offset+[-100 -50 0 50 100],rowCount);
aliasScores=allG(aliases+1,selected);
competitor=allG(:,selected);
distance=abs(mod(rows-offset+rowCount/2,rowCount)-rowCount/2);
competitor(distance<=5)=-Inf;
[otherScore,otherIndex]=max(competitor);
metadata=struct('scope','Supervised row-position calibration from known reference, training B1 only.', ...
    'reference_path',referencePath,'reference_width',750,'reference_height',1334, ...
    'reference_used_for','Row labels and alignment only; never substituted into measured images.', ...
    'frame_rows_prior',rowCount,'row_offset_zero_based',offset,'row_scale',scale, ...
    'mapping','capture_row = mod(offset + scale * source_row, 1881)', ...
    'selected_training_correlation',scores(selected),'scale1_correlation',scores(unitIndex), ...
    'unconstrained_best_scale',scales(bestIndex),'unconstrained_best_offset',offsets(bestIndex), ...
    'unconstrained_best_correlation',bestScore, ...
    'scale_selection_minimum_gain',minimumScaleGain, ...
    'alias_offsets_zero_based',aliases,'alias_correlations',aliasScores.', ...
    'best_competing_offset_outside_5rows',otherIndex-1,'competing_correlation',otherScore, ...
    'peak_margin_outside_5rows',scores(selected)-otherScore, ...
    'boundary_exclusion_capture_rows',2, ...
    'label_counts',struct('unassigned',sum(labels==0),'black',sum(labels==1), ...
    'white',sum(labels==2),'text',sum(labels==3)), ...
    'reference_label_counts',struct('black',sum(referenceLabels==1), ...
    'white',sum(referenceLabels==2),'text',sum(referenceLabels==3)), ...
    'unassigned_meaning','Includes inter-frame/transport interval candidate plus excluded boundaries; not verified blanking.', ...
    'polarity_independent',true,'validation_used_for_selection',false, ...
    'physical_limits',["Known screenshot alignment is not independent color decoding."; ...
    "Actual host transport mode, active row mapping and frame origin remain hypotheses."; ...
    "Same text repeats every50source rows, so +/-50row aliases are explicitly recorded."; ...
    "A scale threshold or correlation margin is not a statistical confidence interval."]);
features=struct('row',rows,'row_mean',rowMean,'row_residual_abs',rowResidualAbs, ...
    'row_payload_std',rowPayloadStd,'kept_columns',keep,'components',components, ...
    'combined',feature,'scales',scales,'offsets',offsets,'scores',scores, ...
    'correlation',allG(:,selected),'raw_labels',rawLabels, ...
    'reference_labels',referenceLabels,'source_coordinate',sourceCoordinate);
if strlength(outputDirectory)>0
    if ~isfolder(outputDirectory),mkdir(outputDirectory);end
    fid=fopen(fullfile(outputDirectory,'row_label_metadata.json'),'w','n','UTF-8');
    assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
    fwrite(fid,jsonencode(metadata,'PrettyPrint',true),'char');
    tab=table(rows,labels,rawLabels,sourceCoordinate,rowMean,rowResidualAbs,rowPayloadStd,feature, ...
        'VariableNames',{'CaptureRowZeroBased','Label','RawLabel','ReferenceRowCoordinate', ...
        'TrainingMeanPower','TrainingResidualAbs','TrainingPayloadStd','TrainingFeature'});
    writetable(tab,fullfile(outputDirectory,'row_labels.csv'));
    save(fullfile(outputDirectory,'row_labels.mat'),'labels','metadata','features');
end
end

function out=robustFeature(v)
N=numel(v);
extended=[v(end-49:end);v;v(1:50)];
baseline=movmedian(extended,101);
v=v-baseline(51:N+50);
v=smoothCircular(v);
ordered=sort(v);
low=ordered(max(1,ceil(.01*N)));high=ordered(min(N,ceil(.99*N)));
v=min(high,max(low,v));
v=v-mean(v);
assert(norm(v)>0,'Training row feature has zero variation.');
out=v/norm(v);
end

function out=smoothCircular(v)
extended=[v(end-1:end);v;v(1:2)];
out=conv(extended,[1;4;6;4;1]/16,'valid');
end
