;;; -*- coding: utf-8; -*-

(ql:quickload '("hunchentoot" "cl-json" "flexi-streams"))


(defpackage :todo-web
  (:use :cl)
  (:export :start-server
           :stop-server))
(in-package :todo-web)

;; 项目根目录 = 当前 todo-web.lisp 所在目录
(defparameter *project-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))

;; 数据持久化文件：<项目根>/todos.json
(defparameter *data-file*
  (merge-pathnames #P"todos.json" *project-root*))

;;; ====== 内存里的 Todo 数据结构 ======

(defvar *todos* (make-hash-table))  ; id -> plist
(defvar *next-id* 0)

(defun make-todo (text &key (done nil) id)
  "创建一个 todo 对象（plist）。如果 id 未提供则自增一个新 id。"
  (let ((real-id (or id (incf *next-id*))))
    (list :id   real-id
          :text text
          :done done)))

(defun todo-list ()
  "以 list 返回当前所有 todo（plist）。"
  (loop for v being the hash-values of *todos*
        collect v))

(defun todo->json-object (todo)
  "把 plist 形式的 TODO 转成适合 cl-json 的对象 alist。"
  (list (cons "id"   (getf todo :id))
        (cons "text" (getf todo :text))
        (cons "done" (and (getf todo :done) t))))

(defun todos-data ()
  "返回 todo 列表对应的 Lisp 数据结构（给 JSON 编码用）。"
  (mapcar #'todo->json-object (todo-list)))

;;; ====== JSON 工具 ======

(defun respond-json (data &optional (code 200))
  "统一 JSON 响应：设置 content-type 和 HTTP 状态码。"
  (setf (hunchentoot:content-type*)
        "application/json; charset=utf-8")
  (setf (hunchentoot:return-code*) code)
  (cl-json:encode-json-to-string data))

(defun read-json-body ()
  "从请求体读取 JSON，解析为 alist，失败或无 body 时返回 NIL。"
  (let ((raw (hunchentoot:raw-post-data :force-text t)))
    (when (and raw (> (length raw) 0))
      (handler-case
          (cl-json:decode-json-from-string raw)
        (error ()
          nil)))))

;;; ====== 文件持久化 ======

(defun save-todos-to-file ()
  "把当前 todos 写入 *data-file*（JSON 数组）。"
  (with-open-file (out *data-file*
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
    (write-string (cl-json:encode-json-to-string (todos-data)) out)))

(defun load-todos-from-file ()
  "从 *data-file* 读入 todos，如果文件不存在则什么也不做。"
  (when (probe-file *data-file*)
    (with-open-file (in *data-file*
                        :direction :input
                        :external-format :utf-8)
      (let* ((len (file-length in))
             (content (make-string len)))
        (read-sequence content in)
        (let ((data (cl-json:decode-json-from-string content)))
          ;; data 格式形如：(((\"id\" . 1) (\"text\" . \"xxx\") (\"done\" . T)) ...)
          (clrhash *todos*)
          (setf *next-id* 0)
          (dolist (obj data)
            (let* ((id   (or (cdr (assoc :id   obj))
                             (cdr (assoc "id"   obj :test #'string=))))
                   (text (or (cdr (assoc :text obj))
                             (cdr (assoc "text" obj :test #'string=))))
                   (done (or (cdr (assoc :done obj))
                             (cdr (assoc "done" obj :test #'string=)))))
              (when (and id text)
                (let ((todo (make-todo text :id id :done (and done t))))
                  (setf (gethash id *todos*) todo)
                  (setf *next-id* (max *next-id* id)))))))))))

;;; ====== SSE 客户端管理 & 广播 ======

(defvar *sse-clients* '()
  "当前所有连接着 SSE 的输出流列表。")

(defun add-sse-client (stream)
  (push stream *sse-clients*))

(defun remove-sse-client (stream)
  (setf *sse-clients* (remove stream *sse-clients*)))

(defun broadcast-todos ()
  "把当前 todos 列表通过 SSE 推送给所有在线客户端。
   如果某个连接已经挂了，就从列表里移除。"
  (let ((payload (cl-json:encode-json-to-string (todos-data))))
    (setf *sse-clients*
          (remove-if
           #'null
           (mapcar (lambda (stream)
                     (handler-case
                         (progn
                           ;; SSE 默认事件格式：data: ...\n\n
                           (format stream "data: ~A~%~%" payload)
                           (finish-output stream)
                           stream)
                       (error ()
                         ;; 写失败说明连接断了，返回 NIL 让上面的 remove-if 去掉
                         nil)))
                   *sse-clients*)))))
(defun todos-events-handler ()
  "SSE 事件流：GET /api/todos/events。"
  ;; 设置 SSE 所需的响应头
  (setf (hunchentoot:content-type*)
        "text/event-stream; charset=utf-8")
  (setf (hunchentoot:header-out :cache-control) "no-cache")
  (setf (hunchentoot:header-out :connection) "keep-alive")

  ;; send-headers 返回的是底层的二进制流（CHUNGA:CHUNKED-IO-STREAM）
  ;; 我们用 flexi-streams 包一层，变成“带 UTF-8 编码的字符流”
  (let* ((raw-stream   (hunchentoot:send-headers))
         (char-stream  (flexi-streams:make-flexi-stream
                        raw-stream
                        :external-format :utf-8)))
    ;; 把字符流加入 SSE 客户端列表
    (add-sse-client char-stream)

    ;; 先推一次当前全量数据
    (format char-stream "data: ~A~%~%"
            (cl-json:encode-json-to-string (todos-data)))
    (finish-output char-stream)

    ;; 保持连接挂起，后续由 broadcast-todos 往这些流写数据
    (unwind-protect
         (loop
           (sleep 60))     ; 简单挂住这个 worker 线程
      ;; 连接断开 / 线程结束，移除客户端
      (remove-sse-client char-stream))))




;;; ====== REST 风格的 /api/todos 处理 ======

(defun parse-id-parameter ()
  "从 ?id=... 里解析整数 id，失败返回 NIL。"
  (let ((id-str (hunchentoot:parameter "id")))
    (and id-str
         (ignore-errors
           (parse-integer id-str :junk-allowed t)))))

(defun find-todo (id)
  (and id (gethash id *todos*)))

(defun handle-list-todos ()
  "GET /api/todos -> 返回全部 todo 列表。"
  (respond-json (todos-data) 200))

(defun handle-create-todo ()
  "POST /api/todos -> 新增一条 todo，返回最新列表。body 支持 JSON 或 form。"
  (let* ((body (read-json-body))
         (text (or (and body
                        (or (cdr (assoc :text body))
                            (cdr (assoc "text" body :test #'string=))))
                   (hunchentoot:parameter "text"))))
    (if (and text (> (length text) 0))
        (progn
          (let ((todo (make-todo text)))
            (setf (gethash (getf todo :id) *todos*) todo))
          (save-todos-to-file)
          (broadcast-todos)
          ;; 返回完整列表，方便前端直接 renderList
          (respond-json (todos-data) 201))
        (respond-json '(("error" . "text-required")) 400))))

(defun handle-update-todo ()
  "PATCH /api/todos?id=... -> 更新 todo。当前只用来修改 done 字段。"
  (let* ((id   (parse-id-parameter))
         (todo (find-todo id)))
    (unless todo
      (return-from handle-update-todo
        (respond-json '(("error" . "not-found")) 404)))
    (let* ((body (read-json-body))
           (has-done-p (and body (or (assoc :done body)
                                     (assoc "done" body :test #'string=)))))
      (cond
        ;; 如果 body 里有 done 字段，就按客户端指定的布尔值来设置
        (has-done-p
         (let* ((raw-done (or (cdr (assoc :done body))
                              (cdr (assoc "done" body :test #'string=))))
                (new-done (and raw-done t)))
           (setf (getf todo :done) new-done)))
        ;; 否则，退化成“切换完成状态”的行为（向后兼容）
        (t
         (setf (getf todo :done) (not (getf todo :done))))))
    (save-todos-to-file)
    (broadcast-todos)
    ;; 返回完整列表
    (respond-json (todos-data) 200)))

(defun handle-delete-todo ()
  "DELETE /api/todos?id=... -> 删除 todo，返回最新列表。"
  (let* ((id   (parse-id-parameter))
         (todo (find-todo id)))
    (unless todo
      (return-from handle-delete-todo
        (respond-json '(("error" . "not-found")) 404)))
    (remhash id *todos*)
    (save-todos-to-file)
    (broadcast-todos)
    ;; 这里也选择返回完整列表，方便前端直接渲染
    (respond-json (todos-data) 200)))

(defun todos-handler ()
  "统一处理 /api/todos，根据 HTTP 方法分发。"
  (case (hunchentoot:request-method*)
    (:GET    (handle-list-todos))
    (:POST   (handle-create-todo))
    (:PATCH  (handle-update-todo))
    (:DELETE (handle-delete-todo))
    (t       (respond-json '(("error" . "method-not-allowed")) 405))))

;;; ====== 首页：读静态 HTML 返回 ======

(defun read-file-as-string (path)
  (with-open-file (in path
                      :direction :input
                      :external-format :utf-8)
    (let ((content (make-string (file-length in))))
      (read-sequence content in)
      content)))

(defun index-handler ()
  (setf (hunchentoot:content-type*)
        "text/html; charset=utf-8")
  (read-file-as-string
   (merge-pathnames #P"public/index.html" *project-root*)))

;;; ====== 配置 dispatch table ======

(defun setup-dispatch-table ()
  (setf hunchentoot:*dispatch-table*
        (list
         ;; SSE 事件流
         (hunchentoot:create-prefix-dispatcher "/api/todos/events" #'todos-events-handler)
         ;; RESTful API
         (hunchentoot:create-prefix-dispatcher "/api/todos" #'todos-handler)
         
         ;; 静态首页
         (hunchentoot:create-prefix-dispatcher "/"          #'index-handler))))

;;; ====== 启动 / 停止服务器 ======

(defvar *server* nil)

(defun start-server (&optional (port 5000))
  "启动 HTTP 服务器，默认端口 5000。会尝试从 todos.json 加载历史数据。"
  (setup-dispatch-table)
  (load-todos-from-file)          ; 如果文件存在就加载，否则保持空列表
  (setf *server*
        (hunchentoot:start
         (make-instance 'hunchentoot:easy-acceptor
                        :port port)))
  (format t "Todo Web server started on http://localhost:~A/~%" port)
  *server*)

(defun stop-server ()
  "停止 HTTP 服务器。"
  (when *server*
    (hunchentoot:stop *server*)
    (setf *server* nil)
    (format t "Todo Web server stopped.~%")))
