# 发布 Jeff

当前下载包面向 macOS 14 及以上的 Apple Silicon Mac。首版为未公证预览版，请在 Release 标题、说明和下载入口中保留这一信息。

## 本地打包

1. 在 `Resources/Info.plist` 更新 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 执行 `make lint`、`make typecheck` 和 `make package`。
3. 使用 `codesign --verify --strict --verbose=2 dist/Jeff.app` 检查签名。
4. 在 `dist/` 中执行 `shasum -a 256 -c SHA256SUMS.txt` 检查 ZIP 校验值。
5. 用全新克隆核对开发构建，再从下载的 ZIP 解压应用，人工核对启动、权限、服务配置、划词、截图、剪贴板和错误提示。构建通过不代表这些交互已经通过。

打包默认使用 ad-hoc 签名，不读取或分发本机证书。`.dev-cert/`、`.build/`、`analysis/`、`dist/` 和根目录的旧发布包均不进入公开 Git 仓库。

## GitHub Release

从已核对的提交创建版本标签，例如 `v1.0.0`。Release 说明记录支持平台、变更、签名状态和已知限制，上传以下附件：

```text
Jeff-1.0.0-macos-arm64.zip
SHA256SUMS.txt
```

先创建草稿并上传全部附件，再发布。未公证版本勾选 Pre-release。GitHub 自动生成的 Source code ZIP 是源码，不是可直接运行的应用安装包。

发布后从 Release 页面实际下载 ZIP，核对文件摘要和解压后的签名。人工验收不需要向模型发送私人内容，可以使用自拟示例。

## Developer ID 签名与公证

具备 Apple Developer ID Application 证书后，可以覆盖默认签名参数：

```bash
make package \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  SIGN_OPTIONS="--options runtime --timestamp"
```

随后使用 Apple 的 `notarytool` 提交 ZIP。公证成功后，对 `dist/Jeff.app` 执行 `stapler staple` 和 `stapler validate`，重新压缩应用并更新 SHA-256，再上传最终 ZIP。当前 `make package` 不会自动公证，请勿将仅完成签名的包描述为已公证。

签名私钥和公证凭据只留在受控的本机钥匙串或发布环境 Secrets 中，不放入源码、Release 附件或日志。正式发行前还需在干净环境核对 Hardened Runtime 下的取词、截图和权限行为。
