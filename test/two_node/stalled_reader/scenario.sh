# Scenario "stalled_reader": B gives A the go-ahead, A streams to B without
# waiting, and B is frozen (SIGSTOP) once the stream is flowing. A streams
# inside its endpoint actor's turn (the go-ahead's continuation), so this is
# where a send that waits for B's credit could hang A: a blocking send rides
# `Actor.call`, which takes the actor's own queued messages (the reader's
# LinkEnded, the heartbeat's PeerGone) as its reply, and A then waited
# forever in serve. Session frames are queued without limit instead
# (`NodeQueue.Unbounded`), so A finishes its stream at once; its heartbeat
# then declares B dead and lets the queue go. A never waits on B, so under
# the failure rules its role completes: "A: closed".
# See specs/progress/2026-09-18-session-frames-never-dropped.md.
# B speaks first, so it is role 1 and listens.
export STALL_B_ADDR=127.0.0.1:$PORT
export MARCH_SESSION_HEARTBEAT_MS=200
export MARCH_SESSION_TIMEOUT_MS=2000

ORDERED=1
start_node b
start_node a
wait_line b "B: receiving"
stop_node b
wait_exit a
kill_node b
