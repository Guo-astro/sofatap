$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'This lifecycle test is restricted to ephemeral GitHub-hosted Windows runners.'
}
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { throw 'RUNNER_TEMP is required.' }
$profileRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SofaTap'
$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'SofaTap.lnk'
if ((Test-Path $profileRoot) -or (Test-Path $startupShortcut) -or @(Get-Process -Name SofaTap, SofaTapHost -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Existing Sofatap data, startup entry or process found; refusing lifecycle test.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$testRoot = Join-Path $env:RUNNER_TEMP ('sofatap-update-lifecycle-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
function Publish-Fixture([string]$project, [string]$output, [string]$version, [string]$intermediate) {
    & $dotnet publish $project -c Release -r win-x64 --self-contained true `
        --artifacts-path $intermediate -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false "-p:Version=$version" -o $output
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $project ($LASTEXITCODE)" }
}
$frontend = Join-Path $repo 'desktop/windows/SofaTap.Desktop.csproj'
Publish-Fixture $frontend (Join-Path $testRoot 'old') '0.8.0-beta.1' (Join-Path $testRoot 'old-build')
Publish-Fixture $frontend (Join-Path $testRoot 'new') '0.8.1-beta.1' (Join-Path $testRoot 'new-build')
Publish-Fixture (Join-Path $PSScriptRoot 'update-fixture-host/UpdateFixtureHost.csproj') (Join-Path $testRoot 'host') '1.0.0' (Join-Path $testRoot 'host-build')
& $dotnet run --project (Join-Path $PSScriptRoot 'update-lifecycle/UpdateLifecycleChecks.csproj') -c Release `
    --artifacts-path (Join-Path $testRoot 'driver-build') -- `
    (Join-Path $testRoot 'old/SofaTap.exe') (Join-Path $testRoot 'new/SofaTap.exe') `
    (Join-Path $testRoot 'host/SofaTapHost.exe') (Join-Path $testRoot 'evidence')
if ($LASTEXITCODE -ne 0) { throw "Updater lifecycle verification failed ($LASTEXITCODE). Evidence: $testRoot" }
Write-Output "Updater lifecycle evidence: $testRoot/evidence/lifecycle-results.json"
