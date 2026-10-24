function report = auditIphoneNarrowOverlap
%AUDITIPHONENARROWOVERLAP Train-only narrow RF alignment; fresh frame64 test.
lab=fileparts(mfilename('fullpath'));
addpath(fullfile(lab,'signal_processing'),fullfile(lab,'stitch'));
out=fullfile(lab,'results','iphone6_followup_20261024','narrow_overlap_100_160_global_phase');
assert(~isfolder(out),'audit:Exists','Refuse overwrite');mkdir(out);
root=fullfile(lab,'results','iphone6_stitch_20261023','templates');
a=load(fullfile(root,'fc100MHz','templates.mat'),'singleTrain','meta');
b=load(fullfile(root,'fc160MHz','templates.mat'),'singleTrain','meta');
n=numel(a.singleTrain);T=a.meta.period_seconds;
[aFresh,readA]=freshFrame(a.meta,64,n);[bFresh,readB]=freshFrame(b.meta,64,n);
cycles=160e6*b.meta.period_seconds-100e6*T;q=round(cycles);frac=cycles-q;
translation=single(exp(1i*2*pi*frac*(0:n-1).'/n));
% Known broadband delay verifies correction sign and fractional units.
previousRng=rng; rngCleanup=onCleanup(@() rng(previousRng)); %#ok<NASGU>
rng(311);ns=4096;k=(-900:900).';sa=randn(size(k))+1i*randn(size(k));
trueDelay=127.31;truePhase=.72;sb=sa.*exp(1i*truePhase-1i*2*pi*k*trueDelay/ns);
check=fitBand(sa,sb,sa,sb,k,ns,1,true);
assert(abs(check.delay_seconds-trueDelay/ns)<1e-7,'audit:DelaySign','Synthetic delay failed');
assert(abs(angle(exp(1i*(check.phase_rad-truePhase))))<1e-5,'audit:PhaseSign','Synthetic phase failed');
centers=106:6:154;width=6e6;branches=-16:16;
records=struct([]);branchRecords=struct([]);
for polarity=[1 -1]
 trA=a.singleTrain;teA=aFresh;trB=b.singleTrain;teB=bFresh;
 if polarity<0,trA=conj(trA);teA=conj(teA);trB=conj(trB);teB=conj(teB);end
 A=fftshift(fft(trA))/n;AT=fftshift(fft(teA))/n;
 B=fftshift(fft(trB.*translation))/n;BT=fftshift(fft(teB.*translation))/n;
 % Relative RF translation uses full normalized time frameIndex+u.
 BT=BT*single(exp(1i*2*pi*frac*64));
 clear trA teA trB teB
 for centerMHz=centers
  lo=(centerMHz-100)*1e6-width/2;hi=(centerMHz-100)*1e6+width/2;
  bins=(ceil(lo*T):floor(hi*T)).';ns=2^nextpow2(numel(bins));
  iA=bins+n/2+1;aa=double(A(iA));at=double(AT(iA));
  for maskTones=[false true]
   scores=zeros(size(branches));
   for j=1:numel(branches)
    iB=bins-(q+branches(j))+n/2+1;bb=double(B(iB));bt=double(BT(iB));
    keep=toneMask(aa,bb,maskTones);
    r=fitBand(aa(keep),bb(keep),at(keep),bt(keep),bins(keep),ns,T,false);
    scores(j)=r.train_coherence;
   end
   [~,j]=max(scores);branch=branches(j);
   iB=bins-(q+branch)+n/2+1;bb=double(B(iB));bt=double(BT(iB));
   keep=toneMask(aa,bb,maskTones);
   r=fitBand(aa(keep),bb(keep),at(keep),bt(keep),bins(keep),ns,T,true);
   r.fc_a_mhz=100;r.fc_b_mhz=160;r.iq_polarity=polarity;
   r.window_center_rf_mhz=centerMHz;r.window_width_mhz=width/1e6;
   r.training_top10_bins_neighborhood_removed=maskTones;
   r.selected_branch_bins=branch;r.branch_hz=branch/T;r.at_search_boundary=abs(branch)==16;
   r.retained_training_power_a=sum(abs(aa(keep)).^2)/sum(abs(aa).^2);
   r.retained_training_power_b=sum(abs(bb(keep)).^2)/sum(abs(bb).^2);
   r.training_frame=0;r.assessment_frame=64;records=[records;r]; %#ok<AGROW>
   for jj=1:numel(branches)
    br=struct('polarity',polarity,'window_center_rf_mhz',centerMHz,'tone_mask',maskTones, ...
      'branch_bins',branches(jj),'training_coarse_coherence',scores(jj));
    branchRecords=[branchRecords;br]; %#ok<AGROW>
   end
   fprintf('Narrow %+.0f RF %.0f MHz mask%d train %.4f fresh %.4f Neff %.1f\n', ...
     polarity,centerMHz,maskTones,r.train_coherence,r.fresh_coherence,r.effective_bins);
  end
 end
end
writetable(struct2table(records),fullfile(out,'window_metrics.csv'));
writetable(struct2table(branchRecords),fullfile(out,'training_branch_search.csv'));
report=struct('status','complete','training_frame_zero_based',0,'fresh_assessment_frame_zero_based',64, ...
 'assessor_used_for_selection',false,'frames_averaged',1,'input_fs_hz',124082800,'period_seconds',T, ...
 'nominal_relative_cycles',cycles,'nominal_integer_center_b',q,'fractional_translation_cycles',frac, ...
 'fresh_global_phase_correction_rad',angle(exp(1i*2*pi*frac*64)), ...
 'phase_convention','B frequency translation exp(j2pi frac*(frameIndex+u)); frame0 training and frame64 assessment.', ...
 'read_a',readA,'read_b',readB, ...
 'mask_definition','Training top 10 cross-magnitude bins, each +/-8 Fourier bins; fixed for assessment.', ...
 'branch_selection','Largest coarse training coherence; winner receives fractional-delay refinement.', ...
 'boundary_model','Single frame circular Fourier alignment, not finite linear correlation.', ...
 'limitations','Single-frame low SNR; finite +/-16/T frequency-branch range; not continuous CFO or sample-clock estimation. High tone-dominated coherence alone is not a valid screen stitch.', ...
 'synthetic_sign_check',check,'records',records);
writeJsonFile(fullfile(out,'overview.json'),report);
fig=figure('Visible','off','Color','w','Position',[60 60 1250 850]);cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
tiledlayout(2,2,'TileSpacing','compact');
for polarity=[1 -1]
 for maskTones=[false true]
  ix=[records.iq_polarity]==polarity & [records.training_top10_bins_neighborhood_removed]==maskTones;
  rr=records(ix);nexttile;
  plot([rr.window_center_rf_mhz],[rr.train_coherence],'-o');hold on;
  plot([rr.window_center_rf_mhz],[rr.fresh_coherence],'-s');grid on;ylim([0 1]);
  xlabel('Nominal overlap RF center (MHz)');ylabel('Complex coherence');
  title(sprintf('IQ polarity %+d | tone mask %d | 6 MHz windows',polarity,maskTones));
  legend('Training frame 0','New frame 64; frozen parameters','Location','best');
 end
end
sgtitle('100 + 160 MHz: narrow overlap validation, not a claimed coherent recovery');
exportgraphics(fig,fullfile(out,'narrow_overlap_validation.png'),Resolution=130);
end
function [z,record]=freshFrame(meta,k,n)
path=resolveIphoneSweepCapture(meta.fc_mhz);start=meta.origin_samples+k*meta.period_samples;first=floor(start)-512;
[raw,record]=readRisIqBlock(path,first,2^21);
raw=raw-complex(meta.training_dc_removed_real,meta.training_dc_removed_imag);
z=sampleGuardedIqFft(raw,start-first+(0:n-1).'/n*meta.period_samples,GuardSamples=512);
record.frame_zero_based=k;record.parameters_fitted_to_new_frame=false;
end
function keep=toneMask(a,b,enabled)
keep=true(size(a));
if enabled
 [~,ix]=sort(abs(a.*b),'descend');
 for j=1:min(10,numel(ix)),keep(max(1,ix(j)-8):min(numel(keep),ix(j)+8))=false;end
end
end
function r=fitBand(a,b,at,bt,k,n,T,refine)
c=b.*conj(a);den=sqrt(sum(abs(a).^2)*sum(abs(b).^2));
cx=complex(zeros(n,1));cx(mod(k,n)+1)=c;
cc=abs(ifft(cx)*n);[peak,ix]=max(cc);d=mod(ix-1+n/2,n)-n/2;
if refine
 kc=k-round(mean(k));
 objective=@(delta)-abs(sum(c.*exp(1i*2*pi*kc*(d+delta)/n)));
 delta=fminbnd(objective,-1,1,optimset('TolX',1e-8,'Display','off'));d=d+delta;
end
ramp=exp(1i*2*pi*k*d/n);phi=angle(sum(c.*ramp));correction=ramp*exp(-1i*phi);
train=b.*correction;test=bt.*correction;w=abs(c);eff=sum(w)^2/max(sum(w.^2),realmin);
guard=max(2,ceil(2*n/(max(k)-min(k)+1)));
distance=abs(mod((0:n-1).'-(ix-1)+n/2,n)-n/2);cc(distance<=guard)=0;
r=struct('train_coherence',abs(sum(train.*conj(a)))/max(den,realmin), ...
 'fresh_coherence',abs(sum(test.*conj(at)))/max(norm(test)*norm(at),realmin), ...
 'fresh_relative_error',norm(at-test)/max(norm(at),realmin), ...
 'fresh_residual_phase_rad',angle(sum(test.*conj(at))), ...
 'delay_seconds',d*T/n,'phase_rad',phi,'effective_bins',eff, ...
 'second_peak_ratio',max(cc)/max(peak,realmin),'correlation_grid_rate_hz',n/T);
end
