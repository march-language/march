PREFIX := $(shell ocamlfind printconf destdir 2>/dev/null | sed 's|/lib$$||')
ifeq ($(PREFIX),)
  PREFIX := $(HOME)/.opam/march
endif

.PHONY: build install test clean

build:
	dune build

install: build
	dune install --prefix $(PREFIX)
	$(MAKE) install-runtime

# The native backend (`march --compile`) compiles and links the C runtime at
# build time, resolving it from `<exe>/../runtime/` — i.e. $(PREFIX)/runtime for
# the installed binary.  `dune install` only ships the stdlib (stdlib/dune's
# install stanza), so without this the installed compiler links a stale runtime
# and new runtime symbols (e.g. march_poly_eq) fail to link.  Keep it in sync.
.PHONY: install-runtime
install-runtime:
	mkdir -p $(PREFIX)/runtime
	cp -R runtime/. $(PREFIX)/runtime/

test:
	dune runtest

clean:
	dune clean
