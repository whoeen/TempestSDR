# Research instructions for this laboratory

These instructions implement the user's MATLAB-based research workflow.

## Roles and ownership
Use separate MIPI/DSI, compromising-emissions, RF signal-processing, and SDR/RF-chain roles when useful. Keep source/claim/read logs under knowledge/<role>. Serialize all operations on the shared MATLAB desktop: only the current execution owner calls MATLAB; other agents inspect files or literature.

## MATLAB
Use the locally installed official MATLAB MCP and toolkit skills, checking skills against current primary documentation when inconsistent. Follow the linked MATLAB coding standards. Preserve the visible shared MATLAB session. Do not clear the user's whole workspace or close all figures indiscriminately. A successful MCP initialize/tools-list is not proof of MATLAB execution. Static mlint success is not a numerical test pass.

## Raw data and records
Original captures are immutable. Log endian, scalar/complex representation, Fs, RF center, capture bandwidth, sample/byte offsets, input identity, code version, settings, units, run status and intermediate results. Logs must distinguish measured, derived, prior fit, hypothesis and unavailable. Unknown antenna Fs/BW remains unknown. Store new exports/results separately and refuse overwriting raw inputs.

## Inference
Do not equate fc, bit rate, forwarded DDR clock, pixel rate, row rate and frame rate.
Do not claim every RF sample corresponds to a pixel in DSI command/burst modes.
HSV hue represents relative measured phase, not recovered RGB.
Low amplitude phase is unreliable; identify phase reference and masking.
Do not assume desired DSI is low rank and driver clutter high rank without defining the matrix and testing it.
Do not call a peak-to-floor statistic SNR without specifying how desired signal and noise were isolated.
Evaluate coherent averaging, notches, whitening, RPCA and subspaces against untouched controls and independent test frames/patterns.
Synthetic results, enhancement/inpainting and physical reconstruction must be labelled separately.

## Reading and sharing
Use primary papers/specs/vendor docs; keep exact page/section/equation and version.
Record access failures and unreviewed ranges. Never say all papers were read.
Keep full copyrighted PDF/extracted-text caches local and ignored in Git.
Commit authored notes, metadata and code. Large raw captures remain in the existing data release; never add them as regular Git blobs.

## Hardware
Identify the actual receiver and daughterboard, supported software, Fs/BW/clock path and expected data rate before hardware changes.
Receive-only lab work is the present scope. Keep fixed-gain/no-subtraction controls.
Record overflow/late samples, finite capture boundaries and source duplication.
TempestSDR raw-file looping does not create independent observations.
