# 实现结构

Swift Package，无第三方运行依赖。CLI 生成模型请求与目标输入框彼此独立：即使在 Claude 桌面，也能选择 Codex CLI 后端。

```mermaid
flowchart LR
    A[显式点击优化] --> B[聚焦编辑器与草稿快照]
    B --> C{读取本机配置}
    C --> D[隔离 Codex CLI]
    C --> E[OpenAI 兼容 API]
    D --> F[复核同一目标与原文]
    E --> F
    F --> G[核验全文选区]
    G --> H[原生粘贴与回读核验]
    H --> I[显示完成 / 保留内存原文]
```

- `Sources/OptimizerCore/Session.swift`：快照、过期结果、冲突和已应用记录。内部 restore proposal 用于比对原生撤销结果，不代表产品中保留了恢复按钮。
- `EditorCompatibility.swift` / `EditorSelection.swift` / `EditorText.swift`：应用白名单、节点重建连续性、全文选区与段落渲染确认。写入前的用户编辑保护保持精确比较。
- `CodexRunner.swift`：只读临时会话，stdin 输入、禁主要工具、超时/取消、私有临时目录及清理。
- `ConfiguredOptimizer.swift`：配置读取、后端选择、HTTP 与错误处理。无自动后端切换。
- `OptimizationPrompt.swift`：原创共享优化指令，将草稿视为数据，不执行草稿任务。
- `InstallationPaths.swift`：只接受系统/本用户 Applications 安装位置，拒绝 DMG 和下载副本。
- `Sources/PromptOptimizer/EditorAccess.swift`：辅助功能目标识别、焦点保护、选区/剪贴板/回填核验、受保护的原生撤销事件。
- `App.swift` / `OrbWidget.swift` / `UndoShortcut.swift`：三项菜单、状态提示、快捷键兼容和内存原文查看。
- `Tests/OptimizerCoreTests/`：自定义 `OptimizerChecks` 可执行检查；不是 XCTest，执行 `swift run OptimizerChecks`。

应用不会通过官方插件接口读写草稿；它依赖 macOS 辅助功能。终端/网页输入区当前不在适配范围。无法可靠区分所有编辑区，适配应用更新后需要真实窗口重新验收。
