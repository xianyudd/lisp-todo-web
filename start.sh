#!/usr/bin/env bash
set -e

# 项目根目录（脚本所在目录）
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PID_FILE="$ROOT_DIR/todo-web.pid"

# 日志目录 & 当前运行日志文件
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="$LOG_DIR/todo-web-$TS.log"

# 颜色
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 一个小 spinner，用来显示“程序还活着”
spinner_check() {
  local pid="$1"
  local frames='-\|/'
  local i=0
  local max_ticks=30    # 30 * 0.1s = 3 秒

  while kill -0 "$pid" 2>/dev/null && [ "$max_ticks" -gt 0 ]; do
    local frame="${frames:i%${#frames}:1}"
    printf "\r[%s] Lisp Todo Web server is running..." "$frame"
    i=$((i + 1))
    max_ticks=$((max_ticks - 1))
    sleep 0.1
  done

  # 清掉这一行，交给后面的 [OK]/[FAIL] 输出
  printf "\r"
}

# 如果已经在运行，就不要重复启动
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo -e "${YELLOW}[INFO]${RESET} Lisp Todo Web server 已在运行，PID: $(cat "$PID_FILE")"
  latest_log="$(ls -1t "$LOG_DIR"/todo-web-*.log 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_log" ]]; then
    echo "  最新日志: $latest_log"
  else
    echo "  暂无日志文件（logs/ 目录为空）"
  fi
  exit 0
fi

# 启动前先写一行标记到本次日志
echo "=== START $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$RUN_LOG"

# 第一行：简单提示一下
echo "[..] Starting Lisp Todo Web server..."
echo "  日志文件: $RUN_LOG"

# 后台启动 SBCL，日志全部写入本次 RUN_LOG
nohup sbcl --noinform --disable-debugger \
  --load "$ROOT_DIR/todo-web.lisp" \
  --eval "(in-package :todo-web)" \
  --eval "(start-server 5000)" \
  --eval "(loop (sleep 3600))" \
  >> "$RUN_LOG" 2>&1 &

PID=$!
echo "$PID" > "$PID_FILE"

# 短暂动画：3 秒内持续检查“进程还活着”
spinner_check "$PID"

# 动画结束之后，再最终判断一次
if kill -0 "$PID" 2>/dev/null; then
  echo -e "${GREEN}[OK]${RESET} Lisp Todo Web server started."
  echo "  PID: $PID"
  echo "  Log: $RUN_LOG"
else
  echo -e "${RED}[FAIL]${RESET} Lisp Todo Web server exited during startup."
  echo "  请查看日志: $RUN_LOG"
  # 清理掉无效的 pid 文件
  rm -f "$PID_FILE" || true
  exit 1
fi
