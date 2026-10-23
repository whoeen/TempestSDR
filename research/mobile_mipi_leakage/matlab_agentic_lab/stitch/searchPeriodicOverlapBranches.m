function [best,alignedBTrainFFT,alignedBTestFFT,searchTable] = searchPeriodicOverlapBranches( ...
    aTrainFFT,bTrainFFT,aTestFFT,bTestFFT,centerBinA,nominalCenterBinB, ...
    periodSeconds,usableBandHz,branchCandidates,options)
%SEARCHPERIODICOVERLAPBRANCHES Search integer harmonic branches using train IQ.
%   Every candidate receives a full guarded-overlap COMPLEX circular
%   correlation. The best coarse candidates plus nominal branch zero receive
%   fractional-delay refinement with alignPeriodicOverlap. Selection uses
%   training complex coherence only. Test metrics never choose a branch.
%
%   BEST is the selected alignment plus branch-search diagnostics. The optional
%   aligned FFT outputs come directly from alignPeriodicOverlap. SEARCHTABLE
%   (also BEST.branch_search_table) is a JSON-compatible struct array; no large
%   spectral vectors are stored in it. Coarse spectra remain single precision.
arguments
    aTrainFFT {mustBeFloat,mustBeVector,mustBeFinite,mustBeNonempty}
    bTrainFFT {mustBeFloat,mustBeVector,mustBeFinite,mustBeNonempty}
    aTestFFT {mustBeFloat,mustBeVector,mustBeFinite,mustBeNonempty}
    bTestFFT {mustBeFloat,mustBeVector,mustBeFinite,mustBeNonempty}
    centerBinA (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger}
    nominalCenterBinB (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger}
    periodSeconds (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive}
    usableBandHz (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive} = 120e6
    branchCandidates {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBeVector,mustBeNonempty} = -16:16
    options.MaxFractionalCandidates (1,1) double {mustBeReal,mustBeFinite,mustBeInteger,mustBePositive} = 3
end
sampleCount = numel(aTrainFFT);
assert(mod(sampleCount,2)==0 && sampleCount>=4,'stitch:EvenFftRequired', ...
    'An even FFT length of at least four is required.');
assert(all([numel(bTrainFFT),numel(aTestFFT),numel(bTestFFT)]==sampleCount), ...
    'stitch:LengthMismatch','All Fourier coefficient vectors must have equal length.');
periodSeconds = double(periodSeconds);
usableBandHz = double(usableBandHz);
centerBinA = double(centerBinA);
nominalCenterBinB = double(nominalCenterBinB);
assert(usableBandHz<=sampleCount/periodSeconds*(1+1e-12), ...
    'stitch:BandExceedsGrid','Usable bandwidth exceeds the Fourier grid.');
edgeGuardHz = 3e6;
assert(usableBandHz>2*edgeGuardHz,'stitch:GuardConsumesBand', ...
    'Usable band must exceed the two 3 MHz guards.');
% Always evaluate nominal zero, even when the supplied list omits it.
branches = unique([double(branchCandidates(:));0]);
branchCount = numel(branches);
assert(max(abs([centerBinA;nominalCenterBinB+branches]))+sampleCount<flintmax, ...
    'stitch:UnrepresentableBins','Global harmonic indices must be exactly representable.');
aTrainSingle = single(aTrainFFT(:));
bTrainSingle = single(bTrainFFT(:));
entry = struct('branch_offset_bins',0,'center_bin_b',0,'overlap_bins',0, ...
    'coarse_complex_coherence',NaN,'coarse_delay_samples',NaN, ...
    'coarse_status','not_evaluated','fractional_refined',false, ...
    'refinement_status','not_selected','train_complex_coherence',NaN, ...
    'test_complex_coherence',NaN,'test_normalized_complex_error',NaN, ...
    'refined_delay_samples',NaN,'relative_phase_rad',NaN);
searchTable = repmat(entry,branchCount,1);
for branchIndex=1:branchCount
    centerB = nominalCenterBinB+branches(branchIndex);
    [score,lag,count,status] = coarseOverlap(aTrainSingle,bTrainSingle, ...
        centerBinA,centerB,periodSeconds,usableBandHz,edgeGuardHz);
    searchTable(branchIndex).branch_offset_bins = branches(branchIndex);
    searchTable(branchIndex).center_bin_b = centerB;
    searchTable(branchIndex).overlap_bins = count;
    searchTable(branchIndex).coarse_complex_coherence = score;
    searchTable(branchIndex).coarse_delay_samples = lag;
    searchTable(branchIndex).coarse_status = status;
end
coarseScores = [searchTable.coarse_complex_coherence].';
valid = find(isfinite(coarseScores));
assert(~isempty(valid),'stitch:NoValidBranch','No candidate has a finite nonzero-energy overlap.');
% Deterministic ties prefer the branch closest to nominal. No image or test
% observation participates in either this ranking or the final ranking.
[~,rank] = sortrows([-coarseScores(valid),abs(branches(valid)),branches(valid)],[1 2 3]);
rankedIndices = valid(rank);
refineIndices = rankedIndices(1:min(options.MaxFractionalCandidates,numel(rankedIndices)));
nominalIndex = find(branches==0,1);
if ~ismember(nominalIndex,refineIndices) && isfinite(coarseScores(nominalIndex))
    refineIndices(end+1) = nominalIndex;
end
alignments = cell(branchCount,1);
for refinementIndex=1:numel(refineIndices)
    branchIndex = refineIndices(refinementIndex);
    searchTable(branchIndex).fractional_refined = true;
    try
        alignment = alignPeriodicOverlap(aTrainFFT,bTrainFFT,aTestFFT,bTestFFT, ...
            centerBinA,nominalCenterBinB+branches(branchIndex),periodSeconds,usableBandHz);
        alignments{branchIndex} = alignment;
        searchTable(branchIndex).refinement_status = alignment.status;
        searchTable(branchIndex).train_complex_coherence = alignment.train_unit_gain.complex_coherence;
        searchTable(branchIndex).test_complex_coherence = alignment.test_unit_gain.complex_coherence;
        searchTable(branchIndex).test_normalized_complex_error = alignment.test_unit_gain.normalized_complex_error;
        searchTable(branchIndex).refined_delay_samples = alignment.delay_samples;
        searchTable(branchIndex).relative_phase_rad = alignment.phase_rad;
    catch exception
        searchTable(branchIndex).refinement_status = ['error:' exception.identifier];
    end
end
refinedScores = [searchTable.train_complex_coherence].';
refinedValid = find(isfinite(refinedScores));
assert(~isempty(refinedValid),'stitch:NoRefinedBranch','No fractional candidate refinement succeeded.');
[~,rank] = sortrows([-refinedScores(refinedValid),abs(branches(refinedValid)),branches(refinedValid)],[1 2 3]);
refinedRanked = refinedValid(rank);
winner = refinedRanked(1);
best = alignments{winner};
best.alignment = alignments{winner};
coarseRatio = scoreRatio(coarseScores(rankedIndices));
refinedRatio = scoreRatio(refinedScores(refinedRanked));
best.nominal_center_bin_b = nominalCenterBinB;
best.selected_center_bin_b = nominalCenterBinB+branches(winner);
best.selected_branch_offset_bins = branches(winner);
best.selected_offset_bins = branches(winner);
best.branch_search_candidates = branches.';
best.branch_search_candidate_count = branchCount;
best.max_fractional_candidates = options.MaxFractionalCandidates;
best.fractional_candidate_count = numel(refineIndices);
best.coarse_alternative_score_ratio = coarseRatio;
best.refined_alternative_score_ratio = refinedRatio;
best.selected_at_search_boundary = branches(winner)==min(branches) || branches(winner)==max(branches);
best.branch_ambiguity_threshold = 0.95;
best.branch_ambiguous = (isfinite(coarseRatio) && coarseRatio>0.95) || ...
    (isfinite(refinedRatio) && refinedRatio>0.95);
best.branch_selection_criterion = 'maximum training complex coherence after fractional refinement';
best.heldout_used_for_selection = false;
best.coarse_search_method = 'full guarded overlap complex IFFT peak / spectral-energy norm; every branch evaluated';
best.coarse_array_precision = 'single';
best.branch_search_table = searchTable;
% Large corrected arrays are requested only for the final selected branch.
if nargout>=3
    [~,alignedBTrainFFT,alignedBTestFFT] = alignPeriodicOverlap( ...
        aTrainFFT,bTrainFFT,aTestFFT,bTestFFT,centerBinA,best.selected_center_bin_b, ...
        periodSeconds,usableBandHz);
elseif nargout>=2
    [~,alignedBTrainFFT] = alignPeriodicOverlap(aTrainFFT,bTrainFFT,aTestFFT,bTestFFT, ...
        centerBinA,best.selected_center_bin_b,periodSeconds,usableBandHz);
end
end

function [score,lag,count,status] = coarseOverlap(a,b,centerA,centerB,period,usableBand,guard)
sampleCount = numel(a);
firstA = centerA-sampleCount/2;
firstB = centerB-sampleCount/2;
halfUsable = (usableBand/2-guard)*period;
first = ceil(max([firstA,firstB,centerA-halfUsable,centerB-halfUsable]));
last = floor(min([firstA+sampleCount-1,firstB+sampleCount-1, ...
    centerA+halfUsable,centerB+halfUsable]));
count = max(0,last-first+1);
score = NaN;
lag = NaN;
status = 'no_overlap';
if count==0
    return
end
globalBins = (first:last).';
aPart = a(globalBins-firstA+1);
bPart = b(globalBins-firstB+1);
energyA = sum(abs(aPart).^2,'double');
energyB = sum(abs(bPart).^2,'double');
if energyA<=0 || energyB<=0 || ~isfinite(energyA*energyB)
    status = 'no_shared_energy';
    return
end
packedCross = complex(zeros(sampleCount,1,'single'));
packedCross(mod(globalBins,sampleCount)+1) = bPart.*conj(aPart);
correlation = ifft(packedCross);
[peak,index] = max(abs(correlation));
score = min(1,double(peak)*sampleCount/sqrt(energyA*energyB));
lag = mod(index-1+sampleCount/2,sampleCount)-sampleCount/2;
status = 'evaluated';
end

function ratio = scoreRatio(sortedScores)
if numel(sortedScores)<2 || sortedScores(1)<=0
    ratio = NaN;
else
    ratio = sortedScores(2)/sortedScores(1);
end
end
