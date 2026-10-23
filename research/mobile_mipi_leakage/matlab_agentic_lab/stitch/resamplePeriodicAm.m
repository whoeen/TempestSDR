function [resampled,meta] = resamplePeriodicAm(amplitude,outputSamples,options)
%RESAMPLEPERIODICAM Explicit anti-alias reduction of a real periodic AM vector.
%   Y=RESAMPLEPERIODICAM(X,M) preserves the period and t=0 origin while reducing
%   an even-length real vector to even M<=numel(X). Positive/negative Fourier
%   coefficients above the output Nyquist harmonic are discarded. The zero-
%   phase gain is one through 0.9*Nyquist, follows a raised cosine to zero at
%   Nyquist, and is zero beyond it. This is periodic offline filtering, so
%   boundary wrapping is part of the declared model.
%
%   Fourier-series coefficients are FFT(X)/Nin. Retained coefficients keep
%   that normalization; Y=real(IFFT(Cout))*M. No sample-rate-dependent gain or
%   fractional time shift is introduced. Tiny negative AM ringing is not
%   clipped; clipping would be a separate nonlinear display operation.
%
%   MATLAB R2026b interpft downsampling is NOT this operation: its installed
%   implementation increases interpolation length and then skips points,
%   without removing input energy above the requested output Nyquist.
arguments
    amplitude {mustBeFloat,mustBeVector,mustBeNonempty,mustBeFinite,mustBeReal}
    outputSamples (1,1) {mustBeNumeric,mustBeFinite,mustBeReal,mustBeInteger,mustBePositive}
    options.PassbandNyquistFraction (1,1) double {mustBeFinite,mustBeReal,mustBePositive} = 0.9
    options.PeriodSeconds (1,1) double {mustBeReal} = NaN
end
inputSamples = numel(amplitude);
outputSamples = double(outputSamples);
assert(mod(inputSamples,2)==0 && mod(outputSamples,2)==0 && outputSamples>=4, ...
    'stitch:EvenResamplingLengths','Input/output lengths must be even and output length at least four.');
assert(outputSamples<=inputSamples,'stitch:AmUpsamplingUnsupported', ...
    'This anti-alias helper supports outputSamples<=inputSamples.');
assert(options.PassbandNyquistFraction<1,'stitch:InvalidTransitionFraction', ...
    'PassbandNyquistFraction must be strictly between zero and one.');
assert(isnan(options.PeriodSeconds) || ...
    (isfinite(options.PeriodSeconds) && options.PeriodSeconds>0), ...
    'stitch:InvalidPeriod','PeriodSeconds must be positive finite or unspecified NaN.');
wasRow = isrow(amplitude);
inputClass = class(amplitude);
amplitude = amplitude(:);
nyquistHarmonic = outputSamples/2;
passbandHarmonic = options.PassbandNyquistFraction*nyquistHarmonic;
positiveHarmonics = (0:nyquistHarmonic-1).';
positiveGain = ones(nyquistHarmonic,1);
transition = positiveHarmonics>passbandHarmonic;
positiveGain(transition) = 0.5*(1+cos(pi* ...
    (positiveHarmonics(transition)-passbandHarmonic)/(nyquistHarmonic-passbandHarmonic)));
inputSpectrum = fft(amplitude);
outputCoefficients = complex(zeros(outputSamples,1,inputClass));
% Normalization is applied only to the retained bins, avoiding an additional
% full-size normalized copy for 2^25-sample synthesis outputs.
outputCoefficients(1:nyquistHarmonic) = ...
    (inputSpectrum(1:nyquistHarmonic)/inputSamples).*cast(positiveGain,inputClass);
% The Nyquist coefficient remains exactly zero. Copy the independently
% computed negative-frequency coefficients with the same real even gain.
outputCoefficients(nyquistHarmonic+2:end) = ...
    (inputSpectrum(inputSamples-nyquistHarmonic+2:end)/inputSamples).* ...
    cast(positiveGain(end:-1:2),inputClass);
clear inputSpectrum
periodicOutput = ifft(outputCoefficients);
realOutput = real(periodicOutput);
imaginaryRelativeRms = double(norm(imag(periodicOutput)))/max(double(norm(realOutput)),realmin);
resampled = realOutput*outputSamples;
if wasRow
    resampled = resampled.';
end
meta = struct();
meta.method = 'periodic Fourier-series truncation with explicit raised-cosine lowpass';
meta.input_samples = inputSamples;
meta.output_samples = outputSamples;
meta.output_over_input_rate = outputSamples/inputSamples;
meta.passband_nyquist_fraction = options.PassbandNyquistFraction;
meta.passband_last_harmonic = passbandHarmonic;
meta.stopband_first_harmonic = nyquistHarmonic;
meta.nyquist_coefficient_zero = true;
meta.anti_alias_filter_applied = true;
meta.phase_response = 'real even zero-phase frequency weights';
meta.time_origin = 'unchanged: input n/Nin and output m/Nout sample the same periodic coordinate';
meta.normalization = 'retained FFT(input)/Nin coefficients; ifft(outputCoefficients)*Nout';
meta.input_class = inputClass;
meta.output_class = class(resampled);
meta.periodic_boundary_assumption = true;
meta.negative_values_clipped = false;
meta.imaginary_relative_rms_before_real_projection = imaginaryRelativeRms;
meta.period_seconds = options.PeriodSeconds;
meta.input_rate_hz = inputSamples/options.PeriodSeconds;
meta.output_rate_hz = outputSamples/options.PeriodSeconds;
meta.passband_edge_hz = passbandHarmonic/options.PeriodSeconds;
meta.stopband_edge_hz = nyquistHarmonic/options.PeriodSeconds;
end
