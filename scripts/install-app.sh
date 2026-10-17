#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_zip="$project_root/dist/Codex提示词助手.zip"
target_app="$HOME/Applications/Codex提示词助手.app"
if pgrep -f '/Codex提示词助手[.]app/Contents/MacOS/PromptOptimizer' >/dev/null; then
  printf '%s\n' '请先从旧版“查看原文”保存需要的文字，再从助手菜单退出。安装器不会强制退出或清空原文。' >&2
  exit 1
fi
unzip -tq "$source_zip"
mkdir -p "$HOME/Applications" "$project_root/dist/backups"
stage="$(mktemp -d "$HOME/Applications/.optimizer-install.XXXXXX")"
trap 'rmdir "$stage" 2>/dev/null || true' EXIT
ditto -x -k "$source_zip" "$stage"
codesign --verify --strict "$stage/Codex提示词助手.app"
next_requirement="$(codesign -d -r- "$stage/Codex提示词助手.app" 2>/dev/null)"
previous_requirement=""
if [ -e "$target_app" ]; then
  previous_requirement="$(codesign -d -r- "$target_app" 2>/dev/null || true)"
fi
if [ -e "$target_app" ]; then
  archive="$project_root/dist/backups/installed-$(date +%Y%m%d-%H%M%S)-$$.zip"
  ditto -c -k --keepParent "$target_app" "$archive"
  unzip -tq "$archive"
  mv "$target_app" "$stage/previous.app"
fi
if ! mv "$stage/Codex提示词助手.app" "$target_app"; then
  if [ -e "$stage/previous.app" ]; then mv "$stage/previous.app" "$target_app"; fi
  exit 1
fi
if [ -e "$stage/previous.app" ]; then
  # The previous installed bundle is preserved in the verified ZIP above.
  rm -rf "$stage/previous.app"
fi
# Remove only the known legacy generated app after a verified recoverable archive.
legacy="$project_root/dist/Codex提示词助手.app"
if [ -e "$legacy" ]; then
  archive="$project_root/dist/backups/legacy-dist-$(date +%Y%m%d-%H%M%S)-$$.zip"
  ditto -c -k --keepParent "$legacy" "$archive"
  unzip -tq "$archive"
  rm -rf "$legacy"
fi
printf 'Installed: %s\n'  "$target_app"
if [ -n "$previous_requirement" ] && [ "$previous_requirement" = "$next_requirement" ]; then
  printf '%s\n' '固定签名身份与上一版一致；启动后仍以系统实际权限检查结果为准。'
else
  printf '%s\n' '本次签名身份发生迁移；如系统未识别授权，请仅重新添加 Applications 内本助手。'
fi
