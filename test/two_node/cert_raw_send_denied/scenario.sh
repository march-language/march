# Scenario "cert_raw_send_denied" (dd step 11b, raw-send denial): both nodes
# in certificate mode. node-a's certificate carries raw_send; node-b's does
# not (it stands in for an isolated IO.Foreign pool). node-b cannot raw-send
# into node-a's pool, node-a cannot raw-send to node-b, and when node-b
# skips its own check (a compromised node, writing through the session
# queue) node-a drops every non-exempt frame kind, counts it and answers
# DELIVERY_FAILED; session traffic to a session route still arrives. node-b
# also checks Node.send's and RemoteCall's paths on a direct certificate-mode
# connection it opens to itself. See node_a.march and node_b.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster cert node-a --roles Probe.A:initiate --flags raw_send --days 1 \
  --trust-domain test.local --pool web --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-a"
"$forge" cluster cert node-b --roles Probe.B:offer --days 1 \
  --trust-domain test.local --pool foreign --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-b"
export CLUSTER_STOP_FILE="$work/stop"
export PIDS_FILE="$work/pids"

start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: probes sent"
wait_line a "node-a: session route got SessionNode.Ping#probe"
wait_line b "node-b: direct connection checked"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
