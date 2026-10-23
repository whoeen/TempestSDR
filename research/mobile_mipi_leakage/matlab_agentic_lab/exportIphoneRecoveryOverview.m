function exportIphoneRecoveryOverview()
%EXPORTIPHONERECOVERYOVERVIEW Arrange measured AM PNGs; no image inference.
root=fullfile(fileparts(mfilename('fullpath')),'results','iphone_recovery_20261023');
files={'iphone6s_P032_am.png','bottom_middle_238_P032_am.png','response_308_P032_am.png'};
labels={'iPhone 6s / 311 MHz / P32','iPhone 6 keypad / 238 MHz / P32','iPhone 6 home / 308 MHz / P32'};
f=figure('Visible','off','Position',[20 20 1500 860]);
layout=tiledlayout(f,1,3,'Padding','loose','TileSpacing','loose');
for k=1:3
    nexttile; image(imread(fullfile(root,'presentation_v2',files{k}))); colormap(gray(256)); axis image off; title(labels{k});
end
title(layout,'Measured IQ: AM reconstructions / individual log display scales');
exportgraphics(f,fullfile(root,'recovery_overview.png'),Resolution=130); close(f);
end
