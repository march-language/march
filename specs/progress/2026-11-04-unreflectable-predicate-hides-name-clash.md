`[P3]` `unreflectable-predicate` doesn't say that a function or constructor name clashes with the stdlib

Found 2026-11-04 on `b86c86a63` (`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md`
§2 P2, gap G2). The sibling of todo `2026-11-03-reflect-type-name-clash-with-stdlib`, which
covers type names.

- A user `fn unwrap(id : Int, q : List(Env)) : Option(Int)` is not reflected:
  `--reflect-report` says `R6:calls unwrap, a name more than one declaration could denote`
  (stdlib `Option.unwrap`/`Result.unwrap`). A lemma whose theorem calls it is
  `skip unreflectable-predicate` and `lemma_unproved`, with no reason at the theorem.
- After renaming the function, a theorem that builds the user constructor `Reply(c, v)` is
  still `unreflectable-predicate`, because `Channel.HandleResult` declares `Reply`. Renaming
  it `RReply` proves the lemma.

Fix in two steps:
1. The skip's diagnostic names the R6 reason and the clashing declaration (as
   `specs/progress/2026-11-03-lemma-tooling-bugfixes.md` did for type names).
2. Resolve the user's own declaration when the call site's module declares it (the
   typechecker's current-module rule).

## Fixed (2026-11-04)

The cause was resolution, not the message: both user functions were reflected.

- **Functions.** The entry file's module is its top level, and the prelude's functions are
  registered there too, so the key `unwrap` had two declarations and the theorem's call was
  marked ambiguous. `Refine_term`'s lookup now prefers, for code in a non-stdlib file, the one
  declaration in that file when every other declaration of the key is the stdlib's (the
  typechecker's rule: `unwrap(Some(5))` in such a module is a type error). Stdlib code still
  sees the ambiguity.
- **Constructors.** A construction filling a reflected function's parameter whose datatype is
  known (and not a conflated short name) is that datatype's constructor
  (`Refine_scope.smt_of_r`'s reflected-call arm), so `tag(Reply(c, v))` proves with
  `Channel.HandleResult`'s `Reply` declared.

Types stay open: todo `2026-11-03-reflect-type-name-clash-with-stdlib`.

Tests: `reflect-lemma` `clash_fn`, `clash_fn_red`, `clash_ctor`, `clash_ctor_red`.
