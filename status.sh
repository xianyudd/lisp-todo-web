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

# 情况一：没有 pid 文件 = 当前肯定没在跑
if [[ ! -f "$PID_FILE" ]]; then
  echo "Lisp Todo Web server: NOT RUNNING 🤣"

  latest_log="$(latest_log_file)"
  if [[ -n "$latest_log" ]]; then
    # 你要的效果：NOT RUNNING + 最近一次日志文件路径
    echo "  Last log: $latest_log"
  else
    echo "  Last log: (none)"
  fi

  # 按 LSB 约定：3 = not running
  exit 3
fi

# 情况二：有 pid 文件，看看进程还在不在
PID="$(cat "$PID_FILE")"

if kill -0 "$PID" 2>/dev/null; then
  echo "Lisp Todo Web server: RUNNING 🎉"
  echo "  PID: $PID"
  echo "  URL: http://localhost:5000/"

  latest_log="$(latest_log_file)"
  if [[ -n "$latest_log" ]]; then
    echo "  Current log: $latest_log"
  else
    echo "  Current log: (none)"
  fi
  echo

  if command -v ps >/dev/null 2>&1; then
    echo "Process info:"
    ps -p "$PID" -o pid,ppid,cmd --no-headers || true
  fi

  exit 0
else
  # 情况三：有 pid 文件但是进程已经不在了 = 脏 pid
  echo "Lisp Todo Web server: NOT RUNNING (stale pid file: $PID)"

  latest_log="$(latest_log_file)"
  if [[ -n "$latest_log" ]]; then
    echo "  Last log: $latest_log"
  else
    echo "  Last log: (none)"
  fi

  # 顺手清理掉无效 pid
  rm -f "$PID_FILE" 2>/dev/null || true
  exit 3
fi
