# iPhone 6 stitching gallery

[Open the offline gallery](index.html)

**Full 720 MHz coherent physical reconstruction is not validated.** The union is nominal RF coverage, not a demonstrated recovered physical bandwidth.

The four PNGs below are compact Git previews. Full-resolution images are referenced by relative path and belong in the views release bundle. Preserve the parent result folder tree when extracting that bundle. No network or external library is used by the HTML.

The gallery generator performs only PNG layout/resizing and reads saved JSON metrics. It does not read IQ/MAT files, apply DSP or enhancement, or calculate image fidelity.

## Preview 1

![Summary 1](summary_01_am_refinement.png)

## Preview 2

![Summary 2](summary_02_eleven_bands.png)

## Preview 3

![Summary 3](summary_03_stitch_unvalidated.png)

## Preview 4

![Summary 4](summary_04_phase_tf.png)

## Rebuild

Run tools/make_iphone_stitch_gallery.py after all MATLAB output stages finish. Missing outputs are shown as pending. Generated gallery files may be replaced; raw captures and existing MATLAB outputs are never modified.

See manifest.json for source assets and missing outputs.
