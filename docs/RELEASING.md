# 构建与发布

## 本地开发包

```bash
swift run OptimizerChecks
swift build --product PromptOptimizer
python3 scripts/setup-local-signing.py
bash scripts/build-app.sh
bash scripts/build-dmg.sh
```

输出在 `dist/`，不进入 Git。只归档 .app 的 ZIP，不把正常同标识的可运行副本留在 dist，避免辅助功能授权到错误副本。DMG 构建使用 macOS 自带 hdiutil，无 Finder 自动化或第三方打包依赖；包含 App、/Applications 快捷方式及安装说明。

默认本地持久签名只适合开发和明确了解限制的小范围测试，不是 Apple Developer ID，不能据此宣传“所有 Mac 下载即用”。当前下载包仅在 Apple Silicon 上构建。不要把本地签名私钥/钥匙串/密码或真实配置放入发布产物。

## 正式 Developer ID 发布

需要你自己的 Apple Developer Program、有效的 Developer ID Application 证书和公证凭据。获取/购买账号与证书不是脚本能替代的步骤。

1. 使用 Developer ID 构建 App：

   ```bash
   OPTIMIZER_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/build-app.sh
   bash scripts/build-dmg.sh
   ```

   显式证书分支会启用 hardened runtime 和时间戳；请检查完整包和所有代码对象的签名。示例不是实际证书信息。

2. 按 [Apple 官方公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)配置 keychain profile；不把凭据写入仓库。按实际分发流程签署 DMG，然后提交、等待成功并 staple。
3. 在另一台非开发 Mac 上，从真实下载开始测试安装、系统检查、辅助功能、配置、回填、撤销、升级和卸载。macOS/芯片版本要在发布页明确列出。
4. 对完成公证的最终 DMG 重新生成 SHA-256。build-dmg 的校验文件只对应它刚生成的未公证字节；签名/staple 后不能沿用旧哈希。
5. 创建 GitHub Release，上传最终 DMG 与对应校验文件，清楚标注公证状态、支持范围、后端费用、已知问题。未完成跨机器验收时使用 prerelease，不把本地构建成功叫作稳定发行。

当前脚本只生成安装载体，不自动使用你的 Apple 账号、支付费用或上传公证。仓库提供 `ci/macos.yml.example` 持续测试模板，当前未启用。发布所用 GitHub 凭据没有 workflow 权限，因此没有创建 Actions 工作流，也未扩大权限。维护者可用具有相应仓库权限的账号将模板放入 `.github/workflows/ci.yml` 后启用；模板只运行构建/无付费模型检查，不读取签名 secrets，也不会自动发布。

## 发布前复查

- Git 跟踪清单仅有原创源码、测试、文档、脚本、无密钥模板和许可证。
- 不包含 WorkBuddy 提取物、专有提示词/代码/图标、私人日志、配置及签名材料。
- README 与实际安装包版本、架构、模型后端和测试状态一致。
- 检查 .app 签名、DMG 完整性、最终校验和；通过新机器真实下载验收。
- 升级给现有使用者前，提示保存内存原文；不自动重建其系统授权。
