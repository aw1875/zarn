.PHONY: install

install:
	zig build
	cp -f zig-out/bin/zarn /usr/bin
