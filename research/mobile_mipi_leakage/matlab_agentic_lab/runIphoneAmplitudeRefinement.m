function result=runIphoneAmplitudeRefinement()
%RUNIPHONEAMPLITUDEREFINEMENT Track envelope timing without a screen template.
labRoot=fileparts(mfilename('fullpath')); addpath(fullfile(labRoot,'signal_processing'),fullfile(labRoot,'stitch'));
root=fullfile(labRoot,'results','iphone6_stitch_20261023'); out=fullfile(root,'am_refinement');
assert(~isfolder(out),'stitch:Exists','Refuse overwrite'); mkdir(out);
centers=[100 340 520]; n=2^21; nr=1100*1881; origin=8192; frameCount=64; checkpoints=[1 4 8 16 32 64];
u=(0:n-1).'/n; signedBins=(0:n-1).'; signedBins(signedBins>=n/2)=signedBins(signedBins>=n/2)-n;
lags=(-16:16).'; lagIds=mod(lags,n)+1; result=struct('status','running','bands',{{}});
for bi=1:numel(centers)
 fc=centers(bi); folder=fullfile(out,sprintf('fc%03dMHz',fc)); mkdir(folder);
 m=jsondecode(fileread(fullfile(root,'templates',sprintf('fc%03dMHz',fc),'metadata.json')));
 p=m.period_samples; dc=complex(m.training_dc_removed_real,m.training_dc_removed_imag); fs=m.fs_hz;
 filename=resolveIphoneSweepCapture(fc);
 sumAm=zeros(n,1,'single'); sumCoh=complex(sumAm); sumInteger=zeros(nr,1,'single'); log=zeros(frameCount,5);
 for f=1:frameCount
  k=f-1; start=origin+k*p; first=floor(start)-512; raw=readRisIqBlock(filename,first,n); raw=raw-single(dc);
  z=sampleGuardedIqFft(raw,start-first+u*p,GuardSamples=512);
  amplitude=abs(z); az=amplitude-mean(amplitude);
  if f==1, reference=z; referenceAm=az; referenceF=fft(az); referenceEnergy=sum(referenceAm.^2,'double'); end
  corr=real(ifft(fft(az).*conj(referenceF))); [peak,idx]=max(corr(lagIds));
  lag=lags(idx); ids=mod(lag+[-1 0 1],n)+1; v=double(corr(ids)); denom=v(1)-2*v(2)+v(3);
  if abs(denom)>eps, lag=lag+max(-.5,min(.5,.5*(v(1)-v(3))/denom)); end
  if f==1, lag=0; end
  amCoherence=double(peak)/sqrt(sum(az.^2,'double')*referenceEnergy);
  z=ifft(fft(z).*single(exp(1i*2*pi*signedBins*lag/n)));
  cross=sum(z.*conj(reference),'double'); phase=angle(cross); rho=abs(cross)/sqrt(sum(abs(z).^2,'double')*sum(abs(reference).^2,'double'));
  sumAm=sumAm+abs(z); sumCoh=sumCoh+z*single(exp(-1i*phase));
  log(f,:)=[k lag amCoherence phase rho];
  % Matched same-N comparison for integer vs fractional/adaptive timing.
  if f<=8
   integerRaw=readRisIqBlock(filename,origin+k*nr,nr); integerRaw=integerRaw-single(dc); sumInteger=sumInteger+abs(integerRaw);
  end
  if any(checkpoints==f)
   amImage=reshape(resamplePeriodicAm(sumAm/f,nr,PeriodSeconds=p/fs),1100,1881).';
   coherentImage=reshape(resamplePeriodicAm(abs(sumCoh/f),nr,PeriodSeconds=p/fs),1100,1881).';
   imwrite(scaleDisplay(amImage),fullfile(folder,sprintf('am_N%02d.png',f)));
   imwrite(scaleDisplay(coherentImage),fullfile(folder,sprintf('coherent_adaptive_N%02d.png',f)));
   if f==8
    integerImage=reshape(resamplePeriodicAm(sumInteger/8,nr,PeriodSeconds=nr/fs),1100,1881).';
    imwrite(scaleDisplay(integerImage),fullfile(folder,'am_integer_N08.png'));
    save(fullfile(folder,'same_N8_comparison.mat'),'integerImage','amImage','coherentImage','-v7');
   end
  end
 end
 % Display-only deterministic high-pass. It does not recover original RGB.
 localMean=conv2(ones(21,1,'single')/21,ones(1,41,'single')/41,amImage,'same');
 enhanced=amImage-localMean;
 imwrite(scaleDisplay(enhanced),fullfile(folder,'am_N64_display_highpass.png'));
 save(fullfile(folder,'N64_images.mat'),'amImage','coherentImage','enhanced','log','m','-v7');
 if fc==100
  imwrite(scaleDisplay(amImage(900:1500,90:1000)),fullfile(folder,'text_region_AM64.png'));
  imwrite(scaleDisplay(enhanced(900:1500,90:1000)),fullfile(folder,'text_region_display_highpass.png'));
 end
 writematrix(log,fullfile(folder,'frame_log.csv'));
 meta=struct('fc_mhz',fc,'frames',frameCount,'frame_indices_zero_based',0:frameCount-1,'period_samples',p, ...
  'fs_hz',fs,'first_sample_origin',origin,'checkpoints',checkpoints,'max_extra_envelope_lag_grid_samples',16, ...
  'median_am_correlation',median(log(2:end,3)),'median_complex_correlation',median(log(2:end,5)), ...
  'phase_reference','frame0 after the same envelope timing alignment', ...
  'log_columns',{{'frame_index','adaptive_lag_output_samples','am_correlation','relative_phase_rad','complex_correlation'}}, ...
  'validation_caveat','Per-frame timing and phase are adaptively estimated on every frame. This is a reconstruction control, not frozen heldout validation.', ...
  'display_highpass','Subtract separable21row x41column local mean; independent1/99percentile display scaling', ...
  'reference_image_used',false,'same_N8_control','Same source frames0:7 and same fixed complex DC; both images explicitly antialiased. Fractional version additionally tracks envelope delay.');
 writeJsonFile(fullfile(folder,'metadata.json'),meta); result.bands{bi}=meta; writeJsonFile(fullfile(out,'overview.json'),result);
 fprintf('AM64 fc%d MHz envelope median%.3f complexmedian%.3f\n',fc,meta.median_am_correlation,meta.median_complex_correlation);
end
result.status='complete'; writeJsonFile(fullfile(out,'overview.json'),result);
end
function y=scaleDisplay(x)
q=double(sampleQuantile(x(:),[.01 .99])); y=uint8(255*min(1,max(0,(double(x)-q(1))/max(q(2)-q(1),eps))));
end
