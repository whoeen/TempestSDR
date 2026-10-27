function [x,meta]=readAlignedFrameIq27(path,frameIndex,N,R,fs,f0,dc,nfft)
% FFT fractional delay independently per row, with wide measured guards.
% Within-row sample-rate slope is held at its midpoint; its maximum error is logged.
ratio=fs/(N*f0);rowStarts=(frameIndex*R+(0:R-1))*fs/f0;
base=floor(rowStarts);delta=rowStarts-base+(N-1)/2*(ratio-1);
guard=floor((nfft-N)/2);first=base(1)-guard;last=base(end)-guard+nfft-1;
assert(first>=0);fid=fopen(path,'r','ieee-be');assert(fid>=0);c=onCleanup(@()fclose(fid));
fseek(fid,4*first,'bof');iq=fread(fid,[2 last-first+1],'int16=>double');
assert(size(iq,2)==last-first+1);z=complex(iq(1,:),-iq(2,:)).'-dc;
x=complex(zeros(N,R));frequency=ifftshift((-nfft/2:nfft/2-1)')/nfft;
for rr=1:96:R
 ids=rr:min(R,rr+95);index=(0:nfft-1)'+(base(ids)-guard-first+1);
 slab=z(index);shifted=ifft(fft(slab,[],1).*exp((2i*pi*frequency)*delta(ids)),[],1);
 x(:,ids)=shifted(guard+(1:N),:);
end
x=x(:);
meta=struct('method','FFT fractional delay per row with measured guards; midpoint affine-clock approximation', ...
 'fft_length',nfft,'guard_samples',guard,'native_to_grid_step',ratio, ...
 'max_within_row_timing_approximation_samples',abs(ratio-1)*(N-1)/2, ...
 'max_within_row_phase_approximation_at_nyquist_rad',pi*abs(ratio-1)*(N-1)/2, ...
 'first_native_sample',first,'native_samples_read',last-first+1, ...
 'guard_comparison_scope','One training frame at nfft4096 and8192; empirical sensitivity, not strict interpolation bound.');
end
