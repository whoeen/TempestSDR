function metadata = explainFamGraphs27(resultRoot, outputDir)
%EXPLAINFAMGRAPHS27 Explain measured FAM coordinates with visible MATLAB plots.
% METADATA = EXPLAINFAMGRAPHS27(RESULTROOT,OUTPUTDIR) reads the existing
% rf78_block1 FAM and anti-aliased IQ results. It creates two figures, PNG
% exports, editable FIG files, a numerical MAT file and a JSON record.
% It does not reread/modify the raw recording, change the user's workspace,
% close existing figures, or claim packet identification.
% The educational FFT below reproduces the original finite channel-pair
% calculation. PSD is calculated separately with Signal Processing Toolbox
% pwelch. Existing FAM search maxima and fixed-pair results are distinguished.
arguments
    resultRoot (1,1) string
    outputDir (1,1) string
end

sourceDir = fullfile(resultRoot,"refined","rf78_block1");
famPath = fullfile(sourceDir,"fam.mat");
iqPath = fullfile(sourceDir,"subband.mat");
assert(isfile(famPath) && isfile(iqPath), ...
    'explainFamGraphs27:MissingInput','Existing FAM and subband files are required.');
if ~isfolder(outputDir)
    mkdir(outputDir);
end
names = ["fam_01_overview.png","fam_01_overview.fig", ...
    "fam_02_pair_mapping.png","fam_02_pair_mapping.fig", ...
    "fam_explanation_metadata.json","fam_explanation_data.mat"];
for ii = 1:numel(names)
    assert(~isfile(fullfile(outputDir,names(ii))), ...
        'explainFamGraphs27:ExistingOutput','Refuse overwrite: %s',names(ii));
end

loaded = load(famPath,'result','context');
wave = load(iqPath,'iq','front');
r = loaded.result;
context = loaded.context;
fsHz = double(r.metadata.fs_hz);
M = double(r.metadata.M);
L = double(r.metadata.L);
P = double(r.metadata.P);
assert(M==32 && L==8 && P==131072 && fsHz==7755175, ...
    'explainFamGraphs27:UnexpectedGrid','This explanation targets the measured 32/8/131072 grid.');
assert(string(r.metadata.options.ChannelWindow)=="hamming" && ...
    string(r.metadata.options.SlowWindow)=="rectangular", ...
    'explainFamGraphs27:UnexpectedWindow','Expected symmetric Hamming and rectangular windows.');
need = (P-1)*L+M;
x = double(wave.iq(1:need));
x = x(:);
assert(all(isfinite(x)),'explainFamGraphs27:Nonfinite','IQ contains nonfinite values.');
dfHz = fsHz/M;
daHz = fsHz/(P*L);
rfCenterHz = double(context.nominal_center_hz);
familyGridHz = 112802.43787765503;
foldRefinedHz = 112802.5501974424;

% Reproduce only channels 5, 6 and 7; no M-by-M-by-P array is allocated.
channelK = [5;6;7];
a = 0.54-0.46*cos(2*pi*(0:M-1).'/(M-1));
D = complex(zeros(numel(channelK),P));
batchSize = 512;
for first = 1:batchSize:P
    rr = first:min(P,first+batchSize-1);
    starts = (rr-1)*L;
    indices = (0:M-1).'+starts+1;
    U = fftshift(fft(x(indices).*a,[],1),1);
    phase = exp(-2i*pi*mod(channelK*starts,M)/M);
    D(:,rr) = U(channelK+M/2+1,:).*phase;
end
q = (-P/2:P/2-1).';
residualHz = q*daHz;
pairSpecs = [5 5 15252;7 6 -2264];
pairs = repmat(struct(),2,1);
pairData = repmat(struct(),2,1);
for pp = 1:2
    k = pairSpecs(pp,1); ell = pairSpecs(pp,2); qPeak = pairSpecs(pp,3);
    dk = D(channelK==k,:).';
    dl = D(channelK==ell,:).';
    product = dk.*conj(dl);
    denominator = sqrt(sum(abs(dk).^2)*sum(abs(dl).^2));
    cyclic = fftshift(fft(product))/denominator;
    alpha0Hz = (k-ell)*dfHz;
    alphaHz = alpha0Hz+residualHz;
    peakIndex = qPeak+P/2+1;
    peakValue = cyclic(peakIndex);
    previous = r.nc.top_candidates;
    matches = [previous.k_bin]==k & [previous.l_bin]==ell & [previous.q_bin]==qPeak;
    assert(nnz(matches)==1,'explainFamGraphs27:CandidateMissing', ...
        'Expected fixed candidate k=%d l=%d q=%d.',k,ell,qPeak);
    previousValue = previous(matches).pair_coherence_complex;
    replayError = abs(peakValue-previousValue);
    assert(replayError<1e-10,'explainFamGraphs27:ReplayMismatch', ...
        'Fixed-pair replay differs from saved result by %.3g.',replayError);
    pairs(pp).k = k;
    pairs(pp).l = ell;
    pairs(pp).q = qPeak;
    pairs(pp).channel1_rf_hz = rfCenterHz+k*dfHz;
    pairs(pp).channel2_rf_hz = rfCenterHz+ell*dfHz;
    pairs(pp).rf_pair_midpoint_hz = rfCenterHz+(k+ell)*dfHz/2;
    pairs(pp).coarse_difference_hz = alpha0Hz;
    pairs(pp).residual_hz = residualHz(peakIndex);
    pairs(pp).alpha_hz = alphaHz(peakIndex);
    pairs(pp).correlation_magnitude = abs(peakValue);
    pairs(pp).local_phase_rad = angle(peakValue);
    pairs(pp).saved_candidate_replay_absolute_error = replayError;
    pairs(pp).reference_fold_harmonic = pp;
    pairs(pp).reference_fold_harmonic_hz = pp*foldRefinedHz;
    pairs(pp).normalization = "Finite weighted channel-pair correlation; not SNR or pointwise population coherence.";
    excerpt = max(1,peakIndex-90):min(P,peakIndex+90);
    nTime = min(P,round(180e-6*fsHz/L)+1);
    pairData(pp).slow_time_us = (0:nTime-1).'*L/fsHz*1e6;
    pairData(pp).product_normalized = product(1:nTime)/sqrt(mean(abs(product).^2));
    pairData(pp).q = q(excerpt);
    pairData(pp).residual_hz = residualHz(excerpt);
    pairData(pp).alpha_hz = alphaHz(excerpt);
    pairData(pp).correlation_complex = cyclic(excerpt);
end

% Conventional PSD: density in ADC-counts^2/Hz, without one-sided doubling.
[psdValue,psdBasebandHz] = pwelch(x,hamming(4096,'periodic'),2048,4096,fsHz,'centered');
psdRfMHz = (rfCenterHz+psdBasebandHz)/1e6;
psdDb = pow2db(max(psdValue,realmin));

fig1 = figure('Name','Measured FAM: PSD, cyclic map and frequency grid', ...
    'NumberTitle','off','Color','w','Visible','on','Position',[70 70 1420 900]);
layout1 = tiledlayout(fig1,2,2,'TileSpacing','compact','Padding','compact');
title(layout1,'iPhone 6 | fc = 100 MHz recording | RF 78 MHz subband | measured block at 0.2 s', ...
    'FontWeight','bold','FontSize',14);

ax = nexttile(layout1,1);
plot(ax,psdRfMHz,psdDb,'LineWidth',1.2,'Color',[0.10 0.32 0.66]);
hold(ax,'on');
for pp = 1:2
    xline(ax,pairs(pp).rf_pair_midpoint_hz/1e6,'--',sprintf('P%d',pp), ...
        'LabelOrientation','horizontal','FontSize',9);
end
hold(ax,'off');
xlabel(ax,'Nominal RF frequency (MHz)');
ylabel(ax,'PSD (dB re 1 ADC count^2/Hz)');
title(ax,'A. Welch PSD: where the received energy lies');
grid(ax,'on');
xlim(ax,rfCenterHz/1e6+[-3.2 3.2]);

ax = nexttile(layout1,2);
hm = r.nc.heatmap;
imageObject = imagesc(ax,hm.alpha_hz/1e3,(rfCenterHz+hm.f_hz)/1e6,hm.max_pair_coherence);
set(imageObject,'AlphaData',double(hm.counts>0));
set(ax,'YDir','normal','Color',[0.93 0.93 0.93]);
colormap(ax,parula(256));
clim(ax,[0 1]);
cb = colorbar(ax);
cb.Label.String = 'Max finite pair correlation in display cell';
hold(ax,'on');
scatter(ax,[pairs.alpha_hz]/1e3,[pairs.rf_pair_midpoint_hz]/1e6,70,'wo','LineWidth',1.5);
hold(ax,'off');
xlim(ax,[0 500]);
ylim(ax,rfCenterHz/1e6+[-3 3]);
xlabel(ax,'Cycle frequency \alpha (kHz)');
ylabel(ax,'Nominal RF pair midpoint (MHz)');
title(ax,'B. NC FAM: periodic spectral relationships (gray = no support)');

ax = nexttile(layout1,3);
plot(ax,r.nc.alpha_hz/1e3,r.nc.max_pair_coherence,'LineWidth',1,'Color',[0.13 0.43 0.66]);
hold(ax,'on');
for order = 1:4
    xline(ax,order*familyGridHz/1e3,':',sprintf('%dF',order), ...
        'Color',[0.72 0.23 0.11],'LabelVerticalAlignment','middle');
end
hold(ax,'off');
xlim(ax,[0 500]);
ylim(ax,[0 1]);
xlabel(ax,'Cycle frequency \alpha (kHz)');
ylabel(ax,'max over tested pairs |C_{kl}(q)|');
title(ax,'C. Cyclic-domain profile: maxima are discovery statistics');
grid(ax,'on');

ax = nexttile(layout1,4);
around = abs(r.nc.alpha_hz-familyGridHz)<=8.1*daHz;
stem(ax,r.nc.alpha_hz(around)-familyGridHz,r.nc.max_pair_coherence(around), ...
    'filled','MarkerSize',4,'Color',[0.13 0.43 0.66]);
hold(ax,'on');
xline(ax,0,'--','FAM grid peak','Color',[0.35 0.35 0.35], ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','middle');
xline(ax,foldRefinedHz-familyGridHz,'--','Training power-fold refinement', ...
    'Color',[0.78 0.25 0.08],'LabelHorizontalAlignment','right');
hold(ax,'off');
xlabel(ax,sprintf('Offset from %.9f Hz (Hz)',familyGridHz));
ylabel(ax,'max over tested pairs |C_{kl}(q)|');
title(ax,sprintf('D. Grid spacing %.6f Hz; fold refinement is a different estimate',daHz));
grid(ax,'on');
ylim(ax,[0 0.85]);

fig2 = figure('Name','Measured FAM: channel product to cycle frequency', ...
    'NumberTitle','off','Color','w','Visible','on','Position',[100 100 1550 890]);
layout2 = tiledlayout(fig2,2,3,'TileSpacing','compact','Padding','compact');
title(layout2,{'Measured fixed-pair calculation: D_k(r)D_l^*(r) -> slow-time FFT -> cyclic coordinates', ...
    '\alpha = (k-l)F_s/M + qF_s/(PL),   f_{RF} = 78 MHz + (k+l)F_s/(2M)'}, ...
    'Interpreter','tex','FontSize',13,'FontWeight','bold');
for pp = 1:2
    p = pairs(pp);
    data = pairData(pp);
    ax = nexttile(layout2,3*(pp-1)+1);
    plot(ax,data.slow_time_us,real(data.product_normalized),'LineWidth',1.1);
    hold(ax,'on');
    plot(ax,data.slow_time_us,imag(data.product_normalized),'LineWidth',1.0);
    hold(ax,'off');
    xlabel(ax,'Slow time rL/F_s (\mus)');
    ylabel(ax,'Channel product / RMS');
    title(ax,sprintf('Pair %d: k=%d, l=%d | f_{RF}=%.6f MHz', ...
        pp,p.k,p.l,p.rf_pair_midpoint_hz/1e6));
    legend(ax,{'real','imaginary'},'Location','best');
    grid(ax,'on');

    ax = nexttile(layout2,3*(pp-1)+2);
    plot(ax,data.residual_hz/1e3,abs(data.correlation_complex),'.-', ...
        'MarkerSize',7,'Color',[0.10 0.37 0.65]);
    hold(ax,'on');
    xline(ax,p.residual_hz/1e3,'--',sprintf('q=%d',p.q),'Color',[0.70 0.25 0.10]);
    hold(ax,'off');
    xlabel(ax,'Residual frequency qF_s/(PL) (kHz)');
    ylabel(ax,'|C_{kl}(q)|');
    title(ax,sprintf('Slow-time FFT: residual = %.6f kHz',p.residual_hz/1e3));
    grid(ax,'on');

    ax = nexttile(layout2,3*(pp-1)+3);
    plot(ax,data.alpha_hz/1e3,abs(data.correlation_complex),'.-', ...
        'MarkerSize',7,'Color',[0.10 0.37 0.65]);
    hold(ax,'on');
    xline(ax,p.alpha_hz/1e3,'--',sprintf('\\alpha=%.6f kHz',p.alpha_hz/1e3), ...
        'Color',[0.70 0.25 0.10],'LabelHorizontalAlignment','left');
    xline(ax,p.reference_fold_harmonic_hz/1e3,':','power-fold reference', ...
        'Color',[0.25 0.50 0.20],'LabelHorizontalAlignment','right');
    hold(ax,'off');
    xlabel(ax,'Mapped cycle frequency \alpha (kHz)');
    ylabel(ax,'|C_{kl}(q)|');
    title(ax,sprintf('Add (k-l)F_s/M = %.6f kHz',p.coarse_difference_hz/1e3));
    grid(ax,'on');
end
drawnow;

exportgraphics(fig1,fullfile(outputDir,names(1)),'Resolution',160);
savefig(fig1,fullfile(outputDir,names(2)));
exportgraphics(fig2,fullfile(outputDir,names(3)),'Resolution',160);
savefig(fig2,fullfile(outputDir,names(4)));

metadata = struct();
metadata.status = 'complete';
metadata.source_kind = 'Measured recording; no synthetic signal in these figures.';
metadata.fam_input = char(famPath);
metadata.subband_input = char(iqPath);
metadata.raw_filename = wave.front.read.filename;
metadata.raw_bytes = wave.front.read.bytes;
metadata.raw_storage = wave.front.read.disk_dtype;
metadata.native_fs_hz = wave.front.native_fs_hz;
metadata.subband_fs_hz = fsHz;
metadata.subband_center_hz = rfCenterHz;
metadata.first_original_sample_zero_based = context.first_sample_zero_based;
metadata.M = M; metadata.L = L; metadata.P = P;
metadata.input_samples = need;
metadata.channel_window = 'Symmetric Hamming, length 32';
metadata.slow_window = 'Rectangular, length 131072';
metadata.channel_spacing_hz = dfHz;
metadata.alpha_spacing_hz = daHz;
metadata.channel_window_seconds = M/fsHz;
metadata.slow_hop_seconds = L/fsHz;
metadata.slow_fft_duration_seconds = P*L/fsHz;
metadata.fam_grid_family_hz = familyGridHz;
metadata.training_power_fold_frequency_hz = foldRefinedHz;
metadata.fold_minus_grid_hz = foldRefinedHz-familyGridHz;
metadata.pairs = pairs;
metadata.heatmap_empty_cells_masked = true;
metadata.heatmap_display_reduction = 'Max of supported estimates in each display cell';
metadata.cdp_definition = 'Maximum finite channel-pair correlation magnitude over tested pairs';
metadata.spectral_coherence_caveat = 'Finite channel windows and channel-energy denominator; not a pointwise population spectral coherence estimator.';
metadata.packet_identified = false;
metadata.cfo_or_timing_correction_applied_here = false;
metadata.output_files = cellstr(fullfile(outputDir,names));
metadata.reference_url = 'https://cyclostationary.blog/2018/06/01/csp-estimators-the-fft-accumulation-method/';
metadata.matlab_version = version;
numerical = struct('psd_rf_hz',rfCenterHz+psdBasebandHz,'psd_density',psdValue, ...
    'cdp_alpha_hz',r.nc.alpha_hz,'cdp_max_pair_correlation',r.nc.max_pair_coherence, ...
    'pair_data',pairData,'metadata',metadata);
save(fullfile(outputDir,names(6)),'numerical','metadata','-v7');
fid = fopen(fullfile(outputDir,names(5)),'wt','n','UTF-8');
assert(fid>=0,'explainFamGraphs27:CannotWrite','Cannot write metadata JSON.');
fileCloser = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(metadata,'PrettyPrint',true));
clear fileCloser
fprintf('Measured FAM explanation saved to %s. Pair replay errors: %.3g, %.3g.\n', ...
    outputDir,pairs(1).saved_candidate_replay_absolute_error,pairs(2).saved_candidate_replay_absolute_error);
end
