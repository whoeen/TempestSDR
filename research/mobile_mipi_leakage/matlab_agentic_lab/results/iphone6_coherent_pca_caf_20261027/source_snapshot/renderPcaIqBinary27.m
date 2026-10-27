function [report,derived] = renderPcaIqBinary27(data,methods,outputDirectory)
%RENDERPCAIQBINARY27 Linear complex-IQ feature projection followed by bits.
%   [REPORT,DERIVED]=renderPcaIqBinary27(DATA,METHODS,OUT) uses METHODS(m).iq
%   as {B1,B2,B3}, each R-by-C-by-D complex IQ features in a fixed common
%   time/phase convention. METHODS(m).name names the method. DATA has labels
%   (0 unknown,1 black,2 white,3 text), rowMeta and f0.
%
%   Only B1 uniform black/white rows calibrate per-column means, one pooled
%   within-class complex covariance, ridge and linear directions. For every
%   validation block:
%     w_c = (C + .05 trace(C)/D I)^(-1) (muBlack_c-muWhite_c)
%     score = real(w_c'*(q-midpoint_c)); bit = score > 0.
%   NO CAF, absolute-square, magnitude, Otsu, morphology, or reference image
%   pixels enter the binary threshold. Magnitude/phase are diagnostic views.
%   Low-separation flags are separate; all thresholded bits remain 0/1.
%
%   Known-reference row semantics are supervision. A text-row black fraction
%   is NOT a text-pixel accuracy, OCR result, or recovered RGB-byte claim.
arguments
    data (1,1) struct
    methods (1,:) struct
    outputDirectory (1,1) string
end
assert(all(isfield(data,{'labels','rowMeta','f0'})),'Missing data fields.');
assert(all(isfield(methods,{'name','iq'})),'Methods require name and iq cells.');
if ~isfolder(outputDirectory),mkdir(outputDirectory);end
labels=double(data.labels(:));rows=numel(labels);
black=labels==1;white=labels==2;textRows=labels==3;
assert(nnz(black)>2&&nnz(white)>2&&nnz(textRows)>2,'Required row classes absent.');
M=numel(methods);assert(M>=1);
N=size(methods(1).iq{1},2);
sourceRows=(0:data.rowMeta.reference_height-1)';
activeIndex=mod(round(data.rowMeta.row_offset_zero_based+ ...
    data.rowMeta.row_scale*sourceRows),rows)+1;
activeMask=false(rows,1);activeMask(activeIndex)=true;
timeUs=((0:N-1)+0.5)/N/data.f0*1e6;
derived=struct([]);records=struct([]);tableRows=cell(M*3,12);
for mm=1:M
    assert(iscell(methods(mm).iq)&&numel(methods(mm).iq)==3,'Three IQ blocks required.');
    first=double(methods(mm).iq{1});
    D=size(first,3);
    assert(size(first,1)==rows&&size(first,2)==N&&all(isfinite(first),'all'));
    muBlack=reshape(mean(first(black,:,:),1),N,D);
    muWhite=reshape(mean(first(white,:,:),1),N,D);
    midpoint=(muBlack+muWhite)/2;
    delta=muBlack-muWhite;
    covariance=complex(zeros(D,D));sampleCount=0;
    for group=1:2
        if group==1,index=black;mu=muBlack;else,index=white;mu=muWhite;end
        residual=first(index,:,:)-reshape(mu,1,N,D);
        residual=reshape(residual,[],D);
        % Rows hold q^T. Nonconjugate transpose on the LEFT implements
        % C=E[(q-mu)*(q-mu)^H], consistent with w^H q below.
        covariance=covariance+residual.'*conj(residual);
        sampleCount=sampleCount+size(residual,1);
    end
    covariance=covariance/max(sampleCount-2*N,1);
    covariance=(covariance+covariance')/2;
    varianceScale=max(0,real(trace(covariance))/D);
    ridge=max(0.05*varianceScale,eps(max(varianceScale,1)));
    regularized=covariance+ridge*eye(D);
    direction=(regularized\delta.').';
    separation=0.5*real(sum(conj(direction).*delta,2));
    separation=max(separation,0);
    positive=separation(separation>0&isfinite(separation));
    if isempty(positive),typicalSeparation=0;else,typicalSeparation=median(positive);end
    separationFloor=max(0.05*typicalSeparation,eps(max(typicalSeparation,1)));
    highSeparation=separation>=separationFloor;
    displayDenominator=max(separation,separationFloor);
    midpointProjected=sum(conj(direction).*midpoint,2);
    parameters=struct('feature_dimension',D,'mu_black',muBlack,'mu_white',muWhite, ...
        'covariance',covariance,'covariance_convention','E[(q-mu)(q-mu)^H]', ...
        'ridge_fraction',0.05,'ridge_actual',ridge,'direction',direction, ...
        'midpoint',midpoint,'midpoint_projected',midpointProjected, ...
        'separation',separation,'separation_floor',separationFloor, ...
        'normalization_denominator',displayDenominator, ...
        'high_separation_columns',highSeparation, ...
        'threshold_raw_score',0,'training_block',1);
    scores=cell(1,3);bits=cell(1,3);blockRecords=struct([]);
    amplitudeB2=[];phaseB2=[];projectedB2=[];amplitudeRange=[];
    for bb=1:3
        X=double(methods(mm).iq{bb});
        assert(size(X,1)==rows&&size(X,2)==N&&size(X,3)==D ...
            &&all(isfinite(X),'all'),'IQ dimensions or finite-value validation failed.');
        projected=sum(X.*reshape(conj(direction),1,N,D),3);
        rawScore=real(projected-midpointProjected.');
        normalizedScore=rawScore./displayDenominator.';
        binary=rawScore>0;
        scores{bb}=single(normalizedScore);bits{bb}=binary;
        if bb==1
            amp=abs(projected(activeIndex,:));
            amplitudeRange=percentileLocal(amp,[1 99]);
            if amplitudeRange(2)<=amplitudeRange(1)
                amplitudeRange(2)=amplitudeRange(1)+max(1,abs(amplitudeRange(1)))*1e-6;
            end
            phaseAmplitudeFloor=percentileLocal(amp,5);
            phaseAmplitudeFloor=max(phaseAmplitudeFloor,eps(max(max(amp,[],'all'),1)));
        end
        rec=blockMetrics(rawScore,normalizedScore,binary,labels,highSeparation);
        rec.block=bb;
        if bb==1,blockRecords=rec;else,blockRecords(bb)=rec;end
        if bb==2
            projectedB2=single(projected);
            amplitudeB2=abs(projected);
            phaseB2=angle(projected)*180/pi;
            phaseB2(amplitudeB2<phaseAmplitudeFloor)=NaN;
        end
        stem=sprintf('%02d_%s_B%d',mm,safeName(methods(mm).name),bb);
        % All bits are preserved. No class labels fill the output image.
        imwrite(uint8(~binary(activeIndex,:))*255, ...
            fullfile(outputDirectory,"iq_binary_"+stem+".png"));
        imwrite(scoreRgb(normalizedScore(activeIndex,:),3), ...
            fullfile(outputDirectory,"iq_signed_projection_"+stem+".png"));
        projectedPhase=angle(projected(activeIndex,:))*180/pi;
        phaseMask=abs(projected(activeIndex,:))>=phaseAmplitudeFloor;
        imwrite(phaseRgb(projectedPhase,phaseMask), ...
            fullfile(outputDirectory,"iq_projected_phase_"+stem+".png"));
        row=(mm-1)*3+bb;
        tableRows(row,:)={string(methods(mm).name),bb,D,rec.balanced_accuracy, ...
            rec.black_recall,rec.white_false_positive_fraction, ...
            rec.text_binary_black_fraction,rec.mean_normalized_score_black, ...
            rec.mean_normalized_score_white,rec.mean_normalized_score_text, ...
            mean(~highSeparation),rec.high_separation_only.balanced_accuracy};
    end
    overlap=struct('active',agreement(bits{2}(activeMask,:),bits{3}(activeMask,:)), ...
        'black',agreement(bits{2}(black,:),bits{3}(black,:)), ...
        'white',agreement(bits{2}(white,:),bits{3}(white,:)), ...
        'text',agreement(bits{2}(textRows,:),bits{3}(textRows,:)));
    item=struct('name',string(methods(mm).name),'parameters',parameters, ...
        'normalized_signed_score',{scores},'binary',{bits}, ...
        'projected_complex_iq_B2',projectedB2,'B1_amplitude_display_range',amplitudeRange, ...
        'phase_amplitude_floor_B1',phaseAmplitudeFloor, ...
        'amplitude_B2',single(amplitudeB2),'phase_B2_degrees',single(phaseB2), ...
        'block_metrics',blockRecords,'B2_B3_agreement',overlap);
    if mm==1,derived=item;else,derived(mm)=item;end
    record=struct('name',string(methods(mm).name),'feature_dimension',D, ...
        'covariance_real',real(covariance),'covariance_imag',imag(covariance), ...
        'covariance_eigenvalues',sort(real(eig(covariance)),'descend').', ...
        'ridge_actual',ridge,'regularized_covariance_condition',cond(regularized), ...
        'low_separation_fraction',mean(~highSeparation), ...
        'separation_floor',separationFloor,'median_separation',typicalSeparation, ...
        'blocks',blockRecords,'B2_B3_agreement',overlap);
    if mm==1,records=record;else,records(mm)=record;end
    fprintf('IQ projection %s: B2/B3 balanced accuracy %.4f / %.4f; white FP %.4f / %.4f.\n', ...
        string(methods(mm).name),blockRecords(2).balanced_accuracy, ...
        blockRecords(3).balanced_accuracy,blockRecords(2).white_false_positive_fraction, ...
        blockRecords(3).white_false_positive_fraction);
end
% Row-shape comparisons are descriptive measured-data agreement, not glyph GT.
for mm=1:M
    rowAgreement=nan(rows,2);
    for bb=2:3
        a=double(derived(1).normalized_signed_score{bb});
        b=double(derived(mm).normalized_signed_score{bb});
        a=a-mean(a,2);b=b-mean(b,2);
        den=sqrt(sum(a.^2,2).*sum(b.^2,2));
        value=sum(a.*b,2)./max(den,realmin);
        value(den==0)=NaN;rowAgreement(:,bb-1)=value;
    end
    derived(mm).row_shape_correlation_to_method1=rowAgreement;
    records(mm).median_text_row_shape_correlation_to_method1= ...
        median(rowAgreement(textRows,:),1,'omitnan');
end
metricsTable=cell2table(tableRows,'VariableNames',{'Method','Block','Dimension', ...
    'UniformRowBalancedAccuracy','BlackRecall','WhiteFalsePositiveFraction', ...
    'TextBinaryBlackFraction','MeanNormalizedScoreBlack','MeanNormalizedScoreWhite', ...
    'MeanNormalizedScoreText','LowSeparationColumnFraction','ReliableOnlyBalancedAccuracy'});
writetable(metricsTable,fullfile(outputDirectory,'iq_projection_binary_metrics.csv'));
report=struct('pipeline','Complex IQ/SVD feature vector -> B1-trained linear projection -> real signed score -> threshold0 bits.', ...
    'threshold_uses_CAF',false,'threshold_uses_power_or_abs_square',false, ...
    'threshold_uses_reference_pixels',false,'threshold_uses_test_data',false, ...
    'reference_use','Existing reference-calibrated row classes only, for B1 black/white supervision.', ...
    'phase_input_assumption','Caller supplies consistently time/phase-corrected IQ feature vectors.', ...
    'phase_output_meaning','Phase of learned linear IQ feature projection; not absolute RF carrier or RGB hue.', ...
    'binary_semantics','1 means classifier black,0 white; text pixels remain unverified.', ...
    'low_separation_policy','All bits retained. Low-separation flag separate and used only for additional diagnostic metrics.', ...
    'display_normalization','Raw score / floored half training mean separation; fixed signed display [-3,3]. Threshold remains raw score0.', ...
    'row_label_counts',struct('black',nnz(black),'white',nnz(white),'text',nnz(textRows)), ...
    'horizontal_axis','1100 measured time bins per candidate period, not750 decoded pixels.', ...
    'training_block',1,'test_blocks',[2 3],'methods',records, ...
    'accuracy_scope','Balanced accuracy applies to known uniform-row classes, not text pixels, character decoding or arbitrary screens.', ...
    'glyph_metric_scope','Row-shape correlation and positive-set agreement are measured-data diagnostics, not OCR or pixel-accuracy scores.', ...
    'reference_pixels_rendered',false);
writeJson(fullfile(outputDirectory,'iq_projection_binary_summary.json'),report);
save(fullfile(outputDirectory,'iq_projection_binary_views.mat'),'derived','report', ...
    'activeIndex','sourceRows','timeUs','metricsTable','-v7.3');
makeFigures(derived,records,activeIndex,sourceRows,timeUs,outputDirectory);
end

function result=blockMetrics(raw,score,bits,labels,reliableColumns)
black=labels==1;white=labels==2;text=labels==3;
br=mean(bits(black,:),'all');fp=mean(bits(white,:),'all');
if any(reliableColumns)
    rbr=mean(bits(black,reliableColumns),'all');rfp=mean(bits(white,reliableColumns),'all');
else
    rbr=NaN;rfp=NaN;
end
result=struct('balanced_accuracy',.5*(br+1-fp), ...
    'black_recall',br,'white_false_positive_fraction',fp, ...
    'text_binary_black_fraction',mean(bits(text,:),'all'), ...
    'mean_raw_score_black',mean(raw(black,:),'all'), ...
    'mean_raw_score_white',mean(raw(white,:),'all'), ...
    'mean_normalized_score_black',mean(score(black,:),'all'), ...
    'mean_normalized_score_white',mean(score(white,:),'all'), ...
    'mean_normalized_score_text',mean(score(text,:),'all'), ...
    'high_separation_only',struct('black_recall',rbr, ...
    'white_false_positive_fraction',rfp,'balanced_accuracy',.5*(rbr+1-rfp)));
end
function r=agreement(a,b)
a=logical(a);b=logical(b);both=nnz(a&b);either=nnz(a|b);
den=nnz(a)+nnz(b);dice=NaN;jaccard=NaN;
if den>0,dice=2*both/den;end
if either>0,jaccard=both/either;end
r=struct('agreement_fraction',mean(a==b,'all'),'positive_dice',dice, ...
    'positive_jaccard',jaccard,'block2_positive_fraction',mean(a,'all'), ...
    'block3_positive_fraction',mean(b,'all'), ...
    'note','Positive-set agreement, not correctness; empty positive sets yield NaN.');
end
function p=percentileLocal(x,percentage)
x=sort(double(x(isfinite(x))));assert(~isempty(x));
position=1+(numel(x)-1)*percentage/100;
lo=floor(position);hi=ceil(position);
p=x(lo).'.*(hi-position)+x(hi).'.*(position-lo);
same=hi==lo;p(same)=x(lo(same));
end
function name=safeName(value)
name=regexprep(char(value),'[^a-zA-Z0-9_-]','_');
if numel(name)>60,name=name(1:60);end
end
function rgb=scoreRgb(value,limit)
u=min(1,max(0,(value+limit)/(2*limit)));
palette=blueRed(256);idx=1+round(u*255);
rgb=uint8(round(255*reshape(palette(idx(:),:),size(value,1),size(value,2),3)));
end
function rgb=phaseRgb(value,valid)
palette=hsv(256);u=min(1,max(0,(value+180)/360));idx=1+round(u*255);
rgb=reshape(palette(idx(:),:),size(value,1),size(value,2),3);
for kk=1:3,plane=rgb(:,:,kk);plane(~valid)=.7;rgb(:,:,kk)=plane;end
rgb=uint8(round(255*rgb));
end
function palette=blueRed(n)
u=linspace(0,1,n)';palette=[min(1,2*u),1-abs(2*u-1),min(1,2*(1-u))];
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
function saveFigure(fig,out,name)
exportgraphics(fig,fullfile(out,name+".png"),'Resolution',145);
savefig(fig,fullfile(out,name+".fig"));
end
function makeFigures(derived,records,activeIndex,sourceRows,timeUs,out)
M=numel(derived);names=string({derived.name});
fig=figure('Name','IQ feature projection followed by binary threshold','Color','w', ...
    'Position',[40 40 max(1200,400*M) 1250]);
tl=tiledlayout(fig,2,M,'TileSpacing','compact','Padding','compact');
for mm=1:M
    ax=nexttile(tl,mm);imagesc(ax,timeUs,sourceRows,derived(mm).normalized_signed_score{2}(activeIndex,:));
    set(ax,'YDir','reverse');clim(ax,[-3 3]);colormap(ax,blueRed(256));colorbar(ax);
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,names(mm)+" | signed IQ projection",'Interpreter','none');
    ax=nexttile(tl,M+mm);imagesc(ax,timeUs,sourceRows,1-double(derived(mm).binary{2}(activeIndex,:)));
    set(ax,'YDir','reverse');clim(ax,[0 1]);colormap(ax,gray(2));
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,'B2: score > 0 = black; no image cleanup');
end
title(tl,'IQ features -> B1 black/white linear calibration -> frozen zero threshold; text bits unverified');
saveFigure(fig,out,'iq_01_projection_then_binary');
fig=figure('Name','Learned IQ projection amplitude and phase','Color','w', ...
    'Position',[60 50 max(1200,400*M) 1250]);
tl=tiledlayout(fig,2,M,'TileSpacing','compact','Padding','compact');
for mm=1:M
    ax=nexttile(tl,mm);imagesc(ax,timeUs,sourceRows,derived(mm).amplitude_B2(activeIndex,:));
    set(ax,'YDir','reverse');clim(ax,derived(mm).B1_amplitude_display_range);colormap(ax,parula(256));colorbar(ax);
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,names(mm)+" | projected IQ amplitude",'Interpreter','none');
    ax=nexttile(tl,M+mm);p=derived(mm).phase_B2_degrees(activeIndex,:);
    im=imagesc(ax,timeUs,sourceRows,p);set(im,'AlphaData',isfinite(p));
    set(ax,'YDir','reverse','Color',[.7 .7 .7]);clim(ax,[-180 180]);colormap(ax,hsv(256));colorbar(ax);
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Reference-aligned row');
    title(ax,'Projection phase (deg), weak amplitude masked');
end
title(tl,'Magnitude and phase are diagnostics; neither sets the binary threshold');
saveFigure(fig,out,'iq_02_projected_amplitude_phase');
fig=figure('Name','Frozen IQ binary classifier validation','Color','w','Position',[80 60 1500 1000]);
tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ba=zeros(M,3);fp=ba;br=ba;tf=ba;dice=zeros(M,1);low=dice;
for mm=1:M
    for bb=1:3
        r=records(mm).blocks(bb);ba(mm,bb)=r.balanced_accuracy;
        fp(mm,bb)=r.white_false_positive_fraction;br(mm,bb)=r.black_recall;
        tf(mm,bb)=r.text_binary_black_fraction;
    end
    dice(mm)=records(mm).B2_B3_agreement.text.positive_dice;
    low(mm)=records(mm).low_separation_fraction;
end
ax=nexttile(tl);bar(ax,ba);set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylim(ax,[0 1]);ylabel(ax,'Uniform-row balanced accuracy');title(ax,'Known black/white row classes only');
legend(ax,'B1 train','B2 test','B3 test','Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,[fp(:,2:3) br(:,2:3)]);set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylim(ax,[0 1]);ylabel(ax,'Fraction');title(ax,'False black on white rows versus black recall');
legend(ax,'White FP B2','White FP B3','Black recall B2','Black recall B3','Location','southoutside');grid(ax,'on');
ax=nexttile(tl);bar(ax,[tf(:,2:3) dice]);set(ax,'XTick',1:M,'XTickLabel',names);xtickangle(ax,20);
ylim(ax,[0 1]);ylabel(ax,'Fraction / overlap');title(ax,'Text positives and repeatability; not pixel accuracy');
legend(ax,'Text black fraction B2','Text black fraction B3','Text B2-B3 positive Dice','Location','southoutside');grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');
for mm=1:M
    plot(ax,timeUs,derived(mm).parameters.separation,'DisplayName',names(mm));
end
xlabel(ax,'Within-period time (us)');ylabel(ax,'Half training signed-score separation');
title(ax,'Per-column classifier separation; low-separation mask saved separately');
legend(ax,'Location','best','Interpreter','none');grid(ax,'on');
saveFigure(fig,out,'iq_03_binary_validation');
end
