function summary = runMobileBaseline(configPath, outputRoot)
%RUNMOBILEBASELINE Reproducible MATLAB study of three immutable RIS captures.
%   SUMMARY = RUNMOBILEBASELINE() uses mobileBaselineConfig. Optional JSON
%   CONFIGPATH replaces that configuration. Every run gets a UTC folder;
%   results and exact block hashes are logged in UTF-8 JSONL notebooks.
arguments
    configPath (1,1) string = ""
    outputRoot (1,1) string = ""
end
if strlength(configPath)==0
    cfg = mobileBaselineConfig();
else
    cfg = jsondecode(fileread(configPath));
end
if strlength(outputRoot)>0
    cfg.output_root = outputRoot;
end
timestamp = string(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
runRoot = fullfile(string(cfg.output_root),timestamp);
mkdir(runRoot);
writeJsonFile(fullfile(runRoot,'config.json'),cfg);
notePath = fullfile(runRoot,'notes.jsonl');
summary = struct('run_root',runRoot,'status','running','devices',struct([]), ...
    'synthetic',struct(),'toolboxes',ver,'matlab_version',version, ...
    'config_sha256',sha256FileRange(fullfile(runRoot,'config.json')));
appendResearchNote(notePath,'run_started',summary);
manifest = jsondecode(fileread(cfg.release_manifest));
if iscell(manifest.datasets)
    datasets = manifest.datasets;
else
    datasets = num2cell(manifest.datasets);
end
datasetNames = cellfun(@(item) string(item.filename),datasets);
for k=1:numel(cfg.devices)
    device = cfg.devices(k);
    outputDir = fullfile(runRoot,string(device.key));
    mkdir(outputDir);
    deviceNote = fullfile(outputDir,'notes.jsonl');
    record = struct('key',device.key,'status','started','source',struct(), ...
        'baseline',struct(),'parametric',struct(),'frame_candidates',struct(), ...
        'raster',struct(),'error',"");
    try
        filePath = locateCapture(device.filename,cfg.search_roots);
        [iq,info] = readRisIqBlock(filePath,cfg.first_sample,cfg.sample_count);
        expectedIndex = find(datasetNames==string(device.filename),1);
        assert(~isempty(expectedIndex),'mobile:ManifestEntry','Capture absent from release manifest.');
        expected = datasets{expectedIndex};
        source = struct('path',filePath,'filename',device.filename,'file_bytes',info.bytes, ...
            'manifest_file_sha256',expected.sha256, ...
            'full_sha_verified_this_run',false,'block',info, ...
            'block_sha256',sha256FileRange(filePath,info.byte_offset,info.byte_count), ...
            'device_metadata',device);
        assert(info.bytes==expected.bytes,'mobile:ManifestSize','Capture size disagrees with release manifest.');
        if cfg.verify_full_file_hash
            source.actual_full_sha256 = sha256FileRange(filePath);
            assert(source.actual_full_sha256==string(expected.sha256), ...
                'mobile:ManifestHash','Capture hash disagrees with release manifest.');
            source.full_sha_verified_this_run = true;
        end
        record.source = source;
        appendResearchNote(deviceNote,'source_and_hypotheses',source);
        record.baseline = analyzeIqBlock(iq,device,cfg,outputDir,deviceNote);
        record.parametric = compareParametricPsd(iq,device.fs_hz,outputDir,cfg.figure_visible);
        appendResearchNote(deviceNote,'parametric_order_sweep',record.parametric);
        record.frame_candidates = measureFrameCandidates(filePath,device,cfg,outputDir);
        appendResearchNote(deviceNote,'slow_frame_candidates',record.frame_candidates);
        if cfg.run_rasters
            record.raster = compareRasterAverages(filePath,device,cfg,outputDir,deviceNote);
        end
        record.status = 'complete';
    catch exception
        record.status = 'failed';
        record.error = string(getReport(exception,'extended','hyperlinks','off'));
        appendResearchNote(deviceNote,'error',struct('message',record.error));
        warning('mobile:DeviceFailed','%s failed: %s',device.key,exception.message);
    end
    writeJsonFile(fullfile(outputDir,'metrics.json'),record);
    summary.devices(k) = record;
    appendResearchNote(notePath,'device_completed',struct('key',device.key,'status',record.status));
end
if cfg.run_synthetic
    summary.synthetic = runWeakModulationDemo(fullfile(runRoot,'synthetic'),string(cfg.figure_visible));
    appendResearchNote(notePath,'synthetic_completed',summary.synthetic);
end
summary.status = 'complete';
if any(strcmp({summary.devices.status},'failed'))
    summary.status = 'completed_with_device_failures';
end
writeJsonFile(fullfile(runRoot,'summary.json'),summary);
appendResearchNote(notePath,'run_completed',struct('status',summary.status,'root',runRoot));
disp(summary);
end

function filePath = locateCapture(filename,searchRoots)
searchRoots = string(searchRoots);
matches = strings(0,1);
for k=1:numel(searchRoots)
    candidate = fullfile(searchRoots(k),string(filename));
    if isfile(candidate)
        matches(end+1,1) = candidate; %#ok<AGROW>
    end
end
assert(~isempty(matches),'mobile:CaptureMissing', ...
    'Capture %s missing. Set TEMPEST_DATA_ROOT or config search_roots.',filename);
filePath = matches(1);
end
