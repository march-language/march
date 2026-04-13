PREFIX := $(shell ocamlfind printconf destdir 2>/dev/null | sed 's|/lib$$||')
ifeq ($(PREFIX),)
  PREFIX := $(HOME)/.opam/march
endif

.PHONY: build install test clean

build:
	dune build

install: build
	dune install --prefix $(PREFIX)

test:
	dune runtest

clean:
	dune clean
