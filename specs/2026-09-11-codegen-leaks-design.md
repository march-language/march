# Six compiled-only leaks: one ownership story, six boundaries

**Date:** 2026-09-11
**Status:** design; nothing here has landed
**Scope:** the six open `specs/todos/` items below. Every `file:line` was read
on this date at `2b32b130`; where a todo's pointer has moved or its stated
mechanism does not match the code, this doc says so rather than repeating it.

| Todo | One-line gap | Effort |
|---|---|---|
| [`2026-09-06-closure-capture-release-widening`](todos/2026-09-06-closure-capture-release-widening.md) | every capture read pins `$clo`; the deep-drop gate declines most closures | M |
| [`2026-09-04-unboxed-aggregate-niche-payload-leak`](todos/2026-09-04-unboxed-aggregate-niche-payload-leak.md) | `Some(P2(..))` box never freed in the niche arm | S |
| [`2026-08-21-ecallptr-owned-arg-borrow-callee-leak`](todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md) | caller says owned, apply fn says borrowed; fresh arg leaks | L |
| [`2026-08-22-boxed-ctor-heap-field-binder-not-dropped`](todos/2026-08-22-boxed-ctor-heap-field-binder-not-dropped.md) | `One(s) -> string_length(s)` leaks `s` | S (see §4: attribution is likely wrong) |
| [`2026-08-12-simd-nontco-vector-param-leak`](todos/2026-08-12-simd-nontco-vector-param-leak.md) | vec box for a `ptr`-slotted callee released by nobody | M |
| [`2026-08-12-float-boxing-task-trampoline-leak`](todos/2026-08-12-float-boxing-task-trampoline-leak.md) | Float box aliased from `task[3]` outlives the Task | S |

**Leak oracles that exist today** (grep-verified): `march_live_allocs`
(`runtime/march_runtime.c:383`, read through an extern in every
`test/native/*_leak_probe.march`); the three-rule dune shape (compile / run
with stderr→`.live` / bash threshold) at `test/dune:6781-6810` for
`simd_leak_probe`, repeated for the other five probes; `test_codegen.ml:2412`
dlsyms the gauge out of the JIT runtime `.so` for REPL fragments;
`test/test_broadcast_migrate_leak.c` (`test/dune:302-336`) for runtime-only
leaks; `MARCH_NO_UNBOX=1` (`lib/tir/repr.ml:105`) as a representation control.
There is **no `MARCH_RC_DEBUG`** in `lib/` or `runtime/`. ASAN is Docker-only
(`ci/Dockerfile.ubuntu`; no in-tree `fsanitize` script). All six leak with
byte-identical stdout, so every fix ships a `live_allocs` delta probe.

---

## 0. What is already true in the tree (verify before building)

- **Closure captures ARE deep-dropped, gated.** `lib/tir/drop.ml:730
  rewrite_apply_clo_drop` rewrites `dec_rc $clo` into
  `march_decrc_freed($clo)` and releases the loaded captures at every tail —
  but only for apply fns admitted by `drop.ml:635 owning_apply_fns`, which
  fails closed on any allocation shape other than an `ELet`-bound `EAlloc`
  whose closure `Borrow.closure_escapes` (`lib/tir/borrow.ml:343`). Item 1 is
  about widening that gate, not building the mechanism.
- **`find_inc_vars`'s `EField` exclusion covers `TTuple`/`TRecord` only.**
  `lib/tir/perceus_core.ml:1494-1498` (`a_is_aggregate`). `TPtr` — the type of
  `$clo` (`lib/tir/perceus.ml:308`, `TPtr TUnit`) — is not excluded, so every
  capture read of a live-after environment emits an `inc_rc $clo`.
- **The boxed case path already handles an aggregate payload.**
  `lib/tir/llvm_case.ml:976-981 is_boxed_agg` binds a struct COPY and releases
  the cell's box on the unique path (`llvm_case.ml:1089-1116`). The **niche**
  path (`llvm_case.ml:356-470`) has none of this: the binder is stored as
  `"ptr"` at `llvm_case.ml:436-448` and `strip_decrc_niche` (`:365`) removes
  the only release. Item 2 is porting `is_boxed_agg` to the niche arm.
- **ECallPtr caller and apply-fn callee still disagree.** Caller:
  `perceus_core.ml:863-876` treats every `ECallPtr` arg as owned ("audit P5").
  Callee: `borrow.ml:671` pins only `i = 0` (the `$clo`) owned; every other
  apply-fn param enters the borrow fixpoint. Unchanged since the todo.
- **One bit of the per-arg channel exists.** `lib/tir/clo_flags.ml:68
  flag_arg0_borrowed = 1` ↔ `runtime/march_runtime.h:156
  MARCH_CLO_ARG0_BORROWED`, stamped into the header pad at
  `lib/tir/llvm_emit_alloc.ml:52,333` and read at `march_runtime.c:8338`.
- **The C runtime calls closures at exactly six sites**, all in
  `runtime/march_runtime.c`: `march_typed_array_map` (`:8254`),
  `march_typed_array_fold` (`:8361`), `native_int_arr_fold` (`:8653`),
  `native_float_arr_fold` (`:8873`), `native_float_arr_to_list` (`:9006`),
  `native_f32_arr_fold` (`:9136`). `march_extras.c` only mentions the
  convention in a comment (`:1366`). Each passes a value it still owns.
- **`string_length` is NOT in the borrow table under its TIR name.**
  `borrow.ml:46 extern_borrow_table` has `march_string_byte_length` (`:56`)
  and `string_byte_length` (`:95`), but `is_borrowed` (`borrow.ml:206`) is
  keyed by the EApp callee name, which for the builtin is `string_length`
  (`lib/tir/llvm_builtins.ml:194`, `c_name = Some "march_string_byte_length"`).
  Lookup falls to `is_extern_borrowed` → `None` → **owned**. `to_string` →
  `march_value_to_string` is the only other `ptr`-param builtin in that state
  (scripted cross-check of the two tables, 2 hits). See §4.
- **The SIMD box release is table-gated and reaches two call arms.**
  `lib/tir/llvm_emit_call.ml:123-132` records a temp box only when the callee
  is in `ctx.native_vec_params` (published by the pre-pass at
  `lib/tir/llvm_toplevel.ml:995-1002`, mutual-TCO members excluded). The
  raises (`llvm_emit_call.ml:353`), blocking (`:355`) and hot-reload
  (`:362`, blocks `hr_direct`/`hr_disp`/`hr_cont` at `:394-396`) paths never
  see `temp_boxes`.
- **Tasks now die; their Float payload does not.** `lib/tir/llvm_emit_task.ml:79`
  releases the handle after `task_await_unwrap`; the `"double"` arm at
  `:50-61` unboxes `task[3]`'s `march_float_box` and leaves it aliased from
  the Task, whose free is `march_decrc`'s generic path. The runtime already
  has a per-tag hook on all four free paths — `march_run_resource_dtor`
  (`march_runtime.c:396-402`, called at `:462, :486, :569, :611`) — but it
  fires only for `MARCH_RESOURCE_TAG`. A Task carries tag 0 (`march_alloc`,
  `:5042` onward). Special tags live at `march_runtime.h:113-194`
  (`-1`..`-6` taken).

---

## 1. Closure-capture release: pinned `$clo`, and the gate that declines

### The gap

An apply fn that reads two captures emits two `inc_rc $clo` with no matching
dec, so its environment's refcount is pinned two above zero forever, and the
deep drop from §0 never fires. Independently, `owning_apply_fns` admitted
2,001 of 5,305 closure types in `cube_forge`; the rest leak their captures
shallowly. Reproducer: the todo's `Array.set` `descend` (three capture reads,
one release), or minimally

```march
fn mk(a : List(Int), b : List(Int)) : (Int) -> Int do fn x -> length(a) + length(b) + x end
pfn loop(n : Int, acc : Int) : Int do
  if n == 0 do acc else let f = mk([n], [n, n]) in loop(n - 1, acc + f(1)) end
end
```

### Root cause, grounded

- `perceus_core.ml:1473-1503`: the `EField` arm calls `find_inc_vars` on a
  non-aggregate source. `$clo : TPtr TUnit` is live after every capture read
  (it is released only at the splice point `perceus.ml:304
  insert_apply_fn_clo_drop`), so each read dups it. Nothing undoes those dups:
  the todo's diagnosis is confirmed by the code.
- `drop.ml:655-663`: an `EAlloc` of a `$Clo_` struct in argument/tail/field
  position, or any `EStackAlloc`, latches the closure TYPE to `false`
  (`note n false`), and a type with no allocation site at all is never
  admitted. Confirmed; the verdict is per type, not per site.

### Candidate fixes

- **A. Add `Tir.TPtr _` to `a_is_aggregate`** (`perceus_core.ml:1496`). One
  line; measured 339→177 MB on `WHICH=4`. The todo's SIGTRAP reading (23/60 vs
  15/60) was against a confounded baseline; it must be re-measured
  interleaved, same runtime. Risk: those dups are today what keeps a
  NON-owning environment's captures alive across the shallow `dec_rc $clo`
  for closures the gate declines — so A alone could convert a leak into a
  use-after-free for exactly the declined set. Hence:
- **B. Widen the gate per allocation site.** Recognise `EAlloc` in argument
  and tail position by hoisting it into an `ELet` in `Drop.run` before the
  scan (a pure local rewrite; `closure_escapes` then applies unchanged), and
  drop the type-wide `note n false` latch in favour of a per-site verdict
  carried to the apply fn. The carrier that already exists is the header pad
  word (`Clo_flags`, §0): one more bit, `flag_env_owned`, stamped at
  `llvm_emit_alloc.ml:52,333`, read by `rewrite_apply_clo_drop`'s emitted
  `case $freed of True -> …` as a second guard. That makes the deep drop a
  runtime decision per object, which is what "per site" means once two sites
  share one apply fn.
- **C. The outer release site** (a closure dropped without being applied): a
  code-pointer→drop table or a drop id in the pad word; touches `llvm_repl`
  finalisers and hot reload. Deferred — a separate leak class, scoped in the
  todo's §3.

**Chosen: A + B together, C deferred.** A is sound only once the deep drop
covers the closures whose captures the dups were masking; B is observable
only once A stops pinning the environment. One commit.

**Costs:** one pad bit (31 spare; `MARCH_CLO_ARG0_BORROWED` is bit 0); a
runtime `and` in `rewrite_apply_clo_drop`'s guard; the REPL/JIT already stamps
the pad (`llvm_emit.ml:419,549,605` call `Clo_flags.pad_for`).

### Test plan

- `test/native/closure_capture_release_probe.march`: the reproducer, 200,000
  iterations, stderr delta, three-rule dune shape, `< 1000`. Today: +3/iter
  (env + two lists). Include a lambda allocated in argument position
  (`List.map(xs, fn y -> …)`) so a gate-declined closure is exercised.
- `test/snapshots/src/closure_hof.march` exists; after A its
  `perceus/*.expected` loses the `inc_rc $clo` lines — regenerate with
  `UPDATE_SNAPSHOTS=1`; the diff is the review artifact.
- **RED controls:** revert only A → +3/iter again. Revert only B (keep A) →
  run `node_discovery.march` and `record_pattern.march` 60× interleaved; the
  expected red is the SIGTRAP-in-`mfm_free` double release the todo recorded.

**Effort M. Risk:** the "dual borrowed notion" hazard
(`project_closure_borrow_map_dual_notion`): `collect_closure_fvs`
(`perceus.ml:591`) puts captures in the callee-side borrowed set while
`find_inc_vars` is the caller side; A changes only the caller side of `$clo`
itself, not of the captures, which is why it is safe to pair with B and unsafe
alone. `node_discovery` is pre-existing-red at ~28/150 SIGBUS on main
(memory); compare per-signal counts, never a single run.

---

## 2. Unboxed aggregate in a niche-encoded payload

### The gap

`Some(P2(1.0, 2.0))` boxes the inline struct into a fresh `march_alloc(32)`
cell (`llvm_ctx.ml:743-763`); `Option(P2)` is niche-encoded so that box IS the
`Some` value; the niche arm binds the payload as a raw `ptr` and strips the
scrutinee's `dec_rc`; the binder's type is the aggregate, `needs_rc` false
(`rc_types.ml:175-177`). One 32-byte cell per evaluation, `MARCH_NO_UNBOX=1`
flat. Reproducer: the todo's `spin` (5,000 → 5,000; 20,000 → 20,000).

### Root cause, grounded

`llvm_case.ml:436-448`: `niche_tagged = false` for a heap payload, so
`(fty, fval) = ("ptr", scrut_p)` and the field var's slot is `ptr`. `:453-454`
strips `DecRC(scrut)` unconditionally ("Some(ptr): stripping is REQUIRED").
The later `p2sum(p)` reads the struct out via the `("ptr", sty)` unbox arm
(`llvm_ctx.ml:764`), whose comment says "the box itself is left alone; whoever
owns it releases it" — and here nobody does. The todo's "believed, not yet
confirmed" mechanism is confirmed by the code; the classification that makes
`Option(P2)` a niche is `repr.ml:360-364` (`niche_payload_ok`).

### Candidate fixes

- **A. Port `is_boxed_agg` into the niche arm.** At `llvm_case.ml:436-448`,
  when `Repr.unboxed_of_llvm_ty (llvm_ty field_var.v_ty) <> None`, bind the
  slot as the struct type via `Llvm_ctx.coerce ctx "ptr" scrut_p sty`, then
  `call void @march_decrc(ptr scrut_p)` immediately (the binder holds a
  register copy; the box aliases nothing). Keep `strip_decrc_niche` as is —
  the explicit release replaces the stripped one rather than fighting it. No
  `march_decrc_freed` split is needed: in the niche arm the scrutinee and the
  payload are one object, so "the cell survives and still owns the box" cannot
  happen.
- **B. Make Perceus see the box** — give the niche `Some` payload a
  `needs_rc = true` binder by typing it `TPtr` at lower time. Rejected: it
  would re-box on every read and contradicts the Milestone-3 contract in
  `rc_types.ml`'s module doc.

**Chosen: A.** It is the same shape the boxed path landed on 2026-09-04 and
keeps the fix where the representation decision is made.

**Costs:** one `coerce` + one `march_decrc` per niche destructure of an
aggregate payload; the boxed control shows the same count.

### Test plan

- A runtime live-object assertion in `test/test_codegen.ml`'s
  `unboxed_aggregates` group in the shape of
  `test_unboxed_aggregate_zero_live_allocs_compiled` (`test_codegen.ml:10383`):
  warm 100, sample, 20,000 iterations, assert `grew == 0` — the `Some(P2)`
  arm must free exactly what it allocates. Add a `.march` twin under
  `test/snapshots/src/` only if the TIR changes; it does not (this fix is
  emitter-only), so no snapshot.
- **RED control:** delete the `march_decrc` line → `GREW 20000`. Non-vacuity of
  the oracle itself: `MARCH_NO_UNBOX=1` must print `ZERO` on both sides.

**Effort S. Risk:** the niche arm (`llvm_case.ml:356-470`) never consults
`body_reuses_scrut`/`EReuse` (verified by grep), so an FBIP reuse of a niche
scrutinee must be impossible for the eager release to be safe; confirm in
`perceus_fbip` before landing.

---

## 3. `ECallPtr`: owned at the caller, borrowed in the callee

### The gap

A fresh heap argument through a genuine indirect call leaks once per call
(200,000 calls → +200,000 `String`s); a long-lived argument becomes immortal.
Reproducer: the todo's `call_n(f, n, acc)` with `f` taken from a list.

### Root cause, grounded

Two sides of one ABI: `perceus_core.ml:863-876` (caller: all args owned; dead
args transfer, live args dup) versus `borrow.ml:671` (callee: only param 0 is
pinned owned; a read-only `String`/`List`/record param stays borrowed and
never consumes). `rc_types.ml:197-203` makes `TVar`/`TFn` params
borrow-ineligible, which is why only borrow-eligible read-only params bite —
the common case. The todo's analysis is current; nothing has moved.

### Candidate fixes

- **A. Callee-side pin: every apply-fn param owned**, mirroring `$clo`. Change
  `borrow.ml:671` from `i = 0 && is_apply_fn` to `is_apply_fn`. Must land with:
  (1) an `march_incrc` before each of the six runtime `call_closure_*` sites
  (§0), since each still owns and releases its own element/accumulator;
  (2) deletion of `release_float_arg_boxes` (`llvm_emit_call.ml:761-777`) and
  its `is_potential_self_call` exemption (`:745-752`): a consuming callee now
  frees the call site's `march_float_box`, so the caller's release becomes a
  double free; (3) `fold_release_prev_acc` (`march_runtime.c:8341`) and the
  `MARCH_CLO_ARG0_BORROWED` witness become dead — the callee always consumes —
  and should be removed in the same change, not left as a second convention.
- **B. Caller-side flip: `ECallPtr` args borrowed**, callee self-incs at
  entry when its body wants ownership. Unsound alone (an OWNED-inferred param
  underflows); made sound by a prologue `inc_rc` on every owned apply-fn
  param, which puts an RC op on the hot path of every stored/returned arg and
  inverts the convention `Known_call`'s direct-`EApp` rewrite uses for the
  same function. Rejected.
- **C. Per-argument modes in the pad word** (the P5 "full fix"): 31 bits,
  `Clo_flags.register` widened, the call site loads the pad and branches per
  arg; the six runtime sites need the same dynamic check. Most general, most
  expensive per call. Keep the channel for §1's bit; build this only if A is
  measured insufficient.

**Chosen: A**, as the todo's 2026-08-22 addendum concluded, on its own branch.

**Costs:** read-only apply-fn params gain one tail `dec_rc` each (Perceus
emits it once the param is owned); callers stop hand-balancing live-after
args. Net RC traffic ≈ neutral; measure on `bench/list_ops.march` compiled
`--opt 2`.

### Test plan

- `test/native/ecallptr_fresh_arg_leak_probe.march`: the `call_n` reproducer
  with `f` from a list, 1,000,000 calls, stderr delta, threshold `< 1000`.
- Keep GREEN: `native_float_box_abi_leak_probe` (pins the emitted-caller
  convention), `native_arr_fold_acc_leak_probe` (pins the C-runtime-caller
  convention), `test/native/simd_vector_escape_arg.march`, `cap_mock_*`, and
  the full ASAN corpus in Docker — an ownership flip passes unit tests and
  double-frees in the corpus.
- TIR snapshot: `test/snapshots/src/closure_hof.march`'s `perceus/*.expected`
  will show the callee-side `dec_rc` on apply-fn params; regenerate and review.
- **RED controls:** (i) revert the `borrow.ml:671` pin alone → the new probe
  leaks 1/call again; (ii) keep the pin but restore `release_float_arg_boxes`
  → `native_float_box_abi_leak_probe` aborts with `RC underflow` from
  `march_decrc_freed`/`march_decrc` (`march_runtime.c:474-497`); (iii) keep
  the pin but skip the runtime `march_incrc` at `native_float_arr_fold`
  (`:8873`) → `native_arr_fold_leak_probe` underflows. Each half of the
  coordinated change has its own red.

**Effort L. Risk:** the TCO mixed-tail hazard (`project_toml_rc_bug_cluster`):
an apply fn whose tail is a self-call after `Known_call` becomes a back-edge,
and the new param `dec_rc` must land before the jump, not after it
(`llvm_tco` discards post-back-edge code — see `rc_types.ml:204-212`'s note).
`Perceus.insert_owned_aggregate_param_drops` already solves this placement for
aggregates; reuse it. Also: the runtime is a THIRD owner of closures
(`project_runtime_consumes_closure_third_party`); do the six-site edit with
the audit in `specs/progress/2026-08-22-fold-heap-accumulator-borrowed-return-leak.md`
open.

---

## 4. A heap field destructured out of a generic ctor "is never dropped"

### The gap

`One(s) -> string_length(s)` over `One(int_to_string(n))` leaks one `String`
per iteration, compiled only (10,000 / 10,000; interpreted 0). The todo
attributes it to the binder `s` receiving the cell's transferred reference and
nothing dropping it.

### Root cause, grounded — the attribution does not survive the code

The Perceus route the todo names is not open here. `perceus_core.ml:1305-1320`
puts `br_vars` into `borrowed_field_vars` only when the scrutinee is in
`live_after` (`scrutinee_live_across_case`), and `c` is dead after the match
(`dec_rc c` is emitted in the arm). So `$f30212` and its alias `s` are owned
by Perceus's own account, and the EApp post-call release
(`perceus_core.ml:665-695`) fires for a dead-after arg **iff
`Borrow.is_borrowed bm "string_length" 0` is true**. It is false: see §0 —
`string_length` is absent from `extern_borrow_table` under its TIR name, so the
arg is classified OWNED, the caller transfers, and `march_string_byte_length`
never frees. That predicts the todo's every measurement:

- `One(String)`: 1 `String`/iter — the string passed to `string_length`.
- `string_length(s ++ "!")` "does not change the count": `++` is
  `string_concat` (`borrow.ml:92`, both borrowed) so `s` IS released; the fresh
  concat result then goes to `string_length` and leaks instead. Same count.
- `Cell(String, Float)`: 2/iter on main, 1 after the erased-slot fix.
- `erased_float_slot_leak_probe.march:126` had to make its string a LITERAL
  (immortal) to stay green — consistent with `string_length` on a fresh
  string leaking regardless of any ctor.
- The todo's "probably the same defect": `to_string` of a `List(String)`
  leaks compiled — `to_string` is the OTHER builtin in the same state (§0).

**Decisive experiment before any fix** (one program, no ctor at all):
`pfn direct(n, acc) = direct(n-1, acc + string_length(int_to_string(n)))`. If
it leaks 1/iter, this item is a one-line borrow-table entry and its title is
wrong; if it is flat, the destructure route is real and the leads below apply.
This doc could not run it (no build in this session); it is the first step.

### Candidate fixes

- **A. Key the borrow table by both names.** In `borrow.ml:206 is_borrowed`,
  on `None`, also try the builtin's `c_name` from `Llvm_builtins` (or simply add
  `("string_length", [true])` and `("to_string", [true])` next to `:95`).
  Better: a startup assertion that every `in_is_builtin = true` entry with a
  `ptr` param has EITHER its `march_name` or `c_name` in the table, so a third
  builtin cannot fall into the gap silently (the scripted cross-check in §0 is
  that assertion, run once).
- **B. If the experiment is flat:** the destructure route. Then the fix is in
  the ECase arm at `perceus_core.ml:1347-1358`, which only decs br_vars DEAD in
  the body; a USED-then-dead binder relies on the same EApp post-dec, and the
  only remaining suppressors are `borrowed_field_vars`/`closure_fvs`/
  `moved_vars` (`:690-693`). Dump with `MARCH_DUMP_TXT=perceus` to see which.

**Chosen: A first; B only if the experiment says so.** A is the honest fix for
what the code shows; the todo file should be retitled when it moves to
`specs/progress/`.

**Costs:** every `string_length(x)`/`to_string(x)` with a dead-after `x` gains
the `dec_rc` it should always have had. `Escape` (`lib/tir/escape.ml:435`)
also consults `is_borrowed` but only under `callee_is_local` (March-defined
callees), so stack promotion is unaffected by a builtin-table entry.

### Test plan

- `test/native/builtin_borrow_key_leak_probe.march`: the ctor-free `direct`
  loop plus the todo's `One(String)` loop, 100,000 each, two stderr deltas,
  both `< 1000`. Add the niche form (`type One(a) = One(a) | Nothing` IS niche)
  and the boxed two-field form as further legs.
- Switch `erased_float_slot_leak_probe.march`'s `mixed_leg` string from the
  literal back to `int_to_string(n)` — the compose check the todo asked for.
- **RED control:** remove the `("string_length", [true])` entry → both legs
  return to 1/iter. If the `One(String)` leg goes red but `direct` stays green,
  B is real and separate; file it as its own todo with the TIR dump attached.

**Effort S (A) / M (B). Risk:** an over-eager release and a missing one are
indistinguishable in a unit test and opposite in the corpus: run the ASAN
sweep. `to_string` on `String` lowers to `Show$String.show` (identity,
`perceus_core.ml:919-927`), so its table entry only affects the container
path.

---

## 5. Non-TCO SIMD vector parameters: a box neither side releases

### The gap

A callee whose vector param stays `ptr` (non-tail-recursive, apply fn,
mutual-TCO member) called with a native `<4 x float>` value gets a fresh
`march_simd_alloc` box from `coerce`'s `(vt, "ptr")` arm (`llvm_ctx.ml:710`)
that nobody frees: the caller releases only for `ctx.native_vec_params`
callees, and the callee emits no `EDecRC` on a param Perceus never saw a box
for. Reproducer: `test/native/simd_leak_probe.march` with `go` made
structurally recursive (the todo's recipe).

### Root cause, grounded

`llvm_emit_call.ml:123-132`: `native_vec_idxs` gates `record_temp_box`; for a
callee not in the table the box is created (`coerce`) and forgotten. The
callee side: the param arrives as `ptr`, is `borrow_eligible` (`TCon` → true,
`rc_types.ml:201`), and a read-only body keeps it borrowed, so Perceus's
callee never decs — and if the body stores it (`simd_vector_escape_arg.march`)
the aggregate owns it, which is why the caller must not release blindly. The
three excluded paths are as the todo states: `:353` raises, `:355` blocking,
`:362` hot-reload — none touches `temp_boxes`. All confirmed.

### Candidate fixes

- **A. Materialise the box as a TIR binding** (the todo's option 2): in
  `Lower`/`Mono`, when a vector-typed atom flows into a `ptr`-slotted
  parameter, wrap it as `let $vb = box_vec(a) in f(.., $vb, ..)` with `$vb :
  TCon("SimdBox")`, `needs_rc` true, `borrow_eligible` true. Perceus then does
  the ordinary thing: the callee's borrow mode decides caller post-dec versus
  transfer, the escaping shape is owned by the cons cell, the read-only shape
  is post-dec'd by the caller. The emitter's `(vt,"ptr")` arm becomes the
  lowering of `box_vec`, and `record_temp_box`/`native_vec_params` release
  machinery is deleted — the native-slot case is just "callee borrows".
- **B. Borrow-guarded callee-side release** (option 1): thread the borrow map
  into `Llvm_toplevel.emit_fn` and dec the param at the callee's tails when
  inferred owned. Fixes only the OWNED shape; the read-only (borrowed) shape
  is the one that leaks, so B alone does not close the reproducer.
- **C. Extend the emitter table** to non-TCO callees by re-deriving "does not
  retain" from the body. Rejected: it re-implements borrow inference in the
  emitter, the drift hazard `llvm_toplevel.ml:140-160` warns about.

**Chosen: A.** It also subsumes the three excluded paths for free (the box is
an ordinary owned temp released by Perceus, not by the call arm), and it is
the same move §2's boxed path and §6's Float handling want: make the box a
value Perceus owns.

**Costs:** one more TIR shape for `Perceus`, `Escape`, `Drop` and the printer;
a `Repr` entry for `SimdBox` (`Boxed`, tag `MARCH_SIMD_TAG`). `simd_*`
`--emit-llvm` output moves; use `scripts/ir-oracle.sh` (baseline first, prove
RED with a bogus extra release, then GREEN).

### Test plan

- `test/native/simd_nontco_leak_probe.march`: non-tail-recursive `nt(v, k)`,
  2,000,000 calls, three-rule dune shape, `< 1000`; one leg each through a
  `raises` and a `blocking` extern. The hot-reload leg needs `--hot-reload`;
  add it only if a fixture already compiles that way, else record the gap in
  the progress entry.
- Keep GREEN: `simd_leak_probe`, `simd_vector_escape_arg`, `simd_mutual_tco`.
- **RED controls:** suppress the caller post-dec of `$vb` (force it into
  `moved_vars`) → +2,000,000; force a post-dec on the escaping shape →
  `simd_vector_escape_arg` exits 138/139. Both directions have a witness.

**Effort M. Risk:** the dual-borrowed-notion hazard again — `Escape`'s
stack-promotion (`escape.ml:435`) will see `$vb` as a candidate; a
stack-allocated vec box passed to a callee that stores it is a dangling
pointer. `closure_escapes`-style analysis must exclude `$vb` from promotion
when the callee param is owned.

---

## 6. Float-boxing at the task trampoline: `task[3]`'s payload

### The gap

`task_spawn(fn _ -> 2.5)` + `task_await_unwrap` leaks exactly one
`march_float_box` per await over the Int control (100k: 300,001 vs 200,000
before the task-handle fix; the 2/iter is now 0, so the excess is the whole
delta). Reproducer: the todo's await loop; `task_lifetime_leak_probe.march`
already has the double-await leg to extend.

### Root cause, grounded

`march_runtime.c:4976` stores `task[3] = (raw << 1) | 1` — for a Float task
`raw` is the box pointer the apply fn produced. `llvm_emit_task.ml:50-61`
recovers it and `march_unbox_float`s it, correctly leaving the box alone
(double-await is legal). `:79` then `march_decrc(task)`, whose free at
`march_runtime.c:449-472` is shallow. The trampoline's own drop is `:5010`.
The todo's "no task-aware free path to hook" is **out of date in one respect**:
`march_run_resource_dtor` (`:396-402`) is precisely a tag-dispatched hook on
every free path — it just only knows `MARCH_RESOURCE_TAG`.

### Candidate fixes

- **A. Give the Task a tag and teach the existing hook.** `#define
  MARCH_TASK_TAG ((int32_t)-7)` (`-1`..`-6` are taken, `march_runtime.h:113-194`),
  set it in `march_task_spawn_thunk` after `march_alloc`, and extend
  `march_run_resource_dtor` with a `MARCH_TASK_TAG` arm that reads `task[3]`,
  untags, and `march_decrc`s the payload iff `IS_HEAP_PTR` and its tag is
  `MARCH_FLOAT_TAG` — the same guard as `fold_release_prev_acc` (`:8341`). A
  `ptr` payload is NOT released here: `task_await_unwrap`'s `ptr` arm hands
  the caller the reference Perceus already accounts for (`:41-48`), and the
  `Ok` route took its own `+1` on 2026-08-22.
- **B. A dedicated `march_task_release`** called from the two emit sites.
  Misses the fire-and-forget path where `:5010` is the last drop. Rejected for
  that reason alone.

**Chosen: A.** It covers both await routes and fire-and-forget with one arm,
and every free path already calls the hook.

**Costs:** one `tag ==` compare per free (already paid for
`MARCH_RESOURCE_TAG`); add `-7` to the tag list `march_runtime.c:814-817`
says the free paths "need no case for".

### Test plan

- Extend `test/native/task_lifetime_leak_probe.march` with a Float leg: 100,000
  `task_await_unwrap`s of a Float task, delta `< 1000`; and a Float
  double-await leg (value correct twice, delta still bounded). Keep the Int
  legs.
- A C unit under `test/dune` in the `test_broadcast_migrate_leak.c` shape is
  unnecessary: the probe reaches the runtime path directly.
- **RED control:** delete the `MARCH_TASK_TAG` arm → Float leg +100,000. Second
  control: release the payload unconditionally (drop the `MARCH_FLOAT_TAG`
  guard) → the `ptr` legs abort with `RC underflow`.

**Effort S. Risk:** `task_race_cancel.march` writes `task[3] = mk_err_cstr(..)`
(`:5153`) — an `Err` cell, tag ≥ 0, so the Float guard skips it and the
existing ownership of that cell is unchanged; verify the fixture stays green.

---

## 7. Shared mechanism, and what subsumes what

- **§3 subsumes the caller-side Float releases and the arg0 witness:** it
  deletes `release_float_arg_boxes` and makes `MARCH_CLO_ARG0_BORROWED` /
  `fold_release_prev_acc` dead. It touches neither §6 (box aliased from the
  Task, not a call site) nor §2 (no call).
- **§5 is §3's discipline applied to a boxed argument.** Once a vec box is a
  TIR binding, its caller/callee mode is the question §3 settles; land §3
  first so `ECallPtr` callees with vector params inherit the owned pin.
- **§1 and §3 both spend a pad bit in `Clo_flags`.** §1 adds `flag_env_owned`;
  §3 may retire `flag_arg0_borrowed`. Allocate §1's as bit 1 regardless.
- **§2 and §6 are local and independent.** Land first; each is S with a
  one-line RED control.
- **§4 is probably misattributed.** Run the ctor-free experiment before
  anything; if it leaks, the fix is a borrow-table entry that also closes the
  `to_string(List(String))` leak and lets `erased_float_slot_leak_probe` drop
  its literal workaround.

**Order:** §4 experiment → §2 → §6 → §4 fix → §1 (A+B) → §3 → §5. Each step
ships its probe and RED control in one commit, moves its todo to
`specs/progress/`, and adds a `### Fixed` bullet to `CHANGELOG.md`.
