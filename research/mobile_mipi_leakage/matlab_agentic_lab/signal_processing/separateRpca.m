function [lowRank, sparsePart, residual, metadata] = separateRpca(observed, options)
%SEPARATERPCA Bounded exploratory principal-component pursuit (real/complex).
%   Minimize nuclear_norm(L) + lambda*sum(abs(S)), subject to X=L+S.
%   A low-rank output is a mathematical component, not an identified emitter.
arguments
    observed (:,:) double {mustBeFinite}
    options.Lambda (1,1) double {mustBeNonnegative} = 0
    options.Tolerance (1,1) double {mustBePositive} = 1e-6
    options.MaxIterations (1,1) double {mustBeInteger,mustBePositive} = 200
    options.MaxEntries (1,1) double {mustBeInteger,mustBePositive} = 65536
    options.MatrixAxes (1,1) string = "unspecified; caller must define axes"
    options.OutputPrefix (1,1) string = ""
end
assert(~isempty(observed),'mobile:EmptyRpca','Provide a nonempty matrix.');
assert(numel(observed)<=options.MaxEntries,'mobile:RpcaBound', ...
    'Choose a bounded ROI or explicitly increase MaxEntries after assessing SVD cost.');
lambda = options.Lambda;
if lambda==0
    lambda = 1/sqrt(max(size(observed)));
end
initialSingular = svd(observed,'econ');
normF = norm(observed,'fro');
norm2 = initialSingular(1);
lowRank = zeros(size(observed));
sparsePart = zeros(size(observed));
dual = observed/max([norm2,max(abs(observed),[],'all')/lambda,eps]);
mu = 1.25/max(norm2,eps);
muMaximum = mu*1e7;
history = zeros(options.MaxIterations,3);
converged = false;
for iteration=1:options.MaxIterations
    [u,s,v] = svd(observed-sparsePart+dual/mu,'econ');
    shrunk = max(diag(s)-1/mu,0);
    active = shrunk>0;
    lowRank = (u(:,active).*shrunk(active).')*v(:,active)';
    temporary = observed-lowRank+dual/mu;
    sparsePart = temporary.*max(0,1-(lambda/mu)./max(abs(temporary),eps));
    residual = observed-lowRank-sparsePart;
    relativeError = norm(residual,'fro')/max(normF,eps);
    history(iteration,:) = [relativeError,nnz(active),mu];
    if relativeError<=options.Tolerance
        converged = true;
        break
    end
    dual = dual+mu*residual;
    mu = min(mu*1.5,muMaximum);
end
history = history(1:iteration,:);
sparseMask = abs(sparsePart)>options.Tolerance*max(max(abs(observed),[],'all'),eps);
lowSingular = svd(lowRank,'econ');
metadata = struct('method','inexact augmented-Lagrangian principal-component pursuit', ...
    'matrix_size',size(observed),'matrix_axes',options.MatrixAxes, ...
    'lambda',lambda,'tolerance',options.Tolerance,'iterations',iteration, ...
    'converged',converged,'relative_reconstruction_error',relativeError, ...
    'initial_singular_values',initialSingular,'low_rank_singular_values',lowSingular, ...
    'numerical_low_rank',nnz(lowSingular>options.Tolerance*max(lowSingular(1),eps)), ...
    'sparse_entry_fraction',mean(sparseMask,'all'), ...
    'rows_with_sparse_entries_fraction',mean(any(sparseMask,2)), ...
    'columns_with_sparse_entries_fraction',mean(any(sparseMask,1)), ...
    'history_columns',{{'relative_reconstruction_error','threshold_rank','mu'}}, ...
    'history',history,'identification_status','No MIPI/panel/clutter identity assigned', ...
    'assumption_checks','Dense or coherent interference can violate sparse/incoherent assumptions. Small fit residual is not source-separation proof.');
if strlength(options.OutputPrefix)>0
    writeJsonFile(options.OutputPrefix+"_metadata.json",metadata);
    save(options.OutputPrefix+"_components.mat",'observed','lowRank','sparsePart','residual','metadata','-v7');
end
end
