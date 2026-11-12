`[P1]` The typechecker treats two types of one SHORT name as one type: `A.Tq` and `B.Tq` (or a user
type and a built-in, `type DownReason`, `type Option`) unify, so a value of one is accepted where
the other is expected. A type-system soundness hole: a `match` on a `B.Tq` value may list `A.Tq`'s
constructors, and a function of `A.T` accepts a `B.T`.

Found by the round-2 soundness review of the refinement checker's constructor registry
(`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`). Probes (round-2 review
scratch area `ctor-review2/`):

- `q1.march`: `mod A do type T = KA(Int) | ZA ... fn g(x : T) end`, `mod B do type T = KB | ZB end`;
  `A.g(B.ZB)` and `A.g(B.mk())` typecheck and run.
- `c2diff.march`: the same program with B's type renamed `Tb` is rejected (`expected Tb but got
  Tq`), so it is the shared short name, not structural typing, that admits it.

Cause (as read): a constructor's `ci_type` and a type's `TCon` name are the BARE type name
(`Typecheck` registers `ci_type = name.txt`), so two declarations of one short name are one nominal
type to unification.

The refinement checker now works around it (every datatype whose short name two declarants share,
the typechecker's built-in types included, resolves no constructor), at the cost of proofs over
such types (`module-qualified-measure-and-sort`). Fixing the typechecker (qualified nominal types)
would let that rule be relaxed.

**The same conflation reaches the backend** (round-4 review, probe `ctor-review4/ct3.march`): a
user `type CancelToken = Tok(Int)` is merged with the typechecker's built-in `CancelToken` (named
only in builtin signatures such as `task_cancel_token_new`), so
`match Some(task_cancel_token_new()) do Some(Tok(_)) -> …` typechecks; interpreted it reaches the
wrong arm, and `--compile` emits invalid LLVM (`march: clang failed (exit 1)`). A user type named
like any type the base environment produces (`Typecheck_builtins.builtin_type_names`) should be
rejected or kept distinct by the typechecker.

## 2026-11-09: nested-module collisions fixed; built-in and stdlib collisions still open

Two variant types of one short name declared in two modules of the checked program
(`A.T` / `B.T`, the `q1.march` probe) now have their own identities
(`lib/typecheck/typecheck_nominal.ml`;
`specs/progress/2026-10-13-same-short-name-nested-types-unify.md`). What remains open here:

- a user type named like a type the base environment produces (`type CancelToken`,
  `type DownReason`, `type Option`; `Typecheck_builtins.builtin_type_names`), and
- a user type named like a stdlib type.

Stdlib declarations are excluded from the collision count on purpose: they reach a check
through the cached stdlib env, whose signatures are bare, which is what sank the archived
"cut (b)" (`specs/plans/archive/2026-07-17-fqn-type-ctor-identity.md`). The mechanism extends
by counting those names as declared at a pseudo path and giving a colliding entry-level user
type a non-bare identity (e.g. `Main.CancelToken`). Before doing that, audit the tests and
examples that declare a type with a built-in name on purpose (they rely on the conflation
today), and decide whether rejecting such a declaration is the better answer.

The refinement checker's skip rule (every datatype whose short name two declarants share
resolves no constructor) can be relaxed for nested-module pairs now.

## 2026-11-10: the function-name half is fixed; this type half needs its own mechanism

The two sibling todos (a user `fn show` vs the `Show` method, an entry `mod List` vs the stdlib
`List`) were one TIR symbol for two definitions, and lowering now names the user's definition
distinctly (`specs/progress/2026-11-10-user-stdlib-name-collisions.md`). That does not reach this
item: a type's identity is decided by the typechecker (unification on the bare `TCon` name), before
lowering, so a user `type CancelToken` is already the built-in one by the time TIR names anything.
The fix is still the one sketched above (count built-in and stdlib type names as declared at a
pseudo path in `Typecheck_nominal` and give a colliding entry-level user type a non-bare identity,
or reject the declaration), after auditing the tests and examples that rely on the conflation.

## 2026-11-11: fixed. A user variant named like a built-in or stdlib type has its own identity

### Audit

A temporary diagnostic (an entry-level type whose name is in
`Typecheck_builtins.builtin_type_names` or is a stdlib type's name), run over `test/`,
`examples/`, `specs/lang/`, `bench/`, `forge/`, `lsp/test/` and `docs/`, the `.ml` test sources
and `.md` snippets included: 635 declarations of 58 distinct names.

- Almost all are a coincidence with a stdlib type the program never touches: `Client` and
  `Server` (102 each, the `@[endpoints]` role types), `Tree` (83, `OrderedMap`'s), `Color` (74,
  `Plot`'s record), `T` (43), `Config`, `State`, `Ops`, `Conn`, `Handle`.
- A built-in name on purpose, to test the collision or the reservation: `Down` / `DownReason`
  (14), `Process` / `Socket` / `Dir` / `Handle` (the ocap handle names), `CancelToken`,
  `TimerRef`, `CsvRow`, `Tagged`, `Node`, `Map`, `Matrix`.
- A prelude type redeclared: `Result` 5 programs, `Option` 2, `List` 1 (test sources), plus the
  reference's own `type Option(a) = None | Some(a)` snippets. Each uses only its own
  declaration; none passes its value to a prelude function or the reverse.

So no program relied on the conflation, and the choice was an identity of its own, as #1235
made for nested modules. The one rejection stays the one #1222 added: a top-level `Down` /
`DownReason`, which the monitor ABI hard-codes.

### The fix

`Typecheck_nominal.compute` takes a `base` predicate: the short names of the base environment's
types (`Typecheck_builtins.is_base_type_short_name`, derived from `builtin_type_names`) and of
the variant types the seed env (the cached stdlib) declares; a stdlib variant declared in the
checked module itself counts too. A user VARIANT with such a name always gets an identity,
entry-qualified at the top level (`Main.CancelToken`), as the reserved handle names already
did. The base type keeps the bare name, which is what builtin signatures and the cached stdlib
env spell. A bare name written in a user file means the user's declaration (the existing
lexical rule); a reference written in a stdlib file never resolves to a user declaration.

A NESTED user variant gets its identity only when the stdlib's declarations can be told from
the user's (the stdlib came from the cached env, or its spans are marked): the stdlib itself
declares types the base environment names (`Bytes` in `mod Bytes`, `CsvRow` in `mod Csv`), and
a check that carries those unmarked (the OCaml test harness, the browser build) must leave
them bare. A top-level declaration is never the stdlib's.

What had to follow, each found by a suite that went red:

- **Messages.** An entry-level identity prints as its short name
  (`Typecheck_nominal.display`), so a program with a `type Color` reads as before. A mismatch
  whose two sides would print alike is printed in full (`qualify_if_alike`):
  ``expected `CancelToken` but got `Main.CancelToken` ``.
- **The ambiguous-constructor hint** counts a user type and its base namesake once
  (`all_ctors_named`), as when they were one `ci_type`.
- **Module exports.** A module exported every constructor whose `ci_type` was one of its public
  type NAMES, so `mod UserValues do type Down = Down(Int) end` exported the built-in `Down`
  (3 arguments) as `UserValues.Down`. It now exports the constructors of its own identity.
- **Exhaustiveness.** A constructor's argument types are read from the scrutinee type's own
  constructor (`ctor_arg_tys ~of_type`) and a declared argument type by its identity
  (`inst_ty`), so a nested pattern over a recursive user `Tree` enumerates the user's
  constructors, not `OrderedMap`'s.
- **The refinement checker** files a datatype under its short name and module path, so an
  entry-level identity is read there by its short name (`Typecheck_nominal.refine_name`, at the
  seven places a typechecker type's name is looked up). Proofs over a user `Tree` beside
  `OrderedMap`'s are as before.

Backends are unchanged: `Lower_types.convert_ty` maps an identity to its short name.

### Tests

`specs/lang/types/reject/t460` (the `CancelToken` probe: now
``expected `CancelToken` but got `Main.CancelToken` ``), `t461` (a user `Level` passed to
`Logger.set_module_level`), `t462` (a prelude `Option` passed where the program's own `Option`
is expected), `accept/t463` and golden `g49` (user `CancelToken`, `Option`, `Result`, `Level`
beside the base types, both backends).

### Not done

- **The refinement checker's skip rule is not relaxed.** It still resolves no constructor for a
  datatype whose short name two declarants share. Relaxing it needs that checker to resolve
  every type reference the way the typechecker now does, on both its typechecker-type and its
  AST-name paths; reading an identity by its short name (above) keeps today's answers and today's
  rule. Filed: `specs/todos/2026-11-11-refine-relax-conflated-short-name-rule.md`.
- **REPL.** A fragment is checked one declaration at a time (`check_decl`), without
  `Typecheck_nominal.compute`, so a type declared at the prompt is still its bare name.
- **Two stdlib types of one short name** (`Value` in `Config`, `Msgpack`, `DataFrame`) are still
  one type; so are records, which unify structurally.
- **Backends key a type by its short name.** A user type that shares a prelude type's name AND
  needs name-keyed machinery there is not covered: `type Result = Won(Int) | Lost` with
  `derive Show for Result` fails to compile (`ambiguous interface-method call to show`). Filed:
  `specs/todos/2026-11-11-compiled-derive-on-user-type-named-like-prelude-type.md`.

### Fallout found in CI (fixed in the same PR)

- **`transitions` blocks.** A user `Handle` (the short name of `File.Handle`) is now
  `<Entry>.Handle`, and the via-function check compared the written short name with the
  function's types by string, rejecting `specs/lang/grammar/parse/p21`. It now also accepts the
  resolved identity.
- **Host-scope check through an impl method (`lib/tir/net_scope.ml`).** A nested impl for a type
  whose short name collides (`B.T`, mangled `Fetch$B.T.fetch`) is called through the bare
  dispatch name `Fetch.fetch`, which has no TIR definition; net_scope read that as an unknown
  leaf and the impl's network use went unchecked (`cap_net_scope` "impl method name not leaked"
  compiled instead of being rejected). It now reads such a call as a call to each impl of the
  method. Any colliding nested type hit this before the change too; the change made `T` collide.
- **`test/stdlib/test_file.march`** redeclared `File`'s private `FileStat`/`FileKind` and relied
  on the conflation; it now matches `File.FileStat` / `File.RegularFile`.
- Not CI-run, and failing `march test` on main already: `test_http_server` and `test_seq` mirror
  `HttpServer.Conn` and `Seq`'s private `Step` the same way and now report a type mismatch
  instead of their earlier `cap_ceiling` error; `test_config` fails identically on main.
