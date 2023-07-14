# Configuration file for fcgi.janet

# NB For OpenBSD, socket file must exist when httpd starts
# Must be owned by user www
(def socket-file
  (case (os/which)
    :openbsd "/var/www/var/run/fcgi.sock"
    "/tmp/fcgi.sock"))

# PARAM to match for routing url
(def route-param "REQUEST_URI")

# fcgi scripts must provide an function 'fcgi-main' which accepts
# two arguments: params (table of params from the web server) and stdin
(def routes [{:url "/fcgi/test" :script "test.fcgi"}
             {:url "/fcgi/list" :script "/share/mark/dev/janet/src/list.janet"}
             {:url "/fcgi/fail" :script "no-such-file"}])
# Logging
(def log-file "fcgi.log")
(def log-level 0)
