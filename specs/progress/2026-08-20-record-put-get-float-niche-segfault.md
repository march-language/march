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

## RESOLVED (2026-08-20, same day)

Fixed as a cluster of three defects, all the same root class (a Boxed-ADT
Float field stored/loaded as a raw inline `double` while the convention is a
`march_alloc_float` box behind a `ptr` slot):

1. `runtime/march_extras.c` `rec_box_some_float`: stored raw IEEE-754 bits at
   offset 16 of the boxed `Some` cell; now stores a `march_alloc_float` box,
   matching `march_string_to_float`'s documented convention.
2. `lib/tir/llvm_eq.ml` `field_load_llty`: loaded a `TFloat` ctor field as
   `double`; now loads `ptr` + `march_unbox_float` before `fcmp` (both the
   Boxed-strategy eq fn and the tuple eq fn).
3. `lib/tir/llvm_emit.ml` (10 ctor-store sites) + `lib/tir/llvm_case.ml`
   (branch field extraction): construction stored the raw double inline and
   extraction loaded it as `double`; both now go through `field_load_llty`'s
   boxed convention, fixing e.g. `PFloat(3.14)` in a multi-ctor ADT
   round-tripping through construction → match → `to_string` (depot's
   `SqlValue`, "compile_inline PFloat literal").

Verified: full `scripts/run-tests.sh` suite green; TIR snapshots unchanged;
depot's "Float type default in blank" and all `PFloat` compile tests pass.

Note the ORIGINAL repro in this file (an UNTYPED `record_get` whose result is
only `println`'d — the payload stays fully erased, kind 'g') still crashes:
the erased/'g' path returns niche encoding and the generic print treats the
raw Float bits as a pointer. That residual is the known erased-niche
Float-payload hole (uniform Option encoding is the only full fix) and is far
less reachable from real code — every TYPED use (annotation, match, equality,
arithmetic, `to_string` after a typed match) now works.
