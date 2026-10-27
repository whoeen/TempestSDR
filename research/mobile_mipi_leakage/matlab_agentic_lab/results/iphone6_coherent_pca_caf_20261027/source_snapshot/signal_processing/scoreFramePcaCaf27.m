function [scores, details] = scoreFramePcaCaf27(Y, YA, YB, labels, Nphase, fsGrid, f0)
%SCOREFRAMEPCACAF27 B1-only CAF selection of complex frame-PCA components.
% Inputs are sample-position-by-component matrices for full/first-half/
% second-half temporal combinations. Rows are one aligned raster frame,
% ordered with Nphase consecutive samples per capture row. Labels are frozen
% capture-row classes: 0 unassigned,1 black,2 white,3 text.
%
% Nonzero-lag products use midpoint phase and exclude pairs whose endpoints
% and midpoint have different or unassigned classes. Class phase profiles are
% count-normalized after linear deposition, then transformed at h*f0.
%
% Off-cycle controls retain the COMPLETE row-cycle phase by multiplying each
% lag product by exp(-j*2*pi*0.37*(n+d/2)/Nphase) BEFORE phase folding. The
% returned offCAF tests (h+0.37)*f0, and offCAFZero tests 0.37*f0.
%
% score = max(0, real cosine of half-A/B normalized class contrasts)
%       * max(0, target-contrast RMS - offset-cycle-contrast RMS).
% This is a heuristic training selector, NOT a detection significance test.
% Component energy below 1e-3 of total is ineligible. Positive selection uses
% a 1e-12 numerical cutoff; no component is forced when all scores fail.
%
% A frozen frame-axis temporal projector can use these component indices.
% This helper does not apply a learned full-image left singular-vector
% projection and does not infer physical DSI lane channels or packet bytes.

arguments
    Y {mustBeNumeric,mustBeFinite}
    YA {mustBeNumeric,mustBeFinite}
    YB {mustBeNumeric,mustBeFinite}
    labels (:,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger}
    Nphase (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive}
    fsGrid (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive}
    f0 (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive}
end
assert(ismatrix(Y)&&isequal(size(Y),size(YA),size(YB)),'Component matrices must have equal 2-D shapes.');
assert(size(Y,1)==numel(labels)*Nphase,'Rows must equal frameRows*Nphase.');
assert(all(ismember(labels,0:3)),'Unknown row label.');
assert(all(arrayfun(@(c)any(labels==c),1:3)),'Need black, white and text row classes.');
assert(abs(fsGrid/(Nphase*f0)-1)<1e-10,'The aligned grid must satisfy FsGrid=Nphase*f0.');
Nphase=double(Nphase);fsGrid=double(fsGrid);f0=double(f0);
labels=double(labels);numberRows=numel(labels);
numberComponents=size(Y,2);numberSamples=size(Y,1);
orders=(1:32)';lags=[1;2;4;8;16];offset=0.37;
F=exp(-2i*pi*orders*(0:Nphase-1)/Nphase)/Nphase;
caf=complex(zeros(numel(orders),numel(lags),3,numberComponents,3));
offCAF=caf;
offCAFZero=complex(zeros(1,numel(lags),3,numberComponents,3));
classProfiles=complex(zeros(Nphase,numel(lags),3,numberComponents,3));
classPower=zeros(3,numberComponents,3);
componentEnergy=zeros(numberComponents,1);
verticalStripeFraction=zeros(numberComponents,1);
textWhiteEffect=zeros(numberComponents,1);
rowEnergy=cell(numberComponents,1);
rowClass=repelem(labels,Nphase);
for component=1:numberComponents
    for split=1:3
        x=chooseColumn(Y,YA,YB,component,split);
        p=abs(x).^2;
        for cls=1:3
            classPower(cls,component,split)=mean(p(rowClass==cls));
        end
        if split==1
            componentEnergy(component)=sum(p);
            raster=reshape(p,Nphase,numberRows);
            globalMean=mean(raster,'all');
            meanRowProfile=mean(raster,2);
            centeredTotal=sum((raster-globalMean).^2,'all');
            stripeEnergy=numberRows*sum((meanRowProfile-globalMean).^2);
            verticalStripeFraction(component)=min(1,max(0,stripeEnergy/max(centeredTotal,realmin)));
            whiteProfile=mean(raster(:,labels==2),2);
            energyByRow=mean(abs(raster-whiteProfile),1)';
            rowEnergy{component}=energyByRow;
            textWhiteEffect(component)=pooledEffect(energyByRow(labels==3),energyByRow(labels==2));
        end
    end
end
phaseCounts=zeros(Nphase,numel(lags),3);
for lagIndex=1:numel(lags)
    d=lags(lagIndex);
    n=(0:numberSamples-d-1)';
    rowA=floor(n/Nphase)+1;
    rowB=floor((n+d)/Nphase)+1;
    rowMid=floor((n+d/2)/Nphase)+1;
    cls=labels(rowMid);
    keep=cls>0 & cls==labels(rowA) & cls==labels(rowB);
    n=n(keep);cls=cls(keep);
    phase=mod(n+d/2,Nphase);
    b0=floor(phase)+1;
    fraction=mod(d,2)/2;
    index0=b0+(cls-1)*Nphase;
    index1=mod(b0,Nphase)+1+(cls-1)*Nphase;
    count=(1-fraction)*accumarray(index0,1,[Nphase*3 1])+ ...
        fraction*accumarray(index1,1,[Nphase*3 1]);
    phaseCounts(:,lagIndex,:)=reshape(count,Nphase,1,3);
    offPhasor=exp(-2i*pi*offset*(n+d/2)/Nphase);
    for component=1:numberComponents
        for split=1:3
            x=chooseColumn(Y,YA,YB,component,split);
            product=x(n+d+1).*conj(x(n+1));
            sums=(1-fraction)*accumarray(index0,product,[Nphase*3 1])+ ...
                fraction*accumarray(index1,product,[Nphase*3 1]);
            shiftedProduct=product.*offPhasor;
            offSums=(1-fraction)*accumarray(index0,shiftedProduct,[Nphase*3 1])+ ...
                fraction*accumarray(index1,shiftedProduct,[Nphase*3 1]);
            profile=reshape(sums./max(count,1),Nphase,3);
            offProfile=reshape(offSums./max(count,1),Nphase,3);
            classProfiles(:,lagIndex,:,component,split)=reshape(profile,Nphase,1,3);
            caf(:,lagIndex,:,component,split)=reshape(F*profile,numel(orders),1,3);
            offCAF(:,lagIndex,:,component,split)=reshape(F*offProfile,numel(orders),1,3);
            offCAFZero(:,lagIndex,:,component,split)=reshape(mean(offProfile,1),1,1,3);
        end
    end
end
totalEnergy=sum(componentEnergy);
energyFraction=componentEnergy/max(totalEnergy,realmin);
eligible=energyFraction>=1e-3;
targetStrength=zeros(numberComponents,1);offStrength=targetStrength;
offZeroStrength=targetStrength;contrastRealCosine=targetStrength;
contrastAbsCosine=targetStrength;rawRealCosine=targetStrength;
rawAbsCosine=targetStrength;rawStrength=targetStrength;score=targetStrength;
normalizedContrasts=complex(zeros(numel(orders),numel(lags),2,numberComponents,3));
normalizedOffContrasts=normalizedContrasts;
for component=1:numberComponents
    normalizedRaw=cell(3,1);
    contrast=cell(3,1);offContrast=cell(3,1);
    for split=1:3
        powers=classPower(:,component,split);
        floorPower=max(mean(powers)*1e-6,realmin);
        c=caf(:,:,:,component,split);
        off=offCAF(:,:,:,component,split);
        c0=offCAFZero(:,:,:,component,split);
        normalizedRaw{split}=c./reshape(max(powers,floorPower),1,1,3);
        denominators=max([(powers(1)+powers(2))/2,(powers(3)+powers(2))/2],floorPower);
        contrast{split}=cat(3,(c(:,:,1)-c(:,:,2))/denominators(1), ...
            (c(:,:,3)-c(:,:,2))/denominators(2));
        offContrast{split}=cat(3,(off(:,:,1)-off(:,:,2))/denominators(1), ...
            (off(:,:,3)-off(:,:,2))/denominators(2));
        normalizedContrasts(:,:,:,component,split)=contrast{split};
        normalizedOffContrasts(:,:,:,component,split)=offContrast{split};
        if split==1
            off0=cat(3,(c0(:,:,1)-c0(:,:,2))/denominators(1), ...
                (c0(:,:,3)-c0(:,:,2))/denominators(2));
            offZeroStrength(component)=sqrt(mean(abs(off0).^2,'all'));
        end
    end
    targetStrength(component)=sqrt(mean(abs(contrast{1}).^2,'all'));
    offStrength(component)=sqrt(mean(abs(offContrast{1}).^2,'all'));
    [contrastRealCosine(component),contrastAbsCosine(component)]=complexCosine(contrast{2},contrast{3});
    [rawRealCosine(component),rawAbsCosine(component)]=complexCosine(normalizedRaw{2},normalizedRaw{3});
    rawStrength(component)=sqrt(mean(abs(normalizedRaw{1}).^2,'all'));
    score(component)=max(0,contrastRealCosine(component))* ...
        max(0,targetStrength(component)-offStrength(component));
end
score(~eligible)=0;
scores=table((1:numberComponents)',componentEnergy,energyFraction,eligible, ...
    targetStrength,offStrength,offZeroStrength,contrastRealCosine,contrastAbsCosine, ...
    rawStrength,rawRealCosine,rawAbsCosine,verticalStripeFraction,textWhiteEffect,score, ...
    'VariableNames',{'Component','Energy','EnergyFraction','Eligible', ...
    'ContrastCafStrength','OffCycleContrastStrength','OffCycle037Strength', ...
    'ContrastHalfRealCosine','ContrastHalfAbsCosine','RawCafStrength', ...
    'RawHalfRealCosine','RawHalfAbsCosine','VerticalStripePowerFraction', ...
    'TextWhiteEffect','Score'});
[~,order]=sort(score,'descend');
positive=order(score(order)>1e-12&eligible(order));
if isempty(positive),primary=[];secondary=[];else,primary=positive(1);secondary=positive(1:min(2,numel(positive)));end
details=struct('caf',caf,'offCAF',offCAF,'offCAFZero',offCAFZero, ...
    'classProfiles',classProfiles,'classPower',classPower, ...
    'normalizedContrasts',normalizedContrasts,'normalizedOffContrasts',normalizedOffContrasts, ...
    'phaseCounts',phaseCounts,'orders',orders,'lags',lags,'fsGrid',fsGrid,'f0',f0, ...
    'offCycleFraction',offset,'rowEnergy',{rowEnergy},'labels',labels, ...
    'primaryComponent',primary,'secondaryComponents',secondary,'sortedIndices',order, ...
    'splitOrder',["full","halfA","halfB"],'classOrder',["black","white","text"], ...
    'contrastOrder',["black-white","text-white"], ...
    'selectionScope',"B1 only; all ranks, component choices and temporal weights must be frozen for validation.", ...
    'scoreDefinition',"max(0, half-contrast real cosine) * max(0, target contrast RMS - shifted-cycle contrast RMS)", ...
    'scoreOffControl',"Equal-size bank at (h+0.37)*f0. The separate offCAFZero contains alpha=0.37*f0.", ...
    'offCycleConvention',"Multiply products by exp(-j2pi*0.37*(n+d/2)/Nphase) before row-period folding; complete row-cycle phase retained.", ...
    'phaseConvention',"z[n+d]conj(z[n]); midpoint phase; linear node deposition, then per-node count normalization.", ...
    'energyThreshold',1e-3,'positiveNumericalCutoff',1e-12, ...
    'verticalStripeDefinition',"R*sum((mean_rows(power)-globalmean)^2) / sum((power-globalmean)^2); all raster rows.", ...
    'textWhiteEffectDefinition',"Mean absolute power residual from within-component white-row profile; text-white mean difference / pooled row SD.", ...
    'limitations',["Training selector is heuristic, not a p-value or a protocol decoder."; ...
    "Fixed stripes with state-dependent amplitude can also have class-contrast CAF."; ...
    "Global phase per component cancels from nonconjugate CAF."; ...
    "Off-cycle gate leakage and finite-row boundaries are retained, not assumed zero."; ...
    "A temporal projector does not create separate physical DSI lane observations."]);
end

function x=chooseColumn(Y,YA,YB,component,split)
if split==1,x=Y(:,component);elseif split==2,x=YA(:,component);else,x=YB(:,component);end
end
function [realValue,absoluteValue]=complexCosine(a,b)
den=norm(a(:))*norm(b(:));
if den==0,realValue=0;absoluteValue=0;return;end
inner=sum(conj(a(:)).*b(:))/den;
realValue=max(-1,min(1,real(inner)));absoluteValue=min(1,abs(inner));
end
function d=pooledEffect(text,white)
nt=numel(text);nw=numel(white);
pooled=sqrt(((nt-1)*var(text)+(nw-1)*var(white))/max(nt+nw-2,1));
d=(mean(text)-mean(white))/max(pooled,realmin);
end
