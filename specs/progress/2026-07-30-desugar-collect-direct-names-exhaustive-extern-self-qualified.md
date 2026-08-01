# `collect_direct_names` exhaustive; a self-qualified `extern` fn resolves

Landed 2026-07-30.

**At landing:** `run_codegen` 523 (was 520, +3 entry-self-qualification /
over-qualification parity tests). Typing corpus 241/241 (was 240/240, +1 accept
`t139`; `t126`/`t127` rewritten, see below). `test_refinecheck` 387,
`run_compiler` 619, `run_eval` 256, `run_snapshots` 33 (unchanged — no TIR shape
change), `run_stdlib` 826 with only the pre-existing environmental
`MARCH_SANITIZE` failure, grammar corpus 45/45 — unchanged.

**What changed.** `lib/desugar/desugar.ml`'s `collect_direct_names` is now
exhaustive over all 24 `A.decl` constructors with no wildcard, so a 25th form is
a compile error (verified by deleting an arm: `Error (warning 8
[partial-match])`). It was the fifth walk of the family in which the other four
each hid a real bug, and the one that had not been made exhaustive. It also
carries more weight than a diagnostics walk: it feeds `strip_entry_self_qual`,
which rewrites entry-module name spellings before anything else runs, so a wrong
entry changes which definition a call resolves to.

**One real bug, found by the exercise.** An `extern` block's `fn`s are ordinary
lowercase value names of the declaring module, but the walk could not see them,
so `Foo.my_abs(-7)` inside entry `mod Foo` failed `unbound variable:
Foo.my_abs` (interpreted) / `Undefined symbols: _Foo.my_abs` (compiled) while
the bare spelling worked. Fixed.

**The two consumers genuinely disagree, and that is the load-bearing finding.**
`collect_direct_names` feeds both `strip_entry_self_qual` and
`qualify_module_refs`/`qualify_level`, and they want different sets for
`DExtern`: an extern IS a member of the module for stripping purposes, but
codegen calls it by its C symbol and never under a module-qualified name, so a
bare intra-module call to one must NOT be qualified. Folding externs into both
was measured to break a nested module calling its own extern
(`Undefined symbols: _Bar.my_abs`, compiled only — the interpreter tolerated
it). Hence the new `~externs` parameter, passed explicitly at both call sites.

**Every other form was classified by experiment, not by reading the
constructor list.** `DActor`'s name is a CONSTRUCTOR — `spawn(Foo.Counter)`
fails in the constructor namespace, which `strip_entry_self_qual` explicitly
leaves alone — and the functions lowering derives from an actor are
underscore-mangled and unwritable in source (`Counter_spawn`,
`Counter_dispatch`, via `MARCH_DUMP_TXT=tir-lower`). `DType` /
`DAlwaysLinearType` introduce only type and constructor names. `DDescribe`'s
body admits only `test` / nested `describe`. `DUse` / `DAlias` name things from
elsewhere. The remainder are uppercase type/module/capability names or declare
no name at all.

**`DInterface`/`DImpl` were the close call, and are OUT.** An interface method
name is lowercase and reachable as an `EVar`, but it is not module-qualifiable
in March at all: with the interface declared in a nested `mod Bar`, `Bar.greet(1)`
fails `unbound variable: Bar.greet` from outside just as it would from inside.
So entry-level `Foo.greet(1)` failing is consistent, not a stripping gap — and
including the names actively regressed a working program, because
`qualify_level` then rewrote the bare `greet(1)` inside the declaring module
into `Bar.greet(1)`. Making the qualified spelling work is a dispatch-side
change, filed as an open residual in `specs/todos.md`.

**The fix invalidated two refinement-corpus witnesses, and that is the most
important thing in this entry.** `accept/t126` and `accept/t127` pinned
`stdlib_member_defs_ok`'s entry-module walk start by declaring the competing
`length`/`byte_size` in an **`extern` block, chosen precisely because
`strip_entry_self_qual` did not rewrite extern members** — a dependency stated
in `refine_check.ml`'s own comment. Once it does, the guard is spelled bare, the
measure alias is never consulted, and both witnesses would have passed whatever
the gate did — vacuous, the exact trap this corpus exists to avoid. (`t126` was
worse than vacuous: bare `length` in an entry module that also defines `go`
trips a *pre-existing, unrelated* bogus "recursive call to `length` is not in
tail position" error, reproducible with no extern anywhere — the tail-call
analysis merges an entry module's top-level names with the prelude's, and
prelude `length`'s inner helper is named `go`. Filed, not fixed here.)

Both witnesses now declare the competing member as an `interface`/`impl` method
pair — a form `strip_entry_self_qual` still does not rewrite — and both were
**mutation-verified**: with the walk start reverted to `go false`, each is
rejected with the false `len(_) > 0` violation it exists to catch. New
`accept/t139_nested_module_shadows_list_length_extern` keeps the `A.DExtern`
arm of that member scan covered, from a NESTED `mod List` whose name is not
stripped; mutation-verified by deleting the arm. Typing corpus 240/240 →
241/241 (121 accept, 120 reject).

**Tests.** +3 `run_codegen` parity tests, +1 typing-corpus accept, 2 rewritten.
The extern codegen test is RED pre-fix on both backends with the exact
`unbound variable: Foo.my_abs`. The other two codegen tests are
over-qualification guards, and they are not decorative: each pins one of the two
regressions this task's own intermediate versions actually introduced.
