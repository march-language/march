(lang dune 3.0)
(using menhir 2.1)
(name march)
(version 0.1.0)

(generate_opam_files true)

(source (github march-lang/march))
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
  (menhir (>= 20230608))
  (ppx_deriving (>= 6.0))
  (alcotest (>= 1.7.0))))
