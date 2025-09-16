# FCGI client - acts as webserver

(import fcgi-lib :as fcgi)

(def fcgi-vars {"FCGI_MAX_CONNS" "1" "FCGI_MAX_REQS" "2" "FCGI_MPXS_CONNS" "1"})
(def request {:role :fcgi-responder :fcgi-keep-conn true})
(def get-vals-result [@{:content-length 51  :padding-length 5  :request-id 0
                        :type :fcgi-get-values-result :version 1}
                      @{"FCGI_MAX_CONNS" "1" "FCGI_MAX_REQS" "2"
                        "FCGI_MPXS_CONNS" "1"}])
(def good-page "Received: Content-Type: text/html\n\n<p>HTML RESPONSE: @{\"DOCUMENT_URI\" \"/fcgi/test\"\n  \"FCGI_MAX_CONNS\" \"1\"\n  \"FCGI_MAX_REQS\" \"2\"\n  \"FCGI_MPXS_CONNS\" \"1\"}</p>")
(def end-request "End Request: @{:app-status 0 :protocol-status :fcgi-request-complete}")
(def bad-end-request "End Request: @{:app-status 404 :protocol-status :fcgi-request-complete}")
(def  bad-route "Received: Content-type: text/html\n\n<p>FCGI Server error: unknown route: /fcgi/list</p>")
(def overload "End Request: @{:app-status 0 :protocol-status :fcgi-overloaded}")

(defn fcgi-receive
  "Read message from fcgi server."
  [conn]
  (try
     (let [[header content] (fcgi/read-msg conn 10)]
       (if (table? header)
         (case (header :type)
           :fcgi-get-values-result
            [header content]
            :fcgi-stdout
            (string/format "Received: %s" content)
            :fcgi-end-request
            (string/format "End Request: %p" content)
            :else
            (string/format "Unhandled type: %p" (header :type)))
         (string/format "fcgi-receiver: got %p from fcgi/read-msg" header)))
     ([err f]
      (string/format "fcgi-receive: error: %p" err))))

(defn url-request
  [conn id url]
  (let [fcgi-header (fcgi/mk-header :type :fcgi-begin-request)]
    (put fcgi-header :request-id id)
    (fcgi/write-msg conn fcgi-header request)
    (put fcgi-header :type :fcgi-params)
    (fcgi/write-msg conn fcgi-header fcgi-vars)
    (fcgi/write-msg conn fcgi-header {"DOCUMENT_URI" url})
    (fcgi/write-msg conn fcgi-header "")
    (put fcgi-header :type :fcgi-stdin)
    (fcgi/write-msg conn fcgi-header "")))

(defn main
  [& args]
  # clean up previous log
  (when (os/stat "fcgi.log")
    (os/rm "fcgi.log"))
  # start server and give time for socket to be created
  (os/shell "jpm -l janet fcgi-server.janet -c test/test.cfg &")
  (os/sleep 1)

  (let [fcgi-header (fcgi/mk-header :type :fcgi-get-values)]
    (with
     [conn (net/connect :unix "/tmp/fcgi.sock")]
     (put fcgi-header :type :fcgi-get-values)
     (fcgi/write-msg conn fcgi-header fcgi-vars)
     (let [result (fcgi-receive conn)]
       (pp result)
       (assert (deep= result get-vals-result)))

     # Good requests
     (url-request conn 1 "/fcgi/test")
     (url-request conn 2 "/fcgi/test")
     # overload
     (put fcgi-header :type :fcgi-begin-request)
     (put fcgi-header :request-id 3)
     (fcgi/write-msg conn fcgi-header request)
     (let [msg (fcgi-receive conn)]
       (pp msg)
       (assert (deep= msg overload)))
     (let [page (fcgi-receive conn)]
       (pp page)
       (assert (deep= page good-page)))
     (assert (deep= (fcgi-receive conn) end-request))
     (let [page (fcgi-receive conn)]
       (pp page)
       (assert (deep= page good-page)))
     (let [msg (fcgi-receive conn)]
       (pp msg)
       (assert (deep= msg end-request)))

     # Bad request
     (url-request conn 1 "/fcgi/list")
     (let [page (fcgi-receive conn)]
       (pp page)
       (assert (deep= page bad-route)))
     (let [msg (fcgi-receive conn)]
       (pp msg)
       (assert (deep= msg bad-end-request)))

     # abort request
     (put fcgi-header :type :fcgi-begin-request)
     (put fcgi-header :request-id 2)
     (fcgi/write-msg conn fcgi-header request)
     (put fcgi-header :type :fcgi-abort-request)
     (fcgi/write-msg conn fcgi-header "")
     (let [msg (fcgi-receive conn)]
       (pp msg)
       (assert (deep= msg end-request)))

     # terminate server
     (put fcgi-header :type :fcgi-null-request-id)
     (fcgi/write-msg conn fcgi-header "")
     (os/sleep 1))))
