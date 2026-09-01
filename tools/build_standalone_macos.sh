#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

if [[ ! -x dist/jd_paddle_ocr/jd_paddle_ocr ]]; then
  tools/build_paddle_runtime.sh
fi

flutter build macos --release
app_resources="build/macos/Build/Products/Release/JD Automation.app/Contents/Resources"
mkdir -p "$app_resources/PaddleOCR"
ditto dist/jd_paddle_ocr "$app_resources/PaddleOCR"
codesign --force --deep --sign - "build/macos/Build/Products/Release/JD Automation.app"
