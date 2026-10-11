#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ServiceDirectory,
    [Parameter(Mandatory)][string]$ProviderDll,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ReceiverFingerprint,
    [switch]$AllowUnsignedPilot
)
$ErrorActionPreference = 'Stop'
if (-not $AllowUnsignedPilot) { throw 'This is a development pilot installer only. Release package signing and dependency-manifest verification are not implemented. Use -AllowUnsignedPilot only for an explicitly approved test installation.' }
$clsid = '{F8F3819A-9AB1-4C6F-86D5-90B57D9A42C7}'
$install = Join-Path $env:ProgramFiles 'Chekusu\Sofatap Login'
$dataParent = Join-Path $env:ProgramData 'Sofatap'
$data = Join-Path $dataParent 'Login'
$profile = Join-Path $env:LOCALAPPDATA 'SofaTap'
$providerKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$clsid"
if (-not [Environment]::Is64BitProcess) { throw 'Run 64-bit PowerShell.' }
$sourceExe = Join-Path (Resolve-Path -LiteralPath $ServiceDirectory) 'Sofatap.Login.Service.exe'
$sourceDll = (Resolve-Path -LiteralPath $ProviderDll).Path
foreach ($file in @($sourceExe, $sourceDll)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Build the service and provider first.' }
    if (-not $AllowUnsignedPilot -and (Get-AuthenticodeSignature -LiteralPath $file).Status -ne 'Valid') { throw 'Release installation requires signed binaries. An isolated pilot can explicitly use -AllowUnsignedPilot.' }
}
if ((Get-Service SofatapLogin -ErrorAction SilentlyContinue) -or (Test-Path $providerKey) -or (Test-Path $install) -or (Test-Path $data)
    -or (Test-Path "HKLM:\SOFTWARE\Classes\CLSID\$clsid") -or (Test-Path 'HKLM:\SOFTWARE\Chekusu\SofatapLogin')
    -or (Get-NetFirewallRule -Name 'SofatapLogin-PrivateLocal' -ErrorAction SilentlyContinue)) { throw 'An existing installation or enrollment exists. Use its uninstaller first; nothing was overwritten.' }
# Refuse preexisting ancestors that ordinary users can replace or turn into junctions.
function Assert-TrustedParent([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installation paths must not be junctions.' }
    $acl = Get-Acl -LiteralPath $Path
    $owner = $acl.Owner
    try { $owner = ([Security.Principal.NTAccount]$owner).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    if ($owner -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'An installation parent has an untrusted owner.' }
    foreach ($rule in $acl.Access) {
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        $write = $rule.FileSystemRights -band ([Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership)
        if ($rule.AccessControlType -eq 'Allow' -and $write -and $sid -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'An installation parent is writable by an untrusted identity.' }
    }
}
Assert-TrustedParent $dataParent
Assert-TrustedParent (Split-Path $install)
$registryParent = 'HKLM:\SOFTWARE\Chekusu'
function Assert-TrustedRegistryParent([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    $acl = Get-Acl $Path
    $owner = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'The registry parent has an untrusted owner.' }
    foreach ($rule in $acl.Access) {
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        $write = $rule.RegistryRights -band ([Security.AccessControl.RegistryRights]::SetValue -bor [Security.AccessControl.RegistryRights]::CreateSubKey -bor [Security.AccessControl.RegistryRights]::Delete -bor [Security.AccessControl.RegistryRights]::ChangePermissions -bor [Security.AccessControl.RegistryRights]::TakeOwnership)
        if ($rule.AccessControlType -eq 'Allow' -and $write -and $sid -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'The registry parent is writable by an untrusted identity.' }
    }
}
Assert-TrustedRegistryParent $registryParent
foreach ($item in @(Get-Item -LiteralPath $ServiceDirectory) + @(Get-ChildItem -LiteralPath $ServiceDirectory -Recurse -Force) + @(Get-Item -LiteralPath $sourceDll)) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Build inputs must not contain symbolic links or junctions.' }
}
if (-not $PSCmdlet.ShouldProcess('This local Windows account', 'Install the optional Sofatap login service and extra credential provider; preserve all normal Windows sign-in options')) { return }
if (-not (Test-Path -LiteralPath $dataParent)) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SofatapPrivateDirectory {
 [StructLayout(LayoutKind.Sequential)] struct SA { public int size; public IntPtr sd; public int inherit; }
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string s, uint r, out IntPtr sd, IntPtr n);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateDirectory(string p, ref SA sa);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 public static void Create(string path) {
  IntPtr sd; if(!ConvertStringSecurityDescriptorToSecurityDescriptor("O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)",1,out sd,IntPtr.Zero)) throw new InvalidOperationException("Private directory security failed");
  try { var sa=new SA { size=Marshal.SizeOf(typeof(SA)),sd=sd }; if(!CreateDirectory(path,ref sa)) throw new InvalidOperationException("Directory exists or cannot be created; refusing race"); }
  finally { LocalFree(sd); }
 }
}
'@
    [SofatapPrivateDirectory]::Create($dataParent)
}
Assert-TrustedParent $dataParent
# Private service configuration; no plaintext Windows password is ever written here.
& icacls.exe $dataParent /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /setowner '*S-1-5-32-544' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect service configuration.' }
New-Item -ItemType Directory -Path $data | Out-Null
New-Item -ItemType Directory -Path $install -Force | Out-Null
& icacls.exe $install /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /setowner '*S-1-5-32-544' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect service binaries.' }
$backup = Join-Path $data 'recovery'
New-Item -ItemType Directory -Path $backup | Out-Null
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers' | Select-Object -ExpandProperty PSChildName | Set-Content (Join-Path $backup 'original-provider-ids.txt')
Copy-Item -Path (Join-Path $ServiceDirectory '*') -Destination $install -Recurse
Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $install 'SofatapLoginProvider.dll')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $install
$exe = Join-Path $install 'Sofatap.Login.Service.exe'
try {
    if (-not (Test-Path $registryParent)) { New-Item $registryParent | Out-Null }
    Assert-TrustedRegistryParent $registryParent
    $settingsPath = Join-Path $registryParent 'SofatapLogin'
    New-Item $settingsPath | Out-Null
    $settingsAcl = New-Object Security.AccessControl.RegistrySecurity
    $settingsAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;CI;KA;;;SY)(A;CI;KA;;;BA)')
    Set-Acl -Path $settingsPath -AclObject $settingsAcl
    & $exe --provision $ReceiverFingerprint $profile
    if ($LASTEXITCODE -ne 0) { throw 'Enrollment failed: the physical console must be signed into the same local or personal Microsoft profile as this elevated process. Domain/Entra identities are unsupported.' }
    New-Service -Name SofatapLogin -BinaryPathName ('"' + $exe + '"') -DisplayName 'Sofatap optional phone sign-in' -StartupType Automatic | Out-Null
    New-NetFirewallRule -Name 'SofatapLogin-PrivateLocal' -DisplayName 'Sofatap optional login (private local subnet)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 53320 -Program $exe -Profile Private -RemoteAddress LocalSubnet | Out-Null
    Start-Service SofatapLogin
    $com = "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
    New-Item -Path $com -Force | Out-Null
    Set-Item -Path $com -Value (Join-Path $install 'SofatapLoginProvider.dll')
    New-ItemProperty -Path $com -Name ThreadingModel -Value Apartment -PropertyType String -Force | Out-Null
    New-Item -Path $providerKey -Force | Out-Null
    Set-Item -Path $providerKey -Value 'Sofatap optional phone sign-in'
    Write-Output 'Optional component installed. Normal Windows sign-in is unchanged. Reopen Sofatap Receiver while unlocked, then explicitly enroll this computer in the iPhone app. Lock/unlock acceptance remains a separate test.'
} catch {
    # Remove only our newly-created registration, service and firewall rule. Preserve private recovery data.
    Remove-Item $providerKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SOFTWARE\Classes\CLSID\$clsid" -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Service SofatapLogin -ErrorAction SilentlyContinue
    & sc.exe delete SofatapLogin | Out-Null
    Remove-NetFirewallRule -Name 'SofatapLogin-PrivateLocal' -ErrorAction SilentlyContinue
    throw
}
