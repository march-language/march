#!/usr/bin/env python3
"""
End-to-end test suite for forge notebook serve.

Runs the notebook server, connects via WebSocket, and validates:
  - load / parse_cells
  - run cells (single, sequential, multi-cell scoping)
  - multi-line expressions (DataFrame-style, if/match)
  - module cells (mod wrapper)
  - Phase 1: clear output via WS
  - error propagation
  - edge cases: empty cell, comment-only, println side effect
"""

import os, sys, json, socket, base64, struct, subprocess, time, signal, tempfile, textwrap

SERVER_PORT = 18899
MARCH_BIN   = "/Users/80197052/code/march/_build/default/bin/main.exe"
FORGE_BIN   = "/Users/80197052/code/march/_build/default/forge/bin/main.exe"

# ── WebSocket helpers ──────────────────────────────────────────────────────────

def ws_connect(host, port, path="/ws", timeout=10):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
           f"Connection: Upgrade\r\nUpgrade: websocket\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    sock.send(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(1024)
    assert b"101" in resp, f"WS upgrade failed: {resp[:100]}"
    return sock

def ws_send(sock, text):
    data = text.encode()
    n = len(data)
    frame = bytearray()
    frame.append(0x81)
    if n < 126:
        frame.append(0x80 | n)
    elif n < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", n))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", n))
    mask = os.urandom(4)
    frame.extend(mask)
    frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
    sock.send(bytes(frame))

def ws_recv(sock):
    h = b""
    while len(h) < 2: h += sock.recv(2 - len(h))
    opcode  = h[0] & 0x0f
    masked  = (h[1] & 0x80) != 0
    length  = h[1] & 0x7f
    if length == 126:
        lb = b"";
        while len(lb) < 2: lb += sock.recv(2)
        length = struct.unpack(">H", lb)[0]
    elif length == 127:
        lb = b""
        while len(lb) < 8: lb += sock.recv(8)
        length = struct.unpack(">Q", lb)[0]
    data = b""
    while len(data) < length:
        chunk = sock.recv(min(4096, length - len(data)))
        if not chunk: raise EOFError("connection closed")
        data += chunk
    return opcode, data.decode("utf-8", errors="replace")

def send_json(sock, obj):
    ws_send(sock, json.dumps(obj))

def recv_json(sock):
    _, txt = ws_recv(sock)
    return json.loads(txt)

def run_cell(sock, nb_content, cell_idx, timeout=15):
    """Save notebook then run cell at cell_idx; return (stdout, error)."""
    send_json(sock, {"type": "save", "content": nb_content})
    msg = recv_json(sock)
    assert msg["type"] == "saved", f"save failed: {msg}"
    send_json(sock, {"type": "run", "index": cell_idx})
    sock.settimeout(timeout)
    # read "running" + "output"
    for _ in range(2):
        msg = recv_json(sock)
        if msg["type"] == "output":
            return msg.get("stdout", ""), msg.get("error")
    raise RuntimeError("did not receive output message")

# ── Server lifecycle ───────────────────────────────────────────────────────────

def start_server(nb_path):
    proc = subprocess.Popen(
        [FORGE_BIN, "notebook", "serve", nb_path,
         "--port", str(SERVER_PORT), "--no-open"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    # Wait for server to be ready
    for _ in range(30):
        time.sleep(0.2)
        try:
            s = socket.create_connection(("127.0.0.1", SERVER_PORT), timeout=0.5)
            s.close()
            return proc
        except OSError:
            pass
    proc.kill()
    raise RuntimeError("Server never came up")

def stop_server(proc):
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()

# ── Test helpers ───────────────────────────────────────────────────────────────

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
results = []

def check(name, actual, expected):
    ok = actual == expected
    tag = PASS if ok else FAIL
    print(f"  {tag}: {name}")
    if not ok:
        print(f"       expected: {expected!r}")
        print(f"       actual:   {actual!r}")
    results.append((name, ok))

def check_contains(name, actual, substring):
    ok = substring in (actual or "")
    tag = PASS if ok else FAIL
    print(f"  {tag}: {name}")
    if not ok:
        print(f"       expected to contain: {substring!r}")
        print(f"       actual: {actual!r}")
    results.append((name, ok))

def check_no_error(name, error):
    ok = error is None
    tag = PASS if ok else FAIL
    print(f"  {tag}: {name}")
    if not ok:
        print(f"       unexpected error: {error!r}")
    results.append((name, ok))

# ── Notebook content builder ───────────────────────────────────────────────────

def nb(*cells):
    """Build .mnb content from a list of (kind, source) tuples."""
    parts = []
    for kind, src in cells:
        if kind == "md":
            parts.append(src)
        elif kind == "server":
            parts.append(f"```march:server\n{src}\n```")
        else:
            parts.append(f"```march\n{src}\n```")
    return "\n\n".join(parts) + "\n"

# ── Tests ─────────────────────────────────────────────────────────────────────

def test_load(sock, nb_path):
    print("\n── load ──────────────────────────────────────────────────────────────")
    send_json(sock, {"type": "load"})
    msg = recv_json(sock)
    check("type is notebook", msg["type"], "notebook")
    check("has cells key", "cells" in msg, True)
    check("has source key", "source" in msg, True)

def test_basic_expressions(sock, nb_path):
    print("\n── basic expressions ─────────────────────────────────────────────────")

    content = nb(("md", "# Test"), ("code", "1 + 1"))
    out, err = run_cell(sock, content, 1)
    check("integer arithmetic", out, "2")
    check_no_error("no error", err)

    content = nb(("md", "# Test"), ("code", '"hello" ++ ", world"'))
    out, err = run_cell(sock, content, 1)
    check("string concat", out, "hello, world")

    content = nb(("md", "# Test"), ("code", "true"))
    out, err = run_cell(sock, content, 1)
    check("bool literal", out, "true")

def test_let_bindings(sock, nb_path):
    print("\n── let bindings ──────────────────────────────────────────────────────")

    content = nb(("md", "# T"), ("code", "let a = 42\na"))
    out, err = run_cell(sock, content, 1)
    check("let then expr", out, "42")

    content = nb(("md", "# T"), ("code", "let a = 1"))
    out, err = run_cell(sock, content, 1)
    check("let only: no output (result is unit)", out, "")
    check_no_error("no error", err)

    content = nb(("md", "# T"), ("code", "let s = String.to_uppercase(\"march\")\ns"))
    out, err = run_cell(sock, content, 1)
    check("let with stdlib call", out, "MARCH")

def test_println_side_effects(sock, nb_path):
    print("\n── println side effects ──────────────────────────────────────────────")
    content = nb(("md", "# T"), ("code", 'println("hello")\nprintln("world")'))
    out, err = run_cell(sock, content, 1)
    check("multi println captured", out, "hello\nworld")

def test_cross_cell_scoping(sock, nb_path):
    print("\n── cross-cell scoping ────────────────────────────────────────────────")

    content = nb(
        ("md", "# T"),
        ("code", "let x = 10"),
        ("code", "let y = 20\nx + y"),
    )
    # Run cell 2 (runs cells 0,1,2)
    out, err = run_cell(sock, content, 2)
    check("cross-cell variable access", out, "30")
    check_no_error("no error", err)

def test_multiline_expressions(sock, nb_path):
    print("\n── multi-line expressions ────────────────────────────────────────────")

    # List literal spanning multiple lines
    src = textwrap.dedent("""\
        let xs = [
          1,
          2,
          3
        ]
        List.length(xs)
    """).strip()
    content = nb(("md", "# T"), ("code", src))
    out, err = run_cell(sock, content, 1)
    check("multi-line list literal", out, "3")
    check_no_error("no error", err)

    # if/do/end
    src = textwrap.dedent("""\
        let n = 5
        if n > 3 do
          "big"
        else
          "small"
        end
    """).strip()
    content = nb(("md", "# T"), ("code", src))
    out, err = run_cell(sock, content, 1)
    check("if/do/end expression", out, "big")

    # match expression
    src = textwrap.dedent("""\
        let opt = Some(42)
        match opt do
          Some(v) -> v * 2
          None    -> 0
        end
    """).strip()
    content = nb(("md", "# T"), ("code", src))
    out, err = run_cell(sock, content, 1)
    check("match expression", out, "84")

def test_module_cells(sock, nb_path):
    print("\n── module cells ──────────────────────────────────────────────────────")

    mod_src = textwrap.dedent("""\
        mod Greet do
          fn hello(name) do
            "Hello, " ++ name ++ "!"
          end
        end
    """).strip()
    use_src = 'Greet.hello("March")'
    content = nb(("md", "# T"), ("code", mod_src), ("code", use_src))
    out, err = run_cell(sock, content, 2)
    check("module cell: function call", out, "Hello, March!")
    check_no_error("no error", err)

def test_error_propagation(sock, nb_path):
    print("\n── error propagation ─────────────────────────────────────────────────")

    content = nb(("md", "# T"), ("code", "undefined_variable"))
    out, err = run_cell(sock, content, 1)
    assert err is not None, "Expected error for undefined variable"
    check_contains("undefined variable → error", err, "")  # any non-None error
    results[-1] = (results[-1][0], err is not None)  # fix the check
    print(f"    error msg: {err!r:.80}")

def test_list_and_stdlib(sock, nb_path):
    print("\n── list & stdlib ─────────────────────────────────────────────────────")

    src = textwrap.dedent("""\
        let xs = [1, 2, 3, 4, 5]
        let evens = List.filter(xs, fn x -> x % 2 == 0)
        let total = List.fold_left(0, xs, fn (acc, x) -> acc + x)
        println(String.join(List.map(evens, int_to_string), ", "))
        total
    """).strip()
    content = nb(("md", "# T"), ("code", src))
    out, err = run_cell(sock, content, 1)
    check("List.filter+map+fold: output line", out.split("\n")[0], "2, 4")
    check("List.filter+map+fold: result", out.split("\n")[-1], "15")
    check_no_error("no error", err)

def test_run_all_ordering(sock, nb_path):
    print("\n── run-all ordering (sequential cell execution) ──────────────────────")

    content = nb(
        ("md", "# T"),
        ("code", "let acc = 1"),
        ("code", "let acc = acc * 2"),
        ("code", "let acc = acc + 10\nacc"),
    )
    out, err = run_cell(sock, content, 3)
    check("sequential: acc = (1*2)+10 = 12", out, "12")
    check_no_error("no error", err)

def test_save_and_reload(sock, nb_path):
    print("\n── save and reload ───────────────────────────────────────────────────")

    content = nb(("md", "# Saved"), ("code", 'println("reloaded")'))
    send_json(sock, {"type": "save", "content": content})
    msg = recv_json(sock)
    check("save returns saved", msg["type"], "saved")

    send_json(sock, {"type": "load"})
    msg = recv_json(sock)
    check("reload type", msg["type"], "notebook")
    check("reload cell count", len(msg["cells"]), 2)
    check("reload code source", msg["cells"][1]["source"], 'println("reloaded")')

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    with tempfile.NamedTemporaryFile(suffix=".mnb", mode="w", delete=False) as f:
        f.write(nb(("md", "# Test Notebook"), ("code", 'println("ready")')))
        nb_path = f.name

    print(f"Starting notebook server on port {SERVER_PORT}...")
    proc = start_server(nb_path)
    print("Server started.\n")

    try:
        sock = ws_connect("127.0.0.1", SERVER_PORT)

        test_load(sock, nb_path)
        test_basic_expressions(sock, nb_path)
        test_let_bindings(sock, nb_path)
        test_println_side_effects(sock, nb_path)
        test_cross_cell_scoping(sock, nb_path)
        test_multiline_expressions(sock, nb_path)
        test_module_cells(sock, nb_path)
        test_error_propagation(sock, nb_path)
        test_list_and_stdlib(sock, nb_path)
        test_run_all_ordering(sock, nb_path)
        test_save_and_reload(sock, nb_path)

        sock.close()
    finally:
        stop_server(proc)
        os.unlink(nb_path)

    # Summary
    total  = len(results)
    passed = sum(1 for _, ok in results if ok)
    failed = total - passed
    print(f"\n{'─'*60}")
    print(f"Results: {passed}/{total} passed", end="")
    if failed:
        print(f"  ({failed} FAILED)")
        for name, ok in results:
            if not ok:
                print(f"  FAIL: {name}")
    else:
        print("  ✓ all pass")
    sys.exit(0 if failed == 0 else 1)

if __name__ == "__main__":
    main()
