function survey = surveyIphoneArchive(maxFrames)
%SURVEYIPHONEARCHIVE Re-read all six archived iPhone 6 captures in big endian.
% Keeps full raster and untouched AM controls. Timing is a prior hypothesis.
arguments
    maxFrames (1,1) double {mustBeInteger,mustBePositive} = 8
end
labRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
rawRoot = fullfile(getenv('USERPROFILE'),'Desktop','mobile','0625');
outRoot = fullfile(labRoot,'results','iphone_recovery_20261023',sprintf('archive_P%03d',maxFrames));
assert(~isfolder(outRoot),'iphone:Exists','Refuse to overwrite an existing run: %s',outRoot);
mkdir(outRoot);
cfg = mobileBaselineConfig();
cfg.max_frames = maxFrames;
cfg.checkpoints = unique([1 4 maxFrames]);
cfg.figure_visible = 'off';
files = ["238M_60M_124.08571_topleft_iphone6_book34page_.rIs"; ...
    "238M_60M_124.08571M_bottom middle_iphone6.rIs"; ...
    "238M_60M_124.08571M_topleft_iphone6.rIs"; ...
    "238M_60M_124.08571M_topmiddle_book93page_iphone6.rIs"; ...
    "308M_60M_124.08571M_bageung hwameon_iphone6.rIs"; ...
    "312M_49M_124.08571M_baeung.rIs"];
keys = ["book34_238";"bottom_middle_238";"topleft_238";"book93_238";"response_308";"response_312"];
fc = [238 238 238 238 308 312]*1e6;
bw = [60 60 60 60 60 49]*1e6;
survey = struct([]);
for n=1:numel(files)
    d = cfg.devices(2);
    d.key = char(keys(n)); d.title = char("iPhone 6 / "+keys(n));
    d.filename = char(files(n)); d.fs_hz = 124.085710e6;
    d.rf_center_hz = fc(n); d.receiver_bandwidth_hz = bw(n);
    d.prior_line_hz = 112805.083;
    d.raster_rows = 1880; d.raster_columns = 1100;
    d.prior_frame_samples = d.raster_rows*d.fs_hz/d.prior_line_hz;
    d.origin_columns = 0;
    d.active_row_segments = [1 d.raster_rows];
    d.active_column_segments = [1 d.raster_columns];
    d.metadata_source = 'Existing release manifest and filename; timing transferred as a hypothesis, not individually fitted.';
    output = fullfile(outRoot,keys(n)); mkdir(output);
    file = fullfile(rawRoot,files(n));
    fprintf('START %s\n',keys(n)); drawnow;
    [probe,info] = readRisIqBlock(file,0,2^20);
    diagnostic = diagnoseIq(probe);
    result = compareRasterAverages(file,d,cfg,output,fullfile(output,'notes.jsonl'));
    item = struct('key',keys(n),'source',file,'read_info',info,'device',d, ...
        'diagnostic',diagnostic,'reconstruction',result);
    writeJsonFile(fullfile(output,'metrics.json'),item);
    if isempty(survey), survey=item; else, survey(end+1)=item; end %#ok<AGROW>
    writeJsonFile(fullfile(outRoot,'survey.json'),survey);
    fprintf('DONE %s: AM odd/even correlation %.5f\n',keys(n),result.checkpoints(end).am_odd_even_correlation);
end
end
