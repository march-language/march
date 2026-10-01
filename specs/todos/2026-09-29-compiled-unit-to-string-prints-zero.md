`[P3]` **Compiled `to_string(())` prints `0`; the interpreter prints `()`.**

Filed 2026-09-29 from the observe quick wins
([`progress/2026-09-29-observe-quick-wins-results.md`](../progress/2026-09-29-observe-quick-wins-results.md), QW3).

```march
mod Render do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(to_string(()))
  end
end
```
Interpreted prints `()`; compiled (`--compile`) prints `0`. The unit value is the
immediate `0` at runtime and `march_value_to_string` cannot tell it from an Int
without the static type. Fix at lowering: when the argument's static type is Unit,
emit the literal `"()"` instead of calling the generic formatter. Add the case to
the backend-parity tests.
