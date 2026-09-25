# JIT REPL: List(Float) printed garbage, and a Float result crashed the next prompt (fixed)

**Found and fixed 2026-09-24**, while building `NativeArray.sort_float`. The report
was: in the JIT REPL, `NativeArray.to_list_float` prints garbage for any float array,
while single-element reads (`get_float`) are correct. There turned out to be two
independent bugs, both in the REPL layer. `to_list_float` was a bystander: the
runtime builds its list correctly.

## Which modes were affected

Repro: a 3-element float array, then `to_list_float`, then print.

| mode | result |
|---|---|
| interpreter (`march file.march`, `MARCH_REPL_INTERP=1`) | correct |
| `--compile` | correct |
| `march --jit file.march` | correct (list data consumed by March code) |
| interactive REPL, JIT (ORC and clang backends) | **garbage / SIGSEGV** |

The prelude/JIT `.so` cache was ruled out first: the bug reproduces from a
fresh, empty scratch `HOME`, cold and warm.

(Unrelated, not fixed here: `to_string(xs)` on a `List(Float)` inside a
`march --jit` *file* is an internal compiler error, `Ambiguous_iface_call` on
`Show$List.show`, and a `NativeF32Arr` value at the JIT prompt prints `#<tag:-6>`.)

## Bug 1: the value printer read float boxes as raw doubles

Float-boxing stage 2 made codegen store a Float that crosses an erased (TVar-declared)
slot as a `march_alloc_float` box (`Llvm_ctx.coerce`'s `("double","ptr")` arm). That
covers a List's Cons head, `Option`/`Result` payloads, tuple slots, and a generic
constructor's argument. The REPL heap printer (`lib/jit/repl_jit.ml`, `pp_field` /
`pp_word`) still read every `TFloat` slot as raw IEEE-754 bits. So it printed the
box *pointer* as a denormal double:

```
march> NativeArray.to_list_float(NativeArray.from_list_float([3.5, 1.25, 2.0]))
= [2.15262e-313, 2.15262e-313, 2.15262e-313]
march> [3.5, 1.25, 2.0]
= [2.67964e-313, 2.67964e-313, 2.67964e-313]
march> Some(1.5)
= Some(1.74003e-313)
```

`List.head(...)` printed `3.5` because a top-level Float result goes through a
different path (`call_void_to_float`). Int lists were fine: ints are tagged
immediates, not boxes.

**Fix.** `pp_float_word ~erased` reads the value at `+16` of a `march_float_box`
(tag `MARCH_FLOAT_TAG` = -3) when the slot is erased (the printer's existing
`~tagged` flag, which already means "declared type is a TVar"). It checks the box tag
before reading. Concrete Float fields (records, a constructor declared at `Float`)
still read raw bits. The erased-`TVar` arm now also renders a float box instead of
`#<tag:-3>`.

## Bug 2: the "v" slot release decrc'd a Float's raw bits

Each REPL expression's result is stored in the persistent `v` slot
(`march_repl_set`). `Llvm_repl.emit_store_to_slot` released the slot's OLD value
whenever the NEW result was heap-typed, relying on `march_decrc`'s `IS_HEAP_PTR`
guard to skip scalars. Slots hold Floats as raw bits, though. `IS_HEAP_PTR` rejects
only odd, small or negative words, and 3.5 = `0x400C000000000000` passes. So any
Float result followed by any heap-returning expression dereferenced the double as a
header and crashed (exit 139):

```
march> let a = NativeArray.from_list_float([3.5, 1.25])
march> NativeArray.get_float(a, 0)
= 3.5
march> NativeArray.to_list_float(a)
[SIGSEGV]
```

Plain `3.5` then `[1, 2]` crashed the same way. This is why the report tied the
garbage to `get_float`: the fragment IR (`MARCH_KEEP_LL=1`) showed `repl_2` doing
`march_repl_get(1)` → `inttoptr` → `march_decrc` on slot 1, which held `repl_1`'s
bitcast double.

**Fix.** `emit_store_to_slot ~prev_slots` looks up the slot's previous type (the
`v` entry repl_jit records per expression, already passed to every emitter) and
emits the release only when that type is heap-shaped (`slot_holds_heap_ref`). The
release now also runs when the new result is a scalar, so a heap `v` that is
replaced by a Float or Int is released rather than leaked. A slot with no previous
entry has never been written by this session, so no release is emitted for it.

That last rule is load-bearing. The first version of this fix released an
unrecorded slot too, on the theory that it still read as zero. It does not:
`march_repl_slots` is a static array in the runtime .so, which stays mapped for the
life of the process, and every new session's `alloc_slot` restarts at 0. So a fresh
session's slot 0 holds whatever an earlier session in the same process last stored
there. CI's `run_codegen` runs many JIT sessions in one process, and it died with
SIGSEGV (exit 139, no alcotest summary) in `repl_jit_cross_line` 11 ("stdlib
List.length via precompile"): that session's first `v` store decrc'd a dangling
pointer that case 10 ("capture-free closure materialization does not leak") had left
in slot 0. Running only cases 10 and 11 reproduced it; either case alone passed.

## Siblings checked

- `to_list_f32`: same printer bug, fixed by the same change.
- `to_list_int`: unaffected (tagged immediates).
- `Option`/`Result`/tuple/nested (`[Some(0.75)]`) Float payloads, and a generic
  user constructor `W(1.5)`: same printer bug, fixed.
- Concrete `type P = P(Float, Int)` and `type N = N(Float)`: unaffected, still correct.
- Probed sequences: heap then Float then heap; string then Int then string;
  `let xs = [1.5]` then `xs` then `2.5` then `xs`; enum values; a REPL `fn`
  returning Float then a list. All correct after the fix. Five of those sequences
  crashed before it.

## Evidence

Regression test: `test/test_jit.ml`, "Floats print and survive the v slot" (JIT, plus
an interpreter parity control). It runs one session with `get_float` →
`to_list_float` → `to_list_f32` → `Some(2.5)` → `(1.5, 7)` → `[Some(0.75)]`.

- origin/main sources: **FAIL**, exit code 139 (bug 2 fires first).
- Slot fix only, old printer: **FAIL**, `expected = [3.5, 1.25, 0.5]` (bug 1).
- Both fixes: **OK**. `scripts/run-tests.sh test_jit`: 26 tests, all green.
