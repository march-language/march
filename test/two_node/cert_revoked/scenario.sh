# Scenario "cert_revoked": after the two link, node-a is handed a revocation
# of node-b's certificate (`forge cluster revoke --serial`); it drops the
# link, reports NodeDead(node-b, "certificate revoked") and refuses node-b's
# handshakes. See node_a.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
export CLUSTER_STOP_FILE="$work/stop"
cert() { "$forge" cluster cert "$@" --trust-domain test.local --pool web >> "$work/pki.log" || fail "forge cluster cert $*"; }

export REVOKE_TOKEN_FILE="$work/revoke.token"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen"
cert node-a --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
cert node-b --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
serial=$(awk '/^node .*node-b$/ { want = 1 } want && /^serial / { print $2; exit }' "$work/pki.log")
[ -n "$serial" ] || fail "no serial for node-b in $work/pki.log"
start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: linked to node-b"
wait_line b "node-b: linked to node-a"
"$forge" cluster revoke --serial "$serial" --operator-key "$PKI/operator.key" > "$work/revoke.tmp" || fail "forge cluster revoke"
mv "$work/revoke.tmp" "$REVOKE_TOKEN_FILE"
wait_line a "node-a: node-b dead: certificate revoked"
wait_line a "node-a: refused a handshake: certificate revoked"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
