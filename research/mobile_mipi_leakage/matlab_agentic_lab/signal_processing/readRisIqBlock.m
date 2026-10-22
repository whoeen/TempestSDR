function [iq, info] = readRisIqBlock(filePath, firstSample, sampleCount)
%READRISIQBLOCK Read a bounded block of headerless big-endian int16 I,Q.
%   FIRSTSAMPLE is zero based. IQ is a complex single column in ADC counts.
%   The file is opened read-only. No sample-rate or RF metadata is inferred.
arguments
    filePath (1,1) string
    firstSample (1,1) double {mustBeInteger,mustBeNonnegative}
    sampleCount (1,1) double {mustBeInteger,mustBePositive}
end
fileInfo = dir(filePath);
assert(~isempty(fileInfo), 'mobile:FileMissing', 'File not found: %s', filePath);
assert(mod(fileInfo.bytes,4)==0, 'mobile:BadLength', ...
    'RIS byte length must be divisible by four.');
assert(4*(firstSample+sampleCount)<=fileInfo.bytes, 'mobile:ShortRead', ...
    'Requested block extends beyond the file.');
fid = fopen(filePath,'r','ieee-be');
assert(fid>=0, 'mobile:OpenFailed', 'Cannot open %s.', filePath);
cleanup = onCleanup(@() fclose(fid));
status = fseek(fid,4*firstSample,'bof');
assert(status==0, 'mobile:SeekFailed', 'Cannot seek to requested offset.');
[raw,count] = fread(fid,[2,sampleCount],'int16=>single');
assert(count==2*sampleCount, 'mobile:ShortRead', 'Short IQ block read.');
iq = complex(raw(1,:).',raw(2,:).');
info = struct('filename',string(fileInfo.name),'bytes',fileInfo.bytes, ...
    'first_sample_zero_based',firstSample,'sample_count',sampleCount, ...
    'byte_offset',4*firstSample,'byte_count',4*sampleCount, ...
    'disk_dtype','big-endian signed int16 interleaved I,Q', ...
    'memory_dtype','complex single','units','ADC counts');
end
