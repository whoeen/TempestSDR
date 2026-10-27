function report = fitPcaCafObservationBank27(out, priorOut, options)
%FITPCACAFOBSERVATIONBANK27 Match frame-PCA codebooks with shared raw weights.
%   Reads OUT/pca_caf_observations.mat, variable observations. Each method has
%   name, target [H,L,3,B], halves [H,L,3,2], and mix(weights K-by-J,
%   timeOffsetsSeconds K-by-1). Multiple columns of weights are CAF-ensemble
%   branches, not waveforms coherently added together.
%   Rawgrid B1 half precision weights are frozen for every fitted method.
%   All 30 old packet/control geometries get newly fitted shared lane h.
%   Exact frame-comb scalar invariance is asserted for each forward model.
%   Known binary screenshot rows are used solely for held-out forward tests.
%
%   Required top-level coordinates are fs,fc,f0,orders,lags,labels,rowFeatures.
%   Prior rate, emission and delay remain fixed; no fresh full search occurs.
%   Output is stored under OUT/codebook_METHOD and a bank summary JSON/MAT.

arguments
    out (1,1) string
    priorOut (1,1) string
    options (1,1) struct = struct()
end
settings=struct("methodNames",["rawgrid","PC1","selected"], ...
    "maxStarts",3,"maxIterations",1500,"reuseCompleted",false);
fields=fieldnames(options);
for ii=1:numel(fields)
    assert(isfield(settings,fields{ii}),"Unknown option: %s",fields{ii});
    settings.(fields{ii})=options.(fields{ii});
end
loaded=load(fullfile(out,"pca_caf_observations.mat"),"observations");
bank=loaded.observations;
assert(all(isfield(bank,["fs","fc","f0","orders","lags", ...
    "labels","rowFeatures","methods"])),"Incomplete PCA observation bank.");
methodNames=string({bank.methods.name});
rawIndex=find(lower(methodNames)=="rawgrid");
assert(isscalar(rawIndex),"Exactly one rawgrid control is required.");
rawHalves=double(bank.methods(rawIndex).halves);
noise=abs(rawHalves(:,:,:,1)-rawHalves(:,:,:,2)).^2/2;
floorVariance=max(median(noise(:,:,1:2),"all"),eps)*0.1;
sharedWeights=1./max(noise,floorVariance);
typical=median(sharedWeights(:,:,1:2),"all");
sharedWeights=min(25*typical,max(typical/25,sharedWeights))/typical;
rowMeta=jsondecode(fileread(fullfile(priorOut,"row_label_metadata.json")));
screen=imread(string(rowMeta.reference_path));
sourceRows=round(bank.rowFeatures.source_coordinate(bank.labels==3))+1;
assert(all(sourceRows>=1&sourceRows<=size(screen,1)), ...
    "Reference text row indices outside the screenshot.");
binaryRows=uint8(255*(screen(sourceRows,:,1)>=128));
[patterns,~,patternIndex]=unique(binaryRows,"rows");
counts=accumarray(patternIndex,1);
patternWeights=counts/sum(counts);
requested=string(settings.methodNames(:));
records=cell(numel(requested),1);
destinations=strings(numel(requested),1);
for ii=1:numel(requested)
    index=find(lower(methodNames)==lower(requested(ii)));
    assert(isscalar(index),"Requested method missing or duplicated: %s",requested(ii));
    method=bank.methods(index);
    obs=struct("fs",bank.fs,"fc",bank.fc,"f0",bank.f0, ...
        "orders",bank.orders,"lags",bank.lags, ...
        "target",method.target,"halves",method.halves, ...
        "precisionWeights",sharedWeights, ...
        "weightSource","Rawgrid B1 half-difference precision; floored/capped; shared unchanged across every method, codeword and test block.", ...
        "textPatterns",patterns,"textPatternWeights",patternWeights);
    mix=method.mix;
    mix.periodicRfGridInvariant=true;
    % This assumes preprocessing retained the original within-row CAF epoch.
    % A common absolute IQ phase cancels, but an unknown time shift does not.
    safeName=regexprep(lower(string(method.name)),"[^a-z0-9_-]","_");
    destinations(ii)=fullfile(out,"codebook_"+safeName);
    existing=fullfile(destinations(ii),"pca_caf_codebook.mat");
    if settings.reuseCompleted && isfile(existing)
        priorRun=load(existing,"target","weights","mix","settings");
        assert(isequaln(priorRun.target,obs.target)&&isequaln(priorRun.weights,sharedWeights) ...
            &&isequaln(priorRun.mix,mix),"Cached result differs from current observation/operator.");
        records{ii}=jsondecode(fileread(fullfile(destinations(ii),"pca_caf_codebook.json")));
        fprintf("Reusing verified completed %s fit.\n",method.name);
        continue
    end
    records{ii}=fitTimeMixedCafCodebook27(destinations(ii),priorOut, ...
        obs,mix,struct("maxStarts",settings.maxStarts, ...
        "maxIterations",settings.maxIterations));
end
report=struct("status","complete", ...
    "methods",requested,"output_directories",destinations, ...
    "method_reports",[records{:}], ...
    "shared_precision_source","rawgrid B1 half CAF difference", ...
    "model_operator","Exact fixed frame-comb applied to every forward lane before CAF.", ...
    "periodic_model_consequence", ...
    "For integer row-period frame offsets, each branch response is a common scalar across RF harmonics; channel refitting absorbs its scale.", ...
    "reference_text_threshold",128, ...
    "reference_text_unique_rows",size(patterns,1), ...
    "reference_used_for","Known-pattern forward validation only, never measured image insertion.", ...
    "caf_phase_epoch_assumption","Same within-row epoch as prior complex CAF.", ...
    "full_rate_timing_search_repeated",false, ...
    "physical_channel_identified",false,"packet_decoded",false);
writeJson(fullfile(out,"pca_caf_codebook_bank.json"),report);
save(fullfile(out,"pca_caf_codebook_bank.mat"),"report","sharedWeights", ...
    "patterns","patternWeights","sourceRows","settings","-v7.3");
end

function writeJson(path,value)
fid=fopen(path,"w","n","UTF-8");assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,"PrettyPrint",true),"char");
end
