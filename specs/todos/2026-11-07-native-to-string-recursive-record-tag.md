`[P3]` Native `to_string` prints `#<tag:0>` for a recursive record inside a list.

Found 2026-11-07 reviewing `fix/js-test-runner-gaps`. With no `Show` impl,

```march
type Node = { v : Float, kids : List(Node) }
println(to_string({ v: 1.0, kids: [{ v: 2.0, kids: [] }] }))
```

prints `{ kids: [{ kids: [], v: 2. }], v: 1. }` interpreted and on `--target js`, but
`{ kids: [#<tag:0>], v: 1. }` from a `--compile` binary. A non-recursive record in a list
(`type Q = { ps : List(P) }`) prints correctly natively, so the constructor-descriptor renderer
(`Llvm_ctor_desc`, `march_extras.c`) loses the descriptor when the element type is the record
being described. Fix it there and pin it with an interp/native/JS parity case.
