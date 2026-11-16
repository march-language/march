`[P2]` `HttpClient.with_connection`: a reconnect uses up two retries, and the reconnected socket is leaked (2026-11-11)

Two faults in `transport_keepalive` / `reconnect_and_retry` / `run_on_fd`.
1. Each reconnect takes two from the retry budget (one in each function), and the budget starts at `max_retries + 1`. So `with_retry(c, 0, _)` still retries once, and `with_retry(c, 6, _)` makes 5 attempts where `HttpClient.get` on the same client makes 7.
2. After a reconnect `transport_keepalive` returns the new fd, but `run_on_fd_scoped` discards it. Later requests go to the old, closed fd number, and `with_connection` closes that number a second time at the end. The new socket is never closed. In a single-threaded program the leak is often hidden because the new socket gets the number just freed; any other descriptor closed in between exposes it, and the stray `tcp_close` can then close a descriptor some other task has opened.

Repro (`http_keepalive_retries.march`):

```march
mod A do
needs IO.Console
needs IO.NetConnect
fn body(r) do
  match r do
    Ok(resp) -> to_string(Http.response_body(resp))
    Err(e) -> "Err " ++ to_string(e)
  end
end
fn stats() do body(HttpClient.get(HttpClient.new_client(), "http://127.0.0.1:47613/stats")) end
fn try_retries(n) do
  let _ = HttpClient.get(HttpClient.new_client(), "http://127.0.0.1:47613/reset")
  let client = HttpClient.with_retry(HttpClient.new_client(), n, 0)
  -- /drop: the server closes every connection without answering, so every attempt fails
  let r = HttpClient.with_connection(client, "http://127.0.0.1:47613", fn do_request ->
    match Http.get("http://127.0.0.1:47613/drop") do
      Ok(req) -> body(do_request(Http.set_body(req, "")))
      Err(_) -> "bad url"
    end)
  -- the /reset and /stats requests are one connection each and no drop
  println("with_retry(" ++ int_to_string(n) ++ "): " ++ to_string(r) ++ "; server saw " ++ stats() ++ " (attempts = drops; want " ++ int_to_string(n + 1) ++ ")")
end
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect)) do
  try_retries(0)
  try_retries(1)
  try_retries(2)
  try_retries(3)
  try_retries(4)
  try_retries(6)
  -- the same retry budget on the non-keepalive path
  let _ = HttpClient.get(HttpClient.new_client(), "http://127.0.0.1:47613/reset")
  let r = HttpClient.get(HttpClient.with_retry(HttpClient.new_client(), 4, 0), "http://127.0.0.1:47613/drop")
  println("HttpClient.get with_retry(4): " ++ body(r) ++ "; server saw " ++ stats())
end
end
```

Repro (`http_keepalive_fd_leak.march`):

```march
mod A do
needs IO.Console
needs IO.NetConnect
fn body(r) do
  match r do
    Ok(resp) -> to_string(Http.response_body(resp))
    Err(e) -> "Err " ++ to_string(e)
  end
end
fn open_fd() do
  match tcp_connect("127.0.0.1", 47613) do
    Ok(fd) -> fd
    Err(_) -> 0 - 1
  end
end
fn probe_fd() do
  -- the lowest free descriptor number: open a socket, note its number, close it
  let fd = open_fd()
  tcp_close(fd)
  fd
end
fn once(do_request) do
  match Http.get("http://127.0.0.1:47613/once") do
    Ok(req) -> body(do_request(Http.set_body(req, "")))
    Err(_) -> "bad url"
  end
end
fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect)) do
  let before = probe_fd()
  -- some other descriptor of the program, open while the connection is made
  -- and closed while it is in use (as any concurrent task's socket would be)
  let other = open_fd()
  let client = HttpClient.with_retry(HttpClient.new_client(), 1, 0)
  -- /once: the server answers and then closes, so request 2 finds the
  -- connection stale and reconnects
  let r = HttpClient.with_connection(client, "http://127.0.0.1:47613", fn do_request ->
    let a = once(do_request)
    tcp_close(other)
    let b = once(do_request)
    [a, b])
  println(to_string(r))
  let after = probe_fd()
  println("lowest free fd before: " ++ int_to_string(before) ++ ", after with_connection returned: " ++ int_to_string(after)
          ++ " (descriptors left open: " ++ int_to_string(after - before) ++ ")")
end
end
```

The repro needs the local test server from the triage scratch directory: `python3 server.py 47613` (it is reproduced at the end of this file).

Expected: attempts = `max_retries + 1` for every n; no descriptor left open after `with_connection` returns.

Actual (interpreted / compiled): attempts for n = 0, 1, 2, 3, 4, 6 are 2, 2, 3, 3, 4, 5 on both backends; descriptors left open: 1 / 2.

Source: `transport_keepalive`, `reconnect_and_retry`, `run_on_fd_scoped`, `with_connection_scoped`, stdlib/http_client.march. The fix is to count one retry per reconnect and to carry the current fd through the `do_request` closure.

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
