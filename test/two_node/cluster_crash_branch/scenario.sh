# Scenario "cluster_crash_branch": a crash branch taken over the cluster node
# service. The Logging protocol declares `may crash C`; node-c is SIGKILLed
# once it is in the session and before it sends Read. I is waiting on C with
# nothing queued and has a crash continuation installed for it, so instead of
# being cancelled it takes the crash branch, tells L, and closes. All three
# entry points return, and nothing is cancelled.
#
# The point of this scenario is the DETECTOR: over a cluster node, C going is
# reported by the node (SWIM, or a refused redial) rather than by a dropped
# per-session connection, and `SessionNode.check_waiting` is the same code in
# both paths. Phase B1 (specs/progress/2026-09-20-crash-branches-b1.md) said
# that should work and left it unpinned.
#
# I prints the crashed role but not the cause: which detector wins the race
# decides the wording, so pinning it would be pinning a race.
#
# Every node is compiled up front. `start_node` otherwise compiles at that
# moment, and CI's slower compile lands inside the window between C joining
# the session and the kill.
export MARCH_NUM_SCHEDULERS=1

ORDERED=1
compile a
compile b
compile c
start_node a
start_node b
start_node c                   # every node blocks in await_members until all three are up
wait_line a "node-a: up"
wait_line c "C: in session"
wait_line b "I: got Trigger"   # I is at its receive from C
kill_node c                    # SIGKILL before its send
wait_exit b
wait_exit a
