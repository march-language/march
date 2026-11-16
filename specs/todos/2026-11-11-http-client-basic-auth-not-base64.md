`[P2]` `HttpClient.step_basic_auth` sends `user:pass` in the clear instead of base64 (2026-11-11)

The step sets `Authorization: Basic user:pass`. RFC 7617 requires the credentials to be base64 encoded, so any conforming server rejects the header. The doc string already admits this; the function has never produced a usable header.

Repro (`http_basic_auth.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  match Http.get("http://example.com/") do
    Err(_) -> println("bad url")
    Ok(req) ->
      let basic = HttpClient.step_basic_auth("ann", "pw")
      println(to_string(Result.map(basic(req), fn r -> Http.get_request_header(r, "Authorization"))))
      println("RFC 7617 wants: Basic " ++ Base64.encode(Bytes.from_string("ann:pw")))
  end
end
end
```

Expected: `Ok(Some(Basic YW5uOnB3))`

Actual (interpreted / compiled): `Ok(Some(Basic ann:pw))` / `Ok(Some(Basic ann:pw))`

Source: `step_basic_auth`, stdlib/http_client.march. The fix is to pass `user ++ ":" ++ pass` through `Base64.encode`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
