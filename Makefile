# Kunloria — development tasks
#
# The toolchain lives in ~/.moon/bin; run `make` targets from the repo root.

MOON ?= $(HOME)/.moon/bin/moon
EXAMPLE ?= rgw-tenant
IMAGE ?= ghcr.io/chnlkw/kunloria-$(EXAMPLE):dev

.PHONY: help check test fmt build run prove examples clean docker-build

help:
	@echo "make check         type-check every package"
	@echo "make test          run the full test suite"
	@echo "make fmt           format sources + regenerate interfaces"
	@echo "make build         build the EXAMPLE binary (release)"
	@echo "make run           run the EXAMPLE server locally on :8080"
	@echo "make examples      build every example binary (debug)"
	@echo "make prove         formally verify the verdict package (needs why3 + z3)"
	@echo "make docker-build  build the EXAMPLE container image"
	@echo "variables: EXAMPLE=$(EXAMPLE) IMAGE=$(IMAGE)"

check:
	$(MOON) check

test:
	$(MOON) test

fmt:
	$(MOON) fmt && $(MOON) info

build:
	$(MOON) build --release --target native "examples/$(EXAMPLE)/main"
	@echo "binary: _build/native/release/build/examples/$(EXAMPLE)/main/main.exe"

run:
	$(MOON) run "examples/$(EXAMPLE)/main"

examples:
	$(MOON) build --target native examples/minimal/main
	$(MOON) build --target native examples/rgw-tenant/main
	$(MOON) build --target native examples/k8s-write-authz/main

clean:
	$(MOON) clean

# moon prove requires the Why3 verification toolchain (why3 1.7.x) and at
# least one SMT solver (z3 / cvc5 / alt-ergo); see docs/verification.md.
prove:
	@command -v why3 >/dev/null 2>&1 || { \
	  echo "why3 not found — install it (opam install why3=1.7.2) plus a solver (z3)"; exit 1; }
	$(MOON) prove verdict

docker-build:
	docker build --build-arg EXAMPLE=$(EXAMPLE) -t $(IMAGE) .
