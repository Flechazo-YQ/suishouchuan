# CommandV iPhone 版

CommandV 通过同一 Wi-Fi 把照片、截图和短视频发送到现有 Windows CtrlV 接收端。照片不经过业务云服务器。GitHub Actions 的 macOS 机器仅编译源码、签名并上传测试安装包。

## 当前功能

- 扫描电脑二维码或粘贴 `imagebridge://pair` 链接；确认电脑名称后配对。
- 配对保存在 iOS Keychain；主应用与系统分享扩展通过指定 Keychain 访问组共享配对。
- 拍照、相册多选、预览移除、1–10 张图集，以及最长 30 秒的视频。
- 在系统照片或截图分享菜单选择 CommandV，确认接收电脑后发送。
- 固定二维码中的电脑证书指纹，SHA-256 校验上传；mDNS 只更新同一设备的地址，不替换证书。
- Windows 回复 `copied` 后显示成功并清理手机临时副本。失败保留待发素材和请求编号，允许重试。

JPEG/PNG 原件在 32 MB / 6400 万像素范围内保留像素，方向由接收端纠正。其他静态图片转换为最长边 4096 像素的 JPEG；视频转换为 720p MP4。图集和视频上限为 100 MB。相册原件不会删除。应用下次导入时会清理超过 24 小时的遗留临时目录。

iPhone 不提供 Android 的悬浮截屏按钮；截图使用 iOS 系统截图与分享菜单。代码部署目标为 iOS 15.1，后续系统兼容性以实机测试为准。

## 构建

原生 SwiftUI 工程位于 `apps/ios`，通过 XcodeGen 的 `project.yml` 生成，不依赖 Android 的原生模块。

```bash
brew install xcodegen
xcodegen generate --spec apps/ios/project.yml
bash scripts/ios-test.sh
```

测试脚本用于 GitHub macOS runner，需要 `RUNNER_TEMP`。它先启动实际接收服务验证 Swift 的配对、证书固定、单图、图集和重试，再运行 iPhone 模拟器单元测试与界面测试。测试中的剪贴板回调检查已接收图片，不代替 Windows 系统剪贴板和 iPhone 真机验收。

云端工作流为 `.github/workflows/ios.yml`。开发分支和主线涉及 iOS 的推送执行测试；手动运行并勾选 `upload` 才会签名上传 TestFlight。不会自动提交 App Store 审核或正式上架。

仓库 Secrets：`APPLE_CERTIFICATE_P12`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_PROFILE_APP`、`APPLE_PROFILE_SHARE`、`APPLE_API_KEY`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER`。P12 与两个描述文件使用 Base64，API 私钥保留 PEM 文本。密钥不得写入源码或日志。主应用 Bundle ID 为 `com.flechazoyq.commandv`，分享扩展为 `com.flechazoyq.commandv.share`。

## 真机验收

1. 在 iPhone 安装 TestFlight，加入已处理完成的测试构建。
2. 两端连接同一 Wi-Fi；Windows 打开 CtrlV 配对二维码，手机允许相机和本地网络权限。
3. 拍一张测试照片，预览确认发送；手机应提示“已复制到电脑”，Windows Ctrl+V 能粘贴图片。
4. 从相册选两张图片发送，验证顺序及 Windows 文件剪贴板；截图通过系统分享入口发送。
5. 验证短视频、关闭接收、撤销配对、断网重试及失败时保留素材。

TestFlight 上传成功、Apple 完成处理、安装到手机和完整业务实测是不同状态，交付时分别记录。中国大陆正式分发资料在提审前按实际功能核实，本页不声明已满足备案或审核要求。
