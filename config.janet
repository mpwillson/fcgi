# Configuration file for fcgi.janet

# Pathname of socket file
(def socket-file
  (case (os/which)
    :openbsd
     "/run/fcgi.sock"
     "/tmp/fcgi.sock"))

# Use chroot?
(def chroot
  (case (os/which)
    :openbsd
     "/var/www"
     nil))

# Drop privileges?
(def user
  (case (os/which)
    :openbsd
     "www"
     nil))

# PARAM to match for routing url
(def route-param "REQUEST_URI")

# Define routes
# fcgi scripts must provide a function 'fcgi-main' which accepts
# two arguments: params (table of params from the web server) and stdin
(def routes [{:url "/fcgi/test" :script "test.fcgi"}
             {:url "/fcgi/fail" :script "no-such-file"}])

# Logging
(def log-file
  (case (os/which)
    :openbsd
     "/logs/fcgi.log"
     "fcgi.log"))
(def log-level 0)
