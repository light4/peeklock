# 安装与权限

## 构建与安装

需要 macOS 13+ 和 Xcode（Swift 5.9+）。不依赖 Python 或其他第三方工具。

```bash
swift build                                  # 调试构建（带 60 秒安全自动解锁）
swift scripts/package.swift --install         # release 构建 + 签名 + 安装
```

`scripts/package.swift` 的步骤：

1. 生成 `build/PeekLock.app`，App 可执行文件位于 `Contents/MacOS/PeekLock`，CLI 位于 `Contents/Helpers/peeklock`。CLI 不放进 `MacOS/` 目录，因为在大小写不敏感的 APFS 上，`peeklock` 和 `PeekLock` 是同一个文件。
2. 用本机第一个 `Apple Development` 证书签名。
3. 带 `--install` 时，安装到 `~/Applications/PeekLock.app`，并把 CLI 链接到 `~/.local/bin/peeklock`。

| 选项 | 说明 |
| --- | --- |
| `--install` | 安装到 `~/Applications`，并链接 CLI |
| `--debug` | 打包调试构建（锁定 60 秒后自动解锁） |
| `--identity <SHA1>` | 指定签名证书 |
| `--adhoc` | ad-hoc 签名；每次重新构建后都需要重新授权 |
| `--zip` | 另外生成 `PeekLock-<版本>.zip` 和 `.sha256` |
| `--bin-path <目录>` | 直接使用已构建的二进制，不再运行 `swift build`（e2e 测试用） |
| `--output <目录>` | 输出目录，默认 `build/` |
| `--print-version` | 输出 `Version.swift` 中的版本号 |

用固定的开发证书签名后，重新构建时 TCC 权限可以保留。

## 权限

拦截并吞掉输入需要**辅助功能（Accessibility）**权限：

1. 打开 PeekLock.app，系统会弹出授权提示；也可以从菜单栏点 “Grant Accessibility Permission…”。
2. 系统设置 › 隐私与安全性 › **辅助功能**：打开 PeekLock。
3. （可选）同一页面的 **输入监控**：打开 PeekLock。

在终端直接运行 `peeklock` 时，macOS 会把权限算在**终端 App** 名下（Terminal、iTerm、Ghostty 等）。如果不想给终端授权，可以用 `peeklock --app` 让已授权的菜单栏 App 执行锁定。

**没有权限时绝不会进入锁定状态**：缺少辅助功能权限，或者任意一个 `CGEventTap` 创建失败时，都会报错并引导去系统设置，不会出现“看起来锁住了、其实没锁”的情况。

```console
$ peeklock --status
Accessibility: granted, Input Monitoring: granted
Authentication: Touch ID + password
Unlock hotkey: ⌃⌥⌘U
Secure Event Input active: false
```
