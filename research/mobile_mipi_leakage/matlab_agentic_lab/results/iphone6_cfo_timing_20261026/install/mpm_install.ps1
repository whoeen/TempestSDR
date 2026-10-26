$ErrorActionPreference = 'Stop'
$mpmPath = 'C:\Users\leechanghoon\Downloads\mpm.exe'
$inputFile = 'C:\Users\leechanghoon\Documents\Codex\2026-09-21\snr-svd\tempestsdr-cloud\research\mobile_mipi_leakage\matlab_agentic_lab\results\iphone6_cfo_timing_20261026\install\mpm_input_r2026b.txt'
$installArgs = @('install', ('--inputfile="' + $inputFile + '"'))
Write-Output ('Running: "' + $mpmPath + '" install --inputfile="' + $inputFile + '"')
$mpmProcess = Start-Process -FilePath $mpmPath -ArgumentList $installArgs -Verb RunAs -WindowStyle Hidden -PassThru -Wait
Write-Output ('ExitCode: ' + $mpmProcess.ExitCode)
exit $mpmProcess.ExitCode
