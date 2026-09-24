# Scenario "cert_wrong_operator": node-a's certificate is from one operator
# key, node-b's from another, and each node trusts only its own operator.
# Each refuses the other's certificate at the handshake; they never link.
# See node_a.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
export CLUSTER_STOP_FILE="$work/stop"
cert() { "$forge" cluster cert "$@" --trust-domain test.local --pool web >> "$work/pki.log" || fail "forge cluster cert $*"; }

mkdir -p "$PKI/op1" "$PKI/op2"
"$forge" cluster keygen --out "$PKI/op1" > "$work/pki.log" || fail "forge cluster keygen (op1)"
"$forge" cluster keygen --out "$PKI/op2" >> "$work/pki.log" || fail "forge cluster keygen (op2)"
cert node-a --days 1 --operator-key "$PKI/op1/operator.key" --out "$PKI"
cert node-b --days 1 --operator-key "$PKI/op2/operator.key" --out "$PKI"
start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: refused a handshake: certificate not signed by the cluster operator"
wait_line b "node-b: refused a handshake: certificate not signed by the cluster operator"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
