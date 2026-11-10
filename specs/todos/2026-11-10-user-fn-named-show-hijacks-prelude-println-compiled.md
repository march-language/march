# A user function named `show` changes what `println` prints, compiled only

Found 2026-11-10 while writing ocap phase 1's conformance fixtures
(test/cap_conformance/process_refused.march, first draft).

A module that defines its own `fn show(r : Result(a, CapError)) : String` and
calls `println(show(x))` prints the string interpreted, but compiled and
through the JIT each line came out as `Err(<the string>)`: the Prelude's
`println(x)`, which calls `show(x)` internally, reached the user's `show`
instead of the `Show` interface method. The interpreter resolves it correctly.

Same family as the module-function-shadows-a-builtin and user-fn-named-like-a-
libc-symbol traps. Pre-existing: reproduced on `aeac8a566` (before ocap phase 1)
with this program, which prints `bad` / `ok` interpreted and `Err(bad)` /
`Ok(1)` compiled. A monomorphic `show(r : Result(Int, String))` does not
reproduce it; the polymorphic parameter does.

```march
mod U do
  needs IO.Console
  fn show(r : Result(a, String)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> e
    end
  end
  fn main(_c : Cap(IO.Console)) do
    println(show(Err("bad")))
    println(show(Ok(1)))
  end
end
```

Done when a user `show` cannot change the Prelude's `println`, with a
compiled-vs-interpreted regression test.
