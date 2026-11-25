# CommandC iPhone 版

CommandC 通过可互通的局域网把照片、截图和短视频发送到 Windows CtrlV 或 Mac CommandV。素材在两台设备之间直传。[电脑接收端下载](../README.md#下载与版本) · [操作图库](images/README.md)

**App Store 正式版 1.1（75）** 已在中国大陆以外的店面免费上线。中国大陆店面暂不可下载。主 App 和系统分享支持简体中文与英文。[App Store 下载](https://apps.apple.com/us/app/commandc/id6835768173)

**TestFlight 内测 1.1（80）** 测试每张截图保存后的收片与计数滚动。通过灵动岛截取时还会请求系统短暂展开。是否展开以及停留时长由 iOS 决定，新反馈待真机复测。

## 当前功能

- 相机首页与 Android CtrlC 的操作布局对齐：黑色取景页、九宫格、左上配对电脑、中央快门，左下相册图标，右下截屏/录屏入口。
- 轻触拍照，按住录像，松手或最长 30 秒结束。单张预览左上重新拍摄、右上勾选后确认上传；不提供闪光灯和镜头翻转按钮。
- “拍摄 / 连拍”可点选或左右滑动。连拍与连续截屏共用一个可调的 1–99 张上限，升级沿用原连拍设定。收起时显示包含所选值在内的四个邻近档位。若要发送超过 10 张的图集，请用支持大图集的电脑接收端预发行包。
- 相册可按当前上限选取图片，或选择一段 30 秒以内的视频。选中的素材独立发送，成功后恢复先前的连拍组。待发组可通过「待发 N 张 · 查看」切换。
- 在配有灵动岛且运行 iOS 27 或以上的 iPhone 上，可从右下「截屏 / 录屏」授权跨 App 屏幕采集。在目标 App 长按灵动岛即可截取、开始或停止录屏，或点「查看」回 App。录屏时点「查看」会结束录制并开始保存。操作按钮也可绑定 CommandC 快捷指令。
- 低于 iOS 27 的系统继续在“截屏 / 录屏”页提供系统截图和录屏的导入方式。各版本都可通过系统分享菜单发送已保存的素材。
- 扫描电脑二维码或粘贴 `imagebridge://pair` 链接；确认电脑名称后配对。
- 配对由主 App 与系统分享扩展共享。打开或回到 App 时优先连接上次已配对的电脑。地址变化时，验证原配对通过才保存新地址。
- 在系统照片或截图分享菜单选择 CommandC，确认接收电脑后发送。
- 固定二维码中的电脑证书指纹，SHA-256 校验上传；mDNS 只更新同一设备的地址，不替换证书。
- 接收端回复 `copied` 后显示成功并清理手机临时副本。失败保留待发素材和请求编号，允许重试。

JPEG/PNG 原件在 32 MB / 6400 万像素范围内保留像素，方向由接收端纠正。其他静态图片转换为最长边 4096 像素的 JPEG；视频转换为 720p MP4。图集和视频上限为 100 MB。相册原件不会删除。应用下次导入时会清理超过 24 小时的遗留临时目录。

iPhone 采用系统灵动岛和操作按钮控制。原生屏幕采集需要 iOS 27，主应用及分享扩展最低 iOS 15.1。旧系统可使用拍摄、系统截图分享和素材导入。

## 构建

原生 SwiftUI 工程位于 `apps/ios`，通过 XcodeGen 的 `project.yml` 生成，不依赖 Android 的原生模块。

```bash
brew install xcodegen
xcodegen generate --spec apps/ios/project.yml
bash scripts/ios-test.sh
```

测试脚本用于 GitHub macOS runner，需要 `RUNNER_TEMP`。它先用真机 SDK 编译原生采集代码，再启动实际接收服务验证 Swift 的配对、证书固定、单图、图集和重试，最后运行 iPhone 模拟器单元测试与界面测试。模拟器 SDK 不提供 ScreenCaptureKit，模拟器只验证入口和素材流程；剪贴板回调及模拟器结果不能代替 Windows 系统剪贴板和 iPhone 真机采集验收。

云端工作流为 `.github/workflows/ios.yml`。开发分支涉及 iOS 的推送执行测试；通过后合入主线，手动运行并勾选 `upload` 才会签名上传 TestFlight。上传前核对成功测试记录；只有发布脚本或文档变化时，可在 `tested_commit` 填写已通过测试的完整提交 SHA。工作流会逐文件比较 iOS 工程、接收端和测试脚本，任何差异都会要求重新测试。不会自动提交 App Store 审核或正式上架。

仓库 Secrets：`APPLE_CERTIFICATE_P12`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_PROFILE_APP`、`APPLE_PROFILE_SHARE`、`APPLE_PROFILE_CAPTURE`、`APPLE_API_KEY`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER`。P12 与三个描述文件使用 Base64，API 私钥保留 PEM 文本。密钥不得写入源码或日志。主应用 Bundle ID 为 `com.flechazoyq.commandv`，分享扩展为 `.share`，灵动岛扩展为 `.capture`。按 Apple DTS 澄清，无需示例中遗留的 `com.apple.developer.screen-recording` entitlement。

上传后需等待 Apple 处理完成，再把构建分配给 TestFlight 内部测试组。安装者从邀请邮件进入 TestFlight；GitHub Release 的 EXE / APK 仍对应 Windows / Android。

测试时遇到问题，可在 TestFlight 的 CommandC 页面发送反馈，也可在使用 CommandC 时通过系统截屏附上截图和说明。[Apple 的 TestFlight 反馈说明](https://developer.apple.com/cn/testflight/)

## 真机验收

1. 在 CommandC 点右下“截屏 / 录屏”，点“开始屏幕采集”，允许共享整个屏幕。
2. 切到要截图的 App，**长按屏幕顶部灵动岛里的 CommandC 活动**，直到面板展开。
3. 点「截取」后向上轻扫收起面板。等灵动岛计数增加后再截下一张。
4. 长按灵动岛后点“查看”，也可以回 CommandC 点右下“截屏 / 录屏”。点“预览并发送”，再点右上“确认并发送”。在电脑的文件夹内粘贴，Windows 按 Ctrl+V，Mac 按 ⌘V。

配有操作按钮的 iPhone 可在「设置」的「操作按钮」页面滑到「快捷指令」，打开下方的选项，在 CommandC 下选「截取一张」。开始采集后，在目标 App **长按机身操作按钮**，等计数增加后再操作。

先前已在真机验证灵动岛、操作按钮截取及单图发送。对 80 版内测，重点复测连续截屏的计数、短暂展开和是否遮挡目标 App。大图集、录屏保存及电脑端粘贴需按实际设备复测。

原相机回归：

1. 在 TestFlight 更新到本轮内部测试版本，确认左上显示原配对电脑；首次使用才需扫码，手机允许相机和本地网络权限。
2. 两端连接同一 Wi-Fi，轻触快门拍照，右上勾选并确认发送；Windows Ctrl+V 应能粘贴图片。
3. 长按快门录制短视频，松手结束；首次麦克风授权后按提示重新长按。检查预览声音、发送与最长 30 秒停止。
4. 左滑切换连拍，拍两张后打开相册：取消应保留原组；选图后只发送新选择，随后恢复原组。连拍预览右上可直接确认并发送，电脑文件剪贴板顺序应一致。
5. 从右下入口选取截图/录屏视频，或从系统分享菜单发送；再验证关闭接收、断网重试及失败时保留素材。
