function audit = auditPcaNumerics27(out)
%AUDITPCANUMERICS27 Narrow conservation and FFT-sign checks for frame PCA.
% Uses saved measured power maps for conservation. Uses analytic periodic
% complex tones for the exact FFT fractional-delay core; no synthetic signal
% is passed through, written over, or mistaken for measured IQ.
arguments
    out (1,1) string
end
s=jsondecode(fileread(fullfile(out,'pca_summary.json')));
p=load(fullfile(out,'pca_image_data.mat'),'allComponentImages','cafMethods');
t=load(fullfile(out,'training_pca.mat'),'V','frame0');
names=string({p.cafMethods.name});rawIndex=find(names=="rawgrid");
assert(isscalar(rawIndex),'Need one rawgrid baseline.');
relativeTolerance=5e-6;maxTolerance=2e-5;
blocks=struct([]);
for bb=1:numel(p.allComponentImages)
    components=p.allComponentImages{bb};
    raw=double(p.cafMethods(rawIndex).power{bb});
    assert(isequal(size(raw),size(components,[1 2])),'Power map dimensions differ.');
    summed=sum(double(components),3);difference=summed-raw;
    relativeL2=norm(difference(:))/max(norm(raw(:)),realmin);
    relativePeak=max(abs(difference),[],'all')/max(max(abs(raw),[],'all'),realmin);
    totalRelative=abs(sum(summed,'all')-sum(raw,'all'))/max(sum(abs(raw),'all'),realmin);
    record=struct('block',bb,'component_count',size(components,3), ...
        'all_pc_total_power',sum(summed,'all'),'rawgrid_total_power',sum(raw,'all'), ...
        'relative_L2_error',relativeL2,'max_error_relative_to_raw_peak',relativePeak, ...
        'relative_total_power_error',totalRelative, ...
        'pass',relativeL2<relativeTolerance&&relativePeak<maxTolerance&&totalRelative<relativeTolerance);
    if isempty(blocks),blocks=record;else,blocks(end+1)=record;end %#ok<AGROW>
end
clear p components raw summed difference
K=size(t.V,2);
unitaryErrorDouble=norm(t.V'*t.V-eye(K),'fro')/sqrt(K);
Vs=double(single(t.V));unitaryErrorSingle=norm(Vs'*Vs-eye(K),'fro')/sqrt(K);
% Reproduce exactly the core FFT direction and guard indexing used in
% readAlignedFrameIq27. Bin-centered tones avoid FFT-edge discontinuities,
% so the result has an analytic exact value for positive and negative bins.
nfft=4096;N=double(s.phase_samples_per_row);guard=floor((nfft-N)/2);
frequency=ifftshift((-nfft/2:nfft/2-1)')/nfft;
bins=[-1980 -511 -1 1 767 1980];deltas=[0 .125 .499 .875 1.05];
toneResults=struct([]);n=(0:nfft-1)';cropped=(0:N-1)'+guard;
for kk=1:numel(bins)
    nu=bins(kk)/nfft;tone=exp(2i*pi*nu*n);
    for jj=1:numel(deltas)
        delta=deltas(jj);
        shifted=ifft(fft(tone,[],1).*exp((2i*pi*frequency)*delta),[],1);
        actual=shifted(guard+(1:N));
        expected=exp(2i*pi*nu*(cropped+delta));
        opposite=exp(2i*pi*nu*(cropped-delta));
        record=struct('fft_bin',bins(kk),'cycles_per_native_sample',nu,'advance_samples',delta, ...
            'max_absolute_error',max(abs(actual-expected)), ...
            'relative_L2_error',norm(actual-expected)/norm(expected), ...
            'opposite_sign_relative_error',norm(actual-opposite)/norm(opposite));
        if isempty(toneResults),toneResults=record;else,toneResults(end+1)=record;end %#ok<AGROW>
    end
end
toneTolerance=1e-9;
maxToneError=max([toneResults.max_absolute_error]);
maxOppositeError=max([toneResults.opposite_sign_relative_error]);
tonePass=maxToneError<toneTolerance && maxOppositeError>0.1;
% The actual row reader approximates an affine sampling grid by one delay at
% each row midpoint. Bound the remaining timing/phase error independently.
ratio=double(s.fs_native_hz)/(N*double(s.f0_hz));
maxTimeError=abs(ratio-1)*(N-1)/2;
maxPhaseBound=pi*maxTimeError;
rowStarts=(double(t.frame0(1))*double(s.frame_rows_hypothesis)+(0:double(s.frame_rows_hypothesis)-1))* ...
    double(s.fs_native_hz)/double(s.f0_hz);
fraction=rowStarts-floor(rowStarts);
delta=fraction+(N-1)/2*(ratio-1);
assert(all(delta>-1&delta<2),'Unexpected row fractional advance.');
% Analytic phase bound is relative to desired x[rowStart+j*ratio]. It is
% separate from finite-window interpolation, which these periodic tones do
% not test for arbitrary measured broadband input.
audit=struct('pass',all([blocks.pass])&&tonePass, ...
    'measured_energy_conservation',blocks, ...
    'power_relative_L2_tolerance',relativeTolerance,'power_peak_relative_tolerance',maxTolerance, ...
    'V_double_unitarity_relative_frobenius_error',unitaryErrorDouble, ...
    'V_single_unitarity_relative_frobenius_error',unitaryErrorSingle, ...
    'fft_tone_sign_pass',tonePass,'fft_tone_max_absolute_error',maxToneError, ...
    'fft_tone_absolute_tolerance',toneTolerance, ...
    'opposite_sign_control_max_relative_error',maxOppositeError, ...
    'tone_results',toneResults,'fft_length',nfft,'guard_samples',guard, ...
    'native_to_grid_step',ratio,'midpoint_affine_max_timing_error_samples',maxTimeError, ...
    'midpoint_affine_nyquist_phase_bound_rad',maxPhaseBound, ...
    'measured_row_fractional_advance_range',[min(delta) max(delta)], ...
    'measured_input_modified',false,'main_processing_modified',false, ...
    'energy_identity',"sum_j |X*v_j/sqrt(K)|^2 = sum_k |X_k/sqrt(K)|^2 for unitary V; saved measured maps are checked pixelwise.", ...
    'fft_sign_identity',"IFFT(FFT(x).*exp(+j2pi*nu*delta)) evaluates x[n+delta] on the periodic bandlimited FFT grid.", ...
    'inspection',"The positive FFT phase and guard+(1:N) indices match the intended fractional advance. Within-row affine resampling is a documented midpoint approximation.", ...
    'limits',["The tone check verifies sign, complex-frequency convention and crop indexing, not arbitrary broadband finite-window interpolation error."; ...
    "The energy check verifies the full PCA basis only; a selected subset is expected to discard power."; ...
    "These checks establish numerical consistency, not signal identification or reconstruction quality."]);
fid=fopen(fullfile(out,'numerical_audit.json'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));fwrite(fid,jsonencode(audit,'PrettyPrint',true),'char');
fprintf('PCA numerical audit: energy pass %d, FFT-sign pass %d, tone max error %.3g, timing bound %.3g samples.\n', ...
    all([blocks.pass]),tonePass,maxToneError,maxTimeError);
end
