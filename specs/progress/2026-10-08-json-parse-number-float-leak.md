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

## Narrowed 2026-10-08

A 100-parse `live_allocs()` probe still grows beyond the fixed threshold on
current main. Post-Perceus TIR identifies the ownership boundary: it reuses
the `Option(Float)` cell from `string_to_float` as `JsonValue.Number(f)`, then
the generated `__drop$JsonValue` Number arm releases only that outer cell. The
boxed Float payload is not released. This is the same general boxed-Float ADT
drop limitation tracked by `2026-10-07-option-float-payload-shallow-drop.md`,
not a parser-local release that can safely be added here (a local `dec_rc f`
would leave `Number(f)` with a dangling payload). Fix that general drop path,
then add this probe as its Json coverage.
