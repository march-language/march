`[P3]` `HttpClient.with_retry` stores `backoff_ms` but nothing ever sleeps (2026-11-11)

`run` and `run_on_fd` destructure the client with `_` in the backoff position and retry immediately. The doc string says so. Either implement the sleep or remove the parameter.

Repro (`http_backoff_unused.march`):

```march
mod A do
needs IO.Console
needs IO.NetConnect
needs IO.Clock
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _k : Cap(IO.Clock)) do
  -- port 1 refuses at once: 1 attempt + 4 retries, 400 ms backoff each
  let client = HttpClient.with_retry(HttpClient.new_client(), 4, 400)
  let t0 = unix_time_ms()
  let r = HttpClient.get(client, "http://127.0.0.1:1/")
  let ms = unix_time_ms() - t0
  println(to_string(Result.is_err(r)) ++ "; 4 retries with backoff_ms=400 took under 400 ms in all: " ++ to_string(ms < 400))
end
end
```

Expected: four retries with a 400 ms backoff take at least 1600 ms.

Actual (interpreted / compiled): under 400 ms in all / the same.

Source: `with_retry`, `transport_with_retry`, `run_scoped`, stdlib/http_client.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
