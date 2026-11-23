`[P2]` `Bytes.from_list` with a value outside 0..255 gives three different results on three backends (2026-11-11)

The doc string says out-of-range values are unsupported, that native backends keep the low 8 bits and
the browser raises. In fact the interpreter raises, the compiled binary wraps, and `--target js` under
node emits several bytes per bad value (six inputs become sixteen bytes).

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Bytes.to_list(Bytes.from_list([256, 257, 511, -1, 65, 1000]))))
end
end
```

Expected: one behaviour everywhere, preferably a panic naming `Bytes.from_list`.

Actual (interpreted / compiled): interpreted: run-time error `byte_to_char: 256 out of range 0–255`. Compiled: `[0, 1, 255, 255, 65, 232]`. `--target js` + node: `[239, 160, 128, 239, 160, 129, 239, 163, 191, 239, 191, 191, 65, 239, 171, 168]`.

Source: `from_list` / `from_list_go` in `stdlib/bytes.march`, builtin `byte_to_char` in each backend.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

## Decision (2026-11-23, owner)

Refine the parameter and keep a run-time panic.

- `Bytes.from_list(xs : List({Int | _ >= 0 && _ <= 255}))`. A call the checker can show violates
  it, such as a literal `300`, is a compile error.
- Refinements are not checked at run time (`specs/lang/refinement-types.md`: a refined type
  compiles to its base type), and outside `cap verified` the checker is silent on what it cannot
  prove. Checked 2026-11-23 on a build of `4744a0830`: with the same element refinement on a test
  function, `take([1, 2, 300])` is rejected (`refinement_violated`), but
  `take(List.map([1, 2, 3], fn x -> x * 100))` passes `--check` and runs.
- So `from_list_go` also panics on a value outside 0..255, with a message naming
  `Bytes.from_list`, on every engine. Register it in `panic_surface_contracted`
  (`lib/typecheck/typecheck_modcaps.ml`) as a contracted panic.
- Check the stdlib callers: each should prove the range or come from a source that already
  guarantees it (for example `Bytes.to_list`).
