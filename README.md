# Lisp Todo Web

一个用 **Common Lisp** 写的小型 Todo Web 应用，包含：

* 基于 **Hunchentoot** 的 HTTP 服务
* RESTful API（`/api/todos`）+ Server-Sent Events（`/api/todos/events`）
* 支持拖拽排序的列表接口（`/api/todos/reorder`）
* 前端页面 + 原生 JavaScript + SSE 实时刷新
* JSON 文件持久化（支持配置和 Docker 卷挂载）
* 多阶段 Docker 构建，生成较小的运行时镜像
* 已部署在 Render，提供在线 Demo

---

## 在线 Demo

本项目已部署在 Render 免费实例上，可以直接在线体验：

👉 [https://lisp-todo-web.onrender.com](https://lisp-todo-web.onrender.com)

> 提示：Render 免费实例长时间无人访问会“休眠”，第一次打开可能会稍慢，需要等它唤醒后才能正常访问。

---

## 功能特性

* ✍️ **增删 Todo**

  * 输入框 + 按钮 / 回车 创建任务
  * 每条任务都可以删除（带缩小 + 淡出动画）

* ✔ **完成状态切换**

  * 勾选复选框切换完成 / 未完成
  * 完成项变灰 + 删除线，未完成正常显示

* 🔄 **多标签页实时同步（SSE）**

  * 前端通过 `EventSource` 订阅 `/api/todos/events`
  * 任意一个浏览器窗口增删改 Todo，其他窗口会自动同步最新列表

* 📌 **拖拽排序（前端 + 排序接口）**

  * 前端使用拖拽组件（例如 SortableJS）调整任务顺序
  * 释放时将当前顺序对应的 `ids` 列表 POST 给 `/api/todos/reorder`
  * 后端根据 `ids` 重排当前内存列表，并持久化到 JSON 文件

* 📊 **统计信息**

  * 底部展示：`共 N 条任务，未完成 M 条`

* 💾 **文件持久化**

  * Todo 写入 JSON 文件，服务重启后自动恢复
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

  * 提供 HTTP 服务器与路由
  * 暴露 RESTful API 与 SSE 端点
* `cl-json` —— JSON 编解码
* `flexi-streams` —— 将底层二进制流包装为 UTF-8 字符流，用于 SSE 推送

**前端**

> 说明：仓库当前的 `public/index.html` 还是简化的占位页面；你可以替换为带拖拽 + SSE 的完整实现，接口设计已经就绪。

* 单文件前端：`public/index.html`
* 原生 JavaScript（计划 / 建议）：

  * 使用 `fetch` 调用 `GET / POST / PATCH / DELETE /api/todos`
  * 使用 `EventSource` 订阅 `/api/todos/events` 做实时刷新
  * 使用拖拽库（如 `SortableJS`）配合 `/api/todos/reorder` 实现前端拖拽排序
* 简单 CSS / Tailwind 动画（可选）：

  * 卡片淡入、悬浮阴影
  * 删除时缩小 + 淡出

**部署 / 运维**

* 多阶段 Docker 构建：

  * 构建阶段：安装 SBCL + Quicklisp，加载 `todo-web.lisp` 并通过 `save-lisp-and-die` 打包为单一可执行文件
  * 运行阶段：基于精简 Debian，仅包含可执行文件和静态资源
* 本地管理脚本：`start.sh` / `stop.sh` / `status.sh`

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
│   └── index.html      # 前端页面（当前为占位 UI，可替换为完整实现）
├── start.sh            # 本地启动脚本（非 Docker）
├── stop.sh             # 本地停止脚本
├── status.sh           # 查看本地进程状态
├── todo-web.lisp       # Lisp 后端源码
└── todos.json          # 本地示例数据（实际运行可使用 data/todos.json）
```

> 实际运行时，数据文件路径由 `config.json` 控制，推荐使用 `data/todos.json`，并通过 Docker 卷挂载到宿主机目录。

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

字段说明：

* `listen-port`：默认监听端口（会被环境变量 `PORT` 覆盖，前提是调用 `start-server` 时不显式传入端口）
* `data-file`：数据文件路径

  * 支持相对路径（相对项目根目录，如 `data/todos.json`）
* `max-data-bytes`：数据文件允许的最大体积（字节）
* `max-todo-count`：最多允许保存的 Todo 数量
* `max-text-length`：单条 Todo 文本最大长度

应用启动流程（针对 `start-server` 函数本身）：

1. 读取 `config.json`，初始化 `*config*` / `*data-file*`
2. 如果 `data-file` 存在，从中加载历史 Todo
3. 按以下优先级决定端口：

   1. 函数参数 `port`（调用者显式传入）
   2. 环境变量 `PORT`
   3. 配置文件中的 `listen-port`
   4. 默认值 `5000`

> 注意：仓库里的 `start.sh` 当前是写死 `(start-server 5000)`，因此 `PORT=6000 ./start.sh` 实际不会改变端口。如果希望通过环境变量控制端口，可以将脚本中的 `5000` 参数去掉，让 `start-server` 自己做选择。

---

## Todo JSON 结构

后端使用一个 `todo-item` 结构体来保存任务，JSON 编码后的字段形如：

```json
{
  "id": 1,
  "text": "写代码",
  "done": false,
  "priority": null,
  "due_time": null,
  "order": 1,
  "created_at": 3920000000,
  "updated_at": 3920000000
}
```

字段含义：

* `id`：自增整数 ID
* `text`：Todo 文本内容
* `done`：是否已完成（布尔值）
* `priority`：预留的优先级字段（当前前端未使用，可以在将来扩展）
* `due_time`：预留的截止时间字段（当前前端未使用）
* `order`：当前列表中的排序位置（`/api/todos/reorder` 会更新这个值）
* `created_at`：创建时间（Lisp `universal-time` 整数）
* `updated_at`：最后修改时间（Lisp `universal-time` 整数）

> 前端如果只关心基础功能，可以只使用 `id` / `text` / `done` 三个字段，其余可以忽略。

---

## 本地运行（不使用 Docker）

> 前提：已安装 SBCL，并通过 Quicklisp 能 `ql:quickload` 所需依赖。

### 方式一：使用脚本一键启动

```bash
./start.sh      # 启动
./status.sh     # 查看状态
./stop.sh       # 停止
```

当前脚本默认使用端口 `5000`：

```text
http://localhost:5000
```

如果你修改了 `start.sh`，让它不再写死 `5000`，而是调用 `(start-server)`，那么就可以通过环境变量来覆盖端口：

```bash
PORT=6000 ./start.sh
# 然后访问 http://localhost:6000
```

### 方式二：在 REPL 中手动启动

```bash
sbcl --load todo-web.lisp
```

在 REPL 中：

```lisp
(in-package :todo-web)
(start-server)          ; 或 (start-server 5000)
```

然后打开浏览器访问 `http://localhost:5000`（或你自己指定的端口）。

---

## HTTP API 简要说明

### 1. 获取全部 Todo 列表

```http
GET /api/todos
```

返回 JSON 数组（每项为“Todo JSON 结构”中描述的对象）：

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
* HTTP 状态码为 `201 Created`

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

如果请求 body 中省略 `done` 字段，会触发“反转完成状态”的兼容行为（即从已完成变为未完成，或反之）。

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

后端在增删改 / 排序 Todo 后会调用 `broadcast-todos`，向所有在线 SSE 客户端广播最新完整列表。

### 6. 调整 Todo 顺序

```http
POST /api/todos/reorder
Content-Type: application/json

{"ids": [3, 1, 2]}
```

含义：

* `ids`：一个整数数组，表示前端当前列表从上到下的 `id` 顺序。

行为说明：

1. 后端会根据 `ids` 重建内部的 `*todos*` 列表顺序；
2. `ids` 中未出现但仍然存在的 todo，会被追加到列表末尾（容错处理）；
3. 顺序更新后会同步写入数据文件，并更新各个 todo 的 `order` 字段；
4. 最后返回完整列表，并通过 SSE 广播给所有在线客户端。

常见错误：

* `400 ids-required`：未提供 `ids` 字段
* `400 ids-must-be-list`：`ids` 不是一个数组

---

## Docker 部署

本项目提供了多阶段构建的 `Dockerfile`，可以方便地打包并部署。

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

然后访问：[http://localhost:5000](http://localhost:5000)

### 带数据持久化的运行

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
* 浏览器访问 [http://localhost:5000](http://localhost:5000)
* 数据会写入容器内 `/app/data/todos.json`，实际落在宿主机 `/home/your-name/todo-data/todos.json`

> 更多关于多阶段构建、镜像体积优化的细节，见 `doc/docker.md`。

---

## 在 Render 上部署

本项目已经在 Render 上部署，你也可以用自己的账号再部署一份。

### 思路概览

* Render 会直接使用仓库中的 `Dockerfile` 构建镜像
* Render 会自动注入 `PORT` 环境变量，应用会使用该端口监听
* 免费实例不保证容器文件系统持久化

### 操作步骤（简略）

1. 将仓库推送到 GitHub（本仓库已推送）
2. 登录 Render，选择 **New → Web Service**
3. 选择 **From Git repository**，选中本仓库
4. 构建方式选择 **Docker**（Render 会自动识别 `Dockerfile`）
5. 其他配置保持默认或选择 Free 方案
6. 点击创建，等待构建与部署完成

完成后，Render 会给出一个类似这样的地址：

```text
https://lisp-todo-web.onrender.com
```

> 注意：如果在 Render 上也希望数据真正持久，请考虑：
>
> * 使用 Render 的 Persistent Disk 功能；或
> * 将 Todo 存储迁移到外部数据库（PostgreSQL / Redis 等），而不是本地 JSON 文件。

---

## 开发小记

这个项目的目标不是做一个“功能特别完备”的 Todo 应用，而是：

* 用 Common Lisp 写一个“前端 + 后端 + 持久化”完整链路的小服务：

  * 前端页面
  * 后端 API
  * 文件持久化
* 练习 Hunchentoot + SSE 的用法
* 体验多阶段 Docker 构建，把 Lisp 程序打包成一个较小的镜像
* 顺便试一把在 Render 上部署带 SSE 的服务

如果你有兴趣，可以在此基础上继续扩展：

* 增加 Todo 编辑功能

* 增加多用户 / 多列表支持

* 将存储从 JSON 文件换成数据库

---

## License

本项目使用 **MIT License**，详见 [`LICENSE`](./LICENSE)。
