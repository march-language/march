---
name: march-debug
description: Debugging and triage tools for the March compiler. Use when a March program misbehaves, a test fails, compiled and interpreted output differ, something leaks, a compile is slow, CI is red, or you need to prove a refactor changed no behaviour.
---

# March debugging and triage

Organised by **symptom → first command → how to read it → what not to do**.
Every tool here exists on `main`; each entry is short and links the plan section
that has the depth:

- triage design: `specs/plans/diagnostics-and-triage-plan.md` (Part T, §13–§15)
- observability design: `specs/plans/incremental-codegen-cas-plan.md` (Part A, §6–§10)

Run the compiler as `./_build/default/bin/main.exe` (the `march` binary) after
`dune build --root . bin/main.exe`. A fresh worktree may ship a stale binary:
check `--help | grep -c <flag>` before trusting a flag is there.

**Never skip, disable or quarantine a test to get green.** A timing flake gets
one re-run and a comment naming it (the steward skill lists the known ones).
Anything else is a real failure until proven otherwise.

---

## Compiled output differs from interpreted, or a compiled program crashes

**First command:**
```bash
scripts/triage.sh FILE                 # add --expect OUT if the interpreter can't be trusted
```
It runs interp vs compiled, then (only if they differ, or with `--deep`) each
optional-pass switch in turn, splits a `MARCH_DUMP_TXT=all` dump into one file
per stage, and rebuilds with `MARCH_SANITIZE=1` on a crash. Private `HOME` and a
fresh temp project, so no cache can confuse it.

**Read it:** the `switches` line names the first switch that makes compiled match
("blamed"). None helps → a mandatory pass (mono/defun/perceus/drop/escape/trmc).
`--fn NAME` reports the first stage where that function's body changed. The last
line is the next command to run.

**Don't:** rerun the ladder by hand before reading triage's screen. Don't trust a
"no divergence" from a narrow repro; a bug can stay live in the full program.

## Which TIR stage went wrong?

**First command:**
```bash
MARCH_DUMP_TXT=all ./_build/default/bin/main.exe --compile FILE -o /tmp/x 2> dump.txt
MARCH_DUMP_TXT=tir-mono ...            # substring filter on the stage name
```
Pretty-printed TIR on **stderr**, one `===== tir-<stage> =====` section per
pass. Read forward to the first wrong body. `Opt`'s inner passes print nothing
here.

`--dump-phases` is different: a node/edge graph for `tools/phase-viewer.html`,
written to `trace/phases/phases.json` (and legacy `march-phases/`) **relative to
the CWD**, with function names but no bodies. Use it for the viewer and for
`Opt`'s per-pass snapshots, not for reading code.

**Don't:** blame codegen before reading `tir-lower`. A "codegen mis-lowering" has
been a parser bug before.

## Is the TIR itself malformed?

**First command:** `--verify-tir` (or `MARCH_VERIFY_TIR=1`, which also reaches
the REPL/JIT and every compile `test_oracle` runs).
```bash
./_build/default/bin/main.exe --verify-tir --compile FILE -o /tmp/x
```
Checks scoping and references after every pass (each variable bound, each callee
resolvable, indirect calls through something callable, no duplicate fn names).
From `tir-mono` on, it also checks types: call arity, each argument's
representation against its parameter, case-branch binder counts, projected
field names, and no source-named type variable left in a signature.

**RC balance:** `--verify-tir-rc` (`MARCH_VERIFY_TIR_RC=1`) also walks every
path of every function after Perceus. It reports an over-release or a use after
release with the object, its binding and the path (`case kv: $Tuple2`).
`MARCH_VERIFY_TIR_LEAKS=1` adds leaks. It is a separate switch because it
currently reports three known Perceus bugs, two in stdlib code every program
links (`specs/todos/2026-10-07-perceus-releases-parent-before-field-use.md`).
Filter for your own function's name.
A finding exits 3 and names the stage and function: the first stage listed is
the pass that broke it. Always on in `run_snapshots` and the hand-rolled
pipelines in `test_codegen.ml`. Design: observability plan §6 (A1).

**Don't:** suppress a finding by name without classifying it; the checks' false
positives are fixed in `lib/tir/tir_verify.ml` with a comment saying why.
## Which commit broke it?

```bash
scripts/bisect-ir.sh GOOD BAD FILE          # first PR merge whose emitted IR for FILE differs
scripts/bisect-output.sh GOOD BAD FILE [--expect OUT]   # ... whose compiled program behaves differently
```
Both run in a throwaway worktree with a private `HOME`, bisect `--first-parent`
along `main`'s PR merges, skip commits that do not build, and print the blamed
merge with its `specs/progress/` entry. `bisect-ir` renumbers fresh names
(`$lamN`, numbered `%` locals) before hashing, because a lambda added anywhere
in the stdlib renumbers every program's IR; `--exact` hashes the raw IR.
`bisect-output` compiles each step against that commit's own `runtime/` and
`stdlib/` (`MARCH_RUNTIME_DIR`, `MARCH_STDLIB`), so runtime changes are seen.

**Don't:** `git bisect` by hand in your own checkout: a targeted build there
does not restage `runtime/`, and the stale `_build` stdlib copy leaks in.

## Which optional pass?

**First command:** `--bisect-pass`.
```bash
./_build/default/bin/main.exe --bisect-pass FILE              # vs the interpreter
./_build/default/bin/main.exe --bisect-pass FILE --expect OUT # vs a known-good stdout
```
It reports the smallest set of optional TIR passes whose removal makes the
compiled output right. If disabling all of them does not help, it says so; then
the bug is in a mandatory pass, codegen or the runtime. Any build takes
`--disable-pass P1,P2` (or `MARCH_DISABLE_PASS`, in the CAS key), and
`--list-passes` names the passes. Each probe is a full compile, so expect about
twenty of them. `MARCH_BISECT_TIMEOUT` (seconds, default 60) bounds each run.

Outside the TIR passes: `MARCH_NO_UNBOX=1`, `MARCH_NO_INLINE_RC=1`, `--no-opt`
(triage.sh tries these). `MARCH_NO_TRMC` **does not exist** (removed
2026-09-21; TRMC is mandatory).

**Shrink the program first** when it is large:
```bash
./_build/default/bin/main.exe --reduce FILE --oracle 'sh oracle.sh {}'
```
The oracle exits 0 while the candidate still shows the bug. Make it check that
the candidate still compiles and runs, or the reducer will "find" a syntax
error. The reducer removes declarations, then lines, and writes
`FILE.reduced.march`.

**Don't:** compare an A/B with a switch on a warm cache without checking the
switch is in the CAS key (`MARCH_DEBUG_CASFLAGS=1`, below). A switch missing from
the key reuses whichever variant was cached first.

## Crash, memory corruption, use-after-free

**First command:** `MARCH_SANITIZE=1` (ASan + UBSan build of the program).
```bash
MARCH_SANITIZE=1 ./_build/default/bin/main.exe --compile FILE -o /tmp/x_asan && /tmp/x_asan
```
`MARCH_SANITIZE=1` builds also abort on `march_free` of a shared object and on a
TRMC hole fill that finds the slot non-null.

`--debug-info` emits per-function DWARF (a `DISubprogram` per March fn plus
`!march.provenance`) and links with `-g`, so `lldb`, ASan reports and `perf`
name March functions. `--dump-provenance` prints the fn-name → origin table
(which specialisation or lambda a mangled name came from).

**Don't:** park, `lldb`-attach and `kill -9` a wedged compiled March process
(it has kernel-panicked a Mac). On macOS, ASan binaries can hang under endpoint
security; reproduce in a Linux container.

## Wrong value, ASan-clean

**First command:** `MARCH_REPR_AUDIT=1` on the compile. It records every
representation decision codegen makes and reports a type encoded or decoded by
mixed families (boxed vs unboxed, niche vs tag). ASan-clean wrong values are
usually a repr mismatch, not a use-after-free.

## Leak: who took the unreleased reference?

**First command:**
```bash
./_build/default/bin/main.exe --rc-trace --compile -o prog FILE    # or MARCH_RC_TRACE=1
MARCH_TRACE_GC=1 ./prog
scripts/gc-trace-report.py trace/gc            # --site PATTERN, --addr HEX, --top N
```
**Read it:** every object live at exit with its type, allocation site and full
inc/dec history, each step named `<fn>#<ordinal>:<runtime callee>`. Exit 1 while
anything is live. `kill -USR2 PID` flushes a live process's trace first.

**Don't:** treat an RC unit test asserting a mechanism ("has `EIncRC`") as proof
of no leak; one has pinned a leak before. A leak fix can unmask a use-after-free
elsewhere: run the sanitizer after it. Release IR is byte-identical with
`--rc-trace` off.

## Cache looks wrong (stale binary, flag ignored)

```bash
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile FILE -o /tmp/x   # key: target, flags, src=, ch=
MARCH_DEBUG_CASFLAGS=2 ...                                                      # + per-SCC hash lines
rm -rf .march/cas/artifacts-v2 ~/.march/cas/artifacts-v2                       # BOTH: builds write through to ~/.march; NOT artifacts/ (inert v1)
```
`src=` digests only the source/TIR input and is comparable across compiler
builds; `ch=` folds in the compiler executable. After editing `runtime/*.c`, a
targeted `dune build bin/main.exe` does **not** restage the runtime; build
something that does (`dune build --root .`) or the edit is not in the build.

## Compile is slow

**First command:** `--timings` prints per-stage stamps to stderr (each TIR
pass's line also carries its counts: `fns allocs stack inc dec reuse jp`), including
`alloc-contract` (the `@[no_alloc]` analyses) and `cas-hash` (SCC build + Merkle
hashing before the post-TIR lookup).
```bash
scripts/compile-time-bench.sh          # cold / warm / edit scenarios over a corpus, three buckets
```
**Don't:** use absolute-ms baselines as regression detectors. Only a same-box
A/B against a compiler built from the base commit means anything; check the load
average first.

## Prove a refactor changed no behaviour

Record a baseline on the base commit, check on yours. **Prove the oracle goes
RED on an intentional perturbation before trusting a GREEN** (two of these once
shipped broken and were certified "verified"). Run under a **private `HOME`**.

| Oracle | What it compares | Blind to |
|---|---|---|
| `scripts/ir-oracle.sh baseline\|check DIR` | `--emit-llvm` hashes over ~240 programs | the interpreter (`lib/eval/`), `lsp/` |
| `scripts/refine-oracle.sh baseline\|check DIR` | refinement diagnostics over ~297 fixtures | its corpus has no violation programs: perturb a verdict, not a message |
| `scripts/types-oracle.sh baseline\|check DIR` | core-AST inference results + diagnostic text (two tiers) | programs it doesn't contain |
| `scripts/determinism-oracle.sh [--corpus small\|all] [--self-test]` | same source under cold/warm `HOME` × two cwds: `.ll` and `--dump-impl-hashes` identical | needs no baseline; proves environment-independence, not correctness |

None of them sees match-arm order, module-initialisation order, or behaviour the
corpus doesn't exercise. `--dump-impl-hashes` (with `--emit-llvm`/`--compile`)
writes `<file>.hashes`: symbol, impl hash, sig hash per post-TIR def.

`dune build @types-check` **without `--force`** is an empty check that exits 0.

## TIR shape changed on purpose

```bash
UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e
git diff test/snapshots/                # this diff IS the review artifact
```

## Machine-readable diagnostics

`--check-json` emits diagnostics as NDJSON on stdout (what `forge fix` consumes).

## A test or CI job is red

1. Reproduce with `scripts/run-tests.sh <suite>` (never a bare `dune runtest`
   inside a worktree; pass `--root .`).
2. Check `main`'s own recent runs for the same failure before blaming the diff.
3. A known timing flake gets **one** re-run and a PR comment naming it. A second
   red is real.
4. For CI log reading and flake policy, load the `steward` skill.
