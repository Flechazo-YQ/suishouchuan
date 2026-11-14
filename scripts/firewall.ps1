param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Executable).Path
if ([IO.Path]::GetFileName($resolved) -ne '随手传.exe') {throw '只能为随手传的已安装程序配置防火墙。'}
$name = 'ImageBridge Local Images'
$rule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
if ($rule) {$rule | Remove-NetFirewallRule}
New-NetFirewallRule -DisplayName $name -Direction Inbound -Program $resolved -Action Allow -Profile Private,Public -RemoteAddress LocalSubnet -Protocol TCP -LocalPort 43821,43822 | Out-Null
$mdnsName = 'ImageBridge Local Discovery'
$mdns = Get-NetFirewallRule -DisplayName $mdnsName -ErrorAction SilentlyContinue
if ($mdns) {$mdns | Remove-NetFirewallRule}
New-NetFirewallRule -DisplayName $mdnsName -Direction Inbound -Program $resolved -Action Allow -Profile Private,Public -RemoteAddress LocalSubnet -Protocol UDP -LocalPort 5353 | Out-Null
Write-Output 'ImageBridge LAN-only firewall rules installed.'
