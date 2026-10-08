`[P2]` - [x] **The kind table answers one way per type, whichever spelling asks.**

Filed 2026-10-06 as `specs/todos/2026-10-06-kind-qualified-vs-bare-repr.md`
(found in `specs/progress/2026-10-06-nominal-record-short-name-drop.md`,
"Left"); landed 2026-10-07.

## What was wrong

Lowering registers a type declared inside a module under its qualified name
(`GlobalRegistry.Names`, `Duration.Duration`, `Main.Inner.Id`) and builds
every value of it under the short one: the constructor key is
`Names.Names`, and `emit_alloc_ctor` takes the type from it. The kind table
looked names up exactly, so each such type had two answers:

- **short name**: misses the qualified declaration, falls back to **Boxed**.
  This is what every construction site asks, so it is the layout every value
  actually has.
- **qualified name**: finds the declaration and answers **Newtype**,
  **Niche** or **Unboxed** from its shape, a layout no value has.

The todo described one type. An instrumented trace over the IR-oracle corpus
(`MARCH_KIND_TRACE`, every `repr_of` / `is_niche_shaped` /
`niche_repr_of_concrete` query logged with its caller when the two spellings
disagreed; about 300 programs) found it for **73 types**: 61 declared
newtypes, 6 niches and 6 unboxable aggregates, stdlib and user alike
(`Map`, `Bytes`, `DataFrame`, `Decimal`, `Duration`, `UUID`, `Date`, ...).

Construction and decode both ask the short name, so no value was ever
miscompiled by it; a direct probe of a user nested-module newtype, multi-field
type and niche, built and matched from both sides of the module, agreed
compiled and interpreted. The damage was in the consumers that held the
qualified spelling:

| Caller | Queries in the trace | Consequence |
|---|---|---|
| `llvm_ctor_desc.ml` (constructor descriptors) | 1,442 | Skipped every such type as "unboxed", so compiled `to_string` / `println` printed `#<tag:0>` where the interpreter printed `Duration(5000)`, `UUID("abc")`, `Id(3)`. User-visible. |
| `drop.ml` suffix resolver and field-type paths | 6,222 | Treated niche-shaped library types (`CtlGate`, `Verdict`, `Outcome`, `Upgrade`, `RegisterError`) as niches and declined to destructure their boxed cells. |
| `llvm_emit_alloc`, `escape`, `alloc_contract`, `llvm_case` | 8 | `UserValues.Down` (built under a qualified key, never destructured) and `Csv.CsvRow` (see below). |

## Why there was no spelling-only fix

Two C-runtime ABIs pull in opposite directions:

- `CsvRow` must be a **niche**: `march_csv_next_row` returns raw NULL for
  `CsvEof`. Only the qualified answer is right
  (`test/native/csv_niche_row.march`).
- `Bytes` must be **boxed**: the runtime builds it as a cell
  (`compress_bytes_from_raw`). Only the short answer is right.

`Process.LiveProcess` (declared unboxable) is also built by C as a boxed cell
(`process_spawn_async`: "tag=0, 2 int64 fields"), so it agrees with the short
answer too. These three are the only module-declared non-Boxed types named in
a C builtin signature.

## The change

`Kind.canonical_name`: every name-keyed representation query (`repr_of`,
`is_niche_shaped`, `niche_repr_of_concrete`, `unboxed_of_type_name`, and the
`needs_rc` / `borrowable` / `llvm_ty` / `layout` fields of `of_ty`) is asked
under the short name, the spelling values are built under. One documented
exception, `declared_layout_types = ["CsvRow"]`, resolves to the declaration
because C fixes its layout. A short name declared by two modules is already
forced Boxed by the collision set, so the short name cannot resolve to a
different type; the actor-message pin is checked under both spellings, so
canonicalising can only add a Boxed answer, never remove one.

Shape questions go the other way. `closure_free` and `float_free` describe what
a value contains, which does not depend on its layout (a boxed `P2(Float,
Float)` still holds two Floats), so the deep walk resolves a name to its
declaration with `Kind.declaration_of`. The first version of the fix missed
this and the new unit test caught it: the short spelling walked no fields and
answered "float-free".

## Proof

- New `test/native/to_string_module_types.march`, run interpreted AND compiled
  against one `.expected`: **8 of its 12 lines were red on the pre-fix
  compiler** (`#<tag:0>` / `#<tag:1>`), all 12 green after. The four that
  matched before (a multi-field and three multi-constructor values) are boxed
  under either spelling, so they are the control that the fix only moves the
  types whose spellings disagreed.
- `test/test_kind.ml`: both spellings agree for newtype, heap newtype, niche,
  unboxable and bare-registered types across every query; the `CsvRow` pin;
  `canonical_name`; a two-module short-name collision stays Boxed.
- `test/native/csv_niche_row.march` (the pinned type) still matches its
  `.expected`; `actor_monitor_down_reason` still compiles and runs.
- IR oracle (`scripts/ir-oracle.sh`, frozen compilers, private
  `HOME`, 428 programs): changed, as intended, and every change is accounted
  for after normalising fresh-name renumbering:

  | Change | Count | Why |
  |---|---|---|
  | Renumbering only | 287 programs | fresh-name counters shift |
  | Constructor descriptors added | 33 programs | module-declared types are now described (the `to_string` fix) |
  | Descriptor-id shifts in `*_inspect` / `to_string` call sites | 20 functions | more types described, so local ids move |
  | Shallow `decrc_local` -> deep drop (`__drop$Upgrade`, inlined tag switch in `ClusterNode.h_register`) | 16 call sites, 10 drop helpers | niche-shaped library types (`Upgrade`, `RegisterError`, ...) now destructure as the boxed cells they are built as: a leak fix |
  | `UserValues.Down(7)` raw int -> heap cell | 1 (`actor_monitor_down_reason`) | the one type built under a qualified key; now consistent with every other site |

  No other function changed.
- `scripts/run-tests.sh` over every suite but refinecheck: exit 0, 11 suites,
  3,785 tests, 0 failures. Refinecheck runs in CI; the only refinecheck input
  this change touches is the audit baseline, regenerated above.
- `test/refine_audit/corpus.baseline` regenerated for the new fixture (the two
  expected lines).

## Left

The canonical answer is the one programs already build, which means a type
declared inside a module never gets its declared newtype, niche or unboxed
layout. Switching to declared layouts is a representation change for 73
types with C-ABI and wire-format consequences:
`specs/todos/2026-10-07-module-type-layouts.md`.
