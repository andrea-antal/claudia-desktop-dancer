#!/bin/zsh
# ./build.sh        build Claudia.app (Apple Silicon)
# ./build.sh test   run the behaviour checks
set -e
cd "${0:A:h}"
mkdir -p .cache
if [[ $1 == test ]]; then
  swiftc Sources/Brain.swift Tests/main.swift -o .cache/test && .cache/test
  exit
fi
[[ -d Sprites ]] || ./tools/extract.sh
app=Claudia.app
rm -rf $app && mkdir -p $app/Contents/{MacOS,Resources}
swiftc -O -target arm64-apple-macos14 Sources/*.swift -o $app/Contents/MacOS/Claudia
cp -R Sprites $app/Contents/Resources/
cat > $app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claudia</string>
  <key>CFBundleIdentifier</key><string>io.github.andrea-antal.claudia-desktop-dancer</string>
  <key>CFBundleExecutable</key><string>Claudia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - $app   # ad-hoc signature so Apple Silicon will launch it
echo "built $PWD/$app"
