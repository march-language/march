# Shell: fragment and session leaks on the node (and review F9)

Filed 2026-10-06 as `specs/todos/2026-10-06-shell-fragment-leaks.md`; fixed
2026-10-08. Also settles finding F9 of
`specs/reviews/2026-10-07-shell-r5-review-packet.md`.

## The report

LeakSanitizer (Linux, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`) running
`test/shell/session.txt` against `test/native/shell_node.march` reported
16 286 bytes in 287 allocations left on the node. By 2026-10-08
`session.txt` had grown, and the same run reported 352 431 bytes in 10 839
allocations.

## How it was measured

`live_allocs()` is a builtin, so a shell input can read the node's live
object count. A session that runs an input N times between two
`live_allocs()` readings gives the leak per input. Two sessions against one
node, each starting with `live_allocs()`, give what a session leaves
behind. Both work on macOS, without a sanitizer build.

## Four causes

1. **No deep drops in fragments.** `Repl_jit.shell_compile` ran Perceus and
   then Escape, but not `Drop.run`, which the native pipeline
   (`Contract_pipeline`) runs between them. So a `dec_rc` of a list, record
   or variant that the code does not take apart lowered to
   `march_decrc_local`, which frees only the top cell. That leaked most of
   each rendered result and of each intermediate. Rendering
   `List.range(1, 1000)` leaked 4 000 objects per input, and
   `Json.parse(s)` leaked 36.

2. **F9: every input took a reference on every binding.** It was broader
   than the review guessed. The slot bridge
   (`Llvm_repl.emit_prev_slot_bridges`) called `march_incrc` on every
   heap-typed slot at the entry of every fragment, whether or not the input
   used it. Perceus, meanwhile, treats slot variables as BORROWED in the
   fragment's `main` (`Perceus.perceus ~repl_vars`). It never releases one,
   and it increments one itself before any owned use. So nothing balanced
   the bridge's increment.
   - The count only grows, so the live-object count per input stays flat.
     The cost shows when the session ends: one decrement cannot free a value
     that the session's later inputs incremented.
   - Seen as one object per session: a `let j = …` followed by any later
     input retained `j`'s top cell. With cause 3 fixed, it retained the
     whole value.
   - Calls to borrowing node functions (`Json.parse(s)`) were balanced in
     the TIR: no increment and no release. The leak was the bridge, not
     borrow modes.

3. **Shallow release at session end.** `slot_range_release`
   (`runtime/march_shell.c`) called `march_decrc` on each slot word that
   `IS_HEAP_PTR` accepted. That had two problems:
   - It freed only a value's top cell. A session's `let xs =
     List.range(1, 1000)` and `let ys = List.map(xs, …)` left 2 999 objects
     behind.
   - A Float slot holds raw IEEE bits. 2.5 is `0x4004000000000000`, which
     `IS_HEAP_PTR` accepts. So `let f = 3.5` in any session **killed the
     node with SIGSEGV** (`addr=0x400c000000000000`) when that session
     ended.

4. **Closure captures.** Two problems:
   - **No registration.** Fragments did not register their capture-release
     functions (`$clodrop$`, `march_clo_register_drops`), so a closure that
     a fragment released through its function type kept its captures.
   - **No known-call pass.** The fragment pipeline had no `Known_call` pass.
     So `List.filter`'s local `go` stayed a `call_ptr` callee, its
     environment was judged not to own the predicate it captured
     (`Drop.owning_apply_fns`), and nothing released the predicate. That was
     one closure per call: `evens(4)` on the test node.

## The fixes

- `lib/jit/repl_jit.ml` `shell_compile`, in order:
  1. `Known_call.run` before Perceus, as natively.
  2. Perceus.
  3. A synthesized `shell_slot_drop(x) = dec_rc x` for an init fragment that
     stores a heap value.
  4. `Drop.run`, which makes every bare `dec_rc` of an aggregate, including
     the one in `shell_slot_drop`, the type's deep drop.
  5. A prune of what nothing reaches. `Drop.run` makes a release for every
     actor and closure type of the program, more than 80 of a 100-function
     fragment, so the prune shrinks a typical fragment's IR from 353 KB to
     77 KB. It keeps the slot drop and the releases the fragment registers.
- `lib/tir/llvm_repl.ml` `emit_repl_expr`, three new options, each passed
  only by the shell. The local REPL is unchanged.
  - `~borrow_slots`: no increment in the slot bridge. The slot's own
    reference covers the fragment's lifetime.
  - `?slot_drop_fn`: after the store, `march_repl_set_drop(slot,
    @shell_slot_drop)`.
  - `~register_drops`: the fragment's `march_clo_drops_register` (the same
    `Llvm_toplevel.clo_drop_registration` a program's `main` calls), run
    before its body. `Llvm_toplevel.closure_drop_wants` is split out of it
    so that the prune can keep those releases.
- `runtime/march_extras.c`: `march_repl_set_drop` / `march_repl_get_drop`, a
  release per slot.
- `runtime/march_shell.c`:
  - **Session end.** `slot_range_release` runs each slot's registered
    release and leaves a slot without one alone (a scalar). It runs the
    releases with `march_rc_set_thread_concurrent(1)`, since the session
    thread is not a scheduler thread and a value may also be held by tasks.
  - **A stuck input.** If an input of the session ended `TIMEOUT
    uncancellable`, it may still be running and reading bindings it borrows.
    The values are then kept (leaked) instead of released.
  - **Fragment files.** Each fragment file is unlinked right after `dlopen`.
    Every input used to leave its ~70 KB `.so` in `$TMPDIR/march-shell-<pid>/`
    for good.
- `runtime/march_runtime.c`: the closure-release registry takes
  registrations while the scheduler runs. Registration is under a mutex.
  Each entry is filled in place, its release before its key (release store,
  acquire load). Growing publishes a new table, and the old one is never
  freed because a lookup may still be probing it; the retired tables add up
  to less than the live one. Before this, registration happened only in
  `main`'s prologue, before any thread could look an entry up.

## Before and after

Per input, live objects left per run (macOS, `let xs = List.range(1, 10)`,
`let s = "{\"a\": 1}"`, 10 runs each):

| input | before | after |
|---|---|---|
| `List.range(1, 1000) limit: 2000` | 4000 | 3 |
| `List.range(1, 100)` | 256 | 3 |
| `xs` | 31 | 3 |
| `s` | 12 | 4 |
| `Json.parse(s)` | 36 | 16 |
| `List.map(xs, fn x -> x * x)` | 40 | 3 |
| `evens(4)` | 13 | 3 |
| `List.length(evens(100))` | 1 | 0 |
| `List.reverse(items(5)) limit: 3` | 136 | 25 |
| `string_length(to_string(xs))` (`xs` of 500) | 1002 | 3 |

What is left after the fix does not grow with the data. It is exactly one
object per string literal the fragment evaluates; see Residual below.
`List.length(["a"])` leaves 1, `List.length(["a", "b", "c"])` leaves 3, and
an input without literals leaves 0.

Per session, objects left once it ended:
- `let xs = List.range(1, 1000)`, `let ys = List.map(xs, …)`, two uses: 2 999
  before, 0 after.
- `let f = 3.5`: the node crashed before; nothing is left after.

LeakSanitizer, Linux arm64 (`march-amdr-repro`), node built with
`MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`, `ASAN_OPTIONS=detect_leaks=1`; the
node's `main` returns after a fixed sleep, so LSan reports at exit:
- `session.txt`: 352 431 bytes in 10 839 allocations before, 7 776 bytes in
  7 allocations after.
- `session.txt` + `big.txt` (the 1000-element bindings): 444 263 bytes in
  13 838 allocations before. Before the known-call change, with the other
  fixes in, it left 7 904 bytes in 12 allocations, the same as
  `session.txt` alone: the bindings no longer stay.
- The 7 left:
  - `march_ctor_table_ensure`'s table (4 allocations, 7 712 bytes), one per
    process and the same for any program that prints a variant;
  - two Float boxes from the node's own native `Json.parse` (one of them in
    `main`): a native leak, now
    `specs/todos/2026-10-08-json-parse-number-float-leak.md`;
  - one cell under `session.txt`'s panicking `List.head` input (see
    Residual).
- The full stress run (`session.txt`, `big.txt`, a Float binding, a session
  of closure, tuple, Option, Map and rebound bindings with a deliberate
  mid-`List.map` panic, `link.txt`, and 20 calls of a node function on a
  binding) had **no AddressSanitizer errors**. Its leaks: the ctor table, the
  `Json.parse` Float boxes, and the deliberate panic's live values (a
  1000-element list).

## Residual (`specs/todos/2026-10-08-shell-fragment-retention.md`)

- **One immortal string per literal site a fragment evaluates.** Literals are
  one immortal cell per site (`march_string_lit_static`), and every input is a
  new `.so` with new sites. LSan does not report them, since they are
  reachable from the loaded fragment.
- **The fragment's mapping.** The `.so` stays loaded: anything it allocated
  may point at its code or data. The file itself is now unlinked.
- **A panic leaks what the input held when it panicked.** `panic` long-jumps
  out of the fragment, the same as a panicking task in a native program, so
  a 1000-element list live at the panic stays. Bindings are not affected:
  inputs no longer hold references on them.
- **The local REPL** (`march repl`, `Repl_jit.lower_module`) has causes 1,
  2 and 4 too: `specs/todos/2026-10-08-repl-jit-fragment-leaks.md`.

## Tests

`test/dune` `native_shell_leak.out`, inputs in `test/shell/leak.txt`, which
has two checks:
- **Per input.** Inputs that each leaked run three times between two
  `live_allocs()` readings, after one warm-up round, and the difference must
  be 0. The inputs are `List.length(evens(100))` (closure capture) and
  `Result.is_ok(Json.parse(s))` (shallow drop). Before: 30.
- **Per session.** A second session reads `live_allocs()`. Ending the first
  must have released its bindings (`xs`, `ys` and a parsed `r`, more than
  1 500 objects), and its `let f = 2.5` must not have crashed the node.
  Before: the node died at the end of the first session, and the second
  session could not connect.

RED with only the bridge increment restored (`~borrow_slots:false`, every
other fix in): "the session end released 0 objects (1528 at its end, 1528
in the next session)". So the check catches F9 on its own.

The four shell goldens (`native_shell_{session,node,skew,link}.out`) are
unchanged, and all five pass on macOS arm64 and on Linux arm64.
`scripts/run-tests.sh -q compiler test_jit codegen` and the TIR snapshots
pass.

**Cost of the registry change.** On a microbenchmark that drops 4 million
capturing closures through `march_clo_release`, compiled `--opt 2` on an M3
under load, CPU time was 0.394 s median against 0.385 s before. That is the
table pointer's acquire load and one more indirection. Acquire loads on
every probe cost ~10%, which is why the probes are relaxed. `bench/list_ops`
showed no difference within noise.

ASAN/LSan recipe, for the next leak hunt:
1. Copy the tree into `march-amdr-repro` and build `bin/main.exe`,
   `test/shell_check.exe` and `@@runtime/default`.
2. Build a copy of `shell_node.march` whose `sleep_ms` is shorter (e.g.
   30 s) with `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`.
3. Run the node under `ASAN_OPTIONS=detect_leaks=1` with
   `MARCH_STDLIB`/`MARCH_RUNTIME_DIR` pointing into the tree.
4. Drive sessions with `--shell-inputs`, then wait for the node's `main` to
   return.
5. Map `frag-N.so` in a leak trace to an input through the audit log: the
   Nth `"result":"ok"` line.
