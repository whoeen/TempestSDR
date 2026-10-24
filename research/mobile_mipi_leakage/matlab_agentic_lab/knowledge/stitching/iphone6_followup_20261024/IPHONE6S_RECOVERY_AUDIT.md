# iPhone 6s prior recovery audit — 2026-10-24

Scope: read-only audit of repository history, MATLAB code, recorded CSV/JSON and saved images. MATLAB execution belongs to the parent agent and was not performed for this audit. New ablation code is authored but unexecuted. Repository reviewed at bd1a09d; prior recovery commit d943f38 precedes sweep commit f1525a4. File references below are relative to matlab_agentic_lab unless prefixed by ../. Line numbers refer to this checkout.

## 1. What the existing images actually establish

Direct visual inspection of results/iphone_recovery_20261023/iphone6s_P032/P032_comparison.png confirms the keypad circles, digits, several smaller key labels and lower controls in both nearest-AM and cubic-AM panels. The same 32-frame uncorrected complex average is nearly black on the fixed shared scale; global-phase and row-phase corrected averages recover the structure. In presentation_v2/iphone6s_P032_comparison.png, log display and contrast make the structures more prominent. Visible vertical stripes remain.

**Supported explanation:** this capture already contains recoverable UI structure with the established time raster; averaging reduces the visibly incoherent component; phase registration prevents destructive complex averaging. Cubic interpolation changes the sampled image but is not a necessary condition for the visible recovery: the same-N nearest control also succeeds. The record does not quantify how much interpolation increases image fidelity.

This is a single 311 MHz iPhone 6s capture. The newer iPhone 6 experiment uses 11 separately retuned recordings, a different screen pattern and receiver passband. The older recovery did not solve the cross-recording relative RF phase/clock/harmonic-map problem required by stitching. A clearer old image does not establish that any failed sweep algorithm step is unnecessary.

## 2. Capture identity and timing

| Quantity | Recorded value | Exact evidence |
|---|---:|---|
| Input | Desktop/mobile/0625/311m_55.05487m_20m.rIs | signal_processing/mobileBaselineConfig.m:23 |
| File size | 1,069,200,000 bytes; verified by file stat in this audit | Existing knowledge/signal_processing/iphone6s_audit_20261023.md:21–31; current stat |
| Complex samples | 267,300,000 | bytes/4 |
| Format | Headerless BE int16 I,Q; complex I+jQ, single ADC counts | signal_processing/readRisIqBlock.m:20–32 |
| Stored Fs | 55.054870 MS/s | mobileBaselineConfig.m:24 |
| RF center / nominal receiver BW | 311 MHz / 20 MHz | mobileBaselineConfig.m:24 |
| Frame count | 32 distinct stored-frame offsets | extendIphoneRecovery.m:5,20–26; frame_parameters.csv:2–33 |
| Prior line frequency | 112,613.234 Hz | mobileBaselineConfig.m:24 |
| Line period | 488.884547974175 samples; 8.879951001141 microseconds | metrics.json:47; Fs/fH |
| Prior frame period | 917,636.666798 samples; 59.996371104 Hz | metrics.json:46; Fs/frame period |
| Raster | 1877 rows x 750 columns | mobileBaselineConfig.m:24 |
| Active display | rows1400:1877 then1:856; columns1:750 =1334x750 | mobileBaselineConfig.m:25 |
| Samples/output raster column | 0.651846063965567 | metrics.json:45 |
| Virtual uniform raster rate | 84.4599255 MS/s | 750*fH; not a new acquisition rate or verified MIPI pixel clock |
| Shared amplitude limits | [40.14971923828125,194.93595886230469] counts | metrics.json:48–50 |

Fs/fc/BW come from filenames and prior records, not a header or instrument readback. Full raw SHA was not recomputed in this audit. The earlier manifest expectation is d55e8616140e4658f4fdf8bc7bfa63276fc17a9640121fea15952d25c9621af7. The raw file and the local 46,088,008-byte raster_final.mat both exist.

Line and frame values are independently retained prior fits: 1877*lineSamples=917636.296547527, differing from the prior frame period by0.370250473 samples. The original reconstruction samples each frame from its own origin; it does not require the last raster cell to close an exactly periodic complex frame. Treating that image pipeline as a wideband periodic stitching template would add a new assumption.

## 3. Exact earlier processing

1. Read each bounded raw interval without DC subtraction or gain normalization: compareRasterAverages.m:204–211 and readRisIqBlock.m:20–32. This differs from ../coherent_hsv_resampling.py:468, which removes its block complex mean; that Python pipeline's Apple example is a separate iPhone6/238 MHz capture, as its metrics source path confirms.
2. Set the first zero-based origin to4 samples plus any configured column offset; subsequent nominal origins use the prior fractional frame period: compareRasterAverages.m:14–18,54. Evaluate each row/column at a fractional complex sample position: lines36–37,204–210. Four-point Catmull–Rom is explicitly implemented in sampleFractionalRaster.m:17–26; nearest rounds the **same** fractional coordinate in lines12–15. Neither path independently estimates a pixel clock.
3. Estimate per-frame horizontal shift from the full-row mean amplitude profile against frame1, search ±24 columns, parabolic sub-column refinement, then reread at origin-shift*step: compareRasterAverages.m:56–69,221–238. Saved frame2–32 shifts are −0.669980137…+0.485807996 columns, mean−0.134944830; profile correlation before correction is0.98544555…0.99580486 (mean0.99207054). Therefore this capture's prior time grid was already close at the measured profile level.
4. Form global scalar phase from the summed complex cross product; also form a row-linear phase fit using alternate training rows selected before unwrapping. Apply each and retain uncorrected complex and AM controls: compareRasterAverages.m:71–117. Minimum coherence0.1, at least16 fit rows, condition limit1000. No fallback occurred in the P32 run (metrics.json:54–57).
5. The row-fit held-out mixture coherence is0.716607119…0.835111994 across frames2–32, mean0.769312512; frame1 is a self-reference and excluded from these statistics. Horizontal alignment and the reference share all rows, so this is partial parameter holdout, not independent image validation.
6. Use frame1 active-crop amplitude1/99 percentiles for all main comparison panels and checkpoints: compareRasterAverages.m:62,155–177. Save am/nearestAm/coherent/globalCoherent/uncorrected in raster_final.mat at lines182–183.

Git diff d943f38..bd1a09d is empty for mobileBaselineConfig.m, sampleFractionalRaster.m and compareRasterAverages.m. The 6s P32 run simply extends the prior baseline to32 frames (extendIphoneRecovery.m:20–26); it is not a newly fitted line/DDR/byte-rate reconstruction.

## 4. What can be attributed, and what cannot

| Comparison | Existing same-frame evidence | Inference supported / limitation |
|---|---|---|
| No phase vs global phase, P32 |68.5292282 vs6288.54 count^2; metrics.json:38–39 |91.764x coherent power,19.62674dB less cancellation on the received mixture. Not a measured desired-signal SNR or fidelity gain. |
| Global vs row-linear phase, P32 |6288.54 vs6282.96289 count^2; metrics.json:39–40 |Row fit is0.003853dB lower in this statistic; no demonstrated advantage over global correction. |
| Nearest vs cubic, P32 |Both visibly recover; relative AM RMS difference0.166231245; metrics.json:42 |A difference measure, not an accuracy gain. Interpolation also changes frequency response/amplitude, even with identical gain. |
| P8→P16→P32 |AM odd/even correlation .899234078→.942830184→.967616608; metrics.json:16,26,36 |Repeatability improves with increasing N. Stable clutter also contributes; N differs, so this is not an interpolation ablation. |
| Prior origin vs per-frame alignment |No saved disable-alignment arm located |Its separate contribution is presently unquantified. Existing small corrections make a large timing rescue implausible, but do not prove zero benefit. |
| P8 baseline vs first8 of P32 |P8 metrics numerically identical:6417.67236 global power,6408.08398 row power,.899234078 AM correlation |Consistent replay of the same processing; not independent replication/new capture. |
| Display processing |finalizeIphoneRecovery.m:39–49,95–96 |log1p, separate1/99% scaling, optional subtraction of column mean. These can make digits look clearer without adding measured bandwidth. |

For the6s presentation, the pre-existing crop is retained (finalizeIphoneRecovery.m:25–26). HSV uses globalCoherent phase referenced to the cropped complex sum, saturation based on |globalCoherent|/AM, amplitude15th percentile and consistency0.2 masks (lines43–49). Its value channel is log-AM display. It is not recovered RGB. The Pxxx comparison HSV instead uses row-fit coherent amplitude and consistency (compareRasterAverages.m:159–160), so those two HSV presentations are not identical signal products.

The older provided_restoration_analysis/iphone6s/P001–P200 figures belong to the historical family identified by ../README.md:16–26 as little-endian legacy generation. The current reader is big-endian. Do not combine those P200 pictures with these BE P32 metrics to calculate a resampling or phase improvement. The original reference is a photographed screen, not a registered ground-truth pixel array; no defensible PSNR/SSIM/OCR error rate is available from these records alone.

## 5. Minimal missing paired experiment — authored, not executed here

New code: auditIphone6sPairedTimingAblation.m. Call auditIphone6sPairedTimingAblation() for32 frames; FrameCount=8 may be used for a bounded replay check. It refuses an existing output folder.

Four AM-only arms use exactly the same stored frame indices:

| Origin model | Nearest | Cubic |
|---|---|---|
| Fixed prior frame origin, no horizontal correction |A |B |
| Saved per-frame aligned origin |C |D |

The two coordinates are read from one common raw block per frame; DC removal stays0, gain1, same reader/Fs/line/frame model/crop/fixed scale. No new phase fit, timing fit, content fitting or display enhancement is allowed. C versus D isolates interpolation conditional on the saved alignment; B versus D isolates saved timing correction conditional on cubic interpolation. A versus C checks whether the timing effect depends on interpolation. At N32 the driver records RMS replay agreement of C/D with saved nearestAm/am as an implementation gate. It saves raw-block hashes, origins, full AM arrays, odd/even arrays, count-domain metrics and shared-scale PNGs in a new results/iphone6_followup_20261024/iphone6s_paired_timing_P032 directory.

Active-crop AM and row-difference odd/even correlations are descriptive stability measurements. Row differences reduce a perfectly static column profile but do not establish source identity. The experiment estimates the conditional contribution of processing choices on this capture; it does not establish physical MIPI pixel mapping. Any later fidelity test should lock geometric registration/crop from a separate calibration and score the same text/key regions without per-arm nonrigid registration or contrast fitting.

## 6. Linkwitz–Riley implementation audit

**The executed sweep uses the steady-state periodic Fourier-series response of W8 L-R. It does not run a literal finite-record time-domain IIR/filtfilt pipeline.** The distinction matters at frame boundaries.

- runIphoneStitchExperiment.m:63–74 calls synthesizePeriodicBands with raised_cosine/guard3MHz and paper_lr_w8/guard0, reconstructs the complex waveform by IFFT*N, takes its magnitude, then explicitly anti-aliases that magnitude to the1100x1881 raster.
- synthesizePeriodicBands.m:65–72 defines Fs_filter=2*nominalUnionHz independently from the power-of-two synthesis Fs_grid. Lines135–147 form sequential weights; lrLow at222–227 evaluates L(f)=1/[1+(abs(tan(pi*f/Fs_filter))/tan(pi*fx/Fs_filter))^8], high=1−L. The first band has no incoming highpass; every earlier band accumulates the later lowpass factors. No weight-sum renormalization is performed.
- This is the squared magnitude of a fourth-order Butterworth at each harmonic. On a genuinely periodic complex signal with seam closure, multiplying those DFT coefficients gives its zero-phase circular steady-state response. The chapter audit explicitly limits equivalence to that condition: knowledge/stitching/iphone6_sweep_20261023/CHAPTER_ALGORITHM_AUDIT.md:119–139.
- Not implemented/executed: causal SOS states; forward/backward finite-block filtering; chosen filtfilt edge extension and initial conditions; padding sized by IIR impulse-response tail; overlap-save/add for nonperiodic records; an interior-region numerical comparison against literal IIR; a validated frame-seam equivalence test. Unit tests of frequency weights do not establish those missing conditions for measured data.
- Also different from a literal source pipeline: power-of-two output grid rather than exactly2B; periodic coefficient placement rather than the source rational resampling chain; branch-selected integer harmonic centers; overlap-only circular/fractional alignment. These changes were labelled in code metadata. Retaining Fs_filter=2B preserves the source digital weight curve, but does not by itself validate the periodic-template assumption.

Actual +polarity full11 result (results/iphone6_stitch_20261023/stitch_polarity_+1/group_100_700/paper_lr_w8_metrics.json, synthesis object): T=.01667515455004975s, nominal union719.997677381MHz, Fs_filter1439.995354762MS/s, Fs_grid2012.241139912MS/s, N=33,554,432, guard0. Minimum weight sum on supported bins=.5259019136, maximum1.0; periodic_boundary_assumption=true and output_rate_is_exact_source_2B=false. Its AM train/test correlation .5785171009 does not establish boundary equivalence or valid720MHz physical reconstruction. Some edge attenuation is expected from source L-R tails where the complementary recording is absent; preserving it is not a normalization bug.

A decisive next L-R check is a known periodic signal with repeated guard periods: compare the FFT weighting with fourth-order Butterworth forward/backward filtering after sufficient settling, excluding edges. Then test a deliberately nonperiodic phase seam to quantify the mismatch. Real data must pass its own seam/overlap checks before substituting the periodic response for finite-record filtering.


## 7. Added custom finite-record IIR audit — awaiting MATLAB execution

New driver auditLinkwitzRileyFiniteIir.m implements two explicit bilinear Butterworth4 biquads per branch, using Q values1/(2cos(pi/8)) and1/(2cos(3pi/8)). It calls base MATLAB filter() section by section, reverses the finite output, filters again and reverses back. Each outer pass starts from zero state. This is a custom forward/backward implementation, not MATLAB filtfilt and not a reconstruction of the thesis author's endpoint handling.

The nominal100/160 MHz pair sets Fs_filter=360 MHz and crossover90 MHz. Response checks independently evaluate the SOS transfer functions and compare their squared magnitudes against the analytic W8 weights. The measured-input option reads a bounded fc100 singleTrain excerpt and uses a declared finite windowed-sinc interpolation to the audit rate plus60 MHz analytic placement. Both filter methods receive the exact same prepared sequence; this does not validate the interpolator or perform RF alignment.

Periodic guards of0,1,2,4,8,16,32,64,128,256 samples at each end are tested on deterministic complex broadband data, an intentional nonperiodic seam, and the optional measured excerpt. The output records full-block, edge, interior and complementary-sum errors. At sufficient padding the custom IIR should converge to the periodic FFT response; without padding its boundary policy should differ. The driver saves artifacts and asserts tolerances, but it was not executed by this audit author. Only the parent agent's actual execution/result files can establish test success.


## 8. Parent-executed results subsequently inspected

The parent MATLAB owner executed both drivers successfully. This section supersedes the pending status in sections5 and7. Source evidence is results/iphone6_followup_20261024/iphone6s_paired_timing_P032/metrics.json and lr_finite_iir/audit.json, read directly after execution.

| Same32-frame arm | Active-crop AM odd/even r | Active-crop row-difference r |
|---|---:|---:|
| Fixed prior origin, nearest |0.908253789 |0.546109906 |
| Fixed prior origin, cubic |0.918020284 |0.647412843 |
| Saved per-frame alignment, nearest |0.882995386 |0.441922654 |
| Saved per-frame alignment, cubic |0.909019105 |0.638237535 |

On these fixed-crop stability proxies, cubic exceeds nearest with either origin policy, while the saved per-frame profile shifts reduce rather than improve repeatability. Thus the historical horizontal correction cannot be credited with the old6s image's precision based on this test. The rows are conditional same-capture comparisons; no original-image fidelity claim follows. The prior published .967616608 was computed over the full1877x750 raster, whereas this table uses the1334x750 active crop. Comparing those two numbers directly would conflate spatial support.

Replay relative RMS is5.05865e-8 for saved cubic and5.76131e-6 for saved nearest. Saved decimal origins are replayed rather than recalculated; nearest is discontinuous at half-sample boundaries. Alignment on/off changes the AM image by relative RMS .032562890(nearest) and .035491045(cubic). This difference magnitude is not an image improvement score.

The explicit IIR audit passed all recorded checks: LP+HP response-unity maximum error1.66533e-15; crossover amplitudes .4999999999999998 and .5000000000000001; maximum pole radius .6681786379192989. On the measured-template excerpt, unpadded lowpass relative RMS error versus circular FFT is .004789827, concentrated near the endpoints (edge .037285295, interior4.03047e-16). With256 periodic guard samples each side the full lowpass discrepancy falls to4.05106e-16 and highpass to7.24505e-16. This establishes actual custom SOS execution and periodic steady-state equivalence, including a measured input. It does not establish that a cut physical waveform actually repeats.

A further actual100+160 MHz pair driver, auditIphonePairLiteralIir.m, has been authored separately. It preserves the earlier failed overlap alignment and compares literal custom SOS execution with a matched FFT response at the **new actual synthesis rate** (~503MHz), not the prior ~360MHz source-rate response. Its execution/result status must be read from its own output audit; mere code existence is not execution evidence.
