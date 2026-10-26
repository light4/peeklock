# PeekLock

PeekLock 是 macOS 上类似 [xtrlock](https://manpages.debian.org/xtrlock) 的输入锁，用 Swift + AppKit 原生实现。锁定后**屏幕内容照常显示和运行**（视频继续播放、其他 App 继续刷新），但键盘、鼠标点击、滚轮、触控板手势和媒体键都会被吞掉。鼠标指针仍能移动，只是不起作用。按下解锁热键（默认 **⌃⌥⌘U**）后，会弹出系统认证框，可用 **Touch ID** 或 **macOS 登录密码**解锁。

> 定位：防误触，防小孩或猫乱按，比如锁住正在放视频或跑演示的电脑。它**不是**安全锁屏，真正离开电脑时请用系统锁屏（⌃⌘Q）。具体原因见[已知缺口](#已知缺口)。

## 组成

| 组件 | 说明 |
| --- | --- |
| `PeekLock.app` | 菜单栏 App（无 Dock 图标）：通过菜单、全局快捷键（默认 ⌃⌥⌘L）、闲置自动锁定，带设置窗口 |
| `peeklock` CLI | 用法同 xtrlock：执行后立即锁定，解锁后退出；`-b` 同时黑屏 |
| `PeekLockCore` | 共享库：`CGEventTap` 拦截、LocalAuthentication、遮罩/角标/锁形光标 |

## 构建与安装

需要 macOS 13+ 和 Xcode（Swift 5.9+），打包脚本还需要 [uv](https://docs.astral.sh/uv/)。

```bash
swift build                                  # 调试构建（带 60 秒安全自动解锁）
uv run scripts/package.py --install          # release 构建 + 签名 + 安装
```

`package.py` 会生成 `build/PeekLock.app`，并用本机第一个 `Apple Development` 证书签名，然后安装到 `~/Applications/PeekLock.app`，再把 CLI 链接到 `~/.local/bin/peeklock`（CLI 实际位于 `PeekLock.app/Contents/Helpers/peeklock`）。可用选项：`--identity <SHA1>` 指定证书；`--adhoc` 用 ad-hoc 签名，但每次重新构建后权限都要重新授予；`--debug` 打包调试构建。

用固定的开发证书签名后，重新构建时 TCC 权限可以保留。

## 权限

拦截并吞掉输入需要 **辅助功能（Accessibility）** 权限：

1. 打开 PeekLock.app，系统会弹出授权提示；也可以从菜单栏点 “Grant Accessibility Permission…”。
2. 系统设置 › 隐私与安全性 › **辅助功能**：打开 PeekLock。
3. （可选）同一页面中的 **输入监控**：打开 PeekLock。设置窗口会显示这一项的状态，但锁定本身只依赖辅助功能权限。

在终端直接运行 `peeklock` 时，macOS 会把权限算在**终端 App** 名下（Terminal、iTerm、Ghostty 等），因此需要给终端授予辅助功能权限。不想这样做的话，可以用 `peeklock --app` 让已授权的菜单栏 App 执行锁定。

**没有权限时绝不会进入锁定状态**：如果检测到缺少辅助功能权限，或者 `CGEvent.tapCreate` 失败，就直接报错，并引导去系统设置。不会出现“看起来锁住了、其实没锁”的情况。

可以随时检查状态：

```console
$ peeklock --status
Accessibility: granted, Input Monitoring: granted
Authentication: Touch ID + password
Unlock hotkey: ⌃⌥⌘U
Secure Event Input active: false
```

## 使用

```text
peeklock            锁定（解锁成功后退出，退出码 0）
peeklock -b         锁定并黑屏（同 xtrlock -b）
peeklock --app [-b] 通知正在运行的 PeekLock.app 锁定
peeklock --status   查看权限/认证/热键状态
```

锁定期间：

- 菜单栏图标变为 🔒，每块屏幕右上角显示 “Locked · ⌃⌥⌘U to unlock”。
- 指针变为锁形。为了拿到光标控制权，PeekLock 会在锁定期间成为前台 App，解锁后切回原来的前台 App。这不影响视频播放；如果不需要锁形光标，可以在设置中关闭。
- 按解锁热键会弹出系统认证框（Touch ID 优先，可以改用密码）。认证框显示期间会**临时放行全部输入**，否则无法输入密码，最多放行 60 秒。取消、失败或超时后立即恢复拦截。

## 设置（菜单栏 › Settings…）

| 项 | 默认 | 说明 |
| --- | --- | --- |
| Unlock hotkey | ⌃⌥⌘U | 必须包含 ⌃/⌥/⌘ 之一；CLI 与 App 共用（偏好域 `com.light4.peeklock`） |
| Lock hotkey | ⌃⌥⌘L | 全局快捷键（Carbon `RegisterEventHotKey`），可关闭 |
| Auto-lock when idle | 0（关） | 闲置 N 分钟后自动锁定 |
| Show badge | 开 | 屏幕角落的锁定标记（点击穿透、不遮挡内容） |
| Padlock cursor | 开 | 锁形光标 |

调试构建（`swift build` / `package.py --debug`）会在锁定 **60 秒后自动解锁**，防止开发时把自己锁死。可以用 `PEEKLOCK_DEBUG_AUTOUNLOCK=<秒>` 调整，设为 `0` 关闭；release 构建没有这个机制。

## 与 xtrlock 对比

| | xtrlock | PeekLock |
| --- | --- | --- |
| 屏幕内容 | 保持显示 | 保持显示（`-b` 黑屏） |
| 键盘/鼠标 | X grab 全部输入 | HID 级 `CGEventTap` 吞掉，指针可移动 |
| 解锁 | 直接盲打用户密码 | 先按解锁热键，再用 Touch ID / 登录密码（LocalAuthentication） |
| 提示 | 锁形光标 | 锁形光标 + 屏幕角标 + 菜单栏图标 |
| 触发 | 命令行 | 命令行、菜单栏、全局快捷键、闲置自动锁定 |

## 实现要点

- `EventBlocker`：`CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap)`，拦截 keyDown/keyUp/flagsChanged、所有鼠标按键、滚轮、手势（gesture/magnify/swipe/rotate/smartMagnify/pressure）、平板事件和 `NX_SYSDEFINED`（媒体、音量、亮度键）。拖动事件会改写成 `mouseMoved`，所以按住按键时指针也能动。如果 tap 因超时被系统禁用（`tapDisabledByTimeout/UserInput`），会立即重新启用。
- `Authenticator`：`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`，带 60 秒超时。
- `OverlayManager`：每块屏幕一个点击穿透的角标面板，外加一个近乎透明的全屏面板用来承载锁形光标（`-b` 模式下为黑色）。面板加入所有 Space（包括全屏 Space）。

## 已知缺口

PeekLock 是普通用户态 App，以下情况**拦不住**或**有意放行**：

- **电源键 / Touch ID 键**：短按会让屏幕休眠或进入系统锁屏，长按强制关机。这些由硬件和固件处理，不经过事件流。
- **合盖、强制重启**（长按电源键、⌃⌘电源键）。
- **Secure Event Input**：如果锁定前有 App 开启了安全输入（例如焦点在密码框、某些终端开启了 Secure Keyboard Entry），macOS 不会把按键交给任何 event tap，按键会**直接穿透**。锁定时一旦检测到会输出警告，用 `peeklock --status` 也能查看。
- **指针移动是放行的**：触发角（Hot Corners）、Dock 自动显示、全屏时菜单栏滑出仍可能被指针触发。如果触发角配置成“锁定屏幕”或“开始屏幕保护程序”，也会生效。点击仍然无效。
- **认证框显示期间**：为了能输入密码，所有输入都会放行，最多 60 秒。
- **进程被结束**：其他用户或 SSH 会话可以 `pkill PeekLock` / `pkill peeklock` 解锁。xtrlock 同样如此；CLI 收到 SIGTERM/SIGHUP 时会清理后退出。
- **辅助技术**：语音控制、Siri、切换控制等可能绕过。
- **调试构建**：60 秒后自动解锁。

需要实测确认的系统组合键（⌘Tab、⌘Q、⌥⌘Esc、⌃⌘Q、⌘Space、F11/调度中心、触控板四指手势）：见下表，验收后更新。

| 输入 | 预期 | 实测 |
| --- | --- | --- |
| 普通按键 / 修饰键 | 拦截 | 待验收 |
| ⌘Tab / ⌘Q / ⌥⌘Esc / ⌘Space | 拦截 | 待验收 |
| ⌃⌘Q（系统锁屏） | 拦截 | 待验收 |
| 媒体键 / 音量 / 亮度 | 拦截 | 待验收 |
| 点击 / 滚轮 / 拖动 | 拦截（指针可移动） | 待验收 |
| 触控板缩放 / 轻扫 / 调度中心手势 | 拦截 | 待验收 |
| 电源键 / Touch ID 键 | 无法拦截 | 待验收 |

## 开发

```bash
prek install                 # git hooks：trailing whitespace、EOF、YAML、swift-format
prek run --all-files
xcrun swift-format lint --strict -r Package.swift Sources scripts/make-icon.swift
```

CI（`.github/workflows/build.yml`，macos-15）会执行 swift-format lint、debug/release 构建、CLI 冒烟测试，以及 ad-hoc 打包和签名校验。
