# Unboxed small scalar aggregates (`Repr.Unboxed`)

**Landed:** 2026-09-03. Design context: `specs/2026-09-03-allocation-contracts-design.md`
lists "Unboxed Float layout" as roadmap item 5; this is that item, generalised
from `Float` to any small scalar-only single-constructor variant.

## The problem this closes

The voxel engine at `~/code/cube_forge` annotated 40 per-frame functions with
`@[no_alloc(warn)]`. 15 verified; the other 25 were rejected for one reason —
**every constructor with fields is a heap cell**:

```march
type Vec3 = Vec3(Float, Float, Float)
fn forward(yaw : Float, pitch : Float) : Vec3 do
  let cp = Math.cos(pitch)
  Vec3(0.0 -. Math.sin(yaw) *. cp, Math.sin(pitch), 0.0 -. Math.cos(yaw) *. cp)
end
-- error: `forward` is marked @[no_alloc] but allocates.
--   In `forward`: constructor `Vec3` is allocated here.
```

`Vec3` compiled to `march_alloc(40)` and nothing could remove it. FBIP had no
dying cell of the same shape to reuse (the inputs are scalars). Escape analysis
could not promote it (the value is returned). The same held for `Quat(Float x4)`,
`Hit(Bool, Int x6)` (over the arity limit, see below) and `Sweep(Float x3, Bool)`.

## What landed

`lib/tir/repr.ml` gains a fourth representation:

```ocaml
| Unboxed of { ctor : string; fields : Tir.ty list }
```

A `TDVariant` with exactly ONE constructor, all of whose fields are
`TInt`/`TFloat`/`TBool`, with arity in `2..Repr.max_unboxed_arity` (4), is an
LLVM struct VALUE — `{ double, double, double }` — in registers, parameters,
returns and local slots. No cell, no header, no refcount.

Landed class vs. the brief's "scalar-only, <= 4 words": identical, with the
arity ceiling at 4 fields (32 bytes) for the ABI reason below. `Hit(Bool, Int,
Int, Int, Int, Int, Int)` from the engine is therefore still boxed; three- and
four-field vector/quaternion/sweep types are not.

### Sites

| File | Change |
|---|---|
| `lib/tir/repr.ml` | the `Unboxed` constructor, the registry, `set_unboxed_types` / `ensure_unboxed_types` / `rebind_registration` / `force_disable` |
| `lib/tir/llvm_ctx.ml` | `llvm_ty` returns `%ub.T`; new `llvm_field_ty` returns `ptr`; `coerce` box/unbox arms; `make_ctx` declares the struct types and registers |
| `lib/tir/llvm_emit_alloc.ml` | `Repr.Unboxed` construction arm (`insertvalue` chain); field stores use `llvm_field_ty` |
| `lib/tir/llvm_case.ml` | `Repr.Unboxed` destructuring arm (`extractvalue`); `is_boxed_agg` binder-copy rule |
| `lib/tir/llvm_emit_data.ml` | record field store/load/update at the SLOT type |
| `lib/tir/llvm_emit_tcoarm.ml` | closure-FV load at the slot type |
| `lib/tir/llvm_emit_arith.ml` | field-wise `==`/`!=` in registers |
| `lib/tir/llvm_data.ml` | `check_slot_ty`: a struct slot type is a hard failure |
| `lib/tir/rc_types.ml` | the `Repr.Unboxed` row: `needs_rc` and `borrow_eligible` both false |
| `lib/tir/escape.ml`, `drop.ml`, `perceus_core.ml` | the new arm in each repr match |
| `lib/tir/alloc_contract.ml` | elision; the `AggBox` reason for a boxing boundary |
| `lib/tir/contract_pipeline.ml` | registers after Mono+Defun, rebinds for the emitter |
| `lib/jit/repl_jit.ml` | `force_disable` — the REPL keeps the boxed representation |

### The two rules that make it safe

1. **A heap slot is 8 bytes** (`alloc_size = 16 + n*8`), so an inline aggregate
   can never live in one; every slot type goes through `Llvm_ctx.llvm_field_ty`
   (which answers `ptr`) and `coerce` boxes into exactly the cell the boxed
   representation would have built. `Llvm_data.emit_store_field`/`emit_load_field`
   `failwith` on a struct slot type, so a missed site is a build error rather
   than a 24-byte store into an 8-byte slot silently corrupting the next field.
   **Three sites were found this way after the first pass** (`ERecord`/`EUpdate`
   in `llvm_emit_data.ml`, the closure-FV load in `llvm_emit_tcoarm.ml`, and
   `Ray(Vec3, Int)`'s constructor field) — the first of them had already produced
   a wrong-value divergence before the guard existed.
2. **One registry, read by everyone.** `repr_of_ty`, `llvm_ty`, `needs_rc`,
   `borrow_eligible`, `Escape`, `Drop` and `Alloc_contract` all read the same
   table, rather than each re-deriving the predicate. Same discipline as the
   actor-message and collision-set exclusions: encode, decode and RC cannot
   disagree about a representation if they read one table.

### Exclusions, each for its own reason

Arity 1 (already `Newtype`); arity > 4 (past two register pairs the C ABI passes
the struct in memory); a non-scalar field (nowhere to refcount it from); two or
more constructors (no tag slot); actor message types; same-short-name colliding
types; and **any type named in an `extern` signature** — the C side would get
the right cell, but that box is unowned and `needs_rc` is false, so it would
leak once per call. Keeping such a type boxed program-wide removes the question.

Off entirely for the REPL/JIT (a fragment thunk is called as `void -> ptr`), for
the JS backend (GC'd runtime, no struct ABI), and under `MARCH_NO_UNBOX=1`.

## Verification

- `test/test_codegen.ml`, group `unboxed_aggregates` (7 cases): the declared
  struct type; `insertvalue`/`extractvalue` with zero `march_alloc` in a
  `Vec3`-only module; a **RED control** showing the same program allocating
  under the empty registry; the eligible-class table (12 rows); the two RC
  predicates; the extern exclusion; and a compiled 20,000-iteration loop whose
  `march_live_allocs` growth is exactly 0.
- `test/test_alloc_contract.ml`: `@[no_alloc]` accepts `forward`/`dot`/`energy`,
  with a RED control asserting the boxed verdict under `MARCH_NO_UNBOX=1` (the
  source carries a distinguishing comment so the artifact cache cannot answer
  it from the accept run).
- `test/native/unboxed_aggregate.march` and
  `test/native/unboxed_aggregate_boundaries.march`, both in the oracle
  allowlist: interpreted == compiled across construction, matching, equality,
  `Show`, `Option`, tuples, records, record update, a recursive ADT field, a
  closure capture, a task boundary and a `Result` payload.
- TIR snapshots `test/snapshots/{lower,perceus}/unboxed_aggregate.expected`:
  pins that Perceus emits no inc/dec around a value with no refcount.
- `bench/vector_math.march`: 20.8 ms unboxed vs 828.3 ms boxed (min of 5,
  `--opt 2`, M-series Mac), same output.

## Measured on the engine that motivated it

`~/code/cube_forge` at 9cd1ffb, built with this branch pinned as a toolchain
(`.march-version`), against the same tree built with `1eb43d39`.

**The representation applies.** The engine's own emitted IR declares ten
unboxed struct types, including three of the four the brief named:

    %ub.CubeForge_Math_Vec3_Vec3   = type { double, double, double }
    %ub.CubeForge_Math_Quat_Quat   = type { double, double, double, double }
    %ub.CubeForge_Math_Mat4_Vec4   = type { double, double, double, double }
    %ub.CubeForge_Player_Sweep     = type { double, double, double, i64 }

plus six stdlib types (`DateTime.Date`/`Time`, `Decimal`, `JsonStream.JsCfg`/
`JsonLimits`, `Process.LiveProcess`), with 48 `insertvalue` and 18
`extractvalue` on them. `Hit(Bool, Int, Int, Int, Int, Int, Int)` — the fourth
type the brief named — has SEVEN fields and stays boxed: it is over
`max_unboxed_arity`.

**Contracts.** With `[contracts] no_alloc = ["*"]` (every verified-clean
function in scope), from the same pristine tree:

| | 1eb43d39 | this branch |
|---|---|---|
| functions carrying `@[no_alloc]` | 379 | **384** |
| functions carrying `@[no_alloc(transient)]` | — | **12** |
| total | 379 | **396** |

Under the DEFAULT generation scope both compilers insert the same 2
attributes; the difference above is entirely in the widened scope. (The base
compiler's output does not then compile — see
`specs/todos/2026-09-03-forge-fix-contracts-inserts-into-unparseable-positions.md`.)

**Allocation churn: unchanged, and here is why.** Over an identical
`MARCH_PIN_MAIN=1 CF_FRAMES=240 CF_SEED=12345` release run, deterministic
across repeats:

| | 1eb43d39 | this branch |
|---|---|---|
| total object allocations | 4 157 337 | 4 159 019 (+0.04%) |
| `CF_ALLOC_PROBE` bisect | 13 lines | identical, line for line |
| live-object delta, frames 100..200 | 150 (1/frame) | 150 (1/frame) |
| 240 frames | 2003 ms, 119.8 fps | 2010 ms, 119.4 fps (both vsync-capped) |

This engine keeps its vectors INSIDE heap values — a `Vec3` in `Player`, in
`Scene`, in a `Ray` — so at those slots the representation trades a
construction for a boxing, and the two very nearly cancel (the +1 682 is the
boxing side coming out slightly ahead). The win is real where a vector stays
in locals, parameters and returns, which is what `bench/vector_math.march`
measures (20.8 ms against 828.3 ms), and it is real for CONTRACTS — `forward`
can be pinned now and could not be before. It is NOT a win for a program that
stores its aggregates, and this table is the evidence for saying so.

The engine's 82 tests pass and the 240-frame release run exits 0.

## Docs

`docs/value-representation.md` §7.5 (the full treatment),
`docs/memory-model.md` + `specs/lang/memory-model.md` ("Small scalar aggregates
never reach the heap at all"), `docs/ffi.md` (the extern exclusion),
`specs/benchmarks.md` (the new benchmark and its trigger row), `CHANGELOG.md`.

## Not done

- **Storing an aggregate inline inside another constructor's fields or in a
  `NativeArray` slot** (both in the original brief). Both need a wider slot
  than the 8-byte one `alloc_size` fixes, i.e. a layout change to the object
  header contract, which is a separate item. Today both box.
- The boxing at a slot boundary produces a fresh `rc=1` cell that Perceus does
  not track — the same position a boxed `Float` has been in since float
  boxing landed (`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`).
  `@[no_alloc]` reports it, so it is visible rather than silent, but the
  underlying ownership gap is shared with that open item.
