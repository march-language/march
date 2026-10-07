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
