# 正式分发：Developer ID 签名与 Apple 公证

## 前置条件

- Apple Developer Program 账户，以及本机钥匙串内有效且包含私钥的 **Developer ID Application** 证书。Apple Development 证书不能替代此分发证书。
- 安装 Apple Command Line Tools 或 Xcode，能够运行 `notarytool`、`stapler`、`codesign` 和 `hdiutil`。
- 通过 `notarytool store-credentials` 将公证凭据保存到钥匙串。不要将密码、私钥或导出的证书提交到仓库。

创建分发证书参考 [Apple Developer ID 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。证书文件必须与本机的私钥配对；仅有 `.cer` 文件不足以签名。

使用 Apple Account 的 App 专用密码时，在本机终端执行下列命令，按照交互提示输入账户、团队 ID 和 App 专用密码：

```sh
xcrun notarytool store-credentials codex-pulse-notary
```

## 构建与公证

先更新 `Resources/Info.plist` 的版本号和构建号，正式分发使用新版本，避免覆盖已发布版本的安装包和校验值。

```sh
security find-identity -v -p codesigning
CODEX_PULSE_SIGN_IDENTITY='Developer ID Application: 证书中的姓名 (团队ID)' \
CODEX_PULSE_NOTARY_PROFILE='codex-pulse-notary' \
./scripts/notarize-release.sh
```

脚本在独立的 `.build/notarization.*` 目录中使用 release 配置构建，并包含语言资源及 MIT 许可证；不修改本机已安装应用或账号数据。

1. 检查有效证书和钥匙串凭据，使用 Developer ID 签名应用并启用 Hardened Runtime 和安全时间戳。
2. 提交应用 ZIP，只有 Apple 返回 `Accepted` 后才附加并验证应用公证凭证。
3. 将带凭证的应用打包为 DMG，签名 DMG，提交 Apple 公证并附加 DMG 凭证。
4. 校验应用及 DMG 的签名、公证凭证、Gatekeeper 评估与 DMG 完整性。最终安装包保存到 `.build/dist/notarized/`，校验值与 Apple 提交结果、日志保存于本次工作目录。

任何签名、公证或校验失败都会终止流程，不会生成新的最终交付包。发生网络中断时，先使用日志中的提交 ID 查询 Apple 处理状态，避免直接重复提交。凭证附加后不要修改应用内容或重新签名。

## 发布验收

- 挂载最终 DMG，校验其中应用的签名和附加凭证，检查架构、最低 macOS 版本和语言资源。
- 确认打包内容不包含登录凭据或运行时账号数据。
- 在新 Git 标签对应的 GitHub Release 上传已公证 DMG，发布说明注明签名和公证结果，并使用最终文件的大小及 SHA-256。
- 下载 GitHub 安装包核对校验值，再验证安装与首次启动。

Apple 流程参考：[自定义公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

## 当前进度（2026-10-02）

正式分发脚本已准备。当前本机检查仅发现 Apple Development 证书；Developer ID Application 证书与公证钥匙串配置待提供。尚未执行真实 Developer ID 签名、Apple 公证或重新发布正式安装包。

已通过：脚本语法与差异检查，缺少参数或无效证书时在构建和提交前停止，release 构建、DMG 完整性及挂载后应用签名检查，语言资源、许可证与无账号凭据打包检查，以及 99 项自动化测试。该验收包为本地 ad-hoc 签名，仅用于验证打包流程。
