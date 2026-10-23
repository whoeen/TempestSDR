function run=runIphoneStitchExperiment(polarity)
%RUNIPHONESTITCHEXPERIMENT Adjacent overlap validation and wideband controls.
arguments
 polarity (1,1) double {mustBeMember(polarity,[-1 1])}=1
end
labRoot=fileparts(mfilename('fullpath')); addpath(fullfile(labRoot,'signal_processing'),fullfile(labRoot,'stitch'));
root=fullfile(labRoot,'results','iphone6_stitch_20261023'); out=fullfile(root,sprintf('stitch_polarity_%+d',polarity));
assert(~isfolder(out),'stitch:Exists','Refuse overwrite'); mkdir(out);
centers=100:60:700; spectraTrain=cell(11,1); spectraTest=cell(11,1); metas=cell(11,1); nominal=zeros(11,1);
for b=1:11
 d=load(fullfile(root,'templates',sprintf('fc%03dMHz',centers(b)),'templates.mat'),'trainFFT','testFFT','meta');
 metas{b}=d.meta; spectraTrain{b}=d.trainFFT; spectraTest{b}=d.testFFT;
 if polarity==-1
  spectraTrain{b}=conj(circshift(flipud(spectraTrain{b}),1));
  spectraTest{b}=conj(circshift(flipud(spectraTest{b}),1));
 end
 nominal(b)=centers(b)*1e6*d.meta.period_seconds+polarity*d.meta.phase_advance_rad_per_frame/(2*pi);
end
period=metas{1}.period_seconds; nominal=round(nominal-nominal(1)); centersBins=nominal;
n=numel(spectraTrain{1}); localBins=(-n/2:n/2-1).'; cumulativeDelay=zeros(11,1); cumulativePhase=zeros(11,1);
run=struct('status','running','iq_polarity',polarity,'period_seconds',period,'center_mhz',centers, ...
 'nominal_center_bins',nominal,'branch_offsets_searched',-16:16,'training_frames',0:7,'heldout_frames',16:23, ...
 'variant','frozen training timing/phase template; provisional harmonic mapping', ...
 'caveat','Computed images are experimental outputs; reconstruction and physical bandwidth fidelity require overlap validation.', ...
 'edges',{{}},'combinations',{{}});
for edge=1:10
 fprintf('Polarity %+d edge %d-%d MHz branch search\n',polarity,centers(edge),centers(edge+1));
 cA=centersBins(edge); initialB=nominal(edge+1)+(cA-nominal(edge));
 [best,bTrainAligned,bTestAligned,search]=searchPeriodicOverlapBranches(spectraTrain{edge},spectraTrain{edge+1}, ...
  spectraTest{edge},spectraTest{edge+1},cA,initialB,period,120e6,-16:16);
 centersBins(edge+1)=best.selected_center_bin_b;
 alignment=best.alignment;
 cumulativeDelay(edge+1)=cumulativeDelay(edge)+alignment.delay_seconds;
 cumulativePhase(edge+1)=cumulativePhase(edge)+alignment.phase_rad;
 folder=fullfile(out,sprintf('pair_%03d_%03d',centers(edge),centers(edge+1))); mkdir(folder);
 writeJsonFile(fullfile(folder,'branch_search.json'),search); writeJsonFile(fullfile(folder,'alignment.json'),best);
 pairTrain={spectraTrain{edge};single(bTrainAligned)}; pairTest={spectraTest{edge};single(bTestAligned)};
 pairCenters=centersBins(edge:edge+1);
 pairOutput=renderCombination(pairTrain,pairTest,pairCenters,period,folder,sprintf('%d + %d MHz',centers(edge),centers(edge+1)));
 run.edges{edge}=best; run.combinations{edge}=pairOutput;
 writeJsonFile(fullfile(out,'overview.json'),run);
 clear bTrainAligned bTestAligned pairTrain pairTest
end
% Apply the measured path correction once per band to put all on band 100.
for b=2:11
 globalBins=localBins+centersBins(b);
 correction=single(exp(1i*2*pi*(globalBins/period)*cumulativeDelay(b)-1i*cumulativePhase(b)));
 spectraTrain{b}=spectraTrain{b}.*correction; spectraTest{b}=spectraTest{b}.*correction;
end
save(fullfile(out,'aligned_templates.mat'),'spectraTrain','spectraTest','centersBins','period','cumulativeDelay','cumulativePhase','-v7.3');
subsets={1:3,1:6,6:11,1:11};
for g=1:numel(subsets)
 subset=subsets{g}; folder=fullfile(out,sprintf('group_%03d_%03d',centers(subset(1)),centers(subset(end)))); mkdir(folder);
 entry=renderCombination(spectraTrain(subset),spectraTest(subset),centersBins(subset),period,folder, ...
  sprintf('%d bands: %d--%d MHz',numel(subset),centers(subset(1)),centers(subset(end))));
 run.combinations{10+g}=entry; writeJsonFile(fullfile(out,'overview.json'),run);
end
run.status='complete'; run.center_bins_selected=centersBins; run.cumulative_delay_seconds=cumulativeDelay; run.cumulative_phase_rad=cumulativePhase;
run.interpretation='Edge coherence, residual phase, ambiguity and holdout errors decide whether synthesis is physically supported. More nominal bandwidth alone is not proof of better image recovery.';
writeJsonFile(fullfile(out,'overview.json'),run);
end

function result=renderCombination(trainSpectra,testSpectra,centerBins,period,folder,label)
result=struct('label',label,'center_bins',centerBins,'methods',{{}}); methods=["raised_cosine","paper_lr_w8"];
for methodIndex=1:2
 method=methods(methodIndex); if methodIndex==1, guard=3e6; else, guard=0; end
 settings=struct('spectra',{trainSpectra},'centerBins',centerBins);
 [fTrain,meta]=synthesizePeriodicBands(settings,period,Method=method,EdgeGuardHz=guard);
 inputPower=sum(abs(fTrain).^2,'double'); wave=ifft(ifftshift(fTrain))*numel(fTrain); clear fTrain
 [raster,aa]=resamplePeriodicAm(abs(wave),1100*1881,PeriodSeconds=period); clear wave
 trainImage=reshape(raster,1100,1881).'; clear raster
 settings.spectra=testSpectra; [fTest,testMeta]=synthesizePeriodicBands(settings,period,Method=method,EdgeGuardHz=guard);
 wave=ifft(ifftshift(fTest))*numel(fTest); clear fTest
 testImage=reshape(resamplePeriodicAm(abs(wave),1100*1881,PeriodSeconds=period),1100,1881).'; clear wave
 imwrite(displayScale(trainImage),fullfile(folder,method+"_train.png")); imwrite(displayScale(testImage),fullfile(folder,method+"_heldout.png"));
 residual=trainImage-mean(trainImage,1)-mean(trainImage,2)+mean(trainImage,'all');
 imwrite(displayScale(residual),fullfile(folder,method+"_row_column_residual.png"));
 a=double(trainImage(:)); b=double(testImage(:)); a=a-mean(a); b=b-mean(b);
 metrics=struct('am_train_test_correlation',dot(a,b)/(norm(a)*norm(b)),'stitched_train_power_counts_squared',inputPower, ...
  'synthesis',meta,'heldout_synthesis',testMeta,'antialias',aa,'image_scaling','independent1st/99thpercentile; display only', ...
  'image_registration','none; common time raster 1100x1881, same raw origin in anchor band');
 writeJsonFile(fullfile(folder,method+"_metrics.json"),metrics);
 save(fullfile(folder,method+"_images.mat"),'trainImage','testImage','metrics','-v7');
 result.methods{methodIndex}=metrics;
 fprintf('  %s %s: output %.3f MS/s; AM train/test r=%.4f\n',label,method,meta.output_rate_hz/1e6,metrics.am_train_test_correlation);
end
end
function y=displayScale(x)
q=double(sampleQuantile(x(:),[.01 .99])); y=uint8(255*min(1,max(0,(double(x)-q(1))/max(q(2)-q(1),eps))));
end
