# Makefile for fcgi-server.janet installation

PREFIX 	:= /usr/local
ETC 	:= ${PREFIX}/etc
RC      := /etc/rc.d
CFG 	:= fcgi-server.cfg

.PHONY:	install uninstall
.SILENT:

install:
	if [ ! -r ${ETC}/${CFG} ]; then \
		echo "copying ${CFG} to ${ETC}..."; \
		cp ${CFG} ${ETC}; \
	else \
		echo "Not overwriting existing ${ETC}/${CFG} file"; \
	fi
	cp rc.d/fcgi_server ${RC}
	jpm install
	echo "You'll need to add fcgi_server_flags=\"\" to /etc/rc.conf.local"
	echo "  and add fcgi_server to the pkg_scripts setting"

uninstall:
	echo "removing ${ETC}/${CFG}"
	rm -f ${ETC}/${CFG}
	rm -f ${RC}/fcgi_server
	jpm uninstall
