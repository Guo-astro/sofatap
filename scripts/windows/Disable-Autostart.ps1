$ErrorActionPreference = 'Stop'
$linkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Tiltro.lnk'
if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath }
Write-Output 'Tiltro automatic startup is disabled.'
