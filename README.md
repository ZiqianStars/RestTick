# RestTick

macOS 菜单栏护眼休息提醒。按“实际使用电脑的时间”计时，到点用一块低调的全屏遮罩提醒你休息；遮罩里轮换低饱和风景照片，帮眼睛从屏幕前移开一会儿。

- 平台：macOS 13+
- 技术栈：SwiftUI + AppKit，Swift Package Manager，无第三方依赖
- 形态：`LSUIElement` 菜单栏应用，不显示 Dock 图标

## 功能

- **专注 / 休息计时**：默认专注 45 分钟、休息 5 分钟；到点自动弹出全屏休息遮罩。
- **只统计清醒活跃时间**：键鼠空闲 ≥ 90 秒、锁屏、屏保时自动暂停累计；回到电脑前继续。
- **媒体播放豁免**：其他进程持有“防显示器休眠”断言（看视频、`caffeinate` 等）时，即使键鼠空闲也继续计时。
- **睡眠 / 唤醒校准**：系统休眠时间不计入使用时长；唤醒后按单调时钟重新校准。
- **到期预告**：剩余 45 秒时右上角弹一个不抢焦点的小浮层，9 秒后自动消失。
- **全屏休息遮罩**：每块显示器一个窗口，淡入淡出；显示倒计时、提示语和背景图。
- **遮罩操作**：长按 3 秒跳过；可“暂停 30 分钟”或“今天不再提醒”。
- **背景图轮换**：内置 5 张护眼照片，每 18 秒切换，多屏同步；每次休息从上一张的下一张开始。
- **自定义图库**：把自己的图片放进图库目录即可优先使用。
- **开机自启**：通过 `SMAppService` 注册，需在系统设置中批准。
- **外部触发**：支持 `resttick://break` URL 与 `--break-now` 启动参数。
- **运行内统计**：菜单底部显示本次运行完成 / 跳过的休息次数（重启清零）。
- **跟随系统语言**：提供简体中文与 English，系统语言变化后自动切换，无需重启 App。

完整需求与实现状态见 [docs/requirements.md](docs/requirements.md)，模块与数据流见 [docs/architecture.html](docs/architecture.html)。

## 获取代码

```bash
git clone https://github.com/ZiqianStars/RestTick.git
cd RestTick
```

仓库地址：<https://github.com/ZiqianStars/RestTick>

## 构建与运行

### 环境

- macOS 13 或更高版本
- Swift 5.9+
- Xcode 或 Command Line Tools

脚本会检测当前工具链：如果只有 Command Line Tools，会自动选用随附的 `MacOSX26.x.sdk`，绕过 SwiftUI 宏插件缺失的问题；装有完整 Xcode 时按默认 SDK 构建。

### 一键构建并启动

```bash
./run.sh
```

它会构建 `dist/RestTick.app`、结束已在运行的 RestTick，然后打开新构建的 App。

### 手动构建

```bash
./scripts/build_app.sh release   # 或 debug
open dist/RestTick.app
```

也可以直接用 SwiftPM 编译可执行文件：

```bash
swift build -c release
```

`build_app.sh` 会组装 App Bundle、复制 `Resources/Info.plist` 与内置背景图，并做 ad-hoc 签名。

## 两个参数怎么调

打开菜单栏图标，在弹出面板里调整：

| 参数 | 默认值 | 范围 | 步长 | 说明 |
| --- | --- | --- | --- | --- |
| 专注时长 | 45 分钟 | 5–180 分钟 | 5 分钟 | 修改后立即按新周期重算剩余时间 |
| 休息时长 | 5 分钟 | 1–30 分钟 | 1 分钟 | 从下一次休息开始生效 |

两个值都会写入 `UserDefaults`（键名 `focusMinutes`、`breakMinutes`），下次启动自动恢复。面板里也提供加减按钮，适合精确调整。

## 图库怎么换图

1. 菜单栏面板点「打开图库」。
2. 目录位于：

   ```text
   ~/Library/Application Support/RestTick/Backgrounds
   ```

3. 把图片直接放进去，支持 `png`、`jpg`、`jpeg`、`heic`、`tif`、`tiff`。
4. 下次开始休息时会自动重新扫描；有自定义图片时优先使用自定义图片，不再使用内置图。

注意：

- 自定义文件名不要以 `resttick-` 开头，这个前缀保留给内置图。
- 图片会按屏幕像素长边降采样（1600–4096），并做 EXIF 方向矫正；不需要手动缩放。
- 删除自定义图片后，如果目录为空，会回退到随 App 打包的 5 张内置图。
- 内置图来自 Pexels，遵循 [Pexels License](https://www.pexels.com/license/)；原始文件见 `Resources/Backgrounds/`。

### 替换内置图

想换掉 App 自带的 5 张图，直接替换 `Resources/Backgrounds/resttick-01.jpg` … `resttick-05.jpg`，保持文件名不变，然后重新构建 App。

首次运行会把新图复制到运行时图库目录。之后 App 会按内容哈希比对内置图：重新构建后如果同名旧图内容不同，会自动覆盖，不需要手动删除。自定义图片不受影响。

## URL 与启动参数触发

App 已注册 `resttick://` URL Scheme。运行中可直接触发一次休息：

```bash
open "resttick://break"
```

`resttick://break-now` 等价。

冷启动时也可以用命令行参数：

```bash
open -a "$PWD/dist/RestTick.app" --args --break-now
# 或直接运行二进制
./dist/RestTick.app/Contents/MacOS/RestTick --break-now
```

## 测试

```bash
./scripts/test.sh
```

测试覆盖空闲判定、计时累计封顶、倒计时文案与归零、暂停/恢复累计、暂停到期判定、进度计算、跨天 / 夏令时恢复、内置图规格等纯逻辑，共 43 项断言。

当前工具链只有 Command Line Tools 时没有 XCTest，测试使用 `Tests/RestTickTests/main.swift` 里的独立断言运行器；被测逻辑集中在 `Sources/RestTickCore`，不依赖 AppKit，便于单独测试。

## 打包 DMG

```bash
./scripts/package.sh
```

输出：`dist/RestTick-<版本号>.dmg`，版本号读取自 `Resources/Info.plist`（当前 `1.0.0`）。

可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `CODESIGN_IDENTITY` | 指定 Developer ID Application 证书；不填则自动查找，找不到就用 ad-hoc 签名 |
| `NOTARY_PROFILE` | `notarytool` 钥匙串配置名；设置后自动提交公证并装订 |

首次公证前需要保存一次凭据：

```bash
xcrun notarytool store-credentials <配置名> \
  --apple-id <账号> --team-id <团队ID> --password <App 专用密码>
```

然后：

```bash
NOTARY_PROFILE=<配置名> ./scripts/package.sh
```

## 日志

使用 OSLog 统一日志，subsystem 为 `com.resttick.app`，分为 `app`、`engine`、`overlay`、`wallpaper`、`login` 五个 category：

```bash
/usr/bin/log show --predicate 'subsystem == "com.resttick.app"' --last 10m
```

## 目录结构

```text
.
├── Package.swift                 # SwiftPM 清单（macOS 13+）
├── README.md
├── .gitignore
├── run.sh                        # 构建并启动 App
├── Resources/
│   ├── Info.plist                # Bundle 信息、URL Scheme、LSUIElement
│   └── Backgrounds/              # 5 张内置护眼图
├── Sources/
│   ├── RestTick/                 # App 本体（菜单栏、计时引擎、遮罩、图库、登录项）
│   └── RestTickCore/             # 纯逻辑计时规则，供测试复用
├── Tests/
│   └── RestTickTests/main.swift  # 无框架断言运行器
├── scripts/
│   ├── build_app.sh              # 构建并组装 .app
│   ├── test.sh                   # 运行测试
│   └── package.sh                # 签名、打包 DMG、可选公证
├── docs/
│   ├── requirements.md           # 需求列表与实现状态
│   └── architecture.html         # 项目架构图
└── .vscode/launch.json           # 调试配置
```

## 使用提示

- **菜单栏图标被折叠**：菜单栏图标较多、空间不足时，macOS 会把 RestTick 的计时项折叠进隐藏区，此时需要点菜单栏右端的展开按钮才能看到。这是系统对菜单栏图标的统一处理，不是 App 隐藏了自己；减少常驻图标或使用菜单栏管理工具可以让它保持可见。
- **开机自启前先安装**：建议先把 `RestTick.app` 拖到「应用程序」文件夹再打开「开机自动启动」。直接在 `dist/` 等临时目录运行时，系统登录项注册可能失败，面板会提示“未找到登录项，请将 RestTick 移到「应用程序」文件夹后再试”。

## 已知限制

- **签名与分发**：当前默认 ad-hoc 签名，未使用 Developer ID，也未做公证。其他 Mac 首次打开可能被 Gatekeeper 拦截，需要右键“打开”；正式分发前应配置证书并公证。
- **休息结束提醒**：休息结束后没有系统通知和提示音，只在菜单栏更新状态。
- **统计不持久化**：完成 / 跳过次数仅保存在内存，重启清零；也没有按天 / 周的历史统计。
- **免打扰场景**：不检测全屏演示、视频会议或系统勿扰模式，只通过“防显示器休眠”断言做媒体豁免。
- **可访问性**：图标按钮有 `accessibilityLabel`，但遮罩文字对比度依赖图片压暗蒙版，未做专项无障碍测试。
- **图片授权**：仅保留 5 张来自 Pexels 的内置图，遵循 Pexels License；仓库内不再包含其他来源的图片素材。

## 许可证

[MIT License](LICENSE)，Copyright (c) 2026 wenjuxu。

## 状态

当前为可运行的 1.0.0 版本，已完成计时、遮罩、图库、自启、URL 触发、测试与 DMG 打包流程；代码托管在 [GitHub](https://github.com/ZiqianStars/RestTick)。
