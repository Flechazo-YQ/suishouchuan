# 开发与构建

## 结构与通信

| 目录 | 内容 |
| --- | --- |
| `apps/desktop` | Electron + React + TypeScript，Windows托盘、局域网接收、图片/视频处理、剪贴板与缓存 |
| `apps/mobile` | React Native + TypeScript；Android原生相机、分享、扫码、设备发现、屏幕采集、证书固定 |
| `scripts` | 构建、媒体工具准备、防火墙与发布包一致性检查 |
| `docs` | 使用、构建和缓存说明 |

手机与电脑之间使用HTTPS，无业务云中转。mDNS发现使用稳定设备ID；二维码包含地址、证书指纹和短期一次性凭据。配对成功后手机保存授权并固定电脑证书，电脑只接受已配对设备。发现失败可重新扫码直连，不自动切到公网。

默认端口：HTTPS TCP43821，局域网APK下载 HTTP TCP43822，mDNS UDP5353。Windows服务限制私有局域网IPv4。防火墙脚本`scripts/firewall.ps1`只为程序及局域网来源开放相应端口，执行需要管理员权限。

| 接口 | 用途 |
| --- | --- |
| `POST /v1/pair` | 一次性配对 |
| `POST /v1/images` | 单图上传 |
| `POST /v1/videos` | MP4上传 |
| `POST /v1/batches` | 1–10张图集上传 |
| `GET /v1/transfers/{id}` | 查询本人设备的接收/复制状态 |

上传使用Bearer授权、请求ID和完整性校验。`received`仅表示已接收，`copied`才表示剪贴板写入已确认；重复已成功的请求不会再次覆盖剪贴板。单图使用系统图片格式，图集/视频使用文件剪贴板。电脑端可主动重新复制。

## 本机构建

环境：Node.js22+、JDK21、Android SDK37/Build Tools37.0.0/NDK27.1、ffprobe8+。依赖版本以lockfile为准。当前发布为Windows x64、Android arm64，Android API26+；HEIC转换依赖API28+和设备解码能力，真实HEIC全链路未完成验收。

```powershell
npm --prefix apps/desktop ci
npm --prefix apps/mobile ci
& ./scripts/prepare-media-tools.ps1 -FfprobePath 'D:\Tools\ffmpeg\bin\ffprobe.exe'
npm test
npm --prefix apps/mobile run typecheck
& ./scripts/build-android.ps1 -SdkRoot 'D:\Android\sdk' -JavaRoot 'C:\Path\To\jdk-21'
npm run desktop:package
node scripts/verify-release.cjs
```

`npm test`运行接收端与移动端草稿切换测试。Gradle JVM测试可在Android构建目录执行`gradlew.bat :app:testReleaseUnitTest`。单元测试不能替代扫码、系统分享、剪贴板和悬浮窗真机验收。

Windows中文项目路径可能影响Android原生构建，现有脚本同步到`D:\Android\builds\imagebridge\mobile`，Gradle缓存为`D:\Android\gradle-cache`。开发者可按自己的磁盘修改脚本中的目录。运行打包前必须先生成APK，因为Windows安装包会内置它。

### Android签名

仓库不含发行私钥。构建脚本要求本机`%LOCALAPPDATA%\ImageBridgeSigning\signing.properties`，字段为`storeFile`、`storePassword`、`keyAlias`、`keyPassword`。自行开发需创建自己的keystore并配置这些字段，后续更新沿用同一密钥，不要把文件或密码提交到Git。

自行签名的APK不能覆盖本仓库发行签名的已安装应用；如果做独立分支，建议更改applicationId，以免影响已有安装和配对。官方版本升级应使用Release里的同签名包。Android不支持把低versionCode当成常规覆盖升级。

### 产物与验证

- Android：`release/android/CtrlV.apk`。
- Windows：`release/windows/CtrlV-Setup-<版本>.exe`。
- `verify-release.cjs`校验构建主进程、内置APK、媒体工具/许可证和原生剪贴板依赖是否一致，生成本地manifest。
- 安装后另外核对运行版本、配对与真实发送；不能仅凭构建通过就判定交付成功。

0.4.9沿用的Android发行证书SHA-256：`fec25f2978922c0462e1577aa4983ede90f8e673400aebd0b7f201840c441c44`。文件SHA-256以Release的`SHA256SUMS.txt`为准。

## 数据与边界

Windows程序安装到`%LOCALAPPDATA%\Programs\ImageBridge`，配置和媒体缓存位于`%APPDATA%\随手传`。0.4.9 将显示名与安装包名称改为 CtrlV，保留该数据目录、安装身份、Android applicationId 和协议标识，避免更新丢失配对；开机启动项改为新可执行文件。未来 iPhone 版计划名为 CommandV，当前仓库不含 iOS 发布包。

这些运行数据不属于源码，不能公开上传。手机私有outbox只暂存待发素材；详情见[缓存规则](CACHE-POLICY.md)。

公开源码以0.4.8已验收代码作为首次基线，早期演进见[CHANGELOG](../CHANGELOG.md)。本机配对配置、签名私钥、私人截图和包含设备信息的调试验收记录不随仓库发布。GitHub首次发布时间与各版本的本地开发日期分别记录，不补造早期发布记录。

FFmpeg的构建来源和GPLv3许可证保留在`apps/desktop/resources/FFmpeg-README.txt`、`FFmpeg-LICENSE.txt`，也随安装包提供；程序通过独立ffprobe进程读取媒体信息。其他依赖保留各自授权和声明。
