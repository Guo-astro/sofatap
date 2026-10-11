$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'SofaTap.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Keep this script next to SofaTap.exe.' }
$startup = [Environment]::GetFolderPath('Startup')
$linkPath = Join-Path $startup 'SofaTap.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = $exe
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'Sofatap iPhone remote receiver'
$link.Save()
Write-Output 'Sofatap will start after you sign in. Keep this folder in its current location.'
