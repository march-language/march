# Repro: double release of a niche-represented record payload

Companion to `specs/todos/2026-09-03-aggregate-field-read-inc-masks-niche-payload-imbalance.md`.
Program: `2026-09-04-niche-record-payload-double-release.march` (15 lines of March).

## Why it needs a patch to fire

The bug is LATENT on the committed compiler. `insert_rc_expr`'s `EField` arm
runs its source through `find_inc_vars`, which emits an `inc_rc` on the
aggregate whenever it is live after the projection. Nothing ever undoes that
inc, so the cell's refcount never reaches zero and the second release lands on
a still-live cell instead of a freed one.

That inc is exactly what has to be removed to fix the borrowed-record-parameter
leak (2001 live objects over 1000 iterations vs 1 when the field is read
inline), which is in turn half of what the record-update leak needs. So this
bug blocks that fix, and it must be root-caused before the inc can go.

## Reproducing

Apply the one-line unmask in `lib/tir/perceus_core.ml`, in the `EField` arm:

```ocaml
(* before *)
let inc_vars = find_inc_vars ~include_borrowed_fields:false env [a] live_after in

(* after *)
let a_is_agg = (match a with
  | Tir.AVar v -> (match v.Tir.v_ty with
                   | Tir.TTuple _ | Tir.TRecord _ -> true | _ -> false)
  | _ -> false) in
let inc_vars =
  if a_is_agg then []
  else find_inc_vars ~include_borrowed_fields:false env [a] live_after in
```

Then:

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2          # MANDATORY between compiler variants
MARCH_RUNTIME_DIR="$PWD/runtime" ./_build/default/bin/main.exe --compile \
  -o /tmp/p1 specs/repros/2026-09-04-niche-record-payload-double-release.march
for i in 1 2 3 4 5 6; do /tmp/p1; echo "exit=$?"; done
```

- Committed compiler: `15000`, exit 0, 6/6.
- Unmasked: 6/6 crash. Three modes seen, all the same underlying corruption:
  - **exit 133** (SIGTRAP) — libsystem_malloc's own freelist-corruption
    detector, the `brk #0x1` in `_xzm_xzone_malloc_freelist_outlined`. `lldb`
    stops there with `EXC_BREAKPOINT`. This is the most common mode.
  - **exit 134** (SIGABRT) — the runtime's own guard:
    `march: RC underflow (rc was -3798685876956648731) at 0x98f000920 — aborting`.
    The GARBAGE refcount is the tell: the dec landed on something that is no
    longer a live heap header.
  - **exit 138** (SIGBUS).

  Which mode appears varies run to run, and the RC-underflow line is often
  printed on stderr even in the 133 case.

## What is required, established by bisection

Each row is one edit away from the repro, 6 runs each:

| variation                                    | crashes |
|----------------------------------------------|---------|
| repro as written                             | **6/6** |
| payload is a TUPLE `W((Int, Int))` not a record | 0/6  |
| second constructor also carries a payload (`W(..) \| V(..)`, so BOXED not niche) | 0/6 |
| no second constructor (`type Wrap = W(..)`, so NEWTYPE) | 0/6 |
| the record is built ONCE outside and reused  | 0/6     |

So all four are necessary: **niche representation** (exactly one payload
constructor plus one nullary), a **record** payload specifically, a **fresh**
record per iteration, and **repeated** execution. Two calls suffice
intermittently (2–4 out of 6); the loop makes it deterministic.

Additionally ruled out, so they are not re-investigated:

- **Not Float-specific.** The original fixture (`test/native/record_pattern.march`)
  used `rate : Float`; an all-`Int` record reproduces identically.
- **Not the static-closure path.** Capture-free join-point closures are interned
  as immortal globals with rc = 2^40 (`Llvm_ctx.intern_static_closure`), so
  decrementing one is harmless by design — and this repro emits no `$static_clo`
  at all.
- **Not the literal-pattern arm.** An earlier repro needed `W({rate: 15}) -> ..`
  as a first arm and it looked essential; the loop form has no literal pattern
  and is more reliable, so the join-point closure chain a literal arm builds is
  NOT the mechanism.

## The TIR, which is where the puzzle now sits

With the unmask applied there is no RC operation left in `f` at all:

```
fn f(w : Wrap) : Int =
  case w of
  W($f30229) -> let $f_rate30230 : Int = $f30229.rate in
                let r : Int = $f_rate30230 in r
  Z() -> 0
```

and the caller looks balanced — one allocation, one release:

```
let $t30233 : { rate : Int } = { rate = 15 } in
let $t30234 : Wrap = alloc Wrap.W($t30233) in     -- niche: $t30234 aliases $t30233
let $rc_740 : Int = f($t30234) in
dec_rc $t30234;
```

`add_scrutinee_free_for` correctly declines to free a niche scrutinee, the
scope-end drop correctly declines `$t30233` (it sits at a consuming position),
and `Drop.droppable_ctors` correctly returns `None` for a niche type so the dec
stays shallow. Every individual decision looks right, yet the cell is released
twice at runtime — so the next step is to find the SECOND release in the emitted
LLVM rather than in the TIR.

## Measurement traps hit while narrowing this

- **Clear `.march/cas/artifacts-v2` between compiler variants.** A bisect of
  this exact bug produced three mutually contradictory results because cached
  artifacts were served across compilers.
- **Check the experimental edit actually BUILT.** Making a binding unused turns
  into a warning-as-error, dune fails, and the previous binary silently answers.
- **The failure mode varies run to run** (133 / 134 / 138). One clean run proves
  nothing; always run at least 6.
