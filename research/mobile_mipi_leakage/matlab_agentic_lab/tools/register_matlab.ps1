param(
  [string]$ToolkitRoot = 'C:\Users\leechanghoon\Downloads\matlab-agentic-toolkit-main\matlab-agentic-toolkit-main',
  [string]$Server = 'C:\Users\leechanghoon\Documents\Codex\2026-09-21\snr-svd\matlab-runtime\matlab-mcp-server-windows-x64.exe'
)
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
$backupPath = "$configPath.before-matlab-20261022.bak"
if (-not (Test-Path -LiteralPath $backupPath)) { Copy-Item -LiteralPath $configPath -Destination $backupPath }
$configText = [IO.File]::ReadAllText($configPath)
if ($configText -notmatch '(?m)^\[mcp_servers\.matlab\]\s*$') {
  $lab = Split-Path -Parent $PSScriptRoot
  & codex mcp add matlab -- $Server '--matlab-root=C:\Program Files\MATLAB\R2026b' '--matlab-session-mode=auto' '--matlab-display-mode=desktop' "--initial-working-folder=$lab" '--disable-telemetry=true'
  if ($LASTEXITCODE -ne 0) { throw 'Codex MCP registration failed.' }
  $configText = [IO.File]::ReadAllText($configPath)
  $configText = $configText.Replace('[mcp_servers.matlab]', "[mcp_servers.matlab]`nstartup_timeout_sec = 120`ntool_timeout_sec = 600`nenv_vars = ['WINDIR']")
  [IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
} else { Write-Output 'Existing matlab MCP configuration preserved.' }
$shortLog = Join-Path $env:USERPROFILE 'Documents\Codex\mcp-log'
New-Item -ItemType Directory -Force -Path $shortLog | Out-Null
$configText = [IO.File]::ReadAllText($configPath)
$match = [regex]::Match($configText, '(?ms)^\[mcp_servers\.matlab\].*?(?=^\[|\z)')
if ($match.Success -and $match.Value -notmatch '--log-folder') {
  $logArgument = '--log-folder=' + $shortLog.Replace('\','/')
  $section = [regex]::Replace($match.Value, '(?m)^args = \[', ('args = ["' + $logArgument + '", '))
  $configText = $configText.Remove($match.Index, $match.Length).Insert($match.Index, $section)
  [IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
}
$skillRoot = Join-Path $env:USERPROFILE '.agents\skills'
New-Item -ItemType Directory -Force -Path $skillRoot | Out-Null
$groups = @('matlab-core','signal-processing','radar','wireless-communications')
$sources = @()
foreach ($group in $groups) {
  $sources += Get-ChildItem -LiteralPath (Join-Path $ToolkitRoot "skills-catalog\$group") -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') }
}
$extras = @('matlab-software-development\matlab-write-tests','matlab-software-development\matlab-run-tests','matlab-app-building\matlab-build-chart','matlab-programming\matlab-validate-function-arguments')
foreach ($extra in $extras) { $sources += Get-Item -LiteralPath (Join-Path $ToolkitRoot "skills-catalog\$extra") }
$registered = @()
foreach ($source in $sources) {
  $target = Join-Path $skillRoot $source.Name
  if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Junction -Path $target -Value $source.FullName | Out-Null }
  $registered += [pscustomobject]@{name=$source.Name; source=$source.FullName; target=$target}
}
$registered | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'environment\registered_skills.json') -Encoding utf8
Write-Output "Registered/preserved $($registered.Count) MATLAB skills."
& codex mcp get matlab
