# Docker 部署与镜像说明

> 本文档专门记录 Lisp Todo Web 的 Docker 化方案和相关说明，避免把所有细节堆在 README 里。

## 1. 目标概述

* 提供一个 **可直接运行的容器镜像**，一条 `docker run` 命令即可启动服务。
* 在镜像内部使用 SBCL 将应用 **打包为单一可执行文件**，运行阶段无需再安装 Quicklisp / 源码。
* 支持通过 **配置文件 + 环境变量** 控制端口和数据文件位置。
* 支持在 Docker 中通过 **挂载宿主机目录** 实现数据持久化。
* 使用 **多阶段构建（multi-stage build）** 控制最终镜像体积，目前运行镜像大小约 ~149MB。

---

## 2. 多阶段 Docker 构建设计

### 2.1 构建阶段（build stage）

* 基础镜像：`debian:12-slim`
* 安装内容：

  * SBCL
  * curl
  * ca-certificates
* 主要工作：

  1. 安装 Quicklisp（非交互模式）。
  2. `ql:quickload` 所需依赖：`hunchentoot`、`cl-json`、`flexi-streams`。
  3. 加载 `todo-web.lisp`，切换到 `todo-web` 包。
  4. 定义一个 `main` 函数：

     * 调用 `(start-server)`
     * 再用一个死循环 `loop (sleep 3600)` 挂住进程。
  5. 使用 `sb-ext:save-lisp-and-die` 将整个程序打包成一个自包含的可执行文件：`/app/todo-web-app`。

**这一阶段包含完整的 Lisp 编译环境，但最终不会进入运行镜像，用完即丢。**

### 2.2 运行阶段（runtime stage）

* 基础镜像：同样使用 `debian:12-slim`，但这是一个干净的新镜像。
* 额外安装：

  * `libssl3` —— 运行时提供 `libcrypto.so.3`，这是 SBCL 生成的二进制在 Debian 12 下的依赖之一。
* 在 `/app` 目录下布置内容：

  * `/app/todo-web-app`：从构建阶段复制的可执行文件。
  * `/app/public/`：静态资源（前端页面）。
  * `/app/config.json`：配置文件（端口 / 数据文件路径 / 限制等）。
  * `/app/data/`：预创建的数据目录，用于挂载宿主机目录。
* 暴露端口：`EXPOSE 5000`
* 启动命令：`CMD ["/app/todo-web-app"]`

最终运行镜像不再包含：SBCL、Quicklisp、项目源码、开发脚本等，只保留运行所需的最小集合。

---

## 3. Dockerfile 示例

> 注意：此 Dockerfile 仅用于说明结构，实际以仓库中的 Dockerfile 为准。

```dockerfile
# ========= 1) 构建阶段：带 SBCL + Quicklisp，用来打包 =========
FROM debian:12-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sbcl curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . /app

# 安装 Quicklisp（非交互）
RUN curl -o /tmp/quicklisp.lisp https://beta.quicklisp.org/quicklisp.lisp && \
    sbcl --non-interactive \
         --load /tmp/quicklisp.lisp \
         --eval '(quicklisp-quickstart:install)' \
         --eval '(quit)' && \
    rm /tmp/quicklisp.lisp

# 预加载依赖 + 加载应用代码 + 定义 main + 打成可执行文件
RUN sbcl --non-interactive \
         --load /root/quicklisp/setup.lisp \
         --eval '(ql:quickload (list "hunchentoot" "cl-json" "flexi-streams"))' \
         --load "/app/todo-web.lisp" \
         --eval '(in-package :todo-web)' \
         --eval '(defun main () (start-server) (loop (sleep 3600)))' \
         --eval '(sb-ext:save-lisp-and-die "/app/todo-web-app" \
                     :toplevel (quote todo-web::main) \
                     :executable t \
                     :compression t)'

# ========= 2) 运行阶段：只带二进制 + 静态文件 =========
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# 安装运行时需要的 OpenSSL 库（提供 libcrypto.so.3）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libssl3 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/data

COPY --from=build /app/todo-web-app /app/todo-web-app
COPY public/ /app/public/
COPY config.json /app/config.json

EXPOSE 5000

CMD ["/app/todo-web-app"]
```

---

## 4. 配置与数据持久化

### 4.1 配置文件 `config.json`

应用启动时会：

1. 根据 `*project-root*` 自动定位 `config.json`：

   * 默认为容器内 `/app/config.json`。
2. 使用 JSON 内容初始化全局配置 `*config*`，并根据 `"data-file"` 字段设置 `*data-file*`，例如：

```json
{
  "listen-port": 5000,
  "data-file": "data/todos.json",
  "max-data-bytes": 1048576,
  "max-todo-count": 500,
  "max-text-length": 200
}
```

* `listen-port`：默认监听端口（可被环境变量 `PORT` 覆盖）。
* `data-file`：数据文件相对路径（基于项目根目录 `/app` 拼出来）。
* `max-data-bytes`：数据文件最大允许体积（字节）。
* `max-todo-count`：Todo 条数上限。
* `max-text-length`：单条 Todo 文本最大长度。

### 4.2 环境变量 `PORT`

`start-server` 的端口解析逻辑：

1. 优先从环境变量 `PORT` 读取。
2. 如果 `PORT` 不存在或解析失败，则使用配置文件中的 `listen-port`。
3. 最终默认值是 `5000`。

这保证了在本地 / Docker / Render 等环境下都可以用统一方式指定端口。

### 4.3 数据持久化目录挂载

当 `config.json` 中：

```json
"data-file": "data/todos.json"
```

在容器内路径会被解析为：

* `/app/data/todos.json`

为了让数据在容器销毁后仍然存在，可以在 `docker run` 时挂载宿主机目录：

```bash
mkdir -p /home/jason/todo-data

docker run \
  -p 5000:5000 \
  -v /home/jason/todo-data:/app/data \
  lisp-todo-web
```

此时：

* 容器内写入 `/app/data/todos.json`；
* 实际数据会同步到宿主机 `/home/jason/todo-data/todos.json`；
* 即使容器删除 / 重建，数据依然存在。

---

## 5. 构建与运行示例

### 5.1 构建镜像

在项目根目录执行：

```bash
docker build -t lisp-todo-web .
```

完成后可以查看镜像大小：

```bash
docker image ls lisp-todo-web
```

示例输出：

```text
REPOSITORY      TAG       IMAGE ID       CREATED         SIZE
lisp-todo-web   latest    faedf9b599b9   2 minutes ago   149MB
```

### 5.2 本地运行（带持久化）

```bash
mkdir -p /home/jason/todo-data

docker run \
  -p 5000:5000 \
  -v /home/jason/todo-data:/app/data \
  lisp-todo-web
```

* 访问地址：[http://localhost:5000](http://localhost:5000)
* 数据文件：`/home/jason/todo-data/todos.json`

停止容器后，数据仍然保留在宿主机目录中。

---

## 6. 镜像体积与优化点

通过多阶段构建，当前运行镜像大小约：**149MB**。

从 `docker history` 可以看到主要体积来源：

* `debian:12-slim` 基础镜像：约 85MB。
* 应用可执行文件 `todo-web-app`：约 13.6MB。
* 运行时依赖 `libssl3` 等：约 6MB。
* 其余为配置与目录创建的少量开销。

相比直接把 SBCL、Quicklisp、源代码、编译缓存全部放进一个镜像，这个方案具有：

* 运行镜像更小；
* 启动更快（无需在容器启动时 quickload 依赖）；
* 生产环境镜像内容更简单、攻击面更小。

如果未来希望进一步压缩镜像体积，可以考虑：

* 使用更精简的运行时基础镜像（如 distroless 系列）；
* 结合更激进的系统裁剪方案。但这些已经超出当前 demo 的需求范围。

---

## 7. 与本地脚本启动方式的关系

项目中还保留了一套本地开发用的脚本：

* `start.sh` / `stop.sh` / `status.sh`

它们适用于 **直接在宿主机上用 SBCL 启动服务** 的场景：

* 使用 `todo-web.lisp` + 本地 SBCL 解释执行；
* 带日志文件输出与简单的进程管理。

Docker 化之后，这些脚本在容器内部不是必须的，但：

* 本地开发 / 调试时仍然可以使用这些脚本；
* Docker 用的是打包好的二进制入口，互不影响。

---

## 8. 小结

* Docker 方案通过 **多阶段构建 + SBCL 打包可执行文件**，实现了一个体积适中、部署简单的运行镜像。
* 支持在容器中使用 `config.json` 配置端口和数据路径，并通过挂载宿主机目录实现持久化。
* 本文档只专注于 Docker 构建与部署细节，避免 README 过长，便于后续单独维护和扩展。
