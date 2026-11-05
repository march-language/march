`[P3]` `--lemma-test` never decides a theorem that uses the logic's `len`: the interpreter has no
`len` binding, so the lemma reads `not-tested  the interpreter: unbound variable: len`.
Law strength binds one (`Lemma_test.len_builtin`, `~with_len:true`), but `--lemma-test` cannot
just turn it on: an interpreter-decided law then reaches the compiled harness, whose generated
source has no `len` either and fails to compile.

Done when `--lemma-test` decides `len` theorems in the interpreter and the compiled harness
compiles them (a `len` for lists and strings in the harness, or the theorem's `len` rewritten to
`List.length`/`String.length` by the argument's type).
