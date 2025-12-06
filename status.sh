#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/todo-web.pid"
LOG_DIR="$ROOT_DIR/logs"

# 小工具：找到最新的日志文件
latest_log_file() {
  if ls -1 "$LOG_DIR"/todo-web-*.log >/dev/null 2>&1; then
    ls -1t "$LOG_DIR"/todo-web-*.log 2>/dev/null | head -n1
  else
    echo ""
  fi
}

if [[ ! -f "$PID_FILE" ]]; then
  echo "Lisp Todo Web server: NOT RUNNING (no pid file)"
  latest_log="$(latest_log_file)"
  if [[ -n "$latest_log" ]]; then
    echo
    echo "最近 20 行日志（最近一次运行）:"
    tail -n 20 "$latest_log"
  fi
  # 按 LSB 约定：3 = not running
  exit 3
fi

PID="$(cat "$PID_FILE")"

if kill -0 "$PID" 2>/dev/null; then
  echo "Lisp Todo Web server: RUNNING"
  echo "  PID: $PID"

  latest_log="$(latest_log_file)"
  if [[ -n "$latest_log" ]]; then
    echo "  当前最新日志文件: $latest_log"
  else
    echo "  当前还没有日志文件（logs/ 目录为空）"
  fi
  echo

  if command -v ps >/dev/null 2>&1; then
    echo "进程信息:"
    ps -p "$PID" -o pid,ppid,cmd --no-headers || true
    echo
  fi

  if [[ -n "$latest_log" ]]; then
    echo "最近 20 行日志:"
    tail -n 20 "$latest_log"
  fi

  exit 0
else
  echo "Lisp Todo Web server: NOT RUNNING (stale pid file: $PID)"
  exit 3
fi
