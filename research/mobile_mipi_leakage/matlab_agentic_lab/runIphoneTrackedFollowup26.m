function runIphoneTrackedFollowup26
lab=fileparts(mfilename('fullpath'));
addpath(lab,fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
out=fullfile(lab,'results','iphone6_cfo_timing_20261026');
analyzeIphoneTracked26;
r=jsondecode(fileread(fullfile(out,'tracked','overview.json')));
fields={'meanPilotTrain','meanPilotTest','meanAmTest','meta'};
a=load(fullfile(out,'tracked','band_fc100.mat'),fields{:});
b=load(fullfile(out,'tracked','band_fc160.mat'),fields{:});
stitchIphonePair26(a,b,r.carrier_translation_cycles_100_to160, ...
    r.canonical_period_seconds,fullfile(out,'stitch_tracked'),"adaptive_time_fixed_cfo",true);
clear a b
runIphoneTfHeldout26;
auditIphoneSingle26;
fprintf('Adaptive tracking, heldout TF and single-frame controls completed.\n');
end
