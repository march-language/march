#!/usr/bin/env bash
# Two-node failure-semantics harness: two compiled March programs as two OS
# processes, a fault script applied from outside, per-node sorted goldens.
#
#   scripts/two-node.sh <scenario>          # test/two_node/<scenario>/
#   scripts/two-node.sh --list
#
# A scenario directory holds node_a.march / node_b.march, node_a.expected /
# node_b.expected (each node's stdout, sorted; a node started twice appends),
# and scenario.sh, the fault script, sourced with these helpers in scope:
#
#   start_node <a|b> [creation]   compile-once, start node-<x> in the background
#                                 (node-b gets MARCH_NODE_PORT/MARCH_NODE_CREATION,
#                                 node-a gets MARCH_PEER_PORT)
#   kill_node <a|b>               SIGKILL it (a crash, distinct from a close)
#   stop_node / cont_node <a|b>   SIGSTOP / SIGCONT (a stall, distinct from a crash)
#   drop_link / heal              drop every TCP packet to or from the scenario
#                                 port (a partition: nothing is refused, nothing
#                                 arrives) / remove the rule. Linux iptables, as
#                                 root or via passwordless sudo; anywhere else the
#                                 scenario exits 3, "skipped: needs root", which
#                                 CI's loop treats as a failure and a local run
#                                 reads as a skip. Rules are removed on exit.
#   wait_line <a|b> <text>        block until the node's stdout contains <text>
#   wait_exit <a|b>               block until the node's process exits
#   ORDERED=1                     (set by the scenario) diff each node's stdout
#                                 unsorted: only for a node that prints from one
#                                 actor, whose order is then the protocol's
#
# Every wait has a deadline (TWO_NODE_TIMEOUT, default 60 s) and fails loudly
# with both nodes' output. Why two processes and not two green threads: see
# specs/progress/2026-09-14-two-node-failure-semantics-harness.md.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
MARCH=${MARCH_BIN:-$root/_build/default/bin/main.exe}
TIMEOUT=${TWO_NODE_TIMEOUT:-60}

if [ "${1:-}" = "--list" ]; then ls "$root/test/two_node"; exit 0; fi
scenario=${1:?usage: scripts/two-node.sh <scenario> | --list}
dir=$root/test/two_node/$scenario
[ -f "$dir/scenario.sh" ] || { echo "two-node: no such scenario: $scenario" >&2; exit 2; }
[ -x "$MARCH" ] || { echo "two-node: compiler not built: $MARCH" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/two-node-$scenario.XXXXXX")

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
pick_port() { PORT=$(( port_lo + (RANDOM ^ $$) % (port_hi - port_lo + 1) )); }
pick_port
port_settled=0                # see start_node: PORT is only movable before
                              # anything has been told which port to use
pid_a=""; pid_b=""            # bash 3 (macOS): no associative arrays
pid_of() { eval "echo \"\$pid_$1\""; }

link_dropped=0
cleanup() {
  for n in a b; do p=$(pid_of "$n"); [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
  [ "$link_dropped" = 1 ] && heal
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM HUP PIPE   # a signal death skips the EXIT trap

fail() {
  echo "two-node[$scenario]: $*" >&2
  for n in a b; do
    [ -f "$work/$n.out" ] && { echo "--- node-$n stdout"; cat "$work/$n.out"; }
    [ -s "$work/$n.err" ] && { echo "--- node-$n stderr"; cat "$work/$n.err"; }
  done >&2
  exit 1
}

compile() {
  local n=$1
  [ -x "$work/node_$n" ] && return
  # Compile a COPY: `march --compile` writes <source>.ll beside the source,
  # and a stray .ll under test/ breaks dune's sandbox copy (Permission denied).
  cp "$dir/node_$n.march" "$work/node_$n.march"
  "$MARCH" --compile -o "$work/node_$n" "$work/node_$n.march" > "$work/compile_$n.log" 2>&1 \
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
  local n=$1 creation=${2:-1}
  compile "$n"
  if [ "$n" = b ]; then
    local tries=1
    while :; do
      MARCH_NODE_PORT=$PORT MARCH_NODE_CREATION=$creation "$work/node_b" >> "$work/b.out" 2>> "$work/b.err" &
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
  else
    MARCH_PEER_PORT=$PORT "$work/node_a" >> "$work/a.out" 2>> "$work/a.err" &
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
drop_link() {
  local ipt; ipt=$(iptables_cmd) || { echo "two-node[$scenario]: skipped: needs root (Linux iptables) to drop packets" >&2; exit 3; }
  $ipt -I INPUT -i lo -p tcp --dport "$PORT" -j DROP || fail "iptables: could not add the drop rule (dport)"
  $ipt -I INPUT -i lo -p tcp --sport "$PORT" -j DROP || fail "iptables: could not add the drop rule (sport)"
  link_dropped=1
}

heal() {
  local ipt; ipt=$(iptables_cmd) || return 0
  $ipt -D INPUT -i lo -p tcp --dport "$PORT" -j DROP 2> /dev/null
  $ipt -D INPUT -i lo -p tcp --sport "$PORT" -j DROP 2> /dev/null
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
for n in a b; do
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
