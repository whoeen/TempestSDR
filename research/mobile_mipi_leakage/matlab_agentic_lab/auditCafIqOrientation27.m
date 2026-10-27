function report=auditCafIqOrientation27(out)
%AUDITCAFIQORIENTATION27 Conditional IQ-conjugation sensitivity, not full search.
arguments
 out (1,1) string
end
d=load(fullfile(out,'complex_caf.mat'),'profiles','halfProfiles','fs','f0','fc');
f=load(fullfile(out,'caf_channel_fits.mat'));
selected=unique([f.validWinner f.matchedWinner f.controlWinner],'stable');
orders=f.orders;lags=f.lags;
F=exp(-2i*pi*orders*(0:1099)/1100)/1100;
records=cell(numel(selected)*2,1);index=0;
for ii=1:numel(selected)
 id=selected(ii);r=f.results(id);g=f.groups(id);
 mB=dsi3LanePowerModel27(g.black,r.rate_hz,d.f0,8192);
 mW=dsi3LanePowerModel27(g.white,r.rate_hz,d.f0,8192);
 B=[dsiCafBasis27(mB,r.emission_index,d.fs,d.fc,lags,orders);dsiCafBasis27(mW,r.emission_index,d.fs,d.fc,lags,orders)];
 ov=repmat(orders,numel(lags)*2,1);
 B=B.*exp(-2i*pi*ov*r.delay_phase).*repmat(sinc(orders/1100).^2,2*numel(lags),1);
 for orientation=1:2
  index=index+1;target=cell(3,1);
  for bb=1:3
   a=d.profiles(:,2:end,1:2,bb);
   if orientation==2,a=conj(a);end
   yBlack=F*a(:,:,1);yWhite=F*a(:,:,2);
   target{bb}=[yBlack(:);yWhite(:)];
  end
  w=ones(size(target{1})); % Equal weights for a direct orientation sensitivity.
  fit=fitDsiCafChannel27(B,target{1},w,struct('maxStarts',5,'maxIterations',600));
  nmse=zeros(1,3);phase=nmse;
  for bb=1:3
   y=target{bb};nmse(bb)=sum(abs(y-fit.prediction).^2)/sum(abs(y).^2);
   phase(bb)=angle(y'*fit.prediction)*180/pi;
  end
  records{index}=struct('candidate',r.name,'conjugated_iq',orientation==2, ...
   'nmse_equal_weights',nmse,'phase_deg',phase,'relative_amplitude',fit.relativeAmplitude, ...
   'relative_phase_deg',fit.relativePhaseDeg,'reference_lane_zero_based',fit.referenceLaneZeroBased, ...
   'timing_rate_emission_fixed',true,'codeword_rate_search_repeated',false);
 end
end
report=struct('scope','Conditional IQ-direction sensitivity for selected codewords only. Channels refitted on B1 with equal weights; rate/emission/delay fixed. Not a full reverse-IQ search.', ...
 'records',[records{:}],'iq_direction_verified',false,'corrections_applied_to_primary_result',false);
fid=fopen(fullfile(out,'iq_orientation_audit.json'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,'PrettyPrint',true),'char');
disp(report);
end
