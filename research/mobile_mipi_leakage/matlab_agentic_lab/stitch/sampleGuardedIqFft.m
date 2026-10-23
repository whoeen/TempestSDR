function [values, diagnostics] = sampleGuardedIqFft(rawIq, querySamples, options)
%SAMPLEGUARDEDIQFFT Wideband fractional-delay sampling with explicit guards.
%   Query positions are zero-based complex-sample positions in RAWIQ.
%   RAWIQ must include real measured guard samples at both ends. The output
%   has the shape of QUERYSAMPLES and is complex single. Query coordinates
%   remain double precision even when IQ storage is single precision.
%
%   Example: [v,d] = sampleGuardedIqFft(rawWithGuards,q,GuardSamples=512);
%
%   A fourfold INTERPFT grid is followed by six-point (degree five) Lagrange
%   interpolation. Only the outer guard samples are smoothly tapered by
%   default. This mitigates FFT periodic-extension discontinuity but cannot
%   prove a universal finite-record error bound. Compare results obtained
%   with larger guards on real data; do not infer new RF bandwidth.
%
%   This routine is a fractional-delay interpolator, NOT an antialias filter.
%   Downsampling beyond the occupied-signal Nyquist limit is not supported.
%   MathWorks interpft reference: https://www.mathworks.com/help/matlab/ref/interpft.html
arguments
    rawIq (:,1) {mustBeNumeric}
    querySamples {mustBeNumeric,mustBeReal,mustBeFinite}
    options.GuardSamples (1,1) double {mustBeInteger,mustBeGreaterThanOrEqual(options.GuardSamples,64)} = 512
    options.TaperGuards (1,1) logical = true
    options.QueryChunkSamples (1,1) double {mustBeInteger,mustBePositive} = 2^17
end
assert(isa(rawIq,'single') || isa(rawIq,'double'), ...
    'stitch:FloatIqRequired','Input must be single or double complex IQ.');
assert(isvector(querySamples) && ~isempty(querySamples), ...
    'stitch:QueryVectorRequired','Provide a nonempty vector of sample coordinates.');
assert(all(isfinite(rawIq)),'stitch:NonfiniteIq','IQ contains nonfinite values.');
n = numel(rawIq);
guard = options.GuardSamples;
upsampleFactor = 4;
maxInputSamples = 2^21;
assert(n<=maxInputSamples,'stitch:InputTooLarge', ...
    'Block exceeds 2^21 raw samples; use guarded blocks and keep only interiors.');
assert(n>2*guard+6,'stitch:InsufficientBlock','Block does not contain both guards and interior.');
qMin = double(min(querySamples(:)));
qMax = double(max(querySamples(:)));
assert(qMin>=guard && qMax<=n-1-guard,'stitch:InsufficientGuard', ...
    'Queries must lie within [GuardSamples, N-1-GuardSamples] in zero-based samples.');
inputClass = class(rawIq);
x = complex(single(real(rawIq)),single(imag(rawIq)));
edgeMismatchBefore = double(abs(x(end)-x(1)));
if options.TaperGuards
    % Quintic smoothstep has zero first and second derivatives at each end.
    % The first/last G points change; all requested interior grid points do not.
    t = (0:guard-1).'/(guard-1);
    ramp = single(t.^3.*(10+t.*(-15+6*t)));
    x(1:guard) = x(1:guard).*ramp;
    x(end-guard+1:end) = x(end-guard+1:end).*flipud(ramp);
end
edgeMismatchAfter = double(abs(x(end)-x(1)));
% Explicit dimension avoids orientation-dependent interpretation.
upsampled = single(interpft(x,upsampleFactor*n,1));
clear x
values = complex(zeros(size(querySamples),'single'));
nodes = -2:3;
chunkSize = min(options.QueryChunkSamples,2^17);
for first=1:chunkSize:numel(querySamples)
    ids = first:min(first+chunkSize-1,numel(querySamples));
    position = upsampleFactor*double(querySamples(ids));
    base = floor(position);
    fraction = position-base;
    valueChunk = complex(zeros(size(fraction),'single'));
    for k=1:numel(nodes)
        weight = ones(size(fraction));
        for j=1:numel(nodes)
            if j~=k
                weight = weight.*(fraction-nodes(j))/(nodes(k)-nodes(j));
            end
        end
        gridIndex = base+nodes(k)+1;
        % Reshape because vector indexing of a column can change orientation.
        gridValues = reshape(upsampled(gridIndex),size(fraction));
        valueChunk = valueChunk+gridValues.*single(weight);
    end
    values(ids) = valueChunk;
end
diagnostics = struct('method','interpft x4 plus 6-point Lagrange', ...
    'raw_sample_count',n,'oversampled_count',upsampleFactor*n, ...
    'query_sample_count',numel(querySamples),'input_class',inputClass, ...
    'processing_class','complex single; double query positions and Lagrange weights', ...
    'output_class','complex single','query_origin','zero-based in raw input block', ...
    'upsample_factor',upsampleFactor,'lagrange_degree',5, ...
    'required_guard_samples',guard,'minimum_left_guard_samples',qMin, ...
    'minimum_right_guard_samples',n-1-qMax,'guard_taper_applied',options.TaperGuards, ...
    'guard_taper','quintic smoothstep on outer GuardSamples points only', ...
    'endpoint_difference_before_counts',edgeMismatchBefore, ...
    'endpoint_difference_after_counts',edgeMismatchAfter, ...
    'max_raw_block_samples',maxInputSamples,'max_oversampled_samples',4*maxInputSamples, ...
    'largest_oversampled_array_bytes',8*upsampleFactor*n, ...
    'query_chunk_samples',chunkSize, ...
    'memory_note','Array size excludes interpft internal workspace, caller input/output and query storage.', ...
    'periodic_extension_limitation','Finite guards and edge taper reduce but cannot bound arbitrary boundary error. Validate by guard-size convergence.', ...
    'antialias_filter_applied',false, ...
    'nyquist_note','Exact Nyquist components have ambiguous continuous-time interpolation. Test band stops at +/-60 MHz for Fs124.0828MHz.');
end
