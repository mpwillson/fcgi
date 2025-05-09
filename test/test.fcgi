# FCGI route handler for testing

(defn fcgi-main
  [params stdin]
  (string/format "Content-Type: text/html\n\n<p>HTML RESPONSE: %p</p>" params))
