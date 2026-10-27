function report=renderFramePcaDiagnostics27(outputDirectory,oldDirectory)
%RENDERFRAMEPCADIAGNOSTICS27 Frame-PCA component/CAF validation figures.
% This renderer does not change PCA choices, temporal weights or fitted data.
% CAF magnitude and phase-projected residuals are diagnostics, not the IQ
% binary decision path. Only B1 defines baselines, phase references and ranges.
arguments
    outputDirectory (1,1) string
    oldDirectory (1,1) string
end
p=load(fullfile(outputDirectory,'pca_image_data.mat'));
t=load(fullfile(outputDirectory,'training_pca.mat'));
old=load(fullfile(oldDirectory,'complex_caf.mat'),'images');
labels=double(p.imageData.labels(:));R=numel(labels);N=size(p.allComponentImages{1},2);
sourceRows=(0:p.imageData.rowMeta.reference_height-1)';
activeIndex=mod(round(p.imageData.rowMeta.row_offset_zero_based+ ...
    p.imageData.rowMeta.row_scale*sourceRows),R)+1;
timeUs=((0:N-1)+.5)/N/p.imageData.f0*1e6;
white=labels==2;textRows=labels==3;
prior=struct('name',"prior_CAF",'caf',{{old.images{1}.caf1,old.images{2}.caf1,old.images{3}.caf1}}, ...
    'power',{{old.images{1}.power,old.images{2}.power,old.images{3}.power}});
methods=prior;
wanted=["rawgrid","PC1","selected","top2"];
allNames=string({p.cafMethods.name});
for name=wanted
    index=find(allNames==name,1);
    assert(~isempty(index),'Missing requested CAF comparison method.');
    methods(end+1)=p.cafMethods(index); %#ok<AGROW>
end
M=numel(methods);K=numel(t.lambda);scores=t.scores;
energy=double(t.lambda(:))/sum(double(t.lambda));
componentNorm=zeros(K,1);rangeSamples=[];
for kk=1:K
    im=double(p.allComponentImages{1}(activeIndex,:,kk));
    componentNorm(kk)=mean(im,'all','omitnan');
    q=im/max(componentNorm(kk),realmin);
    samples=q(1:17:end);
    rangeSamples=[rangeSamples;samples(:)]; %#ok<AGROW>
end
componentRange=finiteRange(rangeSamples,[2 98]);

% 01: first-PC energy, CAF score and the observed fixed-stripe fraction.
fig=figure('Name','Frame PCA energy and cyclic selection','Color','w','Position',[30 30 1450 950]);
tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl);bar(ax,1:K,energy);
yline(ax,1/K,':','Equal-energy reference','HandleVisibility','off');
xlabel(ax,'PCA component');ylabel(ax,'lambda / sum(lambda)');
title(ax,'Temporal PCA singular energy; not physical source labels');grid(ax,'on');xticks(ax,1:K);
ax=nexttile(tl);bar(ax,scores.Component,scores.Score);hold(ax,'on');
scatter(ax,t.selected,scores.Score(t.selected),85,[.9 .25 .1],'filled','DisplayName','B1-selected');
xlabel(ax,'PCA component');ylabel(ax,'Heuristic CAF selection score');
title(ax,sprintf('B1 selects PC%d; top components %s',t.selected,mat2str(t.top2)));
grid(ax,'on');xticks(ax,1:K);
ax=nexttile(tl);bar(ax,scores.Component,scores.VerticalStripePowerFraction);
xlabel(ax,'PCA component');ylabel(ax,'Fixed-column stripe energy / centered power energy');
title(ax,'Stripe fraction does not identify an exclusive physical source');grid(ax,'on');xticks(ax,1:K);ylim(ax,[0 1]);
ax=nexttile(tl);bar(ax,scores.Component,[scores.ContrastCafStrength scores.OffCycleContrastStrength]);
xlabel(ax,'PCA component');ylabel(ax,'Normalized class-contrast CAF RMS');
title(ax,'Target cyclic harmonics versus shifted-cycle control');
legend(ax,'h f_0','(h+0.37) f_0','Location','best');grid(ax,'on');xticks(ax,1:K);
saveFigure(fig,outputDirectory,'pca_01_energy_caf_stripes');

% 02: all eight component powers; per-component B1 normalization is explicit.
fig=figure('Name','All training frame-PCA component power images','Color','w','Position',[40 40 1900 1250]);
tl=tiledlayout(fig,2,4,'TileSpacing','compact','Padding','compact');
for kk=1:K
    ax=nexttile(tl);
    im=double(p.allComponentImages{1}(activeIndex,:,kk))/max(componentNorm(kk),realmin);
    showImage(ax,timeUs,sourceRows,im,componentRange,gray(256));
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,sprintf('PC%d | energy %.2f%% | stripe %.1f%%', ...
        kk,100*energy(kk),100*scores.VerticalStripePowerFraction(kk)));
end
title(tl,'B1 powers divided by each PC B1-active mean; ONE shared B1-derived range; no pixel reconstruction from reference');
saveFigure(fig,outputDirectory,'pca_02_all_component_powers');

% Per-method baselines are frozen on B1. Display normalization does not alter
% metrics; it accounts for different energy budgets after selecting PCs.
views=cell(1,M);records=struct([]);residualSamples=[];projectionSamples=[];
rowDiagnostics=cell(M,3);parameters=struct([]);
for mm=1:M
    caf1=double(methods(mm).caf{1});power1=double(methods(mm).power{1});
    whiteCaf=mean(caf1(white,:),1,'omitnan');
    whitePower=mean(power1(white,:),1,'omitnan');
    normPower=mean(power1(activeIndex,:),'all','omitnan');
    normPower=max(normPower,realmin);
    phaseFloor=max(1e-12,.05*median(abs(whiteCaf),'omitnan'));
    validPhase=isfinite(whiteCaf)&abs(whiteCaf)>=phaseFloor;
    phaseReference=exp(-1i*angle(whiteCaf));
    trainResidual=(caf1-whiteCaf)/normPower;
    trainProjection=real(trainResidual.*phaseReference);
    trainProjection(:,~validPhase)=NaN;
    x=abs(trainResidual(activeIndex,:));residualSamples=[residualSamples;x(1:17:end).']; %#ok<AGROW>
    x=trainProjection(activeIndex,:);projectionSamples=[projectionSamples;x(1:17:end).']; %#ok<AGROW>
    trainContrast=mean(caf1(textRows,:),1,'omitnan')-mean(caf1(white,:),1,'omitnan');
    contrastFloor=max(1e-12,.05*median(abs(trainContrast),'omitnan'));
    reliableContrast=isfinite(trainContrast)&abs(trainContrast)>=contrastFloor;
    blockRecords=struct([]);
    for bb=1:3
        caf=double(methods(mm).caf{bb});power=double(methods(mm).power{bb});
        residual=(caf-whiteCaf)/normPower;
        projected=real(residual.*phaseReference);projected(:,~validPhase)=NaN;
        powerEnergy=mean(abs((power-whitePower)/normPower),2,'omitnan');
        cafEnergy=mean(abs(residual),2,'omitnan');
        projectionEnergy=mean(abs(projected),2,'omitnan');
        contrast=mean(caf(textRows,:),1,'omitnan')-mean(caf(white,:),1,'omitnan');
        consistency=phaseConsistency(trainContrast,contrast,reliableContrast);
        bRec=struct('block',bb, ...
            'power_text_white_effect',effectSize(powerEnergy(textRows),powerEnergy(white)), ...
            'caf_abs_text_white_effect',effectSize(cafEnergy(textRows),cafEnergy(white)), ...
            'caf_projection_text_white_effect',effectSize(projectionEnergy(textRows),projectionEnergy(white)), ...
            'class_contrast_phase_consistency',consistency, ...
            'finite_caf_fraction',mean(isfinite(caf(activeIndex,:)),'all'));
        if bb==1,blockRecords=bRec;else,blockRecords(bb)=bRec;end
        rowDiagnostics{mm,bb}=struct('power',powerEnergy,'caf_abs',cafEnergy,'projection',projectionEnergy);
    end
    testCaf=mean(cat(3,double(methods(mm).caf{2}),double(methods(mm).caf{3})),3,'omitnan');
    residual=(testCaf-whiteCaf)/normPower;
    projected=real(residual.*phaseReference);projected(:,~validPhase)=NaN;
    views{mm}=struct('absolute',abs(residual(activeIndex,:)), ...
        'projection',projected(activeIndex,:));
    param=struct('name',string(methods(mm).name),'B1_mean_power',normPower, ...
        'B1_white_caf',whiteCaf,'B1_white_power',whitePower, ...
        'B1_phase_reference',phaseReference,'B1_phase_valid',validPhase);
    if mm==1,parameters=param;else,parameters(mm)=param;end
    rec=struct('name',string(methods(mm).name),'B1_mean_power',normPower, ...
        'phase_reference_valid_fraction',mean(validPhase),'blocks',blockRecords);
    if mm==1,records=rec;else,records(mm)=rec;end
end
absRange=finiteRange(residualSamples,[2 98]);
projectionLimit=max(abs(finiteRange(projectionSamples,[2 98])));
projectionRange=[-projectionLimit projectionLimit];

% 03: previous CAF, new aligned-grid CAF, and frozen temporal-PC projections.
fig=figure('Name','CAF diagnostics before and after frame PCA','Color','w', ...
    'Position',[60 50 2000 1250]);
tl=tiledlayout(fig,2,M,'TileSpacing','compact','Padding','compact');
for mm=1:M
    ax=nexttile(tl,mm);showImage(ax,timeUs,sourceRows,views{mm}.absolute,absRange,gray(256));
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,string(methods(mm).name)+" | |CAF - B1 white|",'Interpreter','none');
    ax=nexttile(tl,M+mm);showImage(ax,timeUs,sourceRows,views{mm}.projection,projectionRange,blueRed(256));
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,'Re[(CAF - B1 white) exp(-j phase B1 white)]');
end
title(tl,'B2/B3 mean CAF diagnostics; each / its B1 mean power; own B1 phase reference; NOT the binary-decision pipeline');
saveFigure(fig,outputDirectory,'pca_03_caf_residual_and_phase_projection');

% 04: independent blocks, dimensionless effects and complex pattern agreement.
effects=zeros(M,3,3);realCosine=zeros(M,3);absCosine=realCosine;
phaseDelta=realCosine;phaseConcentration=realCosine;
for mm=1:M
    for bb=1:3
        r=records(mm).blocks(bb);
        effects(mm,bb,:)=[r.power_text_white_effect.standardized_effect, ...
            r.caf_abs_text_white_effect.standardized_effect, ...
            r.caf_projection_text_white_effect.standardized_effect];
        c=r.class_contrast_phase_consistency;
        realCosine(mm,bb)=c.real_cosine;absCosine(mm,bb)=c.absolute_cosine;
        phaseDelta(mm,bb)=c.inner_product_phase_deg;
        phaseConcentration(mm,bb)=c.weighted_phase_concentration;
    end
end
names=string({methods.name});
fig=figure('Name','Held-out frame-PCA CAF diagnostics','Color','w','Position',[80 60 1550 1050]);
tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl);bar(ax,squeeze(effects(:,2,:)));
set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylabel(ax,'Text-white difference / pooled row SD');title(ax,'B2: row-energy effect, not SNR or OCR accuracy');
legend(ax,'Power residual','CAF magnitude residual','CAF phase projection','Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,squeeze(effects(:,3,:)));
set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylabel(ax,'Text-white difference / pooled row SD');title(ax,'B3: same frozen B1 preprocessing');grid(ax,'on');
ax=nexttile(tl);bar(ax,[realCosine(:,2:3) absCosine(:,2:3)]);
set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);ylim(ax,[-1 1]);
ylabel(ax,'Normalized complex pattern inner product');
title(ax,'Measured text-minus-white lag-1 CAF pattern consistency');
legend(ax,'Re B1-B2','Re B1-B3','Abs B1-B2','Abs B1-B3','Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,phaseDelta(:,2:3));
set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylabel(ax,'arg(<B1 contrast, test contrast>) degrees');ylim(ax,[-180 180]);
title(ax,'No arbitrary phase rotation fitted to test');legend(ax,'B2','B3','Location','best');grid(ax,'on');
saveFigure(fig,outputDirectory,'pca_04_validation_effects_and_phase');

rowsOut=cell(M*3,10);
for mm=1:M
    for bb=1:3
        r=records(mm).blocks(bb);c=r.class_contrast_phase_consistency;
        rowsOut((mm-1)*3+bb,:)={names(mm),bb, ...
            r.power_text_white_effect.standardized_effect, ...
            r.caf_abs_text_white_effect.standardized_effect, ...
            r.caf_projection_text_white_effect.standardized_effect, ...
            c.real_cosine,c.absolute_cosine,c.inner_product_phase_deg, ...
            c.weighted_phase_concentration,records(mm).phase_reference_valid_fraction};
    end
end
metrics=cell2table(rowsOut,'VariableNames',{'Method','Block','PowerEffect','CafAbsEffect', ...
    'CafPhaseProjectionEffect','ContrastRealCosine','ContrastAbsCosine', ...
    'ContrastPhaseDeltaDegrees','WeightedPhaseConcentration','PhaseReferenceValidFraction'});
writetable(metrics,fullfile(outputDirectory,'pca_diagnostics_metrics.csv'));
report=struct('matrix','within-frame sample positions by8 measured frames', ...
    'component_energy_fraction',energy,'selected_component',t.selected,'top2_components',t.top2, ...
    'PC1_stripe_fraction',scores.VerticalStripePowerFraction(1), ...
    'all_component_stripe_fractions',scores.VerticalStripePowerFraction, ...
    'PC1_interpretation','Largest energy component, not an exclusive physical stripe or driver source.', ...
    'selection_scope','Frozen B1-only CAF heuristic from training_pca.mat; this renderer does not reselect.', ...
    'component_image_normalization','Each component divided by its own B1 active-row mean; all share one B1-derived display range.', ...
    'component_B1_mean_powers',componentNorm,'component_power_display_range',componentRange, ...
    'caf_display_normalization','Each method divided by its B1 active mean power; fixed B1 white baseline and own B1 white CAF phase.', ...
    'caf_magnitude_display_range',absRange,'caf_phase_projection_display_range',projectionRange, ...
    'test_image_blocks',[2 3],'reference_pixels_rendered',false, ...
    'binary_threshold_uses_these_caf_images',false, ...
    'phase_meaning','Nonzero-lag correlation phase, not RF carrier or RGB hue.', ...
    'phase_consistency_definition','Complex cosine of each block measured text-minus-white CAF profile; no fitted test rotation.', ...
    'phase_consistency_test_white_mean','Used only to measure class contrast; it does not change frozen image baselines or classifiers.', ...
    'effect_definition','Mean absolute per-row residual energy text-white difference / pooled within-class row SD; not SNR or text pixel accuracy.', ...
    'comparison_scope','Prior CAF has its prior native hard-bin windows; rawgrid/PC methods share newly aligned eight-frame windows. Rawgrid isolates PCA changes.', ...
    'methods',records);
writeJson(fullfile(outputDirectory,'pca_diagnostics_summary.json'),report);
save(fullfile(outputDirectory,'pca_diagnostics_compact.mat'),'report','metrics', ...
    'parameters','rowDiagnostics','activeIndex','sourceRows','timeUs','-v7.3');
end

function result=effectSize(a,b)
a=a(isfinite(a));b=b(isfinite(b));na=numel(a);nb=numel(b);
assert(na>1&&nb>1,'Insufficient finite row energies.');
pooled=sqrt(((na-1)*var(a)+(nb-1)*var(b))/max(na+nb-2,1));
result=struct('text_count',na,'white_count',nb,'mean_text',mean(a),'mean_white',mean(b), ...
    'pooled_row_sd',pooled,'standardized_effect',(mean(a)-mean(b))/max(pooled,realmin));
end
function result=phaseConsistency(a,b,mask)
mask=mask&isfinite(a)&isfinite(b);a=a(mask);b=b(mask);
if isempty(a)||norm(a)*norm(b)==0
    z=NaN;concentration=NaN;
else
    z=sum(conj(a).*b)/(norm(a)*norm(b));
    w=abs(a).*abs(b);
    concentration=abs(sum(w.*exp(1i*angle(b.*conj(a)))))/max(sum(w),realmin);
end
result=struct('real_cosine',real(z),'absolute_cosine',abs(z), ...
    'inner_product_phase_deg',angle(z)*180/pi, ...
    'weighted_phase_concentration',concentration,'columns',nnz(mask), ...
    'scope','Class-contrast lag1 pattern agreement, not mscohere or a significance probability.');
end
function range=finiteRange(x,pct)
x=double(x(isfinite(x)));assert(~isempty(x));range=prctile(x,pct);
if range(end)<=range(1),range(end)=range(1)+max(1,abs(range(1)))*1e-6;end
end
function showImage(ax,x,y,values,limits,palette)
im=imagesc(ax,x,y,values);set(im,'AlphaData',isfinite(values));
set(ax,'YDir','reverse','Color',[.7 .7 .7]);clim(ax,limits);colormap(ax,palette);colorbar(ax);
end
function palette=blueRed(n)
u=linspace(0,1,n)';palette=[min(1,2*u),1-abs(2*u-1),min(1,2*(1-u))];
end
function saveFigure(fig,out,name)
exportgraphics(fig,fullfile(out,name+".png"),'Resolution',145);
savefig(fig,fullfile(out,name+".fig"));
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
