# Lisp Todo Web

一个用 **Common Lisp** 写的小型 Todo Web 应用，包含：

* Hunchentoot 写的 HTTP 服务
* RESTful API（`/api/todos`）+ Server-Sent Events（`/api/todos/events`）
* 纯 HTML + 原生 JS 前端，小动画 + 实时刷新
* JSON 文件持久化（支持配置和 Docker 卷挂载）
* 多阶段 Docker 构建，生成较小的运行时镜像
* 已部署在 Render，提供在线 Demo

---

## 在线 Demo

本项目已部署在 Render 免费实例上，可以直接在线体验：

👉 [https://lisp-todo-web.onrender.com](https://lisp-todo-web.onrender.com)

> 提示：Render 免费实例长时间无人访问会“休眠”，第一次打开可能会稍微慢一点，需要等它唤醒。

---

## 功能特性

* ✍️ **增删 Todo**

  * 输入框 + 按钮/回车 创建任务
  * 每一条都可以删除（带缩小 + 淡出动画）

* ✔ **完成状态切换**

  * 勾选复选框切换完成/未完成
  * 完成项灰色+删除线，未完成正常显示

* 🔄 **多标签页实时同步（SSE）**

  * 前端通过 `EventSource` 订阅 `/api/todos/events`
  * 任意一个浏览器窗口增删改 Todo，其他窗口会自动更新

* 📊 **统计信息**

  * 底部展示：`共 N 条任务，未完成 M 条`

* 💾 **文件持久化**

  * Todo 会写入一个 JSON 文件，服务重启后可恢复
  * 路径、大小限制等通过 `config.json` 控制

* ⚙️ **可配置限制**

  * **最大 Todo 条数**：`max-todo-count`
  * **单条文本最大长度**：`max-text-length`
  * **数据文件最大体积**：`max-data-bytes`

---

## 技术栈

**后端**

* Common Lisp（SBCL）
* [Hunchentoot](https://edicl.github.io/hunchentoot/)

  * 路由 + HTTP 服务器
  * 提供 RESTful API & SSE 端点
* `cl-json` —— JSON 编解码
* `flexi-streams` —— 把底层二进制流包装成 UTF-8 字符流，用于 SSE

**前端**

* 单个 `public/index.html`
* 原生 JavaScript：

  * `fetch` 调用 `GET/POST/PATCH/DELETE /api/todos`
  * `EventSource` 订阅 `/api/todos/events`
* CSS 小动画：

  * 卡片淡入、悬浮阴影
  * 删除时缩小 + 淡出

**部署 / 运维**

* 多阶段 Docker 构建：

  * build 阶段：安装 SBCL + Quicklisp，加载 `todo-web.lisp` 并用 `save-lisp-and-die` 打包成单一可执行文件
  * runtime 阶段：基于精简 Debian，只携带可执行文件和静态资源
* 提供本地管理脚本：`start.sh` / `stop.sh` / `status.sh`

---

## 项目结构

```text
.
├── Dockerfile          # 多阶段构建镜像
├── LICENSE             # MIT 许可证
├── README.md           # 项目说明（本文件）
├── config.json         # 运行配置：端口、数据文件、限制等
├── doc/
│   └── docker.md       # Docker 相关说明
├── logs/               # 本地 start.sh 运行时的日志（可 .gitignore）
├── public/
│   └── index.html      # 前端页面（Todo UI + SSE 客户端）
├── start.sh            # 本地启动脚本（非 Docker）
├── stop.sh             # 本地停止脚本
├── status.sh           # 查看本地进程状态
├── todo-web.lisp       # Lisp 后端源码
└── todos.json          # 本地示例数据（实际运行可使用 data/todos.json）
```

> 实际运行时，数据文件路径由 `config.json` 控制，推荐使用 `data/todos.json` 并通过 Docker 卷挂载到宿主机目录。

---

## 配置说明（config.json）

示例：

```json
{
  "listen-port": 5000,
  "data-file": "data/todos.json",
  "max-data-bytes": 1048576,
  "max-todo-count": 500,
  "max-text-length": 200
}
```

字段含义：

* `listen-port`：默认监听端口（会被环境变量 `PORT` 覆盖）
* `data-file`：数据文件路径

  * 支持相对路径（相对项目根目录，如 `data/todos.json`）
* `max-data-bytes`：数据文件允许的最大体积（字节）
* `max-todo-count`：最多允许保存多少条 Todo
* `max-text-length`：单条 Todo 文本最大长度

应用启动流程：

1. 读取 `config.json`，初始化 `*config*` / `*data-file*`
2. 如果 `data-file` 存在，从中加载历史 Todo
3. 根据以下顺序确定端口：

   1. 函数参数 `port`（如果调用者手动传入）
   2. 环境变量 `PORT`
   3. 配置文件中的 `listen-port`
   4. 默认 `5000`

---

## 本地运行（不使用 Docker）

> 前提：已安装 SBCL，并通过 Quicklisp 能 `ql:quickload` 相关依赖。

### 方式一：脚本一键启动

```bash
./start.sh      # 启动
./status.sh     # 查看状态
./stop.sh       # 停止
```

默认访问：

```text
http://localhost:5000
```

如需指定端口，可在启动前设置环境变量：

```bash
PORT=6000 ./start.sh
# 访问 http://localhost:6000
```

### 方式二：手动在 REPL 中启动

```bash
sbcl --load todo-web.lisp
```

在 REPL 中：

```lisp
(in-package :todo-web)
(start-server)          ; 或 (start-server 5000)
```

然后打开浏览器访问 `http://localhost:5000`。

---

## HTTP API 简要说明

### 1. 获取全部 Todo 列表

```http
GET /api/todos
```

返回 JSON 数组：

```json
[
  { "id": 1, "text": "吃饭",   "done": false },
  { "id": 2, "text": "写代码", "done": true }
]
```

### 2. 新增 Todo

```http
POST /api/todos
Content-Type: application/json

{"text": "写 Lisp"}
```

成功时：

* 返回最新完整列表
* HTTP 状态码 `201 Created`

常见错误：

* `400 text-required`：文本为空
* `400 text-too-long`：超过 `max-text-length`
* `400 too-many-todos`：数量超过 `max-todo-count`
* `507 data-file-too-large`：数据文件尺寸超过 `max-data-bytes`

### 3. 更新完成状态

```http
PATCH /api/todos?id=1
Content-Type: application/json

{"done": true}
```

如果 body 中省略 `done` 字段，则会进行“反转完成状态”的兼容行为。

### 4. 删除 Todo

```http
DELETE /api/todos?id=1
```

成功后返回最新完整列表。

### 5. SSE 实时事件

```http
GET /api/todos/events
```

返回 `text/event-stream`，前端可以这样使用：

```js
const es = new EventSource('/api/todos/events')

es.onmessage = (evt) => {
  const data = JSON.parse(evt.data)
  // data 是完整的 todos 数组
  renderList(data)
}
```

后端在增删改 Todo 后会调用 `broadcast-todos`，向所有在线 SSE 客户端广播最新完整列表。

---

## Docker 部署

本项目提供了多阶段构建的 `Dockerfile`。

### 构建镜像

```bash
docker build -t lisp-todo-web .
```

构建完成后，可以查看镜像大小：

```bash
docker image ls lisp-todo-web
```

### 简单运行

```bash
docker run -p 5000:5000 lisp-todo-web
```

访问：[http://localhost:5000](http://localhost:5000)

### 带数据持久化的运行方式

1. 在宿主机创建数据目录：

```bash
mkdir -p /home/your-name/todo-data
```

2. 运行容器并挂载数据目录：

```bash
docker run \
  -p 5000:5000 \
  -v /home/your-name/todo-data:/app/data \
  lisp-todo-web
```

此时：

* 应用在容器内监听 `5000` 端口
* 访问 [http://localhost:5000](http://localhost:5000)
* 数据会写入容器内 `/app/data/todos.json`，真实落到宿主机 `/home/your-name/todo-data/todos.json`

> 更多关于多阶段构建、镜像体积优化的细节，见 `doc/docker.md`。

---

## 在 Render 上部署

本项目已经在 Render 上部署，你也可以用自己的账号部署一份。

### 思路概览

* Render 会直接使用仓库中的 `Dockerfile` 构建镜像
* Render 自动注入 `PORT` 环境变量，应用会使用该端口监听
* 免费实例不保证容器文件系统持久化

### 操作步骤（简略）

1. 将仓库推送到 GitHub（本仓库已推送）
2. 登录 Render，选择 **New → Web Service**
3. 选择 **From Git repository**，选中本仓库
4. 构建方式选择 **Docker**（Render 会自动识别 Dockerfile）
5. 其他配置保持默认或选择 Free 方案
6. 点击创建，等待构建与部署完成

完成后，Render 会给出一个类似这样的地址：

```text
https://lisp-todo-web.onrender.com
```

> 注意：如果你在 Render 上也希望数据真正持久，请考虑：
>
> * 使用 Render 的 Persistent Disk 功能；或
> * 把 Todo 存到外部数据库（PostgreSQL / Redis 等），而不是本地 JSON 文件。

---

## 开发小记

这个项目的目标不是做一个“功能特别完备”的 Todo 应用，而是：

* 用 Common Lisp 写一个完整链路的 Web 小服务：

  * 前端页面 + 后端 API + 持久化
* 练习 Hunchentoot + SSE 的用法
* 体验多阶段 Docker 构建，把 Lisp 程序打包成一个小镜像
* 顺便试一把在 Render 上部署带 SSE 的服务

如果你有兴趣，可以在此基础上扩展：

* 增加 Todo 编辑功能
* 增加过滤器（全部 / 未完成 / 已完成）
* 增加多用户/多列表支持
* 把存储从 JSON 文件换成数据库

---

## License

本项目使用 **MIT License**，详见 [`LICENSE`](./LICENSE)。
