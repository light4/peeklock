# PeekLock

macOS 上类似 [xtrlock](https://manpages.debian.org/xtrlock) 的输入锁，用 Swift + AppKit 原生实现。锁定后**屏幕内容照常显示和运行**（视频继续播放、其他 App 继续刷新），但键盘、点击、滚轮、手势和媒体键都会被吞掉，指针仍可移动。按 **⌃⌥⌘U** 后，用 **Touch ID** 或 **macOS 登录密码**解锁。

> 用于防误触，防小孩或猫乱按，**不是**安全锁屏。见[安全模型与已知缺口](docs/security.md)。

## 快速开始

```bash
uv run scripts/package.py --install   # 构建、签名，安装到 ~/Applications，并链接 ~/.local/bin/peeklock
open ~/Applications/PeekLock.app      # 菜单栏出现锁图标；按提示授予「辅助功能」权限
peeklock                              # 或者在命令行锁定（-b 同时黑屏）
```

锁定方式：菜单栏、全局快捷键 ⌃⌥⌘L、闲置自动锁定、`peeklock` 命令。

## 文档

- [安装与权限](docs/installation.md)
- [使用、设置与日志](docs/usage.md)
- [设计与实现](docs/design.md)：模块说明，以及与 xtrlock 的对比
- [安全模型与已知缺口](docs/security.md)
- [测试](docs/testing.md)：e2e 测试与人工验收清单
- [开发](docs/development.md)：目录结构、prek、CI
- [发布](docs/release.md)：打 tag 发布、签名，以及从 Release 安装
