(defn some-fun
  []
  0)

(defn fcgi-entry-point
  [params stdin]
  (string/format "HTML RESPONSE: %p" params))
