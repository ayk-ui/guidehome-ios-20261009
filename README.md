# 导游之家 iOS 原生工程

这是原生 iOS App 的 Xcode 源码工程，不是 IPA 安装包。App 在自己的全屏 WKWebView 内打开现有界面，没有 Safari 地址栏、主屏幕安装说明或额外 App 页面。原有网站后台、账号、头像和资料继续使用同一套服务。

本目录只包含源码，不包含 IPA、签名证书、描述文件或苹果账号密码。源码静态检查不能替代 Xcode 编译和实体 iPhone 验证；对应安装包及编译结果请查看本项目的 GitHub Actions 和 Releases。安装到自己的 iPhone 仍需个人签名。

默认入口：`https://dyzj-ios-tingt02191010.netlify.app/ios-v3-0-1/mobile/`。后台 API 保持原样。站内页面在 App 打开；外部用户点击的网页链接交给 Safari，电话/邮件链接交给系统。原有照片/文件输入使用 WebKit 系统选择器。登录数据保存在 App 自己的持久 WebKit 数据区。

## 有 Mac：免费个人设备运行

1. 用 Xcode 打开 `GuideHome.xcodeproj`，选择 `GuideHome` target。
2. 在 Signing & Capabilities 选自己的 Personal Team，并把 Bundle Identifier 改成自己唯一的值。Apple ID 只在你本机的 Xcode 登录，不需要发给任何人。
3. 连接并信任自己的 iPhone，按系统提示启用 Developer Mode；选择该设备后点 Run。免费 Personal Team 可用于个人真机测试，其描述文件通常 7 天到期，到期后重新用 Xcode 签名运行。

Xcode 编译未签名包：`bash scripts/build.sh unsigned`。产物在 `build/unsigned/GuideHome-unsigned.ipa`；**未签名包不能直接安装到 iPhone**。

已有合法 Apple 签名配置时，可以运行 `GUIDE_DEVELOPMENT_TEAM=你的TeamID GUIDE_BUNDLE_ID=你的BundleID bash scripts/build.sh archive`。导出使用自己准备的合法导出配置：`GUIDE_EXPORT_OPTIONS=/你的配置路径.plist bash scripts/build.sh export`。脚本不会替你登录 Apple ID 或获取证书；没有相应签名条件时无法获得可安装 IPA。

## 只有 Windows：自己的 GitHub 编译

将本 `GuideHome` 文件夹的内容放在自己的公开 GitHub 仓库根目录，确保 `.github/workflows/build-ios-unsigned.yml` 已提交到默认分支。在 Actions 选择 **Build unsigned iOS app to Release → Run workflow** 并选择默认分支。工作流使用标准 `macos-15` 环境编译，成功后在 Releases 下载 `unsigned-运行ID-重试次数` 中的 `GuideHome-unsigned.ipa`。

这个流程使用 GitHub 自动提供的短期仓库令牌保存安装包，无需上传 Apple 密码或签名密钥。公开仓库的标准运行环境免费；产物保存到 Releases，不占 Actions artifact 配额。生成的仍是未签名 IPA，需要在自己的电脑上使用自己的苹果账号进行个人设备签名安装，例如 Windows 的 AltStore Classic。工作流不会更改计费设置或创建苹果账号。

## 工程边界与检查

最低 iOS 15，iPhone 竖屏。UI 业务代码由当前固定 HTTPS 入口加载，联网时同步现有后台；不在 Swift 中复制用户资料或读取 Web 登录 token。颜色桥接采用隔离脚本世界、每次控制器随机消息名、主框架来源验证和严格六位 hex 格式，仅更新系统状态栏背景。没有通用原生 HTTP bridge、ATS 放宽、用户代理伪装或忽略 TLS 错误。

发布前应在实际 Xcode 和 iPhone 验证：登录、后台更改姓名/头像后的同步、各内部页面、照片选择、外部链接、断网重试和重新打开 App。静态校验不能替代编译或真机检查。

官方依据：[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)、[WKUIDelegate](https://developer.apple.com/documentation/webkit/wkuidelegate)、[Apple 免费账号与会员比较](https://developer.apple.com/support/compare-memberships/)、[GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
