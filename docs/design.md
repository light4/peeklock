# 设计与实现

## 组成

| 组件 | 路径 | 说明 |
| --- | --- | --- |
| `PeekLockCore` | `Sources/PeekLockCore` | 共享库：事件拦截、认证、遮罩、热键、设置、日志 |
| `PeekLockApp` | `Sources/PeekLockApp` | 菜单栏 App（打包后为 `PeekLock.app`） |
| `peeklock` | `Sources/CLI` | xtrlock 风格命令行 |

App target 名为 `PeekLockApp`、CLI 源码放在 `Sources/CLI`，原因相同：大小写不敏感的文件系统上，`PeekLock` 和 `peeklock` 会冲突。

## 主要模块

- **`EventBlocker`**：两个 `CGEventTap`。
  - HID 级（`.cghidEventTap`，head insert）：拦截 keyDown/keyUp/flagsChanged、所有鼠标按键、滚轮、手势（gesture/magnify/swipe/rotate/smartMagnify/pressure）、平板事件和 `NX_SYSDEFINED`（媒体、音量、亮度键）。拖动事件改写为 `mouseMoved`，所以按住按键时指针也能动。锁定时在这里识别解锁热键。
  - 已标注会话级（`.cgAnnotatedSessionEventTap`）：事件路由后才带有目标进程 `kCGEventTargetUnixProcessID`。认证期间，这一层按目标进程过滤；平时会丢弃任何漏网的按键或点击（例如在会话层注入的合成事件）。
  - 系统因超时等原因禁用 tap（`tapDisabledByTimeout/UserInput`）时，立即重新启用。
  - 两个 tap 中任何一个装不上，都拒绝锁定。
- **`Authenticator`**：`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`，带 60 秒超时（超时后 `invalidate`）。
- **`LockController`**：状态机 `unlocked → locked → authenticating → locked/unlocked`，协调拦截、遮罩、认证、调试用自动解锁和日志。
- **`OverlayManager`**：每块屏幕一个点击穿透的角标面板（屏保层级 +1），外加一个近乎透明的全屏面板承载锁形光标（`-b` 模式下为黑色）。面板加入所有 Space（含全屏 Space）。
- **`DisplayAwake`**：锁定期间持有 IOKit `PreventUserIdleDisplaySleep` 断言（名为 `PeekLock: input locked`），解锁时释放；进程意外退出时由内核自动回收。
- **`GlobalHotkey`**：Carbon `RegisterEventHotKey`，无需额外权限。
- **`IdleMonitor`**：`CGEventSource.secondsSinceLastEventType` 轮询。
- **`Settings`**：偏好域 `io.i01.peeklock`，App 与 CLI 共用。

## 与 xtrlock 对比

| | xtrlock | PeekLock |
| --- | --- | --- |
| 屏幕内容 | 保持显示 | 保持显示（`-b` 黑屏） |
| 键盘/鼠标 | X grab 全部输入 | HID 级 `CGEventTap` 吞掉，指针可移动 |
| 解锁 | 直接盲打用户密码 | 先按解锁热键，再用 Touch ID / 登录密码（LocalAuthentication） |
| 提示 | 锁形光标 | 锁形光标 + 屏幕角标 + 菜单栏图标 |
| 触发 | 命令行 | 命令行、菜单栏、全局快捷键、闲置自动锁定 |
