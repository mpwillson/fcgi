(declare-project
    :name "fcgi-server"
    :description "FCGI server for Janet scripts")


(declare-binscript
    :main "fcgi-server.janet")

(declare-source
    :source ["fcgi-lib.janet" "log.janet" "util.janet"])
