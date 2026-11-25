# CtrlC / CommandC → CtrlV / CommandV · 手机素材直达电脑剪贴板

<img src="apps/mobile/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="手机发送端相机图标" width="88" />

在 Android 或 iPhone 上拍照、选图、连续截屏或录制短视频，通过局域网传给电脑。看到「已复制」后，在 Windows 按 **Ctrl+V**，在 Mac 按 **⌘V**，把素材粘贴到支持相应格式的输入框、文档或文件夹。

## 下载与版本

| 设备 | 正式版 | 预发行 / 内测 |
| --- | --- | --- |
| iPhone · CommandC | [App Store 1.1（免费）](https://apps.apple.com/us/app/commandc/id6835768173) | TestFlight 1.1（80），限已获邀请的测试者 |
| Windows x64 · CtrlV | [0.4.10 EXE](https://github.com/Flechazo-YQ/suishouchuan/releases/download/v0.4.10/CtrlV-Setup-0.4.10.exe) | [0.4.12](https://github.com/Flechazo-YQ/suishouchuan/releases/tag/receivers-v0.4.12)，显示手机实际连接状态，支持较大图集 |
| Android arm64 · CtrlC | [0.4.10 APK](https://github.com/Flechazo-YQ/suishouchuan/releases/download/v0.4.10/CtrlC-0.4.10-android-arm64.apk) | [0.4.13](https://github.com/Flechazo-YQ/suishouchuan/releases/tag/android-v0.4.13)，打开 App 时自动连接上次使用的电脑 |
| Mac · CommandV | 暂无正式版 | [0.4.12 双架构](https://github.com/Flechazo-YQ/suishouchuan/releases/tag/commandv-macos-v0.4.12)，Apple 芯片选 `arm64`，Intel 选 `x64` |

CommandC 1.1 已在中国大陆以外的 App Store 店面上线，中国大陆店面暂不可下载。Mac 预发行包要求 macOS Ventura 13 或更新版本，采用测试签名，尚未经过 Apple 公证。

[图文使用指南](docs/USER-GUIDE.md) · [iPhone 操作说明](docs/IOS.md) · [版本记录](CHANGELOG.md) · [开发与构建](docs/DEVELOPMENT.md)

## iPhone 与 Mac

1. 将 iPhone 和 Mac 连到可互通的同一局域网。在 Mac 打开 CommandV，点左侧「＋ 配对手机」。在 iPhone 打开 CommandC，用「扫描配对二维码」扫 Mac 屏幕，核对电脑名称并确认。
2. 在 iPhone 拍照，点右上角勾选并确认发送。Mac 显示「已复制」后，按 **⌘V**。单张照片可用 Mac「预览」的「文件 → 从剪贴板新建」打开。图集和视频可在 Finder 文件夹内粘贴。
3. 在配有灵动岛且运行 iOS 27 或更高版本的 iPhone 上，先在 CommandC 右下角开启屏幕采集。切到目标 App 后，**长按灵动岛**，点「截取」并向上轻扫收起面板。计数增加后可截下一张。长按灵动岛点「查看」可回 App 预览并整组发送。

<img src="docs/images/mac-received.png" alt="2017 Intel Mac 上的 CommandV 已接收 iPhone 测试照片并显示已复制，设备信息和缩略图已遮挡" width="799" />

上图来自较早的 Intel Mac 真机测试，已验证 iPhone 配对、单图接收和跨应用粘贴。0.4.12 的 Apple 芯片和 Intel 安装包均通过原生 runner 的配对、传输与剪贴板自检。[Mac 双架构构建与自检](https://github.com/Flechazo-YQ/suishouchuan/actions/runs/45348491648) · [Apple 端操作图库](docs/images/README.md)

## 看图上手：安装 → 扫码配对 → 拍照上传 → 粘贴到 AI

第一次安装并配对后，日常只需 **手机拍照并确认 → 电脑按 Ctrl+V**。

### 1. 电脑装 EXE，手机装 APK

| 设备 | 下载文件 | 安装后做什么 |
| --- | --- | --- |
| Windows x64 电脑 | [CtrlV-Setup-0.4.10.exe](https://github.com/Flechazo-YQ/suishouchuan/releases/download/v0.4.10/CtrlV-Setup-0.4.10.exe) | 安装并打开「CtrlV」，留在系统托盘 |
| Android arm64 手机 | [CtrlC-0.4.10-android-arm64.apk](https://github.com/Flechazo-YQ/suishouchuan/releases/download/v0.4.10/CtrlC-0.4.10-android-arm64.apk) | 用手机浏览器下载，按系统提示允许该来源安装 |

电脑安装完成后打开「CtrlV」，保持托盘运行；Android 手机安装完成后打开「CtrlC」，按提示允许相机权限。让两端连接到可互通的局域网，例如连接同一个家庭 Wi-Fi。电脑端应显示绿色的「正在接收」。

从「随手传」升级可直接覆盖安装，不需要卸载或重新配对。Windows 若弹出防火墙提示，允许 CtrlV 在当前局域网通信；旧规则只绑定旧程序文件，改名后需要允许新程序。

Windows 安装包也内置 APK，可通过电脑配对面板中的局域网下载地址安装。发布页提供 SHA-256 校验文件；下载源码 ZIP 不是安装软件。

Android 最低支持 Android 8（API 26）。不同厂商的权限页面可能不同。下方界面教程对应 Windows 和 Android 正式版。iPhone 操作参见 [CommandC 说明](docs/IOS.md)。

### 2. 电脑显示二维码，手机扫一扫

1. **电脑**：点击左侧「＋ 配对手机」，出现二维码。
2. **手机**：点顶部设备名称或右上角扫码图标 →「扫描配对二维码」，对准电脑屏幕。
3. **手机**：核对弹窗中的电脑名称并确认。成功后，首页左上角会显示已配对电脑；以后默认发送到它。

**电脑点击「配对手机」 → 手机点「扫描配对二维码」**（点击图片可查看大图）：

<p>
  <a href="docs/images/desktop-pairing.png"><img src="docs/images/desktop-pairing.png" alt="Windows CtrlV的配对二维码窗口，左侧为配对手机按钮" width="520" /></a>
  <a href="docs/images/phone-pairing.png"><img src="docs/images/phone-pairing.png" alt="Android 连接电脑面板，下方为扫描配对二维码按钮，设备信息已隐藏" width="300" /></a>
</p>

**请扫描自己电脑 App 中显示的二维码。上图是演示码，不能用于配对。** 配对只需做一次，不用每拍一张都重新扫码。

### 3. 手机拍照，预览后确认上传

1. 选择「拍摄」模式，轻点底部白色圆形快门。
2. 查看照片：不满意点左上「×」重拍，满意点右上绿色「✓」。
3. 在弹窗中核对目标电脑，点「确认上传」。等待手机或电脑提示「已复制」。

**① 轻点白色快门拍照 → ② 点右上绿色勾，进入上传确认：**

<p>
  <a href="docs/images/phone-camera.png"><img src="docs/images/phone-camera.png" alt="Android 拍摄首页，含九宫格、拍摄和连拍模式、底部白色快门" width="290" /></a>
  <a href="docs/images/phone-preview.png"><img src="docs/images/phone-preview.png" alt="拍照后的大图预览，左上叉号重拍，右上绿色勾确认" width="290" /></a>
</p>

<img src="docs/images/phone-confirm.png" alt="发送照片确认弹窗，点击右侧确认上传按钮即可发送到配对电脑" width="460" />

电脑收到后会显示照片和「已复制」，并短暂弹出不抢焦点的小预览。**不需要再去微信下载图片，也不需要再点一次「重新复制」。**

<img src="docs/images/desktop-received.png" alt="Windows 接收页面，照片卡片显示已复制，并提供重新复制和另存为" width="800" />

想一次发几张？切到「连拍」，连续拍摄后点缩略图查看整组，右上点 **「确认并发送」** 即可；相册多选则在确认选择后自动发送。

### 4. 回到电脑 AI 输入框，按 Ctrl+V

1. 在 **Codex 或其他支持图片粘贴的 AI 输入框** 中点一下，让光标进入输入框。
2. 按 **Ctrl+V**。看到图片附件或缩略图，就说明图片已放入输入框。
3. 输入问题，例如：**「请看看这张桌面照片，给我几个整理线缆的建议。」** 核对附件后，再自行发送给 AI。

下面是 Codex 实测粘贴后的输入框局部：图集显示为多张独立附件，横向滚动可查看后面的图片。

<img src="docs/images/ai-paste.png" alt="Codex 输入框中已经出现多张独立图片附件，当前可见编号01至06的一部分" width="800" />

单张照片同样按一次 Ctrl+V；给 Word/WPS 配图时，把光标放在文档需要插图的位置再粘贴。若目标软件不接受图片粘贴，可在电脑端点「另存为」，再使用它的插入图片功能。CtrlV不会自动提交 AI 对话。

<sub>手机为 0.4.8 真机截图，私人设备信息已按授权裁剪或遮挡；电脑为 0.4.9 界面搭配演示数据；Codex 为实际粘贴验收截图的输入区。详见 [截图说明](docs/images/README.md)。</sub>

## 原来怎么做，用了以后怎么做

| 场景 | 原来的常见流程 | 直传流程 |
| --- | --- | --- |
| 拍实物照片，让 AI 分析 | 手机拍照 → 微信文件传输助手 → 电脑微信打开图片 → 复制 → 粘贴到 AI | CtrlC 拍照 → 预览并确认上传 → 电脑 AI 输入框 Ctrl+V |
| 截几个小程序页面，让 AI 对照布局 | 每页系统截图 → 整理相册 → 传到电脑 → 逐张添加附件 | 开启悬浮截屏 → 每页点「截一张」→ 查看整组 →「确认并发送」→ Ctrl+V |
| 把已有的 10 张图发给 AI | 相册挑图 → 发微信 → 电脑下载整理 → 添加多个附件 | 左下相册图标 → 选 1–10 张并确认 → 自动传送 → Ctrl+V 粘贴独立图片 |
| 给 Word/WPS 文档配一张图片 | 拍照 → 发微信 → 电脑另存为 → 文档插入图片 | 单张拍摄并上传 → 文档定位光标 → Ctrl+V；不接受图片粘贴时另存为后插入 |

例如你在做商品页面：连续截下「首页、商品详情、下单页」，整组发到电脑，再在 AI 里粘贴三张图片，输入「请按这三个页面检查按钮间距和布局一致性」。CtrlC 与 CtrlV 负责传图；提问内容和是否发送给 AI 由你决定。

## 手机上的入口

- **拍摄**：短按快门拍照；长按录像，松手结束，最长 30 秒。预览左上「×」重拍，右上「✓」确认上传。
- **相册**：快门左边的图片图标。选择 1–10 张，确认选择后自动发送；系统相册多选后分享给「CtrlC」也可用。
- **连拍**：点模式标签，或向左滑动取景画面。连续点按快门，最多 10 张；点缩略图或「查看 N 张」预览，右上「确认并发送」一次完成。
- **截屏 / 录屏**：快门右边的图标。授权后点浮窗「截一张」收集截图，「查看图片」回 App 预览。录屏有计时和停止按钮，最长 30 秒。
- **连拍中临时做别的事**：已有照片也能进入相册或截屏/录屏。原连拍组保留，新素材单独处理；完成后恢复原组，也可点「待发 N 张 · 查看」来回切换。

系统截图与CtrlC 浮窗是两条入口：手机系统截图不会自动加入 CtrlC 图集。连续截多个页面请用浮窗「截一张」；发送已有系统截图请用相册选择或系统分享。

## 到电脑后怎么粘贴

| 素材 | 电脑剪贴板内容 | 适合放到哪里 |
| --- | --- | --- |
| 单拍或系统分享的单张图片 | 系统图片 | 支持图片粘贴的 AI 输入框、文档、图片编辑器 |
| 连拍、相册、截图图集（即使只有 1 张） | 一组独立图片文件。Mac 预发行版接收超过 10 张时会复制一个图集文件夹 | 支持文件粘贴的输入框或文件夹 |
| 视频 | MP4 文件 | 接受视频文件的输入框，或先另存为再使用 |

**Codex 桌面端已验证一次 Ctrl+V 出现 10 张独立图片。** ChatGPT 及其他客户端能否接收图片、一次接收多少张、是否支持视频，取决于目标客户端和输入框；Word/WPS 对多文件图集的处理也可能不同。传输成功不代表所有软件都支持相同粘贴方式。

电脑预览不会抢走正在输入的窗口焦点；软件不会自动替你按 Ctrl+V，也不会自动提交 AI 对话。

## 临时存储

- 手机不向系统相册保存新拍素材。待发文件暂存在 App 私有目录，上传成功或明确放弃后删除；来源相册原图不受影响。
- 多组待发素材只保留在当前运行会话中，**不是永久相册**；进程重启会清理遗留文件。失败供手动重试，不在离线很久后突然自动补发。
- 电脑照片、视频和缩略图共用 **100 MB（100,000,000 字节）**，超限后在后台按接收先后删除旧素材。图集整组淘汰，当前CtrlV复制的文件受到保护。
- 单图最多 32 MiB、6400 万像素。单个图集最多 100 MB，录像或录屏最多 30 秒。0.4.10 接收端每组最多 10 张。CommandC 1.1 的连拍与连续截屏上限可设为 1–99 张，超过 10 张时需使用支持大图集的接收端预发行包。

例如已缓存 99.27 MB，再收到 1.5 MB，会从最早收到的素材开始清理，直到回到预算内。新素材先校验和写入剪贴板，再后台清理；在途文件、解码临时文件和文件占用可能造成短暂额外空间。重要素材请另存为，缓存不作为备份。[完整缓存规则](docs/CACHE-POLICY.md)

## 当前验证与边界

- Windows 和 Android 0.4.10 已覆盖安装验证。Windows 0.4.12 安装包通过认证重连和连接状态测试。Android 0.4.13 已验证原签名、测试和安装包，真机待复测。
- iPhone 1.1 正式版通过 19 项模拟器测试和 7 项 Swift 测试。TestFlight 80 另有连续截屏计数、收片和短暂展开提示，系统是否展开以真机表现为准。
- 传输耗时取决于局域网、素材大小和处理耗时。系统保护的页面可能无法采集。

连接、权限或粘贴问题见 [使用指南](docs/USER-GUIDE.md)。反馈可到 [Issues](https://github.com/Flechazo-YQ/suishouchuan/issues)，附两端版本、系统版本和复现步骤，截图请先去掉私人内容。
