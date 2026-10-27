# iPhone 6 frame SVD, CAF and IQ projection binary experiment

Open [the offline gallery](gallery/index.html) and [the Korean research report](REPORT_KO.md).

The derived MAT/FIG package is published separately as a GitHub release asset. See cloud_manifest.json for its URL, SHA256 and upload receipt. Original RIS is not duplicated in this derived package.

To reproduce from measurements in MATLAB, add the lab folder and its signal_processing folder to the MATLAB path, then run reproduceFramePca27 with a NEW output directory. Restore the prior complex CAF bundle linked in result_provenance.json first. The immutable RIS and reference screenshot must be available at the paths recorded in the prior metadata. The supplied source_snapshot contains the executed experiment code and supporting MATLAB functions. Figures and data analysis were produced in MATLAB; Python is used only for indexing and packaging.

The per-column binary output is a measured temporal raster. It is not a verified RGB pixel or MIPI bit stream. Strong CAF repetition did not yield successful direct-IQ binary decoding in this experiment.
