# RC trace site ids: `--rc-trace` + `scripts/gc-trace-report.py` (A3 of the incremental-codegen plan, 2026-10-06)

Plan: `specs/plans/incremental-codegen-cas-plan.md` §8. The runtime's `MARCH_TRACE_GC=1`
trace (`runtime/march_runtime.c`, `gc_emit`) already recorded every alloc / inc_ref /
dec_ref / free with address, count and tag. What was missing was *who*: nothing named the
function that took an unreleased reference, and nothing folded the JSONL into per-object
histories. This adds both, without changing a release build.

## What landed

- **Site ids, out-of-band.** `lib/tir/llvm_rc_trace.ml` is a post-emission text pass in the
  mould of `llvm_rc_inline.ml`: for every `call ... @march_*(` on an instruction line of a
  `define`, it inserts `call void @march_rc_site_set(i32 N)` before the call and
  `... (i32 -1)` after it, and appends a table of `"<fn symbol>#<ordinal>:<callee>"` strings
  that a module constructor (merged into the existing `@llvm.global_ctors` when there is
  one) hands to `march_rc_sites_register`. It runs before the inline-RC rewrite, which is
  untouched: the twins take their out-of-line branch whenever tracing is on, so the stored
  site reaches the runtime. The plan's draft said "before each RC call"; bracketing *every*
  runtime call is what makes a string allocated inside `march_string_concat` read as
  `leak_loop#3:march_string_concat` instead of "runtime", and the callee half of the label
  is what makes a history readable without the IR.
- **Runtime** (`runtime/march_runtime.c`): `_Thread_local int32_t march_rc_site` plus the
  setter and the table registration; `gc_emit` writes `"site":N` on every event; the table is
  dumped to `trace/gc/sites.json` (at trace init, or at registration if that comes later,
  e.g. a hot patch). OS-thread-local is sound because preemption is cooperative
  (`march_tls_reductions` checks at compiled-function entry and loop back-edges), so a green
  thread cannot migrate between the store and the call it precedes; the known blur (a
  parking builtin, a builtin calling back into compiled code) is documented at the slot.
- **Two gaps in the existing trace, fixed because the report made them visible on its
  first run:** `march_string_alloc` emitted no `alloc` event (strings, the commonest leaked
  object, had histories that began at their first inc_ref with no allocation site), and
  `march_string_lit_static`'s immortal cells showed as live. Strings now trace their birth,
  a cell becoming immortal emits an `immortal` event, and the CAS-loser copy's free is
  traced. `march analyze-trace` learned the `immortal` event too.
- **Flush on signal.** SIGUSR1 is the scheduler's preemption tick (`march_preempt_signal`),
  so the flush signal is SIGUSR2, or SIGUSR1 when `MARCH_PREEMPT_SIGNAL` moved preemption
  onto SIGUSR2. Installed only when tracing is on. The handler is async-signal-safe by
  construction: `pthread_mutex_trylock` the trace mutex and `fflush` on success, else leave a
  request the next `gc_emit` honours.
- **`scripts/gc-trace-report.py`**: per-object histories (an address reused after a free
  starts a new generation), every object live at the last event with type, allocation site
  and full history, every negative count or double free, a per-site summary (allocs, incs,
  decs, frees, net), `--top N`, `--site PATTERN`, `--addr HEX`, `--all`; exit 1 while
  anything is live or inconsistent. Needs no compiler: `sites.json` is beside the trace.
- **Driver**: `--rc-trace` / `MARCH_RC_TRACE=1` (`bin/flags.ml`, `bin/main.ml`
  `rc_trace_enabled`), CAS tag `rctrace` next to `noinlinerc`; `finish_ir` is the one funnel
  for both post-emission rewrites, used by `--compile` and `--emit-llvm`.
- **Checked extras under `MARCH_SANITIZE`** (`-DMARCH_RC_CHECKS` rides on the sanitize clang
  flag, and `Llvm_toplevel.rc_checks` is set from the same predicate so IR and runtime agree):
  `march_free` of an object with rc > 1 aborts naming the object and pointing at the report
  (the trace is flushed first); the TRMC hole fill (`ESetField`) loads the slot and calls
  `march_hole_fill_check`, which aborts if it is not the null the allocation stored.
- **Tests** (`test/test_rc_trace.ml`, in `run_codegen`): the rewrite on a synthetic module
  (bracketing, ordinals per function, quoted symbols, ctor-table merge and creation,
  identity without runtime calls); `--emit-llvm` with the switch off has no site machinery
  and with it on has sites, the table and the inline twins; and the whole loop on
  `test/native/rc_trace_leak_site.march`, a program that leaks ON PURPOSE (an extern bound
  to `march_incrc`), whose report must show exactly three live objects, all allocated at a
  `leak_loop#N:march_string_concat` site and retained at `leak_loop#N:march_incrc`, four
  immortal cells, nothing inconsistent, and blame nothing on `balanced_loop`; plus a clean
  string-churning program that must report zero live objects (the direction that keeps the
  first test honest). The two existing Slow compiled leak tests in `test_codegen.ml`
  ("compiled Vec3 loop moves march_live_allocs by zero", "compiled branch-built aggregate
  loop does not leak") now, on failure, rebuild with `--rc-trace`, rerun under
  `MARCH_TRACE_GC=1` and append the report to the alcotest message
  (`Test_helpers.rc_trace_report`).

## Verification

- `scripts/ir-oracle.sh`: baseline from an `origin/main` compiler
  (`eea23d6dc`), check with this branch's compiler, switch off: see the PR for the result;
  the same check with `MARCH_RC_TRACE=1` is the red control.
- `scripts/check-runtime-sources.sh` and `scripts/check-actor-rc-stores.sh` pass (the TLS
  store is not an actor refcount word).
- First real run, before the string-alloc fix: the leaked string's history began at its
  `inc_ref` and four literal cells were listed as live. After: one live object, allocated at
  `march_main#4:march_string_concat`, retained at `march_main#6:march_incrc`, released once at
  `march_main#8:march_decrc_local`, final rc 1.

## Not done / follow-ups

- Site ids are dense per module. A hot patch registers its own table and replaces the main
  program's, so a trace spanning a deploy mislabels the pre-deploy sites; the plan's unit
  split (B3) is where a shared table belongs.
- The `march_free`-of-shared check prints the address and a pointer at the report; it does
  not keep an in-memory history (that would be a per-object map for the life of the run).
