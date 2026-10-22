function metadata = exportRisForTempest(inputPath, outputPath, fs, options)
%EXPORTRISFORTEMPEST Export a new bounded little-endian int16 IQ file.
%   Original RIS uses big-endian int16. TempestSDR's native int16 reader on
%   Windows expects little-endian; byte swapping is lossless, not resampling.
%   An accompanying JSON describes the exact input byte range and hashes.
arguments
    inputPath (1,1) string
    outputPath (1,1) string
    fs (1,1) double {mustBePositive}
    options.FirstSample (1,1) double {mustBeInteger,mustBeNonnegative} = 0
    options.SampleCount (1,1) double {mustBeInteger,mustBePositive} = 2^20
    options.BlockSamples (1,1) double {mustBeInteger,mustBePositive} = 2^20
end
inputCanonical = string(java.io.File(char(inputPath)).getCanonicalPath());
outputCanonical = string(java.io.File(char(outputPath)).getCanonicalPath());
assert(~strcmpi(inputCanonical,outputCanonical),'mobile:ImmutableInput', ...
    'Choose a new output file; the original capture must not be overwritten.');
assert(~isfile(outputPath) && ~isfile(outputPath+".json"),'mobile:ExportExists', ...
    'Output or sidecar already exists. Choose a new output name.');
fileInfo = dir(inputPath);
assert(~isempty(fileInfo),'mobile:FileMissing','Input capture does not exist.');
assert(4*(options.FirstSample+options.SampleCount)<=fileInfo.bytes, ...
    'mobile:ShortRead','Requested export extends beyond the capture.');
folder = fileparts(outputPath);
if strlength(folder)>0 && ~isfolder(folder)
    mkdir(folder);
end
fid = fopen(outputPath,'w','ieee-le');
assert(fid>=0,'mobile:ExportOpen','Cannot create output file.');
cleanup = onCleanup(@() fclose(fid));
for first=0:options.BlockSamples:options.SampleCount-1
    count = min(options.BlockSamples,options.SampleCount-first);
    iq = readRisIqBlock(inputPath,options.FirstSample+first,count);
    interleaved = [real(iq).';imag(iq).'];
    written = fwrite(fid,interleaved,'int16');
    assert(written==2*count,'mobile:ExportWrite','Incomplete output write.');
end
delete(cleanup);
metadata = struct('input_filename',string(fileInfo.name), ...
    'input_format','headerless big-endian signed int16 interleaved I,Q', ...
    'output_format','headerless little-endian signed int16 interleaved I,Q', ...
    'first_sample_zero_based',options.FirstSample,'sample_count',options.SampleCount, ...
    'sample_rate_hz',fs,'duration_s',options.SampleCount/fs, ...
    'source_range_sha256',sha256FileRange(inputPath,4*options.FirstSample,4*options.SampleCount), ...
    'output_sha256',sha256FileRange(outputPath),'output_bytes',4*options.SampleCount, ...
    'tempestsdr_native_block_complex_samples',262144, ...
    'tempestsdr_complete_block_samples',floor(options.SampleCount/262144)*262144, ...
    'tempestsdr_trailing_samples',mod(options.SampleCount,262144), ...
    'tempestsdr_eof_warning','RawFile loops at EOF. Replays are not independent frames. Prefer an explicitly requested multiple of 262144 complex samples; no padding or trimming was performed.', ...
    'transform','byte-order conversion only; identical signed I and Q integers', ...
    'sampling_metadata_status','Fs supplied by caller; RIS contains no embedded Fs');
writeJsonFile(outputPath+".json",metadata);
end
