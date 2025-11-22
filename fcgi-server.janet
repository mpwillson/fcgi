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

(var *entry-points* "Holds route entry points for route-mgr" nil)

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

            (= (tokens 0) "max-threads")
            (if-let [mt (scan-number (tokens 1))]
              (put config :max-threads mt)
              (error "fcgi-config: max-threads must be numeric"))

            :else
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
                 :log-level 3
                 :max-threads 10}
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
  (let [req-id (header :request-id)
        resp-hdr (fcgi/mk-header :type :fcgi-end-request :request-id req-id)
        content {:app-status 0 :protocol-status :fcgi-request-complete}]
    (fcgi/close-request req-id)
    (fcgi/write-msg conn resp-hdr content)
    (log/write (string/format "Processed request: %p" (header :type)) 5)))

(defn handle-values
  [conn header content max-threads]
  (let [req-vars content
        resp-header (fcgi/mk-header :type :fcgi-get-values-result)]
    (put req-vars "FCGI_MAX_CONNS" "1")
    (put req-vars "FCGI_MAX_REQS" (string max-threads))
    (put req-vars "FCGI_MPXS_CONNS" "1")
    (fcgi/write-msg conn resp-header req-vars)
    (log/write (string/format "Processed request: %p" (header :type)))
    (log/write (string/format "%p" req-vars) 1)))

(defn run-thread
  [fun header request target chan peg-grammar]
  (setdyn :peg-grammar peg-grammar)
  (try
    (let [result (fun (request :params) (request :stdin))]
      (ev/give chan [:ok (header :request-id) header result target]))
    ([err f]
     (ev/give chan [:err (header :request-id) header err target]))))

(defn request-postlude
  [conn header app-status protocol-status]
  (put header :type :fcgi-end-request)
  (fcgi/write-msg conn header
                  @{:app-status app-status
                    :protocol-status protocol-status}))

(defn invoke-request-handler
  "Invoke route script in a new fiber. Returns true if route found,
   false otherwise."
  [conn header request entry-points route-param chan peg-grammar]
  (var app-status 0)
  (let [header (fcgi/mk-header :type :fcgi-stdout
                  :request-id (header :request-id))
        target ((request :params) route-param)
        match (if target
                (find-index |(= ($ :url) target) entry-points)
                (log/write (string/format "Error: no such route param: %s"
                                          route-param)))]
    (if match
      (let [fun ((entry-points match) :function)]
        (log/write (string/format "Starting request for: %s [%d]" target
                                  (header :request-id)) 0)
        (ev/call run-thread fun header request target chan
                                     peg-grammar)
        conn)
      (do
        (when target
          (log/write (string/format "Unknown route requested: %s" target))
          (fcgi/write-msg conn header
                          (string/format
                           *HTML*
                           (string/format "unknown route: %s" target))))
        (set app-status 404)
        (request-postlude conn header app-status :fcgi-request-complete)
        (= app-status 0)))))

(defn route-result
  [conn msg]
  "Process result from route script."
  (var app-status 0)
  (try
    (let [[tag id header result target] msg]
      (cond
        (= tag :ok)
        (if result
          (do
            (fcgi/write-msg conn header result)
            (log/write (string/format "Request OK: %s" target)))
          (let [fmt (string/format "Route returned nil: %s" target)]
            (fcgi/write-msg conn header
                            (string/format *HTML* fmt))
            (log/write fmt)))

        (= tag :err)
        (do
          (log/write (string/format "Error on route: %s: %s" target result))
          (fcgi/write-msg conn header (string/format *HTML* result))
          (set app-status 500))

        :else
         (log/write (string/format "Thread channel contains bad msg: %p"
                                   tag) 0))
      (request-postlude conn header app-status :fcgi-request-complete))
    ([err f]
     (if (= err "Broken pipe")
       (log/write "Webserver unexpectedly closed connection")
       (log/write "Route result failed: %s" err)))))

(defn route-mgr
  "Initiate route scripts at listener request via chan. Results are returned
   directly to the webserver via conn."
  [conn chan entry-points route-param max-threads peg-grammar]
  (var nthreads 0)
  (var quit false)

  (forever
   (when-let [msg (ev/take chan)]
     (cond
       (= (msg 0) :task)
       (let [[type header content] msg]
         (if (= nthreads max-threads)
           (do
             (put header :type :fcgi-end-request)
             (request-postlude conn header 0 :fcgi-overloaded)
             (log/write
              (string/format "Max threads exceeded; request rejected")))
           (do
             (when (invoke-request-handler conn header content entry-points
                                                route-param chan peg-grammar)
               (set nthreads (inc nthreads))))))

       (or (= (msg 0) :ok) (= (msg 0) :err))
       (do
         (set nthreads (dec nthreads))
         (route-result conn msg)
         (when (and quit (= nthreads 0))
           (log/write "Connection closed at webserver request" 2)
           (:close conn)
           (break)))

       (= (msg 0) :quit)
       (do
         (if (> nthreads 0)
           (set quit true) # delay exit until threads complete
           (do
             (:close chan)
             (break)))))))

  (log/write "Route-Mgr terminated" 10))

(defn listener
  "Read messages from webserver and react as required."
  [conn chan max-threads]
  (try
    (forever
     (let [[header content] (fcgi/read-msg conn)]
       (log/write (string/format "Received: %p" (header :type)) 5)
       (cond
         (or (= header :closed) (= header :reset))
         (do
           (log/write "Connection closed or reset" 2)
           (when conn
             (:close conn))
           (ev/give chan [:quit]))

         (= (header :type) :fcgi-begin-request)
         (log/write (string/format "Begin request: %p\n%p"
                                   header content) 3)

         (= (header :type) :fcgi-get-values)
         (handle-values conn header content max-threads)

         (or (= (header :type) :fcgi-params)
             (= (header :type) :fcgi-stdin))
         (when (and (content :params-complete)
                    (content :stdin-complete))
           (ev/give chan [:task header content])
           (when (not (content :fcgi-keep-conn))
             (ev/give chan [:quit])
             (break)))

         (= (header :type) :fcgi-abort-request)
         (let [keep-conn ((fcgi/requests (header :request-id)) :fcgi-keep-conn)]
           (handle-abort-request conn header)
           (when (not keep-conn)
             (ev/give chan [:quit])
             (break)))

         (= (header :type) :fcgi-null-request-id)
         (do
           (log/write "Terminated by client" 0)
           (ev/give chan [:quit])
           (ev/sleep 1)
           (os/exit 0)))))
    ([err f]
     (when (not= err "stream is closed")
       (log/write (string/format "Listener exit: %p" err))
       (ev/give chan [:quit])
       (when (and (or (= err "Broken pipe") (= err "stream hup")) conn)
         (:close conn)))))
  (log/write "Listener terminated" 10))

(defn handler
  "Handle comms with the webserver. Runs route-mgr in a new fiber to
   initiate route scripts and return results. Calls listerner to receive
   webserver messages and action them."
  [conn chan config entry-points peg-grammar]
  (log/write (string/format "Handler running with conn: %p" conn) 10)
  (ev/call route-mgr conn chan entry-points (config :route-param)
           (config :max-threads) peg-grammar)
  (listener conn chan (config :max-threads))
  (log/write "Handler exit" 10))

(defn handle-term-signal
  [chan]
  (log/write "Terminated by TERM signal")
  (ev/give chan [:quit])
  (ev/sleep 1)
  (os/exit 0))

(defn handle-hup-signal
  [chan routes]
  (log/write "Reloading routes on HUP")
  (set *entry-points* (load-routes routes)))

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
    (log/write (string/format "Configuration file: %s" (config :origin)))
    (log/write (string/format "Log level: %d" (config :log-level)))
    (log/write (string/format "Maximum concurrent requests: %d"
                              (config :max-threads)))
    (when (config :chroot)
      (log/write (string/format "Chroot to: %s" (config :chroot))))
    (when (os/stat (config :socket-file))
      (os/rm (config :socket-file)))

    (let [fcgi-server (net/listen :unix (config :socket-file))
          rm-chan (ev/thread-chan (config :max-threads))]
      (when (config :user)
        (osx/chown (config :socket-file) (config :user))
        (osx/setuid (config :user))
        (log/write (string/format "Effective user: %s" (config :user))))
      (os/sigaction :term |(handle-term-signal rm-chan) true)
      (os/sigaction :hup
         |(handle-hup-signal rm-chan (config :routes))
         true)
      (set *entry-points* (load-routes (config :routes)))
      (forever
       (log/write "Awaiting connection ..." 5)
       (let [conn (net/accept fcgi-server)]
         (log/write (string/format "Client connected on stream: %p" conn) 5)
         # dynamic vars such as *peg-grammar* are not passed to other fibers,
         # so pass explicitly
         (ev/call handler conn rm-chan config *entry-points*
                  (dyn :peg-grammar)))))))
