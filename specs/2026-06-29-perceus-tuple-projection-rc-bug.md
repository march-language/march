# Perceus tuple-field-projection RC under-count — evidence, fix path, alternative

**Status:** root-caused with a minimal reproducer; first fix attempt failed (broke
codegen). Compiler fix not yet landed. forgepm's compiled binary is blocked on it.

**Owner needed:** someone fluent in `lib/tir/perceus.ml` ↔ `lib/tir/llvm_emit.ml`
FBIP/niche codegen. This is not a safe drive-by edit.

**Repros (committed):**
- `specs/repros/perceus_tuple_proj_rc_min.march` — 30 lines; crashes compiled, correct interpreted.
- `specs/repros/perceus_tuple_proj_rc_full.march` — faithful forgepm publish shape.
- `specs/repros/perceus_tuple_proj_rc_control_ok.march` — control: same logic via record field-access, works.

---

## 1. Summary

Compiled March under-reference-counts a value projected out of a **tuple** (or any
`needs_rc = false` aggregate) in a `case` arm when that value **escapes** the arm.
The aggregate's field is freed while a live reference still escapes → use-after-free.
The interpreter is unaffected (OCaml GC). This is the sole remaining blocker for a
reliable natively-compiled `forgepm` binary; it manifests on at least two routes
(multipart publish, home page).

This was originally mis-framed (by an earlier session) as an HTTP-scheduler / async-I/O
bug. That framing is wrong — see §7.

---

## 2. Minimal reproducer

```march
mod T do
  type Conn = { hdrs : List((String, String)) }
  pfn lookup(pairs, key) do
    match pairs do
    Nil -> None
    Cons((k, v), rest) -> if k == key then Some(v) else lookup(rest, key)
    end
  end
  pfn get_req_header(conn, name) do lookup(conn.hdrs, name) end
  fn boundary(content_type) do
    match String.split_first(content_type, "boundary=") do
    None -> None
    Some((_, after)) ->
      let t = String.trim(after)
      if String.byte_size(t) == 0 do None else Some(t) end
    end
  end
  fn run(conn) do
    match get_req_header(conn, "content-type") do
    None -> "no-ct"
    Some(ct) ->
      match boundary(ct) do
      None -> "no-b"
      Some(b) -> let d1 = "--" ++ b   let d2 = "==" ++ b   "[" ++ d1 ++ "|" ++ d2 ++ "]"
      end
    end
  end
  fn main() do
    let conn = { hdrs : Cons(("content-type", "multipart/form-data; boundary=" ++ String.trim("  Xbnd  ")), Nil) }
    println(run(conn))
  end
end
```

- Interpreter: `[--Xbnd|==Xbnd]`.
- Compiled: SIGSEGV (exit 139), empty stdout.
- `MARCH_SANITIZE=1`: AddressSanitizer `heap-buffer-overflow` in `memcmp` (the
  `split_first` inside `boundary` reads a freed buffer).

Build/run a repro with the dev-tree compiler:
```bash
cd /Users/80197052/code/march && dune build bin/main.exe
TMPDIR=<writable> ./_build/default/bin/main.exe --compile -o /tmp/r specs/repros/perceus_tuple_proj_rc_min.march
/tmp/r ; echo "exit=$?"                 # exit 139
TMPDIR=<writable> ./_build/default/bin/main.exe specs/repros/perceus_tuple_proj_rc_min.march   # interpreter oracle
```

---

## 3. Root cause (evidence chain)

1. **It's `ct` that is corrupt, not `b`.** `march_string_slice`/`march_string_trim`
   call `march_string_lit` = `march_string_alloc` + `memcpy` (`runtime/march_runtime.c`),
   so slices/trims **copy** — `b` does not alias `ct`. ASAN points at the `memcmp`
   inside `boundary(ct)`'s `split_first`, i.e. `ct` itself is already freed.

2. **`lookup` returns its field without `inc_rc`; record field-access does inc.**
   Post-Perceus TIR (`--dump-tir`):
   - `get_req_header` (record field) → `inc_rc conn.hdrs; lookup(...)`.
   - `lookup` Cons/Tuple2 arm → `dec_rc <tuple>; let v = <field>; … True() -> Some(v)`
     with **no `inc_rc v`**.
   - The control repro, taking `ct` via a *record field* (`conn.ct`, which emits
     `inc_rc`), does **not** crash. Same `boundary`+double-use. Only the **list
     `lookup`** path crashes. → the difference is the projection, not the use.

3. **"Works by luck" timing.** `rc_min` (use the looked-up value immediately) passes;
   adding the `boundary(ct)` call — whose `split_first` allocates — reuses `ct`'s
   freed buffer and corrupts it. Classic UAF masked by immediate use.

4. **Why the field is under-counted:** `lib/tir/lower.ml:1092-1094` types **every**
   constructor-pattern br_var as `unknown_ty` (`TVar "_"`). `needs_rc (TVar "_") = true`
   but `needs_rc (TTuple _ | TRecord _) = false` (`perceus.ml:236-237`). So the heap
   **tuple** br_var (the `(K,V)` head of `List((K,V))`) is misclassified as a heap-RC
   value. The tuple/record-aware borrow handling in `perceus.ml`'s `scrutinee_borrowed`
   (the `match v_ty with TTuple | TRecord -> true` case, ~line 1001) is keyed on the
   **erased** type and therefore never fires; the field is treated as an owned move
   but the aggregate is still recursively `dec_rc`'d, freeing the moved-out field.

5. **Confirmed control:** forcing an owned copy in `lookup`'s success arm
   (`Some("x" ++ v)`) eliminates the crash — confirms under-ownership of `v`.

---

## 4. Two failed fix attempts → the real blocker is llvm_emit niche codegen

Both independent angles that make the tuple `needs_rc = false` (the correct
classification) hit the **same latent `llvm_emit` bug**, which is now the actual blocker.

**Attempt 1 — `perceus.ml`: guard `add_scrutinee_free_for` to skip `$Tuple…` frees.**
- Broke codegen: `'%niche_none10' is not a basic block`.
- Did not fix the minimal repro (so the fatal `dec_rc` is not *only* from
  `add_scrutinee_free_for` for this shape).

**Attempt 2 — `lower.ml:1092`: type a tuple-pattern br_var as `TTuple` instead of
`unknown_ty`.** (Detect `Ast.PatTuple` sub-patterns structurally — `ty_of_span` on the
composite tuple-pattern span returns nothing because the typechecker only records leaf
variable spans.) This correctly removed the spurious `dec_rc` for simple cases, BUT:
- Same codegen break on the publish-shaped repro: `'%niche_none10' is not a basic block`.
- The minimal repro stopped crashing (exit 139 → 0) but produced **empty** output — the
  reuse/borrow lifetime of the now-`needs_rc=false` field is still wrong on the
  FBIP-reuse path.

**Root blocker (concrete):** `lib/tir/llvm_emit.ml` creates a niche-None SSA value with
`let z = fresh ctx "niche_none"` (lines ~3533 and ~3701, in the niche-alloc and
niche-reuse paths). When the tuple's RC ops are removed/changed, a `br`/`phi` ends up
referencing that **value** (`%niche_none10`) as a **basic-block label** → LLVM verifier
rejects it. So the niche-encoded `Option` codegen is coupled to the presence of the
tuple's RC ops; any correct RC fix must be paired with a fix to this niche emission.

**Implication for the fix:** the work is a CASCADE across three subsystems. Progress:

- **(a) lower.ml — DONE-ish (present in tree):** `lower.ml:1092` types a tuple-pattern
  field `TTuple` (detect `Ast.PatTuple` sub-patterns structurally). With this, the
  post-Perceus TIR is correct: no `dec_rc` of the tuple, `v` is `inc_rc`'d on escape,
  the spurious `reuse pairs` is gone.
- **(b) llvm_emit niche collision — FIXED:** root cause was a fresh-NAME collision, not a
  block-structure problem. `fresh` (SSA values, `ctx.ctr`) and `fresh_block` (labels,
  `ctx.blk`) are independent counters but shared the prefix `"niche_none"`, so a value
  `%niche_none10` and a block `niche_none10` could collide (LLVM shares the value/label
  namespace). Fix: give the niche-None *value* a distinct prefix (`"niche_nullval"`) at
  the two `fresh ctx "niche_none"` sites (llvm_emit ~3533/3701). After this the publish
  repro compiles cleanly and no longer crashes.
- **(c) STILL OPEN — an optimizer/inliner RC drop (the "empty output" symptom):** once
  (a)+(b) remove the crash, `get_req_header` gets INLINED into its caller, and the
  resulting `let h = conn.hdrs in lookup(h, …)` is emitted **without** the `inc_rc conn.hdrs`
  that the standalone `get_req_header` had (`conn` is a borrowed param, so `conn.hdrs` is a
  borrowed-field var; the inc that should fire when it escapes into the consuming `lookup`
  is missing post-inline). `lookup` consumes the borrowed list reference → the looked-up
  string comes back empty. This is an inline/cprop/borrowed-field interaction — a DIFFERENT
  subsystem from (a) and (b). Repro: `rc_ct` compiles & doesn't crash but prints empty.

This three-subsystem cascade (Perceus typing → niche codegen → inliner RC) is why this is
compiler-owner work. (a)+(b) are landable and correct; (c) needs the inliner/borrow
interaction fixed. Validation gate for the whole: `dune runtest` + the three repros (must
print the interpreter's output) + RC benchmarks + forgepm Playwright.

---

## 5. Proposed path forward (recommended)

**Two tracks, in parallel; they are independent.**

### Track A — unblock forgepm now (no compiler change)
Force owned copies at the boundaries where a borrowed aggregate field escapes into
later allocation:
- `get_req_header` result and `req_body` result in `lib/forgepm/api/packages_handler.march`
  (`run_publish`): bind `let ct = force_copy(<header>)`, `let body = force_copy(req_body(conn))`,
  where `force_copy(s)` is a guaranteed-fresh-buffer copy (e.g. a tiny `String` helper that
  round-trips the bytes — verify it is not optimized to identity).
- Home route (`lib/forgepm/web/web_router.march` `home`): same treatment for the
  `list_popular(8)` / `list_recent(5)` projections that feed `home_page`.
- Gate the compiled binary on the full Playwright suite (29/0) + the existing concurrency
  stress, run against `MARCH_HTTP_SEQUENTIAL=1` (per the committed runtime work).

Cost: small, local, reversible. Risk: low (no shared-toolchain change). Downside: a
workaround per escape site; must be removed once Track B lands.

### Track B — fix the compiler properly (the real fix)
Preferred: **stop erasing tuple/record br_var types in `lower.ml`.** At
`lower.ml:1092-1094`, give each pattern br_var its real field type (derivable from the
scrutinee's type instantiated at the constructor) instead of `unknown_ty`. Then a tuple
br_var is `TTuple`, `needs_rc = false`, the spurious aggregate free never arises, and
`scrutinee_borrowed`'s tuple/record case fires so escaping fields are duped correctly —
the existing, tested machinery does the right thing without new special-casing.
- Where the concrete field type is genuinely unavailable (polymorphic `V` still `'_NNNN`),
  fall back to the current behavior but route through the borrow-aware path (see Track-B
  alternative below).
- Validation gate (all must pass): the three committed repros; `dune runtest` (full
  compiler + snapshot suite); a NEW snapshot test for this pattern in
  `test/test_snapshots.ml`; RC benchmarks (`bench/tree_transform`, `binary_trees`,
  `list_ops`) within tolerance of `specs/benchmarks.md`; forgepm cold build + Playwright 29/0.
- Then Phase 5 (toolchain reinstall, hazard-controlled) + remove Track-A workarounds.

**Sequencing:** land Track A first (forgepm reliable on the compiled binary for the known
routes), then Track B as a separate, properly-budgeted compiler change owned by whoever
maintains `perceus.ml`/`llvm_emit.ml`.

---

## 6. Plausible alternative path

**Fix in `perceus.ml` by adding the compensating `inc`, keyed on the constructor tag
rather than the erased type — without removing any free.**

Rationale: the failed attempt removed the free and broke niche codegen. The inverse —
*keep* the aggregate free, but ensure escaping tuple/record fields are `inc`'d — should
not touch block structure. Concretely: in the per-branch logic where `scrutinee_borrowed`
is computed (`perceus.ml` ~line 988), also treat the scrutinee as borrowed-for-field-RC
when `br.br_tag` denotes a tuple/record destructure (prefix `"$Tuple"`, or a record tag),
so its br_vars are added to `la` and `find_inc_vars` dups the escaping ones. Leave
`add_scrutinee_free_for` untouched.

Risks / why it's the alternative not the recommendation:
- `scrutinee_borrowed = true` currently *implies* "not freed in this branch"; making a
  tuple both field-borrowed (dup on escape) **and** freed may double-handle dead fields or
  the aggregate box — needs careful reasoning about the net RC on each field (escaping:
  `+1 dup` then `−1` from the box free = net 0, correct; dead: `−1` from box free only,
  correct; box: freed, no leak — *if* the dup lands and the box free still recurses).
- Every condition in this region guards a documented past regression (sort_by `9930ce5`,
  Toml `table_get`, `Array.get`, closure-FV `d2cf09e`, HAMT `Map.node_fold`). A change
  here must re-prove all of them via `dune runtest`.
- It special-cases tag strings in the RC pass, which is more fragile than fixing the type
  at its source (Track B preferred).

Use this alternative if Track B's "thread real types through `compile_matrix`" turns out
to be too invasive (compile_matrix is intentionally type-erased and may not have the
field types in hand).

---

## 7. Correction to the original framing (so it isn't re-introduced)

The original task described this as depot's postgres socket I/O being "scheduler-dependent
— async socket op never completes because HTTP worker threads don't pump the scheduler."
That is **false**: the socket builtins (`march_tcp_connect/recv_exact/send_all` in both
`runtime/march_http.c` and the interpreter's `eval.ml`) are **fully blocking**; there is no
async op to pump. The real, separate issues were:
- **Bug #1 (fixed, committed `90164158`):** `SIGUSR1` preemption landing in `getaddrinfo`
  (async-signal-unsafe on macOS) → SIGILL on DB routes. Masked around blocking calls.
- **Bug #2 (handled, committed `90164158`):** compiled handlers can't run on raw pthread
  pool workers (no scheduler-thread context) — they crash *and* mis-render even
  single-threaded. Mitigated with `MARCH_HTTP_SEQUENTIAL=1` (handlers on the accept-loop
  green thread). The architecturally-correct successor is scheduler green-thread handlers
  (`march_sched_spawn`); an earlier attempt crashed (likely green-stack size) and is
  deferred. The plan's "pump the scheduler on worker threads" option is moot — there is no
  async I/O to drive.
- **Bug #3 (this document):** the Perceus tuple-projection RC under-count. Pure
  single-threaded miscompilation; nothing to do with threading.

---

## 8. State of the tree

- **march** (`90164158`): runtime HTTP reliability fixes (preemption mask, evloop opt-in,
  atomic-RC flag, `MARCH_HTTP_SEQUENTIAL`, `MARCH_NUM_SCHEDULERS`). `perceus.ml` is
  **clean** (failed attempt reverted). Installed toolchain (`~/.march/versions/local-main`)
  carries only these runtime fixes; backup at `local-main.bak-2026-06-29`.
- **forgepm** (`c873365`, `8e3f371`): CSRF `~H` `conn` threading + auth hardening; the
  compiled-binary reliability plan doc. No Track-A workaround applied yet.
- **Interpreter (`forge run`) is the reliable path today:** 29/1-skip/0-fail Playwright,
  every route including publish and home.
- Bug #3 recorded in `specs/todos.md` / `specs/progress.md`.
