$ErrorActionPreference = 'Stop'
$linkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'SofaTap.lnk'
if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath }
Write-Output 'Sofa Tap automatic startup is disabled.'
