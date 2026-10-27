function report = renderIphoneCaf27(outputDirectory)
%RENDERIPHONECAF27 Measured images, cyclic phase and channel/control audit.
% Displays use B1-only ranges/baselines. Screenshot pixels are never rendered.
% Row semantics are reference-calibrated, and the horizontal axis is time,
% not decoded RGB pixels. CAF phases are correlation phases, not carrier phase.
arguments
    outputDirectory (1,1) string
end
data=load(fullfile(outputDirectory,'complex_caf.mat'));
fitData=load(fullfile(outputDirectory,'caf_channel_fits.mat'));
rows=size(data.images{1}.power,1);N=size(data.images{1}.power,2);
timeUs=((0:N-1)+0.5)/N/data.f0*1e6;
row=(0:rows-1)';
labels=double(data.labels);
names=["black","white","text"];
classColors=[0.18 0.22 0.28;0.68 0.72 0.78;0.9 0.38 0.12];
activeRow=(0:data.rowMeta.reference_height-1)';
captureIndex=mod(round(data.rowMeta.row_offset_zero_based+data.rowMeta.row_scale*activeRow),rows)+1;
white=labels==2;textRows=labels==3;
assert(any(white)&&any(textRows),'White and text row classes are required.');
% Raster baseline uses the raster's hard-bin convention, not the linearly
% deposited profile nodes used for CAF fitting.
whitePower=mean(data.images{1}.power(white,:),1);
whiteCaf=mean(data.images{1}.caf1(white,:),1);
referenceThreshold=max(1e-12,0.05*median(abs(whiteCaf)));
phaseReference=exp(-1i*angle(whiteCaf));
phaseReferenceValid=abs(whiteCaf)>=referenceThreshold;
views=cell(3,1);rowEnergy=cell(3,1);
effectRecords=repmat(struct(),1,3);
for bb=1:3
    power=data.images{bb}.power;
    caf=data.images{bb}.caf1;
    residual=caf-whiteCaf;
    projection=real(residual.*phaseReference);
    projection(:,~phaseReferenceValid)=NaN;
    rho=abs(caf)./max(data.images{bb}.caf1_norm,realmin);
    phase=angle(caf)*180/pi;
    phase(rho<0.2)=NaN;
    views{bb}=struct('power',power,'cafAbs',abs(residual), ...
        'cafProjection',projection,'cafPhaseDeg',phase,'rho',rho);
    powerEnergy=mean(abs(power-whitePower),2);
    cafEnergy=mean(abs(residual),2);
    projectedEnergy=mean(abs(projection),2,'omitnan');
    rowEnergy{bb}=struct('power',powerEnergy,'caf',cafEnergy,'projection',projectedEnergy);
    rec=struct('block',bb,'power_white_subtracted',effectSize(powerEnergy(textRows),powerEnergy(white)), ...
        'caf_white_subtracted',effectSize(cafEnergy(textRows),cafEnergy(white)), ...
        'caf_projection',effectSize(projectedEnergy(textRows),projectedEnergy(white)), ...
        'active_phase_valid_fraction',mean(isfinite(phase(captureIndex,:)),'all'));
    if bb==1,effectRecords=rec;else,effectRecords(bb)=rec;end
end
rangePower=finitePercentiles(views{1}.power(captureIndex,:),[5 95]);
rangeAbs=finitePercentiles(views{1}.cafAbs(captureIndex,:),[5 95]);
projectionLimit=max(abs(finitePercentiles(views{1}.cafProjection(captureIndex,:),[2 98])));
rangeProjection=[-projectionLimit projectionLimit];
trainingAbs=abs(fitData.target(:,:,:,1));
magnitudeLimit=finitePercentiles(trainingAbs,[0 99.5]);magnitudeLimit=[0 magnitudeLimit(2)];
realLimit=max(abs(finitePercentiles(real(fitData.target(:,:,:,1)),[.5 99.5])));
imagLimit=max(abs(finitePercentiles(imag(fitData.target(:,:,:,1)),[.5 99.5])));
halfVariance=abs(fitData.halves(:,:,:,1)-fitData.halves(:,:,:,2)).^2/2;
phaseThreshold=3*sqrt(halfVariance); % heuristic, not a calibrated significance test
selection=[fitData.validWinner fitData.matchedWinner fitData.controlWinner];
selectionNames=["Protocol","Matched control","Control-bank winner"];

% 01: training alignment and frozen semantic labels.
fig=figure('Name','CAF row states from training only','Color','w','Position',[30 30 1450 950]);
tl=tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl,1,[2 1]);showImage(ax,timeUs,row,data.images{1}.power,rangePower,gray(256));
xlabel(ax,'Within-period time (us)');ylabel(ax,'Capture row modulo 1881');
title(ax,'B1 native power; reference pixels not inserted');
ax=nexttile(tl,2,[2 1]);showImage(ax,1,row,labels,[-.5 3.5], ...
    [0.78 0.80 0.83;classColors]);
xticks(ax,[]);ylabel(ax,'Capture row modulo 1881');
cb=colorbar(ax);cb.Ticks=0:3;cb.TickLabels={'Unassigned','Black','White','Text'};
title(ax,'Frozen reference-calibrated classes');
ax=nexttile(tl,3);hold(ax,'on');
for cls=1:3
    ix=labels==cls;
    scatter(ax,row(ix),data.rowFeatures.combined(ix),5,classColors(cls,:), ...
        'filled','DisplayName',names(cls));
end
xlabel(ax,'Capture row');ylabel(ax,'Training alignment feature');
title(ax,sprintf('Offset=%d; row scale=%.4f',data.rowMeta.row_offset_zero_based,data.rowMeta.row_scale));
legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(tl,6);plot(ax,row,data.rowFeatures.correlation,'LineWidth',1);
xline(ax,data.rowMeta.row_offset_zero_based,'--','Selected B1 offset','HandleVisibility','off');
xlabel(ax,'Candidate reference-to-capture row offset');ylabel(ax,'Normalized G(k)');
title(ax,sprintf('Peak margin outside +/-5 rows: %.4f',data.rowMeta.peak_margin_outside_5rows));
grid(ax,'on');
title(tl,'Row labels use the known reference for calibration; they are not blind color decoding');
saveFigure(fig,outputDirectory,'01_row_states');

% 02: nonzero-lag CAF real/imag/magnitude/phase for all three classes.
fig=figure('Name','Class-conditioned nonzero-lag complex CAF','Color','w','Position',[45 40 1600 1000]);
tl=tiledlayout(fig,3,4,'TileSpacing','compact','Padding','compact');
alphaMHz=fitData.orders*data.f0/1e6;lagIndex=1:numel(fitData.lags);
for cls=1:3
    z=fitData.target(:,:,cls,2);
    phase=angle(z)*180/pi;
    phase(abs(z)<phaseThreshold(:,:,cls))=NaN;
    values={real(z),imag(z),abs(z),phase};
    limits={[-realLimit realLimit],[-imagLimit imagLimit],magnitudeLimit,[-180 180]};
    titles={"Re CAF","Im CAF","|CAF|","CAF phase (deg)"};
    palettes={blueRed(256),blueRed(256),parula(256),hsv(256)};
    for column=1:4
        ax=nexttile(tl);showImage(ax,alphaMHz,lagIndex,values{column}.',limits{column},palettes{column});
        set(ax,'YDir','normal','YTick',lagIndex,'YTickLabel',compose('%g',fitData.lags));
        xlabel(ax,'Cyclic frequency alpha (MHz)');ylabel(ax,'Lag d (native samples)');
        title(ax,names(cls)+" | B2 "+titles{column});
    end
end
title(tl,'Complex cyclic autocorrelation, held-out B2; phase masked below 3 x B1 half-difference scale');
saveFigure(fig,outputDirectory,'02_complex_caf_maps');

% 03: conditional channel estimates and local identifiability.
fig=figure('Name','Conditional three-lane channel estimates','Color','w','Position',[60 50 1400 900]);
tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
amplitudes=zeros(3,3);phases=amplitudes;
for kk=1:3
    result=fitData.results(selection(kk));
    amplitudes(:,kk)=result.relativeAmplitude(:);
    phases(:,kk)=result.relativePhaseDeg(:);
end
ax=nexttile(tl);bar(ax,0:2,amplitudes);xlabel(ax,'Assumed data lane');ylabel(ax,'Amplitude / strongest lane');
xticks(ax,0:2);title(ax,'One shared channel for black and white');legend(ax,selectionNames,'Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,0:2,phases);xlabel(ax,'Assumed data lane');ylabel(ax,'Relative phase (degrees)');
xticks(ax,0:2);ylim(ax,[-180 180]);title(ax,'Each fit: strongest lane phase fixed to zero');grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');
for kk=1:3
    result=fitData.results(selection(kk));sv=result.channelJacobianSingularValues(:);
    semilogy(ax,1:numel(sv),max(sv/max(sv(1),realmin),1e-16),'-o','DisplayName',selectionNames(kk));
end
set(ax,'YScale','log');
xlabel(ax,'Channel-Jacobian singular-value index');ylabel(ax,'sigma / sigma_1');
title(ax,'Five real channel degrees of freedom, fixed timing/model');legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(tl);axis(ax,'off');
lines=strings(0,1);
for kk=1:3
    result=fitData.results(selection(kk));
    lines(end+1,1)=sprintf('%s: %s',selectionNames(kk),result.name); %#ok<AGROW>
    lines(end+1,1)=sprintf('Rate hypothesis %.1f Mb/s | reference lane %d',result.rate_hz/1e6,result.referenceLaneZeroBased); %#ok<AGROW>
    lines(end+1,1)=sprintf('Design rank %d/9 | channel J rank %d/5 | cond %.3g',result.designRank,result.channelJacobianRank,result.channelJacobianCondition); %#ok<AGROW>
    lines(end+1,1)=""; %#ok<AGROW>
end
lines=[lines;"Absolute channel/RF phase is unobservable here."; ...
    "These are conditional, frequency-flat lane fits."; ...
    "No test block re-estimates a channel or delay."];
text(ax,0,1,lines,'Units','normalized','VerticalAlignment','top','FontSize',10,'Interpreter','none');
saveFigure(fig,outputDirectory,'03_channel_estimates');

% 04: frozen validation metrics, then phase residual without arbitrary rotation.
fig=figure('Name','Complex CAF protocol and control validation','Color','w','Position',[75 60 1450 1150]);
tl=tiledlayout(fig,3,2,'TileSpacing','compact','Padding','compact');
nmse=zeros(3,3);realCoherence=nmse;
for kk=1:3
    for bb=1:3
        nmse(bb,kk)=fitData.results(selection(kk)).blocks(bb).nmse;
        realCoherence(bb,kk)=fitData.results(selection(kk)).blocks(bb).real_coherence;
    end
end
ax=nexttile(tl);bar(ax,1:3,nmse);xticks(ax,1:3);xticklabels(ax,{'B1 train','B2 test','B3 test'});
ylabel(ax,'Weighted complex NMSE (lower is better)');title(ax,'Complex residual; no arbitrary phase alignment');
legend(ax,selectionNames,'Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,1:3,realCoherence);xticks(ax,1:3);xticklabels(ax,{'B1 train','B2 test','B3 test'});
ylabel(ax,'Real part of normalized complex inner product');title(ax,'Amplitude and phase consistency');grid(ax,'on');
phaseResidualReliable=zeros(2,2);
for candidate=1:2
    prediction=fitData.predictions{selection(candidate)};
    for cls=1:2
        measured=fitData.target(:,:,cls,2);
        predicted=prediction(:,:,cls);
        residualPhase=angle(predicted.*conj(measured))*180/pi;
        reliable=abs(measured)>=phaseThreshold(:,:,cls) & ...
            abs(predicted)>=phaseThreshold(:,:,cls);
        phaseResidualReliable(candidate,cls)=mean(reliable,'all');
        residualPhase(~reliable)=NaN;
        ax=nexttile(tl);showImage(ax,alphaMHz,lagIndex,residualPhase.',[-180 180],hsv(256));
        set(ax,'YDir','normal','YTick',lagIndex,'YTickLabel',compose('%g',fitData.lags));
        xlabel(ax,'Cyclic frequency alpha (MHz)');ylabel(ax,'Lag d (native samples)');
        title(ax,selectionNames(candidate)+" minus B2 | "+names(cls));
    end
end
saveFigure(fig,outputDirectory,'04_test_controls_and_phase');

% 05: measured reconstruction views; all four ranges are fixed using B1.
testPower=(data.images{2}.power+data.images{3}.power)/2;
testCaf=(data.images{2}.caf1+data.images{3}.caf1)/2;
testNorm=(data.images{2}.caf1_norm+data.images{3}.caf1_norm)/2;
testResidual=testCaf-whiteCaf;
testAbs=abs(testResidual);
testProjection=real(testResidual.*phaseReference);testProjection(:,~phaseReferenceValid)=NaN;
testRho=abs(testCaf)./max(testNorm,realmin);
testPhase=angle(testCaf)*180/pi;testPhase(testRho<.2)=NaN;
panels={testPower(captureIndex,:),testAbs(captureIndex,:), ...
    testProjection(captureIndex,:),testPhase(captureIndex,:)};
limits={rangePower,rangeAbs,rangeProjection,[-180 180]};
palettes={gray(256),gray(256),blueRed(256),hsv(256)};
panelTitles={"Native power control","|CAF(d=1) - B1 white|", ...
    "Phase-referenced CAF residual","CAF(d=1) phase; rho >= 0.2"};
fig=figure('Name','Measured complex-CAF reconstruction views','Color','w','Position',[90 70 1650 1000]);
tl=tiledlayout(fig,1,4,'TileSpacing','compact','Padding','compact');
for kk=1:4
    ax=nexttile(tl);showImage(ax,timeUs,activeRow,panels{kk},limits{kk},palettes{kk});
    xlabel(ax,'Within-period time (us)');
    ylabel(ax,'Reference-aligned active row (hypothesis)');title(ax,panelTitles{kk});
end
title(tl,'Held-out B2/B3 mean; B1-fixed ranges and baseline; measured pixels only, no RGB-byte decoding');
saveFigure(fig,outputDirectory,'05_measured_reconstruction');
fileNames=["screen_power_B23","screen_caf_abs_B23","screen_caf_projection_B23","screen_caf_phase_B23"];
for kk=1:4
    rgb=mapImage(panels{kk},limits{kk},palettes{kk});
    imwrite(rgb,fullfile(outputDirectory,fileNames(kk)+".png"));
end
% 06: report every block's text/white separation, including negative cases.
effect=zeros(3,3);
for bb=1:3
    effect(bb,:)=[effectRecords(bb).power_white_subtracted.standardized_effect, ...
        effectRecords(bb).caf_white_subtracted.standardized_effect, ...
        effectRecords(bb).caf_projection.standardized_effect];
end
fig=figure('Name','Frozen-baseline row separation diagnostic','Color','w','Position',[100 80 1350 850]);
tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl);bar(ax,1:3,effect);xticks(ax,1:3);xticklabels(ax,{'B1 train','B2 test','B3 test'});
ylabel(ax,'(mean text - mean white) / pooled row SD');
title(ax,'Descriptive class separation, not SNR or decoding accuracy');
legend(ax,'Power residual','Complex CAF residual','Phase projection','Location','southoutside');grid(ax,'on');
for bb=1:3
    ax=nexttile(tl);hold(ax,'on');
    plot(ax,row,rowEnergy{bb}.power,'DisplayName','Power residual');
    plot(ax,row,rowEnergy{bb}.caf,'DisplayName','Complex CAF residual');
    plot(ax,row,rowEnergy{bb}.projection,'DisplayName','Phase projection');
    xlabel(ax,'Capture row modulo 1881');ylabel(ax,'Mean absolute residual / B1 mean power');
    title(ax,sprintf('B%d: all rows, frozen B1 white baseline',bb));legend(ax,'Location','best');grid(ax,'on');
end
saveFigure(fig,outputDirectory,'06_row_separation');
tableOut=table((1:3)',effect(:,1),effect(:,2),effect(:,3), ...
    [effectRecords.active_phase_valid_fraction]', ...
    'VariableNames',{'Block','PowerResidualEffect','ComplexCafResidualEffect','PhaseProjectionEffect','ActivePhaseValidFraction'});
writetable(tableOut,fullfile(outputDirectory,'row_separation.csv'));
report=struct('row_semantics',data.rowMeta.scope,'row_mapping',data.rowMeta.mapping, ...
    'reference_pixels_rendered',false,'horizontal_axis','Within-period time, not decoded pixel column.', ...
    'normalization','All power/CAF values divided by B1 native mean power.', ...
    'baseline','B1 raster mean over frozen white row labels; no test fitting.', ...
    'effect_size_meaning','Difference of text/white row mean absolute residual energies divided by pooled within-class SD; descriptive, not SNR.', ...
    'effects',effectRecords,'phase_rho_threshold',0.2, ...
    'phase_mask_meaning','Local lag-one correlation magnitude divided by mean endpoint power; heuristic confidence mask.', ...
    'phase_reference_valid_fraction',mean(phaseReferenceValid), ...
    'B2_phase_residual_reliable_fraction_protocol_then_matched_by_black_white',phaseResidualReliable, ...
    'caf_harmonic_phase_mask','Measured and, for residuals, predicted magnitude >=3*B1 half-difference scale; heuristic.', ...
    'fixed_B1_display_ranges',struct('power',rangePower,'caf_residual_abs',rangeAbs, ...
        'phase_projection',rangeProjection,'phase_deg',[-180 180]), ...
    'validation_image_blocks',[2 3],'phase_interpretation','Lag-product/cyclic-correlation phase, not RF carrier or recovered RGB hue.');
writeJson(fullfile(outputDirectory,'render_summary.json'),report);
save(fullfile(outputDirectory,'reconstruction_views.mat'),'whitePower','whiteCaf','phaseReference', ...
    'phaseReferenceValid','captureIndex','activeRow','panels','limits','effectRecords','rowEnergy','report','-v7.3');
end

function result=effectSize(text,white)
text=text(isfinite(text));white=white(isfinite(white));
nt=numel(text);nw=numel(white);
meanText=mean(text);meanWhite=mean(white);
pooled=sqrt(((nt-1)*var(text)+(nw-1)*var(white))/max(nt+nw-2,1));
result=struct('text_rows',nt,'white_rows',nw,'mean_text',meanText,'mean_white',meanWhite, ...
    'pooled_row_standard_deviation',pooled, ...
    'standardized_effect',(meanText-meanWhite)/max(pooled,realmin));
end
function range=finitePercentiles(values,percentages)
values=values(isfinite(values));
assert(~isempty(values),'No finite values available for display range.');
range=prctile(values,percentages);
if range(end)<=range(1),range(end)=range(1)+max(1,abs(range(1)))*1e-6;end
end
function showImage(ax,x,y,values,limits,palette)
im=imagesc(ax,x,y,values);
set(im,'AlphaData',isfinite(values));
set(ax,'Color',[.7 .72 .75],'YDir','reverse');
clim(ax,limits);colormap(ax,palette);colorbar(ax);
end
function saveFigure(fig,out,name)
exportgraphics(fig,fullfile(out,name+".png"),'Resolution',145);
savefig(fig,fullfile(out,name+".fig"));
end
function rgb=mapImage(values,limits,palette)
q=(values-limits(1))/(limits(2)-limits(1));
valid=isfinite(q);q(~valid)=0;q=min(1,max(0,q));
index=1+round(q*(size(palette,1)-1));
rgb=reshape(palette(index(:),:),size(values,1),size(values,2),3);
for channel=1:3
    plane=rgb(:,:,channel);plane(~valid)=.7;rgb(:,:,channel)=plane;
end
rgb=uint8(round(255*rgb));
end
function palette=blueRed(n)
u=linspace(0,1,n)';
palette=[min(1,2*u),1-abs(2*u-1),min(1,2*(1-u))];
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
