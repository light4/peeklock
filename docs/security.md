# 安全模型与已知缺口

PeekLock 用来**防误触**，防小孩或猫乱按，**不是**安全锁屏。真正离开电脑时请用系统锁屏（⌃⌘Q）。

## 认证期间的输入过滤

认证框必须能接收输入（输入密码、点“使用密码”或“取消”），但不能借此操作其他 App。早期版本在认证期间放行全部输入，可以借此绕过锁定；现在改为两层过滤：

1. **HID 层**只放行普通按键、修饰键和鼠标按键。带 ⌘ 或 ⌃ 的组合键（⌘Tab、⌘Q、⌥⌘Esc、⌃⌘Q、⌘Space 等）、滚轮、手势、媒体/系统键一律拦截。
2. **已标注会话层**按事件的目标进程过滤，只放行以下进程，其余一律丢弃：
   - `LocalAuthentication.framework`（coreautha、coreauthd）
   - `LocalAuthenticationUI.framework`（LocalAuthenticationRemoteService）
   - `LocalAuthenticationCoreUI.framework`
   - `SecurityAgent.bundle`（旧版 macOS 的密码面板）
   - PeekLock 自身

每次认证结束，日志都会记录各目标进程被放行或拦截的次数（见[日志](usage.md#日志)）。如果将来某个 macOS 版本由其他进程绘制认证框，可以从 `BLOCKED … -> <路径>` 中看到它。

## 已知缺口

以下情况 PeekLock **拦不住**或**有意放行**：

- **电源键 / Touch ID 键**：短按会让屏幕休眠或进入系统锁屏，长按强制关机。这些由硬件和固件处理，不经过事件流。
- **合盖、强制重启**（长按电源键、⌃⌘电源键）。
- **Secure Event Input**：如果锁定前有 App 开启了安全输入（例如焦点在密码框、终端开启了 Secure Keyboard Entry），macOS 不会把按键交给任何 event tap，按键会**直接穿透**。锁定时一旦检测到会输出警告，`peeklock --status` 也能查看。
- **指针移动是放行的**：触发角（Hot Corners）、Dock 自动显示、全屏时菜单栏滑出仍可能被指针触发。如果触发角配置成“锁定屏幕”或“开始屏幕保护程序”，也会生效。点击仍然无效。
- **认证框显示期间**：发往认证框的普通按键和点击会被放行。
- **进程被结束**：其他用户或 SSH 会话可以 `pkill PeekLock` / `pkill peeklock` 解锁，xtrlock 同样如此。
- **辅助技术**：语音控制、Siri、切换控制等可能绕过。
- **调试构建**：60 秒后自动解锁。
