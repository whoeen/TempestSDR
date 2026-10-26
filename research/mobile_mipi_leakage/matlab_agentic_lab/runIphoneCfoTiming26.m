function runIphoneCfoTiming26
%RUNIPHONECFOTIMING26 Serialized actual MATLAB toolbox research execution.
lab = fileparts(mfilename('fullpath'));
addpath(lab,fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
out = fullfile(lab,'results','iphone6_cfo_timing_20261026');
fprintf('Starting actual 100/160 MHz timing/CFO analysis.\n');
analyzeIphonePairTiming;
timingDir = fullfile(out,'timing');
data = load(fullfile(timingDir,'model.mat'),'model');
model = data.model;
fields = {'meanPilotTrain','meanPilotTest','meanAmTest','meta'};
bandA = load(fullfile(timingDir,'band_fc100.mat'),fields{:});
bandB = load(fullfile(timingDir,'band_fc160.mat'),fields{:});
stitchIphonePair26(bandA,bandB,model.carrier_translation_cycles_100_to160, ...
    model.canonical_period_seconds,fullfile(out,'stitch'));
clear bandA bandB
runIphoneTf26;
fprintf('All timing/CFO, stitching and TF analyses completed.\n');
end
