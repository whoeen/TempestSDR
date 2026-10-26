function report = verifySignalWaveletInstall
%VERIFYSIGNALWAVELETINSTALL Add newly installed paths without resetting session.
lab = fileparts(mfilename('fullpath'));
installedPaths = string(jsondecode(fileread(fullfile(lab,'results','iphone6_cfo_timing_20261026','install','installed_paths.json'))));
currentPaths = split(string(path),pathsep);
addedPaths = strings(0,1);
for k = 1:numel(installedPaths)
    candidate = installedPaths(k);
    if strlength(candidate)>0 && isfolder(candidate) && ~any(strcmpi(candidate,currentPaths))
        addpath(candidate,'-end');
        addedPaths(end+1,1) = candidate; %#ok<AGROW>
    end
end
rehash toolboxcache
fs = 2000;
t = (0:2047)'/fs;
x = exp(1i*2*pi*(120*t+30*t.^2));
y = resample(x,2,3);
[z,p,k] = butter(4,200/(fs/2));
[sos,g] = zp2sos(z,p,k);
filtered = filtfilt(sos,g,x);
window = kaiser(128,10);
[s,f,tf] = fsst(x,fs,window);
xRecovered = ifsst(s,window);
[cw,wf,coi] = cwt(real(x),fs);
reconstructionError = norm(xRecovered(:)-x)/norm(x);
assert(all(isfinite(y)) && all(isfinite(filtered)));
assert(reconstructionError<1e-10);
assert(all(isfinite(cw(:))) && ~isempty(wf) && ~isempty(coi));
report = struct('status','verified','matlab_version',version, ...
    'products',ver,'new_paths_added',addedPaths, ...
    'resample_path',which('resample'),'filtfilt_path',which('filtfilt'), ...
    'fsst_path',which('fsst'),'cwt_path',which('cwt'), ...
    'resample_output_length',numel(y), ...
    'fsst_size',size(s),'fsst_frequency_range_hz',[min(f),max(f)], ...
    'fsst_time_samples',numel(tf), ...
    'fsst_inverse_relative_error',reconstructionError, ...
    'cwt_size',size(cw));
out = fullfile(lab,'results','iphone6_cfo_timing_20261026','install','verification.json');
fid = fopen(out,'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
fprintf('Signal Processing + Wavelet execution verified. FSST inverse error %.3g.\n',reconstructionError);
end
