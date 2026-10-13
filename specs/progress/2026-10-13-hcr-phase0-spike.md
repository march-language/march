# HCR Phase 0 spike: native code swapped across a boundary, under ASan

**Date:** 2026-10-13. Closes the Phase 0 checkbox of
`specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md`; design in
`specs/hot-code-reload.md` § Central Tension, § Phase 0. Prototype (throwaway,
not in CI): `specs/spikes/2026-10-13-hcr-phase0/`.

## Verdict: NO-GO on Model B as specified (ORC JIT in the server), GO on fixing native swap

Native code CAN be swapped across a boundary with values in flight, and the
"defun fault" the spec feared does not exist in today's compiler. But the
experiments found three ways a native swap corrupts or leaks memory, and all
three hit the native patch model that **already ships** (`--compile-so` patches,
`forge deploy hot`), not only a future JIT. They are a loader-independent
property of native swap: an ORC loader would inherit every one. So:

1. Fix the three findings below in the shipped `.so` model first (each has a
   todo, two are small). That is where the risk is today.
2. Do not build Phase 6 (ORC in the server) on the current evidence. What it adds
   over the shipped model is compiling on the target, which means linking LLVM
   into every production binary, and ORC has a known macOS problem with the
   external thread-local the generated code reads (below). Reopen it if a
   concrete need appears (no build host, or patch latency), after the three
   fixes.

Model A (the interpreter trampoline) was never built (`MARCH_TRAMPOLINE` is
declared and used nowhere). The shipped design is in effect "Model B without a
JIT": AOT-compiled native patches. The soundness questions Phase 0 was meant to
answer for Model B apply to that model, so the spike tested it.

## What was swapped, and how

`app.march.in` serves N requests. Each one builds a `SpikeConn` record
(`{path: String, headers: List(String), status: Int}`) and calls four boundary
functions in `mod Handler`, with the caller still using the values afterwards:

- `handle(conn)`, a record parameter;
- `mk(conn)`, which returns a closure the caller then applies;
- `tag()`, which returns a string literal;
- `count(c.headers)`, a borrowable `List(String)` parameter.

Every 997th closure and tag string is kept until the end and used after all the
swaps. Mid-run the program swaps `Handler.*` in-process to the k-th patch `.so`
(`swap_shim.c`: dlopen, `__march_init`, dlsym, then `march_hcr_activate` as one
deploy, which is the reload server's ACTIVATE minus socket, signature and CAS).
Base: `--compile --opt 2 --hot-reload App`. Patches: the same program with
another `Handler` body, `--compile-so --opt 2 --hot-reload App`. The leak metric
is `live_allocs()` at exit minus at start: 7 with no swap, 12 after a clean
swap (5 objects once, not per request). 20 000 requests unless noted, with the
swap at request 10 000. Machines: macOS arm64 (M-series), and Linux arm64 in
the `march-ci-ubuntu-step6b` container (glibc, ASan + LSan,
`detect_leaks=1`). Both used `MARCH_SANITIZE=1` for both base and patch.
macOS ASan hot-loads fine here: the in-process path uses
`RTLD_NOW|RTLD_GLOBAL`, not `RTLD_DEEPBIND`.

| # | swap | plain (macOS) | ASan macOS | ASan + LSan Linux |
|---|---|---|---|---|
| C | v1 → v1 (control) | delta 12, correct | clean | clean, no leaks |
| E1 | v1 → v2: Conn still only read, **new closure shape** (captures String + List instead of Int) | correct values; **leak 49 962 objects** (5 per request after the swap) | no error (no LSan on macOS) | LSan: 4 × 9 990 objects |
| E1a/b | bisect E1: only `handle` changes / only `mk` changes | 12 / 49 962 | | |
| E1' | E1 with the patch registering its closure drops (spike diff) | delta 12 | | clean, no leaks |
| E2 | `count`'s List param **borrowed → owned** (v1 → v3) | **SIGSEGV** | **heap-use-after-free**: freed in `patch1.so` `Handler.count`, then `march_incrc` on it in the base's `serve` | same UAF |
| E2' | owned → borrowed (v3 → v1) | **leak 40 012** (4 per request) | | LSan: 40 000 allocations, 1.13 MB |
| E2r | the record param (`handle(conn)`) flipped the same way | balanced, delta 12 | | |
| E4 | 4 deploys (ring of 3 reclaims v1's patch), then call the kept closures | **SIGSEGV, pc == fault address** (jump into unmapped code) | SEGV | SEGV, pc == addr |
| E4c | E4 with dlclose suppressed (`HCR0_NO_UNLOAD=1`) | correct | clean | E1's leak only |
| — | string literals returned by reclaimed versions, read after the unload | fine (E4: `kept tags len=406` printed before the crash) | fine | fine |

## Findings

### 1. Closure code pointers outlive their version's `.so` (use-after-unmap, crash)

A closure is a heap cell with its apply function's code pointer at +16. A
version's refcount (`march_dispatch_enter`/`leave`) counts only calls in
progress, so once a version is out of the 3-slot ring and has no call running,
`march_dispatch_stage` dlcloses its `.so` (`slot_dlclose`,
runtime/march_dispatch.c). Any closure that version built and someone kept (in
actor state, a Vault, a callback registry, a `plug`) now points at unmapped
code. E4 reproduces it with four deploys. In production it takes three later
deploys of the same slot. The design said captured closures "carry their
version and keep it pinned" (§ Part 3). Nothing implements that. The same
problem would reach ORC as `ResourceTracker::remove`.
Todo: `specs/todos/2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md`.

### 2. Borrow modes are part of the boundary ABI, and the deploy gate does not check them (UAF or leak)

`Borrow.infer_module` runs over the whole program, so the running caller is
compiled against the borrow mode of the callee version it was built with. If a
patch changes a borrowable parameter (String, List, any ADT; `Kind.borrowable_of`)
from borrowed to owned, the callee releases a reference the caller still holds
(E2, ASan UAF). The reverse change leaks one reference per call (E2'). The
safety gate compares `sig_hash`, which is the type signature only
(`Serialize.serialize_fn_sig`): both of E2's patches have the same `sig_hash`
(`bd9fc78c…`) with different modes, so `forge deploy hot` would accept them.
Fix with no runtime cost: fold each parameter's borrow mode into the hash the
gate compares (or a separate `abi_hash`). The existing rule that callers of a
sig-changed slot must ship in the same deploy then covers a flip. The
alternative from the spec, freezing boundary parameters as owned, costs an
inc/dec per borrowable argument per call.
**Fixed 2026-10-13:** `specs/progress/2026-10-13-hcr-borrow-mode-not-in-sig-hash.md`.
The slot `sig_hash` now folds in the modes (HCR ABI `march-hcr-v4`), and a
mode-only change is refused outright: the caller-coverage rule turned out not
to make it safe (a running caller frame on `main` still crashed with every
caller in the deploy), see
`specs/todos/2026-10-13-hcr-coordinated-sig-change-running-caller-frame.md`.

**The record (`Conn`) case is already safe, and the spec's cost premise is out
of date.** Records and tuples are never borrowed parameters
(`Kind.borrowable_of` returns false for `TRecord`/`TTuple`, so they are owned
for TCO reasons), so E2r balanced. `Conn` crosses the boundary owned in every
build, so a reloadable `Conn` boundary gives up no "borrow elision for the Conn
middleware path" (§ Part 10 (d)), and there is no record-borrow cost to measure.

### 3. Defun: no fault, but a patch's closures leak their captures when dropped outside their apply

March's "defunctionalization" (`lib/tir/defun.ml`) is closure conversion: a
closure struct with a code pointer, called through `ECallPtr`. It is not a
closed tag set with a global `apply` switch. A patch's new lambda shape flows
into the base and is called correctly (E1: values right, ASan clean). The
passes that would bake a lambda into another function's body (`Hof_spec`,
owned-call clones) are already off under `--hot-reload`. So the spec's Central
Tension #2 does not hold for this compiler: a separate "no-defun-at-boundary"
scheme is not needed.

The leak in E1 has a different cause. A closure released anywhere other than
its own apply (`march_clo_release`) looks its capture-release function up in a
runtime table keyed by apply code pointer. Only the main binary's prologue
fills that table, so a patch's closure types are missing from it, and their
captures leak (the runtime comment already names "one built by a hot patch" as
a known leak). The spike diff (`patch-registers-closure-drops.diff`: `__march_init`
calls the patch's `march_clo_drops_register`, same for record shape drops) removed
the leak, LSan-clean on Linux (E1'). It has to land together with finding 1:
the table's keys are never removed ("a fragment's code is never unloaded"), so
once patches unload, a registered drop is a dangling function pointer, and a
later patch mapped at the same address could match a stale key.
Todo: `specs/todos/2026-10-13-hcr-patch-closures-not-in-drop-table.md`.

### Other risks checked

- **Stack frames of old code still executing:** covered by design. A call in
  progress holds `refs` (enter/leave), reclaim needs `refs == 0` (a seq_cst
  Dekker pair in `march_dispatch_stage`), and `march_hcr_activate` WAITs
  instead. Spawned tasks and actors are pinned by epoch. Untested here beyond
  E4's main-thread calls. Closures (finding 1) are the hole, not frames.
- **TLS:** since 2026-09-25 a patch carries no runtime, so its references to
  runtime TLS bind to the host's one copy. Generated code also reads an
  external `thread_local` directly (`@march_tls_reductions`, used by
  `task_reductions()`). dlopen resolves it. ORC on macOS does not:
  `llvm_builtins.ml` drops the reduction check in REPL mode to avoid "the
  emutls symbol-not-found error from ORC JIT on macOS". A Model B server would
  need the same workaround, or a fix in the JIT's TLS handling.
- **Layout drift:** records are structural in TIR, so adding a field should
  change the `sig_hash` of every function that takes the record, and the gate
  should refuse the patch. Not tested here.
- **Static data in a patch:** string literals a reclaimed version returned were
  still readable after its dlclose, under ASan on both platforms. Other
  immortal statics in a patch (static closures are off under `--hot-reload`)
  were not audited.
- **Observability:** `--rc-trace` names a patch's sites from the BASE's site
  table (ordinals collide), so a trace of a swapped program misattributes them.
  Use the bisection (E1a/E1b) instead.

## Boundary deoptimization (Phase 0 item 4)

Already measured on this box, and not re-run: `--hot-reload` versus plain on
`bench/list_ops_nested.march` is +1.1 % (G1,
`specs/progress/2026-09-23-hot-reload-boundary-cost.md`), or +4.3 % with the
2026-09-25 callee-only dispatch rule
(`specs/progress/2026-09-25-hcr-dispatch-callee-only-rule.md`). Both are below
the 10 % threshold. `bench/list_ops.march` puts nothing on the boundary. The
"Bastion request bench" no longer exists (bastion was removed). For the two
costs this spike was asked to measure:

- **Frozen borrow ABI:** nothing to measure for records (owned regardless, see
  finding 2). For String/List/ADT parameters, the recommended fix (borrow
  modes in the gate's hash) has no runtime cost. Only the rejected
  alternative (all boundary parameters owned) would have one.
- **No-defun-at-boundary:** nothing to measure. Closures already use code
  pointers, and the lambda-baking passes are already off under `--hot-reload`,
  so their cost is inside the numbers above.

## Not done (time box)

- ORC was not prototyped. The ORC host today is the OCaml REPL process
  (`lib/jit/jit_orc*.ml`). A server-side loader means embedding LLVM in the
  runtime, which is the main cost of Phase 6. The memory findings above are
  independent of the loader.
- Actors mid-handler were not exercised here. The epoch and drain machinery has
  its own two-node tests (`hcr_new_code_session`, `protocol_*`).

## Open questions for Phase 6, if it is reopened

1. Code lifetime: pin a version's code from every closure it allocates (an RC'd
   code object per version, checked on reclaim), or never unload code. Without
   a tracing pass, March cannot find old closures the way BEAM's purge finds
   old processes.
2. ABI hash: which borrow and ownership facts beyond parameter modes are part
   of a slot's ABI (return ownership, `Clo_flags` conventions, unboxed
   aggregates in closure captures)?
   Answered for the native model (2026-10-13, the borrow-mode fix's progress
   record): only parameter modes vary per function. Returns are always owned,
   the closure-call convention is fixed, and representation is in the type
   hash.
3. TLS from JIT'd code on macOS (`march_tls_reductions`): fix the JIT's TLS
   handling, or route the read through a runtime call?
4. Is target-side compilation needed at all, given AOT `.so` patches built and
   cross-compiled by forge already work?
