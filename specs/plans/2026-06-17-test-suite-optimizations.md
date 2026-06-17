# Test Suite Optimizations

Four targeted improvements to build speed, test isolation, and incremental
edit latency. Items 1 and 2 are the priority; 4 and 5 are follow-on.

---

## Item 1 — JIT test HOME isolation

**Problem.** `test_jit` (7 tests) shares `~/.cache/march/libmarch_rt_test_<hash>.so`
across concurrent dune processes and worktrees. A session that rebuilds the
runtime with different sources writes a new `.so` under the same hash (the hash
covers content, so a diverged worktree produces a *different* hash — but the
*other* session may dlopen a stale artifact if the content hasn't changed while
the ABI has). The result is spurious JIT failures when two worktrees run `dune
runtest` simultaneously.

**Root cause.** `lib/jit/repl_jit.ml:731`: `let home = Sys.getenv "HOME"`.
The cache path is `$HOME/.cache/march/`.

**Fix.** Override `HOME` in the `test_jit` dune stanza so each build-tree gets
its own JIT cache:

```dune
; in test/dune — replace the existing (test (name test_jit) ...) with:
(test
 (name test_jit)
 (modules test_jit)
 (libraries march_jit alcotest)
 (action (setenv HOME %{project_root}/_build/jit_home (run %{test}))))
```

`%{project_root}/_build/jit_home` is inside `_build/`, so `dune clean` wipes
it automatically.

**Verification.** Run `dune runtest` twice in parallel from two different
worktrees — both should pass the JIT suite independently.

---

## Item 2 — Split `test_march.ml` into per-runner modules

**Problem.** `test/test_march.ml` is ~24 000 lines compiled as one library
(`march_test_lib`). Any change to any test function — or adding a new one —
requires recompiling the entire 24k-line file before any of the four runners
can start. On a warm build this is the dominant incremental cost.

**Current structure:**

| Runner | Suite function | Tests |
|--------|---------------|-------|
| `run_compiler.exe` | `compiler_suites` (line 22086) | 202 |
| `run_eval.exe` | `eval_suites` (line 22361) | 214 |
| `run_codegen.exe` | `codegen_suites` (line 22649) | 267 |
| `run_stdlib.exe` | `stdlib_suites` (line 23005) | 780 |

**Natural split points in the test function body** (confirmed by `grep -n`):

| New module | Line range (approx) | Contents |
|---|---|---|
| `test_compiler.ml` | 1–2113 | lexer, AST, parser, desugar, keywords, typecheck, session types, MPST, app, supervisor, registry, dynamic\_supervisor, spec\_construction, shutdown, capabilities |
| `test_eval.ml` | 2114–3816 | eval, repl\_parity, type\_map, convert\_ty |
| `test_tir.ml` | 3817–8365 | defun, fusion, perceus, lean\_theorem\_properties, borrow\_inference, escape\_analysis, atomic\_rc, actor\_tir\_lowering |
| `test_codegen.ml` | 8366–22085 | known\_call, struct\_fusion, tco\_codegen, nested\_lit\_pattern\_codegen, actor\_compile (LLVM IR tests), session\_compile, all JIT helpers, JIT parity |
| `test_stdlib_march.ml` | 22086+/stdlib section | sort, map, set, bytes, logger, flow, actor\_module, tap, repl\_compiler\_parity, tail\_recursion, type\_level\_nat, testing\_library |

**Shared helpers** that all modules need must move to a small `test_helpers.ml`
(or stay in a retained thin `test_march.ml` that just re-exports them):
- `parse_module` (line 236)
- `with_reset` (line 1381)
- `mk_var`, `mk_fn`, `mk_module`, `mk_var_lin` (lines 4895, 8366–8428)
- `make_stdlib_module`, `make_jit_test_module` (lines 7906, 7089)

**Target dune shape:**

```dune
; Shared helpers — compiled once, linked by all runners
(library
 (name march_test_helpers)
 (wrapped false)
 (modules test_helpers)
 (libraries march_lexer march_parser march_ast march_desugar
            march_typecheck march_errors march_effects march_eval
            march_tir march_repl march_debug march_scheduler
            march_cas march_modules march_resolver march_forge
            march_lint alcotest str unix threads.posix))

; Per-topic test libraries
(library (name march_test_compiler) (wrapped false)
  (modules test_compiler)
  (libraries march_test_helpers ...))
(library (name march_test_eval) ...) 
(library (name march_test_tir) ...)
(library (name march_test_codegen) ...)
(library (name march_test_stdlib_march) ...)

; Runners (unchanged filenames)
(test (name run_compiler) (modules run_compiler)
  (libraries march_test_compiler alcotest))
(test (name run_eval) (modules run_eval)
  (libraries march_test_eval alcotest))
(test (name run_codegen) (modules run_codegen)
  (libraries march_test_codegen alcotest))
(test (name run_stdlib) (modules run_stdlib)
  (libraries march_test_stdlib_march alcotest))
```

**Execution.** This is a mechanical refactor — no logic changes:
1. Create `test/test_helpers.ml` with shared helpers extracted from `test_march.ml`.
2. Split the body into `test_compiler.ml`, `test_eval.ml`, `test_tir.ml`,
   `test_codegen.ml`, `test_stdlib_march.ml`. Each file ends with its `*_suites`
   list (currently in `test_march.ml`).
3. Update `run_*.ml` to call the suite function from the new module.
4. Update `test/dune` as above.
5. Delete (or gut) `test_march.ml` once all suites migrate.

**Expected benefit.** Editing a codegen test recompiles only `test_codegen.ml`
(~14k lines) and `run_codegen.exe`, not all 24k lines + 4 runners.

---

## Item 4 — Per-fixture runtime dep granularity

**Problem.** Every native compile fixture declares `(source_tree ../runtime)`.
Any change to any runtime file (e.g. `march_http.c`) invalidates all 9 native
fixtures and forces all 9 to re-run `march --compile` + `clang`.

**Fix.** Replace `(source_tree ../runtime)` with the specific `.c`/`.h` files
each fixture actually needs. Most fixtures only need the core subset:

```
march_runtime.c  march_runtime.h
march_scheduler.c  march_scheduler.h
march_heap.c  march_heap.h
march_gc.c  march_gc.h
march_message.c  march_message.h
march_deque.h
```

HTTP, TLS, WebSocket, and compression runtime files are only needed by fixtures
that exercise those features (currently none of the 9).

**Implementation.** Replace each fixture's `(source_tree ../runtime)` dep with
an explicit `(glob_files ../runtime/march_{runtime,scheduler,heap,gc,message}.*)`
or a named set of `(file ...)` deps.

**Savings.** Editing `march_http.c` currently triggers 9 clang invocations
(each ~2–4 s). After this fix: 0.

---

## Item 5 — Stdlib TCenv warm-up sequencing

**Problem.** The first `dune runtest` after a stdlib change causes all four
parallel runners to race to rebuild `stdlib_tcenv_<hash>.bin`. Three of the
four builds are wasted — only one wins; the others block on the rename.

**Fix.** Add a dedicated warmup alias that the four runner stanzas depend on:

```dune
; in test/dune
(rule
 (alias stdlib-warmup)
 (deps (file %{exe:../bin/main.exe})
       (source_tree ../stdlib))
 (action (run %{exe:../bin/main.exe} --warmup-tcenv)))
```

This requires a `--warmup-tcenv` flag in `bin/main.ml` that runs
`Typecheck.check_stdlib` and exits — the same work the test runners do on
first access, but done once sequentially before they start.

**Note.** Only worth implementing if the race is observable. Measure before
building: run `dune runtest` on a cold stdlib cache and check whether multiple
runners emit "stdlib cache miss" in stderr simultaneously.

---

## Priority order

1. Item 1 (JIT isolation) — ~30 min, fixes 7 persistent spurious failures
2. Item 2 (split test_march.ml) — ~4–6 h, biggest day-to-day dev velocity win
3. Item 4 (runtime dep granularity) — ~1 h, low risk, good cleanup
4. Item 5 (warmup sequencing) — measure first; skip if race isn't observed
