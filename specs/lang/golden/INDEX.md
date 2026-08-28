# Golden corpus index (g01–g47)

Navigable map of the Core March golden conformance corpus: each program in this
directory (`specs/lang/golden/*.march`) to the construct(s) and operational
rule(s) it anchors in `specs/lang/core-march.md`. Every program is verified to
produce **identical output interpreted and compiled**; run the whole corpus
with `specs/lang/golden/verify.sh` (47/47 MATCH, exit 0). See §5 of
`core-march.md` for the full per-program prose (divergences found and routed
around, expected output, guardrails).

Provenance: `g01`–`g08` are the walking-skeleton's original corpus; `g09`–`g13`
Task 1; `g14`–`g16` Task 2; `g17`–`g20` Task 3; `g21`–`g23` Task 4; `g24`–`g27`
Task 5; `g28`–`g30` Task 6; `g31`–`g32` Task 7; `g33`–`g34` post-Phase-1 corpus
widening after the concurrent `float_to_string` (`g33`) and block-`let`
nested-`PatTuple` lowering (`g34`) backend fixes landed; `g35`–`g36` the
actor-operational addition (§4.10 spawn/send/receive/run_until_idle); `g37` the
actor-lifecycle addition (§4.10.6 spawn/kill/is_alive, the one lifecycle plane
matching to the byte compiled; the capability/dead-`send` plane diverges and is a
prose finding, not a golden program); `g38`–`g39` the session-typed channel
operational addition (§4.11 channel runtime: binary `Chan.new`/`send`/`recv`/
`close` and `choose`/`offer`, ENABLED by the concurrent F1/F2 codegen fix that
made odd-Int/Bool channel payloads match to the byte compiled; MPST is documented
but diverges compiled (F3) and is intentionally NOT a golden program); `g40`
the actor foreign-message-drop addition (finding 19: a message for a DIFFERENT
actor `send` to this Pid is silently DROPPED in both backends, ENABLED by the
compiled fix that forces actor message types Boxed with globally-unique tags and
gives the dispatch a dropping default arm, replacing the prior memory-unsafe
misroute); `g41` the linearity-erasure addition (§4.12: linear/affine
annotations are compile-time-erased, widening slice 7; its affine binding is
consumed by a DIRECT match, the regression witness for finding L7, FIXED
2026-07-10: escape analysis no longer stack-promotes erased-repr allocs,
`specs/todos/`); `g43` the parallelism addition (§4.14, widening slice 9:
the data-parallel determinism guarantee: `List.pmap == List.map` plus the RRB
`Parallel` integer/bool reductions, the first compiled witness for the RRB
`Parallel` module; `psum_float` intentionally excluded: IEEE non-associativity,
finding P1); `g44` the distributed-CRDT addition (§4.15, widening slice 10:
the convergence laws of the single-process-testable CRDT core: GCounter/
PNCounter/ORSet merge + VectorClock causality, including the disjoint-key
`compare`/`.concurrent` case that used to crash compiled via the read-then-
update-map use-after-free, finding C1, FIXED 2026-07-11, `specs/todos/`);
`g45` the Perceus RC addition
(§4.16, widening slice 11: the dual-position dup/drop invariant B1, the ONE
rule in this corpus verified three ways: interp==compiled, a committed TIR
snapshot, AND `MARCH_SANITIZE=1` clean); `g46` the refinement-types addition
(`core-march-types.md` §2.14, widening slice 12: refinement obligations are
discharged entirely at `--check` time by a separate pass, `lib/refinecheck`,
that erases to no footprint at runtime; a program with obligations that all
hold by proof therefore runs byte-identically, the same erasure property golden g41
established for linear/affine annotations); `g47` the `let*` generalized
monadic-bind addition (`specs/lang/let-star-generalized-bind.md`: the same
type-directed `flat_map` dispatch works across three different types in one
program, proving it isn't secretly hardwired to any one of them).

| Program | Construct anchored | Rule(s) in core-march.md §4 |
|---|---|---|
| `g01_let_arith` | block `let`, `Int`, `+` | E-Blk-Let (§4.2), δ-Add-I (§4.4) |
| `g02_lambda_app` | lambda + application | E-Lam, E-App-Clo (§4.2) |
| `g03_bool_eq` | `Bool`, `==` | δ-Eq-I / δ-Eq-B (§4.4) |
| `g04_adt_match` | 2-ctor ADT, `match`, payload-free `PatCon` | E-Match (§4.2), match(PatCon …) (§4.3) |
| `g05_adt_payload` | ADT payload, `PatCon C [x]` binding | E-Con (§4.2), match(PatCon C [p…], VCon …) (§4.3) |
| `g06_hof` | higher-order function (closure passed as arg) | E-Lam, E-App-Clo (§4.2) |
| `g07_match_lit` | `PatLit` + `PatWild`, first-match-wins | match(PatLit …), match(PatWild …) (§4.3); branch-selection (§4.3) |
| `g08_nested_let_shadow` | nested block + `let` shadowing | E-Blk-Let (§4.2), assoc-list first-occurrence lookup (§4.1) |
| `g09_literals` | `LitFloat`/`LitString`/`LitAtom` (via `EAtom`) + atom `==` | E-Lit, E-Atom-0 (§4.2); δ-Eq-* (§4.4); match(PatLit …) (§4.3) |
| `g10_arithmetic` | `-`,`*`,`/`,`%`, truncating `/`/`%`, unary `negate`, Float `-`/`*` | δ-Sub/Mul/Div/Mod-I, δ-Neg-I, δ-Sub-F/δ-Mul-F (§4.4) |
| `g11_comparison` | `!=`,`<`,`<=`,`>`,`>=` on Int/Float/String | δ-Neq/Lt/Le/Gt/Ge-* (§4.4) |
| `g12_bool_ops` | `&&`,`\|\|`,`!`/`not`, `++` | δ-And, δ-Or, δ-Not, δ-Concat (§4.4) |
| `g13_strict_bool` | `&&`/`\|\|` **strictness** (rhs side effect fires) | §4.4.1 (strict, not short-circuiting); E-App-Prim (§4.2) |
| `g14_tuple_let` | `ETuple` construction, `PatTuple` in a block `let` | E-Tuple (§4.2), match(PatTuple, VTuple) (§4.3) |
| `g15_tuple_match` | `PatTuple` as a `match` branch, alongside a literal-tuple pattern | E-Match (§4.2), match(PatTuple …) + branch-selection (§4.3) |
| `g16_tuple_nested` | nested `ETuple` destructured by nested `PatTuple` in a `match` | E-Tuple (§4.2), match(PatTuple …) via match_list recursion (§4.3) |
| `g17_record_literal_field` | `ERecord` construction + `EField` access (left-to-right field eval) | E-Record, E-Field (§4.2) |
| `g18_record_update` | `ERecordUpdate` on an existing field (functional/persistent) | E-Update (§4.2), §4.2.1 |
| `g19_record_update_multi_field` | `ERecordUpdate` naming multiple existing fields | E-Update, E-Field (§4.2) |
| `g20_record_nested` | record nested in a record field, chained `EField`/`ERecordUpdate` | E-Field, E-Update (§4.2) |
| `g21_atom_match` | nullary `EAtom`/`VAtom` matched against nullary `PatAtom` | E-Atom-0 (§4.2), match(PatAtom a [], VAtom) (§4.3) |
| `g22_atom_payload_match` | payload `EAtom`/`VCon` matched against payload `PatAtom`, binding payload | E-Atom-N (§4.2), match(PatAtom a [p…], VCon …) (§4.3) |
| `g23_atom_returning_fn` | atom-returning fn, result via atom `==` and via `match` | E-Atom-0 (§4.2), δ-Eq-* (§4.4), match(PatAtom …) (§4.3) |
| `g24_nested_con_tuple` | deeply nested pattern (con → tuple → con → var) | match(PatCon/PatTuple …) via match_list at depth (§4.3) |
| `g25_guard_fallthrough` | guard `when n > 10` FALSE ⇒ falls through to a later branch | branch-selection guard rule (§4.3, `eval.ml:7340`) |
| `g26_catchall` | specific `PatCon` branches then a `PatWild` catch-all keeping `match` total | match(PatWild …) (§4.3), exhaustiveness/no-match rule (§4.3) |
| `g27_guard_binding` | guard reading its OWN branch pattern's bound variables | branch-selection: guard in pattern-extended env (§4.3); reachable substitute for `PatAs` (§4.3.1) |
| `g28_letfn_factorial` | local self-referential `fn go(n)` (factorial) via env-ref knot | E-LetFn (§4.2) |
| `g29_letfn_capture` | local recursive `fn go` closing over an outer `let` while recursing | E-LetFn (§4.2), env-ref re-read (§4.2 prose) |
| `g30_letfn_sum_result` | recursive `fn go` with its result bound by a following `let`, used by rest of block | E-LetFn: binding visible to block continuation (§4.2) |
| `g31_cond_middle_arm` | `ECond` chain where a MIDDLE arm is the first `VBool true` | E-Cond-Sel (§4.2) |
| `g32_cond_all_false_catchall` | `ECond` all-specific-false ⇒ terminal `_ ->`/`true ->` catch-all | E-Cond-Sel with `_`-sugar catch-all; E-Cond-Fail (all-false raises) (§4.2) |
| `g33_float_show` | whole-number `Float` display via `float_to_string` (observation primitive); pins the cross-backend format after the `0a2d3f53` fix | §5 observation-primitive note (not a §4 core rule; float arithmetic/ordering deferred) |
| `g34_nested_tuple_let` | nested `PatTuple` destructured in a block `let`; added after the `3f719a8e` lowering fix the corpus surfaced | E-Blk-Let + `match(PatTuple)` componentwise `match_list` (§4.2/§4.3) |
| `g35_actor_spawn_send` | `spawn` a single `Counter` actor + three async `send(Inc(n))` + `Report()` handler `println` + one `run_until_idle()` drain (interleaving-free determinism witness) | E-Spawn/E-Send/run_until_idle (§4.10.1–.5, `eval.ml:7194/7265/3067→7523`) |
| `g36_actor_receive` | `on Start()` handler calls `receive()` once to pop an already-queued `Follow(99)` and `println`s its payload (non-blocking pop path) | receive pop-or-`BlockedOnReceive` (§4.10.3, `eval.ml:3076`) |
| `g37_actor_lifecycle` | `spawn` → `is_alive` (`true`) → `kill` → `is_alive` (`false`), each printed via a `Bool→String` helper (registry-bool observation, SAFE compiled) | `kill`/`is_alive` + `crash_actor`/`ai_alive` (§4.10.6, `eval.ml:2961/2964/1766/1772`) |
| `g38_chan_int_echo` | binary `Chan.new`/`send`/`recv`/`close` round-trip transporting an **odd** `Int` payload (`42` sent, `43` returned); exactly the value class the concurrent F1/F2 codegen fix made match to the byte compiled | `chan_new`/`chan_send`/`chan_recv`/`chan_close` (§4.11.2–.3, `eval.ml:2632/2645/2655/2666`) |
| `g39_chan_choose_offer` | `Chan.choose`/`Chan.offer` branch selection over a protocol with TYPE-DISTINCT branches (`ok -> Int`, `err -> String`, avoiding the F4 merge-rule pitfall); chooser picks `:ok`, sends an odd `Int` (`43`) after the label. Migrated for session-types Task 4 (2026-07-24, F5 residual): because the branches continue DIFFERENTLY, the offering side now `match`es on the returned label before driving the channel; output unchanged (`:ok` then `43`) | choose=send-atom / offer=recv-atom (§4.11.4, `eval.ml:5581/5588`) |
| `g40_actor_foreign_msg_drop` | a `Logger` message (`Zlog(String)`) `send` to a `Counter` Pid is silently DROPPED (not misrouted) in both backends, sandwiched BETWEEN two count-changing messages (`Inc(3)`, drop, `Inc(4)`); `Counter` `Report`s `count=7`, the stray `Zlog` contributing no count (a misroute would reinterpret the `String` payload as a garbage `Int`); this shape used to be flaky (finding 20, an unrelated actor-struct FBIP/RC race, now fixed), so it now also witnesses that determinism | foreign-message drop: interp handler-name miss (§4.10, `eval.ml:7545`); compiled Boxed message + globally-unique tag + dispatch default arm (finding 19 fix, `lib/tir/lower_actor.ml`, `lib/tir/repr.ml`, `lib/tir/llvm_toplevel.ml`); actor-struct `EReuse` always-in-place (finding 20 fix, `lib/tir/llvm_emit.ml`) |
| `g41_linear_annotations_erased` | all three linearity keyword surfaces in one deterministic program: a `linear` fn param (matched inside the callee), a `linear let` (consumed by the call), an `affine` type-modifier binding consumed by a DIRECT match; the direct match doubles as the L7 regression witness (FIXED 2026-07-10: escape analysis stack-promoted non-escaping erased-repr allocs into boxed stack cells that erased-convention consumers decoded as garbage; this golden's first run caught it); prints `42` / `done`, matching to the byte, stable across repeated runs | linearity erasure (§4.12): no runtime use-accounting on either backend; `v_lin` is optimization-only compiled; static rules in `core-march-types.md` §2.9; escape-promotion gate `lib/tir/escape.ml` `alloc_emits_heap_cell` (slice 7 + L7 fix, 2026-07-10) |
| `g42_letq_short_circuit` | a two-step `let?` Result chain: `chain(5)` succeeds through both steps (E-LetQ-Ok twice → `ok 70`), `chain(-1)` fails the first step so the second `let?` never runs (E-LetQ-Err short-circuits, returns Err verbatim → `err neg`); deterministic, no scheduler | `let?` Result-propagation (§4.13): native `ELetQ` eval, Ok-bind-and-continue / Err-short-circuit, matching to the byte on both backends; typing in `core-march-types.md` §2.10 (slice 8, 2026-07-10) |
| `g43_parallel_determinism` | data-parallel determinism guarantee: `List.pmap == List.map` (order-preserving) on 199 elements plus `Parallel.psum`/`pcount`/`pany`/`pall`/`preduce` over the same RRB `Vec` (associative merges + identities); same result interp (eager/sequential tasks) and compiled (real multi-core scheduler), stress-verified 0/15 crashes; first compiled witness for the RRB `Parallel` module. `psum_float` excluded (IEEE non-associativity, finding P1) | E-PMap / E-PReduce (§4.14): pmap gathers in spawn order; associative-merge reduce is chunk-count-independent |
| `g44_crdt_convergence` | distributed CRDT convergence laws (single-process core): GCounter/PNCounter/ORSet merge commutative + idempotent + value; VectorClock `happens_before` on causally-ordered clocks AND `.concurrent` on disjoint-key clocks; matching to the byte on both backends, stress-verified 0/20 crashes. The disjoint-key case used to crash compiled (finding C1, a `strip_scrut_decrc` scrutinee-dec ordering bug in `lib/tir/llvm_case.ml`); FIXED 2026-07-11 and now included unconditionally | CRDT-Converge (§4.15): join-semilattice merge laws; VectorClock partial order; live-network layers are a prose scope boundary |
| `g45_dual_position_borrow` | Perceus dual-position dup/drop invariant (B1, `specs/perceus-invariants.md` §2.1): `both(a: owned, b: borrowed, n: owned)` called as `both(s, s, 1)`: the exact shape that used to RC-underflow (owned-side and borrowed-side accounting each independently believing itself the only consumer of the one reference). Verified three ways: interp==compiled to the byte; post-Perceus TIR matches `test/snapshots/perceus/mixed_owned_borrowed_args.expected` exactly (one `inc_rc s` before the call, one `dec_rc` after); compiled binary clean under `MARCH_SANITIZE=1` (ASan+UBSan), exit 0, no leak/UAF report | E-Call-Dual-Position (§4.16): exactly one balancing `EIncRC`/`EDecRC` pair for a variable at both an owned and a borrowed position of the same call |
| `g46_refinement_erasure` | refinement types (`core-march-types.md` §2.14) have ZERO runtime footprint: `typecheck.ml` erases every `TyRefine` to its base type (repr strips it); a separate post-typecheck pass (`lib/refinecheck`) discharges the proof obligations entirely at `--check`/`--compile` front-end time, inserting no runtime check on either backend. A `clamp_nonneg`/`take_n` pair with a postcondition and precondition that both hold by proof (`--check` exit 0) therefore runs byte-identically; same erasure property golden `g41` established for linear/affine annotations | T-Refine-Erase (`core-march-types.md` §2.14): a refined type has the identical typing derivation as its base type; no runtime check is inserted at any point |
| `g47_letstar_generalized_bind` | `let*` generalized monadic-bind across three different types in one program: `Option` (propagates through two steps, short-circuits on the first `None`), `Result` (same two-step shape as `g42`'s `let?`, proving `let*` subsumes it), `List` (`flat_map` as cartesian product, proving `let*` isn't secretly special-cased to short-circuiting types); matching to the byte on both backends | `let*` generalized bind (`specs/lang/let-star-generalized-bind.md`): native `ELetStar` typechecked by resolving `<Type>.flat_map` from the RHS's inferred type, lowered to an ordinary `flat_map`/lambda/match call; interpreted path dispatches on the runtime value's type instead |

## Coverage notes (rules NOT anchored by a golden program, and why)

Some rules in `core-march.md` §4 are stated for fidelity to `eval.ml` but are
intentionally NOT exercised by any golden program; each has a `core-march.md`
note explaining why:

- **`match(PatRecord …)`** and **`match(PatAs …)`**: implemented in the
  interpreter but have **no surface grammar** (parse errors), so no `.march`
  source program can construct them. Collected in §4.3.1; `g27` is the reachable
  substitute for `PatAs`'s "bindings visible to the arm" semantics.
- **E-Cond-Fail (truly all-false)** and the **`Match_failure`
  exhaustiveness** case and the **`&&`/`||` crashing strictness** witness; all
  RAISE at runtime, and `verify.sh` treats any nonzero interpreter exit as an
  automatic `INTERP FAIL`, so a crashing program can never register as a golden
  `MATCH`. `g32` (routed through a `_ ->` catch-all) and `g13` (a non-crashing
  `println` side-effect witness) are the non-crashing substitutes.
- **`ERecordUpdate` on a missing field**: the adjudicated-and-converged
  divergence (§4.2.1). Its resolved form is "both backends reject with a nonzero
  exit", which (per the harness limitation above) cannot be a golden `MATCH`; it
  is pinned instead by a unit test
  (`test/test_properties.ml`,
  `test_record_update_missing_field_on_erased_base_converged`).
- **The capability / dead-`send` plane** (`get_cap` / `send_checked` /
  `revoke_cap`, and plain `send` to a dead pid): the interpreter and compiled
  backend **diverge** here (a logged finding, §4.10.6): compiled, `send` to a dead
  actor returns `Some` (interp `None`), `send_checked` on a live cap returns
  `:error` (interp `:ok`), and `get_cap(dead)` returns `Some` (interp `None`). A
  divergent program cannot be a golden `MATCH`, so the epoch-`Cap` mechanism is
  documented in §4.10.6 prose + citations rather than by a golden program. Only
  the lifecycle *liveness* plane (`spawn`/`kill`/`is_alive`) agrees compiled;
  that is what `g37` witnesses. (`revoke_cap`/`is_cap_valid` are additionally not
  registered in the typechecker, so they are not even surface-callable, a second
  finding in §4.10.6.)
- **The supervision / restart plane**: supervisor declaration + child restart
  + epoch invalidation (§4.10.7) has no golden HERE, but the historical reason
  changed (2026-07-08, compiled-actor-supervision plan): `get_actor_field`/
  `pid_of_int` now WORK compiled, supervisors DO spawn their declared children,
  and all three restart strategies are compiled, pinned by six stable native
  golden tests in `test/native/` (`pid_of_int_roundtrip`,
  `get_actor_field_direct`, `supervisor_spawn_children`, `supervisor_
  one_for_one_restart`, `supervisor_one_for_all_restart`,
  `supervisor_rest_for_one_restart`), which serve the interp-vs-compiled
  anchoring role for this plane. The full 3-strategy
  `examples/supervision_strategies.march` demo remains excluded from BOTH
  corpora: historically because of the multi-scheduler kill+respawn
  stack-corruption crash (FIXED 2026-07-09/10: TLS migration barrier +
  single-owner run queues, commits `9407cc6f`/`81adf1b1`; 200/200 clean at
  N=4 and N=8), and PERMANENTLY because its concurrent workers' prints
  interleave nondeterministically (30/30 runs byte-differ), inherent to
  parallel actors, so it can never be a to-the-byte `MATCH`.
- **Multi-party session types (`MPST.*`)**: the MPST runtime (§4.11.5) is
  complete and correct interpreted (a 3-role all-`String` relay runs cleanly),
  but **every** `MPST.*` program segfaults compiled (exit 139, logged as F3 in
  `specs/todos/`); the compiled MPST C runtime is not correctly wired to
  the lowered representation. A crashing program cannot be a golden `MATCH`,
  so MPST is documented in §4.11 prose only; only the **binary** channel plane
  (`g38`/`g39`) is golden-witnessed.
