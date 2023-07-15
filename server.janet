# FCGI Server

(import /fcgi)
(import /log)
(import /config)

(def HTML "Content-type: text/html\n\n<p>FCGI Server error: %s</p>")

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
        content {:app-status 0 :protocol-status :fcgi-request-complete}]
    (fcgi/close-request (header :request-id))
    (fcgi/write-msg conn resp-hdr content)
    (log/write (string/format "Processed request: %p" (header :type)))))

(defn handle-values
  [conn header content]
  (let [req-vars content
        resp-header (fcgi/mk-header :type :fcgi-get-values-result)]
    (put req-vars "FCGI_MAX_CONNS" "1")
    (fcgi/write-msg conn resp-header req-vars)
    (log/write (string/format "Processed request: %p" (header :type)))
    (log/write (string/format "%p" req-vars) 1)))

(defn handle-request
  [conn header request entry-points]
  (when (and (request :params-complete) (request :stdin-complete))
    (var app-status 0)
    (let [header (fcgi/mk-header :type :fcgi-stdout
                    :request-id (header :request-id))
          target ((request :params) config/route-param)
          match (find-index |(= ($ :url) target) entry-points)]
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
                                (string/format HTML fmt))
                (log/write fmt))))

          ([err f]
           (log/write (string/format "Error on route: %s: %s"
                                     ((entry-points match) :url) err))
           (fcgi/write-msg conn header (string/format HTML err))
           (set app-status 500)))
        (do
          (log/write (string/format "Unknown route requested: %s" target))
          (fcgi/write-msg conn header
                          (string/format
                           HTML (string/format "unknown route: %s" target)))
          (set app-status 404)))
      (put header :type :fcgi-end-request)
      (fcgi/write-msg conn header
                      @{:app-status app-status
                        :protocol-status :fcgi-request-complete})
      (fcgi/close-request (header :request-id)))))

(defn handle-messages
  [socket-file]
  (var conn nil)
  (let [fcgi-server (net/listen :unix socket-file)
        entry-points (load-routes config/routes)]
    (set conn (net/accept fcgi-server))
    (prompt :quit
       (forever
        (let [[header content] (fcgi/read-msg conn)]
          (if (or (= header :closed) (= header :reset))
            (do
              (:close conn)
              (set conn (net/accept fcgi-server)))
            (do
              (log/write (string/format "received: %p" (header :type)) 1)
              (case (header :type)
                :fcgi-get-values
                 (handle-values conn header content)
                 :fcgi-params
                 (handle-request conn header content entry-points)
                 :fcgi-stdin
                 (handle-request conn header content entry-points)
                 :fcgi-abort-request
                 (handle-abort-request conn header)
                 :fcgi-null-request-id
                 (return :quit)))))))
    (:close conn)
    (:close fcgi-server)))

(defn main
  [& args]
  (log/init config/log-file config/log-level)
  (log/write "FCGI Server started")
  (log/write (string/format "Using socket file: %s" config/socket-file))
  (when (os/stat config/socket-file)
    (os/rm config/socket-file))
  (handle-messages config/socket-file)
  (log/write "Terminated by client" 0)
  (os/rm config/socket-file))
