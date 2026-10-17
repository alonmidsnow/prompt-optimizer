#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
swift build -c release --product PromptOptimizer
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
staging="$(mktemp -d "$project_root/dist/.package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_bundle="$staging/Codex提示词助手.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE.txt"
cp "$binary_dir/PromptOptimizer" "$app_bundle/Contents/MacOS/PromptOptimizer"
# Release artifacts must not disclose absolute source paths from debug sections.
/usr/bin/strip -S "$app_bundle/Contents/MacOS/PromptOptimizer"
cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PromptOptimizer</string>
<key>CFBundleIdentifier</key><string>cn.sangengxue.codex-prompt-optimizer</string>
<key>CFBundleName</key><string>Codex提示词助手</string>
<key>CFBundleDisplayName</key><string>Codex 提示词助手</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>14</string>
<key>OptimizerRelease</key><string>0.6.0-beta.1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swift "$project_root/scripts/make-icon.swift" "$staging/AppIcon.iconset"
iconutil -c icns "$staging/AppIcon.iconset" -o "$app_bundle/Contents/Resources/AppIcon.icns"
plutil -lint "$app_bundle/Contents/Info.plist"
python3 "$project_root/scripts/sign-app.py" "$app_bundle"
mkdir -p "$project_root/dist/backups"
release_zip="$project_root/dist/Codex提示词助手.zip"
if [ -e "$release_zip" ]; then
  cp "$release_zip" "$project_root/dist/backups/release-$(date +%Y%m%d-%H%M%S)-$$.zip"
fi
ditto -c -k --keepParent "$app_bundle" "$staging/release.zip"
unzip -tq "$staging/release.zip"
mv "$staging/release.zip" "$release_zip"
# Generated staging only. The public output is an archive, never a competing runnable app.
rm -rf "$staging"
printf 'Built archive: %s\n' "$release_zip"
