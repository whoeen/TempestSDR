classdef searchPeriodicOverlapBranchesTest < matlab.unittest.TestCase
    %SEARCHPERIODICOVERLAPBRANCHESTEST Known branch, delay, phase and gain tests.
    properties (TestParameter)
        trueOffset = struct('positive',5,'negative',-6);
    end
    methods (Test)
        function recoversKnownBranchDelayPhaseGain(testCase,trueOffset)
            fixture = branchFixture(trueOffset);
            [best,alignedTrain,alignedTest,search] = searchPeriodicOverlapBranches(fixture.args{:});
            testCase.verifyEqual(best.selected_offset_bins,trueOffset);
            testCase.verifyEqual(best.selected_center_bin_b,10240+trueOffset);
            testCase.verifyEqual(best.alignment.delay_samples,7.375,'AbsTol',3e-5);
            testCase.verifyLessThan(abs(angle(exp(1i*(best.alignment.phase_rad-0.61)))),4e-4);
            testCase.verifyEqual(best.alignment.positive_ls_gain,1/1.4,'AbsTol',1e-8);
            testCase.verifyLessThan(best.alignment.test_positive_ls_gain.normalized_complex_error,3e-4);
            testCase.verifyLessThan(norm(alignedTrain-fixture.expectedTrain)/norm(fixture.expectedTrain),4e-4);
            testCase.verifyLessThan(norm(alignedTest-fixture.expectedTest)/norm(fixture.expectedTest),4e-4);
            testCase.verifyEqual(numel(search),17);
            testCase.verifyTrue(all(strcmp({search.coarse_status},'evaluated')));
            testCase.verifyFalse(best.heldout_used_for_selection);
            testCase.verifyFalse(best.selected_at_search_boundary);
        end
        function heldoutMismatchDoesNotChooseAnotherBranch(testCase)
            fixture = branchFixture(5);
            fixture.args{4} = circshift(fixture.args{4},127);
            [best,~,~,search] = searchPeriodicOverlapBranches(fixture.args{:});
            testCase.verifyEqual(best.selected_offset_bins,5);
            testCase.verifyGreaterThan(best.alignment.train_unit_gain.complex_coherence,0.999999);
            testCase.verifyLessThan(best.alignment.test_unit_gain.complex_coherence,0.2);
            testCase.verifyGreaterThan(best.alignment.test_positive_ls_gain.normalized_complex_error,0.8);
            testCase.verifyFalse(best.heldout_used_for_selection);
            testCase.verifyTrue(all(isfinite([search.coarse_complex_coherence])));
        end
        function recordsSelectedBoundary(testCase)
            fixture = branchFixture(8);
            best = searchPeriodicOverlapBranches(fixture.args{:});
            testCase.verifyEqual(best.selected_offset_bins,8);
            testCase.verifyTrue(best.selected_at_search_boundary);
        end
        function alwaysRefinesNominalAlongsideChosenCandidates(testCase)
            fixture = branchFixture(5);
            [best,~,~,search] = searchPeriodicOverlapBranches(fixture.args{:},MaxFractionalCandidates=1);
            nominal = [search.branch_offset_bins]==0;
            testCase.verifyEqual(best.selected_offset_bins,5);
            testCase.verifyEqual(best.fractional_candidate_count,2);
            testCase.verifyTrue(search(nominal).fractional_refined);
        end
        function rejectsAllZeroSharedEnergy(testCase)
            fixture = branchFixture(5);
            fixture.args{2}(:) = 0;
            testCase.verifyError(@() searchPeriodicOverlapBranches(fixture.args{:}), ...
                'stitch:NoValidBranch');
        end
    end
end

function fixture = branchFixture(trueOffset)
sampleCount = 4096;
period = sampleCount/120e6;
centerA = 8192;
nominalCenterB = 10240;
actualCenterB = nominalCenterB+trueOffset;
binsA = centerA+(-sampleCount/2:sampleCount/2-1).';
binsB = actualCenterB+(-sampleCount/2:sampleCount/2-1).';
firstBin = min(binsA(1),binsB(1));
lastBin = max(binsA(end),binsB(end));
count = lastBin-firstBin+1;
stream = RandStream('mt19937ar','Seed',20261025);
sourceTrain = (randn(stream,count,1)+1i*randn(stream,count,1))/sqrt(sampleCount);
sourceTest = (randn(stream,count,1)+1i*randn(stream,count,1))/sqrt(sampleCount);
indexA = binsA-firstBin+1;
indexB = binsB-firstBin+1;
channel = 1.4*exp(1i*0.61-1i*(2*pi/sampleCount)*binsB*7.375);
aTrain = sourceTrain(indexA);
bTrain = sourceTrain(indexB).*channel;
aTest = sourceTest(indexA);
bTest = sourceTest(indexB).*channel;
fixture = struct();
fixture.args = {aTrain,bTrain,aTest,bTest,centerA,nominalCenterB,period,120e6,-8:8};
fixture.expectedTrain = 1.4*sourceTrain(indexB);
fixture.expectedTest = 1.4*sourceTest(indexB);
end
