# Periodic templates, harmonic indexing, and bounded-memory stitching

2026-10-23. Numerical model review only; no MATLAB execution or smartphone IQ processing by this reviewer. This note derives a practical extension of Chapter 5. The chapter itself does not specify the following Floquet-index estimator.

## 1. What a measured frame phase actually identifies

Use physical time t in seconds, a source frame period T_b for recording b, and normalized source time u=t/T_b. Suppose the downconverted record satisfies, over the analysed interval,

\[
z_b(t+T_b)=e^{j\theta_b}z_b(t).
\]

Define alpha_b=theta_b/(2 pi) in a fixed principal interval, for example [-1/2,1/2). Then

\[
p_b(u)=z_b(T_bu)e^{-j2\pi\alpha_bu}
\]

is periodic with period 1. Its Fourier coefficients P_b[k] obey

\[
z_b(t)=\sum_{k\in\mathbb Z}P_b[k]
\exp\{j2\pi(k+\alpha_b)t/T_b\}.
\]

Thus local bin k represents **baseband frequency (k+alpha_b)/T_b**, not k/T_b before the phase factor is removed. With a calibrated actual receiver LO L_b, its physical RF frequency is L_b+(k+alpha_b)/T_b. With only nominal center fc_b, that RF value is only nominal.

For R raw frames the consistent estimate is

\[
\widehat p_b(u)=\frac1R\sum_{r=0}^{R-1}
z_b(T_b(r+u))e^{-j2\pi\alpha_b(r+u)}.
\]

Correcting only r*theta aligns frame boundaries but leaves exp(j theta u) within the frame. Multiplying only exp(-j theta u) without the frame-index correction does not coherently average different frames. Independent per-frame fitted phases can be useful, but their fitted values and prediction residuals must be retained instead of assuming a single linear advance model fitted the data.

The relation z(t+T)=exp(j theta)z(t) must be **tested on held-out samples**. It is not guaranteed by a high peak in the magnitude autocorrelation. A mixture of components with different phase advances is not one Floquet-periodic signal. Strong clock/driver clutter can dominate a fitted theta while the information-bearing component follows another advance.

## 2. Exact global harmonic-bin map

Assume a common emitted waveform, after clock normalization, has one Floquet class

\[
s(u)=e^{j2\pi\kappa u}\sum_m C[m]e^{j2\pi m u}.
\]

Here kappa is a common fractional RF phase advance per frame, in cycles/frame. Strict frame-periodic RF has kappa=0; that is a hypothesis, not a consequence of a static screenshot. DSI burst timing and an independent panel clock can violate the single-class assumption.

With actual LO L_b and affine source time u=t/T_b, the recording has frequencies

\[
f_{bb,b}(m)=\frac{m+\kappa}{T_b}-L_b.
\]

Therefore there is an integer q_b satisfying

\[
\alpha_b=\kappa-L_bT_b+q_b,
\qquad q_b=L_bT_b+\alpha_b-\kappa\in\mathbb Z.
\]

After the measured phase advance is removed, local and global Fourier indices are related by

\[
\boxed{m=k+q_b.}
\]

To synthesize around requested RF reference fc_ref at a common source period T_ref, choose

\[
q_{ref}=\operatorname{round}(f_{c,ref}T_{ref}-\kappa),
\qquad
\alpha_{ref}=\kappa-f_{c,ref}T_{ref}+q_{ref}.
\]

Deposit band coefficient P_b[k] into periodic composite bin

\[
\boxed{j=k+q_b-q_{ref}.}
\]

Then the baseband output is

\[
y(t)=e^{j2\pi\alpha_{ref}t/T_{ref}}
\sum_j Q[j]e^{j2\pi j t/T_{ref}},
\]

and its physical-frequency label is

\[
f_{out}(j)=\frac{j+\alpha_{ref}}{T_{ref}}
=\frac{m+\kappa}{T_{ref}}-f_{c,ref}.
\]

This is the exact harmonic map under the stated model. It is **not generally** round((fc_b-fc_ref)*T_ref): different measured T_b and alpha_b matter. Mapping to one T_ref rescales the source's RF clock as well as its envelope clock. Usable band support must therefore be tracked using the accepted m indices, not forced back onto nominal centers after the mapping.

An unknown initial source time contributes a phase ramp over m; receiver phase/gain contributes a complex scalar. With p_b shifted in u by d, use a ramp exp(+j2 pi k d) in its local coefficients and fit a scalar phase. Using m instead of k changes only the scalar exp(j2 pi q_b d), which must be accounted for consistently.

## 3. What is and is not identifiable

### 3.1 Modulo-frame-rate ambiguity

The observed theta identifies phase advance only modulo 2 pi. Alpha+integer h gives the same interframe phase and reindexes the periodic template by h. In frequency units this is an ambiguity of h/T_b, approximately h*60 Hz.

An apparent CFO estimated from one-frame phase differences cannot distinguish such integer branches. A whole-frame projection onto periodic harmonics can make a component look coherent because periodicity has been imposed; this is not evidence that the selected branch is physically correct.

Nominal fc_b plus T_b is not a perfect branch label when actual LO error is unknown. Nearest-integer q_b is safe only if the combined uncertainty in L_b*T_b+alpha_b-kappa is below 1/2 cycle and the common-class model is valid. Examples, not hardware specifications:

- At T=1/60 s, an LO uncertainty of 30 Hz already contributes 1/2 cycle.
- At L=700 MHz, period uncertainty 0.714 ns contributes 1/2 cycle; at Fs=124.0828 MS/s that is approximately 0.0886 input samples/frame.
- A nominal ppm error at hundreds of MHz can span many 60 Hz branches.

### 3.2 Do not double-correct fractional CFO

If theta_b is correctly estimated from the actual record, multiplying exp(-j theta_b(r+u)) already removes the measured LO/source **fractional modulo-fv** phase advance. The fractional part of fc_b*T_b+alpha_b need not be equal across bands when the nominal fc differs from actual LO.

Consequently, computing that fractional mismatch and applying a second arbitrary within-frame derotation to force it to a common kappa is not a valid independent CFO estimator. It can double-correct the phase or manufacture apparent agreement. Retain the measured alpha, then resolve integer q differences and any remaining estimation error using overlap evidence.

### 3.3 Practical branch resolution

1. Fix one band's q as a global gauge; absolute RF phase/frequency accuracy still depends on hardware calibration. Keep that uncertainty explicit.
2. Build an integer branch search around nominal q differences. The search range comes from LO readback/clock uncertainty and period-estimation uncertainty, not an unbounded maximum-coherence search.
3. For each candidate integer shift, compare only the physical overlap and allow the Chapter 5 nuisance parameters: a common delay and scalar phase (optionally a separately labelled gain fit). Do not fit independent phase per Fourier bin.
4. Fit on one raw-time subset and score another. Store the winning and runner-up scores, delay, phase residual, effective signal bandwidth and the range of integer shifts tested.
5. A single dominant tone, a row comb, or this screen's repeated identical text rows may leave several delay/branch hypotheses indistinguishable. Report ambiguity rather than claim the maximum is uniquely correct. Hold-out data from the same static signal may not break a genuine symmetry; broad informative bins or another independent pattern/reference are needed.
6. The 11 nominal bands form a **chain** of 10 positive-overlap edges; second-neighbor bands only meet at nominal endpoints. There is no redundant positive-bandwidth graph cycle. Reversing the same pair estimates is a computational consistency check, not independent loop-closure evidence.

A general one-class model has a global common phase/frequency gauge. Choosing kappa=0 as a synthesis convention can be acceptable for an envelope image, but it must not be described as measuring the true absolute RF phase or proving the emitted signal is exactly frame-periodic.

## 4. Time warping must preserve the LO phase model

Let u be normalized source time and let t_b(u) be the actual input sample time at that source coordinate. The raw model is

\[
z_b(t_b(u))=s(u)e^{-j2\pi L_b t_b(u)}
\]

up to source shift/channel/gain. To obtain a periodic local template at index origin q_b, the exact correction is

\[
\boxed{
p_b(u)=z_b(t_b(u))
\exp\{j2\pi L_b t_b(u)-j2\pi(q_b+\kappa)u\}.
}
\]

For t_b(u)=T_bu this reduces to exp(-j2 pi alpha_b u). For nonlinear warping t_b(u)=T_bu+delta_t_b(u), it additionally contains

\[
\exp\{j2\pi L_b\delta t_b(u)\}.
\]

This is easy to miss when resampling downconverted IQ onto a common frame grid. Warping the baseband alone also warps its LO term. A constant fractional timing adjustment per frame is absorbed by a global phase adjustment; a frame-length change proportional to u creates a within-frame phase slope and is not absorbed by one constant.

Use a numerically stable equivalent that evaluates the small difference delta_t and reduced phase modulo 2 pi, rather than subtracting huge nearly equal carrier phases. Nominal fc can approximate L in the **small delta_t correction** if the residual error is bounded; retain an error bound |delta_L * delta_t| in cycles. This approximation does not justify using nominal fc to resolve the large integer q ambiguity without validation.

If the target and clutter follow different source clocks, no single t_b(u), kappa or theta fits both. A shared warp is then a modelling choice whose effect on each component must be tested.

## 5. Residual CFO and drift checks after the model fit

- Before averaging: estimate phase increments over raw frames; inspect linearity, circular residuals and whether different within-frame ROIs give the same theta. Predict phases in held-out frames.
- For a candidate pair: after accepted branch and coarse delay, form short-window cross products in the overlap. A residual slope in phase versus raw time suggests relative CFO or time-varying path phase. Estimate it over enough time to break phase wrapping; a short-window search is needed if a long integration is already cancelled.
- A residual phase slope versus **frequency** suggests delay. A changing delay versus raw time suggests sample-rate/source-time drift. These are different regressors.
- Do not infer a residual CFO from one already-folded average alone: its time evolution has been discarded. Keep per-frame or per-block complex correlations, or reopen immutable raw segments.
- Use a common phase-error budget to select block length. For at most pi/6 accumulated phase error, |delta_f|*T_block < 1/12. This is a chosen engineering budget, not a universal detection threshold.
- Recovered text, overlap coherence and source-clock fit are separate outcomes. A fit that produces a stable stripe-only template has not demonstrated text recovery.

## 6. Bounded-memory implementation for the present sample rate

Input Fs=124.0828 MS/s is the rate supplied by root for this review. The following sizes assume fv close to60 Hz; substitute measured values.

- One frame contains about2,068,046.7 complex input samples, approximately8.27 MB of interleaved int16 I/Q.
- A periodic band grid N_band=2^21 gives a template sampling rate N_band/T≈125.829 MS/s. It can represent a120 MHz band with a small guard. Resample with a validated complex anti-imaging/anti-aliasing kernel; the rational ratio need not be constructed as a huge exact LCM.
- One complex-single N_band vector is16 MiB. Process one band at a time and accumulate separate train/held-out complex sums plus AM controls. Do not retain all raw frames.
- Persist each accepted band's complex coefficients, T_b, alpha_b, valid-bin support, phase/time model and quality flags. Eleven band spectra at this grid require roughly176 MiB on disk in complex single, before metadata/controls.
- A complex-baseband union of720 MHz needs N_out/T_ref >720 MHz plus guard. N_out=2^24 at60 Hz gives Fs_out≈1.00663 GS/s; one complex-single composite is128 MiB. This is an efficient equivalent frequency-placement convention, **not** the paper's positive-analytic fs=2B grid.
- Literal paper positive-analytic support0…720 MHz needs Fs_out≥1.44 GS/s. N_out=2^25 gives Fs_out≈2.01327 GS/s at60 Hz, one complex-single vector256 MiB. Alternatively use a suitable mixed-radix N_out near2BT_ref with guards. If the chosen Fs_out differs from2B, evaluate each digital Butterworth response using the **actual** Fs_out and record that variation; do not claim an identical literal-W8 response.
- To reproduce the exact paper response with its reference Fs_paper=2B while synthesizing on a different sufficient grid, evaluate the continuous-frequency response formula using Fs_paper on the physical frequencies, then label it as sampled paper frequency response. It is not the same as redesigning a digital filter at the new grid rate.
- Read each band spectrum, place only accepted bins by integer j=k+q_b-q_ref, apply weights and accumulate into one output. No 11-by-N_out array is needed. Keep weights real single and allocate one at a time. MATLAB FFT workspace and implicit double promotion can multiply memory use, so estimate peak memory rather than only the output array size.
- To obtain an image, perform one inverse FFT for each selected case, evaluate its restored alpha_ref phase if phase output is needed, raster/crop the valid source coordinates, then release that case before the next. Cache coefficients/edge estimates instead of recomputing raw registration for all55 contiguous groups.

For validation, a pair first needs only180 MHz coverage. Keep the expensive full720 MHz IFFT until adjacent registrations have useful support. A provisional full-chain diagnostic can still be generated, but failed/ambiguous edges must remain visibly labelled.

## 7. Minimal implementation contract

Input to synthesis should explicitly contain: N_band, T_b, alpha_b, q_b or candidate list, train/test coefficient vectors, true/nominal LO distinction, usable global m support, delay/phase/gain calibration, source clock model, frame mask, and model quality flags. The synthesis function should not infer an RF harmonic map from center frequencies alone or normalize every overlap independently until it looks coherent.

The strongest practical reduction is valid when the raw data support one frame-periodic complex waveform up to predictable phase/time changes. If that model fails, the reduction has discarded information necessary for stitching; use shorter raw-time blocks, multiple source classes or an explicitly unsuccessful result instead of creating coherence by projection.
