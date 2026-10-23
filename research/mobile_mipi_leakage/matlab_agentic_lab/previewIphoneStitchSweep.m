function result = previewIphoneStitchSweep()
%PREVIEWIPHONESTITCHSWEEP Unregistered integer-grid controls before stitching.
labRoot=fileparts(mfilename('fullpath')); addpath(fullfile(labRoot,'signal_processing'));
out=fullfile(labRoot,'results','iphone6_stitch_20261023','integer_controls');
assert(~isfolder(out),'stitch:Exists','Output exists'); mkdir(out);
fs=124082800; columns=1100; rows=1881; period=columns*rows; origin=8192;
centers=100:60:700; checkpoints=[1 4 16]; result=struct(); result.fs_hz=fs;
result.note='Integer raster controls; no image registration, no fractional timing, no physical pixel interpretation';
result.period_samples=period; result.rows=rows; result.columns=columns; result.first_sample=origin;
result.frame_counts=checkpoints; result.bands=cell(numel(centers),1);
fig=figure('Visible','off','Color','w','Position',[20 20 1800 1150]); tiledlayout(fig,2,6,'TileSpacing','compact','Padding','compact');
for b=1:numel(centers)
 fc=centers(b); folder=fullfile(out,sprintf('fc%03dMHz',fc)); mkdir(folder);
 filename=resolveIphoneSweepCapture(fc);
 sumAm=zeros(period,1,'single'); sumIq=complex(zeros(period,1,'single')); phases=zeros(16,1); correlations=zeros(16,1);
 for k=1:16
  iq=readRisIqBlock(filename,origin+(k-1)*period,period); iq=iq-mean(iq);
  if k==1, ref=iq; end
  cross=sum(double(iq).*conj(double(ref))); phases(k)=angle(cross);
  correlations(k)=abs(cross)/sqrt(sum(abs(double(iq)).^2)*sum(abs(double(ref)).^2));
  sumAm=sumAm+abs(iq); sumIq=sumIq+iq*exp(-1i*single(phases(k)));
  if any(checkpoints==k)
   amp=reshape(sumAm/k,columns,rows).'; coh=reshape(abs(sumIq/k),columns,rows).';
   imwrite(scaleImage(amp),fullfile(folder,sprintf('am_N%02d.png',k)));
   imwrite(scaleImage(coh),fullfile(folder,sprintf('coherent_N%02d.png',k)));
  end
 end
 corrected=amp-mean(amp,1)-mean(amp,2)+mean(amp,'all');
 imwrite(scaleImage(corrected),fullfile(folder,'am_N16_row_column_residual.png'));
 nexttile; imagesc(amp); axis image off; colormap gray; clim(double(sampleQuantile(amp(:),[0.01 0.99]))); title(sprintf('%d MHz | AM N=16',fc));
 band=struct('fc_mhz',fc,'per_frame_phase_rad',phases,'complex_correlation_to_first',correlations, ...
  'phase_fit_warning','Each frame phase fitted independently; this is a descriptive control, not held-out validation');
 result.bands{b}=band; save(fullfile(folder,'controls.mat'),'amp','coh','corrected','phases','correlations','-v7');
 writeJsonFile(fullfile(folder,'metrics.json'),band); fprintf('Integer controls fc %d MHz complete; median complex correlation %.4f\n',fc,median(correlations(2:end)));
end
sgtitle('iPhone 6 sweep | integer raster 1100 x 1881 | 16-frame AM mean | independent display scaling');
exportgraphics(fig,fullfile(out,'am16_contact.png'),Resolution=120); close(fig);
writeJsonFile(fullfile(out,'overview.json'),result);
end
function y=scaleImage(x)
q=double(sampleQuantile(x(:),[0.01 0.99])); y=uint8(255*min(1,max(0,(double(x)-q(1))/max(q(2)-q(1),eps))));
end
