param([string]$FfprobePath = (Get-Command ffprobe -ErrorAction Stop).Source)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$destination = Join-Path $root 'apps\desktop\resources'
$version = & $FfprobePath -version | Select-Object -First 1
if ($version -notmatch 'ffprobe version (\d+)' -or [int]$Matches[1] -lt 8) { throw 'ffprobe 8 or newer is required.' }
Copy-Item -LiteralPath $FfprobePath -Destination (Join-Path $destination 'ffprobe.exe')
$license = Join-Path (Split-Path (Split-Path $FfprobePath)) 'LICENSE'
if (!(Test-Path $license)) {throw 'FFmpeg license file was not found.'}
Copy-Item -LiteralPath $license -Destination (Join-Path $destination 'FFmpeg-LICENSE.txt')
$readme = Join-Path (Split-Path (Split-Path $FfprobePath)) 'README.txt'
if (!(Test-Path $readme)) {throw 'FFmpeg source/build notice was not found.'}
Copy-Item -LiteralPath $readme -Destination (Join-Path $destination 'FFmpeg-README.txt')
Write-Output $version
