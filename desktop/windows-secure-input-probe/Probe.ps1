#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Install', 'Run', 'Status', 'Remove')][string]$Action,
    [string]$SourceExe,
    [ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
    [switch]$AllowUnsignedDiagnostic
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
$serviceName = 'SofatapSecureInputProbe'
$programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
if ($programFiles -notmatch '^[A-Za-z]:\\') { throw 'Only a local Program Files directory is supported.' }
$parent = Join-Path $programFiles 'Chekusu'
$install = Join-Path $parent 'SofatapSecureInputProbe'
$exe = Join-Path $install 'Sofatap.SecureInputProbe.exe'
$results = Join-Path $install 'Results'
$manifestPath = Join-Path $install 'install.json'
$serviceKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\SofatapSecureInputProbe'
$sc = Join-Path ([Environment]::SystemDirectory) 'sc.exe'
$trusted = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')

function Assert-Trusted([string]$Path, [switch]$VolumeRoot) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A diagnostic path is a reparse point; refusing it.' }
    $acl = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $trusted) { throw 'A diagnostic path has an untrusted owner.' }
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorBinaryForm(), 0)
    if (-not ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -or $null -eq $raw.DiscretionaryAcl) { throw 'A diagnostic path has a null or missing DACL.' }
    $forbidden = [int64][Security.AccessControl.FileSystemRights]::Delete -bor [int64][Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [int64][Security.AccessControl.FileSystemRights]::ChangePermissions -bor [int64][Security.AccessControl.FileSystemRights]::TakeOwnership -bor 0x10000000
    if (-not $VolumeRoot) { $forbidden = $forbidden -bor [int64][Security.AccessControl.FileSystemRights]::Write -bor 0x40000000 }
    foreach ($rule in $raw.DiscretionaryAcl) {
        if ($rule.AceFlags -band [Security.AccessControl.AceFlags]::InheritOnly) { continue }
        if ($rule.AceType -eq [Security.AccessControl.AceType]::AccessDenied) { continue }
        if ($rule.AceType -ne [Security.AccessControl.AceType]::AccessAllowed) { throw 'An unsupported path ACE prevents safe diagnostic installation.' }
        if (([int64]$rule.AccessMask -band $forbidden) -and $rule.SecurityIdentifier.Value -notin $trusted) {
            throw 'A diagnostic path is writable or replaceable by an untrusted identity.'
        }
    }
}
function Assert-Ancestors {
    $volume = [IO.Path]::GetPathRoot($programFiles)
    Assert-Trusted $volume -VolumeRoot
    $current = $programFiles
    $parts = New-Object Collections.Generic.List[string]
    while ($current -ne $volume) { $parts.Add($current); $current = Split-Path -Parent $current }
    for ($i = $parts.Count - 1; $i -ge 0; --$i) { Assert-Trusted $parts[$i] }
    if (Test-Path -LiteralPath $parent) { Assert-Trusted $parent }
}
function New-PrivateDirectory([string]$Path, [switch]$SharedParent) {
    if (-not ('SofatapProbeDirectory' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SofatapProbeDirectory {
 [StructLayout(LayoutKind.Sequential)] struct SA { public int size; public IntPtr sd; public int inherit; }
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string text, uint revision, out IntPtr sd, IntPtr size);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectory(string path, ref SA attributes);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr value);
 public static void Create(string path, bool shared) {
  IntPtr sd;
  string acl = "O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" + (shared ? "(A;OICI;GRGX;;;BU)" : "");
  if (!ConvertStringSecurityDescriptorToSecurityDescriptor(acl, 1, out sd, IntPtr.Zero)) throw new InvalidOperationException("Cannot prepare private diagnostic directory");
  try {
   var sa = new SA { size=Marshal.SizeOf(typeof(SA)), sd=sd };
   if (!CreateDirectory(path, ref sa)) throw new InvalidOperationException("Directory already exists or cannot be created; no existing directory was modified");
  } finally { LocalFree(sd); }
 }
}
'@
    }
    [SofatapProbeDirectory]::Create($Path, [bool]$SharedParent)
    Assert-Trusted $Path
}
function Write-NewText([string]$Path, [string]$Text) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $bytes = [Text.Encoding]::UTF8.GetBytes($Text); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function Assert-ServiceIdentity {
    if (-not (Test-Path -LiteralPath $serviceKey)) { return $false }
    $settings = Get-ItemProperty -LiteralPath $serviceKey
    if ($settings.ImagePath -cne ('"' + $exe + '" --service') -or $settings.ObjectName -ne 'LocalSystem' -or $settings.Start -ne 3 -or $settings.Type -ne 16) {
        throw 'The existing service does not match this fixed, manual diagnostic; it was not changed.'
    }
    return $true
}
function Read-Manifest {
    Assert-Ancestors
    Assert-Trusted $install
    Assert-Trusted $results
    Assert-Trusted $manifestPath
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 2048) { throw 'Invalid diagnostic manifest.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (@($manifest.PSObject.Properties).Count -ne 3 -or $manifest.kind -cne $serviceName -or $manifest.version -ne 1 -or $manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Invalid diagnostic manifest.'
    }
    return $manifest
}
function Assert-Binary($Manifest) {
    Assert-Trusted $exe
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $Manifest.sha256) { throw 'The installed diagnostic differs from its reviewed artifact hash.' }
}
function Assert-KnownFiles {
    foreach ($entry in Get-ChildItem -LiteralPath $install -Force) {
        Assert-Trusted $entry.FullName
        if ($entry.Name -notin @('Sofatap.SecureInputProbe.exe', 'install.json', 'Results')) { throw 'Unexpected installation contents; no files were removed.' }
        if ($entry.Name -ne 'Results' -and $entry.PSIsContainer) { throw 'Unexpected directory; no files were removed.' }
    }
    foreach ($entry in Get-ChildItem -LiteralPath $results -Force) {
        Assert-Trusted $entry.FullName
        if ($entry.PSIsContainer -or $entry.Name -notin @('service-result.json', 'worker-result.json')) { throw 'Unexpected diagnostic result; no files were removed.' }
    }
}
function Show-Results {
    foreach ($name in @('service-result.json', 'worker-result.json')) {
        $path = Join-Path $results $name
        if (Test-Path -LiteralPath $path) {
            Assert-Trusted $path
            if ((Get-Item -LiteralPath $path).Length -eq 0) { Write-Output "$name is incomplete. This is not a successful observation."; continue }
            if ((Get-Item -LiteralPath $path).Length -gt 8192) { throw 'Diagnostic result exceeds its fixed size bound.' }
            Write-Output $name
            Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Format-List
        }
    }
    Write-Output 'A launched worker or accepted event is not proof of pointer movement or PIN acceptance. Inspect the worker observation fields; no PIN was tested.'
}

function Remove-NewIncompleteDirectory {
    # Only used for a directory this invocation created, before any service exists.
    Assert-Ancestors
    Assert-Trusted $install
    foreach ($entry in Get-ChildItem -LiteralPath $install -Force) {
        Assert-Trusted $entry.FullName
        if ($entry.Name -notin @('Sofatap.SecureInputProbe.exe', 'install.json', 'Results')) { throw 'Unexpected file prevents partial-install rollback.' }
        if ($entry.Name -eq 'Results') {
            if (-not $entry.PSIsContainer -or @(Get-ChildItem -LiteralPath $entry.FullName -Force).Count -ne 0) { throw 'Unexpected results prevent partial-install rollback.' }
        } elseif ($entry.PSIsContainer) { throw 'Unexpected directory prevents partial-install rollback.' }
    }
    foreach ($entry in Get-ChildItem -LiteralPath $install -Force) { Remove-Item -LiteralPath $entry.FullName -Force }
    Remove-Item -LiteralPath $install -Force
}

Assert-Ancestors
switch ($Action) {
    'Install' {
        if (-not $AllowUnsignedDiagnostic -or -not $SourceExe -or -not $ExpectedSha256) {
            throw 'This development diagnostic requires -AllowUnsignedDiagnostic, -SourceExe and the independently reviewed artifact -ExpectedSha256. It is not a production installer.'
        }
        if ((Test-Path -LiteralPath $install) -or (Test-Path -LiteralPath $serviceKey) -or (Get-Service $serviceName -ErrorAction SilentlyContinue)) {
            throw 'A diagnostic directory or service already exists. Nothing was overwritten; inspect Status and use Remove first.'
        }
        $source = Get-Item -LiteralPath $SourceExe -Force
        if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $source.Length -gt 20971520) { throw 'Invalid diagnostic executable.' }
        if (-not $PSCmdlet.ShouldProcess($install, 'Install a manual, one-shot pointer diagnostic; do not start it')) { return }
        $createdInstall = $false
        try {
        # Hash and copy the same open handle, denying concurrent writes/deletion.
        $inputFile = [IO.File]::Open($source.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($sha.ComputeHash($inputFile)).Replace('-', '') }
            finally { $sha.Dispose() }
            if ($actual -ne $ExpectedSha256) { throw 'Source executable hash differs from the independently reviewed artifact.' }
            if (-not (Test-Path -LiteralPath $parent)) { New-PrivateDirectory $parent -SharedParent }
            Assert-Trusted $parent
            New-PrivateDirectory $install
            $createdInstall = $true
            New-PrivateDirectory $results
            Write-NewText $manifestPath (@{kind=$serviceName; version=1; sha256=$actual} | ConvertTo-Json -Compress)
            $outputFile = [IO.File]::Open($exe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            try { $inputFile.Position = 0; $inputFile.CopyTo($outputFile); $outputFile.Flush($true) }
            finally { $outputFile.Dispose() }
        } finally { $inputFile.Dispose() }
        Assert-Binary (Read-Manifest)
        New-Service -Name $serviceName -DisplayName 'Sofatap pointer-only diagnostic (manual)' -BinaryPathName ('"' + $exe + '" --service') -StartupType Manual | Out-Null
        & $sc sdset $serviceName 'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not restrict service control. It was not started; use Remove to clean up.' }
        if (-not (Assert-ServiceIdentity)) { throw 'Service registration verification failed. It was not started.' }
        Write-Output 'Installed only. No input occurred. Keep a physical keyboard available, sign into the physical console normally, close the on-screen keyboard and any hover/dwell tools, then lock it. Run is a separate explicit action.'
        } catch {
            $installError = $_
            if ($createdInstall -and -not (Test-Path -LiteralPath $serviceKey)) {
                try { Remove-NewIncompleteDirectory }
                catch { Write-Warning 'Partial rollback could not be verified; the fixed diagnostic directory was retained for inspection. No recursive deletion was attempted.' }
            } elseif ($createdInstall) { Write-Warning 'The manual service/files were retained. This installer did not start them; use Remove to clean up.' }
            throw $installError
        }
    }
    'Run' {
        $manifest = Read-Manifest
        Assert-Binary $manifest
        Assert-KnownFiles
        if (-not (Assert-ServiceIdentity)) { throw 'The diagnostic service is not installed.' }
        if (@(Get-ChildItem -LiteralPath $results -Force).Count -ne 0) { throw 'This installation already ran or has an incomplete report. It cannot repeat input; inspect Status, then Remove.' }
        & $exe --preflight
        if ($LASTEXITCODE -ne 0) { throw 'The physical console must already be WTSActive and locked, with Windows on-screen keyboard closed. Pre-login Connected and disconnected RDP sessions are intentionally rejected. Nothing was started.' }
        if (-not $PSCmdlet.ShouldProcess('The already locked physical console', 'Run one 8-pixel mouse move and conditional restore; no clicks or keys')) { return }
        Start-Service $serviceName
        $service = Get-Service $serviceName
        try { $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(14)) }
        finally { $service.Dispose() }
        Show-Results
    }
    'Status' {
        if (-not (Test-Path -LiteralPath $install)) {
            if (Test-Path -LiteralPath $serviceKey) { throw 'A service exists without its diagnostic directory; inspect it manually.' }
            Write-Output 'The diagnostic is not installed.'; return
        }
        $null = Read-Manifest
        Assert-KnownFiles
        if (Assert-ServiceIdentity) { Get-Service $serviceName | Select-Object Name, Status, StartType }
        Show-Results
    }
    'Remove' {
        if (-not (Test-Path -LiteralPath $install)) {
            if (Test-Path -LiteralPath $serviceKey) { throw 'Service exists without diagnostic files; refusing to remove an unverified registration.' }
            Write-Output 'The diagnostic is already absent.'; return
        }
        $null = Read-Manifest
        Assert-KnownFiles
        $registered = Assert-ServiceIdentity
        if (-not $PSCmdlet.ShouldProcess($install, 'Stop and delete only this diagnostic service and its fixed files, including its reports')) { return }
        if ($registered) {
            $service = Get-Service $serviceName
            try {
                if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) { $service.Stop(); $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(14)) }
            } finally { $service.Dispose() }
            & $sc delete $serviceName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Service deletion failed; diagnostic files were retained.' }
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while (Test-Path -LiteralPath $serviceKey) {
                if ([DateTime]::UtcNow -ge $deadline) { throw 'Service is still pending deletion; files were retained. Close service management windows and run Remove again.' }
                Start-Sleep -Milliseconds 100
            }
        }
        if (@([Diagnostics.Process]::GetProcessesByName('Sofatap.SecureInputProbe')).Count -ne 0) { throw 'A diagnostic process still exists; no files were deleted. Wait for its bounded deadline and retry Remove.' }
        Assert-KnownFiles
        foreach ($entry in Get-ChildItem -LiteralPath $results -Force) { Remove-Item -LiteralPath $entry.FullName -Force }
        Remove-Item -LiteralPath $results -Force
        foreach ($name in @('Sofatap.SecureInputProbe.exe', 'install.json')) {
            $path = Join-Path $install $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        Remove-Item -LiteralPath $install -Force
        if ((Test-Path -LiteralPath $serviceKey) -or (Test-Path -LiteralPath $install)) { throw 'Cleanup is incomplete.' }
        Write-Output 'The diagnostic service and its files were removed. No account, credential provider, firewall, desktop ACL or Windows sign-in policy was changed.'
    }
}
