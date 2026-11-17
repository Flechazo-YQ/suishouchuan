param([string]$SdkRoot = 'D:\Android\sdk', [string]$JavaRoot = 'C:\Program Files\Microsoft\jdk-21.0.5.11-hotspot')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:ANDROID_HOME = $SdkRoot
$env:JAVA_HOME = $JavaRoot
$env:GRADLE_USER_HOME = 'D:\Android\gradle-cache'
$env:IMAGEBRIDGE_SIGNING_PROPERTIES = Join-Path $env:LOCALAPPDATA 'ImageBridgeSigning\signing.properties'
if (-not (Test-Path -LiteralPath $env:IMAGEBRIDGE_SIGNING_PROPERTIES)) {throw '缺少固定发布签名，请恢复 ImageBridgeSigning 备份；不要生成替代密钥覆盖已有安装。'}
$buildRoot = 'D:\Android\builds\imagebridge\mobile'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
# Android's native build tools require an ASCII workspace on Windows.
$mobileRoot = Join-Path $projectRoot 'apps\mobile'
& robocopy $mobileRoot $buildRoot /E /XD (Join-Path $mobileRoot 'android\build') (Join-Path $mobileRoot 'android\app\build') .gradle .cxx /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) {throw 'Android 构建目录同步失败'}
$sdkProperty = 'sdk.dir=' + $SdkRoot.Replace('\', '/').Replace(':', '\:')
Set-Content -LiteralPath (Join-Path $buildRoot 'android\local.properties') -Value $sdkProperty -Encoding ascii
Push-Location (Join-Path $buildRoot 'android')
try {
    & .\gradlew.bat :app:assembleRelease -PreactNativeArchitectures=arm64-v8a --console=plain
    if ($LASTEXITCODE -ne 0) {throw 'Android 构建失败'}
    $target = Join-Path $projectRoot 'release\android'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -LiteralPath 'app\build\outputs\apk\release\app-release.apk' -Destination (Join-Path $target 'CtrlV.apk')
    & (Join-Path $SdkRoot 'build-tools\37.0.0\apksigner.bat') verify --print-certs (Join-Path $target 'CtrlV.apk')
    if ($LASTEXITCODE -ne 0) {throw 'APK 签名校验失败'}
} finally {Pop-Location}
