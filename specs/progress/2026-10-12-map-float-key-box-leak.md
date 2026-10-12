# `Map(Float, v)` / `Set(Float)` leaked their key boxes

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `local_named_like_builtin` reported
`march_alloc_float < Map.node_insert$HEntry_Float_String...` and
`... < Set.node_insert$SEntry_Float...`.

## The bug

A map leaf `HLeaf(h, k, v)` holds its key in a generic (erased) slot; at
`k = Float` the slot holds a `march_alloc_float` box the leaf owns. `HEntry`
is declared by three stdlib modules (`Map`, `HashMap`, `Hamt`), so the type is
registered only under its qualified names, and two places that look it up by
the bare name missed:

1. `Llvm_data.resolve_ctor_fields`: Map's own `case node of HLeaf(h, k, v)`
   is on the bare `HEntry(Float, String)`; neither `type_params` nor
   `poly_ctors` has a bare `HEntry` entry, so the declared `k` came back and
   `Llvm_case` bound the key box as an ordinary heap field (incremented on the
   shared path, moved on the unique one) into a Float binder Perceus never
   drops. Every destructure of a leaf (`Map.size`, an insert over a leaf, a
   remove) leaked the key box.
2. `Drop.boxed_float_slots`: the synthesized `__drop$HEntry_Float_String`
   enumerates the collision union, whose constructor names are qualified
   (`Map.HEntry.HLeaf`), and looked them up by bare name in `HEntry`'s
   constructors, so a dropped map never released its key boxes.

Measured on main: 3,000 to 5,000 leaked objects per 1,000 iterations of the
probe's legs, 1,000 for the Set leg.

## The fix

1. When the bare name has neither table entry, `resolve_ctor_fields` takes
   the qualified candidates (`*.HEntry` with this constructor) and uses their
   instantiated fields if they all agree; any disagreement keeps the old
   fallback.
2. `boxed_float_slots` resolves a qualified constructor name in its own
   candidate type.

## Verification

- `test/native/map_float_key_leak_probe.march`: size, replace + remove, whole
  drop, a shared map inserted into twice (double-free witness) and a
  `Set(Float)`, 1,000 iterations each: every delta 0 (was 1,000 to 5,000);
  output matches the interpreter.
- Linux arm64: the probe is clean under ASAN with leak detection on, and the
  full ASAN error sweep over test/native (342 fixtures, 1 and 14 schedulers)
  re-run with this change has the same verdicts as before it.
