#!/usr/bin/env bash
# Two-node failure-semantics harness: two (optionally three) compiled March
# programs as separate OS processes, a fault script applied from outside,
# per-node sorted goldens.
#
#   scripts/two-node.sh <scenario>          # test/two_node/<scenario>/
#   scripts/two-node.sh --list
#   scripts/two-node.sh --list K/N           # shard K of N (1-based): every
#                                            # scenario whose index in the
#                                            # sorted list is K-1 mod N
#
# A scenario directory holds node_a.march / node_b.march (and node_c.march for
# a three-node scenario), node_<x>.expected (each node's stdout, sorted; a
# node started twice appends), and scenario.sh, the fault script, sourced
# with these helpers in scope:
#
#   start_node <a|b|c> [creation] start node-<x> in the background. The first
#                                 start_node compiles every node of the
#                                 scenario (each once), so no node's compile
#                                 runs inside another node's setup deadline;
#                                 set every COMPILE_FLAGS_<x> before it.
#                                 Every node gets MARCH_PORT_A / MARCH_PORT_B /
#                                 MARCH_PORT_C, one listen port per node, so a
#                                 scenario chooses who listens and who connects;
#                                 node-b also gets MARCH_NODE_PORT (= MARCH_PORT_B)
#                                 and MARCH_NODE_CREATION, node-a MARCH_PEER_PORT
#                                 (= MARCH_PORT_B), the two-node spelling.
#   compile <a|b|c>               compile the node now rather than in the first
#                                 start_node, for a scenario that needs the
#                                 binary (or the work dir's source copy) earlier
#   kill_node <a|b|c>             SIGKILL it (a crash, distinct from a close)
#   stop_node / cont_node <a|b|c> SIGSTOP / SIGCONT (a stall, distinct from a crash)
#   drop_link [port...] / heal    drop every TCP packet to or from node-b's port
#                                 (or each port named)
#                                 (a partition: nothing is refused, nothing
#                                 arrives) / remove the rule. Linux iptables, as
#                                 root or via passwordless sudo; anywhere else the
#                                 scenario exits 3, "skipped: needs root", which
#                                 CI's loop treats as a failure and a local run
#                                 reads as a skip. Rules are removed on exit.
#   wait_line <a|b|c> <text>      block until the node's stdout contains <text>
#   wait_exit <a|b|c>             block until the node's process exits
#   need_built <path>             build <path> (relative to the repo, e.g.
#                                 test/hcr_deploy.exe) with dune unless it is
#                                 already built, so a scenario's helper exe is
#                                 never a CI-only failure
#   COMPILE_FLAGS_<a|b|c>         (set by the scenario) extra `march --compile`
#                                 flags for that node
#   ORDERED=1                     (set by the scenario) diff each node's stdout
#                                 unsorted: only for a node that prints from one
#                                 actor, whose order is then the protocol's
#
#   run_node <binary>             exec a node binary with its in-program
#                                 deadlines scaled under ASan (see TIME_SCALE
#                                 below). start_node uses it; a scenario that
#                                 launches a node itself (the control-plane
#                                 ones) ends the node's subshell with it
#   TIME_SCALE                    (read-only) 1, or the ASan factor, for a
#                                 scenario's own deadlines (ctl_until uses it)
#   TIME_SCALE_EXEMPT             (set by the scenario) deadline variables NOT
#                                 to scale, for a scenario whose point is how
#                                 its own timing compares with that deadline
#
# Every wait has a deadline (TWO_NODE_TIMEOUT, default 60 s) and fails loudly
# with every node's output. Why two processes and not two green threads: see
# specs/progress/2026-09-14-two-node-failure-semantics-harness.md.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
MARCH=${MARCH_BIN:-$root/_build/default/bin/main.exe}
TIMEOUT=${TWO_NODE_TIMEOUT:-60}

# --list K/N deals the sorted list round-robin rather than cutting it into
# contiguous runs: scenarios that share a prefix also share a cost (the four
# control_* are 135-200 s each, the drain_* ~25-50 s), so a contiguous cut
# would put every heavy family in one shard. CI's two-node job runs two shards.
if [ "${1:-}" = "--list" ]; then
  shard=${2:-1/1}
  if [[ $shard =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] \
     && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ]; then
    k=${BASH_REMATCH[1]}; n=${BASH_REMATCH[2]}
  else
    echo "two-node: --list takes K/N with 1 <= K <= N, got: $shard" >&2; exit 2
  fi
  # LC_ALL=C: every shard must see the same order, or one scenario runs
  # twice and another never.
  LC_ALL=C ls "$root/test/two_node" | awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1'
  exit 0
fi
scenario=${1:?usage: scripts/two-node.sh <scenario> | --list}
dir=$root/test/two_node/$scenario
[ -f "$dir/scenario.sh" ] || { echo "two-node: no such scenario: $scenario" >&2; exit 2; }
[ -x "$MARCH" ] || { echo "two-node: compiler not built: $MARCH" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/two-node-$scenario.XXXXXX")

# ── In-program deadlines under AddressSanitizer ─────────────────────────────
# The sanitize gate (specs/lang/golden/sanitize.sh) runs every scenario with
# MARCH_SANITIZE=1, which makes every node several times slower, more on a
# loaded runner. TWO_NODE_TIMEOUT stretches the harness's own waits; it does
# not reach the deadlines INSIDE the nodes, and those are what the sweep kept
# tripping, a different scenario nearly every run: SWIM declaring a slow but
# healthy peer dead at its 3 s suspect timeout, a placement conflict outliving
# its 5 s grace. Some were patched one scenario at a time (HCR_SUSPECT_MS);
# this is the one place instead.
#
# Under MARCH_SANITIZE, run_node multiplies each deadline below by TIME_SCALE
# (TWO_NODE_ASAN_SCALE, default 3): the value the scenario exported, or the
# stdlib's default when it exported none. Only deadlines that DECLARE A
# FAILURE are scaled (a peer dead, a setup abandoned, a conflict real), never
# a poll interval or a "wait at least this long" delay, which would only make
# a slow run slower. Without MARCH_SANITIZE, TIME_SCALE is 1 and run_node is
# a bare exec: the normal two-node job runs exactly as before.
#
#   MARCH_SWIM_PERIOD_MS / _ACK_MS / _SUSPECT_MS   ClusterNode.config (SWIM)
#   MARCH_SESSION_CONNECT_MS / _TIMEOUT_MS          session setup / heartbeat
#   MARCH_PLACEMENT_CONFLICT_GRACE_MS               Topology: a held endpoint
#   MARCH_HOOK_TIMEOUT_MS                           Topology: a placement hook
#   MARCH_CONTROL_AGENT_GRACE_MS                    control: an agent's mark
#
# Each default here must be the stdlib's (stdlib/cluster_node.march,
# session_node.march, topology.march, lib/desugar/control_wiring.march).
# TWO_NODE_TIME_SCALE is exported for a node program's own deadlines.
if [ -n "${MARCH_SANITIZE:-}" ]; then TIME_SCALE=${TWO_NODE_ASAN_SCALE:-3}; else TIME_SCALE=1; fi
[[ $TIME_SCALE =~ ^[1-9][0-9]*$ ]] \
  || { echo "two-node: TWO_NODE_ASAN_SCALE must be a positive integer, got: $TIME_SCALE" >&2; exit 2; }
export TWO_NODE_TIME_SCALE=$TIME_SCALE
scaled_deadlines="MARCH_SWIM_PERIOD_MS=1000 MARCH_SWIM_ACK_MS=500 MARCH_SWIM_SUSPECT_MS=3000
  MARCH_SESSION_CONNECT_MS=20000 MARCH_SESSION_TIMEOUT_MS=10000
  MARCH_PLACEMENT_CONFLICT_GRACE_MS=5000 MARCH_HOOK_TIMEOUT_MS=10000
  MARCH_CONTROL_AGENT_GRACE_MS=20000"
run_node() {
  local kv var cur
  if [ "$TIME_SCALE" != 1 ]; then
    for kv in $scaled_deadlines; do
      var=${kv%%=*}
      case " ${TIME_SCALE_EXEMPT:-} " in *" $var "*) continue ;; esac
      cur=${!var:-${kv#*=}}
      [[ $cur =~ ^[0-9]+$ ]] || cur=${kv#*=}
      export "$var=$(( cur * TIME_SCALE ))"
    done
  fi
  exec "$@"
}

# node-b's listen port, chosen BELOW the OS's ephemeral range.
#
# The old 40000-59999 overlapped Linux's default ephemeral range
# (32768-60999), which is where the kernel draws the local port of every
# OUTGOING connection.  A client socket an earlier scenario opened can
# therefore be sitting on exactly the port node-b is about to bind, and
# node-b dies with "panic: listen: tcp_listen: bind failed" having never met
# a competing listener -- the CI flake this range avoids.  Below the
# ephemeral floor a port is only ever taken by something that asked for it by
# number, which start_node retries out of.
ephemeral_floor() {
  if [ -r /proc/sys/net/ipv4/ip_local_port_range ]; then
    awk '{ print $1 }' /proc/sys/net/ipv4/ip_local_port_range
  else
    echo 49152        # the IANA/BSD default, which is what macOS uses
  fi
}
port_lo=20000
port_hi=$(( $(ephemeral_floor) - 1 ))
[ "$port_hi" -gt "$port_lo" ] || { port_lo=10000; port_hi=19999; }
# $$ as well as $RANDOM: two harnesses started in the same second seed $RANDOM
# identically and would otherwise pick the same "random" port as each other.
pick_port() {
  PORT=$(( port_lo + (RANDOM ^ $$) % (port_hi - port_lo + 1) ))
  # node-a's and node-c's own listen ports, next to node-b's and re-derived
  # with it: a three-node scenario needs more than one listener, and every
  # node is told all three so it can pick who it listens for and who it dials.
  PORT_A=$(( PORT + 1 )); [ "$PORT_A" -le "$port_hi" ] || PORT_A=$(( port_lo ))
  PORT_C=$(( PORT_A + 1 )); [ "$PORT_C" -le "$port_hi" ] || PORT_C=$(( port_lo + 1 ))
}
pick_port
port_settled=0                # see start_node: PORT is only movable before
                              # anything has been told which port to use
pid_a=""; pid_b=""; pid_c=""  # bash 3 (macOS): no associative arrays
pid_of() { eval "echo \"\$pid_$1\""; }

link_dropped=0
cleanup() {
  for n in a b c; do p=$(pid_of "$n"); [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
  [ "$link_dropped" = 1 ] && heal
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM HUP PIPE   # a signal death skips the EXIT trap

fail() {
  echo "two-node[$scenario]: $*" >&2
  for n in a b c; do
    [ -f "$work/$n.out" ] && { echo "--- node-$n stdout"; cat "$work/$n.out"; }
    [ -s "$work/$n.err" ] && { echo "--- node-$n stderr"; cat "$work/$n.err"; }
  done >&2
  exit 1
}

need_built() {
  local rel=$1
  [ -x "$root/_build/default/$rel" ] && return 0
  echo "two-node[$scenario]: building $rel" >&2
  (cd "$root" && dune build --root . "$rel") > "$work/need_built.log" 2>&1 \
    || { cat "$work/need_built.log" >&2; fail "could not build $rel"; }
}

compile() {
  local n=$1
  [ -x "$work/node_$n" ] && return
  # Compile a COPY: `march --compile` writes <source>.ll beside the source,
  # and a stray .ll under test/ breaks dune's sandbox copy (Permission denied).
  cp "$dir/node_$n.march" "$work/node_$n.march"
  # COMPILE_FLAGS_<n> (set by the scenario): extra compiler flags for that
  # node, e.g. `--protocol-baseline $work/base/P.json` (build step 9).
  local flags_var="COMPILE_FLAGS_$n"
  # shellcheck disable=SC2086 # the flags are words, split on purpose
  "$MARCH" --compile ${!flags_var:-} -o "$work/node_$n" "$work/node_$n.march" > "$work/compile_$n.log" 2>&1 \
    || { cat "$work/compile_$n.log" >&2; fail "node_$n.march did not compile"; }
}

# Did the node-b just launched die on its bind()?  True only for that: a
# node-b still alive at the end of the grace period bound its port, and one
# that died some other way is the scenario's problem, surfaced by whatever
# wait_line/wait_exit comes next.  Only reached before the port settles, so
# truncating the two logs discards nothing a golden wants.
bind_failed() {
  local i=0
  while [ "$i" -lt 15 ]; do                       # up to ~300 ms
    if ! kill -0 "$pid_b" 2>/dev/null; then
      wait "$pid_b" 2>/dev/null
      grep -qF "bind failed" "$work/b.err" 2>/dev/null || return 1
      : > "$work/b.err"; : > "$work/b.out"
      pid_b=""
      return 0
    fi
    i=$((i + 1)); sleep 0.02
  done
  return 1
}

start_node() {
  local n=$1 creation=${2:-1} m
  # Compile EVERY node of the scenario before the first one runs, not each in
  # its own start_node: once node-a is up, its setup deadline is running
  # (MARCH_SESSION_CONNECT_MS, a heartbeat), and a node-b compiled only now
  # eats that window wherever compiles are slow -- the first scenario on a
  # cold CI runner took >15 s, node-a's accept timed out, and node-b then
  # dialed a closed listener ("Connection refused"), which read as a session
  # bug (cert_direct, 2026-10-02). Every COMPILE_FLAGS_<x> is set before a
  # scenario's first start_node, and compile is once-only, so this changes
  # no node's binary, only when it is built.
  for m in a b c; do [ -f "$dir/node_$m.march" ] && compile "$m"; done
  compile "$n"
  if [ "$n" = b ]; then
    local tries=1
    while :; do
      MARCH_PORT_A=$PORT_A MARCH_PORT_B=$PORT MARCH_PORT_C=$PORT_C \
      MARCH_NODE_PORT=$PORT MARCH_NODE_CREATION=$creation run_node "$work/node_b" >> "$work/b.out" 2>> "$work/b.err" &
      pid_b=$!
      bind_failed || break
      # Something else holds the port.  Before node-b has ever bound and
      # before node-a has been told where to connect, a different port is
      # still free to choose; after that the port IS the scenario (`restart`
      # restarts node-b on the same one), so a collision is a real failure.
      [ "$port_settled" = 0 ] || fail "node-b could not bind port $PORT"
      tries=$((tries + 1))
      [ "$tries" -gt 10 ] && fail "node-b found no free port in 10 attempts (last $PORT)"
      pick_port
    done
  elif [ "$n" = c ]; then
    MARCH_PORT_A=$PORT_A MARCH_PORT_B=$PORT MARCH_PORT_C=$PORT_C run_node "$work/node_c" >> "$work/c.out" 2>> "$work/c.err" &
    pid_c=$!
  else
    MARCH_PORT_A=$PORT_A MARCH_PORT_B=$PORT MARCH_PORT_C=$PORT_C \
    MARCH_PEER_PORT=$PORT run_node "$work/node_a" >> "$work/a.out" 2>> "$work/a.err" &
    pid_a=$!
  fi
  port_settled=1
}

kill_node() { local p; p=$(pid_of "$1"); kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; eval "pid_$1=''"; }
stop_node() { kill -STOP "$(pid_of "$1")"; }
cont_node() { kill -CONT "$(pid_of "$1")"; }

# The iptables invocation for this host, or nothing when a partition cannot be
# applied here (not Linux, no iptables, no root and no passwordless sudo).
iptables_cmd() {
  [ "$(uname -s)" = Linux ] || return 1
  command -v iptables > /dev/null 2>&1 || return 1
  if [ "$(id -u)" = 0 ]; then echo iptables
  elif sudo -n true 2> /dev/null; then echo "sudo -n iptables"
  else return 1
  fi
}

# Both directions on loopback: a packet to the port and one from it. TCP keeps
# the connection (retransmitting) through the drop, so heal delivers what was
# queued -- a partition, not a close.
# `drop_link` with no argument drops node-b's port, the two-node spelling. A
# scenario whose nodes each listen AND dial (the cluster node service: either
# side may redial the other) names every listen port instead, e.g.
# `drop_link "$PORT" "$PORT_A"`, or new connections route around the fault.
dropped_ports=""
drop_link() {
  local ipt p; ipt=$(iptables_cmd) || { echo "two-node[$scenario]: skipped: needs root (Linux iptables) to drop packets" >&2; exit 3; }
  [ $# -gt 0 ] || set -- "$PORT"
  for p in "$@"; do
    $ipt -I INPUT -i lo -p tcp --dport "$p" -j DROP || fail "iptables: could not add the drop rule (dport $p)"
    $ipt -I INPUT -i lo -p tcp --sport "$p" -j DROP || fail "iptables: could not add the drop rule (sport $p)"
  done
  dropped_ports="$dropped_ports $*"
  link_dropped=1
}

heal() {
  local ipt p; ipt=$(iptables_cmd) || return 0
  for p in ${dropped_ports:-$PORT}; do
    $ipt -D INPUT -i lo -p tcp --dport "$p" -j DROP 2> /dev/null
    $ipt -D INPUT -i lo -p tcp --sport "$p" -j DROP 2> /dev/null
  done
  dropped_ports=""
  link_dropped=0
}

wait_line() {
  local n=$1 text=$2 i=0
  until grep -qF -- "$text" "$work/$n.out" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -gt $((TIMEOUT * 10)) ] && fail "timed out waiting for node-$n to print: $text"
    sleep 0.1
  done
}

wait_exit() {
  local n=$1 i=0 p; p=$(pid_of "$n")
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -gt $((TIMEOUT * 10)) ] && fail "timed out waiting for node-$n to exit"
    sleep 0.1
  done
  wait "$p"; local code=$?
  eval "pid_$n=''"
  [ "$code" -eq 0 ] || fail "node-$n exited $code"
}

# shellcheck disable=SC1090
source "$dir/scenario.sh"

status=0
ORDERED=${ORDERED:-0}
for n in a b c; do
  [ -f "$dir/node_$n.expected" ] || continue
  if [ "$ORDERED" = 1 ]; then normalise() { cat "$1"; }; else normalise() { LC_ALL=C sort "$1"; }; fi
  if ! normalise "$work/$n.out" | diff -u "$dir/node_$n.expected" - > "$work/$n.diff"; then
    echo "two-node[$scenario]: node-$n output differs from node_$n.expected:" >&2
    cat "$work/$n.diff" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && { echo "two-node[$scenario]: ok"; rm -rf "$work"; }
exit $status
