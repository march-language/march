---
name: compiler-rc
description: Debug reference-counting bugs in the March compiler (Perceus, borrow inference, drop glue, runtime RC). Use for a compiled-only crash, double free, use-after-free, leak, or wrong value after an RC operation, when the interpreter gives the right answer.
---

# Debug an RC bug

RC bugs manifest as: SIGSEGV, double-free, slow leak, or wrong output after a GC boundary. They usually live in one of three places:

1. **`lib/tir/perceus.ml`** (the pass entry point and orchestrator) and **`lib/tir/perceus_core.ml`** (the `env` record and `insert_rc_expr`, which decides where every `IncRC`/`DecRC` goes), plus the focused sibling modules:
   - `lib/tir/perceus_liveness.ml` — `live_before`/`name_free_in`/`vars_of_atom(s)` (backwards liveness)
   - `lib/tir/perceus_elide.ml` — `elide_cancel_pairs` (post-insertion inc/dec cancellation)
   - `lib/tir/perceus_fbip.ml` — `try_fbip_sink`/`fbip_expr` (dead-binding reuse, the `$fbip$`-marked arity check)
   - `lib/tir/perceus_scrut.ml` — `preprocess_scrut_escape` (Phase-0.5 scrutinee-escape preprocessing)
   - `perceus.ml` re-exports each (e.g. `let elide_cancel_pairs = Perceus_elide.elide_cancel_pairs`), so existing call sites and greps for `Perceus.foo` still resolve — but the actual function body now lives in the sibling module above; edit it there.
2. **`runtime/march_runtime.c`** — the runtime's pointer classification and RC ops
3. **User March code** — a usage pattern Perceus can't see through, fixable by adding a `let` to make liveness obvious

If the RC-adjacent bug instead lives in code generation or lowering (wrong register reused across an RC op, a tag/untag sequence emitted around a heap pointer, a scrutinee alias mis-lowered before Perceus ever sees it), the relevant logic now lives in one of these Wave 3 chunk 2 splits — same re-export discipline as the perceus siblings above (each orchestrator re-exports its split-out names bare, so existing qualified references still resolve):

- **`lib/tir/llvm_emit.ml`** (orchestrator: `emit_expr`/`emit_atom`, `emit_module`) and its siblings:
  - `lib/tir/llvm_ctx.ml` — `ctx` record, `fresh`/`emit`/`coerce`, layout constants, the audited `emit_tag_scalar`/`emit_untag_scalar`/`emit_untag_known_scalar` helpers (the ptr↔i64 tagging law lives here — read this file first for any tag/untag bug)
  - `lib/tir/llvm_builtins.ml` — the declarative builtin table (`is_builtin_fn`/`builtin_ret_ty`/`mangle_extern`/preamble, one row per builtin)
  - `lib/tir/llvm_eq.ml` — generated structural-equality functions (`ensure_adt_eq_fn`)
  - `lib/tir/llvm_data.ml` — EAlloc/EReuse/ETuple/ERecord/EField/EUpdate helpers, ctor lookup, record-shape metadata
  - `lib/tir/llvm_case.ml` — `emit_case` (niche/newtype/boxed-ADT match dispatch + FBIP-aware RC bookkeeping on scrutinees — a common RC-bug site)
  - `lib/tir/llvm_calls.ml` — EApp/ECallPtr helpers, closure-wrapper dispatch
  - `lib/tir/llvm_tco.ml` — self/mutual TCO analysis + `emit_mutual_tco_group` (loop back-edges that skip RC ops if mis-scoped)
  - `lib/tir/llvm_toplevel.ml` — `emit_fn`, `emit_module` internals, entry/main emission
  - `lib/tir/llvm_repl.ml` — REPL/fragment emitters
- **`lib/tir/lower.ml`** (orchestrator: `lower_expr`/`lower_module`) and its siblings:
  - `lib/tir/lower_state.ml` — the threaded `env` record + module-level lowering state
  - `lib/tir/lower_types.ml` — `lower_ty`/`convert_ty`
  - `lib/tir/lower_match.ml` — `compile_matrix`, guards, join points (a scrutinee mis-lowered here reaches Perceus already wrong)
  - `lib/tir/lower_decls.ml` — fn/type/extern lowering
  - `lib/tir/lower_actor.ml` — actor lowering
  - `lib/tir/lower_tests.ml` — test/setup collection

`lib/tir/tir_names.ml` (cross-pass name contracts: `is_apply_fn`, `is_clo_struct`, `fv_field`, etc.) and `lib/tir/kind.ml` (the per-type table: `Kind.needs_rc_of`, `Kind.borrowable_of`, representation decisions) are the shared modules every pass above depends on. Check these first if a bug looks like a name-predicate or RC/borrow-classification mismatch rather than a missing inc/dec. `lib/tir/borrow.ml` infers which parameters are borrowed (`Borrow.infer_module`, and `extern_borrow_table` for C builtins); `lib/tir/drop.ml` synthesises the `__drop$T` glue.

## 0. Read the invariant contracts first

Before touching flags or IR, read the two documents that state what the RC and
value-representation systems *promise*. Most RC bugs are a specific clause of one
of these contracts being violated; knowing the clause tells you which pass is wrong.

- **`specs/perceus-invariants.md`** — the ownership discipline: what an owned vs
  borrowed parameter promises at a call boundary (and who decrements when), the
  dual-position invariant (a var passed at *both* an owned and a borrowed position
  of one call must be dup'd — its violation is a use-after-free, commit `a5dad194`),
  the FBIP precondition (reuse arity is the *constructor field* count, never the
  type-parameter count — commit `a5dad194`), the closure-FV rule, and the
  path-insensitive scrutinee-borrowed approximation (leak-not-crash by design;
  the cross-branch dec exclusion is commit `20d1d144`). This is the governing
  spec; the module doc comments defer to it.
- **`docs/value-representation.md`** — the tagging law (`ptr→i64` untags iff odd;
  never tag a pointer; known-heap restore is bare `inttoptr`), the `march_hdr`
  layout, UNIFORM vs NATURAL slots, the closure/apply-wrapper ABI, and the
  shallow-free RC contract (who dups children). A tag/untag or
  incrc-on-a-non-pointer bug is almost always a violation stated here.

If the bug looks like a TIR-shape or `br_tag`/synthetic-name issue rather than a
count issue, `specs/features/tir-invariants.md` has the post-lowering invariants.

## 0.5. Ask the instrumentation before reading IR

The compiler can usually name the function, the variable and the path for you. Run these first:

```bash
scripts/triage.sh /tmp/rc_repro.march      # interp vs compiled, optional-pass switches, per-stage TIR, ASAN, one screen
./_build/default/bin/main.exe --verify-tir --emit-llvm /tmp/rc_repro.march
```

- **`--verify-tir`** includes the RC-balance check (check 3, `lib/tir/tir_verify_rc.ml`). It
  walks every path after Perceus and reports an over-release or a use after release as
  `rc-balance/<kind>: \`x\` on path \`case d: Some\`: ...`, naming the binding. Add
  `MARCH_VERIFY_TIR_LEAKS=1` for leaks (expect accepted drop-glue findings; see
  `specs/progress/2026-10-12-verifier-leak-sweep.md`). The check reads the borrow map Perceus
  used, so it verifies placement against those decisions; it cannot say a borrow decision was
  wrong.
- **`--rc-trace`**: who took the unreleased reference.
  ```bash
  ./_build/default/bin/main.exe --rc-trace --compile -o /tmp/prog /tmp/rc_repro.march
  MARCH_TRACE_GC=1 /tmp/prog && scripts/gc-trace-report.py trace/gc
  ```
  Every object live at exit, with its type, allocation site and full inc/dec history, each step
  named `<fn>#<ordinal>:<runtime callee>`. `--site PATTERN`, `--addr HEX`, `--top N`.
- **`march query fn NAME FILE`**: the passes that changed a function and its body at the last
  one; `--at tir-perceus` shows it right after RC insertion, `--at tir-mono` before.
- **`--bisect-pass FILE`**: if an *optional* pass (inlining, fusion, known-call, ...) is to
  blame, it names the smallest set whose removal fixes the output. "No optional pass is the
  cause" points back at Perceus, Drop or codegen.
- **`--reduce FILE --oracle CMD`**: shrinks the program while `CMD` (exit 0 = still bad)
  holds. Make the oracle check that the candidate still compiles, or it finds a syntax error.
- **`MARCH_DUMP_TXT=all`** prints every TIR stage to stderr (`MARCH_DUMP_TXT=tir-perceus`
  filters by stage name). Use a fresh `HOME` or `--emit-llvm`: a warm cache skips the pipeline.

## 1. Get a minimal repro

If the bug surfaced from a large program, shrink it. If you only have a vague symptom, generate candidates:

> Ask an LLM: "Give me 10 small March programs that exercise [closures capturing lists / nested pattern matches / recursive data / HOFs with negative ints / etc.]. Each should be < 20 lines."

Compile and run each. The one that crashes or leaks is your repro. Shrink it with `--reduce` (above) or by hand until no line can be removed without losing the bug.

Save as `/tmp/rc_repro.march`.

## 2. Turn on the debug flags

Before diving into phase dumps, enable the built-in instrumentation. These print directly to stderr and are much faster to read than phase viewer output when you already have a hypothesis:

**`MARCH_DEBUG_PERCEUS=1`** — prints per-module RC insertion counts before and after elision/FBIP:

```
[perceus] main
  inserted:  inc=14 dec=12 atomic_inc=0 atomic_dec=0 free=3 reuse=2
  after elision+fbip: inc=8 dec=6 atomic_inc=0 atomic_dec=0 free=3 reuse=4
  cancelled: inc=6 dec=6 atomic_inc=0 atomic_dec=0
```

If `cancelled` pairs are wildly asymmetric (e.g. many incs cancelled, few decs, or vice versa), the elision pass is over-cancelling — likely the bug's source.

**`MARCH_DEBUG_BORROW=1`** — dumps the converged borrow inference map after analysis:

```
[borrow] main
  list_map(f:own, xs:borrow)
  string_eq(a:borrow, b:borrow)
```

If a parameter you expect to be borrowed shows `:own`, borrow inference is misclassifying it — Perceus will insert a spurious IncRC at every call site, which can mask or cause RC leaks.

Run both together on the repro:

```bash
MARCH_DEBUG_PERCEUS=1 MARCH_DEBUG_BORROW=1 \
  ./_build/default/bin/main.exe --compile -o /tmp/rc_repro /tmp/rc_repro.march
```

**`MARCH_SANITIZE=1`** — enable ASAN+UBSan on the compiled binary (clang paths only; OCaml stubs use `-g` from the dev profile instead):

```bash
MARCH_SANITIZE=1 \
  ./_build/default/bin/main.exe --compile -o /tmp/rc_repro /tmp/rc_repro.march
/tmp/rc_repro   # ASAN will print the exact allocation/free stack on error
```

Use ASAN when you have a crash but the Perceus IR looks correct — it means the bug is in the runtime (wrong pointer arithmetic, bad cast, use-after-free that the RC bookkeeping misses).

**`MARCH_DEBUG_RUNTIME=1`** — build the JIT `.so` with `-g` so you can step into runtime C functions in lldb:

```bash
MARCH_DEBUG_RUNTIME=1 dune exec march -- /tmp/rc_repro.march
lldb -- ./_build/default/bin/main.exe /tmp/rc_repro.march
```

**Never park, `lldb`-attach and `kill -9` a wedged compiled March process.** That sequence
kernel-panicked a Mac on 2026-09-09. Start it under `lldb` instead, or stop it with SIGTERM.
On macOS, ASAN binaries can hang under endpoint security; reproduce in the Linux container.

## 3. Dump phases

```bash
forge compile /tmp/rc_repro.march   # always dumps every phase (trace/phases/phases.json)
forge phases                        # serve the viewer at http://localhost:7777
```

For text you can grep, `MARCH_DUMP_TXT=all` or `march query fn NAME FILE --at <stage>` (§0.5)
is usually faster.

The phase viewer shows each TIR stage. The critical comparison is:

- **Pre-perceus** (e.g. after `dce` or `known_call`) — are the use sites correct as plain TIR?
- **Post-perceus** — is every use site bracketed by the right `IncRC`/`DecRC`?

If pre-perceus is correct but post-perceus has a missing/extra IncRC or DecRC, the bug is in `perceus.ml`. If post-perceus looks right but the program still crashes, the bug is in the runtime.

## 4. Categorize

Match the symptom to one of the known bug patterns. Each comes with a commit reference to read for context:

| Symptom | Likely cause | Reference commit |
|---------|--------------|------------------|
| Closure freed on first call, dangling on second | Captured FVs not in Perceus `borrowed` set; consuming call transfers ownership | `d2cf09e` |
| SIGSEGV in `march_incrc` / `march_decrc` | Runtime classifies a negative int or small value as a heap pointer | `d2cf09e` (IS_HEAP_PTR fix) |
| Double-dec after `let x = ... let x = ...` or branch-bound var | Shadow / branch-var handling in Perceus | `7cbb3b3` |
| RC underflow on borrowed scrutinee pattern match | Arms that take ownership of a borrowed scrutinee | `9930ce5`, `b87de10` |
| Used-twice binding inside a nested call (e.g. `foo(bar(t), t)`) | Perceus liveness walker can't see second use | `d2cf09e` (Check.run_loop fix) |
| Spurious IncRC on every string/list call site | Borrow inference marking the param `:own` instead of `:borrow` | Check `MARCH_DEBUG_BORROW` output |
| Asymmetric cancelled pairs in `MARCH_DEBUG_PERCEUS` | Elision pass over-cancelling one side | `lib/tir/perceus_elide.ml` `elide_cancel_pairs` |
| Abort (exit 134) when one var is passed at an owned AND a borrowed arg position of the same call, dead after | Owned transfer + spurious borrowed post-dec both consume the single reference | `a5dad194` (dual-position balancing inc) |
| Heap overflow / wrong FBIP reuse for a multi-type-param ADT (e.g. `Result`) | `same_arity` used the type-parameter count, not the constructor field count | `a5dad194` (`$fbip$` marker) |
| Abort (exit 134) when the SAME scrutinee is re-matched inside a sibling arm's sub-path | Scrutinee-borrowed re-add fed a cross-branch dec on top of the per-arm free → double-dec | `20d1d144` |
| Leak (one container cell per iteration) in a mutual tail-recursive loop over heap data | Mutual-TCO back-edge emitted before the Perceus dec-chain, stranding it in a dead block | `05d9e46b` (B7) |
| Wrong value or crash compiled when a field read from a record is used after the record's last use (`match d.tag`, `o.ap.f` then a call consuming `o`) | The record was released while a borrowed projection was live; check 3 reports `use-after-release` on the projection | `specs/progress/2026-10-08-perceus-parent-released-before-field-use.md` |
| Leak of a let-bound or parameter record that only one branch consumes | Scope-end aggregate drop placed on the wrong paths | `specs/progress/2026-10-12-perceus-param-drop-past-other-candidates.md`, `...-agg-drop-partial-release.md` |
| A builtin's heap argument leaks once per call | The C function only reads it, but `extern_borrow_table` (`lib/tir/borrow.ml`) has no row, so it is passed owned | recent `borrow:` commits, e.g. `b271ce3a1` |

If none match, read the post-perceus IR for your repro and ask: at every binding, does the inc/dec count match the number of consuming uses? If a value is used twice by consuming callees, there must be exactly one IncRC emitted before the first use. Cross-check the count against the contract in `specs/perceus-invariants.md` (§0) — the bug is usually a named clause being broken, not an arbitrary miscount.

## 5. Fix

**In `perceus_core.ml`** (or its `perceus_liveness.ml`/`perceus_elide.ml`/`perceus_fbip.ml`/`perceus_scrut.ml` siblings; see §1 above for which owns which function): most fixes are small and surgical — adding a case to a pattern match, updating the borrowed set, or fixing liveness tracking across a construct. Read the commits above for examples of the surgical style.

**In `runtime/march_runtime.c`**: usually a guard bug. Be careful with tagging — integer values live in the same slots as pointers and must be distinguished by tag bits (the full law is in `docs/value-representation.md`; the conditional-untag helpers are in `lib/tir/llvm_ctx.ml`). Record/collection builtins hand off values in the UNIFORM (tagged) representation as of the `record_put` uniform-handoff work (merge `c28595bb`): before it, an even `Int >= 4096` (page size) in natural repr was misclassified as a heap pointer and `march_incrc` dereferenced the integer's value — a SIGSEGV that looked like a loop-count threshold. Any new record-builtin emit site must coerce `i64→ptr`, never bare `inttoptr`.

**In user code**: if Perceus can't see a liveness pattern, extract a `let`:

```march
-- BEFORE (Perceus can't see t used twice):
try_prop(prop, Gen.tree_root(t))

-- AFTER (explicit binding makes liveness obvious):
let root = Gen.tree_root(t)
try_prop(prop, root)
```

## 6. Regression test

**TIR golden-snapshot infrastructure now exists** (landed W2.2, `test(tir): golden
snapshot infrastructure — post-lower + post-perceus dumps, UPDATE_SNAPSHOTS regen`):
`test/test_snapshots.ml` + `test/run_snapshots.ml`, corpus under
`test/snapshots/src/*.march`, committed goldens under `test/snapshots/lower/*.expected`
(post-`Lower.lower_module`) and `test/snapshots/perceus/*.expected` (post-`Lower` →
`Mono` → `Defun` → `Perceus`, i.e. after RC insertion/FBIP). The printer is
`lib/tir/pp.ml`'s `string_of_fn_def`/`string_of_type_def` (the human-readable form,
not `Tir.show_*`'s compact hash-fingerprint form); each dump is filtered to the
module's own fns/types (prelude Eq/Ord/Show/Hash impls and the builtin
Option/Result/List type defs are stripped — see `test/test_snapshots.ml`'s
top-of-file comment for the exact filter and the fresh-name-counter determinism
notes, e.g. `Defun.set_lambda_counter 0` before each dump).

**When you fix (or introduce) a Perceus/borrow/RC bug, add or update a snapshot**
in addition to (not instead of) the codegen/eval regression test below — a
snapshot is the only thing that pins the exact IncRC/DecRC/Reuse *shape* a human
can audit, rather than just the program's observable output:

```bash
dune build test/run_snapshots.exe
./_build/default/test/run_snapshots.exe -e              # verify against committed goldens
UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e   # regenerate after an intentional change
git diff test/snapshots/                                  # review the diff — this IS the code review artifact
./_build/default/test/run_snapshots.exe -e                # re-run without the env var: must be green
```

For a NEW bug pattern not yet in the corpus: add a `<20`-line `.march` fixture
under `test/snapshots/src/`, list it in `test/test_snapshots.ml`'s `corpus`, run
the `UPDATE_SNAPSHOTS=1` regen once to generate its `.expected` files, and
eyeball them before committing — you may be the first person to read that
exact IR shape (the Task 4 audit turned up a real double-`dec_rc` RC-underflow
bug this way: the SAME scrutinee re-matched inside a sibling arm's sub-path).
The snapshot harness also runs `--verify-tir`'s RC-balance check on every
post-Perceus snapshot, so a new fixture is checked for balance as well.

**The differential oracle catches RC underflows automatically now.**
`test/test_properties.ml` generates random well-typed programs, runs each through
the interpreter and the compiled binary, and compares. As of the W2.0 oracle fix
(`a5dad194`), a compiled binary killed by a signal (`rc_run >= 128`: SIGABRT=134,
SIGSEGV=139) while the interpreter succeeded is a hard **failure**, not a skip
(only a clean nonzero *error* exit still skips — see `test/test_properties.ml`
around the `rc_run >= 128` branch). So an RC underflow/UAF in any shape the
generators already produce will surface here without you writing a targeted test.
Two consequences:
- After a Perceus/borrow fix, run `dune build test/test_properties.exe &&
  ./_build/default/test/test_properties.exe -e` — a regression that reintroduces
  a crash-shaped RC bug fails the oracle even if your snapshot didn't cover it.
- If your bug's shape isn't generated yet, bias a generator toward it (e.g. calls
  passing one var at two positions with different borrow modes, dead multi-param
  ADT bindings before an alloc) rather than only adding a fixed fixture — the
  oracle then guards the whole *class*, not one program.

**The full-corpus conformance sweep is the `eval.ml` refactor gate.**
`test/test_oracle.ml` (the `@oracle` dune alias, a *slow lane* separate from
`@runtest`) sweeps every `bench/`+`examples/` program through the both-ways diff
(interpreter vs compiled). Unlike the property oracle it runs *curated, real*
language shapes, and as of the Phase-4 hardening a compiled **signal-crash** or
**internal-compiler-error (exit 3)** while the interpreter succeeded is a
divergence, gated by an explicit `known_divergence` list (open bugs, cited) kept
distinct from the `nondeterministic_allowlist` (actor/server/RNG programs). Run
it with `dune build @oracle` (or `HOME=<scratch> MARCH_BIN=<march> ./_build/default/test/test_oracle.exe`
in a worktree, isolated HOME to dodge the shared-cache fake-hang).

This sweep is the **interpreter-refactor gate**: `eval.ml` has no IR to diff, so
it can't use the byte-identical-IR gate the backend refactors used. Instead, a
change to `lib/eval/eval.ml` (or anything that alters interpreter output) must
leave the sweep with **zero NEW divergences** — every `[UN-TRIAGED FAILURE]` is
either a real interpreter/compiled regression you introduced or a program that
must be triaged into `known_divergence` with a filed bug. A green `@oracle` run
before and after your change is the interpreter analogue of "the IR is
byte-identical." Never suppress a new divergence by adding it to
`nondeterministic_allowlist` — that list is for genuine nondeterminism only.

Also land targeted regression coverage the way the existing suites do:

- **Codegen/IR-shape assertions** (new IR pattern, elision fix, borrow misclassification, ABI/tagging fix): add a test to `test/test_codegen.ml`, following the existing pattern of compiling a fixture and asserting on the emitted LLVM IR text (e.g. exact call-site counts, absence of a dead pattern) or on the compiled binary's stdout/exit code.
- **Runtime-level fixes** (crash, wrong pointer arithmetic, RC underflow/leak): add a test to `test/test_eval.ml` (interpreter-level parity) and/or `test/test_codegen.ml` (compiled repro) that runs the shrunk repro and asserts the correct output/exit code.

```bash
dune build test/run_codegen.exe test/run_eval.exe
./_build/default/test/run_codegen.exe -e
./_build/default/test/run_eval.exe -e
```

## 7. Benchmarks

Run the benchmarks most sensitive to RC changes — **always compiled** (interpreted mode can take hours on `fib`-shaped benchmarks):

```bash
march --compile --opt 2 bench/tree_transform.march -o /tmp/tree_transform && /tmp/tree_transform   # perceus / FBIP
march --compile --opt 2 bench/binary_trees.march -o /tmp/binary_trees && /tmp/binary_trees           # allocation / GC
march --compile --opt 2 bench/list_ops.march -o /tmp/list_ops && /tmp/list_ops                       # closures / HOFs
```

Compare to `specs/benchmarks.md` expected numbers. A significant regression means the fix added emit ops on a hot path — revisit.

## 8. Cache and staging (if you touched the runtime)

The cache key covers the compiler and the runtime sources the compiler actually compiles: the
**staged** copy in `_build/default/runtime`. A targeted `dune build bin/main.exe` does not
restage it, so a `runtime/*.c` edit is not in the build at all until you build something with a
runtime dependency:

```bash
dune build --root . @test/stage-source-trees bin/main.exe
diff -rq runtime _build/default/runtime   # must be empty
```

To rule the cache out, use a private `HOME`, or clear both stores (the project's
`.march/cas/artifacts-v2/` and `~/.march/cas/artifacts-v2/`; `artifacts/` is the old,
inert store).

