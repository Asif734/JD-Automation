#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

flutter build macos --release
codesign --force --deep --sign - "build/macos/Build/Products/Release/JD Automation.app"
