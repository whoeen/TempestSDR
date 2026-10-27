function writeJsonFile(filePath, value)
%WRITEJSONFILE Write a readable UTF-8 JSON artifact.
arguments
    filePath (1,1) string
    value
end
fid = fopen(filePath,'w','n','UTF-8');
assert(fid>=0,'mobile:JsonOpenFailed','Cannot write JSON file.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
