# Configuration file for fcgi server
# OpenBSD on chrome

# Pathname of socket file
(def socket-file "/run/fcgi.sock")

# Use chroot?
(def chroot "/var/www")

# Drop privileges?
(def user "www")

# PARAM to match for routing url
(def route-param "DOCUMENT_URI")

# Define routes
# fcgi scripts must provide a function 'fcgi-main' which accepts
# two arguments: params (table of params from the web server) and stdin
(def routes [{:url "/fcgi/test" :script "test.fcgi"}
             {:url "/fcgi/list" :script "/hydrus/fcgi/list.janet"}
             {:url "/fcgi/fail" :script "no-such-file"}])

# Logging
(def log-file "/logs/fcgi.log")
(def log-level 3)
