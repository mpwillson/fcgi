# Makefile for fcgi-server.janet installation

PREFIX 	:= /usr/local
ETC 	:= ${PREFIX}/etc
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
	jpm install

uninstall:
	echo "removing ${ETC}/${CFG}"
	rm -f ${ETC}/${CFG}
	jpm uninstall
