#!/bin/zsh
# Builds build/Guitar Quest.app (release, ad-hoc signed: runs on this Mac and any Mac you copy it to with a right-click → Open).
# Usage: scripts/build_app.sh            → build only
#        scripts/build_app.sh --install  → move it to /Applications (one copy only)
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh -c release --product GuitarQuest
scripts/build.sh -c release --product IconMaker
BIN="$(swift build -c release --show-bin-path)"

APP="build/Guitar Quest.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GuitarQuest" "$APP/Contents/MacOS/GuitarQuest"

"$BIN/IconMaker" build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Guitar Quest</string>
  <key>CFBundleDisplayName</key><string>Guitar Quest</string>
  <key>CFBundleIdentifier</key><string>local.guitarquest</string>
  <key>CFBundleExecutable</key><string>GuitarQuest</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Family project — offline, no data leaves this Mac.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Guitar Quest.app"
  mv "$APP" /Applications/   # move, not copy: keeps a single copy on the Mac
  echo "Installed: /Applications/Guitar Quest.app"
fi
