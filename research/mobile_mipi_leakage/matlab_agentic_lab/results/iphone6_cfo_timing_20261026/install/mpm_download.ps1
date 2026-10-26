$ErrorActionPreference = 'Stop'
$Destination = 'C:\Users\leechanghoon\Downloads\mpm.exe'
if (Test-Path -LiteralPath $Destination) { Write-Output 'Reusing mpm.exe' } else {
 Invoke-WebRequest -Uri 'https://www.mathworks.com/mpm/win64/mpm' -OutFile $Destination -UseBasicParsing
 if (-not (Test-Path -LiteralPath $Destination)) { throw 'Download failed' }
 Write-Output 'Downloaded mpm.exe'
}
