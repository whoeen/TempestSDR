# Bounded iPhone pair TF controls

Read manifest.json and tf_metrics.csv before comparing colors. Native ADC, canonical prior-grid control, and corrected input are explicitly separate. Nominal RF axes follow caller IQ polarity metadata.

STFT colors are input-unit squared/Hz (complex two-sided PSD); FSST and CWT colors are their own magnitude relative to a shared maximum across both bands/states. Do not compare their color values.

FSST/CWT use an anti-aliased narrow subband and a bounded central excerpt. Only the STFT retains the original measured digital band. No extra RF bandwidth is synthesized by squeezing. The white CWT lines are the cone of influence; coefficients nearer zero offset than these lines can be edge-affected.

Phase is wrapped relative measured RF phase after the declared mixer; it is not reconstructed RGB or an absolute physical phase. The configured raw-amplitude quantile freezes a gate for both states (not a confidence level). Time correction can change the samples being compared, so phase change alone is not a CFO or clock estimate.

Numeric MATs contain TF magnitudes/PSD, phase vectors, filters, and parameters, without full raw capture copies. Each PNG uses identical shared scale limits for its transform across both bands and states.
