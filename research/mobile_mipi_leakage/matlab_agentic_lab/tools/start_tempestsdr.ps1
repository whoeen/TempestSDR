$ErrorActionPreference = 'Stop'
$runtime='C:\Users\leechanghoon\Documents\Codex\2026-09-21\snr-svd\matlab-runtime'
$java = Get-ChildItem -LiteralPath (Join-Path $runtime 'java8') -Recurse -Filter 'javaw.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $java) { throw 'Portable Java runtime not found.' }
$jar = Join-Path $runtime 'TempestSDR\JTempestSDR.jar'
$log = Join-Path $runtime 'TempestSDR\stderr.log'
# This is the user-facing interactive GUI explicitly requested for research.
Start-Process -FilePath $java -ArgumentList '-jar', ('"' + $jar + '"') -WorkingDirectory (Split-Path -Parent $jar) -RedirectStandardError $log -PassThru | Select-Object Id,ProcessName
