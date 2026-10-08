# `[P2]` `Kind.repr_of` answers differently for a type's qualified and bare spellings

Found 2026-10-06 (specs/progress/2026-10-06-nominal-record-short-name-drop.md, "Left").

`Kind.find_variant` is an exact lookup over `k_type_defs`, where a stdlib variant is
registered under its qualified name. So for `stdlib/global_registry.march`'s
`type Names = Names(Map(String, Entry))`:

- `repr_of (TCon ("GlobalRegistry.Names", []))` finds the one-field constructor:
  **Newtype** (the cell IS the map).
- `repr_of (TCon ("Names", []))` finds nothing and falls through to **Boxed**.

Lowering constructs it under the bare name, so the program's values are Boxed cells, and
any consumer that reads the qualified spelling (a qualified field type of a record, as in
#812's drop helpers) is handed the wrong layout: a newtype unwrap of a boxed cell. #812
avoided it by rewriting record field types to bare names (`Kind.record_fields_short`);
nothing else is known to read a qualified spelling, but nothing prevents it either.

## Why this was not fixed in passing

Unifying the answer changes the representation of every type that is spelled both ways.
Codegen (`Llvm_ctx`, `Llvm_emit_alloc`, `Llvm_case`), Perceus, Borrow and Drop each look
types up by whichever spelling they hold, and today's construction sites happen to agree
with the bare (Boxed) answer. Flipping either side without auditing every consumer can turn
a latent disagreement into a live miscompile.

## Suggested approach

1. Instrument `repr_of` (env-gated) to log every TCon name it is asked about, with the
   answer, across the native corpus; list the names asked under both spellings with
   different answers.
2. Decide one canonical key (the one lowering uses at construction) and make `find_variant`
   resolve the other spelling to it, exactly as `record_fields_short` does for records:
   unique last segment only, refuse on ambiguity.
3. Prove it with `scripts/ir-oracle.sh` (expect diffs only in programs that mention the
   affected types) and the ASAN corpus sweep.

## Resolution (FIXED 2026-10-06)

### Measured

`repr_of` was instrumented (env-gated, not committed) to log every `TCon` it was asked
about, its answer, the answer the other spelling would get, and the OCaml call stack of
each divergent query, over `--emit-llvm` of the 356 programs in `test/native` and
`test/session`.

- 36 programs asked about ~36 stdlib types under both spellings with different answers:
  `Map.Map`, `Bytes.Bytes`, `UUID.UUID`, `Duration.Duration`, `VectorClock.VectorClock`,
  `GlobalRegistry.Names` and the `Html.Trusted*` types are Newtype when qualified and Boxed
  when bare; `Decimal.Decimal`, `DateTime.Date` and `JsonStream.JsCfg` are Unboxed when
  qualified and Boxed when bare. Session protocol state types (`Ping_Client.S_send_Ask`, ...)
  split the same way.
- Every layout-deciding consumer asks the BARE spelling: construction
  (`Llvm_emit_alloc`), matching (`Llvm_case`), reuse, Drop, Perceus and Escape. The bare
  lookup misses the qualified registration and lands on Boxed, so Boxed is what these
  programs build. The Newtype and Unboxed answers for stdlib types never fire.
- Qualified spellings reached three consumers: `Llvm_ctor_desc` (runtime-printing
  descriptors; a Newtype answer only skips the descriptor), `Escape.alloc_emits_heap_cell`
  and `Alloc_contract.alloc_is_elided`. The last two take the type name from the
  constructor key, as construction does, so they agree with it. One construction site was
  qualified: `actor_monitor_down_reason`'s nested `UserValues.Down`, whose constructor
  lowering keys qualified because its short name is runtime-reserved.

### The live bug it hid

That last shape is a miscompile once the value is also matched. A nested
`type Down = Down(Int)` was built as a newtype (the value IS the tagged Int) and matched
under the bare `Down` as a boxed cell: compiled-only SIGSEGV at address `0x5b` (`41`
tagged is `0x53`; the tag slot is at +8).

### Fix

`Kind.repr_of`: a qualified name whose short name names no declaration of its own (and no
unboxed type) answers as that short name does. One whose short name names another type
keeps its own lookup, because those are different types. So the answer no longer depends
on the spelling, and it is the one construction and matching already got.

`scripts/ir-oracle.sh` over its 418 programs, against a baseline compiler built from the
parent commit: 33 changed, each diffed with the type-descriptor constant masked.
- 14: only the runtime-printing descriptor string (`Llvm_ctor_desc`) changed. Types
  such as `Map.Map`, `Bytes.Bytes` and `GlobalRegistry.Names` are now describable, which
  they always were at runtime (boxed cells).
- 18: the same, plus the descriptor ids constructors stamp (`add i32 %ctbase, N`)
  shifted by the same amount, because the newly describable types are numbered earlier.
  The table and the stamps move together.
- 1 (`actor_monitor_down_reason`): `UserValues.Down(7)` is now a boxed cell with its own
  tag, not a raw tagged Int, as that test's comment always intended.

Test: `test/native/qualified_newtype_repr.march` (RED before: SIGSEGV).
