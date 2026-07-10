# Typing corpus index (t01–t68 accept, t01–t57 reject)

Navigable map of the Core March **static-semantics** conformance corpus: each
program in this directory (`specs/lang/types/accept/*.march`,
`specs/lang/types/reject/*.march`) to the typing rule(s) it anchors in
`specs/lang/core-march-types.md`. See that document's §3 for the full
per-program prose and §4 for the accumulated findings each `reject/` witness
sometimes doubles as evidence for.

**Note (`t27`–`t28`):** these two `accept/` programs anchor **operational**
(runtime method-DISPATCH) rules in `core-march.md` §4.4.2, not typing rules in
`core-march-types.md` — they ride this same `--check`-plus-run harness because
they are, first, ordinary well-typed programs (the `--check` half of the
corpus model still applies), and the harness has no separate "run and check
the printed value" lane of its own. Their expected VALUE (not just exit code)
is documented in their own table row below and re-verified by running them
interpreted, not only `--check`ing them.

**Note (`t29`–`t30`):** these anchor `core-march-types.md` §2.4 (`derive`/
`satisfy` as `DImpl` GENERATORS, a typing/desugar-time concern) — `t29` is
also a run-value witness for `core-march.md` §4.4.4 (derive-generated impls
dispatch through the identical rules as hand-written ones), same
dual-purpose pattern as `t27`–`t28` above.

**Note (`t32`–`t33`):** these anchor **operational** (module declaration,
nesting, and name-resolution) rules in `core-march.md` §4.7, widening slice 2
Task 2 — not typing rules in `core-march-types.md` (module VISIBILITY, the
`core-march-types.md` counterpart, is Task 3's subject and rides `reject/t25`
+ `accept/t31` instead, from Task 1). Same dual-purpose pattern as `t27`–`t28`:
ordinary well-typed programs for the `--check` half, with their expected
printed VALUE re-verified by running them interpreted.

**Note (`t34`–`t36`):** these anchor `core-march-types.md` §2.5 (widening
slice 2, Task 3) — module visibility as a TYPING concept: the opaque-type
asymmetry (`t34`, a second independent witness after Task 1's `t31`), the
no-per-module-type-namespace design point (`t35`), and the A10
qualified-record re-verification (`t36`). Same dual-purpose pattern as
`t27`–`t28`: ordinary well-typed `--check` programs, each also run
interpreted to confirm its printed value.

**Note (`t37`–`t38`, `reject/t27`):** these anchor **operational**
(`core-march.md` §4.7.1, widening slice 2 Task 4) `use`/`import`/`alias`
selector rules and the file-based resolver pre-pass (`lib/resolver/
resolver.ml`) — not typing rules in `core-march-types.md`, though
`core-march-types.md` §2.5 gained a short cross-reference paragraph noting
that `reject/t27`'s selective-`use`-of-a-private-name rejection is the same
`pub_set` gate `reject/t26` exercises, one syntactic layer up. Same
dual-purpose pattern as `t27`(types)–`t28`(types) above: `t37`/`t38` are
ordinary well-typed `--check` programs, each also run interpreted to confirm
its printed value; `reject/t27` follows the usual pinned-substring reject
convention.

**Note (`accept/t45`–`t48`, `reject/t36`–`t38`):** Capabilities widening,
Task 1 (2026-07-07) — the first `core-march-types.md` §2.8 material: the IO
capability hierarchy (18 entries, `lib/caps/cap_lattice.ml:15-34`),
`cap_subsumes`/`normalize`, the `needs` manifest, and **Check 1**
(`typecheck.ml:5561`) — every `Cap(X)` in a function/actor/extern SIGNATURE
must be covered by a declared `needs` via subsumption, else ERROR. Also files
a live finding: only 10 of the 18 hierarchy entries are registered as valid
`Cap(X)` type ARGUMENTS (`builtin_types`, `typecheck.ml:1858-1861`) — the
other 8 (`IO.Random`, `IO.Database`, `IO.Spawn`, `IO.Mut`, `IO.Telemetry`,
`IO.Foreign`(`.Blocking`), `IO.NetConnect.TLS`) are valid `needs` targets but
cannot be written as a `Cap(X)` annotation today (`Unknown module \`IO\``),
so this task's corpus draws only from the registered 10. See
core-march-types.md §2.8.3.

**Note (`accept/t51`–`t53`, `reject/t40`–`t41`):** Capabilities widening,
Task 3 (2026-07-07) — extends `core-march-types.md` §2.8 (§2.8.8-§2.8.9) with
`cap_narrow`/`root_cap` capability threading (compile-time, runtime-erased),
the effect-inference two projections (`cap_closures` vs `own_cap_closures`,
`record_fn_caps`, `typecheck.ml:5435`), **Check 8** (`typecheck.ml:5798`,
ERROR — a `*_migrate_state` fn must be IO-free, checked via the own-caps
projection so a module's handler-level `needs` doesn't false-blame a pure
migrate), and **Check 7** (`typecheck.ml:5755`, ERROR — a
`Tagged(_, Realtime)` param cannot coexist with a `Cap(Alloc|IO|Panic)`
param). Accept: root-to-sub-cap threading into a stricter callee (`t51`), a
second threading shape narrowing `root_cap` twice to two sibling sub-caps in
one function (`t52`), a pure `*_migrate_state` fn living alongside an `actor`
in a `needs IO.Console` module — the caveat-mitigation witness (`t53`).
Reject: a `*_migrate_state` fn that performs IO (`t40`, Check 8); a
user-declared nullary `Realtime` type used in `Tagged(Int, Realtime)`
alongside `Cap(IO)` (`t41`, Check 7).

**Note (`accept/t49`–`t50`, `reject/t39`):** Capabilities widening, Task 2
(2026-07-07) — extends `core-march-types.md` §2.8 (§2.8.6-§2.8.7) with
transitive `use` coverage (**Check 4**, `typecheck.ml:5661`, ERROR — a
module's declared `needs` must cover every capability the modules it `use`s
themselves declare), extern `Cap(X)` coverage (**Check 5**,
`typecheck.ml:5684`, ERROR), and the extern-implies-`IO.Foreign` obligation
(**Check 1c**, `typecheck.ml:5607`, WARNING-only) — plus the honestly-stated
three-tier enforcement reality (Checks 1/4/5 = ERROR; Checks 1b/1c =
WARNING-only, `--check` exit 0) that reconciles `specs/lang/capabilities.md`'s
tutorial overclaim, filed as **F1** (open, `specs/todos.md`). Also files
**F6** (found during Task 1, filed now): only 10 of the 18 hierarchy entries
are registered as valid `Cap(X)` type arguments (`builtin_types`,
`typecheck.ml:1858-1861`).

**Note (`accept/t54`–`t56`, `reject/t42`–`t44`):** Capabilities widening,
Task 4 (2026-07-07) — extends `core-march-types.md` §2.8 (§2.8.11) with the
five BEHAVIORAL module caps (`cap no_panic`/`no_alloc`/`no_extern`/`pure`/
`deterministic`, lexer tokens `lexer.mll:176-180`, all parsing to `Ast.DOpts`,
`ast.ml:165`) — a per-module syntactic ban, orthogonal to the IO-permission
`needs`/`Cap(X)` machinery Tasks 1–3 cover. `cap no_panic`
(`check_no_panic_module`, `typecheck.ml:6489-6566`) and `cap no_alloc`
(`lib/refinecheck/no_alloc.ml`) are CORRECT for the shapes this task
witnesses (explicit `panic`/division; non-empty tuple/record/`ECon`/`ELam`
construction). `cap pure` (`check_pure_module`, `typecheck.ml:6581-6597`) and
`cap deterministic` (`check_deterministic_module`, `typecheck.ml:6641-6658`)
ban hardcoded name sets (`pure_banned`, `:6570-6576`; `deterministic_banned`,
`:6632-6635`) that reference builtins which do not exist (`write_file`,
`random_int`, `now_ms`, …) while missing the REAL effectful ones
(`file_write`, `file_read`, `random_bytes`, `unix_time_ms`, `vault_set`, …) —
filed as **F2** (open, UNSOUND: a `cap pure` module calling `file_write`
typechecks clean today, live-verified). Also files **F3** (open, UNSOUND):
`cap no_panic`'s `panic_surface_*` sets cover named partial functions but not
the match-exhaustiveness panic surface — a `cap no_panic` module with a
non-exhaustive `match` typechecks clean today and panics at runtime,
live-verified. Also notes **F5** (open, cosmetic): `println`/`print` produce
no Check-1b body-scan diagnostic at all despite being in
`builtin_cap_table`→`IO.Console`, making `IO.Console` the de-facto "free"
capability. F2/F3 are UNSOUND-BUT-NOT-YET-FIXED here (docs-only task); their
fixes and REJECT witnesses land in Tasks 5/6 of this same widening slice.
Accept: a genuinely-pure `cap pure` arithmetic module that stays valid across
the F2 fix (`t54`); a valid `cap no_alloc` module (`t55`); a valid
`cap no_extern` module (`t56`). Reject: `cap no_panic` + explicit `panic`
(`t42`); `cap no_alloc` + tuple construction (`t43`); `cap no_extern` +
`extern` block (`t44`).

**Note (`reject/t45`–`t47`):** Capabilities widening, Task 5 (2026-07-07) —
the **F2 FIX** (now Done). `check_pure_module` (`typecheck.ml:6645`) and
`check_deterministic_module` (`:6710`) no longer consult hand-guessed name
lists; both banned sets are now DERIVED from the authoritative
`builtin_cap_table` (`:1012`). `pure_banned` (`:6637`) = every builtin in the
table (all are effectful) unioned with the incidental non-table impure names
`spawn`/`send`/`exit`. `deterministic_banned` (`:6700`) = only the builtins
the table maps to a NONDETERMINISM cap — `IO.Clock`/`IO.Random`, decided by
`is_nondeterministic_cap` (`:6628`) — so `cap deterministic` stays WEAKER than
`cap pure`: it bans clock/RNG but still permits ordinary IO such as
`file_read` (confirmed live: `cap deterministic` + `file_read` still accepts).
This closes the soundness hole where `cap pure` + `file_write`/`random_bytes`
and `cap deterministic` + `unix_time_ms` all typechecked clean (the stale
lists spelled the nonexistent `write_file`/`random_int`/`now_ms` and missed
the real builtins). Reject: `cap pure` + `file_write` (`t45`); `cap pure` +
`random_bytes` (`t46`); `cap deterministic` + `unix_time_ms` (`t47`) — each
type-correct so the ONLY rejection is the cap ban. These three witnesses were
IMPOSSIBLE pre-fix (they accepted, exit 0). See `specs/todos.md` (F2 → Done).

**Note (`reject/t48`):** Capabilities widening, Task 6 (2026-07-07) — the **F3
FIX** (now Done). A NON-exhaustive `match` lowers to a runtime "no matching
clause" panic, so it is a panic surface a `cap no_panic` module must reject,
exactly like an explicit `panic` (`reject/t42`). Pre-fix `check_no_panic_module`
worked purely from `calls_in_expr` (a name/span list of CALLS) and never
inspected `EMatch`, so a `cap no_panic` module with a non-exhaustive match
typechecked clean (exit 0, only a Warning) and then panicked at runtime.
`check_exhaustiveness` (`typecheck.ml`) already finds every non-exhaustive
match; the fix has it ALSO record the offending `match`'s span into a new shared
ref `env.nonexhaustive_match_spans` (recording is cheap and never itself an
error). `check_no_panic_module` — which runs ONLY for `cap no_panic` modules —
reads that side-table and, for any recorded span nested (by `span_within`
source-position containment) inside one of THIS module's own function bodies,
reports an ERROR. Because the read is gated inside `check_no_panic_module`, a
non-exhaustive match in a PLAIN (non-cap) module is NEVER promoted: it stays a
non-blocking Warning (`accept/t14`, exit 0 — the key regression guard). An
exhaustive match, or one with a `_ -> ...` catch-all, still accepts. See
`specs/todos.md` (F3 → Done).

**Note (`reject/t50`, `accept/t59`):** fix-campaign batch 3 (2026-07-07) — the
**guarded-match exhaustiveness fix** (now Done), closing the residual gap F3
inherited. A `match` with a `when` guard used to short-circuit
`check_exhaustiveness` entirely (`if has_guards then ()`), so a guarded,
genuinely non-exhaustive match was recorded by NEITHER the ordinary Warning NOR
F3's `env.nonexhaustive_match_spans` side-table — invisible to `cap no_panic`'s
error path. The fix: for a guarded match, `check_exhaustiveness` now computes
coverage over the GUARDLESS branches ONLY. A branch reachable only behind a
guard cannot be relied on to match, so it contributes nothing to guaranteed
coverage; if the guardless branches are non-exhaustive the match can panic when
every guard fails at runtime, so the span is recorded (and
`check_no_panic_module` promotes it to an ERROR) exactly as for the guard-free
case — but WITHOUT a global Warning (only `cap no_panic` modules opt into this
strictness; ordinary guarded matches are unaffected). `reject/t50` = `cap
no_panic` + `Some(v) when v > 0 -> v; None -> 0` (guardless arms `{None}`,
non-exhaustive) — IMPOSSIBLE to reject pre-fix. `accept/t59` adds an unguarded
`Some(v) -> …` arm → guardless-exhaustive → still accepts (proving the fix is
not over-rejecting). See `specs/todos.md` (the guarded-match gap → Done) and
`core-march-types.md` §2.8.11 + §2.1a.

**Note (`accept/t60`–`t63`, `reject/t51`–`t57`):** Core March widening slice 6
(proof caps + nested-module type-erasure soundness fix, 2026-07-08) — anchors
`core-march-types.md` §2.8.13 (proof-capability minting, forging, and
unforgeability) and its new general typing-soundness rule (T-QualRef). This
slice is the conformance layer for two compiler soundness fixes that already
landed (`lib/typecheck/typecheck.ml`; see `.superpowers/sdd/prebind-fix-report.md`
+ `.superpowers/sdd/batch-a-report.md` and `specs/todos.md`'s "Nested-module
qualified-prebind type-erasure" Done entry). **The P0 nested-module fix
(GENERAL soundness):** an intra-module reference to a function is now checked
against that function's real body-checked scheme regardless of module nesting —
nesting no longer weakens type checking. Pre-fix, an unannotated public fn in a
nested `mod` kept a stale qualified-prebind placeholder that erased the type of
anything laundered through it (base types, ADTs, and `Cap` alike). `reject/t51`
(nested `id`-launder `Int`→`String`, the clearest memory-safety witness),
`reject/t52` (ADT arg, `Box(String)`→`Box(Int)`), `reject/t53` (distinct-tvar
annotation `fn launder(x:a):b`), and `reject/t54` (entry-module self-qualified
`Main.id`) each were type-correct and ACCEPTED (exit 0) pre-fix — IMPOSSIBLE to
reject pre-fix — and are now rejected; `accept/t60` (nested `id` used at Int AND
String) proves the fix RESTORES legitimate polymorphism rather than
over-restricting. **The proof-cap minting discipline:** `mint_cap` is the only
sanctioned proof-cap mint and is gated to a PUBLIC fn of the cap's declaring
module (`reject/t56` external, `reject/t57` pfn; `accept/t62` the legit mint);
`cap_narrow` can no longer produce a proof cap in ANY position (`reject/t55` the
Batch-A forge) while ordinary IO-lattice narrowing is unaffected
(`accept/t61`); and a proof cap flows by receive-and-pass-through
(`accept/t63`). Together these make `Cap(P)` genuinely unforgeable. Flips the
`specs/todos.md` "proof-cap mint mismatch" finding to resolved and reconciles
`capabilities.md`'s proof-caps section (the non-typechecking `; ()` mint idiom →
`mint_cap`; the "Known mismatch" callout → resolved). The still-OPEN
`cap_narrow` container-launder taint follow-up remains a documented residual.

## The `--check` accept/reject harness model

Unlike the operational golden corpus (`specs/lang/golden/`, which runs each
program through BOTH the interpreter and the compiled backend and diffs their
output — there is something to differentially compare), March has only **one**
typechecker: it runs identically before both `eval` and `--compile`. So this
corpus's anchor is the compiler's own `--check` mode instead of a diff:

- **`accept/*.march`** — must typecheck: `march --check file.march` must exit
  **0**.
- **`reject/*.march`** — must be rejected: `march --check file.march` must exit
  **1**, AND its `--check` stderr/stdout output must contain the exact
  substring named in the program's own first-line annotation,
  `-- EXPECT-ERROR: <substring>`. Pinning the substring (not just "rejected
  somehow") catches a typechecker regression that rejects the program for the
  WRONG reason as well as one that stops rejecting it at all.

Run the whole corpus:

```
dune build bin/main.exe
MARCH_BIN=$PWD/_build/default/bin/main.exe specs/lang/types/check_types.sh
```

Exit 0 iff every program behaves as declared (currently 125/125 — 68 accept, 57
reject). See `specs/lang/core-march-types.md` §3 for the harness's full
description and the invariant it protects (a spec that misdescribes the
typechecker, AND a real typechecker regression, both show up as a harness
failure).

**CI:** this harness is wired into its own `types-check` dune alias — a
*separate, slow, opt-in* lane, deliberately not part of the default
`@runtest`/`@oracle` sweeps (`reject/` programs deliberately fail to
typecheck, so they cannot ride the operational side's both-ways
interpret-vs-compile oracle the way `specs/lang/golden/` does — see the
"Why not `@oracle`" note at the bottom of this file). Run it directly with
`dune build @types-check` (from `test/`, or `dune build test/@types-check`
from the repo root) or as part of the CI workflow's dedicated step.

## Provenance

| Range | Task | Constructs added |
|---|---|---|
| `accept/t01`–`t04` | walking-skeleton v0 | literals, lambda/application, `let`-polymorphism, `if` |
| `reject/t01`–`t04` | walking-skeleton v0 | unify mismatch, unbound var, T-App arity, `if`-branch mismatch |
| `accept/t05`–`t07`, `reject/t05`–`t06` | Task 1 | ADT constructors + `match` (T-Con, T-Match, P-Con) |
| `accept/t08`–`t10`, `reject/t07`–`t09` | Task 2 | tuples + records (T-Tuple, T-Record, T-Field, T-Update, P-Tuple) |
| `accept/t11`–`t12` | Task 3 | atoms (T-Atom-0, T-Atom-N, P-Atom) |
| `accept/t13`–`t15`, `reject/t10`–`t11` | Task 4 | match guards (T-Guard), scrutinee-less `match do` (T-Cond); pattern-typing relation completed |
| `accept/t16`–`t17`, `reject/t12` | Task 5 | local recursive functions (T-LetFn) |
| `accept/t18`–`t20`, `reject/t13`–`t15` | Task 6 | interface-constraint model (T-Discharge, §2.1/§2.1a/§2.1b), boolean primitives |
| — | Task 7 | no new programs — consolidation + this INDEX + CI wiring only |
| `accept/t21`–`t22`, `reject/t16`–`t17` | Typechecker fixes (2026-07-05) | witnesses for findings 16 (`f0f5299c`, let-annotation enforcement), 15 (`8cbd6dd2`, generic `when`-constraint re-check), and 13 (`7e40dc5b`, ELetFn diagnostic dedup — pins `reject/t12` at one diagnostic, no new program) |
| `accept/t23`–`t25`, `reject/t18`–`t21` | Widening slice 1, Task 1 (2026-07-06) | user-defined `interface`/`impl` DECLARATION checking (§2.3: `(T-Interface)` registration, `(T-Impl)`'s ordered checks — missing/extra-method, signature-match, unknown-interface — and default methods) |
| `accept/t26`, `reject/t22` | Widening slice 1, Task 2 (2026-07-06) | superclass/`requires` and `when`-clause discharge (mandatory enforcement, §2.3), the `impl_matches_ty` structural-match judgment named as its own rule, `(T-ImplMatch)` |
| `accept/t27`–`t28` | Widening slice 1, Task 3 (2026-07-06) | method-DISPATCH operational rules (`core-march.md` §4.4.2, not `core-march-types.md`): the four-name `impl_tbl` type-directed lookup for `Show`/`Eq`/`Ord`/`Hash`, and ordinary lexical `env`-binding dispatch for user-defined interfaces |
| — | Widening slice 1, Task 4 (2026-07-06) | no new programs — coherence/overlap is a runtime interp-vs-compiled DIVERGENCE (`core-march.md` §4.4.3), which a single-`--check`-invocation harness cannot witness; documented in prose + filed in `specs/todos.md` instead |
| `accept/t29`–`t30`, `reject/t23`–`t24` | Widening slice 1, Task 5 (2026-07-06) | `derive`/`satisfy` as `DImpl` GENERATORS (§2.4): the closed five-interface `derive` set + `Json`'s `JsonTo`/`JsonFrom` pseudo-interface special case, `satisfy`'s name-matching all-or-nothing wiring, and the filed `derive X for UnknownType` silent-no-op gap (§4.1 finding 17) |
| `reject/t25` | Modules widening — same-file private-member diagnostic (2026-07-06, concurrent) | a same-file qualified reference to a PRIVATE nested-module member (`A.secret` where `secret` is `pfn`) is diagnosed as `` Function `secret` is private to module `A`. `` instead of the misleading `` Unknown module `A` `` (private members are never exported into `env.vars`; `env.local_mods` records them so `qualified_error_msg` recognizes the in-file module) |
| `accept/t31`, `reject/t26` | Widening slice 2, Task 1 (2026-07-06) | cross-module **visibility fix** — `load_module_into_env`'s `ex_public` gate for `ExFn`/`ExValue` (a private `pfn`/value is no longer callable cross-module: `reject/t26` pins `is private to module \`Array\``); the ACCEPT side proves the gate is narrow — a PUBLIC cross-module call still resolves and the OPAQUE-TYPE pattern (a private `ptype`'s bare name usable in a cross-module annotation, `ExType`/`ExRecord` left ungated) still holds (`accept/t31`) |
| `accept/t32`–`t33` | Widening slice 2, Task 2 (2026-07-06) | module declaration/nesting/name-resolution OPERATIONAL rules (`core-march.md` §4.7, not `core-march-types.md`): the `DMod` export mechanism (`own_names`, `"Name.member"` re-prefixing into the enclosing scope and the global `module_registry`), the bare-fails/qualified-works asymmetry, and the lexical-scoping nuance (a `pfn` nested inside `A` callable bare from a module nested inside `A`) |
| `accept/t34`–`t36` | Widening slice 2, Task 3 (2026-07-06) | module visibility as a TYPING concept (§2.5): the opaque-type asymmetry re-verified with a second stdlib witness (`t34`, `ConsistentHash.HashRing`), the no-per-module-type-namespace design point value-witnessed (`t35`, `A.Foo`/`B.Foo` collision), and the A10 qualified-record case re-confirmed still green (`t36`, `Cfg.Site`); also files a real, precisely-traced gap found while probing live — `opaque type`'s constructor-hiding is not actually enforced against qualified construction (`prebind_mod_members`, `typecheck.ml:8032–8087`, registers the qualified ctor key ungated on `var_vis`) |
| `accept/t37`–`t38`, `reject/t27` | Widening slice 2, Task 4 (2026-07-06) | `use`/`import`/`alias` selector rules and the file-based resolver pre-pass (`core-march.md` §4.7.1, not `core-march-types.md`): both `use A.*` (`t37`) and the selector form `use A.{name}` (`t38`) value-witnessed against a real stdlib module (`List`); the file-vs-in-file resolver distinction (`use A.*` against an in-file nested `mod A` rejects `` Module `A` not found ``, since the resolver looks for an actual `a.march` FILE); selective `use X.{name}` of a private stdlib fn (`reject/t27`, `Array.lst_rev`) rejects `` Module `Array` does not export `lst_rev`. `` — the same `pub_set` gate `reject/t26` exercises, confirmed consistent with Task 1's cross-module visibility fix |
| `accept/t39`, `reject/t28` | Widening actors slice, Task 1 (2026-07-06) | actor DECLARATION + `spawn` typing (`core-march-types.md` §2.6): the `DActor` arm's checks (state record type, `init` checked against it, each handler body checked to RETURN the state type; `typecheck.ml:6742–6821`), `spawn`'s compile-time literal-actor-name resolution (only `ECon(_,[],_)`/`EVar` accepted, computed actor expressions rejected; `:4185–4203`, `reject/t28` = `spawn(pick())`), and the truthful `Pid`-parameter account — `spawn` yields `Pid[fresh var]` NOT `Pid[state]` (§4.1 finding 18); `accept/t39` witnesses the fresh-var accept path (`is_alive` on a `spawn` result) |
| `accept/t40`, `reject/t29` | Widening actors slice, Task 3 (2026-07-06) | actor MESSAGE-PAYLOAD typing + the affinity non-guarantee (`core-march-types.md` §2.6.4): a message ctor's payload IS checked via the ordinary `ECon` path (`infer_expr env msg`, `typecheck.ml:4179`) — `accept/t40` = `send(counter, Inc(3))` accepts, `reject/t29` = `send(counter, Inc("x"))` rejects `` expected `Int` but got `String`. ``; but message ACCEPTANCE by the target actor is NOT checked — `send` discards the target Pid's type (`:4178`) and the only send-side check is `check_sendable`'s `RingBuf` denylist (`:3331`/`:3335`), so a wrong-actor send typechecks (silently DROPPED interpreted, MISROUTED compiled — §4.1 finding 19, documented in prose, not corpus-encoded) |
| `accept/t41`–`t42` | Session-types widening, Task 2 (2026-07-06) | `protocol` declaration + projection + duality + `Chan(Role,Proto)` typing (`core-march-types.md` §2.7): `session_ty` (`typecheck.ml:105–116`), `TChan of session_ty ref` (`:95`), `project_steps`/`project_protocol` (`:5870`/`:5952`), binary duality via `dual_session_ty` (`:5935`, check `:5972–5986`), MPST send/recv-pair consistency (documented TYPING-ONLY — compiled MPST segfaults, F3, filed by the operational widening task) — `accept/t41` is a binary `Echo` protocol + `Chan.new` + `Chan(Role,Echo)` annotations, run-witnessed printing `43`; `accept/t42` is a 3-role MPST `Relay` protocol + `MPST.new`, run-witnessed printing a confirmation string (declare-only, never sends, so unaffected by F3). Also files **F4** (§2.7.5, §4.1 finding 20): the MPST merge rule (`:5906–5919`) leaks into binary duality, wrongly rejecting a legal binary `choose` protocol whose two branches carry the same payload type — reproduced live both ways (not a corpus `reject/` program; it would codify the bug as intended) |
| `reject/t30`–`t35`, `accept/t43` | Session-types widening, Task 3 (2026-07-06) | per-operation channel typing + advancement (`core-march-types.md` §2.7.8): the six `reject/` programs pin the live message for each session-state violation — send-at-wrong-state (`t30`), close-before-`End` (`t31`), invalid `choose` label (`t32`), wrong payload type (`t33`, the ordinary `check_expr` path, not a session-specific message), recv-at-wrong-state (`t34`), and a linear channel continuation used twice (`t35`, the generic linear-`let` tracker, not session-specific accounting). `accept/t43` is a full `choose`/`send`/`close` + `offer`/`recv`/`close` round-trip on a two-branch (`Int`/`String`) `Decision` protocol, run-witnessed printing `:ok` then `42`. Also files **F5** (§2.7.9, §4.1 finding 21): `Chan.offer` (`typecheck.ml:3614`) always returns the FIRST branch's continuation type regardless of which branch the peer actually chose at runtime — a documented conservative approximation that is a real (if narrow) soundness gap for protocols whose `offer` branches have DIFFERENT continuations |
| `accept/t44` | Session-types fix-campaign (2026-07-07) | F4 FIX witness (§2.7.5, FIXED): a binary `Decision` protocol whose two `choose` branches carry the SAME payload type (`Int`/`Int`) now typechecks — the merge rule in `project_steps`'s `ProtoChoice` arm is gated on `multiparty`, so a 2-role protocol's non-chooser always projects to `SOffer{...}` instead of collapsing to a shared `Recv`, restoring binary duality |
| `accept/t45`–`t48`, `reject/t36`–`t38` | Capabilities widening, Task 1 (2026-07-07) | IO capability subsumption + `Cap(X)` signature enforcement (§2.8): the 18-entry hierarchy (`lib/caps/cap_lattice.ml:15-34`), `cap_subsumes`/`normalize` (`:50`/`:56`), the `needs` manifest (`DNeeds`, `ast.ml:159`), and **Check 1** (`typecheck.ml:5561`) — every `Cap(X)` in a function/actor/extern signature must be covered by a declared `needs` via subsumption, else ERROR. Accept: bare-covered (`t45`), root-covers-child subsumption (`t46`), sibling independence — each of two siblings needs its own `needs` (`t47`), a second mid-tier subsumption shape (`t48`). Reject: uncovered `Cap(X)` (`t36`), narrow `needs` does not cover a broader `Cap` (`t37`), sibling does not cover sibling (`t38`). Also files a live scoping finding: only 10 of the 18 hierarchy entries are registered as valid `Cap(X)` type ARGUMENTS (`builtin_types`, `typecheck.ml:1858-1861`) — the other 8 (`IO.Random`, `IO.Database`, `IO.Spawn`, `IO.Mut`, `IO.Telemetry`, `IO.Foreign`(`.Blocking`), `IO.NetConnect.TLS`) are valid `needs` targets but cannot be written as a `Cap(X)` annotation (`Unknown module \`IO\``) |
| `accept/t49`–`t50`, `reject/t39` | Capabilities widening, Task 2 (2026-07-07) | transitive `use` + extern-implied caps (§2.8.6): **Check 4** (`typecheck.ml:5661`) — every module a given module `use`s must have ITS OWN declared `needs` covered transitively, via `env.module_caps` and the same `cap_subsumes` subsumption, ERROR on violation; **Check 5** (`typecheck.ml:5684`) — an extern block's own declared `Cap(X)` must be covered by `needs`, ERROR; **Check 1c** (`typecheck.ml:5607`) — every extern block additionally implies `IO.Foreign` (+`.Blocking`), WARNING-only. Accept: an importer declaring the real stdlib module `Vault`'s (`needs IO.Mut`) transitive obligation (`t49`); a well-formed extern covered on both Check 5 and Check 1c (`t50`). Reject: companion to `t49` with the covering `needs` removed, pinning Check 4's ERROR (`t39`). Also states the honest three-tier enforcement reality (Checks 1/4/5 = ERROR; Checks 1b/1c = WARNING-only, `--check` exit 0), reconciling `specs/lang/capabilities.md`'s tutorial overclaim — filed as **F1** (open); also files **F6** (found during Task 1, filed now) — the 10-of-18 `Cap(X)`-argument registration gap |
| `accept/t51`–`t53`, `reject/t40`–`t41` | Capabilities widening, Task 3 (2026-07-07) | `cap_narrow`/`root_cap` threading + effect inference + Check 8 + Check 7 (§2.8.8-§2.8.9): `root_cap : Cap(IO)` (`typecheck.ml:1457`, a value) and `cap_narrow : Cap(IO) -> Cap(a)` (`:1458`, POLYMORPHIC return — compile-time, runtime-erased); `record_fn_caps` (`:5435`) accumulates `cap_closures` (own + module-wide) and `own_cap_closures` (own only); **Check 8** (`:5798`) — a `*_migrate_state` fn must be IO-free, checked via the own-caps projection so a module's handler-level `needs` doesn't false-blame a pure migrate (the F-caveat mitigation); **Check 7** (`:5755`) — a `Tagged(_, Realtime)` param excludes `Cap(Alloc\|IO\|Panic)` params. Accept: narrow-and-thread-to-a-stricter-callee (`t51`), narrow `root_cap` twice to two sibling sub-caps in one fn (`t52`), a pure `*_migrate_state` fn beside a real `actor` in a `needs IO.Console` module (`t53`, the caveat-mitigation witness). Reject: a `*_migrate_state` fn calling `println` (`t40`, Check 8); a user-declared nullary `Realtime` type in `Tagged(Int, Realtime)` alongside `Cap(IO)` (`t41`, Check 7 — `Realtime` itself is not pre-registered in `builtin_types`, so a user must declare it before writing `Tagged(_, Realtime)` at all) |
| `accept/t54`–`t56`, `reject/t42`–`t44` | Capabilities widening, Task 4 (2026-07-07) | Behavioral module caps (§2.8.11): `cap no_panic` (`check_no_panic_module`, `typecheck.ml:6523`), `cap no_alloc` (`lib/refinecheck/no_alloc.ml`), `cap no_extern` (`check_no_extern_module`, `:6668`), `cap pure` (`check_pure_module`, `:6645`), `cap deterministic` (`check_deterministic_module`, `:6710`) — all parsed from `Ast.DOpts` (`ast.ml:165`). Accept: a genuinely-pure `cap pure` arithmetic module (`t54`, stays valid across the F2 fix), a valid `cap no_alloc` module with only comparisons/arithmetic (`t55`), a valid `cap no_extern` module (`t56`). Reject: `cap no_panic` + explicit `panic` (`t42`), `cap no_alloc` + tuple construction (`t43`), `cap no_extern` + an `extern` block (`t44`). Files **F2** (**now FIXED in Task 5**) — `pure_banned`/`deterministic_banned` named nonexistent builtins and missed the real effectful ones, so `cap pure`+`file_write` (or `cap deterministic`+`unix_time_ms`) typechecked clean; **F3** (**now FIXED in Task 6**) — `cap no_panic` didn't consume the exhaustiveness checker's verdict, so a non-exhaustive `match` in a `cap no_panic` module typechecked clean and panicked at runtime; **F5** (open, cosmetic) — `println`/`print` skip the Check-1b body-scan diagnostic entirely. F2/F3's fixes + REJECT witnesses land in Tasks 5/6 of this slice |
| `reject/t45`–`t47` | Capabilities widening, Task 5 — F2 FIX (2026-07-07) | **F2 FIXED**: `pure_banned` (`typecheck.ml:6637`) and `deterministic_banned` (`:6700`) are no longer hand-maintained name lists — both are DERIVED from `builtin_cap_table` (`:1012`), the authoritative effect map Check 1b already trusts. `pure_banned` = every table builtin (all effectful) ∪ `{spawn, send, exit}`; `deterministic_banned` = only table builtins whose cap is a nondeterminism source (`IO.Clock`/`IO.Random`, via `is_nondeterministic_cap`, `:6628`), so `cap deterministic` stays weaker than `cap pure` (still permits a deterministic `file_read`). Reject: `cap pure` + `file_write` (`t45`), `cap pure` + `random_bytes` (`t46`), `cap deterministic` + `unix_time_ms` (`t47`) — each type-correct so the cap ban is the sole rejection; all three ACCEPTED (exit 0) pre-fix. See `specs/todos.md` (F2 → Done) |
| `accept/t59`, `reject/t50` | Fix-campaign batch 3 — guarded-match exhaustiveness (2026-07-07) | **Guarded-match gap FIXED**: `check_exhaustiveness` (`typecheck.ml`) no longer short-circuits on `has_guards` — for a guarded match it computes coverage over the GUARDLESS branches only and records the span into `env.nonexhaustive_match_spans` when they are non-exhaustive (WITHOUT a global Warning — only `cap no_panic` modules opt into this strictness), so `check_no_panic_module` promotes a guarded non-exhaustive match to an ERROR. Closes the residual gap F3 inherited. Reject: `cap no_panic` + `Some(v) when v > 0 -> v; None -> 0` (guardless arms `{None}`, non-exhaustive, `t50` — IMPOSSIBLE to reject pre-fix). Accept: adds an unguarded `Some(v)` → guardless-exhaustive (`t59`). See `specs/todos.md` (guarded-match gap → Done) |
| `accept/t60`–`t63`, `reject/t51`–`t57` | Core March widening slice 6 — proof caps + nested-module type-erasure soundness fix (2026-07-08) | Anchors §2.8.13 (proof-cap minting/forging/unforgeability) + the general (T-QualRef) soundness rule. **P0 nested-module fix (`check_decl` DFn branch, `lib/typecheck/typecheck.ml`):** an intra-module reference to a fn is now checked against its real body-checked scheme at every nesting level incl. entry — pre-fix, an unannotated public fn in a nested `mod` kept a stale qualified-prebind placeholder that erased the type of anything laundered through it (a GENERAL memory-safety hole; the proof-cap forge was one exploitation). Reject: nested `id`-launder `Int`→`String` (`t51`, the clearest memory-safety witness, uses `string_length` not `String.length`), ADT arg `Box(String)`→`Box(Int)` (`t52`), distinct-tvar `fn launder(x:a):b` (`t53`), entry-module self-qualified `Main.id` (`t54`) — each type-correct + ACCEPTED (exit 0) pre-fix, IMPOSSIBLE to reject pre-fix. Accept: nested `id` at Int AND String (`t60`, the fix RESTORES polymorphism). **Proof-cap minting discipline (Batch-A):** `mint_cap` is the only sanctioned mint, gated to a PUBLIC fn of the declaring module; `cap_narrow` can no longer produce a proof cap in ANY position. Reject: `cap_narrow` proof-cap forge (`t55`, `cap_narrow cannot produce`), `mint_cap` external module (`t56`, Check 6), `mint_cap` in a `pfn` (`t57`, Check 6). Accept: legit IO narrow (`t61`), legit `mint_cap` in declaring public fn (`t62`), proof-cap pass-through (`t63`). Flips the `specs/todos.md` "proof-cap mint mismatch" → resolved; reconciles `capabilities.md`. See `.superpowers/sdd/prebind-fix-report.md` + `batch-a-report.md`; still-OPEN `cap_narrow` container-launder taint remains a documented residual |
| `accept/t64`–`t68` | Core March widening slice 7 — linear/affine types, Task 2 (2026-07-10) | Anchors §2.9 (linearity: marking surfaces, the `env.lin` tracker, transparency). Accept: `linear let` single use (`t64`), `linear` param single use (`t65`), affine type-modifier param dropped (`t66`, also pins the WORKING affine spelling — the param-keyword form is a parse error, finding L1), single arithmetic use of a `linear Int` field (`t67` — REQUIRES the slice-7 L2 fix: constraint discharge now strips `TLin` like `impl_matches_ty` always did; rejected `` does not implement Num `` pre-fix), linear-value send-to-actor as the consuming use (`t68`, corrects the tutorial's "cannot be sent" claim, finding L6). Reject twins land in Task 3 (`reject/t58`+). Findings L1–L6 filed in `specs/todos.md`; survey record in `specs/plans/2026-07-10-widening-linear-types-plan.md` |

## `accept/` — must typecheck

| Program | Anchors | Notes |
|---|---|---|
| `t01_literals` | T-Lit (Int/Bool/String) | |
| `t02_lambda_app` | T-Abs, T-App, annotated `Int -> Int` param | |
| `t03_let_poly` | **T-Let generalization** — a local `id = fn x -> x` used at both `Int` and `String` | proves let-polymorphism (§4.1 finding 1) |
| `t04_if` | T-If (Bool cond, matching branches) | |
| `t05_adt_construct_match` | T-Con + T-Match — a 2-ctor ADT (`Hue = Rood \| Bloo`) constructed and matched exhaustively | |
| `t06_payload_ctor_branch` | P-Con — a payload-carrying ctor (`Circle(Int)`) bound to a pattern var in a branch | |
| `t07_generic_option_two_types` | T-Con/P-Con with a fresh instantiation per occurrence — `Box(a) = Full(a) \| Vacant` used at both `Int` and `String` | §4.1 finding 4 witness |
| `t08_tuple_construct_destructure` | T-Tuple + P-Tuple — a tuple built and destructured by both a `match` and a function-arg `PatTuple` | |
| `t09_record_literal_field` | T-Record + T-Field — a record literal (`{ x: 1, y: 2 }`) with both fields read via `EField` | |
| `t10_record_update_existing_field` | T-Update — `{ p with x: 100 }` on an existing field, result type unchanged | |
| `t11_atom_nullary_eq_match` | T-Atom-0 + P-Atom — a nullary `:ok` returned, compared via `==`, matched by a nullary `PatAtom` | |
| `t12_atom_payload_and_name_erasure` | T-Atom-N + P-Atom — payload atom `:count(n+1)` matched with payload bound, plus two differently-tagged nullary atoms proving name-erasure | §4.1 finding 8 witness |
| `t13_match_guard` | (T-Guard) — three `when`-guarded `PatVar` arms, guard checked against `Bool` in the pattern-extended env | |
| `t14_nonexhaustive_match_still_typechecks` | **(T-Match: Exhaustiveness) — the brittleness witness** — a 2-ctor ADT `match` covering only ONE ctor | exhaustiveness is a Warning, not an Error — §4.1 finding 9 |
| `t15_econd_chain` | (T-Cond) — a 3-arm `match do` boolean chain, all conditions `Bool`, all bodies `String` | |
| `t16_letfn_factorial` | (T-LetFn) — a local self-recursive `fn go(k, acc)` (factorial), monomorphic inside its own body | |
| `t17_letfn_generalized_after_block` | **(T-LetFn) generalization** — a local `fn id_rec(x)` used at both `Int` and `String` in the REST of the block | §4.1 finding 13 witness |
| `t18_num_constraint_discharged` | (δT-Add, T-Discharge) — `1 + 2` (Int) and `1.0 +. 2.0` (Float) both discharge cleanly | |
| `t19_eq_ord_constraint_discharged` | (δT-Eq, δT-Ord, T-Discharge) — `x == y` and `x < y` on two `Int`s discharge against built-in instances | |
| `t20_bool_ops` | (δT-And, δT-Or, δT-Not) — `&&`/`\|\|`/`not` over `Bool`-typed comparisons | |
| `t21_let_annot_ok` | **(T-Let annotation, finding 16 fix)** — a correct `let x : Int = 5` and a polymorphic RHS bound at a more specific instance (`let f : (Int) -> Int = fn n -> n`) both typecheck | |
| `t22_generic_when_constraint_satisfied` | **(T-Discharge via instantiate, finding 15 fix)** — a generic `when Ord(a)`/`when Eq(a)` bound SATISFIED at the call site (Int/String) still typechecks | |
| `t23_interface_impl_basic` | (T-Interface), (T-Impl) — a minimal user-declared `interface Speak(a) do fn speak : a -> String end` + `impl Speak(Dog)` providing exactly `speak` | run-witnessed: prints `"Rex"` |
| `t24_interface_impl_generic_head` | (T-Impl), `impl_matches_ty` wildcard semantics — a generic/parameterized impl head `impl Describe(Box(a))`, used at both `Box(Int)` and `Box(String)` | |
| `t25_interface_default_method` | **(T-Impl) default methods** — an interface method with a default body, omitted by the impl; `inject_defaults` (desugar) splices the default in before typecheck ever sees the impl, so no missing-method error fires | run-witnessed: `greeting(Cat("Tom"))` prints `42` (the default, not a value the impl ever defined) |
| `t26_impl_superclass_satisfied` | **(T-Impl) superclass discharge** — `interface Greet(a) requires Speak(a)`, with `impl Speak(Dog)` declared before `impl Greet(Dog)` | run-witnessed: prints `"Hello, Rex"` — the bound SATISFIED |
| `t27_user_iface_lexical_dispatch` | **operational (`core-march.md` §4.4.2, E-DImpl)** — a user `interface Speak(a)` + one `impl Speak(Dog)`; `speak(Dog("Rex"))` resolves via ORDINARY lexical `env` binding, not a type-directed table | run-witnessed: prints `"Rex says Woof"` |
| `t28_derive_impl_tbl_dispatch` | **operational (`core-march.md` §4.4.2, E-Dispatch-Builtin)** — `derive Show, Eq for Color`; `show(Red)`/`Green == Green`/`Red == Blue` all dispatch through the runtime `impl_tbl` hashtable keyed `(iface, type_name)` on the argument's dynamic type | run-witnessed: prints `Red` / `true` / `false` |
| `t29_derive_eq_show` | **(§2.4) `derive` as a `DImpl` generator** — `derive Eq, Show for Color` expands (desugar-time) into ordinary `impl Eq(Color)`/`impl Show(Color)` blocks, indistinguishable from hand-written ones; also a run-value witness for `core-march.md` §4.4.4 (derive-generated impls dispatch through the SAME `impl_tbl` rule as §4.4.2) | run-witnessed: prints `Red` / `true` / `false` |
| `t30_satisfy_wiring` | **(§2.4) `satisfy` as a `DImpl` generator** — `satisfy Named for Person` wires an EXISTING top-level `fn name` to `interface Named(a)`'s one method purely by name match, no `impl` block written | run-witnessed: prints `"Ada"` |
| `t31_cross_module_public_and_opaque_ptype` | **module visibility — the ACCEPT side (slice 2, Task 1)** — a PUBLIC cross-module call (`Array.length(Array.empty())`) still resolves, AND a private `ptype`'s bare type NAME (`ConsistentHash.HashRing(String)`) is still usable as a cross-module param annotation (the opaque-type pattern; `ExType`/`ExRecord` left ungated). Witnesses the narrowness of the `ExFn`/`ExValue` gate that `reject/t25` exercises | run-witnessed: exit 0, `length(empty()) == 0` |
| `t32_qualified_cross_module_call` | **module operational rules (`core-march.md` §4.7, E-DMod) — qualified cross-module resolution** — `A.double(21)`, a nested module's declared `fn` reached by full qualification from its sibling `Main`; witnesses the `own_names` export step (`eval.ml:8228–8271`) that re-prefixes `A`'s own names to `"A.member"` in the enclosing scope | run-witnessed: prints `42` |
| `t33_nested_module_lexical_resolution` | **module operational rules (§4.7) — the lexical-scoping nuance** — `secret`, a `pfn` (private) declared inside `A`, is called BARE (unqualified) from `Inner`, a module nested directly inside `A`; privacy only gates cross-module qualified access (a typecheck-time concern), not lexical access from a directly-nested module | run-witnessed: prints `42` |
| `t34_opaque_ptype_qualified_annotation` | **module visibility — the opaque-type asymmetry, second witness (§2.5, slice 2 Task 3)** — `ConsistentHash.HashRing(a)` (a private `ptype`) used as a cross-module param annotation (`ring_arity(_ring : ConsistentHash.HashRing(String))`); independent of `t31`'s `Array` witness, exercising the annotation directly rather than an otherwise-unused param | run-witnessed: prints `1` |
| `t35_no_per_module_type_namespace` | **the no-per-module-type-namespace DESIGN POINT (§2.5)** — sibling modules `A`/`B` each declare their own `type Foo`; `take_a(x : A.Foo)` silently accepts a `B.Foo` value (`B.make()`) because types resolve by bare name only — no per-module type identity exists to keep them apart | run-witnessed: prints `7` |
| `t36_qualified_record_type_still_green` | **A10 re-verification (§2.5)** — the survey's flagged-not-confirmed qualified-record case (`Cfg.Site`), same-file nested-module form; re-checked live after both `9001e4c0` and Task 1's visibility fix — no regression found | run-witnessed: prints `Site` |
| `t37_use_all_stdlib_module` | **`use`/`import` operational rules (§4.7.1, slice 2 Task 4) — bulk `use A.*`** — `use List.*` rebinds `List`'s public names (including `append`, genuinely `List`-only, not shadowed by `prelude.march`) bare in `Main`'s scope; witnesses `UseAll`'s rebinding rule (`typecheck.ml:7275–7319`) and the resolver pre-pass locating a real stdlib file | run-witnessed: prints `3` |
| `t38_use_selector_named_import` | **`use`/`import` operational rules (§4.7.1) — the selector form `use A.{name}`** — `use List.{append}` imports exactly the one named public fn; witnesses `UseNames`'s narrower, per-name rebinding rule (`typecheck.ml:7320–7337`) | run-witnessed: prints `3` |
| `t39_actor_spawn_pid` | **actor declaration + `spawn` typing (§2.6, actors slice Task 1)** — a valid `actor Counter do state {count:Int} init {…} on Inc() do … end end` (the `DActor` arm checks state type + `init` + handler-returns-state, `typecheck.ml:6742–6821`) and `spawn(Counter)` yielding a `Pid` consumed by `is_alive : Pid(a) -> Bool`; also the ACCEPT witness for §4.1 finding 18 — the yielded `Pid` parameter is a FRESH VAR, not the state type (`:4203`), so `is_alive`'s `a` unifies with it freely | `--check` exit 0 |
| `t40_actor_send_typed_payload` | **actor message-payload typing (§2.6.4, actors slice Task 3) — the accept path** — `send(counter, Inc(3))` where the handler is `on Inc(x : Int)`; the `ESend` arm (`typecheck.ml:4177`) types the message via ordinary `ECon` constructor typing (`let msg_ty = infer_expr env msg`, `:4179`), so a correctly-typed payload passes, and `check_sendable` (`:4180`, `:3335`) finds no `RingBuf` and raises nothing. Also the accept-side witness for §4.1 finding 19 (the affinity non-guarantee): `send` discards the target Pid's type (`:4178`) and checks only the payload shape | `--check` exit 0 |
| `t41_binary_protocol_chan_new` | **binary session-type protocol declaration + projection + duality + `Chan(Role,Proto)` typing (§2.7, session-types widening Task 2)** — `protocol Echo` (2 roles, `Client`/`Server`, each declared as its own nullary type to avoid the undeclared-role HINT); `project_protocol` (`typecheck.ml:5952`) projects each role's local `session_ty` and verifies binary duality (`dual_session_ty`, `:5935`, check `:5972–5986`); `Chan(Client,Echo)`/`Chan(Server,Echo)` resolve via `surface_ty`'s `TyCon("Chan",...)` special case (`:2285–2311`) to a linear `TChan` endpoint; `Chan.new(Echo)` constructs both endpoints, threaded through a straight-line send/recv/close sequence (send always before its matching recv, avoiding the unrelated no-scheduler runtime deadlock) | `--check` exit 0; run-witnessed: prints `43` |
| `t42_mpst_protocol_new` | **MPST (3-role) protocol projection + send/recv-pair consistency typing (§2.7.3–§2.7.4, session-types widening Task 2)** — `protocol Relay` (`Client`/`Server`/`Logger`, all `String` payloads); `project_protocol` sets `multiparty = true`, projects each role to role-annotated `SMSend`/`SMRecv` (`:115–116`) instead of binary `SSend`/`SRecv`, and verifies every `ProtoMsg` has a matching send/recv pair across its two endpoints (`:5987+`); `MPST.new(Relay)` destructures into a 3-tuple of role endpoints. Witnesses that MPST is TYPING-ONLY in this reference — the program deliberately never sends a message, so it is unaffected by the compiled MPST segfault (F3, filed by the operational widening task) | `--check` exit 0; run-witnessed: prints a confirmation string |
| `t43_choose_offer_roundtrip` | **`choose`/`offer` full session round-trip (§2.7.8, session-types widening Task 3)** — `protocol Decision` (`choose by Client: ok -> Int \| err -> String`, two branches with DIFFERENT payload types so the F4 merge-rule pitfall does not fire); `Chan.choose(cc, :ok)` advances to the `:ok` branch's continuation (`typecheck.ml:3564`), followed by `Chan.send`/`Chan.close`; `Chan.offer(sc)` (`:3614`) returns `(Atom, Chan at FIRST branch's continuation)` — here the chooser always picks `:ok`, which IS the first branch, so the F5 approximation happens to be exact for this witness (see F5, §2.7.9, for why that isn't true in general) | `--check` exit 0; run-witnessed: prints `:ok` then `42` |
| `t44_binary_choice_identical_branches` | **F4 FIX witness (fix-campaign, 2026-07-07) — a BINARY protocol with two IDENTICAL-payload-type `choose` branches now typechecks** — `protocol Decision` (`choose by Client: ok -> Int \| err -> Int`, both branches `Int`). Before the F4 fix this was WRONGLY rejected "not duals of each other": `project_steps`'s `ProtoChoice` merge rule collapsed the non-chooser (`Server`) projection from `SOffer{...}` to the shared `Recv(Int, End)`, breaking binary duality. The fix gates the merge on `multiparty` (`typecheck.ml`), so a 2-role protocol's non-chooser always projects to `SOffer{...}`. Flips the §2.7.5 finding-20 defect from a documented bug to a passing accept. See `core-march-types.md` §2.7.5 (FIXED) + `specs/todos.md` finding 20 (Done) | `--check` exit 0 |
| `t45_cap_bare_covered` | **Check 1 (§2.8, capabilities widening Task 1) — the base case** — `Cap(IO.Console)` param, module declares exactly `needs IO.Console`; `cap_subsumes IO.Console IO.Console` holds trivially (a cap covers itself) | `--check` exit 0 |
| `t46_cap_broad_needs_covers_narrow` | **Check 1 subsumption (§2.8) — root covers a child** — `Cap(IO.Network)` param covered by the ROOT `needs IO`; `cap_subsumes "IO" "IO.Network"` holds because `"IO.Network"`'s ancestor chain includes `"IO"` | `--check` exit 0 |
| `t47_cap_sibling_independence` | **Check 1 (§2.8) — siblings checked independently** — `Cap(IO.FileRead)` and `Cap(IO.FileWrite)` (siblings under `IO.FileSystem`, neither subsumes the other) each covered by its OWN `needs` line; proves Check 1 walks each used `Cap(X)` separately, no cross-sibling subsumption | `--check` exit 0 |
| `t48_cap_midtier_subsumption` | **Check 1 subsumption (§2.8) — a second, mid-tier shape** — `Cap(IO.NetConnect)` param covered by `needs IO.Network` (`IO.NetConnect`'s direct parent), one tier down from t46's root-covers-all shape; historically documented the corpus-scoping finding that only 10/18 hierarchy entries were valid `Cap(X)` type arguments (`builtin_types`, `typecheck.ml`) — now RESOLVED (F6, 2026-07-07): all 18 are registered, see `accept/t57` | `--check` exit 0 |
| `t49_transitive_use_covered` | **Check 4 (§2.8.6, capabilities widening Task 2) — transitive `use` coverage** — `Main` declares `needs IO.Mut` and `use`s the real stdlib module `Vault` (`stdlib/vault.march:26`, `needs IO.Mut`); Check 4 (`typecheck.ml:5661`) looks up `Vault`'s declared caps in `env.module_caps` and confirms `Main`'s own `needs IO.Mut` covers it (reflexive subsumption) | `--check` exit 0 |
| `t50_extern_cap_and_foreign_covered` | **Check 5 + Check 1c (§2.8.6, capabilities widening Task 2) — extern block, both obligations covered** — `Bindings` declares `needs IO.Foreign` and `needs IO.FileSystem`, then an `extern "libc" : Cap(IO.FileSystem) do ... end` block; Check 5 (`typecheck.ml:5684`, ERROR) confirms the extern's own declared `Cap(IO.FileSystem)` is covered, Check 1c (`typecheck.ml:5607`, WARNING) confirms the blanket `IO.Foreign` implication is covered — neither fires | `--check` exit 0 |
| `t51_cap_narrow_thread` | **`cap_narrow`/`root_cap` threading (§2.8.8, capabilities widening Task 3) — narrow-then-thread-to-a-stricter-callee** — `boot(root : Cap(IO))` narrows its ambient `Cap(IO)` via `cap_narrow(root)` to `Cap(IO.Network)` and passes the narrowed value to `listen`, whose signature demands the stricter sub-capability; both `Cap(IO)` and `Cap(IO.Network)` are covered by the single module-level `needs IO` (Check 1 subsumption, §2.8.3) — `cap_narrow` changes the STATIC TYPE of the threaded value, not what `needs` must cover | `--check` exit 0 (STABLE across 40+ repeated runs; the Check 3 narrowing HINT on `boot`'s own `Cap(IO)` param is FLAKY on this exact program shape — present roughly 1-in-10 runs, byte-identical binary and input — a live-observed nondeterminism (the flaky narrowing-HINT finding, filed in `specs/todos.md`, documented in core-march-types.md §2.8.10 — not a §4.1 numbered entry); it never affects the exit code) |
| `t52_cap_narrow_multi` | **`cap_narrow`/`root_cap` threading (§2.8.8) — a second shape: `root_cap` read directly, narrowed twice to two sibling sub-caps** — `main` (no `Cap(X)` parameter of its own) reads `root_cap` and calls `cap_narrow` twice, minting an independently-typed `Cap(IO.Console)` and `Cap(IO.FileRead)` token from the same root, each threaded to its own callee. Proves narrowing composes and that a plain `root_cap` read needs no ambient parameter | `--check` exit 0 (no diagnostics at all — `main`'s signature carries no `Cap(X)`, so Check 3's narrowing HINT does not fire here) |
| `t53_migrate_pure_needs_io` | **Check 8 (§2.8.9, capabilities widening Task 3) — the caveat-mitigation ACCEPT witness** — `Counter` declares `needs IO.Console` (for its `actor CounterActor`'s `on Inc` handler, which calls `println`) and a SIBLING top-level `fn counter_migrate_state(old) do old end` (pure, no `actor` nesting — migrate-state fns are ordinary `DFn`s recognized purely by the `_migrate_state` name suffix, `typecheck.ml:5368-5378`). Check 8 consults `env.own_cap_closures` (own caps only, excluding `module_wide_caps`), so the module's `needs IO.Console` does NOT get folded into the migrate fn's own-caps closure — no false blame | `--check` exit 0 |
| `t54_cap_pure_arithmetic` | **`cap pure` (§2.8.11, capabilities widening Task 4) — the ACCEPT side** — `add`/`scale` call only each other and `+`/`*`; neither appears in `pure_banned` (`typecheck.ml:6570-6576`), so `check_pure_module` finds nothing to flag. Deliberately chosen to remain valid across the F2 fix (Task 5 of this slice rebuilds `pure_banned` from `builtin_cap_table`) — plain arithmetic and an internal call are not, and will never become, members of any effectful-builtin set | `--check` exit 0 |
| `t55_cap_no_alloc_arithmetic` | **`cap no_alloc` (§2.8.11, capabilities widening Task 4) — the ACCEPT side** — `max3`'s nested `if`/`else` and `abs_diff`'s `let` + arithmetic negation touch none of the four allocating shapes `no_alloc.ml:20-37` flags (non-empty `ETuple`, `ERecord`, `ECon` with args, `ELam`) | `--check` exit 0 |
| `t56_cap_no_extern_ok` | **`cap no_extern` (§2.8.11, capabilities widening Task 4) — the ACCEPT side** — no `DExtern` block and no `needs` path starting `IO.Foreign`; `needs IO.Network` plus a plain `Cap(IO.Network)`-taking `fn` trips neither of `check_no_extern_module`'s two raise sites (`typecheck.ml:6604-6628`) | `--check` exit 0 |
| `t57_cap_all_hierarchy_args` | **F6 FIX witness (fix-campaign, 2026-07-07) — all 18 capability-hierarchy roots are now valid `Cap(X)` type ARGUMENTS** — `builtin_types` (`typecheck.ml`) registered only 10 of the 18 `IO.*` entries as 0-arity type names, so `Cap(IO.Random)`/`Cap(IO.Mut)`/`Cap(IO.Foreign)`/`Cap(IO.Telemetry)` (all valid `needs` targets) were rejected `` Unknown module `IO` ``. The missing 8 (`IO.Random`, `IO.Database`, `IO.Spawn`, `IO.Mut`, `IO.Telemetry`, `IO.Foreign`, `IO.Foreign.Blocking`, `IO.NetConnect.TLS`) are now registered, mirroring the full 18-entry hierarchy in `lib/caps/cap_lattice.ml:15-33`. This witness types four of the newly-registered roots as `Cap(X)` params with matching `needs` lines. Flips the `reject/t48` note ("only 10/18 valid today") to resolved | `--check` exit 0 |
| `t58_revoke_cap_typechecks` | **fix-campaign (2026-07-07) — `revoke_cap`/`is_cap_valid` are now typecheck-registered builtins** — both are `eval.ml` epoch-plane builtins (`eval.ml:3164`/`:3172`) but had NO entry in the typecheck builtin table (only `get_cap`/`send_checked` were present, `typecheck.ml:1486-1487`), so surface `revoke_cap(cap)` was rejected `` I cannot find `revoke_cap` ``. Registered as `revoke_cap : Cap(a) -> Atom` (returns the `:ok` atom) and `is_cap_valid : Cap(a) -> Bool`, mirroring `get_cap`'s `poly1` form. Witness spawns an actor (fresh-var `Pid`, cf. `accept/t39`), `get_cap`s it, then exercises both new builtins on the `Cap(a)` payload | `--check` exit 0 |
| `t59_cap_no_panic_guarded_guardless_catchall` | **guarded-match exhaustiveness fix, ACCEPT side (fix-campaign batch 3, 2026-07-07)** — a `cap no_panic` module whose guarded `match` (`Some(v) when v > 0 -> v`) is followed by an UNGUARDED `Some(v) -> …` and `None -> …`, so the GUARDLESS branches `{Some, None}` cover the whole `Option(Int)` domain. `check_exhaustiveness` computes coverage over the guardless matrix, finds it exhaustive, records nothing, and `check_no_panic_module` has no span to promote. Proves the fix is not over-rejecting every guarded match. Reject companion: `reject/t50` (drop the unguarded `Some(v)`). See `core-march-types.md` §2.8.11 + §2.1a | `--check` exit 0 |
| `t60_nested_id_polymorphic` | **P0 nested-module soundness fix, ACCEPT side (widening slice 6, §2.8.13 / (T-QualRef), 2026-07-08)** — a nested unannotated `fn id(x) do x end` used at BOTH `Int` and `String` in the same nested module. The positive counterpart to `reject/t51`–`t54`: pre-fix the stale qualified-prebind placeholder pinned `id` to its FIRST use, so a second use at a different type spuriously ERRORED (`id` was accidentally monomorphic). The fix reconciles the qualified key to `id`'s real body-checked scheme `a -> a`, RESTORING let-polymorphism while closing the launder — an independent witness the fix neither over-restricts nor over-monomorphises | `--check` exit 0 |
| `t61_cap_narrow_io_narrow_still_ok` | **cap_narrow regression guard (widening slice 6, §2.8.13, 2026-07-08)** — the Batch-A restriction (`reject/t55`) rejects a `cap_narrow` whose result is a nominal PROOF cap, but ordinary IO-lattice narrowing must stay accepted: `boot` narrows `Cap(IO)` to `Cap(IO.Network)` via `cap_narrow` and threads it to `use_net`. `IO.Network` is an IO-permission cap, NOT in `env.proof_caps`, so the proof-cap restriction never fires. Proves Part 1 did not break least-privilege IO threading | `--check` exit 0 |
| `t62_mint_cap_public_declaring` | **the legit proof-cap mint (widening slice 6, §2.8.13, 2026-07-08)** — `Db`'s own PUBLIC (`fn`) `run_migrations` mints its own `Cap(Db.Migrated)` via `mint_cap`; `mint_cap(x) : Cap(P)` typechecks iff `P`'s declaring module == the enclosing module AND the enclosing fn is public. Check 6's self-declaration exemption + Check 1's proof-cap self-declaration mean `Db` needs no `needs Db.Migrated`. Accept counterpart to `reject/t56` (external) and `reject/t57` (pfn) — the mint surface is exactly the declaring module's public fns; runtime-erased (aliases `cap_narrow`) | `--check` exit 0 |
| `t63_proof_cap_passthrough` | **proof-cap pass-through (widening slice 6, §2.8.13, 2026-07-08)** — external code cannot MINT a proof cap but CAN receive one as a parameter and pass it through: `App` (non-declaring) declares `relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end`, satisfying Check 6 (the returned cap IS in the parameter caps) with `needs Db.Migrated` for Check 1. Receive-and-pass-through is one of the only two ways to obtain a `Cap(P)` (the other is `mint_cap` in the declaring module's public fns, `t62`) | `--check` exit 0 |
| `t64_linear_let_single_use` | **(T-LinMark)/(T-LinUse)/(T-LinDrop) positive (linearity widening slice 7, §2.9.1-§2.9.2, 2026-07-10)** — a `linear let r : Res = R(1)` consumed exactly once (`take(r)`); the single use satisfies both the immediate double-use check and the scope-close must-consume check | `--check` exit 0 |
| `t65_linear_param_single_use` | **(T-LinMark) fn-param surface positive (slice 7, §2.9.1)** — `fn good(linear q : Res)` whose body consumes `q` exactly once; the param is registered Linear at `bind_fn_param` and (T-LinDrop) at fn-body close is satisfied | `--check` exit 0 |
| `t66_affine_ty_param_drop` | **(T-AffDrop) positive (slice 7, §2.9.2)** — an unused `c : affine Cap2` param typechecks: `check_linear_all_consumed` filters to `Linear` only, so affine values may be silently dropped. Also pins the WORKING affine spelling (type-modifier `c : affine T`) — the param-keyword form `fn ok(affine c : T)` is a PARSE error (finding L1) | `--check` exit 0 |
| `t67_linear_field_arith_single` | **(T-LinCoerce) positive, REQUIRES the L2 fix (slice 7, §2.9.4, fixed 2026-07-10)** — `p.data + 1` on a `linear data : Int` record field: a single, linearity-correct arithmetic use. Pre-fix, constraint discharge did not strip the `TLin` wrapper and rejected this with `` `linear Int` does not implement Num `` before the tracker ever ran — IMPOSSIBLE to accept pre-fix | `--check` exit 0 |
| `t68_linear_send_consumes` | **(T-LinUse) send-consumes positive (slice 7, §2.9.2)** — `send(pid, StoreRes(r))` with `linear let r`: the payload `EVar` is an ordinary consuming use, so a linear value MAY be sent to an actor (corrects the tutorial's former "cannot be sent" claim, finding L6). Reject twin: `reject/t66` (use after send). Ctor named `StoreRes` to dodge the flat-namespace collision with stdlib `Method.Put` | `--check` exit 0 |

## `reject/` — must be rejected (exit 1 + pinned substring)

| Program | Anchors | `EXPECT-ERROR` substring |
|---|---|---|
| `t01_int_vs_string` | unification mismatch | `` expected `Int` but got `String` `` |
| `t02_unbound_var` | T-Var, `x ∉ Γ` | `` I cannot find `undefined_var` `` |
| `t03_arity` | T-App arity (no partial application) | `expects 1 argument, but got 2` |
| `t04_if_branch_mismatch` | T-If branch unification | `Both branches of an if expression must return the same type` |
| `t05_ctor_arity` | T-Con arity (`ECon` arm) | `` Constructor `Circle` expects 1 argument(s) but I got 2. `` |
| `t06_match_branch_mismatch` | T-Match branch-body unification | `All branches of a match must have the same type.` |
| `t07_field_missing` | T-Field "no such field" (`EField` arm) | `` This record does not have a field called `z`. `` |
| `t08_tuple_arity_mismatch` | T-Tuple/unify length mismatch, via a `(Int,Int)`-annotated param checked against a 3-tuple | `` expected `(Int, Int)` but got `(Int, Int, Int)`. `` |
| `t09_record_update_missing_field` | T-Update "no such field" (concrete-`TRecord` base) | `` This record does not have a field called `z`. `` |
| `t10_guard_not_bool` | (T-Guard) non-Bool guard (`n when n + 1 -> …`) | `Match guards must be Bool.` |
| `t11_econd_condition_not_bool` | (T-Cond) non-Bool condition (bare `n -> …` where `n : Int`) | `` Each condition in `match do` must be Bool. `` |
| `t12_letfn_ret_annot_conflict` | (T-LetFn) declared return-type annotation (`fn go(k) : Int`) conflicts with the self-consistent inferred `String` body | `` expected `Int` but got `String` `` |
| `t13_num_no_impl_string` | (T-Discharge, `CNum`) — `x + y` on two agreeing `String`s, violating `+`'s own `Num` obligation at the enclosing `fn`'s discharge point | `String does not implement Num (only Int and Float do)` |
| `t14_ord_no_impl_adt` | (T-Discharge, `CInterface "Ord"`) — `a < b` on a bare 2-ctor ADT with no `impl Ord` | `` `Hue` does not implement interface `Ord` `` |
| `t15_and_non_bool_operand` | (δT-And) — `1 && true`, an `Int` operand against `&&`'s fixed `Bool → Bool → Bool` | `March does not coerce Int to Bool` |
| `t16_let_annot_mismatch` | **(T-Let annotation, finding 16 fix)** — `let x : Int = "foo"` now rejects (the annotation is a checking context for the RHS) | `` expected `Int` but got `String`. `` |
| `t17_generic_when_constraint_unsatisfied` | **(T-Discharge via instantiate, finding 15 fix)** — `same(Rood, Rood)` with `fn same(a, b) when Eq(a)` on a no-`Eq` ADT now rejects | `` `Hue` does not implement interface `Eq`. `` |
| `t18_impl_missing_method` | (T-Impl) missing required method — an interface with two methods, an impl providing only one (no default on the omitted one) | `` Missing method `greet` in `impl Speak(Dog)`. `` |
| `t19_impl_extra_method` | (T-Impl) extra undeclared method — an impl provides a method the interface never listed | `` Interface `Speak` does not declare a method `bark`. `` |
| `t20_impl_signature_mismatch` | (T-Impl) signature-match — a provided method's inferred body type disagrees with the interface's declared signature | `` `speak` in `impl Speak` must match the interface signature `` |
| `t21_impl_unknown_interface` | (T-Impl) interface-existence — `impl` of an interface name never declared with `interface` | `` Unknown interface `NotDeclared` — is it declared above this impl? `` |
| `t22_impl_superclass_unsatisfied` | **(T-Impl) superclass discharge, unsatisfied** — `interface Greet(a) requires Speak(a)`, `impl Greet(Dog)` declared with no `impl Speak(Dog)` anywhere in scope — mandatory rejection, not a conditional gap | `` Cannot implement `Greet(Dog)`: required superclass `Speak(Dog)` is not satisfied. `` |
| `t23_derive_unknown_interface` | (§2.4) `derive` targets a CLOSED five-interface set — `derive Frobnicate for Color`, an interface name outside `{Eq, Show, Hash, Ord, Json}` | `` Unknown derive target `Frobnicate` for type `Color`. `` |
| `t24_satisfy_missing_function` | (§2.4) `satisfy` all-or-nothing — `satisfy Named for Person` where no top-level `fn name` exists anywhere in the module | `` satisfy Named for Person: no function `name` found in scope. `` |
| `t25_private_nested_member` | same-file qualified reference to a PRIVATE nested-module member — `mod A do pfn secret() … end` referenced as `A.secret()` from a sibling in the same file; the private member is never exported, but the diagnostic must name the real cause, not report the plainly-present module as absent | `` Function `secret` is private to module `A`. `` |
| `t26_cross_module_private_fn` | **module visibility — the REJECT side (slice 2, Task 1)** — `Array.lst_rev(...)`, a real private `pfn` (stdlib/array.march:39), is no longer callable by qualification from unrelated code; `load_module_into_env`'s new `ex_public` gate for `ExFn`/`ExValue` makes the qualified lookup miss, so `qualified_error_msg` reports the private-access message (the same shape the `ExCtor` gate already produced for private constructors) | `` is private to module `Array` `` |
| `t27_use_selector_private_name` | **`use`/`import` operational rules (§4.7.1, slice 2 Task 4) — selective `use` of a PRIVATE name** — `use Array.{lst_rev}`, a selective import of the same real private `pfn` `t26` exercises via plain qualification; `DUse`'s `UseNames` arm looks up `"Array.lst_rev"` in `env.vars`, misses (the SAME `pub_set` absence `t26` hits), and raises the "does not export" message rather than `t26`'s "is private to" message — different text, identical underlying gate, consistent with Task 1's fix | `` Module `Array` does not export `lst_rev`. `` |
| `t28_spawn_computed_actor` | **actor `spawn` typing (§2.6, actors slice Task 1) — computed actor expression rejected** — `spawn(pick())`, a FUNCTION-CALL actor argument rather than a literal name; the `ESpawn` arm (`typecheck.ml:4185`) accepts only the bare-name shapes `ECon(_,[],_)`/`EVar` (`:4194–4202`) and rejects everything else at `:4197–4202`, because `spawn` is resolved to a static `<Actor>_spawn` at compile time (no runtime actor value). `spawn(if … end)` / `spawn(A(x))` reject identically | `` `spawn` needs a plain actor name written directly, like `spawn(Counter)`. `` |
| `t29_actor_send_wrong_payload` | **actor message-payload typing (§2.6.4, actors slice Task 3) — wrong-payload-shape send rejected** — `send(counter, Inc("not an int"))` where the handler is `on Inc(x : Int)`; the `ESend` arm types the message via ordinary `ECon` constructor typing (`infer_expr env msg`, `typecheck.ml:4179`), so the `String` argument fails to unify with the `Inc` constructor's `Int` payload type. Proves message-payload SHAPE is statically checked (the complement of §4.1 finding 19: message ACCEPTANCE by the target actor is NOT — `send` discards the target Pid's type at `:4178`) | `` expected `Int` but got `String`. `` |
| `t30_send_at_recv_state` | **channel-op session typing (§2.7.8, session-types widening Task 3) — send-at-wrong-state** — `Chan.send` called twice in a row on the same protocol thread with no intervening `recv`; the second call's channel argument is at `Recv(Int, End)` (the peer's expected next move), not `SSend(T,S)` — `Chan.send`'s arm (`typecheck.ml:3479`) requires `SSend` and rejects any other state | `` Chan.send: channel is at `Recv(Int, End)` but I expected `Send(T, ...)`. `` |
| `t31_close_before_end` | **channel-op session typing (§2.7.8, session-types widening Task 3) — close-before-`End`** — `Chan.close` called on the receive endpoint before its matching `Chan.recv` has run, so the channel is still at `Recv(Int, End)`, not `SEnd`; `Chan.close`'s arm (`typecheck.ml:3537`) requires `SEnd` | `` Chan.close: channel is at `Recv(Int, End)` but I expected `End`. `` |
| `t32_invalid_choose_label` | **channel-op session typing (§2.7.8, session-types widening Task 3) — invalid `choose` label** — `Chan.choose(cc, :maybe)` on a `Decision` protocol whose only declared branches are `:ok`/`:err`; `Chan.choose`'s arm (`typecheck.ml:3564`) requires the label to name a declared branch (`List.assoc_opt`) | `` Chan.choose: label `:maybe` is not a valid branch of this protocol. `` |
| `t33_wrong_payload_type` | **channel-op session typing (§2.7.8, session-types widening Task 3) — wrong payload type** — `Chan.send(cc, "not an int")` where the protocol declares `Client -> Server : Int`; `Chan.send`'s arm `check_expr`s the payload against the session's declared `T` (`typecheck.ml:3479–3482`) via the ORDINARY constructor/type-mismatch path, not a session-specific message — proves payload SHAPE is checked, not just session STATE | `` expected `Int` but got `String` `` |
| `t34_recv_at_wrong_state` | **channel-op session typing (§2.7.8, session-types widening Task 3) — recv-at-wrong-state** — `Chan.recv(cc)` called on the Client endpoint of `Echo` immediately after `Chan.new`, while `cc` is still at `Send(Int, Recv(Int, End))` (the first op must be a send); `Chan.recv`'s arm (`typecheck.ml:3509`) requires `SRecv` | `` Chan.recv: channel is at `Send(Int, Recv(Int, End))` but I expected `Recv(T, ...)`. `` |
| `t35_linear_used_twice` | **channel-op linearity (§2.7.8, session-types widening Task 3) — linear channel continuation used twice** — `Chan.close(cc2)` called twice on the same `let`-bound continuation; channel endpoints are `TLin (Linear, TChan ...)` (§2.7.6), and double-use of a `let`-bound linear value is caught by the GENERIC linear tracker, not session-specific accounting (same diagnostic shape as any other linear value used twice) | `` The linear value `cc2` is used more than once here. `` |
| `t36_cap_sig_uncovered` | **Check 1 (§2.8, capabilities widening Task 1) — the base rejection** — `Cap(IO.Network)` param, no `needs` declared at all, so `declared_needs = []` covers nothing | `` is not declared in `needs` `` |
| `t37_cap_narrow_does_not_cover_broad` | **Check 1 (§2.8) — subsumption is directional, not symmetric** — module declares the NARROW `needs IO.Network`, signature uses the ROOT `Cap(IO)`; `cap_subsumes "IO.Network" "IO"` is false (a child never covers its own parent). Also emits a Check 3 narrowing HINT ahead of the ERROR | `` `Cap(IO)` used in module `Server` but `IO` is not declared in `needs` `` |
| `t38_cap_sibling_does_not_cover_sibling` | **Check 1 (§2.8) — one more violation: siblings don't cover each other** — module declares only `needs IO.FileRead`; `save`'s signature uses `Cap(IO.FileWrite)` (a sibling under `IO.FileSystem`), uncovered. Companion to `accept/t47`, which declares both siblings and accepts | `` `Cap(IO.FileWrite)` used in module `Store` but `IO.FileWrite` is not declared in `needs` `` |
| `t39_transitive_use_missing_cap` | **Check 4 (§2.8.6, capabilities widening Task 2) — transitive `use` coverage, REJECT side** — companion to `accept/t49` with the covering `needs IO.Mut` line removed: `Main` `use`s `Vault` (`needs IO.Mut`) but declares no `needs` of its own, so `declared_needs = []` covers nothing; Check 4 raises an ERROR (not a warning) | `` module `Main` imports `Vault` which requires `Cap(IO.Mut)`, but `IO.Mut` is not declared in `needs` `` |
| `t40_migrate_state_does_io` | **Check 8 (§2.8.9, capabilities widening Task 3) — the REJECT side** — companion to `accept/t53` with the migrate fn's body changed to call `println` (`IO.Console` in `builtin_cap_table`); `counter_migrate_state`'s own capability closure is now non-empty, so Check 8 raises regardless of the module's `needs IO.Console` declaration | `` migrate_state must be IO-free `` |
| `t41_realtime_excludes_cap_io` | **Check 7 (§2.8.9, capabilities widening Task 3) — realtime exclusion** — a user-declared nullary `type Realtime = Realtime` (needed because `Realtime` is not itself pre-registered in `builtin_types`) makes `Tagged(Int, Realtime)` resolve as a surface type; `step`'s signature combines it with `Cap(IO)`, one of the three excluded roots (`Alloc`/`IO`/`Panic`); Check 7 (`is_realtime_tagged`/`is_excluded_cap`, `typecheck.ml:5760-5765`) matches on the type NAME, so a user-declared `Realtime` trips it exactly like a built-in one would | `` takes `Tagged(_, Realtime)` but also takes `Cap(IO)` `` |
| `t42_cap_no_panic_explicit_panic` | **`cap no_panic` (§2.8.11, capabilities widening Task 4) — the most direct panic surface** — `fail`'s body calls `panic` directly; `panic` is a member of `panic_surface_direct` (`typecheck.ml:6408-6414`), matched with no fixpoint/transitive step needed | `` calls `panic`, which can panic `` |
| `t43_cap_no_alloc_tuple` | **`cap no_alloc` (§2.8.11, capabilities widening Task 4) — non-empty tuple construction** — `make_pair`'s `(a, b)` return allocates a 2-tuple; `check_expr`'s `ETuple` arm (`no_alloc.ml:20-24`) special-cases only the EMPTY tuple `()` as non-allocating | `` tuple construction allocates in a `cap no_alloc` module `` |
| `t44_cap_no_extern_extern_block` | **`cap no_extern` (§2.8.11, capabilities widening Task 4) — an `extern` block present** — `check_no_extern_module`'s `DExtern` arm (`typecheck.ml:6608-6612`) raises unconditionally on any extern block, regardless of whether its own Check 5/1c obligations are separately satisfied (they are, here — `needs IO.FileSystem` covers Check 5 cleanly; only a WARNING-level Check 1c diagnostic about the missing `needs IO.Foreign` fires alongside, not the pinned substring) | `` contains an `extern` block `` |
| `t45_cap_pure_file_write` | **`cap pure` (§2.8.11, capabilities widening Task 5 — F2 FIX witness) — the REAL effectful builtin `file_write`** — `check_pure_module` (`typecheck.ml:6645`) now bans every builtin in `builtin_cap_table` (`:1012`), which the F2 fix DERIVES `pure_banned` from instead of the pre-fix hand-guessed list that spelled the nonexistent `write_file` and missed `file_write` (mapped `IO.FileWrite`, `:1028`). Type-correct (`file_write : String -> String -> Result(Unit, r)`, signature `Result(Unit, String)`) so the ONLY rejection is the cap ban, not a type mismatch. Accepted (exit 0) pre-fix — this witness was impossible until Task 5 | `` which has side effects `` |
| `t46_cap_pure_random_bytes` | **`cap pure` (§2.8.11, capabilities widening Task 5 — F2 FIX witness) — the RNG builtin `random_bytes`** — `random_bytes` (mapped `IO.Random`, `typecheck.ml:1077`) is now in the table-derived `pure_banned`; pre-fix `pure_banned` spelled the nonexistent `random_int`/`random_float`/`random_bool` and missed the real `random_bytes`. `random_bytes : Int -> Bytes` is total, so `: Bytes` is type-correct and the ONLY rejection is the cap ban. Accepted (exit 0) pre-fix | `` which has side effects `` |
| `t47_cap_deterministic_unix_time_ms` | **`cap deterministic` (§2.8.11, capabilities widening Task 5 — F2 FIX witness) — the wall-clock builtin `unix_time_ms`** — `check_deterministic_module` (`typecheck.ml:6710`) now bans exactly the builtins `builtin_cap_table` maps to a NONDETERMINISM cap (`IO.Clock`/`IO.Random`, via `is_nondeterministic_cap`); `unix_time_ms` (mapped `IO.Clock`, `:1074`) is now caught, where pre-fix `deterministic_banned` spelled the nonexistent `now_ms` and missed it. `unix_time_ms : Unit -> Int` so `unix_time_ms(())` at `: Int` is type-correct. `cap deterministic` stays WEAKER than `cap pure` (a deterministic module may still `file_read`) — only clock/RNG are banned. Accepted (exit 0) pre-fix | `` which is non-deterministic `` |

| `t48_cap_no_panic_nonexhaustive_match` | **`cap no_panic` (§2.8.11, capabilities widening Task 6 — F3 FIX witness) — the match-non-exhaustiveness panic surface** — a non-exhaustive `match` lowers to a runtime "no matching clause" panic, so a `cap no_panic` module must reject it just like an explicit `panic` (cf. `reject/t42`). `check_exhaustiveness` (`typecheck.ml`) already finds every non-exhaustive match; besides the usual Warning it now records the offending `match`'s span into `env.nonexhaustive_match_spans` (a shared ref). `check_no_panic_module` (runs ONLY for `cap no_panic` modules) reads that side-table and, for any recorded span nested (via `span_within` containment) inside one of THIS module's own function bodies, reports an ERROR. A non-exhaustive match in a PLAIN module stays a non-blocking Warning (`accept/t14`), so the fix is scoped to `cap no_panic`. Accepted (exit 0) pre-fix | `` contains a non-exhaustive `match`, which panics at runtime `` |
| `t49_derive_unknown_type` | **finding 17 FIX witness (fix-campaign, 2026-07-07) — `derive X for UnknownType` now ERRORs instead of silently no-opping** — `expand_derive` (`desugar.ml`) previously returned a bare `[]` when the derive TARGET TYPE was absent from the module's `type_defs`, emitting no diagnostic, so `derive Show for NoSuchType` typechecked clean (exit 0) — a misspelled type name was indistinguishable from a no-op. The `None` branch now mirrors its sibling (unknown derive INTERFACE) and emits an `Err.error` at the type-name span before returning `[]`. Accepted (exit 0) pre-fix | `` Unknown type `NoSuchType` in `derive` `` |
| `t50_cap_no_panic_guarded_nonexhaustive` | **guarded-match exhaustiveness fix (fix-campaign batch 3, 2026-07-07) — the GUARDED-match panic surface** — a `cap no_panic` module whose `match opt do Some(v) when v > 0 -> v; None -> 0 end` has GUARDLESS arms `{None}` alone (non-exhaustive, missing an unguarded `Some`); when the `when v > 0` guard fails at runtime no arm matches and the match panics. A `when` guard used to short-circuit `check_exhaustiveness` entirely (`if has_guards then ()`), so this was invisible to both the ordinary Warning and F3's error path (accepted exit 0, zero diagnostics). The fix computes coverage over the GUARDLESS branches only and records the span when they are non-exhaustive; `check_no_panic_module` promotes it to an ERROR — no global Warning (only `cap no_panic` modules opt in). Accept companion: `accept/t59` (adds an unguarded `Some(v)`). IMPOSSIBLE to reject pre-fix. See `specs/todos.md` (guarded-match gap → Done), `core-march-types.md` §2.8.11 + §2.1a | `` contains a non-exhaustive `match`, which panics at runtime `` |
| `t51_nested_id_launder_int_to_string` | **P0 nested-module type-erasure fix — the HEADLINE memory-safety witness (widening slice 6, §2.8.13 / (T-QualRef), 2026-07-08)** — an UNANNOTATED public `fn id` in a NESTED `mod` launders an `Int` through to a `String` param. Pre-fix, the nested fn's qualified name (`App.id`) kept a stale `Mono` placeholder that `check_decl` reconciled only under the BARE name, so a sibling resolving the desugar-qualified `App.id` got a decoupled `?a -> ?b` that ERASED the laundered type — `takes_str(id(42))` typechecked (exit 0), a genuine memory-safety break. The fix reconciles every qualified fn key to the fn's real body-checked scheme. Uses `string_length` (a real `String -> Int` builtin), NOT `String.length`. IMPOSSIBLE to reject pre-fix | `` expected `String` but got `Int` `` |
| `t52_nested_id_launder_box` | **P0 nested-module fix — ADT-arg witness (widening slice 6, §2.8.13, 2026-07-08)** — the same nested `id`-launder as `t51` but on an ADT payload: `Box("hi") : Box(String)` coerced to `Box(Int)`, then read as an Int (`n + 1`). The decoupled placeholder erased the ADT argument's type just as it erased base types. IMPOSSIBLE to reject pre-fix | `` expected `Int` but got `String` `` |
| `t53_nested_distinct_tvar_launder` | **P0 nested-module fix — distinct-tvar annotation witness (widening slice 6, §2.8.13, 2026-07-08)** — a nested `fn launder(x : a) : b do x end` declares two DISTINCT signature tvars, so its prebound scheme (built from annotation SYNTAX, `a -> b`) is never unified against the body constraint `a ~ b`; pre-fix (round-2 of the fix) this un-body-validated annotation scheme was left intact and laundered `Int`→`String`. The fix binds every qualified key to `check_fn`'s real body-checked scheme (forcing `a = b`). IMPOSSIBLE to reject pre-fix | `` expected `String` but got `Int` `` |
| `t54_entry_self_qualified_launder` | **P0 nested-module fix — ENTRY-module variant (widening slice 6, §2.8.13, 2026-07-08)** — the same launder through the entry module's own top-level fn referenced by its SELF-QUALIFIED name `Main.id`. The entry module seeds its own unannotated fns under a self-qualified key while the nested-prefix accumulator is empty, so the round-2 nested reconcile (gated `cap_qual_prefix <> ""`) excluded it; `Main.id(42)` erased `Int`→`String` (exit 0). Bare `id` was always safe; only the written `Main.id` form triggered. The fix (round 3) reconciles BOTH the `cap_qual_prefix` and `current_module` keys. IMPOSSIBLE to reject pre-fix | `` expected `String` but got `Int` `` |
| `t55_cap_narrow_forges_proof_cap` | **cap_narrow proof-cap FORGE, now closed (widening slice 6, §2.8.13, 2026-07-08)** — `cap_narrow : Cap(IO) -> Cap(a)` instantiated `a := Db.P` at an inline call-argument position (which Check 6's declared-return scan structurally cannot see), letting any holder of a plain `Cap(IO)` forge a nominal proof cap by name (exit 0 pre-fix). The Batch-A fix restricts `cap_narrow`: its result may NEVER be a nominal proof cap in ANY position; IO-lattice narrowing is unaffected (`accept/t61`) and proof caps are minted only via gated `mint_cap` (`accept/t62`). IMPOSSIBLE to reject pre-fix | `cap_narrow cannot produce` |
| `t56_mint_cap_external_module` | **mint_cap unforgeability — external module (widening slice 6, §2.8.13, 2026-07-08)** — `App` (non-declaring) tries to `mint_cap` a `Cap(Db.P)` in a fn's declared RETURN position, so Check 6 (declared-return-type pass-through discipline) fires: `App` did not receive the cap as a parameter and is not `Db`, so it may only pass through, never construct. Accept counterpart `accept/t62` (the same mint INSIDE `Db`'s public fn accepts) | `Only public functions of` |
| `t57_mint_cap_pfn_declaring` | **mint_cap gated to PUBLIC declaring fns (widening slice 6, §2.8.13, 2026-07-08)** — the mint surface is exactly the PUBLIC (`fn`) functions of the declaring module; a `pfn` (private) of the declaring module is NOT a mint surface. `Db`'s own `pfn run_migrations` minting its own `Cap(Db.Migrated)` is rejected by Check 6's private-in-declaring-module branch. Making the fn public is exactly `accept/t62` | `Only public functions of` |

**Result: 125 / 125 (68 accept, 57 reject).**

## Coverage notes (deliberately absent programs, and why)

- **No atom-specific `reject/` program.** Every `EAtom`/`PatAtom` occurrence
  synthesizes the single bare `Atom` type (T-Atom-0/T-Atom-N, P-Atom) — there
  is no per-tag/per-arity typing distinction to violate, so atoms cannot
  originate a type error in isolation (a payload sub-expression error, e.g.
  `:count(1 + "x")`, comes from `+`'s own `Num` constraint, already covered).
  See `core-march-types.md` §3.
- **No polymorphic-recursion `reject/` program.** Verified live during Task 5
  (a local `fn go(x)` recursively calling itself at `Int` then `String`
  fails), but not committed as a corpus program — it would restate
  `reject/t01`'s ordinary T-App mismatch shape rather than add new coverage.
  See `core-march-types.md` §2 (T-LetFn).
- **No `reject/` program for finding 15 (the `when Iface(a)` constraint-
    survival gap) or finding 16 (the `let`-annotation-ignored gap).** Both are
  real, filed typechecker gaps (`specs/todos.md`, "Compiler: Type System") —
  but a `reject/` program encoding either would assert a behavior this
  document identifies as WRONG (the program currently, incorrectly,
  typechecks), which would defeat the corpus's purpose of pinning CORRECT
  behavior. Once each is fixed, a `reject/` witness should be added here (see
  `core-march-types.md` §4.1, findings 15–16, for the exact repros to convert).
- **No exhaustiveness/redundancy `reject/` program.** Both are Warnings, never
  Errors (`--check`'s exit code filters strictly on `severity = Error`), so a
  non-exhaustive/redundant `match` can never produce a passing `reject/`
  program under this harness — `accept/t14_nonexhaustive_match_still_
  typechecks` is the (correct) witness that this is so. See
  `core-march-types.md` §2 "Exhaustiveness and redundancy" and §4.1 finding 9.
- **No `reject/` program for a duplicate `interface` declaration or an
  interface method that never mentions its own type parameter.** Both are
  real gaps in the `(T-Interface)` arm (§2.3): a second `interface Speak(a)`
  in the same module silently replaces the first in `env.interfaces`
  (ordinary `StrMap.add`, no "already declared" check), and a method signature
  like `fn bar : Int -> Int` inside `interface Foo(a) do ... end` — which never
  uses `a` at all — still typechecks with `CInterface(Foo, a)` attached to an
  otherwise-free variable. Neither is committed as a corpus program: both are
  narrow, low-value-to-pin edge cases (flagged, not fixed, in this task) rather
  than confirmed regressions worth a dedicated `reject/` witness. See
  `core-march-types.md` §2.3.
- **No coherence/overlap corpus entry here.** Two impls of the same interface
  for the same type both typecheck with no diagnostic (`env.impls`'s
  "insert-only, search by structural match" registration shape, §2.3 item 1) —
  this is a genuine divergence between the interpreter and compiled backends
  at RUNTIME, not a `--check`-time accept/reject distinction, so it cannot be
  encoded in this harness at all (a `--check` program cannot witness an
  interp-vs-compiled split). Documented and filed as its own task's subject
  (`core-march.md`'s dispatch/coherence section, `specs/todos.md`).
- **No `reject/` program for a multi-argument superclass or `when` constraint.**
  Both the superclass-discharge and `when`-clause-discharge steps (§2.3,
  typecheck.ml:7086–7103, 7118–7143) only handle a single-argument constrained
  type (`| [ty] -> ... | _ -> ()`); a hypothetical multi-argument constraint
  would silently skip the check. Not committed as a corpus program because
  March's interface grammar only supports one type parameter per interface
  (`parser.mly:769-786`), so no `interface`/`impl`/`requires`/`when` surface
  syntax the parser accepts can actually produce a multi-argument constraint
  today — the branch is very likely dead code, not a live, reachable gap.
- **No `reject/` program for `derive X for UnknownType`.** A real, filed gap
  (`specs/todos.md`, "Compiler: Type System"; `core-march-types.md` §4.1
  finding 17): `derive Eq for Ghost`, where `Ghost` is never defined, silently
  no-ops (exit 0, no diagnostic) instead of rejecting — `expand_derive`'s
  `None` branch (`desugar.ml:1659`) returns `[]` with no `Err.error` call. Not
  committed as a `reject/` program for the same reason findings 15–16 aren't:
  it would assert behavior this document identifies as WRONG. See
  `core-march-types.md` §2.4 and §4.1 finding 17 for the exact repro to
  convert once fixed.

## Why not `@oracle`? (the harness-model difference from the golden corpus)

`specs/lang/golden/` rides `test/test_oracle.ml`'s both-ways
interpret-vs-compile sweep (see that directory's own `INDEX.md`) because every
golden program **runs** and produces comparable stdout on both backends. This
corpus is structurally different: every program here is `--check`-only, and
**`reject/` programs are deliberately malformed — they are SUPPOSED to fail to
typecheck.** Feeding a `reject/` program into the oracle's interpret-vs-compile
sweep would make it indistinguishable from an ordinary compile failure (a
regression the oracle is built to catch), not a correctly-rejected program —
there is no "expected output" to diff against for a program that must not run
at all. That is why this corpus needs its own harness (`check_types.sh`,
keyed on `--check`'s exit code plus a pinned error substring) and its own CI
lane (`types-check`, see `specs/lang/core-march-types.md` §5/§6) rather than
extending `@oracle`'s sweep.
