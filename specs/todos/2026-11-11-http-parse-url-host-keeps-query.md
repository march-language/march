`[P2]` Http.parse_url keeps the query (or fragment) in the host when the URL has no path (2026-11-11)

`parse_url` ends the authority only at the first `/`. For a URL with a query or fragment but no path, such as `http://h?x=1`, the host becomes `h?x=1` and the query is `None`. With a port the same input is rejected as `InvalidPort`. RFC 3986 ends the authority at `/`, `?` or `#`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  match Http.parse_url("http://h?x=1") do
  Ok(r) -> println("host=" ++ Http.host(r) ++ " path=" ++ Http.path(r) ++ " query=" ++ to_string(Http.query(r)))
  Err(_) -> println("Err")
  end
  match Http.parse_url("http://h:80?x=1") do
  Ok(r) -> println("host=" ++ Http.host(r) ++ " port=" ++ to_string(Http.port(r)) ++ " query=" ++ to_string(Http.query(r)))
  Err(InvalidPort(p)) -> println("InvalidPort " ++ p)
  Err(_) -> println("Err")
  end
  match Http.parse_url("http://h#frag") do
  Ok(r) -> println("host=" ++ Http.host(r) ++ " path=" ++ Http.path(r))
  Err(_) -> println("Err")
  end
end
end
```

Expected: `host=h path=/ query=Some(x=1)`

Actual (interpreted / compiled): `host=h?x=1 path=/ query=None` / same

Source: `parse_url` in stdlib/http.march.
