#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/todo-web.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "未找到 PID 文件 ($PID_FILE)，服务可能没有在运行。"
  exit 0
fi

PID="$(cat "$PID_FILE")"

if kill -0 "$PID" 2>/dev/null; then
  echo "Stopping Lisp Todo Web server (PID: $PID) ..."
  kill "$PID"
  # 给一点时间优雅退出
  sleep 1
else
  echo "PID 文件存在，但进程 $PID 不在运行。"
fi

rm -f "$PID_FILE"
echo "已停止（或已清理 PID 文件）。"
