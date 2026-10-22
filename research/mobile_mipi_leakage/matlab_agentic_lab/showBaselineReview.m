function review = showBaselineReview(runRoot)
%SHOWBASELINEREVIEW Show the measured baseline with explicit display scaling.
arguments
    runRoot (1,1) string
end
labRoot = string(fileparts(mfilename('fullpath')));
addpath(fullfile(labRoot,'signal_processing'));
summary = jsondecode(fileread(fullfile(runRoot,'summary.json')));
originals = ["lgx2_original.png","iphone6s_original.png","galaxy_original.png"];
review = struct('run_root',runRoot,'am_display','log1p of fixed first-frame 1/99 percentiles', ...
    'phase_display','H=relative IQ phase; S=complex consistency, masked below P8 amplitude Q25; V=log amplitude', ...
    'warning','Display mapping only; no new bandwidth or original RGB recovery.');
fig = figure('Name','Measured smartphone IQ: original and frame progression', ...
    'Color','w','Position',[30 40 1600 1000],'Visible','on');
layout = tiledlayout(fig,3,6,'TileSpacing','compact','Padding','compact');
metricsFig = figure('Name','Coherence and averaging diagnostics', ...
    'Color','w','Position',[60 60 1300 900],'Visible','on');
metricLayout = tiledlayout(metricsFig,3,2,'TileSpacing','compact','Padding','compact');
for k=1:numel(summary.devices)
    d = summary.devices(k);
    deviceDir = fullfile(runRoot,d.key);
    arrays = load(fullfile(deviceDir,'raster_final.mat'));
    axesRows = arrays.activeRows; axesCols = arrays.activeCols;
    ax = nexttile(layout);
    image(ax,imread(fullfile(labRoot,'..','provided_restoration_analysis',originals(k))));
    axis(ax,'image','off'); title(ax,string(d.source.device_metadata.title)+" | original",'Interpreter','none');
    for frames=[1 4 8]
        % Recover only the stored display values; this panel is a display remap.
        gray = imread(fullfile(deviceDir,sprintf('P%03d_am.png',frames)));
        if isinteger(gray), gray=double(gray)/double(intmax(class(gray))); else, gray=double(gray); end
        range = arrays.normalization;
        amplitude = range(1)+gray*(range(2)-range(1));
        value = (log1p(amplitude)-log1p(range(1)))/(log1p(range(2))-log1p(range(1)));
        ax = nexttile(layout); image(ax,repmat(value,1,1,3)); axis(ax,'image','off');
        title(ax,sprintf('P%d AM | fixed log scale',frames));
    end
    amplitude = abs(arrays.coherent(axesRows,axesCols));
    range = arrays.normalization;
    value = min(max((log1p(double(amplitude))-log1p(range(1)))/(log1p(range(2))-log1p(range(1))),0),1);
    ax = nexttile(layout); image(ax,repmat(value,1,1,3)); axis(ax,'image','off'); title(ax,'P8 row-fit amplitude | log');
    hue = mod(angle(arrays.coherent(axesRows,axesCols))+pi,2*pi)/(2*pi);
    mask = amplitude>sampleQuantile(amplitude,0.25);
    saturation = arrays.rowConsistency(axesRows,axesCols).*single(mask);
    rgb = hsv2rgb(cat(3,double(hue),double(saturation),value));
    imwrite(rgb,fullfile(deviceDir,'P008_phase_hsv_log_masked.png'));
    ax = nexttile(layout); image(ax,rgb); axis(ax,'image','off'); title(ax,'P8 relative phase | Q25 masked');
    parameters = readtable(fullfile(deviceDir,'frame_parameters.csv'));
    progression = readtable(fullfile(deviceDir,'frame_progression.csv'));
    ax = nexttile(metricLayout);
    plot(ax,parameters.frame,parameters.profile_correlation,'o-'); hold(ax,'on');
    plot(ax,parameters.frame,parameters.heldout_mixture_coherence,'s-'); hold(ax,'off');
    ylim(ax,[0 1.05]); xlabel(ax,'Frame (1 is self-reference)'); ylabel(ax,'Normalized mixture statistic');
    title(ax,string(d.key)+" | alignment vs phase",'Interpreter','none'); grid(ax,'on');
    legend(ax,'Column-profile alignment','Disjoint-row phase agreement','Location','best');
    ax = nexttile(metricLayout);
    plot(ax,progression.frames,powerDb(progression.uncorrected_coherent_power_counts2),'o-'); hold(ax,'on');
    plot(ax,progression.frames,powerDb(progression.global_coherent_power_counts2),'s-');
    plot(ax,progression.frames,powerDb(progression.row_coherent_power_counts2),'^-'); hold(ax,'off');
    xlabel(ax,'Averaged frames'); ylabel(ax,'Power (dB re ADC counts squared)');
    title(ax,'Mixture coherent power; NOT signal SNR'); grid(ax,'on');
    legend(ax,'Uncorrected','Global phase','Row phase','Location','best');
end
title(layout,'Real captured IQ | display remap for inspection | shared linear controls saved separately');
title(metricLayout,'Amplitude alignment does not establish phase alignment or screen fidelity');
exportgraphics(fig,fullfile(runRoot,'review_overview.png'),Resolution=140);
exportgraphics(metricsFig,fullfile(runRoot,'review_diagnostics.png'),Resolution=140);
writeJsonFile(fullfile(runRoot,'review_display_metadata.json'),review);
figure(fig);
end
