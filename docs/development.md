# 开发

## 目录

```text
Sources/PeekLockCore/   共享库
Sources/PeekLockApp/    菜单栏 App
Sources/CLI/            peeklock 命令行
scripts/package.py      打包 / 签名 / 安装（uv 单文件脚本）
scripts/make-icon.swift 生成 App 图标
e2e/                    端到端测试（见 testing.md）
docs/                   文档
```

## 代码检查

[prek](https://prek.j178.dev) 管理 git hooks，配置文件是 `prek.toml`：

- prek 内置 hooks：trailing whitespace、EOF、mixed line ending、YAML/TOML 语法、merge conflict、大文件、**大小写冲突**、shebang、私钥检测
- 本地 hooks：`swift-format`（format + `lint --strict`，配置 `.swift-format`），以及 `ruff format` 与 `ruff check`（配置 `ruff.toml`）

```bash
prek install
prek run --all-files
```

## CI

`.github/workflows/build.yml`（macos-15）依次执行：swift-format lint、ruff、release 构建、`uv run e2e/run.py`。实际运行的是 `uv run e2e/run.py --lock`，覆盖 debug 构建、ad-hoc 打包、签名校验、App 启动，以及真实锁定测试（托管 runner 已有辅助功能权限）。

发布流程见 [release.md](release.md)：推送 `v<版本>` tag 后，由 `.github/workflows/release.yml` 构建并创建 GitHub Release。
