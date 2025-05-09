#!/usr/bin/env janet
#
# FCGI Server

(import fcgi-lib :as fcgi)
(import log)
(import util)

# Provide stub routines if osx module is not available; avoid compile error
(try
  (import osx)
  ([err]
   (defglobal 'osx/chroot (fn[& _]))
   (defglobal 'osx/chown (fn[& _]))
   (defglobal 'osx/setuid (fn[& _]))
   (defglobal 'osx/setgid (fn[& _]))
   (defglobal 'osx/hostname (fn[& _] "unknown"))))

(def *HTML* "Content-type: text/html\n\n<p>FCGI Server error: %s</p>")

(defn file-lines
  [filename]
  (if-let [f (file/open filename :r)]
    (file/lines f)
    (error
      (string/format "fcgi-config: unable to open file: %s" filename))))

(defn read-config
  `Merge server configuration from filename into config. Returns updated
   config. Will throw error on configuration errors.`
  [filename config]
  (let [lines (file-lines filename)
        simple-keywords "socket-file|chroot|user|route-param|log-file"
        comment-or-empty (peg/compile '(+ (* :s* "#") (* :s* -1)))]
    (each line lines
      (when (not (peg/match comment-or-empty line))
        (let [tokens (map string/trim
                          (string/split ":" (string/trim line)))]
          (cond
            (empty? tokens)
            (error (string/format "fcgi-config: malformed line: '%s'"
                                  line))

            (and (string/find (tokens 0) simple-keywords)
                 (= (length tokens) 2) (not= (tokens 1) ""))
            (put config (keyword (tokens 0))
                 (if (= (tokens 1) "nil") nil (tokens 1)))

            (and (= (tokens 0) "route") (= (length tokens) 3))
            (array/push (config :routes)
                        {:url (tokens 1) :script (tokens 2)})

            (= (tokens 0) "log-level")
            (if-let [ll (scan-number (tokens 1))]
              (put config :log-level ll)
              (error "fcgi-config: log-level must be numeric"))

            (error (string/format
                    "fcgi-config: malformed line: '%s'" line)))))))
  (put config :origin filename))

(defn find-config
  `Returns server configuration from filename, if provided, otherwise
   from preset locations. If no files found, returns default internal config.`
  [&opt filename]
  (let [config @{:origin "<InternalDefault>"
                 :socket-file "/tmp/fcgi.sock"
                 :chroot nil
                 :user nil
                 :route-param "DOCUMENT_URI"
                 :routes @[]
                 :log-file "/tmp/fcgi.log"
                 :log-level 3}
        files ["/etc/fcgi-server.cfg" "/usr/local/etc/fcgi-server.cfg"]]
    (if filename
      (read-config filename config)
      (each file files
        (when (os/stat file)
          (read-config file config))))
    config))

(defn load-routes
  [routes]
  (let [entry-points @[]]
    (each route routes
      (try
        (let [e (dofile (route :script))
              entry-point ((e 'fcgi-main) :value)]
          (log/write
           (string/format "Loaded route '%s' using script: '%s'"
                          (route :url) (route :script)) 0)
          (array/push entry-points
                      {:url (route :url) :function entry-point}))
        ([err f]
         (log/write
          (string/format "Error loading route '%s': %s"
                         (route :url) err) 0))))
    entry-points))

(defn handle-abort-request
  [conn header]
  (let [resp-hdr (fcgi/mk-header :type :fcgi-end-request :request-id
                    (header :request-id))
        req-id (header :request-id)
        keep-conn ((fcgi/requests req-id) :fcgi-keep-conn)
        content {:app-status 0 :protocol-status :fcgi-request-complete}]
    (fcgi/close-request (header :request-id))
    (fcgi/write-msg conn resp-hdr content)
    (log/write (string/format "Processed request: %p" (header :type)))
    (if keep-conn
      conn
      (do
        (:close conn)
        (log/write "Connection closed at webserver request" 2)
        nil))))

(defn handle-values
  [conn header content]
  (let [req-vars content
        resp-header (fcgi/mk-header :type :fcgi-get-values-result)]
    (put req-vars "FCGI_MAX_CONNS" "1")
    (fcgi/write-msg conn resp-header req-vars)
    (log/write (string/format "Processed request: %p" (header :type)))
    (log/write (string/format "%p" req-vars) 1)))

(defn invoke-request-handler
  [conn header request entry-points route-param]
    (var app-status 0)
    (let [header (fcgi/mk-header :type :fcgi-stdout
                    :request-id (header :request-id))
          target ((request :params) route-param)
          match (if target
                  (find-index |(= ($ :url) target) entry-points)
                  (log/write (string/format "Error: no such route param: %s"
                                            route-param)))]
      (if match
        (try
          (let [fun ((entry-points match) :function)
                result (fun (request :params) (request :stdin))]
            (if result
              (do
                (fcgi/write-msg conn header result)
                (log/write (string/format "Request OK: %s" target)))
              (let [fmt (string/format "Route returned nil: %s" target)]
                (fcgi/write-msg conn header
                                (string/format *HTML* fmt))
                (log/write fmt))))
          ([err f]
           (log/write (string/format "Error on route: %s: %s"
                                     ((entry-points match) :url) err))
           (fcgi/write-msg conn header (string/format *HTML* err))
           (set app-status 500)))
        (do
          (when target
            (log/write (string/format "Unknown route requested: %s" target))
            (fcgi/write-msg conn header
                            (string/format
                             *HTML*
                             (string/format "unknown route: %s" target))))
          (set app-status 404)))
      (put header :type :fcgi-end-request)
      (fcgi/write-msg conn header
                      @{:app-status app-status
                        :protocol-status :fcgi-request-complete})
      (let [keep-conn ((fcgi/requests (header :request-id)) :fcgi-keep-conn)]
        (fcgi/close-request (header :request-id))
        (if keep-conn
          conn
          (do
            (:close conn)
            (log/write "Connection closed at webserver request" 2)
            nil)))))

(defn handle-messages
  [fcgi-server socket-file routes route-param]
  (var conn nil)
  (log/write (string/format "Using socket file: %s" socket-file))
  (let [entry-points (load-routes routes)]
    (try
      (forever
       (when (not conn) (set conn (net/accept fcgi-server)))
       (let [[header content] (fcgi/read-msg conn)]
         (if (or (= header :closed) (= header :reset))
           (do
             (:close conn)
             (set conn (net/accept fcgi-server)))
           (do
             (log/write (string/format "Received: %p" (header :type)) 1)
             (cond
               (= (header :type) :fcgi-begin-request)
               (log/write (string/format "Begin request: %p\n%p"
                                         header content) 3)

               (= (header :type) :fcgi-get-values)
               (handle-values conn header content)

               (or (= (header :type) :fcgi-params)
                   (= (header :type) :fcgi-stdin))
               (when (and (content :params-complete)
                          (content :stdin-complete))
                 (set conn (invoke-request-handler conn header content
                                                   entry-points route-param)))

               (= (header :type) :fcgi-abort-request)
               (set conn (handle-abort-request conn header))

               (= (header :type) :fcgi-null-request-id)
               (do
                 (log/write "Terminated by client" 0)
                 (:close conn)
                 (:close fcgi-server)
                 (break)))))))
      ([err f]
       (log/write (string/format "Server exit: message handling error: %p" err))
       (when (or (= err "Broken pipe") (= err "stream hup"))
         (:close conn)
         (set conn nil))))))

(defn main
  [name & args]
  (let [opts (util/argparse args "c:" @{:c nil})
        config (try (find-config (opts :c))
                    ([err f] (eprintf err) (os/exit 1)))]
    (when (config :chroot)
      (os/cd (config :chroot))
      (osx/chroot (config :chroot)))
    (log/init (config :log-file) (config :log-level))
    (log/write "FCGI Server started")
    (log/write (string/format "Using config file: %s" (config :origin)))
    (log/write (string/format "Using log level: %d" (config :log-level)))
    (when (config :chroot)
      (log/write (string/format "Chroot to: %s" (config :chroot))))
    (when (os/stat (config :socket-file))
      (os/rm (config :socket-file)))

    (let [fcgi-server (net/listen :unix (config :socket-file))]
      (when (config :user)
        (osx/chown (config :socket-file) (config :user))
        (osx/setuid (config :user)))
      (handle-messages fcgi-server (config :socket-file)
                       (config :routes) (config :route-param)))

    (os/rm (config :socket-file))))
