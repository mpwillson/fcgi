(import fcgi-lib :as f)

(each type f/types
  (assert (f/decode-type (f/encode-type type)) type))

(loop [n :range [0 (dec (math/pow 2 16))]]
  (assert (f/decode-bytes ;(f/encode-bytes n)) n))

(let [rng (math/rng)]
  (for i 0 200000
    (let [n (math/rng-int rng)]
    (assert (f/decode-int (f/encode-int4 n)) n))))

(assert (f/decode-header (f/encode-header f/header-proto)) f/header-proto)

(let [dict @{"x" "0" "a" "1" "junk" "longer string"}]
  (assert (f/decode-params (f/encode-params dict)) dict))

(let [fcgi-header (f/mk-header :type :fcgi-get-values)
      request {:role :fcgi-responder :fcgi-keep-conn true}]
  (assert (f/decode-header (f/encode-header fcgi-header)) fcgi-header)
  (assert (f/decode-request (f/encode-request request)) request))

#(os/shell "jpm -l janet fcgi-server.janet -c test/test.cfg &")
