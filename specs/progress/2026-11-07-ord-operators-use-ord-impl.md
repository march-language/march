# `<` `<=` `>` `>=` use the type's `Ord` impl on native and JS (issue #1172)

**Landed:** 2026-11-07. Reported as
[#1172](https://github.com/march-language/march/issues/1172).

On a user type with an `Ord` impl (derived or hand-written), the ordering
operators worked in the interpreter (`Eval_runtime`'s `cmp_op` looks the impl
up) but compiled code never called the impl:

- **Native, boxed operand** (enum, record, payload ADT): the emitter
  (`Llvm_emit_arith`) saw a plain `ptr` and called `march_poly_compare`, which
  returns 0 for two ordinary heap cells, so every `<`/`>` was false and every
  `<=`/`>=` true.
- **Native, newtype** (`type Wrap = Wrap(Int)`, no heap cell): `icmp` on the
  raw payload, so `Wrap(1) < Wrap(2)` was true where the derived `Ord`
  (constructor order) says equal.
- **Native, unboxed ADT** (`type Pair = Pair(Int, Int)`): `icmp` on an LLVM
  aggregate, a clang type error that failed the build.
- **JS**: `inline_binop` mapped `<` to the JS operator on two objects.
- **Generic** `fn lt(a, b) when Ord(a) do a < b end` had all of the above
  after monomorphisation.

**Fix.** The tuple fix ([2026-10-11-tuple-ord.md](2026-10-11-tuple-ord.md))
already routed `<` & co. on a `TTuple` through prelude helpers in
`Mono.rewrite_calls`; that routing now covers every `TCon` (except `Atom`) and
`TRecord` whose `compare` resolves to an impl (`iface_impl_name "compare"`),
so it happens after specialisation and generic callers are covered. The
prelude helpers are renamed `__tuple_lt`/`le`/`gt`/`ge` →
`__ord_lt`/`le`/`gt`/`ge` (`compare(a, b) <op> 0`); their specialisation
dispatches `compare` to the type's own impl. Int/Float/String/Bool/atoms keep
the emitters' native comparisons, and a type with no resolvable `compare` impl
is left as before. Native and JS share this, since both consume Mono's output.

JS also needed `compare` on the primitives, which a derived `Ord` calls per
field: `js_emit` now lowers `march_compare_int`/`compare_int` and
`march_compare_string`/`compare_string` inline (-1/0/1), and
`march_compare_float`/`compare_float` to a new NaN-total
`march_compare_float` in `runtime/march_runtime.mjs` (matching the C runtime
and the interpreter). Before, `compare` on a derived record with `Int` fields
failed the JS build with "builtin `march_compare_int` has no
JavaScript-target implementation".

Tests: `test/native/adt_ord_operators.march`, golden = interpreter output, run
both compiled (`native_adt_ord_operators`) and on `--target js`
(`js_adt_ord_operators`): the issue's repro (enum, record, payload ADT,
hand-written impl), a derived and a hand-written newtype, an unboxed ADT,
generic `when Ord(a)` callers at ADT, record and primitive types, a derived
record over `String`/`Float` fields, `compare` on Int/Float/String, and
`List.sort_by` with `<` on a hand-written impl.

Found along the way, not fixed here: derived `Ord` on a record with two or
more fields returns only the LAST field's comparison
([2026-11-07-derived-record-ord-last-field-only.md](../todos/2026-11-07-derived-record-ord-last-field-only.md)).
