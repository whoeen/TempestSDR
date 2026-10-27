function report = fitTimeMixedCafCodebook27(out, priorOut, observation, mix, options)
%FITTIMEMIXEDCAFCODEBOOK27 Refit codebooks after a matched frozen IQ operator.
%   OBSERVATION.target is harmonic-by-lag-by-class-by-block complex CAF.
%   Classes are [black white text]. OBSERVATION.halves contains the two
%   training-B1 half targets, harmonic-by-lag-by-class-by-half. Required scalar
%   coordinates: fs, fc, f0; vectors: orders and lags (nonzero sample lags).
%   Optional textPatterns (uint8 rows) and textPatternWeights enable a known
%   reference forward test; these must not be fitted from validation IQ.
%
%   MIX follows dsiTimeMixCafBasis27:
%       output(t)=sum_j weights(j)*input(t+timeOffsetsSeconds(j)).
%   It MUST describe the frozen deployed operator, including phase factors.
%   No operator is learned here. Every candidate forward waveform passes
%   through the identical operator before CAF and channel fitting.
%
%   The prior candidate bank supplies only packet/rate/emission/delay. Every
%   selected candidate gets a fresh shared black/white 3-lane channel from B1.
%   Weights and winners are selected on B1 and frozen for later blocks.
%   This is a conditional re-fit, not a repeated full bitrate/timing search.

arguments
    out (1,1) string
    priorOut (1,1) string
    observation (1,1) struct
    mix (1,1) struct
    options (1,1) struct = struct()
end
assert(lower(replace(out,"\","/"))~=lower(replace(priorOut,"\","/")), ...
    "New output directory must differ from prior results.");
required=["target","halves","fs","fc","f0","orders","lags"];
assert(all(isfield(observation,required)),"Missing observation fields.");
assert(all(isfield(mix,["weights","timeOffsetsSeconds"])), ...
    "The exact deployed linear operator is required.");
prior=load(fullfile(priorOut,"caf_channel_fits.mat"),"groups","results");
settings=struct("maxStarts",3,"maxIterations",1500, ...
    "groupIndices",1:numel(prior.results));
names=fieldnames(options);
for ii=1:numel(names)
    assert(isfield(settings,names{ii}),"Unknown option: %s",names{ii});
    settings.(names{ii})=options.(names{ii});
end
indices=double(settings.groupIndices(:).');
validateattributes(indices,{'numeric'},{'nonempty','integer','positive', ...
    '<=',numel(prior.results)});
assert(numel(unique(indices))==numel(indices),"Duplicate candidate indices.");
orders=double(observation.orders(:));
lags=double(observation.lags(:));
assert(all(lags~=0),"This adapter fits nonzero lags only.");
target=double(observation.target);
halves=double(observation.halves);
assert(size(target,1)==numel(orders)&&size(target,2)==numel(lags)&& ...
    size(target,3)==3&&size(target,4)>=2,"Target dimensions differ.");
assert(size(halves,1)==numel(orders)&&size(halves,2)==numel(lags)&& ...
    size(halves,3)==3&&size(halves,4)==2,"B1 half-target dimensions differ.");
assert(all(isfinite(target),"all")&&all(isfinite(halves),"all"), ...
    "Nonfinite CAF target.");
if isfield(observation,"precisionWeights")
    weights=double(observation.precisionWeights);
    assert(isequal(size(weights),[numel(orders),numel(lags),3]) && ...
        all(isfinite(weights),"all") && all(weights>=0,"all") && ...
        any(weights>0,"all"),"Invalid shared precision weights.");
    assert(isfield(observation,"weightSource"),"Shared weights need source metadata.");
    weightSource=string(observation.weightSource);
else
    weights=trainingWeights(halves);
    weightSource="This method B1 half-difference (not shared across methods).";
end
training=target(:,:,1:2,1);training=training(:);
weightBlackWhite=weights(:,:,1:2);weightBlackWhite=weightBlackWhite(:);
coordinates=struct("fsHz",double(observation.fs), ...
    "fcHz",double(observation.fc),"lagSamples",lags, ...
    "harmonicOrders",orders,"delayPhase",0);
numberBlocks=size(target,4);
numberCandidates=numel(indices);
results=cell(numberCandidates,1);
predictions=cell(numberCandidates,1);
operatorAudits=cell(numberCandidates,1);
for candidateIndex=1:numberCandidates
    priorIndex=indices(candidateIndex);
    old=prior.results(priorIndex);
    group=prior.groups(priorIndex);
    coordinates.delayPhase=old.delay_phase;
    black=filteredBasis(group.black,old,observation.f0,coordinates,mix);
    [white,audit]=filteredBasis(group.white,old,observation.f0,coordinates,mix);
    design=[black;white];
    fit=fitDsiCafChannel27(design,training,weightBlackWhite, ...
        struct("maxStarts",settings.maxStarts, ...
        "maxIterations",settings.maxIterations));
    prediction=fit.prediction;
    blocks=cell(numberBlocks,1);
    for blockIndex=1:numberBlocks
        held=target(:,:,1:2,blockIndex);
        blocks{blockIndex}=compareCaf(prediction,held(:),weightBlackWhite);
    end
    record=rmfield(fit,"prediction");
    record.name=old.name;record.family=old.family;record.control=old.control;
    record.prior_group_index=priorIndex;
    record.rate_hz=old.rate_hz;record.emission_index=old.emission_index;
    record.emission=old.emission;record.delay_phase=old.delay_phase;
    record.delay_seconds=old.delay_seconds;
    record.blocks=[blocks{:}];
    record.channel_shared_between_classes=["black","white"];
    record.channel_training_block=1;
    record.channel_refitted=true;
    record.rate_timing_emission_refitted=false;
    record.forward_operator_matched=true;
    record.operator_common_scalar_relative_error= ...
        audit.response_common_scalar_relative_error;
    record.operator_sum_branch_scalar_power=audit.sum_branch_scalar_power;
    record.operator_near_null_for_periodic_template=audit.sum_branch_scalar_power<1e-10;
    results{candidateIndex}=record;
    predictions{candidateIndex}=reshape(prediction,numel(orders),numel(lags),2);
    operatorAudits{candidateIndex}=audit;
    fprintf("Matched operator %d/%d %s: B1 %.4f, B2 %.4f.\n", ...
        candidateIndex,numberCandidates,record.name, ...
        record.blocks(1).nmse,record.blocks(2).nmse);
end
results=[results{:}];
valid=find([results.control]==0);
wrong=find([results.control]~=0);
assert(~isempty(valid)&&~isempty(wrong),"Need protocol and wrong controls.");
trainLoss=arrayfun(@(r) r.blocks(1).nmse,results);
[~,ii]=min(trainLoss(valid));validWinner=valid(ii);
[~,ii]=min(trainLoss(wrong));controlWinner=wrong(ii);
matched=find([results.control]~=0 & ...
    [results.family]==results(validWinner).family);
assert(~isempty(matched),"Need a same-family wrong control.");
[~,ii]=min(trainLoss(matched));matchedWinner=matched(ii);
selected=unique([validWinner,matchedWinner,controlWinner],"stable");
[textReport,textPredictions]=textForwardTest(observation,mix,coordinates, ...
    results,selected,weights);
report=struct("status","complete", ...
    "scope","Matched frozen linear-IQ operator; conditional prior rate/timing hypotheses.", ...
    "candidate_count",numberCandidates,"prior_group_indices",indices, ...
    "valid",jsonFit(results(validWinner)), ...
    "matched_control",jsonFit(results(matchedWinner)), ...
    "control",jsonFit(results(controlWinner)), ...
    "selected_by","B1 weighted complex NMSE only.", ...
    "weights",weightSource, ...
    "channel_fit","Fresh shared black/white three-lane rank-one PSD h*h'.", ...
    "full_rate_timing_search_repeated",false, ...
    "operator_matched_to_forward_codewords",true, ...
    "deposition_kernel","1100-bin exact grid: even lag 1; odd lag cos(pi*harmonic/1100).", ...
    "high_order_grid_alias_mixing_modeled",false, ...
    "operator",jsonMixer(mix), ...
    "reference_text_validation",textReport, ...
    "global_rf_phase_identifiable",false, ...
    "actual_lane_count_verified",false,"packet_decoded",false, ...
    "cross_pipeline_nmse_caution", ...
    "Targets and precision weights change with preprocessing; NMSE differences alone are not SNR gains.", ...
    "settings",settings);
if ~isfolder(out),mkdir(out);end
writeJson(fullfile(out,"pca_caf_codebook.json"),report);
save(fullfile(out,"pca_caf_codebook.mat"),"results","predictions", ...
    "operatorAudits","target","halves","weights","orders","lags", ...
    "mix","settings","validWinner","matchedWinner","controlWinner", ...
    "textReport","textPredictions","-v7.3");
writeCandidateTable(out,results);
end

function weights=trainingWeights(halves)
noise=abs(halves(:,:,:,1)-halves(:,:,:,2)).^2/2;
floorVariance=max(median(noise(:,:,1:2),"all"),eps)*0.1;
weights=1./max(noise,floorVariance);
typical=median(weights(:,:,1:2),"all");
weights=min(25*typical,max(typical/25,weights))/typical;
end

function [basis,audit]=filteredBasis(packet,record,f0,coordinates,mix)
model=dsi3LanePowerModel27(packet,record.rate_hz,f0,8192);
[basis,audit]=dsiTimeMixCafBasis27(model,record.emission_index,coordinates,mix);
% Exact midpoint deposition on the new equally spaced 1100-bin IQ grid.
% Even integer lags fall on bins; odd lags fall halfway between two bins.
% Relative to the ideal midpoint CAF, linear deposition therefore gives
% 1 for even lags and cos(pi*h/N) for odd lags, with no extra phase factor.
% High-order alias mixing from the finite sampled grid is NOT modeled here.
numberBins=1100;
lagSamples=coordinates.lagSamples(:);
assert(all(lagSamples==round(lagSamples)), ...
    "The exact-grid deposition kernel requires integer sample lags.");
oddLag=mod(lagSamples,2)~=0;
deposit=ones(numel(coordinates.harmonicOrders),numel(lagSamples));
deposit(:,oddLag)=repmat(cos(pi*coordinates.harmonicOrders(:)/numberBins), ...
    1,nnz(oddLag));
basis=basis.*deposit(:);
end

function [report,predictions]=textForwardTest(observation,mix,coordinates,results,selected,weights)
predictions={};
if ~all(isfield(observation,["textPatterns","textPatternWeights"]))
    report=struct("status","not_run","reason", ...
        "Explicit known-reference text patterns were not supplied.");
    return
end
patterns=observation.textPatterns;
patternWeights=double(observation.textPatternWeights(:));
assert(ismatrix(patterns)&&size(patterns,2)==750, ...
    "Expected 750-column grayscale reference rows.");
validateattributes(patternWeights,{'numeric'},{'nonnegative','finite', ...
    'numel',size(patterns,1)});
assert(sum(patternWeights)>0,"Empty text reference weights.");
patternWeights=patternWeights/sum(patternWeights);
controlNames=["valid","header-byte-permutation","header-bit-order-reversed", ...
    "shuffled-sync-header","geometry"];
records=cell(numel(selected),1);
predictions=cell(numel(selected),1);
for candidateIndex=1:numel(selected)
    record=results(selected(candidateIndex));
    if record.family<=4
        mode="video";vc=record.family-1;
    elseif record.family==5
        mode="2C";vc=0;
    else
        mode="3C";vc=0;
    end
    coordinates.delayPhase=record.delay_phase;
    average=complex(zeros(numel(coordinates.harmonicOrders)* ...
        numel(coordinates.lagSamples),9));
    for patternIndex=1:size(patterns,1)
        packet=buildDsiGrayPacketCaf27(uint8(patterns(patternIndex,:)), ...
            mode,vc,controlNames(record.control+1));
        basis=filteredBasis(packet,record,observation.f0,coordinates,mix);
        average=average+patternWeights(patternIndex)*basis;
    end
    prediction=average*hermitianVector(record.H);
    textWeights=weights(:,:,3);textWeights=textWeights(:);
    blocks=cell(size(observation.target,4),1);
    for blockIndex=1:numel(blocks)
        held=observation.target(:,:,3,blockIndex);
        blocks{blockIndex}=compareCaf(prediction,held(:),textWeights);
    end
    records{candidateIndex}=struct("candidate",record.name, ...
        "blocks",[blocks{:}],"channel_refitted_on_text",false);
    predictions{candidateIndex}=reshape(prediction, ...
        numel(coordinates.harmonicOrders),numel(coordinates.lagSamples));
end
report=struct("status","complete","pattern_count",size(patterns,1), ...
    "scope","Known-reference forward prediction; no decoding or image insertion.", ...
    "row_model","Each text-row pattern is periodically repeated before applying the frozen operator.", ...
    "channel_refitted_on_text",false,"candidates",[records{:}]);
end

function theta=hermitianVector(H)
theta=[real(diag(H));real(H(1,2));imag(H(1,2));real(H(1,3)); ...
    imag(H(1,3));real(H(2,3));imag(H(2,3))];
end

function metric=compareCaf(prediction,target,weights)
targetEnergy=sum(weights.*abs(target).^2);
assert(targetEnergy>0,"Zero weighted validation target.");
inner=sum(weights.*conj(target).*prediction);
den=sqrt(targetEnergy*sum(weights.*abs(prediction).^2));
metric=struct("nmse",sum(weights.*abs(target-prediction).^2)/targetEnergy, ...
    "real_coherence",real(inner)/max(den,realmin), ...
    "abs_coherence",abs(inner)/max(den,realmin), ...
    "phase_deg",angle(inner)*180/pi, ...
    "unweighted_nmse",sum(abs(target-prediction).^2)/sum(abs(target).^2));
end

function s=jsonFit(s)
s.h_real=real(s.h);s.h_imag=imag(s.h);
s.H_real=real(s.H);s.H_imag=imag(s.H);
s.relative_channel_real=real(s.relativeChannel);
s.relative_channel_imag=imag(s.relativeChannel);
s=rmfield(s,{'h','H','relativeChannel'});
end

function s=jsonMixer(mix)
s=struct("definition","y(t)=sum_j w_j*z(t+delta_t_j)", ...
    "weights_real",real(mix.weights), ...
    "weights_imag",imag(mix.weights), ...
    "time_offsets_seconds",mix.timeOffsetsSeconds(:), ...
    "branch_combination","Sum of branch CAFs without cross terms", ...
    "learned_here",false,"frozen_operator_required",true);
end

function writeCandidateTable(out,results)
numberCandidates=numel(results);numberBlocks=numel(results(1).blocks);
nmse=zeros(numberCandidates,numberBlocks);
for ii=1:numberCandidates
    for jj=1:numberBlocks,nmse(ii,jj)=results(ii).blocks(jj).nmse;end
end
names=string({results.name}).';
values=table(names,[results.prior_group_index].',[results.rate_hz].', ...
    [results.delay_seconds].',[results.channelJacobianCondition].', ...
    'VariableNames',["Candidate","PriorGroup","RateHypothesisHz", ...
    "DelayHypothesisSeconds","ChannelJacobianCondition"]);
for jj=1:numberBlocks,values.("B"+jj+"Nmse")=nmse(:,jj);end
writetable(values,fullfile(out,"pca_caf_codebook.csv"));
end

function writeJson(path,value)
fid=fopen(path,"w","n","UTF-8");assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,"PrettyPrint",true),"char");
end
