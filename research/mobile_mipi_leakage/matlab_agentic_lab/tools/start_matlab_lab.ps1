$ErrorActionPreference = 'Stop'
$labRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = (Join-Path $labRoot 'startLab.m').Replace('\','/')
$matlab = 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe'
# Visible desktop is requested explicitly for interactive research.
Start-Process -FilePath $matlab -ArgumentList '-desktop', '-r', ('"run(''' + $scriptPath + ''')"')
