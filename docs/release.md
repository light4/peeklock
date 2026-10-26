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

macOS 在授予辅助功能等权限（TCC）时，会记录 App 的 **designated requirement**（代码要求），之后每次启动都按它识别 App：

| 签名方式 | designated requirement | 影响 |
| --- | --- | --- |
| ad-hoc（`--adhoc`） | `cdhash H"…"`，每次构建都不同 | **每个新版本、每次重新构建都要重新授权** |
| 自签名证书 “PeekLock Code Signing” | `identifier "io.i01.peeklock" and certificate root = H"…"` | 只要证书不变，权限在各版本之间一直有效 |

因此，本地构建和 CI 发布都使用同一个**自签名**证书。不用 Apple Development 证书，是因为它会把 Apple ID 邮箱和 Team ID 写进公开发布的二进制。自签名证书不经 Apple 信任：`security find-identity -v` 不会列出它，属于正常现象；codesign 和 TCC 都可以正常使用。

### 创建签名身份（每台开发机一次）

身份放在独立 keychain `~/.config/peeklock/signing/` 中（目录权限 700），不改动登录钥匙串；`scripts/package.swift` 默认从这里读取，并用同目录的 `keychain.password` 解锁。

```bash
umask 077; S=~/.config/peeklock/signing; mkdir -p "$S"; cd "$S"
uuidgen > keychain.password; uuidgen > p12.password
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=PeekLock Code Signing/O=i01.io" \
  -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "PeekLock Code Signing" \
  -out peeklock-signing.p12 -passout file:p12.password
KC="$S/peeklock-signing.keychain-db"
security create-keychain -p "$(cat keychain.password)" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$(cat keychain.password)" "$KC"
security import peeklock-signing.p12 -k "$KC" -P "$(cat p12.password)" -f pkcs12 -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat keychain.password)" "$KC"
rm key.pem
```

换一台机器时，不要重新生成证书（否则会变成“另一个 App”），而是把 `peeklock-signing.p12` 和 `p12.password` 带过去，从 `security create-keychain` 那一步开始执行。

### CI 使用同一证书

```bash
S=~/.config/peeklock/signing
base64 -i "$S/peeklock-signing.p12" | gh secret set MACOS_CERT_P12_BASE64 -R light4/peeklock
gh secret set MACOS_CERT_PASSWORD -R light4/peeklock < "$S/p12.password"
```

配置后，`release.yml` 会把证书导入临时 keychain 并用它签名；没有这两个 secrets 时退回 ad-hoc 签名并给出警告。

无论哪种签名，都**没有公证（notarization）**，从浏览器下载后会被 Gatekeeper 拦下，见下文安装步骤。

## 从 Release 安装

```bash
gh release download v0.1.0 -R light4/peeklock -p 'PeekLock-*.zip*'
shasum -a 256 -c PeekLock-0.1.0.zip.sha256
ditto -x -k PeekLock-0.1.0.zip ~/Applications
xattr -dr com.apple.quarantine ~/Applications/PeekLock.app   # 未公证，去掉隔离属性
ln -sf ~/Applications/PeekLock.app/Contents/Helpers/peeklock ~/.local/bin/peeklock
open ~/Applications/PeekLock.app
```

首次安装时需要在 系统设置 › 隐私与安全性 › 辅助功能 中打开 PeekLock。之后只要签名证书不变，升级不需要重新授权。v0.1.0 是 ad-hoc 签名，从它升级时需要授权一次。
