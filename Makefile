# Kunloria — development tasks
#
# The toolchain lives in ~/.moon/bin; run `make` targets from the repo root.

MOON ?= $(HOME)/.moon/bin/moon
IMAGE ?= ghcr.io/chnlkw/kunloria:0.1.0

.PHONY: help check test fmt build run clean prove docker-build

help:
	@echo "make check        type-check every package"
	@echo "make test         run the full test suite"
	@echo "make fmt          format sources"
	@echo "make info         regenerate .mbti interfaces"
	@echo "make build        build the native binary (release)"
	@echo "make run          run the server locally on :8080"
	@echo "make prove        formally verify the proof/ package (needs why3 + z3)"
	@echo "make docker-build build the container image"

check:
	$(MOON) check

test:
	$(MOON) test

fmt:
	$(MOON) fmt && $(MOON) info

info:
	$(MOON) info

build:
	$(MOON) build --release --target native cmd/main
	@echo "binary: _build/native/release/build/cmd/main/main.exe"

run:
	$(MOON) run cmd/main

clean:
	$(MOON) clean

# moon prove requires the Why3 verification toolchain (why3 1.7.x) and at
# least one SMT solver (z3 / cvc5 / alt-ergo); see docs/verification.md.
prove:
	@command -v why3 >/dev/null 2>&1 || { \
	  echo "why3 not found — install it (opam install why3=1.7.2) plus a solver (z3)"; exit 1; }
	$(MOON) prove proof

docker-build:
	docker build -t $(IMAGE) .
