# FCGI - Utility routines

(def header-proto @{:version 1 :type :fcgi-null-request-id
                    :request-id 0 :content-length 0
                    :padding-length 0})

(def types [:fcgi-null-request-id :fcgi-begin-request
              :fcgi-abort-request :fcgi-end-request :fcgi-params
              :fcgi-stdin :fcgi-stdout :fcgi-stderr :fcgi-data
              :fcgi-get-values :fcgi-get-values-result
              :fcgi-unknown-type])

(def roles [:unused :fcgi-responder :fcgi-authorizer :fcgi-filter])

(def status [:fcgi-request-complete :fcgi-cant-mpx-conn
               :fcgi-overloaded :fcgi-unknown-role])

(def requests (array/new 256))

(defn mk-header
  [& kvs]
  (if kvs
    (let [t (table ;kvs)]
      (table/setproto t header-proto))
    (table/setproto @{} header-proto)))

(defn index
  [arr val]
  (find-index |(= $ val) arr))

(defn begin-request
  [header req]
  (let [req-id (header :request-id)]
    (put requests req-id @{:params @{} :stdin @""
                           :params-complete false :stdin-complete false
                           :fcgi-keep-conn (req :fcgi-keep-conn)})
    [header (requests req-id)]))

(defn close-request
  [req-id]
  (put requests req-id nil))

(defn add-request-params
  [header content]
  (let [req-id (header :request-id)]
    (if (requests req-id)
      (let [val (get requests req-id)]
        (if (= (length content) 0)
          (put val :params-complete true)
          (put val :params (merge (val :params) content)))
        [header val])
      [:invalid-reqid nil])))

(defn add-request-stdin
  [header content]
  (let [req-id (header :request-id)]
    (if (requests req-id)
      (let [val (get requests req-id)]
        (if (= (length content) 0)
          (put val :stdin-complete true)
          (buffer/push-string (val :stdin) content))
        [header val])
    [:invalid-reqid nil])))

(defn encode-type
  [type]
  (find-index |(= $ type) types))

(defn decode-type
  [n]
  (get types n))

(defn encode-bytes
  [n]
  (let [b0 (band n 0xff)
        b1 (brshift n 8)]
    [b1 b0]))

(defn decode-bytes
  [b1 b0]
  (bor (blshift b1 8) b0))

(defn encode-int4
  [n]
  (let [b (buffer/new 4)]
    (put b 3 (band n 0xff))
    (put b 2 (band (brshift n 8) 0xff))
    (put b 1 (band (brshift n 16) 0xff))
    (put b 0 (band (brshift n 24) 0xff))
    b))

(defn encode-int
  [n]
  (if (< n 127)
    n
    (let [b (buffer/new 4)]
      (put b 3 (band n 0xff))
      (put b 2 (band (brshift n 8) 0xff))
      (put b 1 (band (brshift n 16) 0xff))
      (put b 0 (bor (band (brshift n 24) 0xff) 0x80))
      b)))

(defn decode-int
  "From 4 byte buffer"
  [b]
  (let [[b3 b2 b1 b0] b]
    (bor (blshift (band 0x7F b3) 24) (blshift b2 16) (blshift b1 8) b0)))


(defn encode-param
  [name val]
  (let [name-len (length name)
        val-len (length val)
        data (buffer/new 256)]
    (buffer/push data (encode-int name-len))
    (buffer/push data (encode-int val-len))
    (buffer/push data name)
    (buffer/push data val)
    data))

(defn encode-header
  [fh]
  (let [header (buffer/new 8)
        req-id (encode-bytes (fh :request-id))
        con-len (encode-bytes (fh :content-length))]
    (put header 0 (fh :version))
    (put header 1 (encode-type (fh :type)))
    (put header 2 (get req-id 0))
    (put header 3 (get req-id 1))
    (put header 4 (get con-len 0))
    (put header 5 (get con-len 1))
    (put header 6 (fh :padding-length))
    (put header 7 0)
    header))

(defn decode-header
  [header]
  (let [fh (table/setproto @{} header-proto)]
    (put fh :version (get header 0))
    (put fh :type (decode-type (get header 1)))
    (put fh :request-id (decode-bytes (get header 2) (get header 3)))
    (put fh :content-length (decode-bytes (get header 4) (get header 5)))
    (put fh :padding-length (get header 6))
    fh))

(defn encode-params
  [dict]
  (if (= (length dict) 0)
    ""
  (let [data (buffer/new 256)]
    (loop [key :keys dict]
      (buffer/push data (encode-param key (dict key))))
    data)))

# TBD 4 byte lengths
(defn decode-params
  [data]
  (let [dict @{}
        data-len (length data)]
    (var i 0)
    (while (< i data-len)
      (let [name-len (get data i)
            val-len (get data (+ i 1))]
      (if (and (< name-len 127) (< val-len 127))
        (do
          (set i (+ i 2))
          (def name (string (buffer/slice data i (+ i name-len))))
          (set i (+ i name-len))
          (def val (string (buffer/slice data i (+ i val-len))))
          (set i (+ i val-len))
          (put dict name val)))))
    dict))

(defn decode-request
  [content]
  (let [role (decode-bytes (content 0) (content 1))]
    @{:role (roles role) :fcgi-keep-conn (= (content 2) 1)}))

(defn encode-request
  [request]
  (let [req (buffer/new-filled 8)
        role (encode-bytes (index roles (request :role)))]
    (put req 0 (role 0))
    (put req 1 (role 1))
    (put req 2 (if (request :fcgi-keep-conn) 1 0))
    req))

(defn decode-end-request
  [content]
  (let [dict @{}
        app-status (decode-int (buffer/slice content 0 4))
        protocol-status (status (get content 4))]
    @{:app-status app-status :protocol-status protocol-status}))

(defn encode-end-request
  [end-request]
  (let [end-req (buffer/new-filled 8)]
    (buffer/push-at end-req 0 (encode-int4 (end-request :app-status)))
    (put end-req 4 (index status (end-request :protocol-status)))
    end-req))

(defn read-msg
  [conn]
  "Read header and content from conn. Returns decoded."
  (try
    (if-let [hbuf (:read conn 8)]
      (let [header (decode-header hbuf)
            content (if (= (header :content-length) 0)
                      "" (:read conn (header :content-length)))
            padding (if (= (header :padding-length) 0)
                      ""
                      (:read conn (header :padding-length)))]
        (case (header :type)
          :fcgi-get-values
           [header (decode-params content)]
           :fcgi-get-values-result
           [header (decode-params content)]
           :fcgi-begin-request
           (begin-request header (decode-request content))
           :fcgi-params
           (add-request-params header (decode-params content))
           :fcgi-stdin
           (add-request-stdin header content)
           :fcgi-end-request
           [header (decode-end-request content)]
           [header content]))
      [:closed nil])
    ([err f]
     [:reset nil])))

(defn write-msg
  "Encodes header and content; writes to conn."
  [conn header content]
  (var payload content)
  (case (header :type)
    :fcgi-get-values
     (set payload (encode-params content))
     :fcgi-get-values-result
     (set payload (encode-params content))
     :fcgi-begin-request
     (set payload (encode-request content))
     :fcgi-params
     (set payload (encode-params content))
     :fcgi-end-request
     (set payload (encode-end-request content)))

   (let [content-len (length payload)
         pad-len (- 8 (mod content-len 8))
         padding (buffer/new-filled pad-len)]
     (put header :content-length content-len)
     (if (= pad-len 8)
       (put header :padding-length 0)
       (put header :padding-length pad-len))
     (:write conn (encode-header header))
     (when (not (= content-len 0)) (:write conn payload))
     (when (not (= pad-len 8))
       (:write conn padding))))
