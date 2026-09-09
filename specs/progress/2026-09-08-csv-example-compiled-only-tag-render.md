# `examples/csv_example.march` renders `#<tag:1>` compiled, real values interpreted

Found 2026-08-10 while verifying the R1 stage D migration. **Not caused by
stage D** — proven with a pre-fix control (see below). Filed separately
because it is a live compiled-only divergence in a shipped example.

## Symptom

```
march examples/csv_example.march          # --- Example 1: each_row (streaming) ---
                                          # [name, age, city][Alice, 30, New York]…

march --compile examples/csv_example.march -o /tmp/x && /tmp/x
                                          # --- Example 1: each_row (streaming) ---
                                          # #<tag:1>#<tag:1>#<tag:1>#<tag:1>#<tag:1>Done.
```

Both exit 0. The compiled binary prints a constructor-tag placeholder where
the interpreter prints the row's contents.

## Why it is NOT stage D

The pre-fix control this repo's own postmortems require: a compiler built at
`413d3c48` (the last commit before any stage-D code) compiling the
**pre-migration** `csv_example.march` produces the identical `#<tag:1>`
output. The bug predates the stage.

Also ruled out, because "cannot plausibly be related" is not evidence here:

- minimal `println(Cons("a", Cons("b", Nil)))` under a 1-capability `main` —
  interpreted and compiled agree (`[a, b]`);
- the same program under a **3**-capability `main` — also agree, so the new
  N-null entry adapter is not implicated;
- `test_codegen`'s `main_cap_adapter` group passes at 0/1/2/3 capabilities.

## Where to start

Probably the same family as the `sort_by`/`println`-of-list saga
(`specs/progress/`, the mono/`llvm_emit` Show-dispatch bugs): a `Show` impl
resolved to the wrong instance in compiled code prints the tag rather than the
payload. The distinguishing detail here is that plain `List(String)` is FINE —
so it is specific to whatever type `Csv.each_row` yields, not to lists in
general. Start by diffing the TIR for the row-printing call
(`MARCH_DUMP_TXT=<stage>`) between a working `List(String)` case and this one.

Worth a compiled-parity regression test in `test_codegen` once fixed;
`examples/` is not covered by the compiled-parity suites today, which is why a
shipped example could diverge unnoticed.

---

## Resolved 2026-09-08

Root cause was the missing constructor metadata, not a mis-resolved `Show`
instance: `Csv.each_row` yields a declared ADT whose cells carried a tag and
nothing else, so the type-erased formatter printed the tag. The constructor
name table closes it — see
`specs/progress/2026-09-08-compiled-to-string-adt-ctor-names.md`.

Verified: `examples/csv_example.march` interpreted and compiled now produce
byte-identical output, with zero `#<tag:` occurrences.

The note's closing suggestion — that `examples/` is not covered by the
compiled-parity suites — still stands and is NOT addressed here. The new
coverage is `test/native/to_string_ctor_names.march`, a purpose-built parity
golden; the examples directory remains uncovered.
