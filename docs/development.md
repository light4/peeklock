# 开发

## 目录

```text
Sources/PeekLockCore/   共享库
Sources/PeekLockApp/    菜单栏 App
Sources/CLI/            peeklock 命令行
scripts/package.swift   打包 / 签名 / zip / 安装（swift scripts/package.swift --help）
scripts/make-icon.swift 生成 App 图标
e2e/                    端到端测试，SwiftPM 测试目标 E2E（见 testing.md）
docs/                   文档
```

## 代码检查

[prek](https://prek.j178.dev) 管理 git hooks，配置文件是 `prek.toml`：

- prek 内置 hooks：trailing whitespace、EOF、mixed line ending、YAML/TOML 语法、merge conflict、大文件、**大小写冲突**、shebang、私钥检测
- 本地 hooks：`swift-format`（format + `lint --strict`，配置 `.swift-format`）

```bash
prek install
prek run --all-files
```

## CI

`.github/workflows/build.yml`（macos-15）依次执行：swift-format lint、release 构建、`PEEKLOCK_E2E_LOCK=1 swift test`。e2e 覆盖 debug 构建、ad-hoc 打包、签名校验、zip、App 启动，以及真实锁定测试（托管 runner 已有辅助功能权限）。

仓库只用 Swift 和系统自带命令，没有 Python 或其他运行时依赖。

发布流程见 [release.md](release.md)：推送 `v<版本>` tag 后，由 `.github/workflows/release.yml` 构建并创建 GitHub Release。
