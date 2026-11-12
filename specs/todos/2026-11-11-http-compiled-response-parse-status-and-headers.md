`[P1]` Compiled HTTP client: odd status codes are halved (401 reads as 200), headers are always empty, and a dead connection reads as a 200 (2026-11-11)

Not one of the 2026-10-18 claims; found on 2026-11-11 while checking the redirect claim. The compiled `http_parse_response` (runtime/march_http.c, `march_http_parse_response`) disagrees with the interpreter in three ways, and every `HttpTransport` / `HttpClient` response goes through it:
1. The status is stored as a raw integer where the compiled code expects its Int representation, so every ODD status reads as (n - 1) / 2: 201 as 100, 307 as 153, 401 as 200, 403 as 201, 503 as 251. `step_raise_on_error` therefore lets a 401 through as a success. Rated P1 for that reason.
2. The headers list is always `Nil` ("Build empty headers list"), so `Http.get_header` finds nothing and no redirect is ever followed.
3. It never returns `Err`: a connection closed without a byte parses as status 200 with an empty body.

Repro (`http_compiled_response_parity.march`):

```march
-- Not one of the 2026-10-18 claims: found while checking the redirect claim.
-- Interpreted and compiled disagree on what an HTTP response is.
mod A do
needs IO.Console
needs IO.NetConnect
fn show(r) do
  match r do
    Ok(resp) -> "status " ++ int_to_string(Http.response_status_code(resp)) ++ ", X-Test=" ++ to_string(Http.get_header(resp, "x-test")) ++ ", body \"" ++ to_string(Http.response_body(resp)) ++ "\""
    Err(e) -> "Err " ++ to_string(e)
  end
end
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect)) do
  let c = HttpClient.new_client()
  println("200: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/200")))
  println("201: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/201")))
  println("401: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/401")))
  println("403: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/403")))
  println("404: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/404")))
  println("503: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/status/503")))
  println("server closes without answering: " ++ show(HttpClient.get(c, "http://127.0.0.1:47613/drop")))
  println("401 with step_raise_on_error: " ++ show(HttpClient.get(HttpClient.add_response_step(c, "raise", HttpClient.step_raise_on_error), "http://127.0.0.1:47613/status/401")))
end
end
```

The repro needs the local test server from the triage scratch directory: `python3 server.py 47613` (it is reproduced at the end of this file).

Expected: the interpreter's output on both backends.

Actual (interpreted / compiled): 200/201/401/403/404/503 with `X-Test=Some(yes)`, `Err ConnParseError` for the dropped connection, `Err StepError("step_raise_on_error", "401")` / 200, 100, 200, 201, 404, 251, all with `X-Test=None`; the dropped connection is `status 200, body ""`; the 401 passes `step_raise_on_error`.

Source: `march_http_parse_response`, runtime/march_http.c; called from `send_and_recv_on` and `request_plain_raw`, stdlib/http_transport.march.

Found 2026-11-11 on a7110f95f while re-verifying the 2026-10-18 doc sweep claims.

`server.py`:

```python
#!/usr/bin/env python3
"""Tiny local HTTP test server for the HttpClient repros. 127.0.0.1 only.
/echo        -> 200, body "<METHOD> bodylen=<n>"
/r307 /r308  -> that redirect status, Location: /echo
/status/NNN  -> status NNN, body "body", header X-Test: yes
/once        -> 200 "ok", then the server closes the connection (a stale keep-alive)
/drop        -> closes the connection without answering
/stats       -> 200, body "conns=<n> drops=<n>" (counts since the last /reset)
/reset       -> zeroes the counters
Other requests are served keep-alive unless they carry Connection: close."""
import socket, sys, threading
port = int(sys.argv[1])
lock = threading.Lock()
st = {"conns": 0, "drops": 0}
def read_req(c):
    buf = b""
    while b"\r\n\r\n" not in buf:
        d = c.recv(4096)
        if not d: return None
        buf += d
    head, rest = buf.split(b"\r\n\r\n", 1)
    lines = head.decode("latin1").split("\r\n")
    meth, path, _ = lines[0].split(" ", 2)
    n = 0
    close = False
    for l in lines[1:]:
        if l.lower().startswith("content-length:"): n = int(l.split(":", 1)[1])
        if l.lower().replace(" ", "") == "connection:close": close = True
    while len(rest) < n:
        d = c.recv(4096)
        if not d: break
        rest += d
    return meth, path, len(rest[:n]), close
def send(c, status, body, extra=""):
    b = body.encode()
    c.sendall(("HTTP/1.1 %s\r\nContent-Length: %d\r\n%s\r\n" % (status, len(b), extra)).encode() + b)
def serve(c):
    try:
        while True:
            r = read_req(c)
            if r is None: return
            meth, path, n, close = r
            if path == "/stats":
                with lock: s = "conns=%d drops=%d" % (st["conns"], st["drops"])
                send(c, "200 OK", s)
                if close: return
                continue
            if path == "/reset":
                with lock: st["conns"] = 0; st["drops"] = 0
                send(c, "200 OK", "reset")
                if close: return
                continue
            if path == "/drop":
                with lock: st["drops"] += 1
                return
            if path == "/echo": send(c, "200 OK", "%s bodylen=%d" % (meth, n))
            elif path == "/r307": send(c, "307 Temporary Redirect", "", "Location: /echo\r\n")
            elif path == "/r308": send(c, "308 Permanent Redirect", "", "Location: /echo\r\n")
            elif path.startswith("/status/"): send(c, path[8:] + " X", "body", "X-Test: yes\r\n")
            elif path == "/once": send(c, "200 OK", "ok"); return
            else: send(c, "404 Not Found", "nope")
            if close: return
    finally:
        c.close()
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(64)
while True:
    c, _ = s.accept()
    with lock: st["conns"] += 1
    threading.Thread(target=serve, args=(c,), daemon=True).start()
```
