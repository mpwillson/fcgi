# Configuration file for fcgi server

# Pathname of socket file
(def socket-file "/tmp/fcgi.sock")

# Use chroot?
(def chroot nil)

# Drop privileges?
(def user nil)

# PARAM to match for routing url
(def route-param "DOCUMENT_URI")

# Define routes
# fcgi scripts must provide a function 'fcgi-main' which accepts
# two arguments: params (table of params from the web server) and stdin
(def routes [{:url "/fcgi/test" :script "test.fcgi"}
             {:url "fcgi/list"
              :script "/share/mark/dev/janet-dev/src/list.janet"}
             {:url "/fcgi/fail" :script "no-such-file"}])

# Logging
(def log-file "fcgi.log")
(def log-level 0)
