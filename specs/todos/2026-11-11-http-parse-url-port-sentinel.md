`[P3]` Http.parse_url uses -1 as its bad-port sentinel, so :-1 is rejected and :-5 is accepted (2026-11-11)

`parse_url` maps a non-numeric port to `Some(-1)` and then rejects `Some(-1)`. A literal `:-1` is therefore `InvalidPort` while `:-5` (and `:99999`) is returned as a valid request. The doc string says the port is not range-checked, but a negative port can never be valid and the two negative inputs should agree.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  fn show(u) do
    match Http.parse_url(u) do
    Ok(r) -> println(u ++ " -> Ok port=" ++ to_string(Http.port(r)))
    Err(InvalidPort(p)) -> println(u ++ " -> InvalidPort(" ++ p ++ ")")
    Err(_) -> println(u ++ " -> other Err")
    end
  end
  show("http://h:-1/")
  show("http://h:-5/")
  show("http://h:99999/")
  show("http://h:abc/")
  show("http://h:/")
end
end
```

Expected: `InvalidPort` for both negative ports

Actual (interpreted / compiled): `http://h:-1/ -> InvalidPort(h:-1)`, `http://h:-5/ -> Ok port=Some(-5)` / same

Source: `parse_url` (`url_port`) in stdlib/http.march.
