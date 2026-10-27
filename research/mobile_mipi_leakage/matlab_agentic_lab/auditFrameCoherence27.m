function summary = auditFrameCoherence27(out)
%AUDITFRAMECOHERENCE27 Bounded first-order coherence audit of measured frames.
% Fits a relative CFO and integer delay on the first half of each B1 frame,
% then evaluates those unchanged corrections on its second half. This audit
% does not alter PCA, CAF, input IQ, frame timing, or any selected weights.
% Positive delay pairs reference[n] with comparison[n+delay]. Positive
% correction frequency multiplies comparison by exp(+j2pi*f*n/FsGrid).
% The product FFT therefore estimates the CORRECTION frequency directly.

arguments
    out (1,1) string
end
lab=string(fileparts(mfilename('fullpath')));
addpath(fullfile(lab,'signal_processing'));
s= jsondecode(fileread(fullfile(out,'pca_summary.json')));
t=load(fullfile(out,'training_pca.mat'),'frame0','Tf');
d=load(fullfile(lab,'results','iphone6_complex_caf_channels_20261027','complex_caf.mat'),'labels');
N=double(s.phase_samples_per_row); R=double(s.frame_rows_hypothesis);
K=double(s.frames_per_block); fs=double(s.fs_native_hz); f0=double(s.f0_hz);
fsGrid=double(s.fs_grid_hz); fc=double(s.fc_hz); M=N*R;
raw=string(s.raw); dc=complex(s.dc_real,s.dc_imag);
assert(dir(raw).bytes==s.raw_bytes,'Raw byte count changed.');
frameStart=double(t.frame0(1)); Tf=double(t.Tf);
scale=sqrt(double(s.scale_power_adc2));
[reference,alignment]=readAlignedFrameIq27(raw,frameStart,N,R,fs,f0,dc,4096);
reference=reference*exp(2i*pi*mod(fc*frameStart*Tf,1))/scale;
trainingEnd=floor(M/2);
trainingRange=[1 trainingEnd]; validationRange=[trainingEnd+1 M];
lags=(-4:4)'; blockLength=256; maxCfoHz=100e3;
results=struct([]); allLagFits=cell(K-1,1); allClassMetrics=cell(K-1,1);
for kk=2:K
    frameIndex=frameStart+kk-1;
    comparison=readAlignedFrameIq27(raw,frameIndex,N,R,fs,f0,dc,4096);
    comparison=comparison*exp(2i*pi*mod(fc*frameIndex*Tf,1))/scale;
    lagFits=repmat(struct('delay',0,'correctionHz',0,'trainingCoherence',0, ...
        'trainingZeroCfoCoherence',0,'fftPeakToMedian',0,'fftBinHz',0, ...
        'fftPeakAtSearchBoundary',false,'fftSuggestedHz',0),numel(lags),1);
    for jj=1:numel(lags)
        [p,~,den]=pairProduct(reference,comparison,lags(jj),trainingRange,N);
        [frequency,peakMedian,binHz,edge]=findProductPeak(p,fsGrid,blockLength,maxCfoHz);
        phase=(0:numel(p)-1)'/fsGrid;
        cPeak=abs(sum(p.*exp(-2i*pi*frequency*phase)))/max(den,realmin);
        cZero=abs(sum(p))/max(den,realmin);
        initialFrequency=frequency;
        if cZero>cPeak,frequency=0;cPeak=cZero;end
        lagFits(jj)=struct('delay',lags(jj),'correctionHz',frequency, ...
            'trainingCoherence',cPeak,'trainingZeroCfoCoherence',cZero, ...
            'fftPeakToMedian',peakMedian,'fftBinHz',binHz, ...
            'fftPeakAtSearchBoundary',edge,'fftSuggestedHz',initialFrequency);
    end
    zeroLag=find(lags==0);
    [~,bestLag]=max([lagFits.trainingCoherence]);
    % Refine only the two candidates needed for CFO-only and joint reporting.
    refineIndices=unique([zeroLag bestLag]);
    for jj=refineIndices
        [p,~,den]=pairProduct(reference,comparison,lags(jj),trainingRange,N);
        phase=(0:numel(p)-1)'/fsGrid;
        center=lagFits(jj).correctionHz; radius=1.5*lagFits(jj).fftBinHz;
        lower=max(-maxCfoHz,center-radius); upper=min(maxCfoHz,center+radius);
        objective=@(frequency) -abs(sum(p.*exp(-2i*pi*frequency*phase)))/max(den,realmin);
        options=optimset('Display','off','TolX',0.1,'MaxFunEvals',20,'MaxIter',20);
        [refinedFrequency,negativeValue]=fminbnd(objective,lower,upper,options);
        if -negativeValue>lagFits(jj).trainingCoherence
            lagFits(jj).correctionHz=refinedFrequency;
            lagFits(jj).trainingCoherence=-negativeValue;
        end
    end
    [~,bestLag]=max([lagFits.trainingCoherence]);
    joint=lagFits(bestLag); cfoOnly=lagFits(zeroLag);
    baselineTrain=evaluatePair(reference,comparison,0,0,trainingRange,N,fsGrid);
    baselineTest=evaluatePair(reference,comparison,0,0,validationRange,N,fsGrid);
    cfoTrain=evaluatePair(reference,comparison,0,cfoOnly.correctionHz,trainingRange,N,fsGrid);
    cfoTest=evaluatePair(reference,comparison,0,cfoOnly.correctionHz,validationRange,N,fsGrid);
    jointTrain=evaluatePair(reference,comparison,joint.delay,joint.correctionHz,trainingRange,N,fsGrid);
    jointTest=evaluatePair(reference,comparison,joint.delay,joint.correctionHz,validationRange,N,fsGrid);
    % Absolute first-order phase is reported, but never optimized on validation.
    record=struct('comparison_frame_offset',kk-1,'reference_absolute_frame',frameStart, ...
        'comparison_absolute_frame',frameIndex,'baseline_train_coherence',baselineTrain.coherence, ...
        'baseline_validation_coherence',baselineTest.coherence, ...
        'cfo_only_correction_hz',cfoOnly.correctionHz, ...
        'cfo_only_train_coherence',cfoTrain.coherence, ...
        'cfo_only_validation_coherence',cfoTest.coherence, ...
        'joint_delay_grid_samples',joint.delay,'joint_delay_ns',1e9*joint.delay/fsGrid, ...
        'joint_correction_hz',joint.correctionHz,'inferred_comparison_minus_reference_cfo_hz',-joint.correctionHz, ...
        'joint_train_coherence',jointTrain.coherence,'joint_validation_coherence',jointTest.coherence, ...
        'validation_coherence_gain_absolute',jointTest.coherence-baselineTest.coherence, ...
        'validation_coherence_gain_ratio',jointTest.coherence/max(baselineTest.coherence,realmin), ...
        'joint_train_phase_rad',jointTrain.phaseRad,'joint_validation_phase_rad',jointTest.phaseRad, ...
        'joint_validation_complex_correlation_real',real(jointTest.correlation), ...
        'joint_validation_complex_correlation_imag',imag(jointTest.correlation), ...
        'joint_validation_eight_chunk_coherence',jointTest.chunkCoherence, ...
        'joint_validation_eight_chunk_phase_rad',jointTest.chunkPhaseRad, ...
        'joint_validation_chunk_phase_resultant',jointTest.chunkPhaseResultant, ...
        'joint_training_fft_peak_to_median',joint.fftPeakToMedian, ...
        'joint_delay_at_search_boundary',abs(joint.delay)==max(abs(lags)), ...
        'joint_cfo_at_search_boundary',abs(joint.correctionHz)>maxCfoHz-2*joint.fftBinHz, ...
        'joint_cfo_fit_fft_resolution_hz',joint.fftBinHz, ...
        'reference_comparison_training_pairs',jointTrain.pairCount, ...
        'reference_comparison_validation_pairs',jointTest.pairCount);
    if isempty(results),results=record;else,results(end+1)=record;end %#ok<AGROW>
    classMetrics=repmat(struct('class',"",'validation_pairs',0,'baseline_coherence',0, ...
        'joint_coherence',0,'joint_phase_rad',0),3,1);
    names=["black","white","text"];
    for cls=1:3
        baseClass=evaluatePair(reference,comparison,0,0,validationRange,N,fsGrid,d.labels,cls);
        fittedClass=evaluatePair(reference,comparison,joint.delay,joint.correctionHz,validationRange,N,fsGrid,d.labels,cls);
        classMetrics(cls)=struct('class',names(cls),'validation_pairs',fittedClass.pairCount, ...
            'baseline_coherence',baseClass.coherence,'joint_coherence',fittedClass.coherence, ...
            'joint_phase_rad',fittedClass.phaseRad);
    end
    allLagFits{kk-1}=lagFits;allClassMetrics{kk-1}=classMetrics;
    fprintf('Frame coherence +%d: validation %.4g -> %.4g; correction %+0.2f Hz, delay %+d samples.\n', ...
        kk-1,baselineTest.coherence,jointTest.coherence,joint.correctionHz,joint.delay);
end
summary=struct('raw',raw,'raw_modified',false,'reference_absolute_frame',frameStart, ...
    'frame_count',K,'fs_grid_hz',fsGrid,'frame_rows',R,'samples_per_row',N, ...
    'training_sample_range_one_based',trainingRange,'validation_sample_range_one_based',validationRange, ...
    'cfo_search_hz',[-maxCfoHz maxCfoHz],'integer_delay_search_grid_samples',lags, ...
    'crossproduct_block_average_samples',blockLength,'alignment',alignment, ...
    'pca_changed',false,'estimated_corrections_applied_to_main_results',false, ...
    'median_baseline_validation_coherence',median([results.baseline_validation_coherence]), ...
    'median_joint_validation_coherence',median([results.joint_validation_coherence]), ...
    'maximum_joint_validation_coherence',max([results.joint_validation_coherence]), ...
    'median_validation_coherence_absolute_gain',median([results.validation_coherence_gain_absolute]), ...
    'frames_improved_on_validation',sum([results.validation_coherence_gain_absolute]>0), ...
    'results',results,'class_validation',{allClassMetrics}, ...
    'estimator',"Block-mean cross-product FFT locates a candidate phase ramp; exact normalized inner products refine and verify it. No assumption that the complete product is a stationary sinusoid.", ...
    'sign_convention',"p[n]=reference[n]*conj(comparison[n+d]); correction +f multiplies comparison[n+d] by exp(+j2pi*f*n/FsGrid).", ...
    'pair_rule',"Endpoint samples must remain in the same capture row; class-specific metrics additionally require the frozen row class.", ...
    'validation_rule',"First half of positions fits lag/CFO; second half evaluates frozen lag/CFO, with no phase alignment or parameter refit.", ...
    'limitations',["This bounds only a constant residual CFO and an integer delay within the stated search box."; ...
    "It does not test fractional delay, row-dependent timing drift, nonlinear phase, changed content or channel response."; ...
    "Low first-order coherence can coexist with reproducible second-order CAF; it is not evidence that packet periodicity is absent."; ...
    "FFT zero padding interpolates the peak; it does not increase independent frequency resolution."; ...
    "A search-boundary optimum may require a wider search before excluding alignment error."; ...
    "Validation samples belong to different positions of the same training frames; this is an alignment audit, not independent B2/B3 model validation."]);
save(fullfile(out,'frame_coherence_audit.mat'),'summary','results','allLagFits','allClassMetrics','-v7.3');
flat=rmfield(results,{'joint_validation_eight_chunk_coherence','joint_validation_eight_chunk_phase_rad'});
writetable(struct2table(flat),fullfile(out,'frame_coherence_audit.csv'));
fid=fopen(fullfile(out,'frame_coherence_audit.json'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));fwrite(fid,jsonencode(summary,'PrettyPrint',true),'char');
end

function [product,valid,den,referencePower,comparisonPower] = pairProduct(reference,comparison,delay,range,N,labels,wantedClass)
if nargin<7,wantedClass=[];end
indices=(range(1):range(2))'; shifted=indices+delay;
valid=shifted>=1 & shifted<=numel(comparison);
referenceRows=floor((indices-1)/N)+1;
comparisonRows=floor((shifted-1)/N)+1;
valid=valid & referenceRows==comparisonRows;
if ~isempty(wantedClass),valid=valid & labels(referenceRows)==wantedClass;end
product=complex(zeros(numel(indices),1));referencePower=zeros(numel(indices),1);comparisonPower=referencePower;
a=reference(indices(valid));b=comparison(shifted(valid));
product(valid)=a.*conj(b);referencePower(valid)=abs(a).^2;comparisonPower(valid)=abs(b).^2;
den=sqrt(sum(referencePower)*sum(comparisonPower));
end

function [frequency,peakMedian,binHz,edge] = findProductPeak(product,fsGrid,blockLength,maxCfoHz)
numberBlocks=ceil(numel(product)/blockLength);
product(end+1:numberBlocks*blockLength)=0;
blocked=mean(reshape(product,blockLength,numberBlocks),1)';
window=.5-.5*cos(2*pi*(0:numberBlocks-1)'/max(numberBlocks-1,1));
nfft=2^nextpow2(4*numberBlocks);
spectrum=abs(fftshift(fft(blocked.*window,nfft)));
fsBlock=fsGrid/blockLength;binHz=fsBlock/nfft;
frequencies=(-nfft/2:nfft/2-1)'*binHz;
keep=find(abs(frequencies)<=maxCfoHz);
[peak,which]=max(spectrum(keep));index=keep(which);
frequency=frequencies(index);
if index>1&&index<nfft
    values=log(max(spectrum(index+(-1:1)),realmin));
    curvature=values(1)-2*values(2)+values(3);
    if curvature<0
        offset=.5*(values(1)-values(3))/curvature;
        if abs(offset)<=1,frequency=frequency+offset*binHz;end
    end
end
frequency=max(-maxCfoHz,min(maxCfoHz,frequency));
peakMedian=peak/max(median(spectrum(keep)),realmin);
edge=which<=2||which>=numel(keep)-1;
end

function metric = evaluatePair(reference,comparison,delay,frequency,range,N,fsGrid,labels,wantedClass)
if nargin<9,wantedClass=[];labels=[];end
[product,valid,den,referencePower,comparisonPower]=pairProduct(reference,comparison,delay,range,N,labels,wantedClass);
time=((range(1)-1):(range(2)-1))'/fsGrid;
corrected=product.*exp(-2i*pi*frequency*time);
correlation=sum(corrected)/max(den,realmin);
chunks=8;edges=round(linspace(0,numel(product),chunks+1));
chunkCoherence=zeros(1,chunks);chunkPhase=zeros(1,chunks);chunkCorrelation=complex(zeros(1,chunks));
for jj=1:chunks
    index=(edges(jj)+1):edges(jj+1);
    chunkDen=sqrt(sum(referencePower(index))*sum(comparisonPower(index)));
    chunkCorrelation(jj)=sum(corrected(index))/max(chunkDen,realmin);
    chunkCoherence(jj)=abs(chunkCorrelation(jj));chunkPhase(jj)=angle(chunkCorrelation(jj));
end
phaseResultant=abs(sum(chunkCorrelation))/max(sum(abs(chunkCorrelation)),realmin);
metric=struct('coherence',abs(correlation),'phaseRad',angle(correlation), ...
    'correlation',correlation,'pairCount',sum(valid),'chunkCoherence',chunkCoherence, ...
    'chunkPhaseRad',chunkPhase,'chunkPhaseResultant',phaseResultant);
end
