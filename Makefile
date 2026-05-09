PREFIX ?= $(HOME)/.local
ZIG ?= zig
BIN ?= zig-out/bin/zmx

.PHONY: build install

build:
	$(ZIG) build -Doptimize=ReleaseSafe

install:
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/zmx
