`[P2]` `HttpClient.TransportError` lacks `SchemeNotSupported`, so a total match on it can panic (2026-11-11)

HttpClient re-declares HttpTransport's `TransportError` but without `SchemeNotSupported`. `with_connection` on an `https://` URL returns `HttpTransportError(SchemeNotSupported(..))`, a value that is not in the type the checker assigns to it. A match that handles every declared constructor then panics at run time with a non-exhaustive match.

Repro (`http_transport_error_mirror.march`):

```march
mod A do
needs IO.Console
needs IO.NetConnect
-- Every constructor HttpClient.TransportError declares is handled, so the
-- checker accepts this match as exhaustive.
fn name(e : HttpClient.TransportError) : String do
  match e do
    HttpClient.ConnectionRefused(m) -> "ConnectionRefused " ++ m
    HttpClient.ConnTimeout(m) -> "ConnTimeout " ++ m
    HttpClient.SendError(m) -> "SendError " ++ m
    HttpClient.RecvError(m) -> "RecvError " ++ m
    HttpClient.ConnParseError(m) -> "ConnParseError " ++ m
    HttpClient.Closed -> "Closed"
    HttpClient.Refused(m) -> "Refused " ++ m
  end
end
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect)) do
  -- an https URL makes HttpTransport answer SchemeNotSupported, a constructor
  -- HttpClient's mirror of the type does not have
  let r = HttpClient.with_connection(HttpClient.new_client(), "https://127.0.0.1:1/", fn d -> 1)
  println(to_string(r))
  match r do
    Err(HttpClient.HttpTransportError(e)) -> println("transport error: " ++ name(e))
    Err(_) -> println("other error")
    Ok(_) -> println("Ok")
  end
end
end
```

Expected: the error is one of the constructors of `HttpClient.TransportError`, and the match is total.

Actual (interpreted / compiled): panic `Non-exhaustive pattern match: no branch matched the value SchemeNotSupported(..)` / see the compiled column of RESULTS.md.

Source: `type TransportError`, stdlib/http_client.march (the mirror) and stdlib/http_transport.march (the original). The fix is to drop the mirror (the type namespace is global) or add the constructor.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
