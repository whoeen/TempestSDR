function audit = auditTemplateGeneralization27(outputDir)
%AUDITTEMPLATEGENERALIZATION27 Diagnose held-out failures without retuning.
arguments
    outputDir (1,1) string
end
s=load(fullfile(outputDir,'short_template.mat'));
f=load(fullfile(outputDir,'frame_template.mat'));
st=s.shortTable; ft=f.frameTable;
test=~ft.IsTraining & ~ft.IsGuard;
delta=st.ValidationCorrAfter-st.ValidationCorrBefore;
jumps=abs(st.EstimatedDelayNs)>500; % Descriptive cutoff, not a correction gate.
largeLoss=delta < -0.1;
testFit=polyfit(ft.FrameIndexZeroBased(test),ft.MeasuredLagLines(test),1);
zeroRms=rms(ft.MeasuredLagLines(test));
predictionRms=rms(ft.MeasuredLagLines(test)-ft.PredictedLagFromTrainingLines(test));
audit=struct('short_validation_windows',height(st), ...
    'short_mean_corr_before',mean(st.ValidationCorrBefore), ...
    'short_mean_corr_after',mean(st.ValidationCorrAfter), ...
    'short_number_improved',sum(delta>0),'short_number_degraded',sum(delta<0), ...
    'short_number_large_losses_over_0p1',sum(largeLoss), ...
    'short_number_abs_delay_over_500ns',sum(jumps), ...
    'short_maximum_loss',min(delta),'short_large_loss_rows',find(largeLoss)', ...
    'short_jump_within_frame_rows', ...
        mod(st.TimeSeconds(jumps)*s.shortMeta.frozen_frequency_hz,f.frameMeta.training_acf_lines)', ...
    'short_timing_interpretation', ...
        'A global template can match a different pulse when waveform state changes. Large lag is not validated clock drift.', ...
    'frame_test_diagnostic_slope_lines_per_frame',testFit(1), ...
    'frame_test_zero_delay_rms_lines',zeroRms, ...
    'frame_test_training_prediction_rms_lines',predictionRms, ...
    'frame_training_drift_model_supported_on_test',predictionRms<zeroRms, ...
    'frame_timing_interpretation', ...
        'Training slope extrapolation is not supported when residual lag RMS exceeds zero-delay baseline. Small profile-correlation gains after interpolation do not prove timing correction.', ...
    'template_still_detects_periodic_structure',true,'automatic_time_warp_approved',false, ...
    'packet_decoded',false,'test_data_used_to_retune',false);

[~,worst]=min(delta); block=st.Block(worst); chunk=st.Chunk(worst);
lab=string(fileparts(mfilename('fullpath')));
source=fullfile(lab,'results','iphone6_fc100_fam_20261026','refined', ...
    sprintf('rf78_block%d',block),'subband.mat');
wave=load(source,'iq','front');
power=abs(wave.iq).^2;
time=wave.front.retained_original_first_sample/wave.front.native_fs_hz+ ...
    (0:numel(power)-1)'/wave.front.output_fs_hz;
edges=round(linspace(1,numel(power)+1,33));
first=edges(chunk);last=edges(chunk+1)-1;middle=floor((first+last)/2);
halfA=fold(power(first:middle),time(first:middle),s.shortMeta.frozen_frequency_hz);
halfB=fold(power(middle+1:last),time(middle+1:last),s.shortMeta.frozen_frequency_hz);
fig=figure('Name','Template limitations: held-out evidence','Color','w','Position',[110 60 1400 900]);
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout);stem(ax,st.TimeSeconds,delta,'filled','MarkerSize',3);
yline(ax,0,'--','HandleVisibility','off');xlabel(ax,'Absolute recording time (s)');
ylabel(ax,'Validation correlation after - before');
title(ax,sprintf('%d of %d test windows lose > 0.1 correlation',sum(largeLoss),height(st)));grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
phase=((0:127)'+0.5)/128*s.shortMeta.period_us;
plot(ax,phase,normalizeShape(s.template),'DisplayName','Frozen global template');
plot(ax,phase,normalizeShape(halfA),'DisplayName','First half: lag estimation');
plot(ax,phase,normalizeShape(halfB),'DisplayName','Second half: validation');
xlabel(ax,'Within-period time (us)');ylabel(ax,'Mean-removed unit-energy profile');
title(ax,sprintf('Observed shape change: block %d, chunk %d',block,chunk));
legend(ax,'Location','best');grid(ax,'on');
ax=nexttile(layout);hold(ax,'on');
within=mod(st.TimeSeconds*s.shortMeta.frozen_frequency_hz,f.frameMeta.training_acf_lines);
scatter(ax,within,st.EstimatedDelayNs,28,delta,'filled');
cb=colorbar(ax);cb.Label.String='Validation correlation change';
xlabel(ax,'Nominal within-frame row at validation midpoint');ylabel(ax,'Estimated lag (ns)');
title(ax,'Large lag clusters with waveform state; not verified clock drift');grid(ax,'on');
ax=nexttile(layout);bar(ax,[zeroRms predictionRms]);
xticks(ax,1:2);xticklabels(ax,{'Zero-delay baseline','Training linear drift'});
ylabel(ax,'Held-out measured-lag residual RMS (rows)');
title(ax,'Training slope fails to predict held-out lag');grid(ax,'on');
title(layout,'Validation prevents interpreting every correlation gain as successful timing recovery');
exportgraphics(fig,fullfile(outputDir,'template_failure_audit.png'),'Resolution',150);
savefig(fig,fullfile(outputDir,'template_failure_audit.fig'));
fid=fopen(fullfile(outputDir,'generalization_audit.json'),'w','n','UTF-8');
assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
disp(audit);
end

function p=fold(power,time,f0)
bin=min(128,floor(mod(time*f0,1)*128)+1);
count=accumarray(bin,1,[128 1]);
p=accumarray(bin,power,[128 1])./max(count,1);
end

function x=normalizeShape(x)
x=x-mean(x);x=x/max(norm(x),realmin);
end
