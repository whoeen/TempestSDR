function result=auditImageFusionContrastControl
%AUDITIMAGEFUSIONCONTRASTCONTROL Compare flatness at fixed training structure.
lab=fileparts(mfilename('fullpath'));addpath(fullfile(lab,'signal_processing'));
root=fullfile(lab,'results','iphone6_followup_20261024','image_fusion');
out=fullfile(root,'contrast_matched_control');assert(~isfolder(out),'audit:Exists','Refuse overwrite');mkdir(out);
x=load(fullfile(root,'fusion_images.mat'));
p=load(fullfile(root,'frozen_parameters.mat'));
methods=x.summary.methods; anchorMean=methods{1}.training.uniform_roi_mean;
gains=zeros(1,3);offsets=zeros(1,3);records=struct([]);
sets={x.fusionTrain,x.fusionTest,x.fusionFresh};
names={'training','reused_test','later64_71'}; adjusted=cell(3,3);
for j=1:3
 gains(j)=1/methods{j}.training.structure_projection_to_training_anchor;
 offsets(j)=anchorMean-gains(j)*methods{j}.training.uniform_roi_mean;
 for split=1:3
  a=gains(j)*double(sets{split}{j})+offsets(j);
  adjusted{split,j}=a;
  g=.5*(circshift(a,[-1 0])-circshift(a,[1 0]));g=g-mean(g,1);g=g-mean(g,2);
  v=g(p.featureMask);
  r=struct('method',x.methodNames{j},'partition',names{split},'fixed_training_gain',gains(j), ...
   'fixed_training_offset',offsets(j),'uniform_roi_std',std(a(p.flatMask)), ...
   'structure_projection',dot(v,p.anchorVector)/p.anchorEnergy, ...
   'structure_gradient_rms',sqrt(mean(v.^2)));
  records=[records;r]; %#ok<AGROW>
 end
end
result=struct('status','complete','gains_fitted_only_on_training',gains, ...
 'offsets_fitted_only_on_training',offsets,'records',records, ...
 'purpose','Test whether the apparent flatness improvement is only attenuation of useful structure.', ...
 'limitation','Anchor gradient includes clutter and may drift. This is a contrast-controlled proxy, not OCR or pixel fidelity.');
writeJsonFile(fullfile(out,'metrics.json'),result);
writetable(struct2table(records),fullfile(out,'metrics.csv'));
fig=figure('Visible','off','Color','w','Position',[80 80 1500 760]);cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
tiledlayout(2,3,'TileSpacing','compact');
rc=x.summary.structure_roi_rectangle_one_based;
for split=[1 3]
 for j=1:3
  nexttile;imagesc(adjusted{split,j}(rc(1):rc(2),rc(3):rc(4)),p.displayLimits);axis image off;colormap gray;
  title(sprintf('%s | %s',names{split},x.methodNames{j}),'Interpreter','none');
 end
end
sgtitle('Text region: training structure contrast matched, same display limits');
exportgraphics(fig,fullfile(out,'contrast_matched_text.png'),Resolution=140);
end
