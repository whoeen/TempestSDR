%% Smartphone electromagnetic leakage laboratory
% Start a visible, shared MATLAB session. Raw captures are read only.
labRoot = fileparts(mfilename("fullpath"));
cd(labRoot);
addpath(fullfile(labRoot,"signal_processing"));
if ~isfolder(fullfile(labRoot,"environment"))
    mkdir(fullfile(labRoot,"environment"));
end
diary(fullfile(labRoot,"environment","matlab_desktop_diary.txt"));
toolboxPath = fullfile(fileparts(fileparts(fileparts(fileparts(labRoot)))), ...
    "matlab-runtime","MATLABMCPServerToolbox.mltbx");
if exist("shareMATLABSession","file") ~= 2 && usejava('jvm') && isfile(toolboxPath)
    matlab.addons.toolbox.installToolbox(toolboxPath);
end
if exist("shareMATLABSession","file") == 2
    shareMATLABSession();
    sharingStatus = "Explicit session sharing enabled";
else
    sharingStatus = "Explicit shareMATLABSession unavailable; use the configured MATLAB MCP managed desktop";
end
inventory = struct("timestamp",string(datetime("now","TimeZone","UTC")), ...
    "version",version,"release",version("-release"),"root",matlabroot, ...
    "products",ver,"addons",table2struct(matlab.addons.installedAddons));
fid = fopen(fullfile(labRoot,"environment","matlab_inventory.json"),"w");
assert(fid >= 0,"Lab:InventoryWrite","Cannot write inventory.");
fwrite(fid,jsonencode(inventory,PrettyPrint=true),"char");
fclose(fid);
disp(sharingStatus);
disp("Run runMobileBaseline after reviewing the config and current source.");
edit(fullfile(labRoot,"labWorkbench.m"));
