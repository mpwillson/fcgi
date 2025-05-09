# Utilty functions

(defn argparse
  `Parses an array of string args, accepting options defined in flags.
   Options are represented by  one character, preceeded by a -. The end of
   options may be indicated by -- (if following arg(s) are prefixed with -).
   Flags is a string of recognised single character options. If an option
   must take a value, the option letter should be followed by a :.

   argparse returns a table containing options as keys (keywords) with
   associated values. If an invalid option is encountered, the error message
   is assigned to the key :err. Arguments following the end of options are
   available through the key :args.

   Default values for options may be passed in the optional argument dict.`
  [args flags &opt dict]
  (default dict @{})
  (if (empty? args)
    dict
    (let [arg (args 0)]
      (if (string/has-prefix? "-" arg)
        (if (= (length arg) 2)
          (let [opt (string/slice arg 1)
                i (string/find opt flags)]
            (if i
              (let [ind (inc i)
                    val-ind (and (< ind (length flags))
                                 (= (string/slice flags ind (inc ind)) ":"))
                    missing-opt-arg (and val-ind (= (length args) 1))]
                (if missing-opt-arg
                  (put dict :err
                       (string/format "option -%s expects argument" opt))
                  (do
                    (put dict (keyword opt)
                         (if val-ind (args 1) true))
                    (argparse (tuple/slice args (if val-ind 2 1)) flags dict))))
              (if (= opt "-")
                (put dict :args (tuple/slice args 1))
                (put dict :err
                     (string/format "unrecognised option: -%s" opt)))))
          (put dict :err (string/format "malformed option: %s" arg)))
        (put dict :args args)))))

(defn die
  `Write fmt string with optional args on stderr and exit with non-zero status`
  [fmt & args]
  (eprintf fmt ;args)
  (os/exit 1))
