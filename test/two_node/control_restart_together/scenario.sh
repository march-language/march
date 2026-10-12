# Scenario "control_restart_together": nodes of a `[control]` topology app
# started together, and then restarted together, keep a bounded heap
# (specs/progress/2026-10-05-lab-simultaneous-restart-memory-burst.md).
#
# The multi-host lab's app (examples/lab_app: an ingress pool initiating Shop
# sessions, a work pool offering Stock everywhere and Ledger on one "books"
# node, the control plane on the "control" nodes) on three nodes: a is the
# ingress, b and c are work nodes labelled control,books. Every node writes
# its live heap objects (`live_allocs()`) to $HOME/lab-probe (every second
# here; 5 s in the lab). The ingress starts one session a second.
#
#   1. a, b and c start at the same moment, each seeded with all three;
#   2. once sessions finish, every node is stopped (SIGTERM, as systemctl
#      does) and all three start again at the same moment, on the state the
#      first run left (its control dir and hot-reload state);
#
# and in both runs, for BURST_SECS (default 30) after sessions flow, no
# node's live heap may pass BURST_LIMIT objects (default 400,000).
#
# What it guards: in the lab (2026-10-05) nodes started together allocated
# 8-30 million objects (0.5-1.5 GB) within 30-75 s and were OOM-killed. The
# cause was a leak per cluster message: every decoded frame (`Msgpack.Value`,
# a type whose short name collides with other stdlib types) was freed
# shallowly, orphaning its payload's byte list (fixed 2026-10-05 in
# lib/tir/drop.ml, specs/progress/2026-10-05-colliding-type-shallow-drop.md).
# Nodes meeting each other at once exchange the most traffic (registry and
# membership syncs between new incarnations, the count = 1 Ledger and
# Ctl.Control settling, sessions refused and retried while they do), so a
# simultaneous start is where such a leak shows first. A node passing 1.5 GB
# of RSS fails the scenario at once, before it can take the machine with it.
source "$root/test/two_node/control_plane/lib.sh"
FORGE="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
need_built forge/bin/main.exe
limit=${BURST_LIMIT:-400000}
secs=${BURST_SECS:-30}

proj="$work/proj"
mkdir -p "$proj/src" "$work/keys" "$work/fakebin" "$work/nodes" "$work/home"
printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.log"\nexit 1\n' "$work" > "$work/fakebin/ssh"
chmod +x "$work/fakebin/ssh"
export PATH="$work/fakebin:$PATH"

app="$root/examples/lab_app"
# The probe every second rather than every 5 s.
sed 's/sleep_ms(5000)/sleep_ms(1000)/' "$app/src/lab_app.march" > "$proj/src/lab_app.march"
grep -q 'sleep_ms(1000)' "$proj/src/lab_app.march" || fail "could not speed up the lab app's probe"
cp "$app/forge.toml" "$app/topology.toml" "$proj/"
(cd "$proj" && HOME="$work/home" "$FORGE" topology check) > "$work/check.log" 2>&1 \
  || { cat "$work/check.log" >&2; fail "topology check failed"; }
digest="$proj/.forge/topology.json"

"$HCR" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")
(cd "$proj/src" && HOME="$work/home" "$MARCH" --compile --hot-reload LabApp --signing-pubkey "$pk" --topology "$digest" \
   -o "$work/node_a" lab_app.march) > "$work/compile.log" 2>&1 \
  || { cat "$work/compile.log" >&2; fail "the lab app did not compile"; }
cp "$work/node_a" "$work/node_b"; cp "$work/node_a" "$work/node_c"
socks=$(mktemp -d /tmp/hs.XXXXXX)

all="127.0.0.1:$(ctl_port a),127.0.0.1:$(ctl_port b),127.0.0.1:$(ctl_port c)"
rt_start() {
  local n=$1 pool=$2 labels=$3 d="$work/nodes/$1"
  mkdir -p "$d/home"
  rm -f "$d/home/lab-probe"
  (
    export MARCH_NODE_NAME=$pool-$n MARCH_NODE_PORT=$(ctl_port "$n") MARCH_NODE_LABELS=$labels MARCH_CLUSTER_NODES=$all
    export MARCH_CLUSTER_SECRET=ctl MARCH_POOLS=$pool MARCH_NODE_CREATION=$creation
    export MARCH_TOPOLOGY_FILE="$digest" MARCH_TOPOLOGY_STATUS="$d/status"
    export MARCH_HOT_RELOAD_SOCKET="$(ctl_sock "$n")" MARCH_CONTROL_DIR="$d/control"
    export MARCH_CONTROL_PORT_OFFSET=1000
    export HOME="$d/home"
    run_node "$work/node_$n"
  ) >> "$work/$n.out" 2>> "$work/$n.err" &
  eval "pid_$n=$!"
}
start_all() {
  rt_start a ingress ""
  rt_start b work control,books
  rt_start c work control,books
}
# One session a second, at most 4 at once (the lab's default).
mkdir -p "$work/nodes/a/home" && echo "1000 4" > "$work/nodes/a/home/lab-traffic"

live() { sed -n 's/^live //p' "$work/nodes/$1/home/lab-probe" 2> /dev/null; }
rss_kb() { ps -o rss= -p "$(pid_of "$1")" 2> /dev/null | tr -d ' '; }
finished() { awk '$1 == "finished" { print $2; f = 1 } END { if (!f) print 0 }' "$work/nodes/a/home/lab-stats" 2> /dev/null; }

# watch <run> <seconds>: sample every node every second; fail on a heap past
# the limit, a node past 1.5 GB of RSS, or a node that died.
watch() {
  local run=$1 i=0 n v r
  while [ "$i" -lt "$2" ]; do
    sleep 1; i=$((i + 1))
    for n in a b c; do
      kill -0 "$(pid_of "$n")" 2> /dev/null || fail "$run: node-$n died"
      v=$(live "$n"); r=$(rss_kb "$n")
      echo "$run t=$i $n live=${v:--} rss_kb=${r:--}" >> "$work/samples"
      [ -n "$r" ] && [ "$r" -gt 1572864 ] && fail "$run: node-$n reached $((r / 1024)) MB of RSS ($v live objects) $i s in"
      [ -n "$v" ] && [ "$v" -gt "$limit" ] && fail "$run: node-$n holds $v live heap objects $i s in (limit $limit); samples: $(tail -9 "$work/samples")"
      eval "peak_$n=\$(( \${peak_$n:-0} > ${v:-0} ? \${peak_$n:-0} : ${v:-0} ))"
    done
  done
}

# sessions_flow <run> <at least>: the ingress has finished that many sessions.
sessions_flow() {
  local want=$2
  ctl_until 90 "$1: $want sessions finished (stats: $(cat "$work/nodes/a/home/lab-stats" 2> /dev/null | tr '\n' ' '))" \
    sh -c "[ \"\$(awk '\$1 == \"finished\" { print \$2 }' '$work/nodes/a/home/lab-stats' 2> /dev/null)\" -ge $want ]"
}

# 1. All three at once.
creation=1
start_all
sessions_flow "first start" 3
watch "first start" "$secs"
first=$(finished)
echo "first start: peak live objects a=$peak_a b=$peak_b c=$peak_c; $first sessions finished" >&2

# 2. Stop all three (SIGTERM, a drain), then all three at once again.
for n in a b c; do kill -TERM "$(pid_of "$n")" 2> /dev/null; done
for n in a b c; do
  p=$(pid_of "$n"); i=0
  while kill -0 "$p" 2> /dev/null; do
    i=$((i + 1)); [ "$i" -gt 300 ] && fail "node-$n did not stop on SIGTERM within 30 s"
    sleep 0.1
  done
  wait "$p" 2> /dev/null; eval "pid_$n=''"
done
rm -f "$work/nodes/a/home/lab-stats"
peak_a=0; peak_b=0; peak_c=0
creation=2
start_all
sessions_flow "restart" 3
watch "restart" "$secs"
echo "restart: peak live objects a=$peak_a b=$peak_b c=$peak_c; $(finished) sessions finished" >&2
[ -n "${BURST_KEEP:-}" ] && cp "$work/samples" "$BURST_KEEP"

ctl_no_ssh
ctl_done
