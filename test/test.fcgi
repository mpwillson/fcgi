# FCGI route handler for testing

(defn fcgi-main
  [params stdin]
  (peg/compile '(+ :s)) #test peg patterns are defined
  (ev/sleep 2)
  (string/format "Content-Type: text/html\n\n<p>HTML RESPONSE: %p</p>" params))
