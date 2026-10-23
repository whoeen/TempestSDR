function result = estimateStitchFrameModel(centersMHz,outputDirectory)
%ESTIMATESTITCHFRAMEMODEL Estimate per-band frame period without holdout fitting.
%   Complex circular cross-correlation against frame zero determines a coarse
%   lag within +/-64 samples. Fractional lag maximizes the coherent cross-
%   spectrum sum. Positive lag means sampling the current frame FORWARD.
%   A separate demeaned-AM cross-correlation is retained as a control.
%   Only frames 0:7 fit the linear period model. Frames 16:23 test prediction.
%   Correlation may track interference; this function does not identify DSI.
arguments
    centersMHz (1,:) double = 100:60:700
    outputDirectory (1,1) string = ""
end
assert(all(ismember(centersMHz,100:60:700)) && numel(unique(centersMHz))==numel(centersMHz), ...
    'stitch:BadCenters','Centers must be unique members of 100:60:700 MHz.');
assert(~isempty(centersMHz),'stitch:NoBands','Select at least one band.');
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
if strlength(outputDirectory)==0
    outputDirectory = fullfile(labRoot,'results','iphone6_stitch_20261023','timing_model');
end
assert(~isfolder(outputDirectory) && ~isfile(outputDirectory), ...
    'stitch:OutputExists','Refuse overwrite: %s',outputDirectory);
mkdir(outputDirectory);
fs = 124082800;
p0 = 2069100;
origin = 8192;
trainingFrames = (0:7).';
heldoutFrames = (16:23).';
frameIndices = [trainingFrames;heldoutFrames];
maxLag = 64;
lagGrid = (-maxLag:maxLag).';
lagIndices = mod(lagGrid,p0)+1;
% FFT bin frequencies in cycles/input sample; signed bins preserve the
% baseband continuous-time delay convention for negative frequencies.
frequency = (0:p0-1).'/p0;
frequency(frequency>=0.5) = frequency(frequency>=0.5)-1;
optimizer = optimset('Display','off','TolX',0.002,'MaxIter',16,'MaxFunEvals',18);
inventoryPath = fullfile(labRoot,'knowledge','stitching','iphone6_sweep_20261023','CAPTURE_INVENTORY.json');
inventory = jsondecode(fileread(inventoryPath));
result = struct('status','running','started_utc',utcNow(), ...
    'fs_hz',fs,'nominal_period_samples',p0,'origin_sample_zero_based',origin, ...
    'training_frame_indices',trainingFrames,'heldout_frame_indices',heldoutFrames, ...
    'lag_search_samples',[-maxLag maxLag], ...
    'positive_lag_convention','corr(curr,ref) positive lag d => compare curr[n+d] with ref[n]', ...
    'complex_objective','abs(sum(FFT(curr).*conj(FFT(ref)).*exp(+j*2*pi*k_signed*d/N))/N)', ...
    'complex_dc_removed',true,'am_mean_removed',true, ...
    'warning','Both AM and complex alignment can lock to clutter. Heldout samples are never used in fitting.', ...
    'correlation_boundary_note','Circular correlation of finite frame blocks; +/-64 sample wrap can affect up to 64/2069100 of products. No guard extrapolation is performed.', ...
    'bands',{{}});
writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
summaryRows = cell(numel(centersMHz),1);
for bandIndex=1:numel(centersMHz)
    fcMHz = centersMHz(bandIndex);
    fprintf('Timing model %d/%d fc=%d MHz\n',bandIndex,numel(centersMHz),fcMHz);
    bandDirectory = fullfile(outputDirectory,sprintf('fc%03dMHz',fcMHz));
    mkdir(bandDirectory);
    source = resolveIphoneSweepCapture(fcMHz);
    [reference,referenceInfo] = readRisIqBlock(source,origin,p0);
    referenceMean = mean(reference,'double');
    referenceRawPower = sum(abs(reference).^2,'double');
    reference = reference-single(referenceMean);
    referencePower = sum(abs(reference).^2,'double');
    referenceSpectrum = fft(reference);
    referenceAm = abs(reference);
    referenceAm = referenceAm-single(mean(referenceAm,'double'));
    referenceAmPower = sum(referenceAm.^2,'double');
    referenceAmSpectrum = fft(referenceAm);
    clear reference referenceAm
    frames = cell(numel(frameIndices),1);
    for frameNumber=1:numel(frameIndices)
        frameIndex = frameIndices(frameNumber);
        isTraining = frameIndex<=trainingFrames(end);
        if frameIndex==0
            delay = 0; phase = 0; coherence = 1; amDelay = 0; amCoherence = 1;
            coarse = 0; frac = 0; boundary = false; amBoundary = false;
            optimizerExitFlag = 1; optimizerEvaluations = 0;
            currentPower = referencePower; currentMean = referenceMean; currentRawPower = referenceRawPower;
            secondBest = NaN;
        else
            firstSample = origin+frameIndex*p0;
            current = readRisIqBlock(source,firstSample,p0);
            currentMean = mean(current,'double');
            currentRawPower = sum(abs(current).^2,'double');
            current = current-single(referenceMean);
            currentPower = sum(abs(current).^2,'double');
            currentSpectrum = fft(current);
            crossSpectrum = currentSpectrum.*conj(referenceSpectrum);
            clear currentSpectrum
            crossCorrelation = ifft(crossSpectrum);
            normalizer = sqrt(referencePower*currentPower);
            candidates = abs(crossCorrelation(lagIndices))/max(normalizer,eps);
            [~,bestIndex] = max(candidates);
            coarse = lagGrid(bestIndex);
            sortedScores = sort(candidates,'descend');
            secondBest = double(sortedScores(min(2,numel(sortedScores))));
            boundary = abs(coarse)==maxLag;
            clear crossCorrelation candidates sortedScores
            % Pre-rotate by the integer lag; optimize only a bounded fraction.
            % Single FFT/phasor arrays and double reduction keep RAM bounded.
            crossSpectrum = crossSpectrum.*unitPhasor(2*pi*frequency*coarse);
            lower = max(-1,-maxLag-coarse);
            upper = min(1,maxLag-coarse);
            objective = @(delta) -abs(correlationAtFraction(crossSpectrum,frequency,delta,p0))/max(normalizer,eps);
            [frac,~,optimizerExitFlag,optimizerOutput] = fminbnd(objective,lower,upper,optimizer);
            optimizerEvaluations = optimizerOutput.funcCount;
            alignedCorrelation = correlationAtFraction(crossSpectrum,frequency,frac,p0);
            delay = coarse+frac;
            phase = angle(alignedCorrelation);
            coherence = abs(alignedCorrelation)/max(normalizer,eps);
            clear objective crossSpectrum alignedCorrelation
            currentAm = abs(current);
            currentAm = currentAm-single(mean(currentAm,'double'));
            currentAmPower = sum(currentAm.^2,'double');
            clear current
            amCross = ifft(fft(currentAm).*conj(referenceAmSpectrum));
            clear currentAm
            amCandidates = real(amCross(lagIndices))/max(sqrt(referenceAmPower*currentAmPower),eps);
            [amCoherence,amPeakIndex] = max(amCandidates);
            amInteger = lagGrid(amPeakIndex);
            amBoundary = abs(amInteger)==maxLag;
            amDelay = refineCircularPeak(real(amCross),amInteger,p0);
            clear amCross amCandidates
        end
        frames{frameNumber} = struct('frame_index',frameIndex,'training',isTraining, ...
            'first_sample_zero_based',origin+frameIndex*p0, ...
            'complex_delay_samples',double(delay),'complex_phase_rad',double(phase), ...
            'complex_coherence',double(coherence),'am_delay_samples',double(amDelay), ...
            'am_coherence',double(amCoherence),'coarse_complex_lag_samples',coarse, ...
            'complex_fractional_correction_samples',double(frac), ...
            'complex_search_boundary',boundary,'am_search_boundary',amBoundary, ...
            'optimizer_exitflag',optimizerExitFlag,'optimizer_function_evaluations',optimizerEvaluations, ...
            'second_highest_integer_coherence',secondBest, ...
            'dc_power_fraction',abs(currentMean)^2/max(currentRawPower/p0,eps), ...
            'rms_complex_counts',sqrt(currentPower/p0));
        partialTable = struct2table(vertcat(frames{1:frameNumber}));
        writetable(partialTable,fullfile(bandDirectory,'per_frame.csv'));
        fprintf('  frame %2d, delay %+9.5f, complex coherence %.5f, AM lag %+9.5f\n', ...
            frameIndex,delay,coherence,amDelay);
    end
    frameTable = struct2table(vertcat(frames{:}));
    trainingMask = frameTable.training;
    complexFit = fitTrainingPeriod(frameTable.frame_index(trainingMask), ...
        frameTable.complex_delay_samples(trainingMask),p0);
    amFit = fitTrainingPeriod(frameTable.frame_index(trainingMask), ...
        frameTable.am_delay_samples(trainingMask),p0);
    frameTable.complex_predicted_delay_samples = complexFit.intercept_samples+ ...
        complexFit.slope_samples_per_frame*frameTable.frame_index;
    frameTable.am_predicted_delay_samples = amFit.intercept_samples+ ...
        amFit.slope_samples_per_frame*frameTable.frame_index;
    frameTable.complex_prediction_residual_samples = frameTable.complex_delay_samples- ...
        frameTable.complex_predicted_delay_samples;
    frameTable.am_prediction_residual_samples = frameTable.am_delay_samples-frameTable.am_predicted_delay_samples;
    heldoutMask = ~trainingMask;
    complexValidation = heldoutSummary(frameTable.complex_prediction_residual_samples(heldoutMask), ...
        frameTable.complex_coherence(heldoutMask));
    amValidation = heldoutSummary(frameTable.am_prediction_residual_samples(heldoutMask), ...
        frameTable.am_coherence(heldoutMask));
    identityIndex = find([inventory.captures.fc_mhz]==fcMHz,1);
    band = struct('fc_mhz',fcMHz,'source',source, ...
        'full_sha256',inventory.captures(identityIndex).full_sha256, ...
        'reference_read_info',referenceInfo,'fs_hz',fs, ...
        'nominal_period_samples',p0,'origin_sample_zero_based',origin, ...
        'complex_period_samples',complexFit.period_samples, ...
        'am_period_samples',amFit.period_samples, ...
        'complex_fit_slope_samples_per_frame',complexFit.slope_samples_per_frame, ...
        'am_fit_slope_samples_per_frame',amFit.slope_samples_per_frame, ...
        'lag_fit_intercept_samples',complexFit.intercept_samples, ...
        'am_lag_fit_intercept_samples',amFit.intercept_samples, ...
        'training_frame_indices',trainingFrames,'heldout_frame_indices',heldoutFrames, ...
        'complex_fit',complexFit,'am_fit',amFit, ...
        'complex_heldout',complexValidation,'am_heldout',amValidation, ...
        'perframe',table2struct(frameTable),'completed_utc',utcNow());
    writetable(frameTable,fullfile(bandDirectory,'per_frame.csv'));
    writeJsonFile(fullfile(bandDirectory,'model.json'),band);
    writeJsonFile(fullfile(outputDirectory,sprintf('fc%dMHz.json',fcMHz)),band);
    result.bands{bandIndex} = band;
    summaryRows{bandIndex} = struct('fc_mhz',fcMHz, ...
        'complex_period_samples',band.complex_period_samples,'am_period_samples',band.am_period_samples, ...
        'complex_fit_slope_samples_per_frame',complexFit.slope_samples_per_frame, ...
        'complex_slope_standard_error',complexFit.slope_standard_error, ...
        'complex_training_residual_rms',complexFit.residual_rms_samples, ...
        'complex_heldout_residual_rms',complexValidation.residual_rms_samples, ...
        'complex_heldout_mean_coherence',complexValidation.mean_coherence, ...
        'am_training_residual_rms',amFit.residual_rms_samples, ...
        'am_heldout_residual_rms',amValidation.residual_rms_samples, ...
        'am_heldout_mean_coherence',amValidation.mean_coherence);
    writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
    writetable(struct2table(vertcat(summaryRows{1:bandIndex})),fullfile(outputDirectory,'overview.csv'));
    clear referenceSpectrum referenceAmSpectrum frames frameTable partialTable band
end
result.status = 'complete';
result.completed_utc = utcNow();
result.summary = vertcat(summaryRows{:});
writeJsonFile(fullfile(outputDirectory,'overview.json'),result);
end

function value = correlationAtFraction(crossSpectrum,frequency,delta,n)
value = sum(crossSpectrum.*unitPhasor(2*pi*frequency*delta),'double')/n;
end

function phasor = unitPhasor(theta)
phasor = complex(single(cos(theta)),single(sin(theta)));
end

function lag = refineCircularPeak(ac,integerLag,n)
indices = mod(integerLag+[-1 0 1],n)+1;
values = double(ac(indices));
denominator = values(1)-2*values(2)+values(3);
lag = integerLag;
if abs(denominator)>eps
    lag = lag+max(-0.5,min(0.5,0.5*(values(1)-values(3))/denominator));
end
end

function model = fitTrainingPeriod(indices,delays,p0)
x = [ones(numel(indices),1),double(indices(:))];
y = double(delays(:));
coefficients = x\y;
residual = y-x*coefficients;
dof = numel(y)-2;
sigma2 = sum(residual.^2)/dof;
covariance = sigma2*((x.'*x)\eye(2));
standardErrors = sqrt(diag(covariance));
% Two-sided Student t(.975,6); eight fixed training frames, two fitted terms.
assert(dof==6,'stitch:UnexpectedFitDOF','Expected 8 training observations.');
tCritical = 2.446911851;
period = p0+coefficients(2);
model = struct('period_samples',period,'intercept_samples',coefficients(1), ...
    'slope_samples_per_frame',coefficients(2),'slope_standard_error',standardErrors(2), ...
    'intercept_standard_error',standardErrors(1),'degrees_of_freedom',dof, ...
    'period_ci95_samples',period+tCritical*standardErrors(2)*[-1 1], ...
    'residual_rms_samples',sqrt(mean(residual.^2)), ...
    'residual_max_abs_samples',max(abs(residual)), ...
    'residual_samples',residual,'training_frame_indices',indices, ...
    'uncertainty_note','OLS t interval assumes independent equal-variance lag errors and a linear model. Frame correlation/peak aliases can invalidate this interpretation; heldout residuals are reported separately.');
end

function validation = heldoutSummary(residual,coherence)
validation = struct('residual_rms_samples',sqrt(mean(residual.^2)), ...
    'residual_mean_samples',mean(residual),'residual_max_abs_samples',max(abs(residual)), ...
    'mean_coherence',mean(coherence),'minimum_coherence',min(coherence), ...
    'fitted_to_heldout',false);
end

function stamp = utcNow()
stamp = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end
