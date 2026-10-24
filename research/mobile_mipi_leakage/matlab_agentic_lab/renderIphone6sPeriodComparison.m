function renderIphone6sPeriodComparison
%RENDERIPHONE6SPERIODCOMPARISON Scientific panels with identical pixel scaling.
lab=fileparts(mfilename('fullpath'));
root=fullfile(lab,'results','iphone6_followup_20261024','iphone6s_frame_period_P032');
d=load(fullfile(root,'paired_am_arrays.mat'));
arms=[5 1 6 2];
names={'Rounded frame; nearest','Fractional frame; nearest','Rounded frame; cubic','Fractional frame; cubic'};
for crop=[false true]
 fig=figure('Visible','off','Color','w','Position',[70 70 1500 1100]);cleanup=onCleanup(@() close(fig));
 tiledlayout(1,4,'TileSpacing','compact');
 for j=1:4
  a=double(d.am(d.activeRows,d.activeCols,arms(j)));
  if crop,a=a(250:700,90:660);end
  nexttile;imagesc(a,d.normalization);axis image off;colormap gray;
  title(names{j});
 end
 sgtitle('iPhone 6s | same 32 frames, same line timing, same display scale | integer period adds 15.85-column drift');
 if crop,file='period_comparison_text.png';else,file='period_comparison_full.png';end
 exportgraphics(fig,fullfile(root,file),Resolution=130);clear cleanup
end
end
