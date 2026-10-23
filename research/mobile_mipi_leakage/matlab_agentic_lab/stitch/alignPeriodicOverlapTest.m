classdef alignPeriodicOverlapTest < matlab.unittest.TestCase
    %ALIGNPERIODICOVERLAPTEST Synthetic tests; no real phone IQ or MATLAB UI reset.
    % Run: results = runtests('alignPeriodicOverlapTest.m');
    properties (TestParameter)
        delaySamples = struct('positive',7.25,'negative',-11.4, ...
            'zero',0,'nearPositiveWrap',2047.7,'nearNegativeWrap',-2047.6);
    end
    methods (Test)
        function recoversFractionalDelayAndGlobalPhase(testCase,delaySamples)
            fixture = makeFixture(delaySamples,0.73,1.6,8192,10240);
            [actual,alignedTrain,alignedTest] = alignPeriodicOverlap(fixture.args{:});
            periodicError = mod(actual.delay_samples-delaySamples+2048,4096)-2048;
            phaseError = angle(exp(1i*(actual.phase_rad-0.73)));
            testCase.verifyLessThan(abs(periodicError),2e-5);
            testCase.verifyLessThan(abs(phaseError),4e-4);
            testCase.verifyEqual(actual.positive_ls_gain,1/1.6,'AbsTol',1e-8);
            testCase.verifyLessThan(actual.test_positive_ls_gain.normalized_complex_error,2e-4);
            testCase.verifyEqual(actual.test_unit_gain.normalized_complex_error,0.6,'AbsTol',2e-6);
            testCase.verifyGreaterThan(actual.test_unit_gain.complex_coherence,0.999999);
            testCase.verifyLessThan(norm(alignedTrain-fixture.expectedTrain)/norm(fixture.expectedTrain),3e-4);
            testCase.verifyLessThan(norm(alignedTest-fixture.expectedTest)/norm(fixture.expectedTest),3e-4);
            testCase.verifyFalse(actual.test_parameters_refitted);
            testCase.verifyGreaterThan(actual.effective_bin_count,500);
            testCase.verifyGreaterThan(actual.energy_90_percent_span_fraction,0.7);
        end
        function handlesNegativeGlobalFrequencyBins(testCase)
            fixture = makeFixture(-23.375,-1.12,1,-10240,-8192);
            actual = alignPeriodicOverlap(fixture.args{:});
            testCase.verifyEqual(actual.delay_samples,-23.375,'AbsTol',2e-5);
            testCase.verifyLessThan(abs(angle(exp(1i*(actual.phase_rad+1.12)))),4e-4);
            testCase.verifyLessThan(actual.test_unit_gain.normalized_complex_error,2e-4);
        end
        function heldoutPhaseErrorIsNotRefitted(testCase)
            fixture = makeFixture(4.375,-0.82,1,8192,10240);
            fixture.args{4} = fixture.args{4}*exp(1i*0.4);
            actual = alignPeriodicOverlap(fixture.args{:});
            testCase.verifyLessThan(actual.train_unit_gain.normalized_complex_error,2e-4);
            testCase.verifyEqual(actual.test_unit_gain.normalized_complex_error,2*sin(0.2),'AbsTol',2e-4);
            testCase.verifyEqual(actual.test_unit_gain.residual_cross_phase_rad,0.4,'AbsTol',2e-4);
            testCase.verifyGreaterThan(actual.test_unit_gain.complex_coherence,0.999999);
            testCase.verifyFalse(actual.test_parameters_refitted);
        end
        function flagsSingleToneDelayAmbiguity(testCase)
            sampleCount = 4096;
            period = sampleCount/120e6;
            a = complex(zeros(sampleCount,1));
            b = a;
            globalBin = 9001;
            a(globalBin-(8192-sampleCount/2)+1) = 1;
            b(globalBin-(10240-sampleCount/2)+1) = exp(1i*0.31-1i*2*pi*globalBin*8.3/sampleCount);
            actual = alignPeriodicOverlap(a,b,a,b,8192,10240,period,120e6);
            testCase.verifyEqual(actual.effective_bin_count,1,'AbsTol',1e-12);
            testCase.verifyEqual(actual.second_peak_ratio,1,'AbsTol',1e-10);
            testCase.verifyTrue(actual.low_spectral_diversity);
            testCase.verifyTrue(actual.competing_periodic_peak);
            testCase.verifyEqual(actual.status,'ambiguous_periodic_estimate');
        end
        function rejectsNonoverlappingBands(testCase)
            fixture = makeFixture(0,0,1,8192,10240);
            fixture.args{6} = 16384;
            testCase.verifyError(@() alignPeriodicOverlap(fixture.args{:}),'stitch:NoUsableOverlap');
        end
        function rejectsNoSharedEnergy(testCase)
            fixture = makeFixture(0,0,1,8192,10240);
            fixture.args{2}(:) = 0;
            testCase.verifyError(@() alignPeriodicOverlap(fixture.args{:}),'stitch:NoSharedEnergy');
        end
        function rejectsOddLength(testCase)
            data = ones(4095,1);
            testCase.verifyError(@() alignPeriodicOverlap(data,data,data,data, ...
                0,1000,4095/120e6,120e6),'stitch:EvenFftRequired');
        end
    end
end

function fixture = makeFixture(delaySamples,phaseRad,gain,centerA,centerB)
% Independent training/test source Fourier coefficients, same known channel.
% These are synthetic coefficients of periodic complex signals, with FFT/N
% normalization. A and B select overlapping portions of one RF spectrum.
sampleCount = 4096;
period = sampleCount/120e6;
localBins = (-sampleCount/2:sampleCount/2-1).';
binsA = localBins+centerA;
binsB = localBins+centerB;
firstBin = min(binsA(1),binsB(1));
lastBin = max(binsA(end),binsB(end));
count = lastBin-firstBin+1;
stream = RandStream('mt19937ar','Seed',20261023);
sourceTrain = (randn(stream,count,1)+1i*randn(stream,count,1))/sqrt(sampleCount);
sourceTest = (randn(stream,count,1)+1i*randn(stream,count,1))/sqrt(sampleCount);
indexA = binsA-firstBin+1;
indexB = binsB-firstBin+1;
channel = gain*exp(1i*phaseRad-1i*(2*pi/sampleCount)*binsB*delaySamples);
aTrain = sourceTrain(indexA);
bTrain = sourceTrain(indexB).*channel;
aTest = sourceTest(indexA);
bTest = sourceTest(indexB).*channel;
fixture = struct();
fixture.args = {aTrain,bTrain,aTest,bTest,centerA,centerB,period,120e6};
fixture.expectedTrain = gain*sourceTrain(indexB);
fixture.expectedTest = gain*sourceTest(indexB);
end
