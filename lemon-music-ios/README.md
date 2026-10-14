# 柠檬音乐 iOS 客户端（LemonMusic）

基于 [lemon-music（柠檬音乐）](https://github.com/jia070310/lemon-muisc) 开放 API（`/api/v1`）的 **iOS 原生客户端**。
连接你自托管的柠檬音乐服务器（飞牛 NAS / Docker / 服务器），在 iPhone / iPad 上浏览曲库、播放、管理歌单。

> 本客户端不内置任何音源与曲库，仅作为你自有服务器的播放器。请仅用于个人已合法授权的音乐资源管理。

## 功能

- 🔐 服务器连接与登录（账号密码，Bearer 会话，Keychain 保存）
- 🎵 歌曲列表：分页加载、搜索、播放全部
- 💿 专辑 / 歌手浏览与详情页
- 📃 用户歌单：查看、播放、新建、把歌曲加入歌单
- ▶️ 流式播放：进度拖拽、上一首/下一首、随机、列表/单曲循环
- 🔒 锁屏 / 控制中心播放控制（后台音频）
- 📝 歌词显示（LRC，自动滚动）
- 🍋 自研 App 图标（来自上游项目 icon）

暂未包含（路线图）：在线音源搜索/下载、标签编辑、情绪地图、下载队列。
这些功能请先用 Web 端完成，客户端聚焦「曲库 + 播放」。

## 仓库结构

```
lemon-music-ios/
├── LemonMusic/                 # Swift 源码（文件夹同步组，Xcode 自动收集）
│   ├── LemonMusicApp.swift
│   ├── Models/                 # API 数据模型
│   ├── API/                    # /api/v1 客户端
│   ├── Player/                 # AVPlayer 播放内核
│   ├── Support/                # 会话、封面、歌词解析
│   ├── Views/                  # SwiftUI 界面
│   └── Assets.xcassets/        # 图标与主题色
├── Config/Info.plist
├── LemonMusic.xcodeproj/       # 预生成 Xcode 工程（Xcode 16+）
├── project.yml                 # XcodeGen 备用工程定义
├── scripts/package-ipa.sh      # 打包 .ipa
└── .github/workflows/          # CI：自动构建 .ipa
```

## 构建方式

### 方式 A：GitHub Actions 自动构建（无需 Mac）⭐推荐

1. 把本目录推送到你的 GitHub 仓库（保持目录为仓库根目录）：
   ```bash
   cd lemon-music-ios
   git init && git add . && git commit -m "LemonMusic iOS client"
   git remote add origin https://github.com/<你>/lemon-music-ios.git
   git push -u origin main
   ```
2. 打开仓库 **Actions** 页，等待 `Build iOS IPA` 跑完（约 5–10 分钟）。
3. 在该次运行的 **Artifacts** 里下载 `LemonMusic-ipa`，得到未签名的 `LemonMusic.ipa`。
4. 打 tag（`v1.0.0` 等）会自动把 ipa 挂到 GitHub Release。

### 方式 B：Mac + Xcode 本地构建

- **Xcode 16+**：直接打开 `LemonMusic.xcodeproj`，在 Target → Signing & Capabilities 里选择你的 Team（个人免费 Apple ID 即可），真机运行。
- **Xcode 15 或工程打不开**：`brew install xcodegen && xcodegen generate` 重新生成工程。

命令行出 ipa：

```bash
xcodebuild -project LemonMusic.xcodeproj -scheme LemonMusic -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/LemonMusic.xcarchive \
  archive CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
bash scripts/package-ipa.sh build/LemonMusic.xcarchive build/LemonMusic.ipa
```

## 自签名安装

拿到 `LemonMusic.ipa` 后，任选一种安装方式：

| 方式 | 说明 | 有效期 |
|------|------|--------|
| **AltStore / SideStore** | 免费 Apple ID 自签安装，AltServer 定期续签 | 7 天（可自动续签） |
| **Sideloadly** | 数据线/WiFi 安装，支持免费 Apple ID | 7 天 |
| **TrollStore** | 免签永久安装（越狱漏洞设备） | 永久 |
| **自己的开发者证书** | 用 iOS App Signer / Xcode 重签后安装 | 1 年（个人/企业证书视类型） |

> 提示：免费 Apple ID 自签需要 7 天重签一次（AltStore/SideStore 可后台自动续签）。
> 如果你有自己的开发者证书，用 Xcode 打开工程直接真机安装也可以，或用 iOS App Signer 对 ipa 重签。
> 由于签名的应用同一时刻限量 3 个（免费账号），必要时可改 `project.yml` / 工程里的 `PRODUCT_BUNDLE_IDENTIFIER` 为自己的 ID。

## 使用

1. 先在 NAS / Docker 部署好柠檬音乐服务端（见[上游 README](https://github.com/jia070310/lemon-muisc)），完成初始账号设置。
2. 打开 App，填服务器地址，例如 `http://192.168.1.10:7983`（可省略 `http://`），输入用户名密码登录。
3. 服务器曲库为空时，请先在 Web 端「设置 → 文件路径」配置音乐目录并扫描。

### 网络与证书说明

- **HTTP（局域网）**：开箱即用（App 已放开 ATS 限制）。
- **HTTPS 有效证书**：开箱即用。
- **HTTPS 自签名证书**：登录界面打开「允许自签名证书」。注意：音频流由系统 AVPlayer 拉取，自签名证书下**流播放可能仍会失败**（iOS 系统限制），API/封面不受影响。局域网建议直接用 HTTP，或给服务器配一个有效证书（如 Let's Encrypt / 内网 CA）。

## 已知限制

- 歌单写入走服务端整体覆盖语义（`PUT /library/playlists`），多端同时编辑歌单可能互相覆盖。
- 播放票据（`?ticket=`）默认 2 小时有效，超长挂机后如遇播放失败请重新点播。
- 在线曲目播放依赖你在服务端导入的音源脚本，客户端不做音源解析。

## 开源协议

MIT（与上游项目一致）。App 图标来自上游项目 `icon.png`。
