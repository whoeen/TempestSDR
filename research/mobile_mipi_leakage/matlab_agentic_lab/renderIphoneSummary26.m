function renderIphoneSummary26
lab=fileparts(mfilename('fullpath'));
out=fullfile(lab,'results','iphone6_cfo_timing_20261026');
fig=figure('Visible','off','Color','w','Position',[20 20 1400 1250]);
tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
for b=[100 160]
    paths={fullfile(out,'timing',sprintf('fc%d_images',b),'AM_heldout_raw.png'), ...
        fullfile(out,'timing',sprintf('fc%d_images',b),'AM_heldout_both.png'), ...
        fullfile(out,'tracked',sprintf('fc%d_Adaptive_AM_partition2.png',b))};
    labels={'Fixed prior; no fitted correction','Frozen CFO + affine timing','Adaptive per-frame timing + fixed CFO'};
    for j=1:3
        ax=nexttile;
        image(ax,imread(paths{j}));axis(ax,'image');axis(ax,'off');
        title(ax,sprintf('%d MHz | %s',b,labels{j}));
    end
end
colormap(fig,gray(256));
sgtitle(fig,'Same frames 72--79; shared training contrast per band | AM repeatability, not an image-fidelity score');
exportgraphics(fig,fullfile(out,'gallery','am_before_after.png'),Resolution=130);
close(fig);
summary=jsondecode(fileread(fullfile(out,'stitch_tracked','overview.json')));
r=summary.records(1);
f=figure('Visible','off','Color','w','Position',[40 40 1150 460]);
tiledlayout(f,1,2);
nexttile;bar([r.narrow_106mhz_alignment.train_coherence,r.narrow_106mhz_alignment.test_coherence,r.narrow_training_tone_mask_control.test_coherence]);
xticklabels({'Training','Adaptive assessment','Masked assessment'});ylim([0 1]);ylabel('Complex coherence');grid on;
nexttile;bar(r.narrow_106mhz_alignment.test_phase_rad);xticklabels({'Adaptive assessment'});ylim([-pi pi]);ylabel('Frozen RF-fit residual phase (rad)');grid on;
sgtitle(f,'Adaptive AM tracking; RF alignment fit remains frozen on training');
exportgraphics(f,fullfile(out,'stitch_tracked','overlap_phase_coherence.png'),Resolution=140);close(f);
end
