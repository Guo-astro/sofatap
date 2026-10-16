$ErrorActionPreference = 'Stop'
$linkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'SofaTap.lnk'
if (Test-Path -LiteralPath $linkPath) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($linkPath)
    if ([IO.Path]::GetFileName($link.TargetPath) -ine 'SofaTap.exe') {
        throw 'The Sofatap startup shortcut points to another application; it was not removed.'
    }
    Remove-Item -LiteralPath $linkPath
}
$settings = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SofaTap'
New-Item -ItemType Directory -Force -Path $settings | Out-Null
$preference = Join-Path $settings 'desktop-startup.json'
$temporary = $preference + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
try {
    [IO.File]::WriteAllText($temporary, '{"enabled":false}')
    Move-Item -Force -LiteralPath $temporary -Destination $preference
} finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
Write-Output 'Sofatap automatic startup is disabled.'
