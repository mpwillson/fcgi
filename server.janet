# FCGI Server

(import ./fcgi)
(import ./log)

# Provide stub routines if osx module is not available; avoid compile error
(try
  (import osx)
  ([err]
   (defglobal 'osx/chroot (fn[& _]))
   (defglobal 'osx/chown (fn[& _]))
   (defglobal 'osx/setuid (fn[& _]))
   (defglobal 'osx/setgid (fn[& _]))
   (defglobal 'osx/hostname (fn[& _] "unknown"))))

# import host-dependent config if it exists. Fallback to config.janet
(def *config-file*
  (let [cf (string "./config-" (osx/hostname))]
    (try
      (do
        (import* cf :as "config")
        cf)
      ([err]
       (when (not (string/has-prefix? "could not find module" err))
         (file/write stderr
                     (string/format "Error loading config file: %s\n" err))
         (os/exit 1))
       (import ./config)
       "./config"))))

(def *HTML* "Content-type: text/html\n\n<p>FCGI Server error: %s</p>")

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
  [conn header request entry-points]
    (var app-status 0)
    (let [header (fcgi/mk-header :type :fcgi-stdout
                    :request-id (header :request-id))
          target ((request :params) config/route-param)
          match (if target
                  (find-index |(= ($ :url) target) entry-points)
                  (log/write (string/format "Error: no such route param: %s"
                                            config/route-param)))]
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
  [fcgi-server]
  (var conn nil)
  (log/write (string/format "Using socket file: %s" config/socket-file))
  (let [entry-points (load-routes config/routes)]
    (prompt :quit
       (forever
        (when (not conn) (set conn (net/accept fcgi-server)))
        (let [[header content] (fcgi/read-msg conn)]
          (if (or (= header :closed) (= header :reset))
            (do
              (:close conn)
              (set conn (net/accept fcgi-server)))
            (try
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
                                                      entry-points)))

                  (= (header :type) :fcgi-abort-request)
                  (set conn (handle-abort-request conn header))

                  (= (header :type) :fcgi-null-request-id)
                  (return :quit)))
              ([err f]
               (log/write (string/format "Message handling error: %p" err))
               (when (or (= err "Broken pipe") (= err "stream hup"))
                 (:close conn)
                 (set conn nil))))))))
    (:close conn)
    (:close fcgi-server)))

(defn main
  [& args]
  (when config/chroot
    (os/cd config/chroot)
    (osx/chroot config/chroot))

  (log/init config/log-file config/log-level)
  (log/write "FCGI Server started")
  (log/write (string/format "Using config file: %s.janet" *config-file*))
  (log/write (string/format "Using log level: %d" config/log-level))
  (when config/chroot
    (log/write (string/format "Chroot to: %s" config/chroot)))
  (when (os/stat config/socket-file)
    (os/rm config/socket-file))

  (let [fcgi-server (net/listen :unix config/socket-file)]
    (when config/user
      (osx/chown config/socket-file config/user)
      (osx/setuid config/user))
    (handle-messages fcgi-server))

  (log/write "Terminated by client" 0)
  (os/rm config/socket-file))
