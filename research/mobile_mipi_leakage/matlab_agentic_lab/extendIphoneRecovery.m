function runs = extendIphoneRecovery()
%EXTENDIPHONERECOVERY Larger averages with explicit prior/estimated timing.
labRoot=fileparts(mfilename('fullpath'));addpath(fullfile(labRoot,'signal_processing'));
root=fullfile(labRoot,'results','iphone_recovery_20261023');
cfg=mobileBaselineConfig();cfg.figure_visible='off';cfg.max_frames=32;cfg.checkpoints=[1 8 16 32];
rawRoot=fullfile(getenv('USERPROFILE'),'Desktop','mobile','0625');
survey=jsondecode(fileread(fullfile(root,'archive_P008','survey.json')));
keys=["bottom_middle_238","response_308"];
runs=struct([]);
for k=1:numel(keys)
    idx=find(string({survey.key})==keys(k),1);d=survey(idx).device;
    d.active_row_segments=[1 d.raster_rows];d.active_column_segments=[1 d.raster_columns];
    out=fullfile(root,keys(k)+"_P032_v2");assert(~isfolder(out),'iphone:Exists','Refuse overwrite');mkdir(out);
    fprintf('START %s P32\n',keys(k));drawnow;
    result=compareRasterAverages(string(survey(idx).source),d,cfg,out,fullfile(out,'notes.jsonl'));
    writeJsonFile(fullfile(out,'metrics.json'),result);
    item=struct('key',keys(k),'output',out,'result',result);
    if isempty(runs),runs=item;else,runs(end+1)=item;end %#ok<AGROW>
end
% Add iPhone 6s control using its established, separate configuration.
d=cfg.devices(2);out=fullfile(root,'iphone6s_P032');
assert(~isfolder(out),'iphone:Exists','Refuse overwrite');mkdir(out);
fprintf('START iPhone6s P32\n');drawnow;
result=compareRasterAverages(fullfile(rawRoot,d.filename),d,cfg,out,fullfile(out,'notes.jsonl'));
writeJsonFile(fullfile(out,'metrics.json'),result);
runs(end+1)=struct('key',"iphone6s",'output',out,'result',result);
% Newly found 25MS/s iPhone6 capture. Keep full raster; no physical-pixel claim.
p=jsondecode(fileread(fullfile(root,'password_diagnostic','diagnostic.json')));
d.key='password_105';d.title='iPhone 6 password capture / 105 MHz';
d.filename='iphone6 password capture March13';d.fs_hz=p.fs_hz;d.rf_center_hz=105e6;d.receiver_bandwidth_hz=NaN;
d.prior_line_hz=p.line_candidates(1).conditional_line_hz;d.raster_rows=1881;d.raster_columns=1100;
d.prior_frame_samples=p.frame_candidates(1).frame_samples;d.origin_columns=0;
d.active_row_segments=[1 1881];d.active_column_segments=[1 1100];
d.metadata_source='March13 LabVIEW screenshot and exact-path source scripts; BW unknown; line/frame estimates from first0.335s';
cfg.max_frames=64;cfg.checkpoints=[1 8 16 32 64];
out=fullfile(root,'password_105_P064');assert(~isfolder(out),'iphone:Exists','Refuse overwrite');mkdir(out);
fprintf('START new iPhone6 password P64\n');drawnow;
result=compareRasterAverages(string(p.source),d,cfg,out,fullfile(out,'notes.jsonl'));
writeJsonFile(fullfile(out,'metrics.json'),result);
runs(end+1)=struct('key',"password_105",'output',out,'result',result);
writeJsonFile(fullfile(root,'extended_runs.json'),runs);
end
