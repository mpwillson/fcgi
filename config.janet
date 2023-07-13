# Configuration file for fcgi.janet

# NB For OpenBSD, socket file must exist when httpd starts
# Must be owned by user www
(def socket-file "/tmp/sock")
# PARAM to match for routing url
(def route-param "TEST_THING")
(def routes [{:url "list" :script "f.janet"}])
# Logging
(def log-file "fcgi.log")
(def log-level 0)
