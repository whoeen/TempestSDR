function result = reproduceFramePca27(outputDirectory)
%REPRODUCEFRAMEPCA27 Run the frozen 100 MHz frame-SVD/CAF/IQ-binary experiment.
% Requires the original 100 MHz RIS, reference PNG and the prior complex CAF
% output bundle in their documented locations. Use a NEW output directory.
arguments
    outputDirectory (1,1) string
end
labRoot=string(fileparts(mfilename('fullpath')));
addpath(fullfile(labRoot,'signal_processing'));
priorDirectory=fullfile(labRoot,'results','iphone6_complex_caf_channels_20261027');
result.preparation=prepareFramePca27(outputDirectory);
iq=load(fullfile(outputDirectory,'pca_iq_features.mat'),'imageData','iqMethods');
[result.binary,~]=renderPcaIqBinary27(iq.imageData,iq.iqMethods,outputDirectory);
clear iq
result.coherence=auditFrameCoherence27(outputDirectory);
result.codebook=fitPcaCafObservationBank27(outputDirectory,priorDirectory, ...
    struct('maxStarts',3,'maxIterations',1500));
result.diagnostics=renderFramePcaDiagnostics27(outputDirectory,priorDirectory);
result.codebookPlot=renderPcaCodebookValidation27(outputDirectory);
result.numericalAudit=auditPcaNumerics27(outputDirectory);
end
