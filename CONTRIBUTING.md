# 参与开发

欢迎复现问题、改善输入框兼容性和文档。提交前运行：

```bash
swift run OptimizerChecks
swift build --product PromptOptimizer
bash -n scripts/build-app.sh scripts/build-dmg.sh scripts/install-app.sh
```

- 从现有代码和检查开始；行为修改添加能复现问题的检查，再做最小修复。
- 不增加盲目全选、全应用扫描、绕过权限、自动发送或隐式模型后端切换。
- 回填前精确保护目标与用户新稿，回填后确认实际结果；不能用测试桩通过证明真实应用可用。
- 不提交 config.json、Key、签名材料、私人草稿、ASAR 提取物、用户验证日志或本机二进制。
- 功能声明区分自动检查、真实目标测试和待验收；新增平台/编辑器必须写清范围。
- 对 macOS 新安装、辅助功能、更新身份和原生撤销有影响的修改应附人工测试说明，不能要求用户关闭系统安全功能。

本项目使用 MIT 许可。提交的贡献应为你有权许可的代码；不要搬运专有软件代码、提示词、图标或其他受限资产。
