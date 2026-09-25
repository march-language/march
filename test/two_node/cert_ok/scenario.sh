# Scenario "cert_ok": both nodes in certificate mode with certificates from
# one operator key; they link, see each other's certificates, and carry
# actor messages over the sealed data connection. See node_b.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster cert node-a --roles CertOk.A:initiate --flags raw_send --days 1 \
  --trust-domain test.local --pool web --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-a"
# node-b carries raw_send too: node-a's pings are raw sends, and since step
# 11b a raw send crosses a link only when both certificates carry the flag.
"$forge" cluster cert node-b --roles CertOk.B:offer --flags raw_send --days 1 \
  --trust-domain test.local --pool web --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-b"
export CLUSTER_STOP_FILE="$work/stop"

start_node b
wait_line b "node-b: up"
start_node a
wait_line b "node-b: got 10 pings"
wait_line a "node-a: node-b presents"
wait_line b "node-b: node-a presents"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
