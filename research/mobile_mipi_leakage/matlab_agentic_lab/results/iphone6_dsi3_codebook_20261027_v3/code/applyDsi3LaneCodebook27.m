function report = applyDsi3LaneCodebook27(outputDirectory)
%APPLYDSI3LANECODEBOOK27 Protocol-conditioned hypotheses against fc100 power.
% Original data are immutable. Block 1 trains every parameter; blocks 2/3 test.
% This is cyclic-power model comparison, NOT a packet/bit decoder.
arguments
    outputDirectory (1,1) string
end
lab=string(fileparts(mfilename('fullpath')));
addpath(fullfile(lab,'signal_processing'));
assert(~isfolder(outputDirectory),'Refuse to overwrite an existing result.');
mkdir(outputDirectory);
book=buildDsi3LaneCodebook27(outputDirectory);
sourceRoot=fullfile(lab,'results','iphone6_fc100_fam_20261026');
prior=jsondecode(fileread(fullfile(sourceRoot,'RESULTS_SUMMARY.json')));
fs=prior.native_fs_hz; f0=prior.training_cyclic_power_refinement.used_frequency_hz;
raw="C:/Users/leechanghoon/Downloads/black글_fc100MHz.rIs";
identity=jsondecode(fileread(fullfile(sourceRoot,'RAW_IDENTITY.json')));
info=dir(raw); assert(info.bytes==identity.bytes);
pre=load(fullfile(sourceRoot,'preflight.mat'),'dc');
bins=1100; subBins=16; framesRows=1881;
starts=round([0.2 1.1 1.8]*fs);
numberSamples=16*1048600;
profiles=zeros(bins,3); counts=profiles; phaseHist=zeros(subBins,3); jointHist=zeros(bins,subBins,3);
raster=cell(3,1); psd=cell(3,1); readRecords=struct([]);
for bb=1:3
    [profiles(:,bb),counts(:,bb),phaseHist(:,bb),raster{bb},psd{bb},readRecord,jointHist(:,:,bb)] = ...
        readFold(raw,starts(bb),numberSamples,fs,f0,bins,subBins,framesRows,pre.dc);
    if bb==1,readRecords=readRecord;else,readRecords(bb)=readRecord;end
    fprintf('Native block %d: %.3f s, %d samples, cyclic profile ready.\n',bb,starts(bb)/fs,numberSamples);
end
scale=mean(profiles(:,1)); y=profiles/scale;
save(fullfile(outputDirectory,'native_fold.mat'),'profiles','counts','phaseHist','raster','psd', ...
    'readRecords','fs','f0','bins','starts','numberSamples','scale','jointHist','-v7.3');

% Generic modulo power gate. Parameters (including delay) are learned on B1.
gateBest=struct('trainScore',-Inf);
phase=((0:bins-1)'+0.5)/bins;
for duty=0.02:0.005:0.98
    gate=double(phase<duty);
    fit=fitShift(gate,y(:,1));
    if fit.trainScore>gateBest.trainScore
        gateBest=fit; gateBest.duty=duty; gateBest.template=gate;
    end
end
gateBest.testCorrelation=zeros(1,3); gateBest.testR2=zeros(1,3);
gatePrediction=gateBest.offset+gateBest.gain*circshift(gateBest.template,gateBest.lag);
for bb=1:3
    gateBest.testCorrelation(bb)=corrLocal(y(:,bb),gatePrediction);
    gateBest.testR2(bb)=rSquared(y(:,bb),gatePrediction);
end
gateBest.period_us=1e6/f0;
gateBest.high_width_us=gateBest.duty/f0*1e6;
gateBest.start_us=gateBest.lag/bins/f0*1e6;
gateBest.scope="Observed-power rectangular gate only; not an identified HS state.";

packets=[book.videoWhite book.videoBlack book.dcs book.matchedControls book.geometryControls];
rates=(685:20:1505)'*1e6;
gridSize=16384;
sampler=makeSampler(gridSize,bins,subBins);
couplingNames=["equal_coherent","equal_incoherent"];
numCandidates=numel(packets)*numel(rates)*3*2;
rows=nan(numCandidates,11); labels=strings(numCandidates,1); emissionLabels=labels; couplingLabels=labels;
packetBest=repmat(struct('trainScore',-Inf,'index',0,'prediction',[],'fit',[]),1,numel(packets));
rowIndex=0; modelMeta=struct();
for pp=1:numel(packets)
    for rr=1:numel(rates)
        model=dsi3LanePowerModel27(packets(pp),rates(rr),f0,gridSize);
        modelMeta=struct('band_hz',model.bandHz,'edge_taper_hz',model.taperHz, ...
            'emission_names',model.emissionNames,'frequency_convention',model.frequencyConvention, ...
            'active_level_convention',model.activeLevelConvention,'assumptions',model.assumptions);
        for ee=1:3
            [coh,inc]=modelFold(model.waveforms{ee},sampler,phaseHist(:,1));
            candidates={coh,inc};
            for cc=1:2
                rowIndex=rowIndex+1;
                fit=fitShift(candidates{cc},y(:,1));
                rows(rowIndex,:)=[pp packets(pp).protocolCandidate rates(rr) ee cc fit.lag ...
                    fit.trainScore fit.gain fit.offset NaN NaN];
                labels(rowIndex)=packets(pp).label;
                emissionLabels(rowIndex)=model.emissionNames(ee);
                couplingLabels(rowIndex)=couplingNames(cc);
                if fit.trainScore>packetBest(pp).trainScore
                    packetBest(pp)=struct('trainScore',fit.trainScore,'index',rowIndex, ...
                        'prediction',fit.offset+fit.gain*circshift(candidates{cc},fit.lag), ...
                        'fit',fit);
                end
            end
        end
    end
    fprintf('Codebook candidate %d/%d: %s, best training corr %.5f.\n', ...
        pp,numel(packets),packets(pp).label,packetBest(pp).trainScore);
end
assert(rowIndex==numCandidates);
% Refine the coarse training winner per codeword using bin-conditional phase
% distributions and fractional delay. Test blocks choose no fit parameters.
validation=repmat(struct(),1,numel(packets));
for pp=1:numel(packets)
    ix=packetBest(pp).index; rr=rows(ix,3); ee=rows(ix,4); cc=rows(ix,5);
    model=dsi3LanePowerModel27(packets(pp),rr,f0,gridSize);
    prediction=zeros(bins,3); correlation=zeros(1,3); testR2=zeros(1,3);
    coarseFit=packetBest(pp).fit;
    refinedFit=struct('trainScore',-Inf);
    for delta=-1:1/16:1
        delay=coarseFit.lag+delta;
        shiftedSampler=makeSampler(gridSize,bins,subBins,delay);
        [coh,inc]=modelFold(model.waveforms{ee},shiftedSampler,jointHist(:,:,1));
        candidate=coh;if cc==2,candidate=inc;end
        fit=fitAtDelay(candidate,y(:,1),delay);
        if fit.trainScore>refinedFit.trainScore,refinedFit=fit;end
    end
    fit=refinedFit;
    shiftedSampler=makeSampler(gridSize,bins,subBins,fit.lag);
    for bb=1:3
        [coh,inc]=modelFold(model.waveforms{ee},shiftedSampler,jointHist(:,:,bb));
        candidate=coh;if cc==2,candidate=inc;end
        prediction(:,bb)=fit.offset+fit.gain*candidate;
        correlation(bb)=corrLocal(y(:,bb),prediction(:,bb));
        testR2(bb)=rSquared(y(:,bb),prediction(:,bb));
    end
    packetBest(pp).trainScore=fit.trainScore;
    packetBest(pp).fit=fit;packetBest(pp).prediction=prediction(:,1);
    rows(ix,10:11)=correlation(2:3);
    validationRecord=struct('label',packets(pp).label,'protocol_candidate',packets(pp).protocolCandidate, ...
        'rate_hz',rr,'byte_rate_hz',rr/8,'ddr_clock_hz',rr/2, ...
        'emission',model.emissionNames(ee),'coupling',couplingNames(cc), ...
        'lag_bins',fit.lag,'lag_us',fit.lag/bins/f0*1e6,'gain',fit.gain,'offset',fit.offset, ...
        'coarse_train_correlation',coarseFit.trainScore, ...
        'correlation',correlation,'r_squared',testR2,'prediction',prediction);
    if pp==1,validation=validationRecord;else,validation(pp)=validationRecord;end
end
scan=array2table(rows,'VariableNames',{'PacketIndex','ProtocolCandidate','LaneRateHz', ...
    'EmissionIndex','CouplingIndex','LagBins','TrainCorrelation','Gain','Offset','Test2Corr','Test3Corr'});
scan.Label=labels;scan.Emission=emissionLabels;scan.Coupling=couplingLabels;
writetable(scan,fullfile(outputDirectory,'candidate_scan.csv'));
validIndex=find([packets.protocolCandidate]);
controlIndex=find(~[packets.protocolCandidate]);
[~,kk]=max([packetBest(validIndex).trainScore]); validWinner=validIndex(kk);
[~,kk]=max([packetBest(controlIndex).trainScore]); controlWinner=controlIndex(kk);

% Resolution/sampling-model audit on the two training-selected winners.
convergence=repmat(struct(),1,2);
for ii=1:2
    pp=[validWinner controlWinner];pp=pp(ii);v=validation(pp);
    ee=rows(packetBest(pp).index,4);cc=rows(packetBest(pp).index,5);
    model=dsi3LanePowerModel27(packets(pp),v.rate_hz,f0,2*gridSize);
    samplerFine=makeSampler(2*gridSize,bins,subBins,v.lag_bins);
    [coh,inc]=modelFold(model.waveforms{ee},samplerFine,jointHist(:,:,1));
    p=coh;if cc==2,p=inc;end
    refined=v.offset+v.gain*p;
    convergenceRecord=struct('label',v.label,'grid_size_fine',2*gridSize, ...
        'relative_prediction_change',norm(refined-v.prediction(:,1))/norm(v.prediction(:,1)), ...
        'training_correlation_fine',corrLocal(refined,y(:,1)));
    if ii==1,convergence=convergenceRecord;else,convergence(ii)=convergenceRecord;end
end
empirical=[1 corrLocal(y(:,1),y(:,2)) corrLocal(y(:,1),y(:,3))];
% Screenshot color census is reference-only, never supplied to detector.
screenPath="C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png";
screen=imread(screenPath);
if size(screen,3)>=3
    pix=reshape(screen(:,:,1:3),[],3);
    binary=all(pix==0,2)|all(pix==255,2);
    gray=all(pix(:,1)==pix(:,2)&pix(:,2)==pix(:,3),2);
    screenMeta=struct('width',size(screen,2),'height',size(screen,1), ...
        'binary_black_or_white_fraction',mean(binary),'grayscale_fraction',mean(gray), ...
        'unique_rgb_count',size(unique(pix,'rows'),1),'used_for_fitting',false);
else
    screenMeta=struct('used_for_fitting',false,'note','Not a three-channel image.');
end
report=struct('status','complete','native_fs_hz',fs,'rf_center_hz',100e6,'nominal_bw_hz',120e6, ...
    'frozen_fam_frequency_hz',f0,'period_us',1e6/f0,'native_samples_per_period',fs/f0, ...
    'number_data_lanes_assumed',3,'pixel_count_assumed',750,'rgb_format','RGB888', ...
    'packet_plus_SoT_rate_lower_bound_hz',6024*f0, ...
    'rate_search_hz',rates,'rate_grid_step_hz',20e6,'phase_bins',bins,'subphase_bins',subBins, ...
    'refined_delay_step_ns',1e9/(f0*bins*16), ...
    'subphase_quantization_halfwidth_ns',1e9/(f0*bins*subBins*2), ...
    'model_phase_grid',gridSize,'model',modelMeta,'gate',gateBest, ...
    'valid_winner',rmfield(validation(validWinner),'prediction'), ...
    'control_winner',rmfield(validation(controlWinner),'prediction'), ...
    'empirical_profile_correlations',empirical,'numerical_convergence',convergence, ...
    'screen_reference',screenMeta,'capture_identity_prior',identity, ...
    'raw_reads',readRecords,'training_block',1,'test_blocks',[2 3], ...
    'test_scope','Disjoint time blocks of the same fixed-screen recording; not independent captures.', ...
    'packet_decoded',false,'actual_lane_count_identified',false,'bitrate_identified',false, ...
    'ecc_crc_validated_on_measurement',false,'carrier_phase_decoded',false, ...
    'important_limitations',["The measured profile averages black/white/text/blanking states."; ...
    "Only first-packet single-HS-burst constant-color models tested."; ...
    "HS zero/prepare/trail, clock, multiple packets and RF channel/skew remain unknown."; ...
    "Equal coherent/incoherent lane coupling are restrictive hypotheses."; ...
    "Template matches test cyclic power, not binary RGB bits."; ...
    "Two reference colors are an approximation; antialiased pixels are counted separately."]);
writeJson(fullfile(outputDirectory,'metrics.json'),report);
save(fullfile(outputDirectory,'candidate_results.mat'),'book','scan','validation','packetBest', ...
    'validWinner','controlWinner','gateBest','gatePrediction','report','y','phaseHist','-v7.3');
makeFigures(book,scan,validation,validWinner,controlWinner,y,gatePrediction,gateBest, ...
    raster,psd,f0,report,outputDirectory);
fprintf('VALID winner %s: train %.5f, test %.5f %.5f.\n',report.valid_winner.label,report.valid_winner.correlation);
fprintf('CONTROL winner %s: train %.5f, test %.5f %.5f.\n',report.control_winner.label,report.control_winner.correlation);
end

function [profile,counts,fractionHist,raster,psd,meta,jointHist]=readFold(path,start,count,fs,f0,bins,subBins,rowCount,dc)
fid=fopen(path,'r','ieee-be');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
assert(fseek(fid,4*start,'bof')==0);
profile=zeros(bins,1);counts=profile;fractionHist=zeros(subBins,1);
jointCounts=zeros(bins,subBins);
rasterSum=zeros(rowCount*bins,1);rasterCount=rasterSum;
chunk=2^20; done=0;
while done<count
    take=min(chunk,count-done);
    iq=fread(fid,[2 take],'int16=>double');assert(size(iq,2)==take);
    z=complex(iq(1,:),-iq(2,:)).'-dc;
    pow=abs(z).^2;
    absoluteIndex=start+done+(0:take-1)';
    cycle=absoluteIndex*(f0/fs);
    phase=mod(cycle,1)*bins;
    bin=floor(phase)+1;
    fraction=min(subBins,floor(mod(phase,1)*subBins)+1);
    profile=profile+accumarray(bin,pow,[bins 1]);
    counts=counts+accumarray(bin,1,[bins 1]);
    fractionHist=fractionHist+accumarray(fraction,1,[subBins 1]);
    jointCounts=jointCounts+accumarray([bin fraction],1,[bins subBins]);
    row=mod(floor(cycle),rowCount)+1;
    index=row+(bin-1)*rowCount;
    rasterSum=rasterSum+accumarray(index,pow,[rowCount*bins 1]);
    rasterCount=rasterCount+accumarray(index,1,[rowCount*bins 1]);
    if done==0
        [density,frequency]=pwelch(z,hann(4096),2048,8192,fs,'centered');
        psd=struct('density',density,'baseband_frequency_hz',frequency);
    end
    done=done+take;
end
assert(all(counts>0));profile=profile./counts;
fractionHist=fractionHist/sum(fractionHist);
jointHist=jointCounts./counts;
raster=reshape(rasterSum./max(rasterCount,1),rowCount,bins);
meta=struct('path',path,'first_complex_sample_zero_based',start, ...
    'byte_offset',4*start,'complex_sample_count',count,'start_seconds',start/fs, ...
    'duration_seconds',count/fs,'endian','ieee-be','data_type','interleaved int16 I,Q', ...
    'iq_convention','I-jQ','dc_real',real(dc),'dc_imag',imag(dc), ...
    'dc_scope','Frozen from earlier preflight; same value for all blocks.', ...
    'power','abs(I-jQ-dc)^2','power_units','ADC counts squared', ...
    'cfo_correction',false,'time_warp',false,'unoccupied_bins',sum(counts==0));
end

function sampler=makeSampler(nGrid,bins,subBins,delayBins)
% Cubic interpolation of the complex analytic RF signal BEFORE squaring.
if nargin<4,delayBins=0;end
phase=mod(((0:bins-1)'+((0:subBins-1)+0.5)/subBins-delayBins)/bins,1);
u=phase*nGrid;
base=floor(u);d=u-base;
sampler.index=cell(1,4);sampler.weight=cell(1,4);
offsets=-1:2;
weights={-d.*(d-1).*(d-2)/6,(d+1).*(d-1).*(d-2)/2, ...
    -(d+1).*d.*(d-2)/2,(d+1).*d.*(d-1)/6};
for jj=1:4
    sampler.index{jj}=mod(base+offsets(jj),nGrid)+1;
    sampler.weight{jj}=weights{jj};
end
sampler.bins=bins;sampler.subBins=subBins;
end

function [coherent,incoherent]=modelFold(wave,sampler,weights)
combined=zeros(sampler.bins,sampler.subBins);
powers=zeros(sampler.bins,sampler.subBins);
for lane=1:3
    z=zeros(size(combined));
    column=wave(:,lane);
    for jj=1:4,z=z+column(sampler.index{jj}).*sampler.weight{jj};end
    combined=combined+z;powers=powers+abs(z).^2;
end
if isvector(weights)
    coherent=abs(combined).^2*weights;incoherent=powers*weights;
else
    coherent=sum(abs(combined).^2.*weights,2);incoherent=sum(powers.*weights,2);
end
% Fixed numerical scaling avoids tiny underflow, shared across blocks.
coherent=coherent*1e6;incoherent=incoherent*1e6;
end

function fit=fitShift(template,data)
a=template-mean(template);b=data-mean(data);
den=norm(a)*norm(b);
if den==0
    fit=struct('lag',0,'trainScore',-Inf,'gain',0,'offset',mean(data));return
end
g=real(ifft(conj(fft(a)).*fft(b)))/den;
[score,ix]=max(g);lag=ix-1;
shifted=circshift(template,lag);
gain=(shifted-mean(shifted))'*b/max(sum(a.^2),realmin);
offset=mean(data)-gain*mean(template);
fit=struct('lag',lag,'trainScore',score,'gain',gain,'offset',offset);
end
function fit=fitAtDelay(template,data,delay)
a=template-mean(template);b=data-mean(data);
gain=max(0,real(a'*b)/max(sum(abs(a).^2),realmin));
offset=mean(data)-gain*mean(template);
fit=struct('lag',delay,'trainScore',corrLocal(template,data),'gain',gain,'offset',offset);
end
function r=corrLocal(a,b)
a=a(:)-mean(a);b=b(:)-mean(b);
r=real(a'*b)/max(norm(a)*norm(b),realmin);
end
function r=rSquared(data,prediction)
r=1-sum((data-prediction).^2)/sum((data-mean(data)).^2);
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);clean=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end

function makeFigures(book,scan,validation,vw,cw,y,gatePrediction,gate,raster,psd,f0,report,out)
f=figure('Name','DSI three-lane codebook','Color','w','Position',[40 40 1400 850]);
tl=tiledlayout(f,2,2,'TileSpacing','compact');
ax=nexttile(tl);hold(ax,'on');
for lane=1:3
    stairs(ax,0:47,double(book.videoWhite(1).hsBits(1:48,lane))+2*(lane-1), ...
        'DisplayName',sprintf('Lane %d',lane-1));
end
xline(ax,8,'--','SoT ends','HandleVisibility','off');xline(ax,16,':','HandleVisibility','off');xline(ax,24,':','HandleVisibility','off');
xlabel(ax,'Bit time / UI');ylabel(ax,'NRZ logical level + lane offset');
title(ax,'B8 parallel SoT; header 3E CA 08 09; RGB888 white');legend(ax);grid(ax,'on');
ax=nexttile(tl);axis(ax,'off');
text(ax,0,1,sprintf(['3 lanes, LSB-first, first packet of HS\n\nSlot       Lane0     Lane1     Lane2\nSoT        B8        B8        B8\n0          3E        CA        08\n1          09        R0        G0\n2          B0        R1        G1\n...\n751        B749      CRC_L     CRC_H\n\nWhite payload: FF FF FF | CRC: 93 7B\nBlack payload: 00 00 00 | CRC: 4A 75']), ...
    'VerticalAlignment','top','FontName','Consolas','FontSize',12);
title(ax,'Actual byte striping used in the model');
ax=nexttile(tl);hold(ax,'on');names=["WW","WB","BW","BB"];
for ii=1:4
    s=double(book.contexts.(names(ii)).hsBits(:,2));
    stairs(ax,0:numel(s)-1,s+2*(ii-1),'DisplayName',names(ii));
end
xlim(ax,[45 110]);xlabel(ax,'Bit time / UI');ylabel(ax,'Logical level + context offset');
title(ax,'Two colors require boundary contexts');legend(ax);grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');
stairs(ax,0:31,ones(1,32),'DisplayName','white bits');stairs(ax,0:31,zeros(1,32),'DisplayName','black bits');
plot(ax,0:31,zeros(1,32),':','LineWidth',2,'DisplayName','Both interior edge trains = 0');
ylim(ax,[-.2 1.3]);xlabel(ax,'Interior bit index');ylabel(ax,'Bit / transition amplitude');
title(ax,'A byte boundary does not force an NRZ transition');legend(ax);
exportgraphics(f,fullfile(out,'01_protocol_codebook.png'),'Resolution',140);savefig(f,fullfile(out,'01_protocol_codebook.fig'));

f=figure('Name','Modulo gate applied to native IQ','Color','w','Position',[60 60 1400 850]);
tl=tiledlayout(f,2,2,'TileSpacing','compact');time=((0:size(y,1)-1)'+.5)/size(y,1)/f0*1e6;
ax=nexttile(tl);hold(ax,'on');plot(ax,time,y);plot(ax,time,gatePrediction,'k','LineWidth',1.4);
xlabel(ax,'Within-period time (us)');ylabel(ax,'Power / B1 mean');grid(ax,'on');
legend(ax,'B1 train','B2 test','B3 test','Fitted modulo gate');
title(ax,sprintf('Power gate D=%.3f; width %.3f us',gate.duty,gate.high_width_us));
ax=nexttile(tl);hold(ax,'on');
a=gate.template-mean(gate.template);
for bb=1:3
    b=y(:,bb)-mean(y(:,bb));
    g=real(ifft(conj(fft(a)).*fft(b)))/(norm(a)*norm(b));
    plot(ax,time,g);
end
xline(ax,gate.start_us,'--','Frozen B1 delay');
xlabel(ax,'Circular delay k / f_0 (us)');ylabel(ax,'Normalized G(k)');
title(ax,'Search delay only on training block');grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');
for bb=1:3,plot(ax,(100e6+psd{bb}.baseband_frequency_hz)/1e6,pow2db(psd{bb}.density));end
xlabel(ax,'RF frequency under I-jQ convention (MHz)');ylabel(ax,'PSD (dB ADC^2/Hz)');
title(ax,'Native 124.0828 MS/s IQ: no narrow-subband decimation');grid(ax,'on');
ax=nexttile(tl);bar(ax,[gate.testCorrelation;report.empirical_profile_correlations].');
xticks(ax,1:3);xticklabels(ax,{'Train B1','Test B2','Test B3'});ylabel(ax,'Correlation');
legend(ax,'Modulo gate','Empirical B1 profile','Location','southoutside');
title(ax,'Gate quality versus repeatability ceiling');ylim(ax,[0 1]);grid(ax,'on');
exportgraphics(f,fullfile(out,'02_modulo_gate_measurement.png'),'Resolution',140);savefig(f,fullfile(out,'02_modulo_gate_measurement.fig'));

f=figure('Name','Protocol templates versus controls','Color','w','Position',[80 70 1450 950]);
tl=tiledlayout(f,2,2,'TileSpacing','compact');
ax=nexttile(tl);hold(ax,'on');
rates=unique(scan.LaneRateHz);
for flag=1:-1:0
    s=zeros(size(rates));
    for rr=1:numel(rates),s(rr)=max(scan.TrainCorrelation(scan.LaneRateHz==rates(rr)&scan.ProtocolCandidate==flag));end
    plot(ax,rates/1e6,s,'-o','MarkerSize',3);
end
legend(ax,'Protocol candidates','Matched / geometry controls','Location','best');
xlabel(ax,'Assumed lane bitrate (Mb/s)');ylabel(ax,'Best training correlation');
title(ax,'Coarse rate scan; fractional refinement follows');grid(ax,'on');
ax=nexttile(tl);hold(ax,'on');plot(ax,time,y(:,2),'Color',[.3 .3 .3]);
plot(ax,time,validation(vw).prediction(:,2),'LineWidth',1.3);
plot(ax,time,validation(cw).prediction(:,2),'LineWidth',1.1);
xlabel(ax,'Within-period time (us)');ylabel(ax,'Power / training mean');grid(ax,'on');
legend(ax,'Held-out B2','Protocol winner','Control winner','Location','best');
title(ax,'All fitted parameters frozen from B1');
ax=nexttile(tl);bar(ax,[validation(vw).correlation;validation(cw).correlation;gate.testCorrelation].');
xticks(ax,1:3);xticklabels(ax,{'Train B1','Test B2','Test B3'});ylabel(ax,'Correlation');
legend(ax,'Protocol','Wrong codeword','Gate','Location','southoutside');grid(ax,'on');
title(ax,'Correlation does not certify packet decoding');
ax=nexttile(tl);axis(ax,'off');
text(ax,0,1,sprintf(['Protocol winner: %s\nRate hypothesis: %.0f Mb/s\nModel: %s / %s\nTest correlations: %.4f, %.4f\n\nControl winner: %s\nTest correlations: %.4f, %.4f\n\nUnknown: lane channel, clock, HS timings,\nmode, packet grouping, actual lane count.\nNo measured ECC/CRC or RGB bits decoded.'], ...
    validation(vw).label,validation(vw).rate_hz/1e6,validation(vw).emission,validation(vw).coupling, ...
    validation(vw).correlation(2:3),validation(cw).label,validation(cw).correlation(2:3)), ...
    'VerticalAlignment','top','FontSize',10,'Interpreter','none');
exportgraphics(f,fullfile(out,'03_template_controls.png'),'Resolution',140);savefig(f,fullfile(out,'03_template_controls.fig'));

f=figure('Name','Measured row-phase raster, not decoded image','Color','w','Position',[100 80 1450 900]);
tl=tiledlayout(f,1,3,'TileSpacing','compact');
for bb=1:3
    ax=nexttile(tl);im=raster{bb}/mean(raster{1},'all');
    imagesc(ax,time,0:size(im,1)-1,im);clim(ax,prctile(raster{1}(:)/mean(raster{1},'all'),[5 95]));
    xlabel(ax,'Within-period time (us)');ylabel(ax,'Row index modulo 1881');
    title(ax,sprintf('B%d: native power raster; not RGB decoding',bb));colorbar(ax);
end
colormap(f,'gray');
title(tl,'Measured period/frame candidates only; no screenshot used for fitting');
exportgraphics(f,fullfile(out,'04_native_rasters.png'),'Resolution',140);savefig(f,fullfile(out,'04_native_rasters.fig'));
end
