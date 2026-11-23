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

## Decision (2026-11-23, owner)

Document it and add a lint; do not keep a `Listener` alive to the end of its lexical scope.
Write the note in the handles section of `specs/lang/capabilities.md` (regenerate `docs/`) and on
`Socket.local_port`'s doc string. The lint flags a `Listener` binding whose last use is
`local_port`. Reason: keeping the value alive would be a type-specific exception in the last-use
release in `lib/tir/perceus_core.ml`, which the in-place array update relies on.
