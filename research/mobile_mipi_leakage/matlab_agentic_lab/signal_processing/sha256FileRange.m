function digest = sha256FileRange(filePath, byteOffset, byteCount)
%SHA256FILERANGE Hash original bytes in bounded reads, not reencoded samples.
arguments
    filePath (1,1) string
    byteOffset (1,1) double {mustBeInteger,mustBeNonnegative} = 0
    byteCount (1,1) double {mustBeNonnegative} = Inf
end
fileInfo = dir(filePath);
assert(~isempty(fileInfo),'mobile:HashFileMissing','Hash input missing.');
byteCount = min(byteCount,fileInfo.bytes-byteOffset);
assert(byteCount>=0,'mobile:HashRange','Hash offset exceeds file size.');
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(filePath,'r');
assert(fid>=0,'mobile:HashOpen','Cannot open hash input.');
cleanup = onCleanup(@() fclose(fid));
assert(fseek(fid,byteOffset,'bof')==0,'mobile:HashSeek','Hash seek failed.');
remaining = byteCount;
while remaining>0
    block = fread(fid,min(remaining,2^20),'*uint8');
    assert(~isempty(block),'mobile:HashShortRead','Unexpected end of hash input.');
    md.update(typecast(block,'int8'));
    remaining = remaining-numel(block);
end
bytes = typecast(md.digest(),'uint8');
digest = string(lower(reshape(dec2hex(bytes,2).',1,[])));
end
