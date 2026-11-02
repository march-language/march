(lang dune 3.7)
(using menhir 2.1)
(name march)
(version 0.6.0)

(generate_opam_files true)

(source (github march-language/march))
(license MIT)
(authors "March Contributors")
(maintainers "March Contributors")

(package
 (name march)
 (synopsis "The March programming language compiler")
 (description "A static functional programming language with algebraic effects, linear types, actors, and content-addressed code")
 (depends
  (ocaml (>= 5.3.0))
  (dune (>= 3.0))
  (dune-configurator (>= 3.0))
  (menhir (>= 20230608))
  (ppx_deriving (>= 6.0))
  (alcotest (>= 1.7.0))
  (qcheck-core (>= 0.91))
  (qcheck-alcotest (>= 0.91))
  (uutf (>= 1.0))   ; for vendor/notty
  ; < 6.5: 6.5.0 (2026-10-22) overflows the JS stack on a 20000-element
  ; List.map in the in-browser REPL (browser-repl smoke test); see
  ; specs/todos/2026-11-02-js-of-ocaml-6-5-browser-repl-stack-overflow.md.
  (js_of_ocaml (and (>= 5.0) (< 6.5))))
)

(package
 (name forge)
 (synopsis "The March package manager and build tool")
 (description "A build tool and package manager for the March programming language")
 (depends
  (ocaml (>= 5.3.0))
  (dune (>= 3.0))
  (cmdliner (>= 1.3.0))
  (alcotest (>= 1.7.0))
  (digestif (>= 1.0))
  (yojson (>= 2.0))
  (qcheck-core (and (>= 0.91) :with-test))
  (qcheck-alcotest (and (>= 0.91) :with-test))))

(package
 (name march-lsp)
 (synopsis "Language Server Protocol server for the March language")
 (description "An LSP server providing diagnostics, hover types, go-to-definition, completion, inlay hints, and March-specific features (interface navigation, actor analysis, linear type tracking) for the March programming language.")
 (depends
  (ocaml (>= 5.3.0))
  (dune (>= 3.0))
  (march (= :version))
  (linol (>= 0.10))
  (linol-lwt (>= 0.10))
  (lsp (>= 1.20.0))
  (lwt (>= 5.0))))
