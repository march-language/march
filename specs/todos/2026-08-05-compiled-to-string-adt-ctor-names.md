# Compiled `to_string` renders user ADTs as `#<tag:N>` instead of the constructor

**Filed:** 2026-08-05
**Priority:** P2 — interpreter/compiled parity gap, not a safety issue

## Symptom

`to_string` on a user-defined ADT disagrees between the interpreter and the
compiled backend:

```march
mod TsProbe do
  type Point = Point(Int, Int)
  fn main() : Unit do
    let p = Point(1, 2)
    println("to_string=" ++ to_string(p))
  end
end
```

```
interpreted : to_string=Point(1, 2)
compiled    : to_string=#<tag:0>
```

Measured 2026-08-05 on `main` @ `079ff744`. Predates and is independent of the
`~H` ADT fix landed alongside this file — `to_string` alone reproduces it with
no sigil involved.

## Cause

`march_value_to_string` (the C implementation behind the `to_string` builtin)
has no constructor-name metadata to consult. It can read a heap cell's tag but
has no table mapping `(type, tag) -> "Point"`, nor field count/types to recurse
into, so it prints the raw tag.

## Why it matters now

The `~H` contextual-escaping work made this visible in rendered output.
`~H"<p>${p}</p>"` used to misread a non-IOList ADT as an IOList (silent empty
output, raw unescaped emission, or a SIGSEGV — see
`specs/progress/2026-08-05-h-sigil-adt-misread.md`). The fix routes such values
through `march_value_to_string`, which is safe and escaped but renders
`#<tag:N>`.

Two consequences worth fixing:

1. `test/native/h_sigil_adt_interp.expected` currently pins `#<tag:N>` as the
   compiled output. It is annotated as a known defect, not intended behaviour.
   **When this is fixed, update that file to the interpreter's rendering.**
2. The `Html.Safe` short-name-collision path
   (`test/native/h_sigil_safe_collision.march`) renders the wrapper rather than
   the markup. Constructor names would at least make that output legible.

## Sketch of a fix

Emit a per-type constructor table (name, arity, field reprs) into the binary and
have `march_value_to_string` walk it, recursing into fields. The capability
lattice already has this shape: `lib/caps/cap_lattice.ml` is an OCaml
source-of-truth with `emit_c_table.ml` generating `runtime/march_cap_lattice.{h,c}`
and an anti-drift freshness check in `test/dune`. Model the constructor table on
that rather than inventing a second mechanism.

Note the tag is not globally unique — tags are numbered per type from 0 — so the
table must be keyed by type identity, which means the emitter has to record
which type each cell belongs to. That is the same information the `~H` fix uses
statically, so the two should share a representation if possible.
