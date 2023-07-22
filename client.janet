# FCGI client - acts as webserver

(import /fcgi)

(def fcgi-vars {"FCGI_MAX_CONNS" "" "FCGI_MAX_REQS" "" "FCGI_MPXS_CONNS" ""})
(def request {:role :fcgi-responder :fcgi-keep-conn true})

(defn fcgi-receiver
  "Read messages from fcgi server. Run as a fiber."
  [conn]
  (try
    (prompt :quit
       (forever
        (let [[header content] (fcgi/read-msg conn)]
          (if (table? header)
            (case (header :type)
              :fcgi-get-values-result
               (let [resp-vars content]
                 (pp header)
                 (pp resp-vars))
               :fcgi-stdout
               (printf "Received: %s" content)
               :fcgi-end-request
               (printf "End Request: %p" content)
               (printf "Unhandled type: %p" (header :type)))
          (do
            (pp header)
            (return :quit))))))
    ([err f]
     (printf "fcgi-receiver: got %p")
     nil)))

(defn main
  [& args]
  (let [fcgi-header (fcgi/mk-header :type :fcgi-get-values)
        content fcgi-vars]
    (with [conn (net/connect :unix "/tmp/fcgi.sock")]
          (def fib (ev/go fcgi-receiver conn))
           (printf "Connected to %q!" conn)
           (put fcgi-header :type :fcgi-get-values)
           (fcgi/write-msg conn fcgi-header content)
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

           # abort request
           (put fcgi-header :type :fcgi-begin-request)
           (put fcgi-header :request-id 2)
           (fcgi/write-msg conn fcgi-header request)
           (put fcgi-header :type :fcgi-abort-request)
           (fcgi/write-msg conn fcgi-header "")

           (if (> (length args) 1)
             (do
               (put fcgi-header :type :fcgi-null-request-id)
               (fcgi/write-msg conn fcgi-header "")))
           (print "Sleeping before exit ...")
           (ev/sleep 1)
           (ev/cancel fib :quit))))
