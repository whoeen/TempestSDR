function report = auditLinkwitzRileyFiniteIir(options)
%AUDITLINKWITZRILEYFINITEIIR Execute explicit SOS forward/backward LR controls.
%   Uses base MATLAB FILTER with two real Butterworth biquads per branch.
%   It is a custom zero-state forward/reverse algorithm, NOT FILTFILT, and
%   does not reproduce any library's endpoint extension/initial-state policy.
%   All comparisons use the same prepared complex input. No RF alignment or
%   additional screen reconstruction is estimated by this audit.
%   Preflight: matlab-design-digital-filter references/INDEX.md and
%   references/quick-ref/general-iir-fir.md. Mode: offline; phase: zero phase
%   only in the periodic steady-state limit. Fs is explicit throughout.
arguments
    options.IncludeMeasured (1,1) logical = true
    options.OutputFolder (1,1) string = ""
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
out = options.OutputFolder;
if strlength(out)==0
    out = fullfile(labRoot,'results','iphone6_followup_20261024','lr_finite_iir');
end
assert(~isfolder(out) && ~isfile(out),'lrAudit:Exists','Refuse overwrite: %s',out);
fs = 360e6; crossover = 90e6; n = 8192;
guards = [0 1 2 4 8 16 32 64 128 256];
edgeWidth = 128;
[sosLow,sosHigh,qValues] = butterworthFourBiquads(fs,crossover);
frequencyHz = linspace(0,fs/2,4097).';
hLow = sosResponse(sosLow,frequencyHz,fs);
hHigh = sosResponse(sosHigh,frequencyHz,fs);
lowResponse = abs(hLow).^2;
highResponse = abs(hHigh).^2;
lowAnalytic = analyticLow(frequencyHz,crossover,fs);
crossLow = abs(sosResponse(sosLow,crossover,fs)).^2;
crossHigh = abs(sosResponse(sosHigh,crossover,fs)).^2;
poleRadii = zeros(4,1);
for section=1:2
    poleRadii(2*section-1:2*section) = abs(roots(sosLow(section,4:6)));
end
responseChecks = struct('maximum_low_plus_high_minus_one',max(abs(lowResponse+highResponse-1)), ...
    'maximum_low_response_vs_analytic_error',max(abs(lowResponse-lowAnalytic)), ...
    'maximum_high_response_vs_analytic_error',max(abs(highResponse-(1-lowAnalytic))), ...
    'low_zero_phase_amplitude_at_crossover',crossLow, ...
    'high_zero_phase_amplitude_at_crossover',crossHigh, ...
    'causal_low_amplitude_at_crossover',abs(sosResponse(sosLow,crossover,fs)), ...
    'maximum_pole_radius',max(poleRadii), ...
    'unity_tolerance',1e-12,'response_tolerance',1e-12,'periodic_relative_rms_tolerance',1e-10);
responseChecks.passed = responseChecks.maximum_low_plus_high_minus_one<1e-12 && ...
    responseChecks.maximum_low_response_vs_analytic_error<1e-12 && ...
    responseChecks.maximum_high_response_vs_analytic_error<1e-12 && ...
    abs(crossLow-.5)<1e-12 && abs(crossHigh-.5)<1e-12 && max(poleRadii)<1;

% Keep the caller's random stream unchanged.
previousRng = rng; rngCleanup = onCleanup(@() rng(previousRng)); %#ok<NASGU>
rng(604241,'twister');
t = (0:n-1).'/fs;
xRandom = complex(randn(n,1),randn(n,1))/sqrt(2);
xPeriodic = xRandom + .4 + .7*exp(1i*(2*pi*(fs/4)*t+.31)) ...
    + .3*exp(1i*(2*pi*(37*fs/n)*t-.42));
% An explicit discontinuity makes the consequence of a periodic seam visible.
xSeam = (.5+1.4*(0:n-1).'/n).*exp(1i*2*pi*(fs*.137)*t);
xSeam(end-63:end) = xSeam(end-63:end)*exp(1i*1.4)+.8;
inputs = {xPeriodic,xSeam};
labels = ["synthetic_broadband_periodic_extension","synthetic_nonperiodic_seam"];
inputMetadata = {struct('kind','synthetic complex broadband plus on-bin tones', ...
    'periodic_interpretation','DFT represents exact repetition of this generated block'), ...
    struct('kind','synthetic nonperiodic tone/ramp with endpoint phase and level change', ...
    'periodic_interpretation','FFT wraps the two endpoints; no physical periodicity is assumed')};
measuredStatus = struct('requested',options.IncludeMeasured,'included',false,'reason','not requested');
if options.IncludeMeasured
    templatePath = fullfile(labRoot,'results','iphone6_stitch_20261023','templates','fc100MHz','templates.mat');
    if isfile(templatePath)
        measured = load(templatePath,'singleTrain','meta');
        assert(isfield(measured,'singleTrain') && isfield(measured,'meta'), ...
            'lrAudit:TemplateFields','Expected singleTrain and meta fields.');
        assert(isfield(measured.meta,'period_seconds') && measured.meta.period_seconds>0, ...
            'lrAudit:TemplatePeriod','Missing positive template period.');
        native = double(measured.singleTrain(:));
        fsNative = numel(native)/measured.meta.period_seconds;
        assert(fsNative<fs,'lrAudit:Interpolation','This bounded control only upsamples its measured template.');
        sourceStartZero = 128;
        positions = sourceStartZero+(0:n-1).'*fsNative/fs;
        interpolated = localWindowedSinc(native,positions,32);
        % Pair100/160MHz analytic coordinates use RF40MHz as the origin;
        % the100MHz template therefore has internal center60MHz.
        measuredInput = interpolated.*exp(1i*2*pi*60e6*t);
        inputs{end+1} = measuredInput;
        labels(end+1) = "measured_fc100_template_excerpt";
        inputMetadata{end+1} = struct('kind','measured one-frame conditioned template excerpt, not new raw acquisition', ...
            'source',templatePath,'variable','singleTrain','source_template_length',numel(native), ...
            'source_template_rate_hz',fsNative,'source_start_zero_based',sourceStartZero, ...
            'target_rate_hz',fs,'analytic_center_shift_hz',60e6, ...
            'resampler','65-tap centered windowed-sinc interpolation, Blackman support32, row-normalized DC gain', ...
            'resampler_caveat','Finite interpolator error is shared by both filters; this is not a resampler performance or RF stitching validation', ...
            'periodic_interpretation','Excerpt endpoints generally do not close; circular result is only a numerical periodic extension');
        measuredStatus = struct('requested',true,'included',true,'reason','bounded same-input filter comparison only');
    else
        measuredStatus.reason = 'fc100 singleTrain template absent; synthetic tests still run';
    end
end

caseReports = cell(numel(inputs),1);
caseArrays = cell(numel(inputs),1);
for caseIndex=1:numel(inputs)
    x = inputs{caseIndex};
    signedFrequencies = [0:n/2-1,-n/2:-1].'*fs/n;
    lowWeights = analyticLow(abs(signedFrequencies),crossover,fs);
    fftInput = fft(x);
    lowFft = ifft(fftInput.*lowWeights);
    highFft = ifft(fftInput.*(1-lowWeights));
    rows = struct([]);
    for guardIndex=1:numel(guards)
        guard = guards(guardIndex);
        lowIir = forwardBackwardPeriodicGuard(x,sosLow,guard);
        highIir = forwardBackwardPeriodicGuard(x,sosHigh,guard);
        edge = [1:edgeWidth,n-edgeWidth+1:n];
        interior = edgeWidth+1:n-edgeWidth;
        item = struct('periodic_guard_samples_each_end',guard, ...
            'guard_time_ns',guard/fs*1e9, ...
            'low_relative_rms_error',relativeError(lowIir,lowFft), ...
            'high_relative_rms_error',relativeError(highIir,highFft), ...
            'sum_relative_rms_error',relativeError(lowIir+highIir,x), ...
            'low_edge_relative_rms_error',relativeError(lowIir(edge),lowFft(edge)), ...
            'low_interior_relative_rms_error',relativeError(lowIir(interior),lowFft(interior)), ...
            'low_maximum_absolute_error',max(abs(lowIir-lowFft)), ...
            'high_maximum_absolute_error',max(abs(highIir-highFft)));
        if isempty(rows),rows=item;else,rows(end+1)=item;end %#ok<AGROW>
        if guard==0
            lowUnpadded = lowIir; highUnpadded = highIir;
        end
    end
    checks = struct('largest_guard_low_matches_fft',rows(end).low_relative_rms_error<1e-10, ...
        'largest_guard_high_matches_fft',rows(end).high_relative_rms_error<1e-10, ...
        'largest_guard_sum_matches_input',rows(end).sum_relative_rms_error<1e-10, ...
        'finite_boundary_difference_detected',rows(1).low_relative_rms_error>1e-8);
    caseReports{caseIndex} = struct('label',labels(caseIndex),'input',inputMetadata{caseIndex}, ...
        'samples',n,'duration_seconds',n/fs,'first_last_complex_difference',abs(x(1)-x(end)), ...
        'guard_convergence',rows,'checks',checks, ...
        'interpretation','Padded convergence establishes periodic steady-state numerical equivalence only; unpadded differences expose finite boundary-policy dependence');
    caseArrays{caseIndex} = struct('input',x,'low_fft',lowFft,'high_fft',highFft, ...
        'low_unpadded_custom_iir',lowUnpadded,'high_unpadded_custom_iir',highUnpadded, ...
        'low_periodic_guard_iir',lowIir,'high_periodic_guard_iir',highIir);
end
allCasesPassed = all(cellfun(@(s)all(structfun(@(v)logical(v),s.checks)),caseReports));
report = struct('status','complete','implementation','custom base MATLAB FILTER two-SOS cascade; forward then reverse/filter/reverse; zero states at each outer boundary', ...
    'is_matlab_filtfilt',false,'filter_rate_hz',fs,'crossover_hz',crossover, ...
    'butterworth_causal_order',4,'effective_forward_backward_lr_order',8, ...
    'q_values',qValues,'sos_columns','b0,b1,b2,a0,a1,a2', ...
    'sos_low',sosLow,'sos_high',sosHigh,'pole_radii',poleRadii, ...
    'coefficient_derivation','Bilinear prewarp K=tan(pi*fc/Fs); Butterworth Q=1/(2*cos(pi/8)),1/(2*cos(3*pi/8))', ...
    'response_checks',responseChecks,'measured_input',measuredStatus,'cases',{caseReports}, ...
    'all_numerical_checks_passed',responseChecks.passed && allCasesPassed, ...
    'new_rf_alignment_performed',false,'screen_reconstruction_claimed',false, ...
    'caveat','These results validate custom SOS execution and periodic equivalence. They do not validate physical frame-seam closure, multiband alignment, actual120MHz passbands, or library FILTFILT behavior.');
mkdir(out);
writeJsonFile(fullfile(out,'audit.json'),report);
writetable(table(frequencyHz,lowResponse,highResponse,lowAnalytic),fullfile(out,'frequency_response.csv'));
for caseIndex=1:numel(caseReports)
    caseReport = caseReports{caseIndex};
    writetable(struct2table(caseReport.guard_convergence),fullfile(out,labels(caseIndex)+"_guards.csv"));
    renderCase(caseArrays{caseIndex},caseReport,fs,edgeWidth,fullfile(out,labels(caseIndex)+".png"));
end
save(fullfile(out,'numerical_arrays.mat'),'caseArrays','caseReports','sosLow','sosHigh', ...
    'frequencyHz','lowResponse','highResponse','lowAnalytic','report','-v7');
f = figure('Visible','off','Position',[60 60 1050 420]);
tiledlayout(f,1,2);
ax=nexttile;plot(ax,frequencyHz/1e6,[lowResponse,highResponse,lowResponse+highResponse]);
xlabel(ax,'Frequency (MHz)');ylabel(ax,'Forward/backward amplitude');grid(ax,'on');
legend(ax,'Low','High','Low + high',Location='best');title(ax,'Explicit Butterworth4 SOS squared responses');
ax=nexttile;semilogy(ax,frequencyHz/1e6,max(abs(lowResponse-lowAnalytic),1e-18));
xlabel(ax,'Frequency (MHz)');ylabel(ax,'Absolute response error');grid(ax,'on');
title(ax,'SOS response versus analytic LR W8');
exportgraphics(f,fullfile(out,'response_verification.png'),Resolution=140);close(f);
assert(report.all_numerical_checks_passed,'lrAudit:NumericalCheck', ...
    'One or more checks failed; inspect saved audit.json before interpreting the result.');
end

function [low,high,q] = butterworthFourBiquads(fs,fc)
k=tan(pi*fc/fs);q=1./(2*cos([pi/8,3*pi/8]));
low=zeros(2,6);high=zeros(2,6);
for section=1:2
    normalization=1/(1+k/q(section)+k*k);
    denominator=[1,2*(k*k-1)*normalization,(1-k/q(section)+k*k)*normalization];
    low(section,:)=[k*k*[1 2 1]*normalization,denominator];
    high(section,:)=[[1 -2 1]*normalization,denominator];
end
end

function h = sosResponse(sos,frequencyHz,fs)
zInverse=exp(-1i*2*pi*frequencyHz(:)/fs);h=ones(size(zInverse));
for section=1:size(sos,1)
    b=sos(section,1:3);a=sos(section,4:6);
    h=h.*(b(1)+b(2)*zInverse+b(3)*zInverse.^2)./(a(1)+a(2)*zInverse+a(3)*zInverse.^2);
end
end

function y = causalCascade(x,sos)
y=x;
for section=1:size(sos,1)
    y=filter(sos(section,1:3),sos(section,4:6),y);
end
end

function y = forwardBackwardPeriodicGuard(x,sos,guard)
n=numel(x);indices=mod((-guard:n+guard-1).',n)+1;
extended=x(indices);
forward=causalCascade(extended,sos);
backward=flipud(causalCascade(flipud(forward),sos));
y=backward(guard+1:guard+n);
end

function low = analyticLow(f,fc,fs)
ratio=abs(tan(pi*f/fs))/tan(pi*fc/fs);
low=1./(1+ratio.^8);low(f<=0)=1;low(f>=fs/2)=0;
end

function value = relativeError(a,reference)
value=norm(a-reference)/max(norm(reference),eps);
end

function y = localWindowedSinc(x,positions,halfWidth)
base=floor(positions);indices=base+(-halfWidth:halfWidth);
assert(all(indices(:)>=0 & indices(:)<numel(x)), 'lrAudit:InterpolationBounds','Measured excerpt support exceeds template.');
delta=positions-indices;
weights=ones(size(delta));nonzero=delta~=0;
weights(nonzero)=sin(pi*delta(nonzero))./(pi*delta(nonzero));
window=.42+.5*cos(pi*delta/halfWidth)+.08*cos(2*pi*delta/halfWidth);
window(abs(delta)>halfWidth)=0;
weights=weights.*window;weights=weights./sum(weights,2);
y=sum(x(indices+1).*weights,2);
end

function renderCase(arrays,caseReport,fs,edgeWidth,path)
n=numel(arrays.input);first=(1:edgeWidth).';last=(n-edgeWidth+1:n).';
f=figure('Visible','off','Position',[50 50 1150 760]);tiledlayout(f,2,2);
ax=nexttile;plot(ax,(first-1)/fs*1e9,real([arrays.low_fft(first),arrays.low_unpadded_custom_iir(first),arrays.low_periodic_guard_iir(first)]));
xlabel(ax,'Time from excerpt start (ns)');ylabel(ax,'Real lowpass output');grid(ax,'on');
legend(ax,'Periodic FFT','Unpadded custom IIR','Periodic-guard custom IIR',Location='best');title(ax,'First boundary');
ax=nexttile;plot(ax,(last-n)/fs*1e9,real([arrays.low_fft(last),arrays.low_unpadded_custom_iir(last),arrays.low_periodic_guard_iir(last)]));
xlabel(ax,'Time relative to last sample (ns)');ylabel(ax,'Real lowpass output');grid(ax,'on');title(ax,'Last boundary');
ax=nexttile;semilogy(ax,(first-1)/fs*1e9,max(abs(arrays.low_unpadded_custom_iir(first)-arrays.low_fft(first)),1e-18));
xlabel(ax,'Time from excerpt start (ns)');ylabel(ax,'Absolute complex difference');grid(ax,'on');title(ax,'Finite boundary versus circular FFT');
rows=caseReport.guard_convergence;
ax=nexttile;semilogy(ax,[rows.periodic_guard_samples_each_end],[rows.low_relative_rms_error;rows.high_relative_rms_error;rows.sum_relative_rms_error].');
xlabel(ax,'Periodic guard samples at each end');ylabel(ax,'Relative RMS error');grid(ax,'on');
legend(ax,'Low vs FFT','High vs FFT','Low + high vs input',Location='best');title(ax,'Periodic padding convergence');
sgtitle(f,strrep(caseReport.label,'_',' '));exportgraphics(f,path,Resolution=140);close(f);
end
