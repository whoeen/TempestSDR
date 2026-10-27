function [capturePath, resolution] = resolveIphoneSweepCapture(fcMHz)
%RESOLVEIPHONESWEEPCAPTURE Find an immutable sweep capture on Windows/Linux.
%   Prefer the user-configured TEMPEST_IQ_ROOT, accepting either original
%   Unicode names or the stable complete-file ASCII release-asset names.
%   No environment variable is written and no raw data are modified/copied.
arguments
    fcMHz (1,1) double {mustBeInteger,mustBeFinite}
end
assert(ismember(fcMHz,100:60:700),'stitch:InvalidSweepCenter', ...
    'fcMHz must be one of 100:60:700.');
helperRoot = fileparts(mfilename('fullpath'));
labRoot = fileparts(helperRoot);
researchRoot = fileparts(labRoot);
repositoryRoot = fileparts(fileparts(researchRoot));
configuredRoot = string(getenv('TEMPEST_IQ_ROOT'));
roots = strings(0,1);
rootKinds = strings(0,1);
if strlength(configuredRoot)>0
    roots(end+1,1) = configuredRoot;
    rootKinds(end+1,1) = "TEMPEST_IQ_ROOT";
end
if ispc
    profileDirectory = string(getenv('USERPROFILE'));
else
    profileDirectory = string(getenv('HOME'));
end
if strlength(profileDirectory)>0
    roots(end+1,1) = fullfile(profileDirectory,'Downloads');
    rootKinds(end+1,1) = "platform Downloads";
end
knownRoots = [string(pwd);fullfile(pwd,'data');fullfile(pwd,'raw_iq_parts'); ...
    fullfile(researchRoot,'data');fullfile(researchRoot,'raw_iq','data'); ...
    fullfile(researchRoot,'raw_iq_parts');fullfile(repositoryRoot,'data'); ...
    fullfile(repositoryRoot,'raw_iq_parts')];
for k=1:numel(knownRoots)
    if isfolder(knownRoots(k))
        roots(end+1,1) = knownRoots(k); %#ok<AGROW>
        rootKinds(end+1,1) = "existing conventional data directory"; %#ok<AGROW>
    end
end
[roots,uniqueIndices] = unique(roots,'stable');
rootKinds = rootKinds(uniqueIndices);
names = [string(sprintf('black글_fc%dMHz.rIs',fcMHz)); ...
    string(sprintf('iphone6_black_text_sweep_20261023_fc%dMHz.rIs',fcMHz))];
checked = strings(0,1);
expectedBytes = NaN;
expectedSha256 = "";
inventoryPath = fullfile(labRoot,'knowledge','stitching','iphone6_sweep_20261023','CAPTURE_INVENTORY.json');
if isfile(inventoryPath)
    inventory = jsondecode(fileread(inventoryPath));
    identityIndex = find([inventory.captures.fc_mhz]==fcMHz,1);
    if ~isempty(identityIndex)
        expectedBytes = inventory.captures(identityIndex).bytes;
        expectedSha256 = string(inventory.captures(identityIndex).full_sha256);
    end
end
for rootIndex=1:numel(roots)
    for nameIndex=1:numel(names)
        candidate = fullfile(roots(rootIndex),names(nameIndex));
        checked(end+1,1) = candidate; %#ok<AGROW>
        if ~isfile(candidate)
            continue
        end
        fileInfo = dir(candidate);
        assert(numel(fileInfo)==1 && ~fileInfo.isdir,'stitch:AmbiguousCapturePath', ...
            'Capture path is not a unique regular file: %s',candidate);
        assert(fileInfo.bytes>0 && mod(fileInfo.bytes,4)==0,'stitch:InvalidCaptureLength', ...
            'Capture byte count must be a positive multiple of four: %s',candidate);
        if isfinite(expectedBytes)
            assert(fileInfo.bytes==expectedBytes,'stitch:CaptureSizeMismatch', ...
                'Existing candidate does not match the recorded byte count; refusing fallback: %s',candidate);
        end
        % DIR.folder is an absolute path, including for relative configured roots.
        capturePath = string(fullfile(fileInfo.folder,fileInfo.name));
        resolution = struct('fc_mhz',fcMHz,'path',capturePath, ...
            'root_source',rootKinds(rootIndex),'selected_filename',names(nameIndex), ...
            'bytes',fileInfo.bytes,'expected_bytes',expectedBytes, ...
            'expected_sha256',expectedSha256,'sha256_verified_by_this_helper',false, ...
            'identity_note','Path and size checked. Use downloader/assembler SHA verification for full-file identity.', ...
            'environment_modified',false,'raw_modified',false);
        return
    end
end
error('stitch:SweepCaptureNotFound', ...
    'No sweep capture found for fc=%d MHz. Configure TEMPEST_IQ_ROOT to the verified data directory. Checked:\n%s', ...
    fcMHz,strjoin(checked,newline));
end
