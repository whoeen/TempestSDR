function [y, info] = conditionIq(x, fs, options)
%CONDITIONIQ Explicit experimental branches with logged transfer functions.
%   Defaults are identity. A strong spectral line alone does not authorize a
%   notch: it may carry the desired modulation. TRAINING must be independent
%   clutter/background data before AR whitening is scientifically justified.
arguments
    x (:,1) {mustBeNumeric}
    fs (1,1) double {mustBePositive}
    options.OffsetHz (1,1) double = 0
    options.Decimation (1,1) double {mustBeInteger,mustBePositive} = 1
    options.NotchHz (:,1) double = zeros(0,1)
    options.NotchWidthHz (1,1) double {mustBePositive} = 1000
    options.WhiteningOrder (1,1) double {mustBeInteger,mustBeNonnegative} = 0
    options.Training (:,1) double = zeros(0,1)
end
n = (0:numel(x)-1).';
y = double(x).*exp(-1j*2*pi*options.OffsetHz*n/fs);
info = struct('offset_hz',options.OffsetHz,'input_fs_hz',fs, ...
    'decimation',options.Decimation,'output_fs_hz',fs/options.Decimation, ...
    'notch_hz',options.NotchHz,'notch_width_hz',options.NotchWidthHz, ...
    'whitening_order',options.WhiteningOrder,'whitening_coefficients',[], ...
    'edge_samples_to_exclude',0,'caveat', ...
    'Each operation changes the observation; retain identity branch and assess held-out screen-content preservation.');
if options.Decimation>1
    if exist('resample','file')>0
        [y,b] = resample(y,1,options.Decimation);
        info.resampling_implementation = 'Signal Processing Toolbox resample';
    else
        [y,b] = decimateBaseFir(y,options.Decimation);
        info.resampling_implementation = 'base MATLAB windowed-sinc FIR decimator';
    end
    info.resample_fir_coefficients = b;
    info.edge_samples_to_exclude = ceil((numel(b)-1)/(2*options.Decimation));
end
fsOut = info.output_fs_hz;
for k = 1:numel(options.NotchHz)
    frequency = options.NotchHz(k);
    assert(abs(frequency)+options.NotchWidthHz/2<fsOut/2, ...
        'mobile:BadNotch','Notch is outside the Nyquist band.');
    % A complex notch removes only the requested signed-frequency region.
    angleZero = 2*pi*frequency/fsOut;
    radius = exp(-pi*options.NotchWidthHz/fsOut);
    b = [1 -exp(1j*angleZero)];
    a = [1 -radius*exp(1j*angleZero)];
    y = filter(b,a,y);
    info.edge_samples_to_exclude = max(info.edge_samples_to_exclude, ...
        ceil(8/max(1-radius,eps)));
end
if options.WhiteningOrder>0
    assert(numel(options.Training)>20*options.WhiteningOrder, ...
        'mobile:NoTraining','Provide independent complex clutter training for whitening.');
    assert(exist('arburg','file')>0,'mobile:ToolboxMissing', ...
        'AR whitening requires Signal Processing Toolbox.');
    [a,errorPower] = arburg(options.Training-mean(options.Training), ...
        options.WhiteningOrder);
    y = filter(a,1,y)/sqrt(max(errorPower,eps));
    info.whitening_coefficients = struct('real',real(a),'imag',imag(a));
    info.whitening_training_count = numel(options.Training);
    info.whitening_training_error_power = errorPower;
    info.edge_samples_to_exclude = max(info.edge_samples_to_exclude,numel(a));
end
end

function [y,b] = decimateBaseFir(x,factor)
% Linear-phase antialias FIR with explicitly recorded coefficients.
% Cutoff is 0.45/factor cycles/input-sample; 20*factor+1 Hann taps.
delay = 10*factor;
n = (-delay:delay).';
cutoff = 0.45/factor;
b = ones(size(n))*2*cutoff;
nonzero = n~=0;
b(nonzero) = sin(2*pi*cutoff*n(nonzero))./(pi*n(nonzero));
window = 0.5+0.5*cos(pi*n/delay);
b = b.*window;
b = b/sum(b);
filtered = filter(b,1,[x;zeros(delay,1)]);
y = filtered(delay+1:factor:delay+numel(x));
end
