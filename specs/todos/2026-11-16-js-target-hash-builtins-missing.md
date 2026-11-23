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

## Decision (2026-11-23, owner)

**Not settled.** The owner chose BigInt on JS so `hash` returns the same values as the C runtime
and the interpreter. That does not work as stated: the JS target stores an Int in a JS double,
exact only within ±(2^53 − 1), and an Int result outside that range throws (`__int_result` in
`runtime/march_runtime.mjs`; `specs/lang/type-system.md`, the JS Int section). A 62-bit hash
computed in BigInt would throw for almost every input when returned as an Int. The choices left:

1. Mask `hash` to 53 bits or fewer on every engine. JS can then return the same values, but hash
   values change everywhere, including `Hamt`'s layout and iteration order.
2. Compute in BigInt on JS and fold the result into the safe range there only. JS stays usable,
   and its hash values differ from native ones (they are never compared across engines unless
   one is serialized).
3. Make the JS target's Int a BigInt. That is a change to the whole target, not to this
   builtin.
