#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

.paddleocr-venv/bin/pyinstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name jd_paddle_ocr \
  --collect-all paddle \
  --collect-all paddleocr \
  --collect-all paddlex \
  --copy-metadata paddlepaddle \
  --copy-metadata paddleocr \
  --copy-metadata paddlex \
  --copy-metadata opencv-contrib-python \
  --copy-metadata imagesize \
  --copy-metadata pyclipper \
  --copy-metadata pypdfium2 \
  --copy-metadata python-bidi \
  --copy-metadata shapely \
  --add-data ".paddlex-cache/official_models/PP-OCRv5_mobile_det:official_models/PP-OCRv5_mobile_det" \
  --add-data ".paddlex-cache/official_models/PP-OCRv5_mobile_rec:official_models/PP-OCRv5_mobile_rec" \
  tools/paddle_ocr_bridge.py
