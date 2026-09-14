# `to_string` of a List no longer leaks the list it builds

**Landed 2026-09-13.** Filed the same day as
`specs/todos/2026-09-13-show-list-leaks-per-call.md`.

## The defect

prelude's `impl Show(List(a))` is

```march
"[" ++ string_join(map(xs, fn x -> show(x)), ", ") ++ "]"
```

`lib/tir/borrow.ml` marked `string_join`'s **list** argument owned, under
both `string_join` and `march_string_join`. That has been true since the
table's first version (`724adae3`, whose comment says "list is heap-owned by
caller", which describes a borrow). `march_string_join` only walks the list
and copies bytes out of each element, so the mapped list and its element
strings were handed over and never freed.

| call, 10,000 times | before | after |
|---|---|---|
| `to_string([n, 7])` | 50,004 (5 per call: 3 list cells + 2 strings) | flat |
| `to_string(Some([n]))` | leaked | flat |
| `string_join([int_to_string(n), "b"], ", ")` | leaked | flat |

## What landed

`string_join` / `march_string_join` borrow both arguments.

Producers of lists reaching it were checked for unowned references (the
hazard from `2026-09-13-builtin-borrow-classification.md`). March-built lists,
`march_string_split`'s fresh list, and `typed_array_to_list` (owned since that
change) all hand out owned references.

## What is not fixed here, and why

`to_string` of a List of **fresh** strings still leaks one object per
element. With two `int_to_string` elements it is 20,004 over 10,000 calls. The
cause is `map` calling the `fn x -> show(x)` lambda through a closure: the
caller transfers each element, and the read-only apply fn never releases it.
That is `specs/todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md`
exactly, and an identity lambda (`fn s -> s`, which owns its parameter) is
flat. It was added to that todo as another reproducer.

## Tests

`test/native/show_list_leak_probe.march` (+ `.expected`, `test/dune`) has
four legs of 10,000 calls: `List(Int)`, `List(String)` of literals,
`Option(List(Int))`, and `string_join` directly. Each prints its value; the
output is identical to the interpreter's. All four legs fail with the old
table entries.
