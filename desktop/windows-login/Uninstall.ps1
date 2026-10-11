#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([switch]$KeepEnrollmentBackup)
$ErrorActionPreference = 'Stop'
$clsid = '{F8F3819A-9AB1-4C6F-86D5-90B57D9A42C7}'
$install = Join-Path $env:ProgramFiles 'Chekusu\Sofatap Login'
$data = Join-Path $env:ProgramData 'Sofatap\Login'
$settings = Get-ItemProperty 'HKLM:\SOFTWARE\Chekusu\SofatapLogin' -ErrorAction SilentlyContinue
if (-not $PSCmdlet.ShouldProcess('Sofatap optional login only', 'Unregister its provider and remove its service; preserve built-in Windows sign-in')) { return }
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$clsid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "HKLM:\SOFTWARE\Classes\CLSID\$clsid" -Recurse -Force -ErrorAction SilentlyContinue
$service = Get-Service SofatapLogin -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service SofatapLogin -ErrorAction Stop
    $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(15))
    & sc.exe delete SofatapLogin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Provider is unregistered, but service deletion failed. Keep the private data and finish service removal before deleting it.' }
}
Remove-NetFirewallRule -Name 'SofatapLogin-PrivateLocal' -ErrorAction SilentlyContinue
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($settings.AccountSid -eq $currentSid) { Remove-Item (Join-Path $env:LOCALAPPDATA 'SofaTap\unlock-capability.dat') -Force -ErrorAction SilentlyContinue }
Remove-Item 'HKLM:\SOFTWARE\Chekusu\SofatapLogin' -Recurse -Force -ErrorAction SilentlyContinue
if (-not $KeepEnrollmentBackup -and (Test-Path -LiteralPath $data)) { Remove-Item -LiteralPath $data -Recurse -Force }
try { if (Test-Path -LiteralPath $install) { Remove-Item -LiteralPath $install -Recurse -Force } }
catch { Write-Output 'Provider has been unregistered. Windows may retain the loaded DLL until restart; remove the Sofatap Login installation folder after restarting.' }
Write-Output 'Sofatap optional login removed. Normal Windows sign-in providers were not modified. Forget the saved computer password in the iPhone app as well.'
