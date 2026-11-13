# A `Listener` whose last use is `local_port` is closed before the next line (2026-11-13)

Found in ocap phase 2b Task 15 (`stdlib/test/test_tls.march` `stub_socket`). In compiled code
a handle is released at its last use, so in

    let l = ... Socket.listen(0) ...
    let port = Socket.local_port(l)
    Socket.connect("127.0.0.1", port)

the listening socket is closed before the connect, which fails with `Connection refused`;
the interpreter (no drop glue) succeeds. The semantics are correct, but the trap is easy to
fall into. Options: a doc note in the handles chapter, a lint for a Listener whose last use is
`local_port`, or keeping a Listener alive to the end of its lexical scope.
