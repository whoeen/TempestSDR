$ErrorActionPreference = 'Stop'
$matlabArguments = @('-batch', '"addpath(''C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab''); preflightIphone100Fam26;"', '-logfile', '"C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/results/iphone6_fc100_fam_20261026/preflight.log"')
$matlabProcess = Start-Process -FilePath 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe' -ArgumentList $matlabArguments -WindowStyle Hidden -PassThru -Wait
Write-Output ('ExitCode: ' + $matlabProcess.ExitCode)
exit $matlabProcess.ExitCode
