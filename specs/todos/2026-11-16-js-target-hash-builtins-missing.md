`[P2]` JS target: `hash` has no implementation (`march_hash_int` & co.)

Found 2026-11-16 while fixing `compare`/`hash` passed as values
(`specs/progress/2026-11-11-compiled-builtin-passed-as-value-undefined-symbol.md`).
Unrelated to that fix: it reproduces on main before it, with a direct call.

```march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(hash(7)))
  end
end
```

Interpreted and native compiled: prints a hash. `--target js`:

```
error: builtin `march_hash_int` has no JavaScript-target implementation (called from main (h1.march:3)).
```

So every `Hamt` and every `Hash`-keyed structure fails to build for the browser. Fix: map the
`march_hash_{int,float,string,bool}` builtins in `lib/tir/js_emit.ml` to helpers in
`runtime/march_runtime.mjs` that return the same values as the C runtime (the interpreter, native
and JS must agree when a hash is printed or used for ordering), and add a JS case to the
test that pins `hash` output.
