$ErrorActionPreference = 'Stop'
$matlabExe = 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe'
$matlabArguments = @('-batch', '"addpath(''C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab''); verifySignalWaveletInstall;"', '-logfile', '"C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/results/iphone6_cfo_timing_20261026/install/toolbox_smoke.log"')
$matlabProcess = Start-Process -FilePath $matlabExe -ArgumentList $matlabArguments -WindowStyle Hidden -PassThru -Wait
Write-Output ('ExitCode: ' + $matlabProcess.ExitCode)
exit $matlabProcess.ExitCode
