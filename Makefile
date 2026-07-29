PREFIX ?= $(HOME)/.local
ZIG ?= zig
BIN ?= zig-out/bin/zmx
# Optional host subset for `deploy`, e.g. `make deploy HOSTS=PRO`.
HOSTS ?=

.PHONY: build install deploy

build:
	$(ZIG) build -Doptimize=ReleaseSafe

install:
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/zmx

# Deploy the already-built binary to MINI, PRO, NHATRANG over ssh and verify the
# deployed version. Does NOT build — run `make build` first.
deploy:
	dart scripts/deploy.dart $(HOSTS)
