#!/bin/zsh
set -euo pipefail

MAX_CUSTOMERS="${1:-100}"
SCROLL_AMOUNT="${2:--420}"
DELAY_SECONDS="${3:-0.8}"
QIANNIU_PID="${4:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="/private/tmp/qianniu_front100_learning"
BUYERS_FILE="$RAW_DIR/buyers.tsv"
SEEN_FILE="$RAW_DIR/seen.txt"
OUT_FILE="$ROOT/outputs/qianniu_chat_learning/$(date +%F)_front100_sanitized_ocr.md"
APPEND_MODE="${QIANNIU_LEARN_APPEND:-0}"
KEEP_RAW="${QIANNIU_KEEP_RAW:-0}"
DISPLAY_ID="${QIANNIU_CAPTURE_DISPLAY:-2}"
# Calibrated against the current secondary-display full screenshot. The crop
# captures the QianNiu reception chat history while avoiding the reply box.
CROP_HEIGHT="${QIANNIU_CHAT_CROP_HEIGHT:-620}"
CROP_WIDTH="${QIANNIU_CHAT_CROP_WIDTH:-620}"
CROP_Y="${QIANNIU_CHAT_CROP_Y:-90}"
CROP_X="${QIANNIU_CHAT_CROP_X:-1980}"

mkdir -p "$RAW_DIR" "$ROOT/outputs/qianniu_chat_learning"
cd "$ROOT"
if [[ "$APPEND_MODE" != "1" ]]; then
  : > "$BUYERS_FILE"
  : > "$SEEN_FILE"
  rm -f "$RAW_DIR"/chat_*.png(N) "$RAW_DIR"/chat_*.json(N)
fi

count="$(wc -l < "$BUYERS_FILE" 2>/dev/null | tr -d ' ')"
[[ -z "$count" ]] && count=0
stale=0

while [[ "$count" -lt "$MAX_CUSTOMERS" && "$stale" -lt 4 ]]; do
  new_this_page=0

  while [[ "$count" -lt "$MAX_CUSTOMERS" ]]; do
    if [[ -n "$QIANNIU_PID" ]]; then
      rows="$(./bin/qianniu_ax --pid "$QIANNIU_PID" dump-buyers)"
    else
      rows="$(./bin/qianniu_ax dump-buyers)"
    fi

    title=""
    while IFS=$'\t' read -r _index _x _y _width _height candidate; do
      [[ -z "${candidate:-}" ]] && continue
      if grep -Fxq -- "$candidate" "$SEEN_FILE"; then
        continue
      fi
      title="$candidate"
      break
    done <<< "$rows"

    [[ -z "$title" ]] && break

    count=$((count + 1))
    new_this_page=$((new_this_page + 1))
    printf '%s\n' "$title" >> "$SEEN_FILE"
    printf '%03d\t%s\n' "$count" "$title" >> "$BUYERS_FILE"

    if [[ -n "$QIANNIU_PID" ]]; then
      ./bin/qianniu_ax --pid "$QIANNIU_PID" click-buyer "$title" >/dev/null
    else
      ./bin/qianniu_ax click-buyer "$title" >/dev/null
    fi
    sleep "$DELAY_SECONDS"

    image="$RAW_DIR/chat_$(printf '%03d' "$count").png"
    full_image="$RAW_DIR/full_$(printf '%03d' "$count").png"
    json="$RAW_DIR/chat_$(printf '%03d' "$count").json"
    screencapture -x -D "$DISPLAY_ID" "$full_image"
    sips -c "$CROP_HEIGHT" "$CROP_WIDTH" --cropOffset "$CROP_Y" "$CROP_X" "$full_image" --out "$image" >/dev/null
    .venv-ocr/bin/python scripts/ocr_rapid.py "$image" --json --min-confidence 0.35 > "$json"
    rm -f "$image" "$full_image"
    printf '{"sample":%d,"buyer_count":%d}\n' "$count" "$count"

    if [[ "$count" -ge "$MAX_CUSTOMERS" ]]; then
      break
    fi
  done

  if [[ "$new_this_page" -eq 0 ]]; then
    stale=$((stale + 1))
  else
    stale=0
  fi

  if [[ "$count" -lt "$MAX_CUSTOMERS" ]]; then
    if [[ -n "$QIANNIU_PID" ]]; then
      ./bin/qianniu_ax --pid "$QIANNIU_PID" scroll-buyers "$SCROLL_AMOUNT" >/dev/null
    else
      ./bin/qianniu_ax scroll-buyers "$SCROLL_AMOUNT" >/dev/null
    fi
    sleep 0.4
  fi
done

.venv-ocr/bin/python scripts/learn_qianniu_front100.py \
  --sanitize-collected-dir "$RAW_DIR" \
  --buyers-file "$BUYERS_FILE" \
  --out "$OUT_FILE"

if [[ "$KEEP_RAW" != "1" ]]; then
  rm -f "$BUYERS_FILE" "$SEEN_FILE" "$RAW_DIR"/chat_*.json(N)
fi
