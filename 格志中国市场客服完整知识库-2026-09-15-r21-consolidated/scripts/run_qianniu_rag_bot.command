#!/bin/zsh
set -e

PROJECT_DIR="/Users/dnying/Documents/Codex/2026-05-15/https-rulechannel-tmall-com-spm-a2177"
PYTHON="/usr/bin/python3"
LOG_DIR="$PROJECT_DIR/outputs/qianniu_bot"
LOG_FILE="$LOG_DIR/run.log"

mkdir -p "$LOG_DIR"

if [ -x "$PROJECT_DIR/.venv-ocr/bin/python" ]; then
  PYTHON="$PROJECT_DIR/.venv-ocr/bin/python"
elif [ -x "/Users/dnying/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3" ]; then
  PYTHON="/Users/dnying/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
fi

cd "$PROJECT_DIR"
export PYTHONUNBUFFERED=1
echo "千牛客服RAG助手启动中..."
echo "模式：自动发送已开启；低置信问题仍会暂缓，避免乱答"
echo "窗口：只锁定附屏的“接待中心”；不会操作千牛主工作台"
echo "停止：退出 QianNiuRAGBot，或执行 pkill -f qianniu_fixed_window_bot.py"
echo "日志：$LOG_FILE"
echo

"$PYTHON" scripts/qianniu_fixed_window_bot.py --interval 4 --auto-send --send-all-risk-levels --watch-list --window-relative --no-pin-reception-window --allow-configured-window-fallback --no-activate-before-scan 2>&1 | tee -a "$LOG_FILE"
