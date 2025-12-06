# ========= 1) 构建阶段：带 SBCL + Quicklisp，用来打包 =========
FROM debian:12-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

# 安装 SBCL + curl（给 quicklisp 用）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sbcl curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 拷贝项目代码到构建镜像
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

# 安装运行时需要的 OpenSSL 库（提供 libcrypto.so.3），镜像仍然比带 sbcl 小很多
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libssl3 && \
    rm -rf /var/lib/apt/lists/*

# 预创建数据目录（给挂 Volume 用）
RUN mkdir -p /app/data

# 从构建镜像复制可执行文件
COPY --from=build /app/todo-web-app /app/todo-web-app

# 复制静态资源和配置文件
COPY public/ /app/public/
COPY config.json /app/config.json

# 默认端口：5000（也可以通过环境变量 PORT 覆盖）
EXPOSE 5000

CMD ["/app/todo-web-app"]
