# Lisp Web Todo

一个用 **Common Lisp + Hunchentoot** 写的极简 Todo Web 应用，支持：

* 添加 / 完成 / 删除 Todo
* 数据持久化（`todos.json`）
* RESTful API（`/api/todos`）
* 基于 SSE 的多浏览器实时同步
* 一键启动 / 停止 / 查看状态脚本（`start.sh` / `stop.sh` / `status.sh`）

## 快速开始

```bash
# 启动服务（后台）
./start.sh

# 查看状态
./status.sh

# 停止服务
./stop.sh
```

打开浏览器访问：

```text
http://localhost:5000/
```

## 项目结构

```text
.
├── public/          # 前端页面（HTML/CSS/JS）
├── todo-web.lisp    # 后端：Lisp 服务器 + REST + SSE + 持久化
├── start.sh         # 启动服务器（后台 + 日志）
├── stop.sh          # 停止服务器
├── status.sh        # 查看运行状态 + 日志信息
├── logs/            # 运行日志（已在 .gitignore 中忽略）
└── todos.json       # 本地任务数据（可选择是否忽略）
```

## 常用命令

```bash
./start.sh   # 后台启动服务
./status.sh  # 查看当前运行状态
./stop.sh    # 停止服务
./logs.sh    # (可选) 实时查看最新日志
```

## License

MIT
