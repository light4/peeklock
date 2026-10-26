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

做法与 [Ghostty](https://github.com/ghostty-org/ghostty) 相同：

| 构建 | Bundle ID | 签名 |
| --- | --- | --- |
| 本地 release（`swift scripts/package.swift`） | `io.i01.peeklock` | ad-hoc |
| 本地 debug（`--debug`，e2e 也用它） | `io.i01.peeklock.debug`，名为 “PeekLock Debug” | ad-hoc |
| GitHub Release（CI） | `io.i01.peeklock` | secrets 中的证书 |

macOS 在授予辅助功能等权限（TCC）时，会记下 App 的 designated requirement（代码要求），按 bundle ID 保存。

- ad-hoc 签名的代码要求是 `cdhash H"…"`，每次构建都不同。因此 debug 构建使用单独的 bundle ID，不会覆盖已安装 release 的授权；本地重新构建 release 后需要重新授权一次。
- CI 用证书签名，代码要求是 `identifier "io.i01.peeklock" and certificate root = H"…"`，只要证书不变，升级就无需重新授权。`release.yml` 会检查这一点。

### CI 证书

`release.yml` 把 secrets 中的 p12 导入临时 keychain，再用 `--identity "$MACOS_CERT_NAME"` 签名。没有 secrets 时退回 ad-hoc，并给出警告。

| Secret | 内容 |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64 -i cert.p12` |
| `MACOS_CERT_PASSWORD` | p12 密码 |

当前使用自签名证书 “PeekLock Code Signing”（`O=i01.io`，10 年有效）。原因：没有 Developer ID；而 Apple Development 证书会把 Apple ID 邮箱和 Team ID 写进公开的二进制。创建方法：

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=PeekLock Code Signing/O=i01.io" \
  -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "PeekLock Code Signing" \
  -out cert.p12 -passout file:p12.password
base64 -i cert.p12 | gh secret set MACOS_CERT_P12_BASE64 -R light4/peeklock
gh secret set MACOS_CERT_PASSWORD -R light4/peeklock < p12.password
```

请离线备份 `cert.p12` 和密码。证书一旦更换，已授权的用户需要重新授权一次。

如果以后有 Developer ID：把 p12 换掉，把 `MACOS_CERT_NAME` 改成 “Developer ID Application: …”，再按 Ghostty 的做法加上 `notarytool` 公证，就不再需要下面的 `xattr` 步骤。

目前没有公证（notarization），从浏览器下载后会被 Gatekeeper 拦下，见下文安装步骤。

## 从 Release 安装

```bash
gh release download v0.1.0 -R light4/peeklock -p 'PeekLock-*.zip*'
shasum -a 256 -c PeekLock-0.1.0.zip.sha256
ditto -x -k PeekLock-0.1.0.zip ~/Applications
xattr -dr com.apple.quarantine ~/Applications/PeekLock.app   # 未公证，去掉隔离属性
ln -sf ~/Applications/PeekLock.app/Contents/Helpers/peeklock ~/.local/bin/peeklock
open ~/Applications/PeekLock.app
```

首次安装时需要在 系统设置 › 隐私与安全性 › 辅助功能 中打开 PeekLock。之后只要 CI 证书不变，升级就不需要重新授权。v0.1.0 是 ad-hoc 签名，从它升级时需要再授权一次。
