#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO_ENV="$PROJECT_ROOT/.venv-video"
BUNDLED_PYTHON="/Users/dnying/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"

if [[ -n "${PYTHON_BIN:-}" ]]; then
  VIDEO_PYTHON="$PYTHON_BIN"
elif [[ -x "$BUNDLED_PYTHON" ]]; then
  VIDEO_PYTHON="$BUNDLED_PYTHON"
else
  VIDEO_PYTHON="python3"
fi

if [[ ! -x "$VIDEO_ENV/bin/python" ]]; then
  "$VIDEO_PYTHON" -m venv "$VIDEO_ENV"
fi

"$VIDEO_ENV/bin/python" -m pip install --upgrade pip
"$VIDEO_ENV/bin/python" -m pip install -r "$PROJECT_ROOT/requirements-video.txt"
"$VIDEO_ENV/bin/python" - <<'PY'
import av
import imageio_ffmpeg
import PIL

print("pyav", av.__version__)
print("ffmpeg", imageio_ffmpeg.get_ffmpeg_exe())
print("pillow", PIL.__version__)
PY
