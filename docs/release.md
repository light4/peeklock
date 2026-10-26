# 发布

## 流程

1. 修改 `Sources/PeekLockCore/Version.swift` 中的 `peekLockVersion`（例如 `0.2.0`），提交并推送到 `main`。
2. 打 tag 并推送：

   ```bash
   git tag -a v0.2.0 -m "PeekLock 0.2.0"
   git push origin v0.2.0
   ```

3. `.github/workflows/release.yml` 自动执行：
   - 校验 tag 与 `Version.swift` 一致，不一致则失败
   - 运行 swift-format 检查，以及包含真实锁定测试的 e2e（`PEEKLOCK_E2E_LOCK=1 swift test`）
   - 用 `swift scripts/package.swift --zip` 打包 release 构建并签名
   - 解压校验：sha256、codesign、CLI 版本、Info.plist 版本
   - 创建 GitHub Release `v0.2.0`，附件为 `PeekLock-0.2.0.zip` 和 `PeekLock-0.2.0.zip.sha256`，说明自动生成

在 Actions 页面手动运行 “release”（workflow_dispatch）属于**演练**：只构建，产物作为 workflow artifact 上传，不创建 Release。

`Version.swift` 是唯一的版本来源：`peeklock --version` 和 Info.plist 的 `CFBundleShortVersionString` / `CFBundleVersion` 都从这里读取。

## 签名

| 仓库 secrets | 签名方式 | 影响 |
| --- | --- | --- |
| 未配置 | ad-hoc | 能运行，但每个新版本都要重新授予辅助功能权限，因为 TCC 按签名识别 App |
| `MACOS_CERT_P12_BASE64` + `MACOS_CERT_PASSWORD` | 证书中的身份（Apple Development） | 同一证书签的各版本之间，TCC 权限可以保留 |

配置证书（在本机执行，导出时需要设置一个 .p12 密码）：

1. 打开钥匙串访问 › 我的证书，右键 “Apple Development: …” › 导出为 `peeklock.p12`。
2. 写入 secrets：

   ```bash
   base64 -i peeklock.p12 | gh secret set MACOS_CERT_P12_BASE64 -R light4/peeklock
   gh secret set MACOS_CERT_PASSWORD -R light4/peeklock   # 交互输入 .p12 密码
   rm peeklock.p12
   ```

无论哪种签名，都**没有公证（notarization）**，从浏览器下载后会被 Gatekeeper 拦下，见下文安装步骤。公证需要 Developer ID 证书，目前不在范围内。

## 从 Release 安装

```bash
gh release download v0.1.0 -R light4/peeklock -p 'PeekLock-*.zip*'
shasum -a 256 -c PeekLock-0.1.0.zip.sha256
ditto -x -k PeekLock-0.1.0.zip ~/Applications
xattr -dr com.apple.quarantine ~/Applications/PeekLock.app   # 未公证，去掉隔离属性
ln -sf ~/Applications/PeekLock.app/Contents/Helpers/peeklock ~/.local/bin/peeklock
open ~/Applications/PeekLock.app
```

首次启动或签名身份变化后，需要在 系统设置 › 隐私与安全性 › 辅助功能 中重新打开 PeekLock。
