# FCGI Server

(import /fcgi)
(import /log)
(import /config)

(defn load-routes
  [routes]
  (let [entry-points @[]]
    (each route routes
      (let [e (dofile (route :script))
            entry-point ((e 'fcgi-entry-point) :value)]
        (log/write
         (string/format "loading route '%s' using script: '%s'"
                        (route :url)
                        (route :script)) 0)
        (array/push entry-points
                    {:url (route :url) :function entry-point})))
    entry-points))

(defn handle-values
  [conn header content]
  (let [req-vars content
        resp-header (fcgi/mk-header :type :fcgi-get-values-result)]
    (put req-vars "FCGI_MAX_CONNS" "1")
    (log/write (string/format "pp table without newlines!") 1)
    (fcgi/write-msg conn resp-header req-vars)))

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
          (let [fun ((get entry-points match) :function)
                result (fun (request :params) (request :stdin))]
            (fcgi/write-msg conn header result))
          ([err f]
           (set app-status 500)))
        (set app-status 404))
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
              (log/write (string/format "received: %p" (header :type)) 0)
              (case (header :type)
                :fcgi-get-values
                 (handle-values conn header content)
                 :fcgi-params
                 (handle-request conn header content entry-points)
                 :fcgi-stdin
                 (handle-request conn header content entry-points)
                 :fcgi-null-request-id
                 (return :quit)))))))
    (:close conn)
    (:close fcgi-server)))

(defn main
  [& args]
  (log/init config/log-file config/log-level)
  (when (os/stat config/socket-file)
    (os/rm config/socket-file))
  (handle-messages config/socket-file)
  (log/write "terminated by client" 0)
  (os/rm config/socket-file))
