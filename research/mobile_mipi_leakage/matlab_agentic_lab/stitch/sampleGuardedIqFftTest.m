function results = sampleGuardedIqFftTest()
%SAMPLEGUARDEDIQFFTTEST Check complex error against analytic bandlimited tones.
%   Synthetic validation only. No recorded smartphone signal or MATLAB session
%   state is cleared. This test does not establish accuracy for arbitrary raw
%   endpoint discontinuities or signal components at exactly Nyquist.
fs = 124082800;
n = 32768;
guard = 512;
frequencies = [-60 -55 -40 -20 -1 0 1 20 40 55 60]*1e6;
offsets = [0 .03125 .125 .249 .375 .5 .625 .875 .999];
integerPositions = (guard:17:n-guard-2).';
queries = integerPositions+offsets;
queries = queries(:);
rows = cell(2*numel(frequencies)+2,1);
row = 0;
for mode=1:2
    for tone=1:numel(frequencies)
        frequency = frequencies(tone);
        if mode==1
            % Integer DFT-bin tones remove the finite-period seam exactly.
            frequency = round(frequency*n/fs)*fs/n;
            useTaper = false;
            limit = 2e-3;
            label = 'periodic_bin_tone';
        else
            % Off-bin +/-60 MHz stresses finite block boundaries and guards.
            useTaper = true;
            limit = 3e-3;
            label = 'finite_offbin_tone';
        end
        phase = 0.231;
        x = single(exp(1i*(2*pi*(frequency/fs)*(0:n-1).'+phase)));
        [actual,diagnostic] = sampleGuardedIqFft(x,queries, ...
            GuardSamples=guard,TaperGuards=useTaper);
        expected = exp(1i*(2*pi*(frequency/fs)*queries+phase));
        error = double(actual)-expected;
        row = row+1;
        rows{row} = describeCase(label,frequency,error,actual,expected,limit);
        assert(diagnostic.oversampled_count==4*n,'stitch:TestGrid','Unexpected interpolation grid.');
    end
end
% Affine queries represent a 25 ppm timing-rate adjustment, not just one delay.
for frequency=[-60e6 60e6]
    q = guard+(0:n-2*guard-4).'*(1+25e-6)+0.375;
    x = exp(1i*(2*pi*(frequency/fs)*(0:n-1).'+0.731));
    [actual,~] = sampleGuardedIqFft(x,q,GuardSamples=guard);
    expected = exp(1i*(2*pi*(frequency/fs)*q+0.731));
    row = row+1;
    rows{row} = describeCase('finite_affine_25ppm',frequency, ...
        double(actual)-expected,actual,expected,3e-3);
end
summary = struct2table(vertcat(rows{1:row}));
% The guard contract must fail early instead of using a periodic wrap sample.
guardRejected = false;
try
    sampleGuardedIqFft(x,guard-0.01,GuardSamples=guard);
catch exception
    guardRejected = strcmp(exception.identifier,'stitch:InsufficientGuard');
end
% Integer-query samples should survive the FFT interpolation in the interior.
integerQuery = (guard:19:n-1-guard).';
integerActual = sampleGuardedIqFft(x,integerQuery,GuardSamples=guard);
integerError = max(abs(double(integerActual)-x(integerQuery+1)));
results = struct('status','synthetic verification executed', ...
    'fs_hz',fs,'raw_samples',n,'guard_samples',guard, ...
    'fractional_offsets',offsets,'cases',table2struct(summary), ...
    'maximum_complex_error',max(summary.max_complex_error), ...
    'integer_grid_max_complex_error',integerError, ...
    'integer_grid_tolerance',1e-5,'insufficient_guard_rejected',guardRejected, ...
    'passed',all(summary.passed) && guardRejected && integerError<1e-5, ...
    'interpretation','Error normalized to unit-amplitude complex tones; not an RF SNR or image-fidelity score.');
disp(summary);
fprintf('Maximum complex error %.6g, integer-grid error %.6g, guard rejection=%d\n', ...
    results.maximum_complex_error,integerError,guardRejected);
assert(results.passed,'stitch:FractionalInterpolationValidation', ...
    'Complex tone error or guard-contract validation failed; inspect returned metrics.');
end

function row = describeCase(label,frequency,error,actual,expected,limit)
row = struct('case_name',label,'frequency_hz',frequency, ...
    'max_complex_error',max(abs(error)),'rms_complex_error',sqrt(mean(abs(error).^2)), ...
    'max_magnitude_error',max(abs(abs(double(actual))-1)), ...
    'max_phase_error_rad',max(abs(angle(double(actual).*conj(expected)))), ...
    'complex_error_limit',limit,'passed',max(abs(error))<limit);
end
