# Scenario "fingerprint_skew": the two nodes run protocols that are identical
# except for what a payload type is MADE OF -- node-a's `Thing` is
# `{ x : Int }`, node-b's is `{ x : String }`. Before
# specs/progress/2026-09-21-protocol-fingerprint-payload-definitions.md the
# fingerprint digested each payload type by NAME, so the two agreed; the
# direct runner did not exchange a fingerprint at all, so nothing would have
# compared them even if they had differed. The skew then surfaced mid-session
# as `Protocol(role, "undecodable message: ...")` on whichever side happened
# to receive a `Thing` first.
#
# Now the fingerprint folds the payload type's definition in AND rides the
# hello, so BOTH nodes refuse at setup, before either body runs -- neither
# prints "RAN THE BODY".
export Q_A_ADDR=127.0.0.1:$PORT_A
export MARCH_SESSION_CONNECT_MS=8000

# A handshake refusal is a timing-sensitive setup path: A's accept window
# must not include B's compile, which on a CI runner can be longer than it.
compile a
compile b

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
