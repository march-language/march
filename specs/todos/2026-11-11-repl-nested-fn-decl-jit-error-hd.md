`[P3]` Native REPL: a function with a nested local `fn` declared at the prompt fails with "jit error: hd" (2026-11-11)

Declaring at the REPL prompt a function whose body defines a local helper `fn go(...)` prints
`jit error: hd` (an uncaught `List.hd` failure) and the function is not defined. A plain function
declared the same way works. The same function in a file runs interpreted and compiled (it is the
shape of `list_len_pr` in stdlib/presence.march).

Repro (`printf '...' | march repl`):

```march
fn len2(xs) do
  fn go(ys, acc) do
    match ys do
      Nil -> acc
      Cons(_, t) -> go(t, acc + 1)
    end
  end
  go(xs, 0)
end
len2([1, 2, 3])
```

Expected: `val len2 = <fn>` then `= 3`.
Actual (REPL): `jit error: hd`, then "I cannot find `len2`".

Source: declaration fragments in lib/jit/repl_jit.ml. Found while re-verifying the 2026-10-18 doc
sweep claims on 2026-11-11, a7110f95f.
