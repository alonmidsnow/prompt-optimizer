#!/bin/bash
# Filesystem-only packaging. No Finder automation and no privacy-setting changes.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_zip="$project_root/dist/Codex提示词助手.zip"
[ -f "$source_zip" ] || { printf '%s\n' '先运行 bash scripts/build-app.sh' >&2; exit 1; }
staging="$(mktemp -d "$project_root/dist/.dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/image" "$project_root/dist/backups"
ditto -x -k "$source_zip" "$staging/image"
codesign --verify --strict "$staging/image/Codex提示词助手.app"
ln -s /Applications "$staging/image/Applications"
cat > "$staging/image/安装说明.txt" <<'TEXT'
Prompt Optimizer / 提示词助手 · 实验测试版

1. 把“Codex提示词助手”拖入 Applications，再从应用程序启动，勿在 DMG 内直接运行。
2. 按提示授予本助手辅助功能权限。
3. 默认使用本机已登录的 Codex CLI；也可编辑本机 config.json 选择自己的模型 API。
4. 点中 Codex 桌面或 Claude 桌面 Code 模式的纯文本草稿，再点圆球“优化提示词”。
5. 不自动发送；退出清空内存原文。模型调用使用你自己的额度或服务计费。

本包尚未经过 Apple 公证，其他 Mac 的首次安装与兼容性仍待测试。
只有确认下载来源并理解权限后才运行；不要关闭 Gatekeeper 或移除安全保护。
源码与完整说明：https://github.com/alonmidsnow/prompt-optimizer
TEXT
hdiutil create -volname 'Prompt Optimizer' -srcfolder "$staging/image" -format UDZO -ov "$staging/PromptOptimizer.dmg"
hdiutil verify "$staging/PromptOptimizer.dmg"
output="$project_root/dist/PromptOptimizer.dmg"
if [ -e "$output" ]; then cp "$output" "$project_root/dist/backups/dmg-$(date +%Y%m%d-%H%M%S)-$$.dmg"; fi
mv "$staging/PromptOptimizer.dmg" "$output"
(cd "$project_root/dist" && shasum -a 256 PromptOptimizer.dmg > PromptOptimizer.dmg.sha256)
printf 'Built: %s\n' "$output"
printf '%s\n' '此步骤只打包；DMG 本身未签名/公证，不能据此承诺下载即用。'
