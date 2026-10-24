#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_ROOT="$REPO_ROOT/.cache/rk3566-logo-build"
LOG_FILE="$WORK_ROOT/build.log"
PID_FILE="$WORK_ROOT/build.pid"
IMAGE_PATH="$REPO_ROOT/distro/Image"
MODE="status"
TAIL_LINES=80

usage() {
  cat <<'EOF'
Usage:
  scripts/host/monitor-rk3566-logo-build.sh [options]

Options:
  --watch                 Follow log in real time (tail -f)
  --status                Show one-shot status (default)
  --lines <n>             Tail line count for --watch (default: 80)
  --work-root <path>      Override build cache directory
  --image <path>          Override output Image path
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      MODE="watch"
      shift
      ;;
    --status)
      MODE="status"
      shift
      ;;
    --lines)
      TAIL_LINES="${2:-}"
      shift 2
      ;;
    --work-root)
      WORK_ROOT="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! "$TAIL_LINES" =~ ^[0-9]+$ ]] || [[ "$TAIL_LINES" -lt 1 ]]; then
  echo "Error: --lines must be a positive integer." >&2
  exit 1
fi

LOG_FILE="$WORK_ROOT/build.log"
PID_FILE="$WORK_ROOT/build.pid"

print_status() {
  echo "Work root : $WORK_ROOT"
  echo "Log file  : $LOG_FILE"
  echo "PID file  : $PID_FILE"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      etime="$(ps -p "$pid" -o etime= | xargs || true)"
      echo "Build     : RUNNING (pid $pid, elapsed ${etime:-unknown})"
    else
      echo "Build     : NOT RUNNING (stale pid file)"
    fi
  else
    echo "Build     : NOT RUNNING"
  fi

  if [[ -f "$IMAGE_PATH" ]]; then
    size="$(stat -c '%s' "$IMAGE_PATH")"
    mtime="$(stat -c '%y' "$IMAGE_PATH")"
    echo "Image     : $IMAGE_PATH"
    echo "ImageSize : $size bytes"
    echo "ImageMTime: $mtime"
    sha256sum "$IMAGE_PATH" | sed 's/^/ImageSHA : /'
  else
    echo "Image     : not generated yet ($IMAGE_PATH)"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    echo "LogMTime  : $(stat -c '%y' "$LOG_FILE")"
  else
    echo "Log       : not created yet"
  fi
}

print_status

if [[ "$MODE" == "watch" ]]; then
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "Waiting for log file to appear..."
    while [[ ! -f "$LOG_FILE" ]]; do
      sleep 1
    done
  fi
  echo "\n--- tail -n $TAIL_LINES -f $LOG_FILE ---"
  tail -n "$TAIL_LINES" -f "$LOG_FILE"
fi
