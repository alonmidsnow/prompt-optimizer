# Prompt Optimizer · 提示词助手

把输入框里的需求，一键改成更清楚的提示词。为 **Codex 桌面**和 **Claude 桌面（含 Code 模式）**设计的 macOS 悬浮助手，不自动发送聊天。

## ⬇️ 下载 Mac 安装包（DMG）

### [点击下载 Prompt Optimizer · v0.6.0-beta.1](https://github.com/alonmidsnow/prompt-optimizer/releases/download/v0.6.0-beta.1/PromptOptimizer.dmg)

**适用：Apple 芯片（M 系列）Mac，macOS 13+。** Intel / Windows 不支持。当前是**未经过 Apple 公证的 Beta 测试包**。

下载 DMG → 打开 → 把 App 拖入“应用程序” → 启动并授权辅助功能 → 使用自己的 Codex CLI 登录或配置模型 API。

[查看版本说明与全部下载文件](https://github.com/alonmidsnow/prompt-optimizer/releases/tag/v0.6.0-beta.1) · [SHA-256 校验文件](https://github.com/alonmidsnow/prompt-optimizer/releases/download/v0.6.0-beta.1/PromptOptimizer.dmg.sha256) · [详细安装步骤](#安装和第一次使用)

受 WorkBuddy 提示词优化交互启发的独立开源实现。没有附带 WorkBuddy 源码、私有提示词、图标或账号数据，不调用其私有接口；与 OpenAI、Anthropic、WorkBuddy 无官方隶属关系。

**状态：0.6.0-beta.1 / MIT / macOS 13+。** 当前 DMG 为 Apple 芯片版本、未经 Apple 公证的测试包；终端 Claude Code、Codex CLI 的交互输入区尚未支持。跨机器安装、原生撤销及真实 API 服务仍需分别验收，不能把自动检查当作全部真实环境通过。

## 能做什么

- 点中未发送的纯文本草稿 → 悬停圆球 → 点“优化提示词” → 优化结果直接回填。
- 识别/生成/回填时旋转提示，核验成功显示绿勾，失败显示橙点。
- 菜单只有“优化提示词 / 查看原文 / 退出”。原文仅保存在本次运行内存。
- 默认调用本机 Codex CLI；也能选择自己的 OpenAI 兼容 API，无需安装 Codex CLI。
- 修改草稿、切换目标、取消或出现无效响应时停止覆盖；不会发送聊天。
- 撤销使用输入框原生 ⌘Z；Ctrl+Z 在当前未改写的优化稿上兼容映射一次 ⌘Z。原生撤销行为需按具体应用验收，失败时可查看并复制原文。

## 支持范围

| 项目 | 当前范围 |
|---|---|
| 系统 | macOS 13 或更高 |
| 下载包 | Apple Silicon / arm64；Intel 未提供或验证 |
| 输入框 | Codex 桌面、Claude 桌面里的可读多行纯文本草稿 |
| 不支持 | Windows、浏览器网页版、终端交互输入区、附件及结构化提及 |
| 模型后端 | 已登录 Codex CLI，或 OpenAI 兼容 Chat Completions API |
| 计费 | 使用你自己的模型额度/API，项目不提供公共 Key 或免费推理服务 |

## 安装和第一次使用

1. 点击页首的 **“下载 Mac 安装包（DMG）”**，或从 [Releases](https://github.com/alonmidsnow/prompt-optimizer/releases) 选择对应版本；也可按下文从源码构建。
2. 打开 DMG，把 **Codex提示词助手.app** 拖进 **Applications**，从应用程序启动，勿从 DMG 内直接运行。也支持 `~/Applications`；只保留一个运行实例。
3. 按系统提示，在“隐私与安全性 → 辅助功能”中允许这个助手控制输入框。系统验证由你自己完成。
4. 默认要求本机已有登录的 Codex CLI。没有 CLI 时按“模型配置”切换到 API。
5. 在 Codex / Claude 桌面点中可丢弃的纯文本草稿，悬停圆球并点优化。检查改写是否保留原意，不要直接相信更长的文字就更好。
6. 要撤销先尝试 ⌘Z；“查看原文”可供手动复制。退出/重启/升级会清空助手内存原文。

测试包尚未 Apple 公证，可能被 macOS 安全检查阻止。请确认来源后按 [Apple 官方说明](https://support.apple.com/102445)自行判断；不要关闭 Gatekeeper、关闭 SIP 或运行移除安全保护的命令。不了解风险时可先阅读源码和等待正式签名版本。

## 模型配置

首次启动创建：

```text
~/Library/Application Support/CodexPromptOptimizer/config.json
```

每次优化重新读取，保存后无需重启。不要把这个真实配置提交到 GitHub；Key 是本机明文，文件权限为 `0600`，不加密。仓库只带 [无密钥模板](config.example.json)。

### 默认：Codex CLI

```json
{
  "backend": "codex_cli",
  "timeout_seconds": 120,
  "codex": { "executable_path": "" }
}
```

`executable_path` 留空自动查找，或填写可执行文件绝对路径。需要 CLI 和登录。当前沿用 CLI 默认模型，隔离用户配置中的自定义模型/provider、插件和工具，输入不附带当前聊天历史。具体额度/费用取决于本机 CLI 认证方式；在 Claude 桌面使用 CLI 后端也不会改用 Claude 额度。

### 可选：OpenAI 兼容 API

```json
{
  "backend": "openai_compatible",
  "timeout_seconds": 120,
  "api": {
    "base_url": "https://api.example.com/v1",
    "model": "服务方提供的模型ID",
    "api_key": "在你电脑上填写自己的Key"
  }
}
```

- 请求 `POST {base_url}/chat/completions`，非流式 `messages`，Bearer 认证。不要在 base_url 里重复填 `/chat/completions`。
- 服务需支持 system/user 消息、`choices[0].message.content` 字符串与 `finish_reason: "stop"`；拒绝/截断/无效输出不回填。不支持 Responses API 或 Claude 原生 Messages 协议。
- 远程要求 HTTPS。HTTP 仅用于 localhost、127.0.0.1、IPv6 回环，本地服务 Key 可为空。拒绝 URL 中的用户名/密码/查询参数/片段，禁止 HTTP 重定向。
- `timeout_seconds` 可填 5–300，默认 120。失败不自动重试，也不切换后端。
- API 由所配置的服务方计费。没有真实服务凭据时不要把示例当作可用配置。

协议参考 [OpenAI 官方 Chat Completions 文档](https://developers.openai.com/api/reference/resources/chat)；第三方实现是否兼容仍需测试。

## 从源码构建

需要 macOS 13+、Xcode Command Line Tools（含 Swift 5.9+）、Python 3。命令在仓库根目录执行：

```bash
swift run OptimizerChecks
swift build --product PromptOptimizer
# 只在第一次本地构建时建立你自己的持久签名身份
python3 scripts/setup-local-signing.py
bash scripts/build-app.sh
bash scripts/build-dmg.sh
```

产物：`dist/Codex提示词助手.zip`、`dist/PromptOptimizer.dmg`、SHA-256 文件。构建不会退出或升级正在使用的助手。

本地签名身份仅写到你自己的 Application Support 专用钥匙串，不改变系统根信任/钥匙串搜索列表，不授予辅助功能权限。切勿提交签名材料。公证发布需要你自己的 Developer ID；见[发布说明](docs/RELEASING.md)。

也可保存原文并退出助手后运行 `bash scripts/install-app.sh`，安装到 `~/Applications`；安装器先备份旧版，拒绝覆盖运行实例。

## 验证和限制

当前 43 项检查覆盖：快照事务、用户改稿/换目标保护、取消/超时、CLI 子进程、配置权限/重新加载、API 响应解析、本机真实 HTTP、重定向拒绝，以及系统/用户安装路径。

曾在本机真实 Claude 桌面观察到回填，用户也反馈 Codex/Claude 能优化；旧版专用恢复因选区兼容问题已移除。最新原生撤销、完整动画、其他机器和真实 API 服务尚未全面验收。

辅助功能无法保证区分所有多行代码区与聊天草稿；请只点中真正的草稿框。附件、引用、@提及、相同节点/相同文字下的聊天切换等有兼容边界。请先用无敏感信息的可丢弃文字测试。

## 文档与参与

- [实现结构](docs/ARCHITECTURE.md)
- [权限、数据与隐私](docs/PRIVACY.md)
- [构建、DMG、签名与发布](docs/RELEASING.md)
- [贡献方式](CONTRIBUTING.md) / [安全反馈](SECURITY.md)
- [macOS CI 模板](ci/macos.yml.example)：当前未启用，需具有 workflow 权限的维护者配置
- [MIT License](LICENSE)

MIT 许可覆盖本仓库原创代码。WorkBuddy、Codex、Claude 名称仅用于说明灵感和兼容目标；各自商标属于其权利人。
