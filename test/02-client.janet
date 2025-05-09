# FCGI client - acts as webserver

(import fcgi-lib :as fcgi)

(def fcgi-vars {"FCGI_MAX_CONNS" "" "FCGI_MAX_REQS" "" "FCGI_MPXS_CONNS" ""})
(def request {:role :fcgi-responder :fcgi-keep-conn true})

(defn fcgi-receive
  "Read message from fcgi server."
  [conn]
  (try
     (let [[header content] (fcgi/read-msg conn)]
       (if (table? header)
         (case (header :type)
           :fcgi-get-values-result
            [header content]
            :fcgi-stdout
            (string/format "Received: %s" content)
            :fcgi-end-request
            (string/format "End Request: %p" content)
            (string/format "Unhandled type: %p" (header :type)))
         (string/format "fcgi-receiver: got %p from fcgi/read-msg" header)))
     ([err f]
      (string/format "fcgi-receive: error: %p" err))))

(defn main
  [& args]

  # start server and give time for socket to be created
  (os/shell "jpm -l janet fcgi-server.janet -c test/test.cfg &")
  (os/sleep 1)

  (let [fcgi-header (fcgi/mk-header :type :fcgi-get-values)
        content fcgi-vars
        get-vals-result [@{:content-length 49  :padding-length 7  :request-id 0
                            :type :fcgi-get-values-result :version 1}
                          @{"FCGI_MAX_CONNS" "1" "FCGI_MAX_REQS" ""
                            "FCGI_MPXS_CONNS" ""}]
        good-page "Received: Content-Type: text/html\n\n<p>HTML RESPONSE: @{\"DOCUMENT_URI\" \"/fcgi/test\"\n  \"FCGI_MAX_CONNS\" \"\"\n  \"FCGI_MAX_REQS\" \"\"\n  \"FCGI_MPXS_CONNS\" \"\"}</p>"
        end-request "End Request: @{:app-status 0 :protocol-status :fcgi-request-complete}"
       bad-route "Received: Content-type: text/html\n\n<p>FCGI Server error: unknown route: /fcgi/list</p>"]
    (with
     [conn (net/connect :unix "/tmp/fcgi.sock")]
     (put fcgi-header :type :fcgi-get-values)
     (fcgi/write-msg conn fcgi-header content)
     (assert (deep= (fcgi-receive conn) get-vals-result))

     # Good request
     (put fcgi-header :type :fcgi-begin-request)
     (put fcgi-header :request-id 1)
     (fcgi/write-msg conn fcgi-header request)
     (put fcgi-header :type :fcgi-params)
     (fcgi/write-msg conn fcgi-header fcgi-vars)
     (fcgi/write-msg conn fcgi-header {"DOCUMENT_URI" "/fcgi/test"})
     (fcgi/write-msg conn fcgi-header "")
     (put fcgi-header :type :fcgi-stdin)
     (fcgi/write-msg conn fcgi-header "")
     (assert (deep=(fcgi-receive conn) good-page))

     # Bad request
     (put fcgi-header :type :fcgi-begin-request)
     (put fcgi-header :request-id 1)
     (fcgi/write-msg conn fcgi-header request)
     (put fcgi-header :type :fcgi-params)
     (fcgi/write-msg conn fcgi-header
                     {"DOCUMENT_URI" "/fcgi/list"
                      "DOCUMENT_ROOT" "/share/mark/www-src/hydrus/data/"
                      "QUERY_STRING" "target=/journal/"})
     (fcgi/write-msg conn fcgi-header "")
     (put fcgi-header :type :fcgi-stdin)
     (fcgi/write-msg conn fcgi-header "")
     (assert (deep= (fcgi-receive conn) end-request))

     # abort request
     (put fcgi-header :type :fcgi-begin-request)
     (put fcgi-header :request-id 2)
     (fcgi/write-msg conn fcgi-header request)
     (put fcgi-header :type :fcgi-abort-request)
     (fcgi/write-msg conn fcgi-header "")
#     (print (fcgi-receive conn))
     (assert (deep= (fcgi-receive conn) bad-route))

     # terminate server
     (put fcgi-header :type :fcgi-null-request-id)
     (fcgi/write-msg conn fcgi-header "")
     (os/sleep 1))))
