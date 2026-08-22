# `record_put`/`record_get` on an erased Float field SIGSEGVs when compiled natively

Filed while validating downstream packages (bastion, depot, forgepm, conduit, sigil,
scroll, march_doc, marathon) against `origin/main` ahead of the 0.3.0 release.

## Symptom

A `Float` value written into a dynamically-shaped `Record` via `record_put` and
read back with `record_get`, then formatted (e.g. via `println`/`to_string` on
the resulting `Option`), segfaults when **compiled** (`--compile`), but returns
the correct value when **interpreted**. This affects both a brand-new field
(record extension) and — per the crash address analysis below — the erased-Option
Niche encoding generally, not just record extension specifically.

Repro (minimal, no dependencies):

```march
mod Main do
  needs IO

  fn main(cap: Cap(IO)) do
    println("before")
    let r = record_put(record_from_list([]), "y", 0.5)
    println("after put")
    let v = record_get(r, "y")
    println("after get")
  end
end
```

```
$ march /tmp/repro.march              # interpreted: prints all three lines, fine
before
after put
after get

$ march --compile --opt 2 /tmp/repro.march -o /tmp/repro && /tmp/repro
before
after put
[SIGSEGV, exit 139]                   # crash is inside/after record_get
```

Also reproduces with `--opt 0`, and with an `Int` payload instead of `Float`
(different crash address, same crashing function — see below).

## Backtrace

```
* thread #2, stop reason = EXC_BAD_ACCESS (code=1, address=0x3fe0000000000010)
    frame #0: march_string_concat3 + 48
    ldr    x9, [x1, #0x10]
```

`0x3fe0000000000010` is `0x3FE0000000000000` (the IEEE-754 bit pattern for
`0.5`) `+ 0x10` — i.e. `march_string_concat3` received the RAW erased Float
bit pattern as one of its `march_string *` arguments and dereferenced
`->data`/`->len` at offset `+0x10`, treating a float payload as a heap string
pointer. The `Int` variant of the same repro (`record_put(..., "y", 5)`)
crashes the same function at address `0x1b` — again a small tagged-int value
used where a pointer was expected.

## Hypothesis

`runtime/march_extras.c`'s NICHE-encoded Option convention for
`march_record_get` (`None = 0`, `Some(v) = v`, comment at
`runtime/march_extras.c:321`) returns the field's erased UNIFORM-representation
bits directly. That's correct in itself — the bug appears to be downstream, at
whatever call site formats the resulting `Option` value (`println`/`to_string`)
without knowing the field's static kind (`'f'` for Float, `'i'` for Int): the
generic/`'g'`-kind formatting path assumes the erased payload is always a
pointer and calls into string-building (`march_string_concat3`) on it
unconditionally, rather than checking the kind tag first.

This lines up with the existing `[[project_erased_i64_convention]]` /
`[[project_record_put_uniform_handoff]]` conventions documented elsewhere in
the codebase (`ptr→i64` is a CONDITIONAL untag; raw scalar bits must never be
coerced straight to a pointer) — this looks like one more site that skips the
kind check.

## Downstream impact

`depot`'s `lib/data/depot_schema.march` already has a long-standing comment
(`depot_schema.march:185-190`) documenting this exact crash as "a known-broken
march primitive" and structures `Depot.Schema.blank`'s default-filling around
it. depot's `test/test_depot_schema.march:269` ("Float type default in blank")
exercises the no-explicit-default path (`put_float_default`'s `None` branch,
which still calls `record_put(r, name, 0.0)`) and fails
(`forge test`, compiled backend) — not a NEW regression from 0.3.0, but it
remains open and worth fixing for the release since it blocks any downstream
package using dynamically-typed records with Float fields (ORMs, schema
validators, etc. are exactly the kind of code that hits this).

## Suggested fix direction

Find the generic Option/value formatter used for `println`/`to_string` on an
erased record-field read (likely in `lib/tir/llvm_builtins.ml` or
`runtime/march_extras.c`'s printing helpers) and make it kind-aware — or, if
the value truly has no statically-known kind at that call site, encode enough
of a type tag in the erased representation to distinguish "raw Float/Int bits"
from "heap pointer" before it reaches string-formatting code.


---

## STATUS: STILL OPEN (updated 2026-08-21)

A fix was attempted and **reverted**. Recording it so the next attempt does
not repeat it.

**What was tried:** treat every `TFloat` ctor field as a `march_alloc_float`
box behind a `ptr` slot — in `llvm_eq.ml`'s `field_load_llty`, `llvm_emit.ml`'s
ctor stores, `llvm_case.ml`'s branch extraction, and the runtime's
`rec_box_some_float`. It made depot's "Float type default in blank" and the
`SqlValue.PFloat` cases pass.

**Why it is wrong:** boxing is the convention only for a **generic (`TVar`)**
field. A **concrete monomorphic `Float`** field is an **inline `double`** —
stated in `test/native/float_generic_field_abi.march`'s own header. Forcing
`ptr` everywhere corrupted the inline paths; six native goldens regressed to
garbage doubles (a pointer read as `5.21501746242e-310`) and silently wrong
arithmetic (`[1., 2., 3.]` where `[4., 5., 6.]` was expected):

    float_generic_field_abi, record_pattern, native_arr_map2_inline,
    native_arr_map_inline_capture, native_arr_map_inline_float_box_reuse,
    native_arr_map_inline_unboxed

**Process note that matters more than the fix:** `scripts/run-tests.sh` does
NOT run those goldens — they are dune rules, so only `dune runtest` covers
them. A green `run-tests.sh` is not sufficient evidence for any change that
touches Float/record field representation. Use `dune runtest`.

**Where a real fix probably lives:** the distinction must be made per-field on
whether the field's resolved type is generic or concrete, not on `TFloat`
alone. `llvm_ty` already returns `double` for concrete `TFloat` and `ptr` for
`TVar`, so the existing behavior is right for both — meaning the actual defect
is elsewhere (most likely in which of those two the *specific* depot call site
resolves to, or in `march_record_get`'s `expected_kind` handoff), not in the
field-slot type rule. Reproduce with the repro at the top of this file before
changing any representation code.

---

## RESOLVED (2026-08-21) — fixed on the branch `fix/vault-record-erased-repr`

The "STILL OPEN" section above ends with the right instinct — *"the actual
defect is elsewhere, not in the field-slot type rule"* — and that is exactly
where it turned out to be. **Nothing in this fix touches `llvm_ty`,
`field_load_llty`, `ctor_field_llty` or `llvm_case`'s branch extraction.** The
concrete-`Float`-is-an-inline-`double` ABI that the six goldens pin
(`float_generic_field_abi`, `record_pattern`, `native_arr_map2_inline`,
`native_arr_map_inline_{capture,float_box_reuse,unboxed}`) is left alone; those
goldens are unchanged and green.

There were THREE separate defects behind this one repro, two in the runtime and
one in the consumer.

### 1. The boxed `Option(Float)` cell contradicted its own comment

`runtime/march_extras.c`'s `rec_box_some_float` stored the raw IEEE-754 bits at
offset 16 — while the 20-line comment directly above it states the field holds
*"a march_alloc_float box — NOT the raw double"*. The revert in #315 took the
code back and left the comment. The decode side settles it, and can be read
straight out of `--emit-llvm`:

```llvm
%fv24 = load ptr, ptr %fp23, align 8              ; Option.Some field 0, as ptr
%cv27 = call double @march_unbox_float(ptr %ld26) ; the Float binder
```

`llvm_case` loads `Option.Some`'s field 0 with the type of the ctor's DECLARED
field (`Some(a)` → TVar → `ptr`), and the `Float` binder reaches it through
`Llvm_ctx.coerce ("ptr","double")`, which IS `march_unbox_float`. So the cell
must contain a box. Handing it raw bits made `march_unbox_float` dereference
`0x3FE0000000000000` — depot's "Float type default in blank", and the concrete
half of the repro at the top of this file.

Runtime-only, one function.

### 2. An erased read handed back raw Float bits

`march_record_get` with an erased (`'g'`) call-site kind returned
`rec_field_out_adt(..., 'f')` verbatim, i.e. raw IEEE-754 bits, into a slot
whose contract is the uniform representation. `march_record_values` and
`march_record_entries` did the same, into list/tuple element slots that are
*always* erased (`List('a)`, `List((String, 'a))`) — so `println(record_values(r))`
SIGSEGV'd on the first Float field too, which this file had not recorded.

Fixed with `rec_box_erased_float` (a `march_alloc_float` box, `MARCH_FLOAT_TAG`)
and `rec_field_out_uniform`. `march_record_get` now keys the OPTION ENCODING on
the call site's `expected_kind` (unchanged — that is what keeps the
niche-for-erased convention that fixed the 74 depot failures) and the PAYLOAD on
the STORED kind, which is the only thing that can reveal a Float. Boxing also
closes the erased `0.0`-reads-back-as-`None` hole for free.

### 3. The consumer: `Show$String.show` was a static identity

This is the residual PR #315 noted, and it is a compiler bug, not a runtime one.
`record_get(r, "y")` has type `Option('a)` with nothing in the program to pin
`'a`. `Mono.default_residual_tvars` maps a dangling type variable to `TString`
on the stated assumption that *"no concrete value ever flows through it"* — which
is false at an erased runtime boundary. `--dump-tir` shows the consequence in
one line:

```
let v : Option('_39896) = record_get(r, "y") in
println$Option_String(v)
```

so `Show$Option.show$Option_String` ran, its inner `show` resolved to
`Show$String.show` = `fn x -> x`, and the erased value went straight into
`march_string_concat3` as a `march_string *`. Crash addresses confirm it:
`0x3FE0000000000010` is 0.5's bits + the `->data` offset, `0x1b` is the tagged
Int 5 (11) + the same offset — both already recorded at the top of this file.

`Show$String.show` is now a DYNAMIC identity: `march_value_to_string(x)`. On a
genuine String that returns the string verbatim (+1) — observationally the same
function it replaced — and on an erased value it classifies the uniform
representation at runtime, which is the only thing that CAN be right here since
the compiler provably does not know the type.

Cost is bounded: the common `"${s}"` interpolation never reaches this body,
because `lower.ml` elides `Show$String.show` at the SOURCE when the argument is
concretely a String (the elision that exists to avoid a Perceus inc/dec pair on
every interpolated operand). What reaches it is the mono-resolved
generic-container path (`Show$List` / `Show$Option` / `string_join` elements),
which already pays a call and an allocation per element.

Two supporting changes:

- `march_value_to_string` had a latent SIGSEGV of its own, now that it is on the
  String path: it never handled INLINE (SSO) strings. A string of <= 7 bytes is
  a value with bit 63 set, not an address, and the function fell through to
  `h->tag` and dereferenced it. It also dereferenced any non-heap word. Both are
  now classified before any load, and the `MARCH_STRING_TAG` check moved ahead
  of the actor-`Pid` table walk (an actor cell always carries an ordinary
  ctor/record tag >= 0, never a reserved negative sentinel, so the reorder
  cannot change a verdict — it just makes the new hot case cheap).
- `lib/tir/js_emit.ml` gained a `march_value_to_string` arm that emits the
  argument unchanged. JS has no uniform representation and no erasure — values
  arrive as their own JS types — so the identity this body replaced is still
  exactly right there, and the JS backend's output is byte-for-byte unchanged.

### Test

`test/native/record_erased_field_repr.march` + `.expected`, wired into
`test/dune`: fully-erased `println(record_get(...))` for ODD Int / EVEN Int /
Float / 0.0 / String / missing key, the concrete `Option(Float)` arithmetic
path, and `record_keys` / `record_values` / `record_entries` over a mixed
record. The fixture's header records why the EVEN Int case is not redundant —
an even Int survives a raw store untouched, because the erased-i64 untag only
shifts odd words, so half this family is invisible on even values.

Non-vacuity, by file-copy swap of the five changed sources back to
`origin/main` (`3fda8f46`) followed by `dune build bin/main.exe` +
`@warm-cache` (verified restaged: `rec_box_erased_float` count 0):

```
----- record_erased_field_repr -----
  run_exit=139
  RESULT: DIFFERS from golden  (non-vacuous)
1,12d0
< Some(7)
  ... all 12 golden lines missing — the binary dies before the first println ...
```

Same verdict against pre-#315 (`c2f747f7`). With the fix restored: exit 0, zero
diff.

The JS backend has its own non-vacuity witness, found the hard way: the first
version of the `Show$String.show` change reddened 27 `js_*` dune rules with
`ReferenceError: march_value_to_string is not defined`, because `Defun` had
turned the call into a closure application
(`march_value_to_string._0(march_value_to_string, x)`). Fixed by registering the
name in `defun.ml`'s `builtin_names` — the same multi-site trap `march_hash_string`
and `march_compare_string` are already in that list for. `borrow.ml`'s
`extern_borrow_table` gained the matching entry (the argument is BORROWED:
march_value_to_string takes its own +1 before aliasing the input).

### Same family

One of five instances of a single root — the erased/uniform boundary between the
C runtime and compiled code, where the runtime has ONE fixed representation and
the compiled call site decodes by the STATIC type. The other two:
`2026-08-20-vault-non-string-key-native-crash.md` (the key, fixed by #315) and
`2026-08-20-nested-option-vault-boxed-niche-mismatch.md` (the Option ENCODING,
fixed alongside this one).
