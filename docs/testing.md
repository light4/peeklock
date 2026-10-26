# 测试

项目只有端到端（e2e）测试，没有单元测试。测试代码在 `e2e/`，用 pytest 编写，由 uv 单文件脚本 `e2e/run.py` 运行，依赖 pytest 和 pyobjc-framework-Quartz，由 uv 自动安装。

```bash
uv run e2e/run.py                 # CLI + 打包测试；不会锁定输入
uv run e2e/run.py --lock          # 另外运行真正锁定输入的测试（每项几秒）
uv run e2e/run.py -- -k bundle    # -- 之后的参数直接交给 pytest
```

## 覆盖范围

| 文件 | 内容 | 何时运行 |
| --- | --- | --- |
| `test_cli.py` | `--help` / `--version` / `--status`、未知参数退出码 2、App 未运行时 `--app` 失败、无辅助功能权限时拒绝锁定（退出码 1） | 默认；最后一项只在 CI（`CI=true`）且无权限时运行，因为它会打开系统设置。GitHub 托管的 macOS runner 已有辅助功能权限，所以这一项在 CI 中实际上会跳过 |
| `test_bundle.py` | 用 `package.py --debug` 打包；检查目录结构（含大小写冲突回归）、Info.plist、codesign；启动第二个实例，确认它是 accessory App 并写入启动日志 | 默认；没有 Apple Development 证书时用 ad-hoc 签名 |
| `test_lock.py` | 真实锁定：锁定时吞掉按键和滚轮，SIGTERM 后恢复；`-b` 模式；调试构建的自动解锁 | 仅 `--lock`；CI 每次都会运行 |

### 锁定测试的原理

测试在 HID 层投递带标记的探针事件（F19 按下/抬起，以及一次零位移滚动，都没有副作用），并用本进程中一个仅监听的**会话级** tap 计数。PeekLock 的 HID tap 位于会话 tap 之前，所以锁定时探针不应到达。

每项测试都会先在未锁定状态下确认探针能够到达；如果环境本身有问题，测试会直接失败，而不会误判为通过。锁定使用调试构建，并设置 `PEEKLOCK_DEBUG_AUTOUNLOCK` 作为安全网；测试结束时一定会结束 peeklock 进程。

GitHub 托管的 macOS runner 默认已授予这些权限，而且是一次性机器，所以 CI 用 `--lock` 运行这些测试。本地运行的前提：终端 App 需要**辅助功能**（投递事件、peeklock 本身）和**输入监控**（监听 tap）权限，否则这些测试会被跳过并说明原因。

## 无法自动化的部分（人工验收）

Touch ID、密码输入和系统认证框无法自动驱动，需要人工验收。建议用调试构建（`uv run scripts/package.py --debug --install`），并开着日志：

```bash
log stream --predicate 'subsystem == "io.i01.peeklock"' --style compact
```

| 项目 | 预期 | 实测 |
| --- | --- | --- |
| 播放视频时锁定 | 视频继续播放、可见 | 待验收 |
| 普通按键 / 修饰键 | 拦截 | 待验收 |
| ⌘Tab / ⌘Q / ⌥⌘Esc / ⌘Space | 拦截 | 待验收 |
| ⌃⌘Q（系统锁屏） | 拦截 | 待验收 |
| 媒体键 / 音量 / 亮度 | 拦截 | 待验收 |
| 点击 / 滚轮 / 拖动 | 拦截（指针可移动） | 待验收 |
| 触控板缩放 / 轻扫 / 调度中心手势 | 拦截 | 待验收 |
| ⌃⌥⌘U → Touch ID | 解锁 | ✅ 通过（日志：`evaluatePolicy` 返回成功） |
| 认证框中点“使用密码”并输入密码 | 解锁；汇总显示认证框进程为 `ALLOWED` | 待验收 |
| 认证框中点取消（Stay Locked） | 保持锁定 | 待验收 |
| 认证框显示期间点击/输入其他 App、⌘Tab、滚动 | 全部拦截；汇总显示为 `BLOCKED` | 待验收 |
| 多显示器 | 每块屏幕都有角标 | 待验收 |
| 电源键 / Touch ID 键 | 无法拦截（已知缺口） | 待验收 |
