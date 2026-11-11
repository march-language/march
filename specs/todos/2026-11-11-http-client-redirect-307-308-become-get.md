`[P2]` `HttpClient` follows 307 and 308 redirects with a body-less GET (2026-11-11)

`handle_redirects` re-issues every redirect as `GET` with an empty body, whatever the status. RFC 9110 says 307 and 308 must keep the method and body, so a redirected POST or PUT silently becomes a GET and the caller gets a 200. The doc string states this behaviour. (Compiled programs never follow a redirect at all, for a different reason: see todo-http-compiled-response-parse-status-and-headers.md.)

Repro (`http_redirect_method.march`):

```march
mod A do
needs IO.Console
needs IO.NetConnect
fn show(r) do
  match r do
    Ok(resp) -> int_to_string(Http.response_status_code(resp)) ++ " " ++ to_string(Http.response_body(resp))
    Err(e) -> "Err " ++ to_string(e)
  end
end
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect)) do
  let client = HttpClient.with_redirects(HttpClient.new_client(), 3)
  -- the server's /echo answers "<METHOD> bodylen=<n>" for whatever reaches it
  println("POST 5 bytes -> 307 -> " ++ show(HttpClient.post(client, "http://127.0.0.1:47613/r307", "hello")))
  println("POST 5 bytes -> 308 -> " ++ show(HttpClient.post(client, "http://127.0.0.1:47613/r308", "hello")))
  println("PUT  5 bytes -> 307 -> " ++ show(HttpClient.put_request(client, "http://127.0.0.1:47613/r307", "hello")))
end
end
```

The repro needs the local test server from the triage scratch directory: `python3 server.py 47613` (it is reproduced at the end of this file).

Expected: the target sees `POST bodylen=5` (or `PUT bodylen=5`).

Actual (interpreted / compiled): `200 GET bodylen=0` for all three / status `153` or `308`, redirect not followed.

Source: `handle_redirects_scoped`, stdlib/http_client.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

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
