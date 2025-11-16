# logging for fcgi

(var log-level 0)
(var lfh nil)

(defn timestamp
  []
  (let [date (os/date nil :local)]
    (string/format "[%d-%02d-%02d %02d:%02d:%02d]" (date :year) (+ 1 (date :month))
                   (+ 1 (date :month-day)) (date :hours) (date :minutes)
                   (date :seconds))))

(defn write
  [msg &opt level]
  (default level 0)
  (when (<= level log-level)
    (if lfh
      (do
        (file/write lfh (string/format "%s %s\n" (timestamp) msg))
        (file/flush lfh))
      (file/write stderr (string/format "%s %s\n" (timestamp) msg)))))

(defn init
  [log-file level]
  (set lfh (file/open log-file :a+))
  (set log-level level)
  (when (not lfh)
    (file/write stderr (string/format "fcgi: cannot open log-file: %s\n"
                                      log-file)))
  lfh)

(defn close
  []
  (when lfh
    (file/close lfh)
    (set lfh nil)))
