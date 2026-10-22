function [targetPart, nuisancePart, residual, metadata] = separateMatchedSubspace(observed, targetBasis, options)
%SEPARATEMATCHEDSUBSPACE Joint fit of explicit target and nuisance hypotheses.
%   Rows are features and columns observations. Basis provenance is required.
%   Overlapping non-identifiable bases are rejected, not assigned arbitrarily.
arguments
    observed (:,:) double {mustBeFinite}
    targetBasis (:,:) double {mustBeFinite}
    options.NuisanceBasis (:,:) double {mustBeFinite} = zeros(0,0)
    options.TargetProvenance (1,1) string = ""
    options.NuisanceProvenance (1,1) string = ""
    options.RankTolerance (1,1) double {mustBePositive} = 1e-8
    options.OutputPrefix (1,1) string = ""
end
assert(strlength(options.TargetProvenance)>0,'mobile:ReferenceProvenance', ...
    'Provide provenance for the independent target reference or theoretical basis.');
assert(~isempty(observed) && ~isempty(targetBasis),'mobile:EmptyTarget', ...
    'Provide nonempty observations and a nonempty target basis.');
assert(size(targetBasis,1)==size(observed,1),'mobile:SubspaceSize','Target basis feature dimension differs.');
[targetQ,~,~] = svd(targetBasis,'econ');
targetSingular = svd(targetBasis,'econ');
targetRank = nnz(targetSingular>options.RankTolerance*max(targetSingular(1),eps));
assert(targetRank>0,'mobile:EmptyTarget','Target basis has zero numerical rank.');
targetQ = targetQ(:,1:targetRank);
if isempty(options.NuisanceBasis)
    nuisanceQ = zeros(size(observed,1),0);
    maximumOverlap = 0;
else
    assert(strlength(options.NuisanceProvenance)>0,'mobile:ReferenceProvenance', ...
        'Document the nuisance-reference acquisition or model.');
    assert(size(options.NuisanceBasis,1)==size(observed,1),'mobile:SubspaceSize', ...
        'Nuisance basis feature dimension differs.');
    [nuisanceQ,nuisanceS,~] = svd(options.NuisanceBasis,'econ');
    nuisanceSingular = diag(nuisanceS);
    nuisanceRank = nnz(nuisanceSingular>options.RankTolerance*max(nuisanceSingular(1),eps));
    nuisanceQ = nuisanceQ(:,1:nuisanceRank);
    overlaps = svd(targetQ'*nuisanceQ);
    maximumOverlap = max([overlaps;0]);
end
jointBasis = [targetQ,nuisanceQ];
singular = svd(jointBasis,'econ');
jointRank = nnz(singular>options.RankTolerance*singular(1));
assert(jointRank==size(jointBasis,2),'mobile:NonidentifiableSubspaces', ...
    'Target/nuisance hypotheses overlap or are underdetermined. Use independent discriminating measurements.');
coefficients = jointBasis\observed;
targetPart = targetQ*coefficients(1:targetRank,:);
nuisancePart = nuisanceQ*coefficients(targetRank+1:end,:);
residual = observed-targetPart-nuisancePart;
metadata = struct('method','joint least-squares fit of explicitly supplied subspaces', ...
    'observation_size',size(observed),'target_rank',targetRank, ...
    'nuisance_rank',size(nuisanceQ,2),'target_provenance',options.TargetProvenance, ...
    'nuisance_provenance',options.NuisanceProvenance,'maximum_canonical_overlap',maximumOverlap, ...
    'joint_condition_number',singular(1)/singular(end), ...
    'residual_energy_fraction',norm(residual,'fro')^2/max(norm(observed,'fro')^2,eps), ...
    'target_energy_fraction',norm(targetPart,'fro')^2/max(norm(observed,'fro')^2,eps), ...
    'nuisance_energy_fraction',norm(nuisancePart,'fro')^2/max(norm(observed,'fro')^2,eps), ...
    'rank_tolerance',options.RankTolerance, ...
    'interpretation','Components follow supplied hypotheses, not automatic emitter identity. Nonorthogonal component energies need not add; large overlap amplifies noise.');
if strlength(options.OutputPrefix)>0
    writeJsonFile(options.OutputPrefix+"_metadata.json",metadata);
    save(options.OutputPrefix+"_components.mat",'observed','targetPart','nuisancePart','residual','metadata','-v7');
end
end
