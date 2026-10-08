`[P2]` **Native `Json.parse` leaks one Float box per number.**

Filed 2026-10-08, found while hunting the shell's leaks
([2026-10-08-shell-slot-and-drop-leaks](../progress/2026-10-08-shell-slot-and-drop-leaks.md)).
LeakSanitizer on the shell test node showed it in the node's own `main`:
24 bytes allocated by `march_string_to_float`, called from
`Json.parse_number`, called from `Json.parse_array_elements`. Each input
calling the node's `Json.parse` showed it too.

Repro (compiled, macOS arm64, no sanitizer):

```march
mod Main do
  needs IO.Console
  fn lp(i, acc) do
    if i == 0 do acc
    else
      let n = match Json.parse("[1.5, 2]") do
        Ok(_) -> 1
        Err(_) -> 0
      end
      lp(i - 1, acc + n)
    end
  end
  fn main(_c : Cap(IO.Console)) do
    let a = live_allocs()
    let _ = lp(100, 0)
    let b = live_allocs()
    println(int_to_string(b - a))
  end
end
```

This prints 201: two objects per parse, one per number, plus one. It should
print 0 or close to it.

Start with the post-Perceus TIR of `Json.parse_number`
(`march query fn Json.parse_number`). The box `string_to_float` returns, or
the one `Number(..)` holds, is not released on some path. See also the
`string_to_float` boxed-Float history in
`specs/progress/` (`grep -l string_to_float specs/progress`).
