# 使用

## 命令行

```text
peeklock            锁定（解锁成功后退出，退出码 0）
peeklock -b         锁定并黑屏（同 xtrlock -b）
peeklock --app [-b] 通知正在运行的 PeekLock.app 锁定
peeklock --status   查看权限/认证/热键状态
peeklock --help     帮助；未知参数退出码为 2
```

CLI 收到 SIGTERM 或 SIGHUP 时会先解锁再退出，因此可以通过 SSH 用 `pkill peeklock` 解锁。

## 菜单栏 App

菜单提供 “Lock Input”、“Lock Input & Blank Screen”、Settings… 和权限引导。也可以通过全局快捷键（默认 ⌃⌥⌘L）或闲置自动锁定来锁定。

## 锁定期间

- 视频、其他 App 照常显示和运行；键盘、点击、滚轮、触控板手势和媒体键都被吞掉；指针可以移动。
- 菜单栏图标变为 🔒，每块屏幕右上角显示 “Locked · ⌃⌥⌘U to unlock”。
- 指针变为锁形。为了拿到光标控制权，PeekLock 会在锁定期间成为前台 App，解锁后切回原来的前台 App。可在设置中关闭锁形光标。
- 按解锁热键（默认 ⌃⌥⌘U）弹出系统认证框（Touch ID 优先，可改用登录密码）。认证期间只放行发往认证框的普通按键和点击，详见[安全模型](security.md)。认证框最多显示 60 秒；取消、失败或超时后，立即回到完全锁定。

## 设置（菜单栏 › Settings…）

| 项 | 默认 | 说明 |
| --- | --- | --- |
| Unlock hotkey | ⌃⌥⌘U | 必须包含 ⌃/⌥/⌘ 之一；CLI 与 App 共用（偏好域 `io.i01.peeklock`） |
| Lock hotkey | ⌃⌥⌘L | 全局快捷键（Carbon `RegisterEventHotKey`），可关闭 |
| Auto-lock when idle | 0（关） | 闲置 N 分钟后自动锁定 |
| Show badge | 开 | 屏幕角落的锁定标记（点击穿透、不遮挡内容） |
| Padlock cursor | 开 | 锁形光标 |

调试构建（`swift build` / `package.py --debug`）会在锁定 **60 秒后自动解锁**，防止开发时把自己锁死。可以用环境变量 `PEEKLOCK_DEBUG_AUTOUNLOCK=<秒>` 调整，设为 `0` 关闭；release 构建没有这个机制。

## 日志

PeekLock 使用 unified logging，subsystem 为 `io.i01.peeklock`：

```bash
log stream --predicate 'subsystem == "io.i01.peeklock"' --style compact
```

会记录：启动和权限状态、锁定/解锁、按下解锁热键、认证结果，以及认证期间按目标进程统计的放行/拦截次数。认证汇总的格式（示意）：

```text
Authentication finished: success. Input during auth: ALLOWED 12x -> 812 /System/Library/…/coreautha; BLOCKED 3x -> 455 /Applications/Safari.app/…
```
