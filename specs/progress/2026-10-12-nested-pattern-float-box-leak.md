# Float box behind a nested pattern leaked once per match

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `nested_option_float_match` and others
reported `march_alloc_float < march_main`.

## The bug

`Some(Some(f))` over `Option(Option(Float))` lowers to a case on the
pattern-compiler temporary `$f : Option(Float)` whose branch tag is the
QUALIFIED `Option.Some`. `Llvm_data.resolve_ctor_fields` looked
`(type_name, ctor_name)` up in `poly_ctors`, which is keyed by the BARE ctor
name, so the lookup missed and it returned the declared field types (`'a`).
With the field's concrete type unknown, `Llvm_case` never recognised the slot
as an erased-slot Float box: it treated it as an ordinary heap field (incremented
on the shared path, moved to the binder on the unique path), and the binder is
a Float, so Perceus drops nothing. One box leaked per match, on both paths.
The same happened for `Ok(Some(f))` and the generic `Some(Some(v))` at `a = Float`.

## The fix

`resolve_ctor_fields` retries the `poly_ctors` lookup with the tag's last
segment when the qualified one misses. The concrete field type is then `Float`,
and the existing erased-slot handling (bind a copy, release the box on the
`march_decrc_freed` path) applies, as it already did for a bare tag.

## Verification

- `test/native/nested_float_pattern_leak_probe.march`: three nested shapes over
  2,000 iterations leaked 6,000 boxes before, 0 after; its shared leg (a value
  matched twice) is the double-free witness. Output matches the interpreter.
- Linux arm64, 1 and 14 schedulers: the probe and `nested_option_float_match`
  are clean under both the ASAN error pass and the LSan pass of
  `scripts/native-sanitize-sweep.sh` (the latter reported the leak before).
