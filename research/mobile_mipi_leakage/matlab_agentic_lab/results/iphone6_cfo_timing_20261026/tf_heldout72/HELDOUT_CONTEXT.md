# Frame72 TF after accumulated timing drift

Frame index72 is zero based and excluded from the Oct26 training fit. The canonical excerpt starts at index1114913, near the line1000 raster coordinate, and has131072 samples. Before/after are saved singleTest columns1/4; no parameter is refitted here.

## fc100MHz

- Canonical Fs: 125765070.184Hz; original native Fs: 124082800Hz.
- Canonical start since frame-origin: 1.20947618268s; duration: 0.00104219716817s.
- Native original first complex-sample index: 150083391 (zero based); byte offset: 600333564.
- Native returned duration: 0.00105632690429s, before helper matching-duration truncation.
- Corrected minus raw starting query: -8.38065729samples = -67.540846ns.
- Frozen native CFO applied to corrected arm: 0Hz.

## fc160MHz

- Canonical Fs: 125765070.184Hz; original native Fs: 124082800Hz.
- Canonical start since frame-origin: 1.20947618268s; duration: 0.00104219716817s.
- Native original first complex-sample index: 150083391 (zero based); byte offset: 600333564.
- Native returned duration: 0.00105632690429s, before helper matching-duration truncation.
- Corrected minus raw starting query: -6.20947617samples = -50.0430049ns.
- Frozen native CFO applied to corrected arm: 712.642796298Hz.

Native control is unresampled but conjugated and fixed training DC removed. Different physical query times are not concealed: exact intervals are in manifest.json. Amplitude gates are heuristics, and short TF windows do not resolve a sub-kHz CFO directly. Colors are shared within this frame72 run; cross-run frame0/frame72 image brightness is not automatically calibrated.
