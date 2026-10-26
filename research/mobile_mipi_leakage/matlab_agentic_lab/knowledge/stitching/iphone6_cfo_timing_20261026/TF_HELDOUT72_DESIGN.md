# Heldout frame72 TF addition

2026-10-26. New no-argument driver: runIphoneTfHeldout26.m. It does not modify the concurrently executing timing/stitch/frame0-TF code.

The first TF wrapper intentionally used the first training frame0. That is useful for inspecting transforms but suppresses the visible effect of cumulative timing drift. The new wrapper instead uses the saved first assessment frame72 (zero based), singleTest columns1 and4. It asserts that72 is the first heldout frame and is absent from training. There is no new fit, band selection or parameter search.

The canonical segment starts at floor(2^21*1000/1881) and contains131072 samples, matching the frame0 design. Load only this slice through matfile. The native sample index is reconstructed with the timing driver's exact local-query then floor operation using its original frame72 read record; re-read131072+1024 samples read-only, trim512 guards, and reproduce conjugation minus the saved fixed training DC. The helper may then truncate the native STFT control to the canonical nominal duration, as before.

Record the native complex-sample and byte offsets, full guarded-read record, capture inventory identity, grid/native sample rates, canonical time since origin, raw/corrected physical query intervals, accumulated displacement in samples/ns, and frozen CFO. These coordinates distinguish a timing-induced phase change from an absolute RF-phase interpretation.

Output is a new tf_heldout72 directory. HELDOUT_CONTEXT.md gives the frame/count/rate/time/offset header; manifest.json retains exact parameters and model provenance. Before/after transforms share scales within this run. The frame0 and frame72 runs each choose their own common display extrema, so differences between their PNG brightness must not be treated as calibrated cross-frame changes. Numeric PSD remains in the same ADC-count-squared/Hz units.

The driver is authored and reviewed statically only; root owns checkcode and MATLAB execution. A completed manifest is the numerical execution record, and CWT status remains separately auditable.

## Derived pre-execution coordinates

Computed from the saved model.json, not from a new MATLAB signal run:

{
  "canonicalStartIndexZeroBased": 1114913,
  "canonicalFsHz": 125765070.18370669,
  "nativeFsHz": 124082800,
  "bands": [
    {
      "fcMHz": 100,
      "startCanonicalSeconds": 1.2094761826778384,
      "nativeFirst": 150083391,
      "deltaSamples": -8.380657293948238,
      "deltaNanoseconds": -67.54084606366264
    },
    {
      "fcMHz": 160,
      "startCanonicalSeconds": 1.2094761826778384,
      "nativeFirst": 150083391,
      "deltaSamples": -6.209476172060695,
      "deltaNanoseconds": -50.04300492945594
    }
  ]
}
