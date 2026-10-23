classdef resamplePeriodicAmTest < matlab.unittest.TestCase
    %RESAMPLEPERIODICAMTEST Analytic controls for explicit anti-alias reduction.
    methods (Test)
        function preservesDcAmplitude(testCase)
            input = 3.7*ones(1024,1);
            [output,meta] = resamplePeriodicAm(input,128,PeriodSeconds=1/60);
            testCase.verifyEqual(output,3.7*ones(128,1),'AbsTol',2e-14);
            testCase.verifyTrue(meta.anti_alias_filter_applied);
            testCase.verifyEqual(meta.output_rate_hz,7680,'AbsTol',1e-10);
        end
        function preservesLowToneGainAndTimePhase(testCase)
            n = (0:1023).';
            m = (0:127).';
            input = 2+0.4*cos(2*pi*13*n/1024+0.73);
            expected = 2+0.4*cos(2*pi*13*m/128+0.73);
            output = resamplePeriodicAm(input,128);
            testCase.verifyEqual(output,expected,'AbsTol',2e-13);
        end
        function rejectsOutOfBandToneWithoutAliasing(testCase)
            n = (0:1023).';
            input = 2+0.4*cos(2*pi*100*n/1024-0.31);
            output = resamplePeriodicAm(input,128);
            testCase.verifyEqual(output,2*ones(128,1),'AbsTol',2e-13);
        end
        function appliesSpecifiedRaisedCosineGain(testCase)
            n = (0:1023).';
            m = (0:127).';
            gain = 0.5*(1+cos(pi*(60-0.9*64)/(64-0.9*64)));
            input = 2+0.4*cos(2*pi*60*n/1024+0.24);
            expected = 2+gain*0.4*cos(2*pi*60*m/128+0.24);
            output = resamplePeriodicAm(input,128);
            testCase.verifyEqual(output,expected,'AbsTol',3e-13);
        end
        function rejectsTargetNyquistExactly(testCase)
            n = (0:1023).';
            input = 2+0.4*cos(2*pi*64*n/1024);
            [output,meta] = resamplePeriodicAm(input,128);
            testCase.verifyEqual(output,2*ones(128,1),'AbsTol',2e-13);
            testCase.verifyTrue(meta.nyquist_coefficient_zero);
        end
        function handlesEvenNonPowerOfTwoLengths(testCase)
            n = (0:999).';
            m = (0:125).';
            input = 1+0.3*sin(2*pi*17*n/1000-0.5);
            expected = 1+0.3*sin(2*pi*17*m/126-0.5);
            output = resamplePeriodicAm(input,126);
            testCase.verifyEqual(output,expected,'AbsTol',3e-13);
        end
        function preservesSinglePrecisionRowOrientation(testCase)
            input = single(1+0.2*cos(2*pi*7*(0:1023)/1024));
            expected = single(1+0.2*cos(2*pi*7*(0:127)/128));
            output = resamplePeriodicAm(input,128);
            testCase.verifyClass(output,'single');
            testCase.verifySize(output,[1 128]);
            testCase.verifyEqual(output,expected,'AbsTol',single(3e-6));
        end
        function zeroInputHasFiniteImaginaryDiagnostic(testCase)
            [output,meta] = resamplePeriodicAm(single(zeros(1024,1)),128);
            testCase.verifyEqual(output,single(zeros(128,1)),'AbsTol',single(0));
            testCase.verifyEqual(meta.imaginary_relative_rms_before_real_projection,0,'AbsTol',0);
        end
        function rejectsOddOutput(testCase)
            testCase.verifyError(@() resamplePeriodicAm(ones(1024,1),127), ...
                'stitch:EvenResamplingLengths');
        end
        function rejectsOddInput(testCase)
            testCase.verifyError(@() resamplePeriodicAm(ones(1023,1),128), ...
                'stitch:EvenResamplingLengths');
        end
    end
end
