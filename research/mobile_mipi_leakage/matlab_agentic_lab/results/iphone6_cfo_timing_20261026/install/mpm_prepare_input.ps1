$ErrorActionPreference = 'Stop'
$InputFile = 'C:\Users\leechanghoon\Documents\Codex\2026-09-21\snr-svd\tempestsdr-cloud\research\mobile_mipi_leakage\matlab_agentic_lab\results\iphone6_cfo_timing_20261026\install\mpm_input_r2026b.txt'
Invoke-WebRequest -Uri 'https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/products/mpm/mpm-input-r2026b.txt' -OutFile $InputFile -UseBasicParsing -UserAgent 'Mozilla/5.0'
$ProductList = @('product.Signal_Processing_Toolbox','product.Wavelet_Toolbox')
$lines = Get-Content -LiteralPath $InputFile
$lines = $lines | ForEach-Object {
 if ($_ -match '^\s*#?\s*destinationFolder=') {
  'destinationFolder=C:\Program Files\MATLAB\R2026b'
  'noJRE=true'
  'caller=agent'
 } elseif ($ProductList -contains ($_ -replace '^\s*#\s*','')) { $_ -replace '^\s*#\s*','' } else { $_ }
}
Set-Content -LiteralPath $InputFile -Value $lines -Encoding UTF8
foreach ($product in $ProductList) { if ($lines -notcontains $product) { throw "Missing product: $product" } }
if ($lines -notcontains 'destinationFolder=C:\Program Files\MATLAB\R2026b') { throw 'Destination mismatch' }
if ($lines -notcontains 'caller=agent') { throw 'Caller missing' }
$unexpected = $lines | Where-Object { $_ -match '^product\.' -and $ProductList -notcontains $_ }
if ($unexpected) { throw 'Unexpected products' }
Write-Output $InputFile
Write-Output $ProductList
