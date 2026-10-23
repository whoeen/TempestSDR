function report = reproduceIphoneSweep(runDirectory,options)
%REPRODUCEIPHONESWEEP Preflight or reproduce analysis in a NEW code workspace.
%   Default Mode="preflight" only resolves files and reports code readiness.
%   Mode="all" copies MATLAB code and the identity inventory into a new
%   directory, then executes the analysis serially without copying raw IQ.
%   It never sets environment variables or overwrites existing result folders.
arguments
    runDirectory (1,1) string = ""
    options.Mode (1,1) string {mustBeMember(options.Mode,["preflight","all"])} = "preflight"
end
sourceLab = fileparts(mfilename('fullpath'));
addpath(fullfile(sourceLab,'signal_processing'),fullfile(sourceLab,'stitch'));
centers = 100:60:700;
resolved = cell(numel(centers),1);
for k=1:numel(centers)
    [~,resolved{k}] = resolveIphoneSweepCapture(centers(k));
end
callers = ["inspectIphoneStitchSweep","previewIphoneStitchSweep", ...
    "estimateStitchFrameModel","buildIphoneStitchTemplates","runIphoneAmplitudeRefinement"];
ready = false(size(callers));
for k=1:numel(callers)
    code = fileread(fullfile(sourceLab,callers(k)+".m"));
    ready(k) = contains(code,'resolveIphoneSweepCapture(') && ...
        ~contains(code,"fullfile(getenv('USERPROFILE'),'Downloads'");
end
report = struct('mode',options.Mode,'source_lab',sourceLab,'raw_files',{resolved}, ...
    'portable_raw_callers',callers,'portable_raw_callers_ready',ready, ...
    'matlab_version',version,'pwelch_available',exist('pwelch','file')>0, ...
    'stft_available',exist('stft','file')>0,'environment_modified',false, ...
    'cloud_execution_claimed',false,'raw_files_copied',false);
if options.Mode=="preflight"
    disp(struct2table(vertcat(resolved{:})));
    disp(table(callers.',ready.','VariableNames',{'caller','portable_resolver_installed'}));
    return
end
assert(all(ready),'stitch:PortableCallersPending', ...
    'Portability replacement is pending in: %s',strjoin(callers(~ready),', '));
assert(strlength(string(getenv('TEMPEST_IQ_ROOT')))>0,'stitch:ExplicitIqRootRequired', ...
    'For a staged reproduction run, configure TEMPEST_IQ_ROOT externally to the verified raw directory.');
assert(strlength(runDirectory)>0,'stitch:RunDirectoryRequired','Provide a new run directory.');
assert(~isfolder(runDirectory) && ~isfile(runDirectory),'stitch:RunDirectoryExists', ...
    'Refuse overwrite of existing run directory: %s',runDirectory);
mkdir(runDirectory);
% Code-only staging isolates deterministic output locations from checked-in
% historical results and preserves them. Never copy result caches or raw IQ.
copyMFiles(sourceLab,runDirectory);
for subfolder=["signal_processing","stitch"]
    mkdir(fullfile(runDirectory,subfolder));
    copyMFiles(fullfile(sourceLab,subfolder),fullfile(runDirectory,subfolder));
end
inventoryRelative = fullfile('knowledge','stitching','iphone6_sweep_20261023');
mkdir(fullfile(runDirectory,inventoryRelative));
copyfile(fullfile(sourceLab,inventoryRelative,'CAPTURE_INVENTORY.json'), ...
    fullfile(runDirectory,inventoryRelative,'CAPTURE_INVENTORY.json'));
addpath(runDirectory,fullfile(runDirectory,'signal_processing'),fullfile(runDirectory,'stitch'),'-begin');
rehash;
% Ensure MATLAB resolves staged code, not a historical function elsewhere.
for name=callers
    actual = string(which(name));
    expected = string(fullfile(runDirectory,name+".m"));
    % DIR supplies an absolute path even for a user-supplied relative directory.
    expectedInfo = dir(expected);
    expected = string(fullfile(expectedInfo.folder,expectedInfo.name));
    assert(strcmpi(actual,expected),'stitch:WrongFunctionResolution', ...
        'MATLAB resolves %s outside the new run directory.',name);
end
report.run_directory = runDirectory;
report.status = 'running';
writeJsonFile(fullfile(runDirectory,'reproduction.json'),report);
verification = struct('fractional',sampleGuardedIqFftTest(),'unit_test_suites',{{}});
testFiles = ["alignPeriodicOverlapTest.m","searchPeriodicOverlapBranchesTest.m", ...
    "synthesizePeriodicBandsTest.m","resamplePeriodicAmTest.m"];
allTestsPassed = true;
for k=1:numel(testFiles)
    testResults = runtests(fullfile(runDirectory,'stitch',testFiles(k)));
    suite = struct('file',testFiles(k),'count',numel(testResults), ...
        'passed',sum([testResults.Passed]),'failed',sum([testResults.Failed]), ...
        'incomplete',sum([testResults.Incomplete]));
    verification.unit_test_suites{k} = suite;
    allTestsPassed = allTestsPassed && suite.count>0 && suite.passed==suite.count;
end
writeJsonFile(fullfile(runDirectory,'verification.json'),verification);
assert(allTestsPassed,'stitch:ReproductionTestFailure','A required existing synthetic test failed or was incomplete.');
steps = {@inspectIphoneStitchSweep,@previewIphoneStitchSweep,@estimateStitchFrameModel, ...
    @buildIphoneStitchTemplates,@() runIphoneStitchExperiment(1), ...
    @() runIphoneStitchExperiment(-1),@runIphoneSingleFrameStitchControl, ...
    @runIphoneAmplitudeRefinement,@createIphoneStitchPhaseEvidence,@auditIphoneStitchClutter};
stepNames = ["diagnostics","integer_controls","timing_model","templates", ...
    "stitch_polarity_positive","stitch_polarity_negative","single_frame_controls", ...
    "am_refinement","phase_tf","clutter_audit"];
report.completed_steps = strings(0,1);
for k=1:numel(steps)
    fprintf('Reproduction step %d/%d: %s\n',k,numel(steps),stepNames(k));
    stepResult = steps{k}(); %#ok<NASGU>
    clear stepResult
    report.completed_steps(end+1,1) = stepNames(k);
    writeJsonFile(fullfile(runDirectory,'reproduction.json'),report);
end
report.status = 'complete';
report.results_directory = fullfile(runDirectory,'results','iphone6_stitch_20261023');
report.execution_note = 'Executed on the MATLAB host that invoked this driver; this file does not infer a cloud location.';
writeJsonFile(fullfile(runDirectory,'reproduction.json'),report);
end

function copyMFiles(source,destination)
files = dir(fullfile(source,'*.m'));
for k=1:numel(files)
    copyfile(fullfile(files(k).folder,files(k).name),fullfile(destination,files(k).name));
end
end
