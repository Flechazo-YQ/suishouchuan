#Requires -RunAsAdministrator
param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Executable).Path
if ([IO.Path]::GetFileName($resolved) -ne 'CtrlV.exe') {throw 'Only the installed CtrlV.exe can be configured.'}
$name = 'ImageBridge Local Images'
$rule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
if ($rule) {$rule | Remove-NetFirewallRule -ErrorAction Stop}
New-NetFirewallRule -DisplayName $name -Direction Inbound -Program $resolved -Action Allow -Profile Private,Public -RemoteAddress LocalSubnet -Protocol TCP -LocalPort 43821,43822 -ErrorAction Stop | Out-Null
$mdnsName = 'ImageBridge Local Discovery'
$mdns = Get-NetFirewallRule -DisplayName $mdnsName -ErrorAction SilentlyContinue
if ($mdns) {$mdns | Remove-NetFirewallRule -ErrorAction Stop}
New-NetFirewallRule -DisplayName $mdnsName -Direction Inbound -Program $resolved -Action Allow -Profile Private,Public -RemoteAddress LocalSubnet -Protocol UDP -LocalPort 5353 -ErrorAction Stop | Out-Null
Write-Output 'CtrlV LAN-only firewall rules installed.'
