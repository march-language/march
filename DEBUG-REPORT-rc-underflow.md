# RC Underflow (compiled) — root cause + fix

**Symptom:** `march: RC underflow (rc was 0) — aborting` (SIGABRT, exit 134) in
COMPILED code, on origin/main (846505b4). Surfaced in forgepm when it starts
conduit's job workers (which use depot's `Pool.checkout`).

## Minimal repro (`/tmp/e.march`, ~32 lines)

```march
mod Main do
needs IO.Spawn
type Conn = PgConn(Int) | LiteConn(String)
actor Pool do
  state { n : Int }
  init { n: 0 }
  on Checkout(reply_to) do
    let _ = actor_reply(reply_to, Some(PgConn(42)))
    state
  end
end
fn describe(c) do
  match c do
  PgConn(fd)  -> "pg:" ++ int_to_string(fd)
  LiteConn(k) -> "lite:" ++ k
  end
end
fn checkout(pool) do
  let t = task_spawn(fn _ ->
    match actor_call(pool, Checkout(0), 5000) do
    Err(e)         -> Err(e)
    Ok(maybe_conn) ->
      match maybe_conn do
      None       -> Err("none")
      Some(conn) -> Ok(conn)
      end
    end
  )
  task_await_unwrap(t)
end
fn main() do
  match checkout(spawn(Pool)) do
  Ok(conn) -> println(describe(conn))
  Err(e)   -> println("err: " ++ e)
  end
end
end
```

Compiled: pre-fix aborts `RC underflow (rc was 0) ... tag=0` in `describe`;
post-fix prints `pg:42`, exit 0. This is depot's exact `Pool.checkout` shape
(`Some(DbConn)` niche-Option reply flowing through `actor_call` +
`task_spawn`/`task_await_unwrap`).

### Bisection (what each factor contributes)
- Drop the actor (fresh `Ok(Some(PgConn(42)))`): **no crash** — provenance matters.
- Drop `task_spawn` (call `actor_call` directly): **no crash**.
- Reply a bare `PgConn(42)` (no `Some`): **no crash** — the niche `Some` wrapper is required.
- Return the whole `Option` from the task instead of re-wrapping `Ok(conn)`: **no crash**.
- Concrete generic `thru(o: Option(Conn))`: **no crash** — it monomorphizes to `Option(Conn)` (niche), no reuse.

The crash needs all of: niche-`Some` reply value + delivered via `actor_call`
(whose reply type is a fully-polymorphic `Result(Option(a), _)` that stays an
unresolved TVar) + the `Some`-unwrap-then-re-box happening inside the task.

## Exact mechanism (value + invariant clause + pass/line)

TIR of the task closure, **pre-fix**:

```
Ok($f27350) -> dec_rc $t27347;
  let maybe_conn : Option('_35129) = $f27350 in
  case maybe_conn of
    None() -> alloc Result.Err("none")
    Some($f27348) -> let conn : '_35129 = $f27348 in
                     reuse maybe_conn as Result.Ok(conn)      <-- BUG
```

- The reply value is a **niche** `Some(PgConn)` — for a concrete `Option(Conn)`,
  `Some(x) ≡ x` (value-representation.md §7). So at runtime `maybe_conn` and its
  payload `conn` are the **same pointer**; there is no distinct `Some` wrapper cell.
- But `actor_call`'s reply type is fully polymorphic, so the consumer sees
  `Option('_35129)` = `TCon("Option", [TVar])`. `Repr.repr_of_ty` conservatively
  returns **Boxed** there (`niche_payload_ok(TVar) = false`, repr.ml).
- **Two repr classifiers disagree:**
  - Perceus's `scrutinee_shares_payload_storage` (perceus.ml) consulted
    `repr_of_ty` → **Boxed** → so `add_scrutinee_free_for` treated the value as
    a distinct boxed cell, emitted the scrutinee free, and marked it FBIP-reusable.
  - Codegen's `emit_case` (llvm_case.ml `effective_repr`, the abstract-arg
    recovery at lines ~126-133) **recovers Niche** for a niche-shaped `TCon`
    applied to TVar args — so the value is niche-encoded at runtime.
- FBIP then rewrote `Some(conn) -> Ok(conn)` into `reuse maybe_conn as Ok(conn)`.
  Since `conn` aliases `maybe_conn` (niche), the reuse **stores the payload into
  its own reused cell** — a self-referential `Ok` cell pointing at itself. When
  `main` matches `Ok(conn)` it frees that cell (`decrc_freed`, 1→0) and passes
  the now-dangling `conn` to `describe`, whose scrutinee dec underflows (0→-1).

  Runtime dec history (instrumented) confirmed: the `PgConn` cell (tag 0) is
  freed in `march_main` (`decrc_freed`, prev_rc=1) then dec'd again in
  `describe` (prev_rc=0 → underflow). No incs — a single cell consumed twice.

**Invariant clause violated:** value-representation.md §7 — *"erased (TVar)
Option payloads must stay NICHE at every commitment site, never fall back to
Boxed inconsistently across sites"* (the cross-module/erased Option repr-drift
class, commits `f0fe40cc`/`fbdadce4`). Perceus's FBIP-reuse site was an
un-migrated commitment site: it trusted `repr_of_ty`'s Boxed verdict while
codegen niche-encodes the same value. Also relates to perceus-invariants.md §5
(FBIP preconditions) — a niche `Some` cell is not a distinct allocation and must
never be offered for whole-cell reuse.

The existing `Perceus_fbip.args_alias_reuse` guard (added for the direct
`Some(result)->Ok(result)` niche self-reference) was defeated here because the
niche payload was renamed through `let conn = $f27348`, so `conn` ≠ `maybe_conn`
by NAME and the name-only alias check missed it.

## Fix (`lib/tir/perceus.ml`, `scrutinee_shares_payload_storage`)

Mirror codegen's abstract-arg niche recovery: when `repr_of_ty` returns Boxed
but the type is a niche-shaped `TCon` applied to abstract (TVar) args, treat it
as sharing payload storage (as codegen will). This suppresses the scrutinee
free and the FBIP reuse for the erased-niche Option, emitting a fresh
`alloc Result.Ok(conn)` instead — matching the concrete-niche path.

```ocaml
| Repr.Boxed ->
  (match ty with
   | Tir.TCon (name, args)
     when args <> []
          && List.exists (function Tir.TVar _ -> true | _ -> false) args
          && Repr.is_niche_shaped env.type_defs name -> true
   | _ -> false)
```

Post-fix TIR of the same arm: `Some($f) -> let conn = $f in alloc Result.Ok(conn)`
(no scrutinee free, no reuse).

## Test evidence

- **Repro pre/post:** `/tmp/e.march` (and `/tmp/rc_repro.march`, the full
  Pool.checkout shape) — pre-fix exit 134 `RC underflow`; post-fix exit 0 `pg:42`.
- **Regression test:** `test/test_codegen.ml`
  `test_erased_option_niche_fbip_no_underflow_compiled` (group
  `erased_option_niche_fbip_codegen`) — compiles + runs the repro, asserts
  `pg:42` + `EXIT:0` + no `RC underflow`. Provably fails pre-fix (pre-fix output
  is `RC underflow`/`EXIT:134`). Passes post-fix. (No interpreter parity arm: the
  interpreter's actor_call/task interaction doesn't deliver the reply for this
  shape — `err: no reply` — an unrelated interpreter limitation; the bug is a
  compiled-backend defect.)
- **Golden snapshot:** not added — the erased `Option(TVar)` reuse shape only
  arises through the `actor_call` polymorphic boundary, and actor/`spawn`
  programs are non-deterministic in the reduced snapshot pipeline (fails the
  post-lower determinism canary). The compiled regression test + differential
  oracle cover the class instead.
- **Snapshots** (`run_snapshots.exe -e`): 29 tests green — the fix changed **no**
  existing corpus golden (verified: `nested_generic_adt` etc. unaffected).
- **Codegen RC groups** (`run_codegen.exe`): `fbip` (7), `rc_types` (2),
  `scrutinee` (1), and the new `erased_option_niche_fbip_codegen` (1) all green.
- **Eval** (`run_eval.exe -e`): all 17 `perceus` tests green. One unrelated
  failure — `repl integration: renders the desugar diagnostic's message text`
  (a REPL pipe-into-match parse/desugar diagnostic, `test/test_eval.ml:1222`) —
  pre-existing baseline, causally untouchable by an FBIP-reuse predicate change.
- **Differential oracle** (`test/test_properties.exe -e`): the RC-relevant
  groups are green — `oracle: classify_compile`, `algebraic oracle`, and
  **`semantic properties (source)`** (the interpreter-vs-compiled diff that turns
  a compiled signal-crash into a hard failure) all pass. No RC-crash divergence.
  One unrelated failure — `parse+typecheck 2 (generated)`, a random-seed parser
  round-trip property (seed 907679514) that never runs Perceus — pre-existing,
  causally unreachable from an FBIP-reuse predicate change.

## forgepm end-to-end — a SECOND, distinct underflow (out of scope)

**My fix did NOT make compiled forgepm reach "listening".** But the remaining
crash is a **different bug**, not the one I fixed:

| run | toolchain | crash |
|---|---|---|
| pre-fix  | origin-test (no fix) | `RC underflow (rc was 0) tag=504556768` (exit 255) |
| post-fix | origin-test (fix)    | `RC underflow (rc was 0) tag=1008799104` (exit 255) |
| post-fix + instrumented runtime | | **SIGSEGV (exit 139)** before the decrc guard, no dec-history printed |

Both crash right after `WORKER-REPRO: starting conduit workers/cron`, i.e. in
conduit's worker/cron/node **startup** path — *before* any DB `Pool.checkout`
runs. The tag differs every run (504556768 vs 1008799104) because it is read
from a **freed/reused** cell, and adding per-op instrumentation flips the
failure from a guarded underflow to a raw SIGSEGV. That signature — garbage
tag, run-to-run variation, timing-sensitivity under instrumentation — is a
**non-deterministic use-after-free**, most likely a data race in the
multithreaded actor scheduler (or a systematic double-free in the worker/cron
startup), NOT the deterministic niche-Option/FBIP miscount I fixed (which is
in `Pool.checkout`, exercised only when a job actually runs).

forge confirmed it recompiled forgepm with the fixed toolchain
(`building with March origin-test` … `compiled … forgepm`), and the fixed
`origin-test` toolchain compiles+runs the minimal repro clean (`pg:42`, exit 0).

**Disposition: DONE_WITH_CONCERNS.** I root-caused, fixed, and regression-tested
one genuine compiled-only RC underflow — the niche-Option/erased-FBIP-reuse in
the exact `Pool.checkout` suspect shape. forgepm's *startup* crash is a separate,
non-deterministic UAF (probably scheduler concurrency) that needs its own
investigation and is not a surgical Perceus/repr fix.

## Scope

Surgical single-line-class fix in one pass (`perceus.ml`), aligning Perceus's
repr classification with codegen's for erased niche-shaped types. No runtime or
codegen change. The only source change is `lib/tir/perceus.ml`
(`scrutinee_shares_payload_storage`) plus the regression test.
