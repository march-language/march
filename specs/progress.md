# March — Progress Summary

## Current State (as of 2026-07-31, `@[vectorize]`/`@[vectorize(warn)]` turns silent auto-vectorization eligibility into a checked contract)

**Counts:** `run_compiler` 619 (unchanged in the quick suite; +1 parser test added by this work), `run_eval` 256 (unchanged), `run_codegen` 537 (was 520, +17 — the `vectorize_check` group, including 2 tests added by the final-review fix wave below), `run_stdlib` 780 (unchanged); `scripts/run-tests.sh -q` all suites passed, exit 0.

**Final-review fix wave (2026-07-31).** Four fixes landed after the whole-branch review, before merge: (1) `reuse_example` (`lib/tir/vectorize_check.ml`) hardcoded float syntax (`x *. 2.0`) in its reuse-gate hint for BOTH Int and Float targets, so the compiler's own suggested fix for an Int violation didn't typecheck — fixed to branch on `is_float_target` too, covering all four map/map2 x Int/Float combinations; regression test `"reuse gate: Int hint uses Int syntax"` asserts the diagnostic's `notes` field. (2) No test compiled-and-ran a PASSING `@[vectorize]` program — the only compiler-driving test exercised a rejected program that never reaches clang, so a `find_markers`/`strip_markers` regression (a surviving sentinel reaching LLVM emission, which has no matching symbol to link against) could ship green; added `"pass: eligible annotated program compiles and runs"`, which compiles `vectorize_source_ok` and runs the binary. (3) A stale comment in `test/test_compiler.ml:475` still said `Vectorize_check.collect_attrs`; that function lives in `Vectorize_mark` since the sentinel redesign — fixed. (4) `generic_diag`'s note pointed at a `docs/simd-vectorization.md` "map_float" heading that doesn't exist — repointed to the real "What vectorizes" heading.

**Feature.** `@[vectorize]` and `@[vectorize(warn)]` function attributes. `NativeArray.map_int`/`map_float`/`map2_int`/`map2_float` have long had an auto-vectorization fast path (`lib/tir/native_map_inline.ml`) that silently either does or doesn't fire depending on how the callback closure is used — until now there was no way for an author to say "this function must vectorize" and have the compiler check it. `@[vectorize]` makes an eligibility violation a hard compile error (exit 1); `@[vectorize(warn)]` reports it as a warning and lets the build continue.

**The two real gates**, deliberately reusing `native_map_inline.ml`'s own matching helpers so the diagnostic can never disagree with what the optimizer actually does:
- **Reuse gate** (Int and Float targets): the callback closure must be used exactly once, passed directly as the map/map2 call's closure argument. `"<fn> cannot vectorize — this callback isn't safe to inline"`.
- **Generic-signature gate** (Float targets only): the callback's resolved signature must be concretely `Float`, not a leftover `TVar` — this is what unlocks the zero-boxing unboxed clone. `"<fn> cannot vectorize — callback type is still generic"`.

A third **misuse** category — the attribute on a function with zero `NativeArray.map`/`map2` calls — is always a hard error even under `(warn)`, catching a misapplied or typo'd annotation.

Worth recording: the informal prose in `docs/simd-vectorization.md` and `stdlib/native_array.march` describes the eligibility bar as "non-capturing or single-capture," but the actual implementation gates on reuse and (Float-only) concrete typing — capture count is not a gate; `native_map_inline.ml`'s Phase 2 (0 captures) and Phase 2c (1+ captures) both get the inlining treatment. The checker follows the code, not the prose, which is why there are two gates rather than three.

**Implementation shape.** `lib/parser/parser.mly` gained a new `fn_attr` alternative for the `@[name(value)]` bracket-with-argument form — the grammar previously supported `@[name]` and bare `@name(value)` but not the combination — encoded as `"vectorize:warn"`, the same convention `@compat(full)` already uses. `lib/tir/vectorize_mark.ml` (new) runs immediately after `Lower.lower_module`, before `Mono` — the one point in the pipeline where a TIR function's name is still exactly its source name — and injects a compiler-internal sentinel call (`__vectorize_marker_hard`/`__vectorize_marker_soft`) at the head of each annotated function's body, carrying the source name and declaration span as literal arguments. `lib/tir/vectorize_check.ml` (new) runs late, right before `Native_map_inline.run` (so it sees the same pre-rewrite TIR shape the optimizer peephole consumes): it scans bodies for sentinels, runs the gates, and returns the TIR with every sentinel stripped back out. `bin/main.ml` wires in both insertion points, each guarded on `not is_js_target`.

**Why a sentinel, not name matching.** The first implementation matched AST attributes to TIR functions by name at the late check point, stripping everything after a TIR name's first `$` on the assumption `$` only marks a monomorphization suffix. Review found that unsound two ways, both confirmed empirically: (a) Defun independently produces `<fn>$apply$<uid>` for every lifted lambda, so a stdlib local `fn scale` becomes `scale$apply$1803` and a user's own `@[vectorize] fn scale` would fire a spurious hard error against it; (b) the check runs after Opt, and a small annotated wrapper gets inlined into its caller and no longer exists as its own `fn_def` — so the exact reuse-gate violation the feature exists to catch was silently missed (confirmed via a post-Opt TIR dump showing `fn scale` entirely absent). The sentinel survives both mangling and inlining because Mono's record-update duplication and Opt's inliner preserve body contents wherever they land. It also fixed two consequences for free: diagnostics now name the user-written source name (not `scale$Float`), and `@[vectorize]` inside a nested `mod` no longer silently no-ops (the mark pass qualifies names the same way `Lower` does).

**Known limitation.** If two separately-annotated functions are both inlined into the same caller, their sentinels merge and can't be attributed call-by-call; `combine_markers` widens (joins the names, takes Hard if any is Hard) rather than silently mis-attributing.

**Tests.** A 17-test `vectorize_check` group in `run_codegen` covers: eligible Float, eligible Int, eligible map2, `(warn)` on eligible code is silent, reuse-gate hard fail, reuse-gate under `(warn)`, reuse-gate on map2, reuse-gate caught even after the annotated fn is inlined away, reuse-gate Int-hint-uses-Int-syntax, generic-signature pass/hard-fail/`(warn)`, misuse hard fail, misuse still hard under `(warn)`, a module-loads smoke test, an end-to-end CLI test driving the real `march --compile` binary against a REJECTED program, and an end-to-end compile-AND-RUN test against an ELIGIBLE program (proves the marker sentinel is actually stripped before LLVM emission). Plus one new `run_compiler` parser test for the `@[vectorize(warn)]` bracket-with-argument grammar.

**Out of scope / follow-up.** Fixed-width SIMD vector types (`f32x4`, `f32x8`, `i32x4`, `i32x8`) were part of the original feature request but are explicitly a separate later increment — they don't depend on this attribute. Tracked as an open TODO in `specs/todos.md`.

**Commits:** `47ce1996` (parser), `8bcc320e` + `5b2e731e` (check pass + sentinel redesign), `bea4ccf4` + `93bb6871` + `e82225d0` (pipeline wiring + test-robustness fixes), `284298ff` + `762d6e49` (test matrix + coverage gaps).

## Current State (as of 2026-07-30, a `(`-led statement no longer glues onto the previous line)

**Counts:** `run_compiler` 619 (was 615, +4 parse tests), `run_codegen` 520
(was 518, +2), `run_eval` 256, `run_snapshots` 33 (unchanged — Perceus/borrow behaviour
did not shift), `run_stdlib` 826 with only the pre-existing environmental
`MARCH_SANITIZE` failure, grammar corpus 45/45, `dune build @runtest` clean.

**Reported as a native-codegen crash; it was a parser bug.** A compiled binary
died with `EXC_BAD_ACCESS`/exit 138 (or SIGSEGV/139) whenever it called a
function that both discarded a parameter (`let _ = a`) and had a literal `()`
as its tail. The emitted IR was damning-looking: the callee was never emitted
at all, and its call site had become a closure-style indirect call *through the
argument* — `getelementptr i8, ptr %sl, i64 16` (the closure ABI's `fn_ptr`
slot) then `call ptr (ptr) %fv(%sl)` — with `%sl` a `String`, so the program
counter ended up at `0x1`.

Codegen was faithfully compiling what it was given. `--dump-tir` at `tir-lower`
showed the callee's body as `a()`: `let _ = a` followed by a line holding only
`()` had parsed as the single binding `let _ = a()`, because a block's newlines
are swallowed by the token filter and the parser therefore saw `a` `(` `)`
adjacent and applied the call rule. The parameter was being *invoked*. The
interpreter agreed — `fn f(a) do let _ = a ⏎ () end` applied to
`fn -> IO.puts("CALLED")` printed `CALLED`, which is what turned a two-fault
codegen theory into a one-line parse fact.

The reported trigger matrix falls out of that reading exactly: both conditions
are required because the discard is what leaves a value-ending token at the end
of the previous line and the literal `()` is what puts a `(` at the start of
the next; a `None`/`0`/`IO.puts(...)` tail has no leading `(`, and a zero-arg
callee has no discard. It is not cross-module, and not an RC bug.

**The fix** (`lib/parser/token_filter.ml`, `lib/parser/parser.mly`). The
newline-separates-statements rule was already specified for `f(1)`⏎`(g(2))`
(grammar §7.3, witness `parse/p24`) but was only ever enforced for the
curried-call `)`⏎`(` shape; the *classification* of the paren ignored the
newline entirely. A `(` that follows a value-ending token across a newline is
now retagged `LPAREN_STMT`, a token accepted only by `expr_atom`'s
group/tuple/unit rules and by `simple_pattern`'s parenthesised/tuple rules
(a match arm may legitimately open a fresh line with a tuple pattern — that
case is what the `Deque.pop_front` codegen test caught mid-fix). The call rule
does not accept it, which is the whole fix. menhir's shift/reduce count is
unchanged at 9.

Pinned by four parse tests (`run_compiler`, including two negative controls:
a same-line call and a multi-line argument list must both still be calls), two
codegen tests (`run_codegen` — one asserting no `call ptr (ptr)` is emitted for
this program, one compiling and running it), and grammar witness
`parse/p33_paren_stmt_after_bare_ident.march`. All were confirmed RED against a
`git show`-sourced copy of the pre-fix parser and GREEN after.

Worth recording separately: the five `try_call_capture_ownership_codegen`
failures seen while verifying this were **not** related — they were the stale
staged-runtime trap (`_build/default/runtime` is not refreshed by a targeted
`dune build bin/main.exe`). `dune build @install` + `@test/cas-runtime-dir`
cleared all five.

## Current State (as of 2026-07-30, the REPL capture-free closure leak is closed)

**Counts:** `run_codegen` 518 tests (was 517 — one new
`repl_jit_cross_line` regression), `run_eval` / `run_compiler` /
`run_stdlib` unchanged. Known failure: `adversarial-regressions` 39
(`MARCH_SANITIZE` 30s timeout) — pre-existing and environmental, reproduced
on a base tree with these changes reverted.

**A capture-free closure materialized under the REPL/JIT no longer leaks one
allocation per materialization.** Natively such a closure is a single
immortal global (`Llvm_ctx.intern_static_closure`), so nothing needs to
release it; `Llvm_emit.static_closure_ok` is `not ctx.repl && ..`, so under
the REPL the very same closure falls back to a fresh `march_alloc` per
materialization — and nothing ever released THAT.

Two prior attempts at this both crashed with `EXC_BAD_ACCESS` at `0x0`,
frame #0 = `0x0`, in `repl_jit_cross_line`'s "stdlib List.length via
precompile", and both diagnosed the crash by pattern-matching rather than by
looking. An actual `lldb` backtrace named it immediately:
`List.length$List_Int -> go$apply$218 -> 0x0`. `go` is `List.length`'s inner
**self-recursive** helper — capture-free, hence caught by a blanket
"drop capture-free apply fns" rule, but it already releases its own
reference through `lift_lambda`'s self-binding alias under completely
ordinary RC insertion (`let go = $clo in case .. of Nil -> dec_rc go; ..`).
The added drop was a second release of the same reference: freed on call 1,
the recursive dispatch then read a zeroed apply-fn slot.

**Fixed in two places, one per capture-free shape** — the second found by
measurement after the first was already green, and independent of it:

- `Perceus.insert_apply_fn_clo_drop ~repl` (threaded via `insert_rc` ←
  `perceus ~repl` ← `Repl_jit.lower_module`, which passes `~repl:true` so
  the flag tracks `ctx.repl` exactly) drops `$clo` for an apply fn whose
  body mentions `$clo` **nowhere**. That test is what excludes the
  self-recursive case above. Covers capture-free lambdas.
- `Llvm_calls.clo_wrap_define ~drop_clo` (`~drop_clo:ctx.repl` at all three
  emission sites) covers capture-free top-level function values, whose
  `@<fn>$clo_wrap` trampoline is synthesized at LLVM emission and has no TIR
  apply fn for Perceus to reach. Sound alongside the slot-read `incrc` from
  the "REPL variable slots now RC-correct" entry below.

Measured over 2,000 materializations in a REPL fragment: `march_live_allocs`
grew by exactly 2,000 before and 0 after, for each shape independently.
Native output is unchanged and provably so — a program exercising both
shapes plus `List.length` emits byte-identical `--emit-llvm --opt 2` IR
before and after. `repl_jit_cross_line` green 20/20 consecutive runs.

## Current State (as of 2026-07-30, `forge test` resolves transitive deps)

**`forge test` built `MARCH_LIB_PATH` from DIRECT deps only**, while
`forge build`/`forge check` walk the graph transitively. `Cmd_build.lib_path_env`
(`forge/lib/cmd_build.ml:244`) calls `collect_transitive_deps` — a breadth-first,
nearest-wins walk that pulls in each dep's own prod `deps` recursively —
but `Cmd_test.project_env` (`forge/lib/cmd_test.ml:105`) mapped
`dep_to_lib_paths` straight over `deps @ dev_deps @ test_deps`. Consequence: a
project depending on `B`, where `B` depends on `C`, saw `C`'s modules from
`lib/` under `forge check` and NOT from `test/` under `forge test` — the test
compile failed with "Unknown module ..." for a call that typechecks two
directories away. This is the same class of bug as the earlier
`scroll`→`bastion`→`depot` failure, just on the one code path that never got
the fix.

`project_env` now uses `Cmd_build.collect_transitive_deps` over the test scope
(`deps` + `dev-deps` + `test-deps`, still excluding `dev-only-deps`), so it
inherits the same breadth-first nearest-wins shadowing — a project's own direct
path dep still beats a same-named dep reached through a sibling.

Pinned by a new unit regression in `forge/test/test_build_check.ml`
("project_env walks transitive path deps"): A path-deps `midb`, `midb`
path-deps `leafc`, assert `leafc/lib` is in `project_env`'s returned lib paths.
Fails on the old code, passes on the new. All seven other forge suites green
(242 tests); `test_build_check` has one PRE-EXISTING unrelated failure
("check: stdlib shadow does not corrupt an unrelated module"), confirmed by
reverting the change and reproducing it.

## Current State (as of 2026-07-30, a refined `let` annotation is CHECKED)

**Counts:** `test_refinecheck` 365 (was 358), typing corpus 233/233 (was
231/231), `check-docs.sh` exit 0, stdlib false-positive sweep EMPTY.

The last refined position in the language that obliged nobody now does.

**The gap.** `let ys : {List(Int) | len(_) > 0} = []` compiled, and reported
`1 proved, 0 violated, 0 skipped`. `scope_add_binding`'s annotated arm —
`A.PatVar n, Some r -> (n.A.txt, r) :: sc` — admitted the predicate into the
refined scope channel **unconditionally**, so the annotation became a *fact*
about `ys` and the later `inner(ys)` was discharged off it. `cap verified`,
whose entire premise is "if it compiles, it is proved", accepted the module.
An author writing an annotation to *document* an invariant instead silently
manufactured it. Every other refined position (a parameter at a call site, a
return refinement, an `impl` method parameter) obliges somebody; this one did
not, and the direction was silent-unsound rather than false-positive, which is
why it survived so long.

**The fix.** `check_let_annotation` (`lib/refinecheck/refine_check.ml`, called
from the block-fold's `ELet` arm BEFORE `scope_add_binding` extends the scope)
reflects the binding as a synthesized one-parameter call: the annotation is the
precondition, the bound expression is the sole argument, and `check_call`
answers it with every resolver it already has — measures, constructor tags,
records, the composition machinery from PR #121/#126 — and the same
definite-failure stance, so an undecidable annotation is skipped, never
reported. There is no new solver code.

Two details are load-bearing. `param_names` carries the **let name**, not the
refinement's binder: `check_call` resolves the refined value through
`actual_of_name`, and only this arrangement makes the `len(ys)` spelling land on
the bound expression (the binder travels separately in `rparam.binder`). And the
bound name is shadowed out of all three fact channels first, so the predicate's
`ys` can never be attributed to an *outer* `ys` — the false-positive direction
this subsystem must never take.

**An unproven annotation grants no fact.** This is the half that is easy to miss:
filing the obligation but still admitting the predicate would re-open the hole in
a quieter form, since `let ys : {List(Int) | len(_) > 0} = zs` for an opaque `zs`
would file a Skipped obligation and then still hand `len(ys) > 0` to every later
goal — `inner(ys)` reporting Proved on a premise nobody established. It now
measures `0 proved, 0 violated, 2 skipped`. The cost is precision (an invariant
the author knows but the checker cannot see is no longer usable) and it lands
entirely in the safe direction, as more skips.

**A second gap closed as a side effect.** `{Int | n > 0}` over `let n` was the
one spelling that was not even trusted — it resolved against nothing and was
merely inert (`0 proved, 0 violated, 1 skipped`). Routing through
`param_names = [let name]` makes `n` denote the bound value, so `0 - 5` is now
seen and reported. All three spellings (`_`, `{v : T | p(v)}`, the bound name)
now behave alike, verified at 6 proved / 0 skipped for a three-spelling witness.

**+7 tests (358 → 365)**, a `let-annotation` group asserting obligation COUNTS
with each case's measured PRE-fix count recorded in its comment — four
false-annotation shapes (three spellings plus Int) that measured `1 proved` and
must now be `1 violated`, the true annotation that must be exactly `2 proved`
(asserting `>= 1` would have been vacuous), and the undecidable control that must
be `0 proved, 0 violated, 2 skipped`. The suite's first draft had four vacuous
cases and one that did not compile; all five were caught by measuring pre-fix
counts rather than by review. Bracketed in the corpus by
`accept/t130_refine_let_annotation_checked_and_composes` and
`reject/t131_refine_let_annotation_false`.

**Blast radius: none in-tree.** A refined `let` annotation appears 0× in
`stdlib/` and 0× in `specs/lang/types/` — all 98 `: {` occurrences in the stdlib
are on `fn` signature lines. The stdlib sweep is empty and every one of the 231
pre-existing corpus files is unchanged, so unlike the composition work (which
added assumptions consumed by many existing call sites and needed five
false-positive fix rounds) this change fires only on a construct no checked code
currently uses.

## Current State (as of 2026-07-30, REPL variable slots now RC-correct)

**A real, independent bug found while chasing the still-open REPL
capture-free-closure leak: REPL variable slots did zero RC bookkeeping.**
`lib/tir/llvm_repl.ml`'s persistent slot mechanism (`@march_repl_get`/
`@march_repl_set`, backed by `runtime/march_extras.c`'s `march_repl_slots`
array) copies raw `int64_t` bits with no incref on read and no decref on
overwrite. Any heap-typed REPL variable — a String, a closure, any boxed
value — read back from a later fragment handed out the slot's OWN
reference with no dup; any overwrite (concretely, the `"v"` magic
last-expression-value slot, genuinely reused across every subsequent REPL
expression) discarded whatever reference the slot held with no release.

Fixed at the two read sites (`emit_prev_slot_bridges`, `emit_slot_loader_fns`
— a prior binding can be read either bridged directly into a later
fragment's entry block, or via a generated zero-arg loader function) and the
one write site (`emit_store_to_slot`), all gated on the *static* `Tir.ty` at
the LLVM-emission call site — deliberately not inside
`march_repl_get`/`march_repl_set` themselves, since slots store
`Int`/`Bool`/`Float` **untagged** (unlike March's usual `(n<<1)|1`
convention), so a blind `IS_HEAP_PTR`-gated fix inside the untyped C
functions would misfire on an ordinary integer whose raw bits happen to look
pointer-shaped. Caught that before it was ever built or run, by diffing
against a `git show`-sourced copy of the pre-edit file rather than mutating
the working tree to test it.

This does NOT close the REPL capture-free-closure leak it was found while
chasing — re-attempting the `is_repl` threading from the previous entry, on
top of this fix, hit the identical SIGSEGV at the identical address. There
is at least one more contributing mechanism, somewhere in how the
precompiled stdlib passes a capture-free closure around internally, not yet
diagnosed. That `is_repl` change was reverted again; this slot fix was kept,
since it is correct and valuable independent of whether the leak is ever
closed.

Verified: all 24 `repl_jit_cross_line`/`repl_jit_regression` tests pass with
this fix alone, including the two shapes that actually exercise repeated
slot access ("var redefinition", "P0: List.length x3 successive
fragments"). Full `dune build @runtest` clean except the pre-existing
environmental ASAN failure.

## Current State (as of 2026-07-29, a CONSTRUCTOR-TAG contract composes too)

**Counts:** `test_refinecheck` 358 (was 352), typing corpus 231/231 (was
229/229), `check-docs.sh` exit 0, stdlib false-positive sweep EMPTY.

The last refined form that did not compose across a call boundary now does.

**The gap.** `fn inner(o : {Option(Int) | is_Some(_)})` called with a caller's
own parameter `p : {Option(Int) | is_Some(_)}` reported `1 proved, 1 skipped` —
the proof being `main`'s literal call, the skip being `inner(p)` inside
`outer`'s body — while the identically-shaped MEASURE contract
(`{Tree | size(_) > 0}`) composed. `refined_scope_ty` admits every registered
ADT, `Option` included, so the scope entry carrying `p`'s promise DID exist; the
gap was downstream, in `reflect_dt`'s `EVar` arm, which declares a bare
caller-scope name as a FRESH, UNCONSTRAINED datatype constant and never
consulted the scope channel. The VC was therefore satisfiable both ways. Same
shape of gap `measure_of_var` had before the measure fix earlier the same day.

**The fix.** `load_scope_tester_facts` in `lib/refinecheck/refine_check.ml`,
the tester analogue of `load_scope_measure_facts`, wired into `check_call`'s
`resolve_tester` immediately before it reflects the subject (load-before-reflect,
mirroring the measure side). It fires only when the actual is a bare name whose
measure-only ADT scope entry's predicate is EXACTLY a bare tester over its own
refined value — all three spellings accepted (`_`, the declared binder, the
parameter's own name) — for the SAME constructor the goal tests and at the same
datatype sort. It then asserts that tester over `Const x`, the very term the
goal side builds, so assumption and goal meet on one symbol; both sides emit the
same `(x, SData adt)` declaration and the VC builder's existing (name, sort)
dedup covers it, with a per-(name, sort, ctor) memo keeping the assumption from
being asserted twice.

**Deliberately narrow.** A caller promising `is_None(_)` into a callee wanting
`is_Some(_)` loads NOTHING and stays skipped. Assuming the caller's promise
verbatim there would also be sound — and, the two testers being exclusive on
`Option`, would turn the call into a reported violation — but it is a strictly
wider claim than "the caller already promised the goal", and a missed report
costs nothing while a wrong fact is the failure this subsystem exists to
prevent. Compound predicates, negations and conjunctions likewise load nothing.

**+6 tests (352 → 358)**, a new `compose-tag` group asserting obligation COUNTS
rather than absence of a diagnostic: the three spellings compose (2 proved,
0 skipped each — all three were `1 proved, 1 skipped` pre-fix, verified against
a file-copy-swapped pre-fix binary), and the different-constructor, `let`-rebind
and `match`-shadow cases must not (1 proved, 1 skipped each — the cardinal-sin
controls). Bracketed in the corpus by `accept/t129_refine_tag_contract_composes_call`
and `reject/t130_refine_tag_composition_narrowed_violation`, the latter pinning
that a real failure through the same non-composing shape is still reported.

For everything prior to this point, see
[specs/progress_through_july_2026.md](progress_through_july_2026.md) — the
prior progress log, archived because it had grown too large to be a useful
implementer-level record. New entries go above this line, newest first, in
the same format as the archive.
