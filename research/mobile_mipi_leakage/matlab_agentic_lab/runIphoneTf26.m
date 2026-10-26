function manifest = runIphoneTf26
%RUNIPHONETF26 Toolbox TF controls for the frozen Oct26 timing-run excerpts.
% Run only after analyzeIphonePairTiming saves both band MATs and model.mat.
% Uses the prior selected106MHz region; it does not optimize TF parameters.
lab=fileparts(mfilename('fullpath'));
inputDir=fullfile(lab,'results','iphone6_cfo_timing_20261026','timing');
outputDir=fullfile(lab,'results','iphone6_cfo_timing_20261026','tf');
assert(~isfolder(outputDir)&&~isfile(outputDir),'tf26:Exists','Refusing output overwrite.');
paths={fullfile(inputDir,'band_fc100.mat'),fullfile(inputDir,'band_fc160.mat')};
fields={'tfRaw','tfBoth','tfNative','meta'};
a=load(paths{1},fields{:});b=load(paths{2},fields{:});
saved=load(fullfile(inputDir,'model.mat'),'model');model=saved.model;
assert(a.meta.fc_hz==100e6&&b.meta.fc_hz==160e6,'tf26:Input','Unexpected band identities.');
assert(a.meta.tf_first_frame_zero_based==b.meta.tf_first_frame_zero_based, ...
    'tf26:Frame','Expected matched frame indices.');
metadata=struct;
metadata.nominal_fc_hz=[a.meta.fc_hz b.meta.fc_hz];
metadata.native_cell={a.tfNative,b.tfNative};
metadata.native_fs_hz=[a.meta.fs_native_hz b.meta.fs_native_hz];
metadata.native_start_samples=[a.meta.tf_native_start_sample b.meta.tf_native_start_sample];
metadata.canonical_start_index_zero_based=[a.meta.tf_canonical_start_index_zero_based b.meta.tf_canonical_start_index_zero_based];
metadata.source_frame_zero_based=[a.meta.tf_first_frame_zero_based b.meta.tf_first_frame_zero_based];
metadata.raw_description=a.meta.tf_raw_description;
metadata.corrected_description=a.meta.tf_both_description;
metadata.native_description='Unresampled contiguous native-rate IQ AFTER conjugation and fixed training-frame DC subtraction; not original ADC bytes.';
metadata.iq_polarity=model.iq_polarity;
metadata.rf_coordinate_convention=model.cfo.baseband_sign_convention;
metadata.input_mat_paths=paths;
metadata.input_mat_bytes=[fileBytes(paths{1}) fileBytes(paths{2})];
metadata.input_band_metadata={a.meta,b.meta};
metadata.timing_model=model;
metadata.selection='RF106MHz prior region, fixed before these TF outputs; q16, displayed103.05--108.95MHz approximately';
metadata.comparison_scope='Frame0 processing diagnostic; not heldout, not simultaneous cross-band IQ, not a stitching validity metric';
metadata.native_canonical_origin_note='Native starts at floor of raw canonical query. Relative axes do not assert identical physical sample instants.';
metadata.source_representation_note='See timing_model.identities/read_records for immutable capture identity, endian, integer representation and byte/sample offsets.';
options=struct('SubbandRfHz',106e6,'Decimation',16,'DisplayNyquistFraction',0.75);
manifest=plotIphonePairTf({a.tfRaw,b.tfRaw},{a.tfBoth,b.tfBoth}, ...
    [a.meta.fs_grid_hz b.meta.fs_grid_hz],outputDir,metadata,options);
fprintf('Toolbox TF output complete: %s\n',outputDir);
end

function bytes=fileBytes(path)
entry=dir(path);assert(isscalar(entry),'tf26:Input','Expected one MAT file.');bytes=entry.bytes;
end
