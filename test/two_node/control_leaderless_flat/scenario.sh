# Scenario "control_leaderless_flat": a cluster with no control-plane leader
# must not grow. Three nodes of a topology app with a [control] section and no
# node carrying its candidate label, so no Ctl.Control is ever offered: every
# node's Agent retries for ever, and SWIM and the registry keep exchanging
# frames. Each node counts its live heap objects over a 30 s window
# (app.march) and must stay under 100.
#
# Before the fix every node grew by ~50 objects a second here (and ~13k a
# second per node in the multi-host lab): ClusterNode's CtlFrame handler leaked
# its whole old CnState on every frame (Perceus's aggregate scope-end drop
# gave up on a scope that released the state on ONE path), and every sealed
# frame leaked its MAC input (hmac_sha256_bytes reached as an indirect call).
# specs/progress/2026-10-05-lab-leaderless-agents-leak.md
source "$root/test/two_node/control_plane/lib.sh"

mkdir -p "$work/keys" "$work/p1" "$work/nodes"
"$HCR" keygen "$work/keys" || fail "keygen failed"
cat > "$work/topology.json" <<JSON
{ "version": 1, "env": null, "sources": ["topology.toml"], "roles": [],
  "pools": [ { "name": "main", "start": "LeakApp.start", "serves": [], "serves_all": false, "initiates": null,
               "caps": null, "isolate": false, "public": [], "main": null, "replicas": null, "hosts": [] } ],
  "drain": { "soft_ms": 2000, "hard_ms": 5000 }, "backend": null,
  "control": { "candidates": "control", "port": 7947 } }
JSON
cp "$root/test/two_node/control_leaderless_flat/app.march" "$work/p1/leak_app.march"
(cd "$work/p1" && "$MARCH" --compile --hot-reload LeakApp --signing-pubkey "$(cat "$work/keys/pk")" \
   --topology "$work/topology.json" -o "$work/node_a" leak_app.march) > "$work/compile.log" 2>&1 \
  || { cat "$work/compile.log" >&2; fail "the app did not compile"; }
cp "$work/node_a" "$work/node_b"; cp "$work/node_a" "$work/node_c"
socks=$(mktemp -d /tmp/hs.XXXXXX)

# No node carries the label "control": there is no candidate, so no leader.
pa=$(ctl_port a)
ctl_start a "" ""
sleep 1
ctl_start b "" "127.0.0.1:$pa"
ctl_start c "" "127.0.0.1:$pa"

measured() { local n; for n in a b c; do grep -q "^probe: grew" "$work/$n.out" || return 1; done; }
ctl_until 90 "every node's measurement" measured

for n in a b c; do
  grep -q "control: no session with a leader" "$work/$n.out" || fail "node $n found a leader; the scenario needs none"
  grew=$(sed -n 's/^probe: grew \(-*[0-9]*\) objects.*/\1/p' "$work/$n.out")
  [ -n "$grew" ] || fail "node $n printed no measurement"
  echo "two-node[$scenario]: node $n grew by $grew live objects in 30 s" >&2
  [ "$grew" -lt 100 ] || fail "node $n grew by $grew live objects in 30 s with no leader"
done

ctl_done
