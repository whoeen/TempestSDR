function entry = appendResearchNote(filePath, stage, payload)
%APPENDRESEARCHNOTE Append one auditable UTF-8 JSON object per line.
arguments
    filePath (1,1) string
    stage (1,1) string
    payload (1,1) struct
end
entry = struct('schema_version',1, ...
    'timestamp_utc',string(datetime('now','TimeZone','UTC', ...
    'Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")), ...
    'stage',stage,'matlab_version',string(version),'payload',payload);
folder = fileparts(filePath);
if strlength(folder)>0 && ~isfolder(folder), mkdir(folder); end
fid = fopen(filePath,'a','n','UTF-8');
assert(fid>=0,'mobile:NoteOpenFailed','Cannot open research notebook.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(entry));
end
