#!/bin/zsh
# Сборка приложения «Расчёт фундамента» (.app) из исходников
set -e
cd "$(dirname "$0")"
swift build -c release
APP="Расчёт фундамента.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FundamentCalc "$APP/Contents/MacOS/FundamentCalc"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>FundamentCalc</string>
  <key>CFBundleIdentifier</key><string>local.fundamentcalc</string>
  <key>CFBundleName</key><string>Расчёт фундамента</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Готово: $(pwd)/$APP"
