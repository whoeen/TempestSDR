classdef synthesizePeriodicBandsTest < matlab.unittest.TestCase
    %SYNTHESIZEPERIODICBANDSTEST Bounded synthetic periodic spectral merge tests.
    methods (Test)
        function pairRaisedCosinePreservesCommonSpectrum(testCase)
            fixture = consistentBands(2);
            [output,meta,diagnostic] = synthesizePeriodicBands(fixture.bands,fixture.period, ...
                Method="raised_cosine",OutputClass="double");
            expected = expectedOnOutput(fixture,meta,diagnostic);
            testCase.verifyLessThan(norm(output-expected)/norm(expected),2e-14);
            testCase.verifyLessThan(meta.max_abs_weight_sum_minus_one_on_covered_bins,2e-15);
            testCase.verifyEqual(meta.internal_gap_bin_count,0);
            testCase.verifyGreaterThanOrEqual(meta.output_rate_hz,2*meta.nominal_union_hz);
            testCase.verifyEqual(norm(output(1:meta.output_fft_length/2)),0,'AbsTol',1e-15);
        end
        function elevenBandsHaveContinuousUnityCoverage(testCase)
            fixture = consistentBands(11);
            [output,meta,diagnostic] = synthesizePeriodicBands(fixture.bands,fixture.period, ...
                Method="raised_cosine",OutputClass="single");
            expected = expectedOnOutput(fixture,meta,diagnostic);
            testCase.verifyLessThan(norm(double(output)-expected)/norm(expected),2e-7);
            testCase.verifyLessThan(meta.max_abs_weight_sum_minus_one_on_covered_bins,2e-7);
            testCase.verifyEqual(meta.internal_gap_bin_count,0);
            testCase.verifyEqual(meta.nominal_union_hz,720e6,'AbsTol',1e-5);
            testCase.verifyLessThanOrEqual(max(diagnostic.coverage_count),uint8(2));
            testCase.verifyEqual(log2(meta.output_fft_length),round(log2(meta.output_fft_length)),'AbsTol',1e-14);
        end
        function literalLrHasUnityOverlapButOutOfOverlapLoss(testCase)
            fixture = consistentBands(2);
            [output,meta,diagnostic] = synthesizePeriodicBands(fixture.bands,fixture.period, ...
                Method="paper_lr_w8",EdgeGuardHz=0,OutputClass="double");
            expected = expectedOnOutput(fixture,meta,diagnostic);
            overlap = diagnostic.coverage_count==2;
            singleCoverage = diagnostic.coverage_count==1;
            weightedExpected = expected;
            indices = meta.output_fft_length/2+(1:numel(diagnostic.weight_sum));
            weightedExpected(indices) = weightedExpected(indices).*diagnostic.weight_sum;
            testCase.verifyLessThan(norm(output-weightedExpected)/norm(weightedExpected),2e-14);
            testCase.verifyLessThan(max(abs(diagnostic.weight_sum(overlap)-1)),2e-15);
            testCase.verifyLessThan(min(diagnostic.weight_sum(singleCoverage)),0.99);
            testCase.verifyFalse(meta.support_limited_partition_unity);
            testCase.verifyEqual(meta.edge_guard_hz,0,'AbsTol',1e-15);
            testCase.verifyEqual(meta.source_lr_filter_rate_hz,360e6,'AbsTol',1e-5);
            testCase.verifyGreaterThan(meta.output_rate_hz,meta.source_lr_filter_rate_hz);
            expectedLow = 1/(1+(tan(pi*30e6/360e6)/tan(pi*90e6/360e6))^8);
            testCase.verifyEqual(diagnostic.weight_sum(1025),expectedLow,'AbsTol',1e-13);
        end
        function literalLrSupportsTinyThreeWayOverlap(testCase)
            fixture = consistentBands(3,2047);
            [output,meta,diagnostic] = synthesizePeriodicBands(fixture.bands,fixture.period, ...
                Method="paper_lr_w8",EdgeGuardHz=0,OutputClass="double");
            weightedExpected = expectedOnOutput(fixture,meta,diagnostic);
            indices = meta.output_fft_length/2+(1:numel(diagnostic.weight_sum));
            weightedExpected(indices) = weightedExpected(indices).*diagnostic.weight_sum;
            testCase.verifyLessThan(norm(output-weightedExpected)/norm(weightedExpected),2e-14);
            testCase.verifyEqual(max(diagnostic.coverage_count),uint8(3));
            testCase.verifyEqual(meta.internal_gap_bin_count,0);
            testCase.verifyLessThanOrEqual(max(diagnostic.weight_sum),1+2e-15);
        end
        function oneBandKeepsFourierSeriesCoefficientNormalization(testCase)
            fixture = consistentBands(1);
            [output,meta,diagnostic] = synthesizePeriodicBands(fixture.bands,fixture.period, ...
                EdgeGuardHz=0,OutputClass="double");
            expected = expectedOnOutput(fixture,meta,diagnostic);
            testCase.verifyLessThan(norm(output-expected)/norm(expected),2e-14);
            testCase.verifyGreaterThan(meta.output_fft_length,numel(fixture.bands.spectra{1}));
            testCase.verifyEqual(max(diagnostic.weight_sum),1,'AbsTol',1e-15);
        end
        function sortingCentersPreservesBandAssociation(testCase)
            fixture = consistentBands(3);
            order = [3 1 2];
            permuted = struct('spectra',{fixture.bands.spectra(order)}, ...
                'centerBins',fixture.bands.centerBins(order));
            output = synthesizePeriodicBands(permuted,fixture.period,OutputClass="double");
            baseline = synthesizePeriodicBands(fixture.bands,fixture.period,OutputClass="double");
            testCase.verifyLessThan(norm(output-baseline)/norm(baseline),1e-14);
        end
        function rejectsDisconnectedSupport(testCase)
            fixture = consistentBands(2);
            fixture.bands.centerBins(2) = fixture.bands.centerBins(1)+8192;
            testCase.verifyError(@() synthesizePeriodicBands(fixture.bands,fixture.period), ...
                'stitch:DisconnectedSupport');
        end
        function rejectsThreeWayOverlap(testCase)
            fixture = consistentBands(3);
            fixture.bands.centerBins = 8192+[0 512 1024];
            testCase.verifyError(@() synthesizePeriodicBands(fixture.bands,fixture.period), ...
                'stitch:TripleOverlap');
        end
    end
end

function fixture = consistentBands(bandCount,centerStep)
% All bands sample the exact same synthetic periodic RF Fourier series.
if nargin<2
    centerStep = 2048;
end
inputCount = 4096;
period = inputCount/120e6;
centers = 8192+(0:bandCount-1)*centerStep;
firstGlobalBin = centers(1)-inputCount/2;
lastGlobalBin = centers(end)+inputCount/2-1;
stream = RandStream('mt19937ar','Seed',20261024);
count = lastGlobalBin-firstGlobalBin+1;
source = (randn(stream,count,1)+1i*randn(stream,count,1))/sqrt(inputCount);
spectra = cell(1,bandCount);
for bandIndex=1:bandCount
    globalBins = centers(bandIndex)+(-inputCount/2:inputCount/2-1).';
    spectra{bandIndex} = source(globalBins-firstGlobalBin+1);
end
fixture = struct('bands',struct('spectra',{spectra},'centerBins',centers), ...
    'period',period,'firstGlobalBin',firstGlobalBin,'source',source);
end

function expected = expectedOnOutput(fixture,meta,diagnostic)
expected = complex(zeros(meta.output_fft_length,1));
positiveBin = (0:numel(diagnostic.weight_sum)-1).';
globalBin = positiveBin+diagnostic.first_global_bin;
covered = diagnostic.coverage_count>0;
sourceIndex = globalBin(covered)-fixture.firstGlobalBin+1;
outputIndex = positiveBin(covered)+meta.output_fft_length/2+1;
expected(outputIndex) = fixture.source(sourceIndex);
end
