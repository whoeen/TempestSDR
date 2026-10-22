function report = verifyStitchConventions()
%VERIFYSTITCHCONVENTIONS Audit Chapter 5 signs using synthetic complex data.
% No hardware or smartphone IQ is read. Uses base MATLAB only.
    sampleCount = 1024;
    randomStream = RandStream("mt19937ar", Seed=20261022);
    reference = complex(zeros(sampleCount, 1));
    reference(257:768) = randn(randomStream, 512, 1) + 1i*randn(randomStream, 512, 1);
    delays = [7, -11, 0];
    phases = [0.6, -0.9, 1.1];
    cases = repmat(struct(), numel(delays), 1);
    fftLength = 2^nextpow2(2*sampleCount - 1);
    lags = (-(sampleCount-1):(sampleCount-1)).';
    for caseIndex = 1:numel(delays)
        measured = shiftFinite(reference, delays(caseIndex))*exp(1i*phases(caseIndex));
        circular = ifft(fft(measured, fftLength).*conj(fft(reference, fftLength)));
        correlation = [circular(end-sampleCount+2:end); circular(1:sampleCount)];
        [~, peakIndex] = max(abs(correlation));
        delayEstimate = lags(peakIndex);
        phaseEstimate = angle(correlation(peakIndex));
        aligned = shiftFinite(measured, -delayEstimate)*exp(-1i*phaseEstimate);
        printedCorrection = shiftFinite(measured, delayEstimate)*exp(-1i*phaseEstimate);
        shifted = shiftFinite(measured, -delayEstimate);
        definitionAtPeak = sum(reference.*conj(shifted));
        relativeError = norm(aligned-reference)/norm(reference);
        cases(caseIndex).trueDelaySamples = delays(caseIndex);
        cases(caseIndex).estimatedDelaySamples = delayEstimate;
        cases(caseIndex).truePhaseRad = phases(caseIndex);
        cases(caseIndex).fftPeakPhaseRad = phaseEstimate;
        cases(caseIndex).definition514PeakPhaseRad = angle(definitionAtPeak);
        cases(caseIndex).correctedRelativeError = relativeError;
        cases(caseIndex).printed517Then520Error = norm(printedCorrection-reference)/norm(reference);
        assert(delayEstimate == delays(caseIndex), "Lag estimate failed.");
        assert(relativeError < 1e-12, "Consistent alignment failed.");
        assert(abs(definitionAtPeak-conj(correlation(peakIndex))) < 1e-9, "Conjugate relation failed.");
    end
    angularFrequency = linspace(0, pi, 4097);
    inverseZ = exp(-1i*angularFrequency);
    denominator = (2+sqrt(2)) + (2-sqrt(2))*inverseZ.^2;
    lowResponse = (1+inverseZ).^2./denominator;
    highResponse = (1-inverseZ).^2./denominator;
    complementError = max(abs(abs(lowResponse).^2 + abs(highResponse).^2 - 1));
    assert(complementError < 1e-12, "Zero-phase complement identity failed.");
    report = struct("status", "passed", "dataKind", "synthetic", ...
        "matlabVersion", version, "cases", cases, ...
        "zeroPhaseComplementMaxError", complementError, ...
        "scope", "Algebra audit only; no full stitching or smartphone performance validation.");
end

function shifted = shiftFinite(signal, delaySamples)
%SHIFTFINITE Return signal[n-delaySamples] with zero extension, never wrap.
    shifted = complex(zeros(size(signal)));
    sampleCount = numel(signal);
    if delaySamples >= 0
        shifted(delaySamples+1:end) = signal(1:sampleCount-delaySamples);
    else
        shifted(1:sampleCount+delaySamples) = signal(1-delaySamples:end);
    end
end
