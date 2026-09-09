# `examples/csv_example.march` renders `#<tag:1>` compiled, real values interpreted

## Closed 2026-09-09

Fixed and already recorded in detail at
`specs/progress/2026-08-12-csv-example-tag-render-compiled-generic-to-string.md`
(root-caused to `lib/tir/mono.ml`'s `find_iface_impls` not retrying
`to_string`→`show` resolution after monomorphization concretizes a generic
function's parameter; fixed by commit `b44ede62`, with regression test
`test/native/generic_fn_to_string_specialize.march`). Re-ran
`examples/csv_example.march` both interpreted and `--compile --opt 2`: all 4
demos now produce byte-identical output, no `#<tag:N>` anywhere. This todo
file is redundant with the progress entry above and is closed without
restating the detail.

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

## Closed 2026-09-09 — the file was STALE, not newly fixed

This item was already fixed on **2026-08-12**, by the mono-time
`to_string` -> `show` retry recorded in
`specs/progress/2026-08-12-csv-example-tag-render-compiled-generic-to-string.md`.
That fix landed with its own progress note and its own regression test
(`test/native/generic_fn_to_string_specialize.march`) but did not remove THIS
file, so the todo sat open for a bug that no longer existed. Removing it is all
that happened here.

Recording the correction rather than quietly deleting the file, because the
first version of this note claimed the constructor-name table
(`specs/progress/2026-09-08-compiled-to-string-adt-ctor-names.md`) closed it.
That was wrong, and wrong in an avoidable way: the example was observed working
and the working state credited to the change in hand, with no pre-fix control
run to establish it had ever been broken at that base. It had not been — the
mono retry was already in the base commit. The two are not even related: the
example's `to_string(row)` resolves to `Show$List.show`, which never reaches
the constructor table.
