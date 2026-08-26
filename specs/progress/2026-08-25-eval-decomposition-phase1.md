# `lib/eval` decomposition: Phase 1 complete — `eval.ml` 12,264 → 4,304 lines

Landed 2026-08-25. Completes Tasks **1.1, 1.2, 1.3, 1.4** and the **1.5 exit
gate** of `specs/plans/2026-08-19-compiler-file-decomposition.md`. Tasks 1.0 and
1.0b landed earlier the same day (#353) — see
`specs/progress/2026-08-25-eval-decomposition-phase1-prerequisites.md`.

## Where the interpreter lives now

| file | lines | what |
|---|---:|---|
| `lib/eval/eval.ml` | **4,304** | the evaluator: `eval_expr`, `apply`, pattern matching, module/test/doctest runners, FFI marshalling, app+supervisor machinery |
| `lib/eval/eval_builtins.ml` | 5,294 | `base_env` — the 5,274-line, 595-entry δ-rule table, verbatim |
| `lib/eval/eval_runtime.ml` | 1,242 | shared runtime state: actor registry/mailboxes, monitors+links+`crash_actor`, type/impl/FFI tables, vault, logger, ring buffer, tap bus, `value_to_string`, `cmp_op`, `show_dispatch` |
| `lib/eval/eval_net.ml` | 1,183 | CSV reader, HTTP server, WebSocket framing, non-blocking multiplexer |
| `lib/eval/eval_simd.ml` | 159 | Simd 128-bit ops + NativeArray narrow-width (f32/i32/u8) helpers |
| `lib/eval/eval_types.ml` | 134 | `value` / `env` and the mutually-recursive record types |
| `lib/eval/eval_session.ml` | 132 | session-typed channels + MPST |
| `lib/eval/eval_prim.ml` | 55 | `Eval_error`, `eval_error`, the five hook refs, `shutdown_requested` |

`lib/eval/dune` needed no edit — the library uses default module discovery.

`eval_builtins.mli` exports `val base_env : Eval_types.env` and nothing else.

## Verbatim, and proven so

Every task is code motion: definitions move byte for byte with their doc
comments. That was not asserted, it was checked. After Task 1.3 — the 5,274-line
table plus 75 scattered helper definitions moved in one commit — a script
reassembled the moved regions from `git show HEAD:lib/eval/eval.ml` and compared
them line by line against the new files, and compared the remainder against what
`eval.ml` still holds:

```
eval_builtins verbatim: True 5274 5274
eval_runtime  verbatim: True 1037 1037
eval.ml remainder verbatim: True 4279 4279
```

Task 1.4 (numbered `§N` headers + a table of contents) was verified
comments-only by masking every line that lies inside a comment and diffing what
is left: **2,835 code lines, byte-identical before and after.**

## Two places the plan's shape had to change

**`open` does not work; `include` does.** The plan says to add `open Eval_simd`
to `eval.ml`. That compiles `eval.ml` and then fails the build in
`test/test_stdlib_suite.ml:13134`, which calls `f32_round` under
`let open March_eval.Eval in`. `open` makes a name visible *inside* `eval.ml`;
only `include` re-exports it to `Eval.*` consumers. Every Phase-1 extraction is
re-exported with `include`, following the `include Eval_types` precedent Task
1.0 already set. **A `grep` for `Eval\.<name>` does not find these call sites** —
that is how the plan's dependency analysis missed them.

**Task 1.3's shared/exclusive split was dropped.** The plan splits the table's
helpers into a shared `eval_runtime.ml` and ~85 "table-exclusive" ones that ride
along inside `eval_builtins.ml`, classified by how often each name appears in
`eval.ml` outside the table. Measured on comment-stripped source, the table's
true dependency closure inside `eval.ml` is **75 top-level definitions, 963
lines** — and they reference each other, so any misclassification splits a
helper from its caller. OCaml reports one unbound name per build, so the
"build is the arbiter" loop would have been ~dozens of 2-minute rebuilds. All 75
went to `eval_runtime.ml` in source order instead. Hiding is preserved where it
matters: `eval_builtins.mli` still exports only `base_env`.

Three smaller corrections the plan did not anticipate:

- **`shutdown_requested` had to move.** The non-blocking HTTP event loop polls
  it, so it could not stay in `eval.ml` once `eval.ml` depended on `Eval_net`.
  It went to `eval_prim.ml`; `eval.ml` keeps `let shutdown_requested =
  Eval_prim.shutdown_requested`, and aliasing a `ref` shares the same cell, so
  `bin/main.ml:4808` is untouched.
- **`value_to_string` had to move before Task 1.3.** `eval_net.ml` needs it,
  which forced `eval_runtime.ml` into existence during Task 1.2 (carrying
  `value_to_string`, `display_tag`, `is_list_value`, `list_elems`, and the
  vault registry types it reads).
- **Extracted files need `open March_ast.Ast`** wherever the moved code names an
  AST type (`actor_def` in `eval_runtime.ml`) — the same omission Task 1.0
  found. Conversely, `eval_runtime.ml` and `eval_net.ml` each needed an `open`
  *removed* to satisfy warning 33.

### The doc-comment trap in range-based extraction

Cutting a definition by line range silently mangles code when the range boundary
lands inside a comment. It happened once here and the compiler caught it as
`Comment not terminated` — but only because the truncated comment happened to
open one. The cause: `match_pattern`'s doc comment contains a **blank line**, so
a "walk back over the preceding comment lines" heuristic that tests
`line.strip() != ''` stops in the middle of it and the *previous* definition's
range swallows the top half. The fix was to compute a real per-line
inside-a-comment mask by scanning the file with a comment-depth counter, and to
assert, for every range before writing anything, that its text has balanced
comment delimiters. **Do this for Phases 2–6; do not trust `grep -n` boundaries
plus a blank-line rule.**

## Verification

**`scripts/ir-oracle.sh` was not run and its green would mean nothing here.**
The interpreter is never emitted as LLVM IR, so the oracle is structurally blind
to everything under `lib/eval/`. This is stated in the plan and in the Task
1.0/1.0b progress note, and is repeated here because it is the one thing a
reader of these commits must not get wrong.

The proof used instead:

1. **`scripts/run-tests.sh`, full suite, after each task.** Baseline at
   `67c8b511`: **2,761 tests, exit 0**. After Task 1.3 (the largest move):
   `936 + 273 + 591 + 878 + 61 + 22 = 2,761`, **All suites passed**, exit 0.
   Task 1.4 (comments only) was gated on `-q` plus a full `dune build`.
2. **`dune build --root . bin/main.exe` and all six test executables** after
   each task, judged by exit code.
3. **A known flake, twice.** The full-suite runs after Tasks 1.1 and 1.2 each
   reported exactly one failure in `run_stdlib`'s `adversarial-regressions`
   group — but a *different* test each time (`aliased owned arg f(x,x)` then
   `string stats: bytes copied`), and each passed on an isolated re-run of the
   same suite against the same binary. These are compiled-and-executed tests;
   the box carried load average 4–13 throughout. A single red in that group is
   not evidence until it reproduces.

## Phase 1 exit gate (Task 1.5): cumulative, not per-task

Tasks 1.0/1.0b measured `fib` dead even and `binary_trees` ~2% slower. One
extraction at 2% is noise-adjacent; five of them is not, so the gate was
measured **for the whole phase at once**.

A control `main.exe` was built from `f31145eb` (two commits before Task 1.0) by
checking out the commit in this worktree — never `git stash`, the stash stack is
shared across march worktrees — and copying the binary aside. Then both binaries
were run **interleaved**, alternating on every iteration, `MARCH_STDLIB` pinned:
5 rounds control-first, then 5 rounds final-first to cancel position bias. 20
samples per benchmark. Checksums matched on all 20 (`fib` 75025,
`binary_trees` 8188).

| bench | control median | final median | delta |
|---|---:|---:|---:|
| `fib` | 573 ms | 579 ms | **+1.0%** |
| `binary_trees` | 494 ms | 499 ms | **+1.0%** |

(medians over 9–10 samples per side, first-position warmup excluded)

**Phase 1 cost the interpreter approximately 1% — inside this box's noise band
and well under the 5% gate.** In particular `fib`, the dispatch-bound benchmark
that would move first if a direct call had become a hook dereference, did not
move. That is consistent with a direct check of the mechanism the plan warns
about: the number of `!*_hook` dereferences across all of `lib/eval` is **55
before and 55 after**, so Phase 1 introduced no new indirection anywhere.

Caveat on the control: `f31145eb` also predates `50c7c384` (a JIT `.so`
`install_name` fix) and `67c8b511` (`.mli` files on four compiler modules), both
of which are on the "final" side of this comparison. Neither touches the
interpreter's hot path.

The first-position warmup is real and large: the very first `fib` run of a batch
took 982 ms against a 573 ms steady state. An absolute-ms before/after would
have reported a 70% regression from that one sample alone.

## Not done here

Phase 2 (`llvm_emit.ml`) and everything after it are untouched. The tracking
item `specs/todos/2026-08-19-compiler-file-decomposition.md` stays open for
Phases 2–6.
