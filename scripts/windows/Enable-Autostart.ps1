$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'SofaTap.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Keep this script next to SofaTap.exe.' }
$startup = [Environment]::GetFolderPath('Startup')
$linkPath = Join-Path $startup 'SofaTap.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
if ((Test-Path -LiteralPath $linkPath) -and ([IO.Path]::GetFileName($link.TargetPath) -ine 'SofaTap.exe')) {
    throw 'The Sofatap startup shortcut points to another application; it was not changed.'
}
$link.TargetPath = $exe
$link.Arguments = '--startup'
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'Sofatap iPhone remote receiver'
$link.Save()
# Preserve Windows Startup Apps approval: do not write StartupApproved.
$settings = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SofaTap'
New-Item -ItemType Directory -Force -Path $settings | Out-Null
$preference = Join-Path $settings 'desktop-startup.json'
$temporary = $preference + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
try {
    [IO.File]::WriteAllText($temporary, '{"enabled":true}')
    Move-Item -Force -LiteralPath $temporary -Destination $preference
} finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
Write-Output 'Sofatap will start after you sign in. Keep this folder in its current location.'
Write-Output 'If Windows Startup Apps has disabled Sofatap, enable it there. This script does not override that choice.'
