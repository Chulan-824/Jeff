# 发布 Jeff

当前下载包面向 macOS 14 及以上的 Apple Silicon Mac。首版为未公证预览版，请在 Release 标题、说明和下载入口中保留这一信息。

## 本地打包

1. 在 `Resources/Info.plist` 更新 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 准备 Python 3.10 及以上，执行 `make lint`、`make typecheck` 和 `make package`。首次打包会联网安装 `Resources/DMG/requirements.txt` 中固定版本的 `dmgbuild` 到 `.build/dmg-venv/`；此依赖只用于打包，不进入应用。无需 Finder 会话或自动化权限。
3. 使用 `codesign --verify --strict --verbose=2 dist/Jeff.app` 检查签名。
4. 在 `dist/` 中执行 `shasum -a 256 -c SHA256SUMS.txt` 检查 DMG 校验值，并用 `hdiutil verify Jeff-版本号-macos-arm64.dmg` 检查磁盘映像。
5. 双击 DMG，确认安装窗口显示中文提示、左侧 Jeff、右侧 Applications 和拖拽箭头。将 Jeff 拖到 Applications，确认复制到 `/Applications/Jeff.app` 后，从“应用程序”打开应用，再推出安装磁盘。升级验收先退出旧版，再确认 Finder 替换提示。
6. 用全新克隆核对开发构建，并人工核对安装后应用的启动、权限、服务配置、划词、截图、剪贴板和错误提示。构建通过不代表这些交互已经通过。

`make dmg` 只构建应用和 DMG；`make package` 还会更新 `SHA256SUMS.txt`。安装窗口布局位于 `Resources/DMG/settings.py`，背景图位于同目录的 `background.tiff`。旧版 Release 的 ZIP 保持原样，后续 Release 以 DMG 为主下载包。

打包默认使用 ad-hoc 签名，不读取或分发本机证书。`.dev-cert/`、`.build/`、`analysis/`、`dist/` 和根目录的旧发布包均不进入公开 Git 仓库。

## 密钥存储人工验收

在隔离的 macOS 用户中使用专用临时密钥验收，先退出旧版 Jeff；不要把真实密钥内容放入截图或日志。以下项目需实机核对，构建、lint 和类型检查不代替行为验收。

| 场景 | 预期结果 |
| --- | --- |
| 全新用户首次打开服务设置 | API Key 为空，安装包不带配置 |
| 保存并重新打开 | 从应用数据目录读取配置；目录权限 `0700`，密钥文件权限 `0600` |
| 旧版钥匙串升级迁移 | 本机写入并回读成功后清理旧记录，密钥仍可使用；以后读取无需旧钥匙串 |
| 本机写入失败 | 显示错误，旧钥匙串密钥保留 |
| 迁移后旧钥匙串清理失败 | 本机密钥可用，显示清理未完成提示；重新读取会重试 |
| 待迁移清理期间旧版本更换了钥匙串密钥 | 保留两份配置并提示差异，不自动删除发生变化的旧记录 |
| 本机密钥文件损坏 | 报错并保留文件，不回退钥匙串；确认清除后可重新配置 |
| 取消“清除密钥”确认框 | 配置保持原样 |
| 确认清除，再关闭并重新打开 | 本机密钥为空，旧钥匙串记录已清理；模型、地址、历史不变 |
| 清除时旧钥匙串清理失败 | 显示提示，重开仍为空；重新读取重试清理，不恢复旧密钥 |
| 清除密钥后再处理文本 | 提示在设置中填写 API Key |
| 覆盖安装与完整卸载 | 覆盖安装保留数据；按 README 删除应用及数据后，重装为空 |

## GitHub Release

从已核对的提交创建版本标签，例如 `v1.0.0`。Release 说明记录支持平台、变更、签名状态和已知限制，上传以下附件：

```text
Jeff-版本号-macos-arm64.dmg
SHA256SUMS.txt
```

先创建草稿并上传全部附件，再发布。未公证版本勾选 Pre-release。GitHub 自动生成的 Source code ZIP 是源码，不是可直接运行的应用安装包。

发布后从 Release 页面实际下载 DMG，核对文件摘要、安装窗口和复制到“应用程序”后的签名。人工验收不需要向模型发送私人内容，可以使用自拟示例。

## Developer ID 签名与公证

具备 Apple Developer ID Application 证书后，可以覆盖默认签名参数：

```bash
make package \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  SIGN_OPTIONS="--options runtime --timestamp"
```

随后对生成的 DMG 使用同一 Developer ID Application 证书执行 `codesign --sign "Developer ID Application: Your Name (TEAMID)" --timestamp dist/Jeff-版本号-macos-arm64.dmg`，再使用 Apple 的 `notarytool` 提交该 DMG。公证成功后，对 DMG 执行 `stapler staple` 和 `stapler validate`，更新 `SHA256SUMS.txt`，再上传最终 DMG。不要在公证后重新执行 `make package`，以免覆盖已签名和附加公证票据的 DMG。当前 `make package` 不会自动签名 DMG 或公证，请勿将仅完成应用签名的包描述为已公证。

签名私钥和公证凭据只留在受控的本机钥匙串或发布环境 Secrets 中，不放入源码、Release 附件或日志。正式发行前还需在干净环境核对 Hardened Runtime 下的取词、截图和权限行为。
