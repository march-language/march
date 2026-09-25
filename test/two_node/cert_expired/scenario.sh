# Scenario "cert_expired": node-b's certificate is valid for a few seconds
# only. The two link; when it expires node-a's per-tick recheck drops the
# link and reports NodeDead(node-b, "certificate expired"), and node-b's
# redials are refused at the handshake. See node_a.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
export CLUSTER_STOP_FILE="$work/stop"
cert() { "$forge" cluster cert "$@" --trust-domain test.local --pool web >> "$work/pki.log" || fail "forge cluster cert $*"; }

# Compile first: the certificate's short life must not be spent compiling.
compile a
compile b
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen"
cert node-a --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
cert node-b --seconds 8 --operator-key "$PKI/operator.key" --out "$PKI"
start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: linked to node-b"
wait_line b "node-b: linked to node-a"
wait_line a "node-a: node-b dead: certificate expired"
wait_line a "node-a: refused a handshake: certificate expired"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
