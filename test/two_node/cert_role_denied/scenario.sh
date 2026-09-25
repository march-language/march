# Scenario "cert_role_denied" (dd step 11b, the two-way role check): both
# nodes in certificate mode. node-b's certificate names only
# Thumbs.Render:offer. Its own `offer_Ledger` refuses to open; it then binds
# the Checkout.Ledger offer name itself (what a compromised node could do:
# offer names are registry names any member can write), and node-a, which
# may initiate both protocols, skips that offer without inviting it. The
# Thumbs session, which node-b's certificate does allow, forms. See
# node_a.march and node_b.march.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster cert node-a --roles Checkout.Client:initiate,Thumbs.Client:initiate --days 1 \
  --trust-domain test.local --pool web --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-a"
"$forge" cluster cert node-b --roles Thumbs.Render:offer --days 1 \
  --trust-domain test.local --pool thumbs --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-b"
export CLUSTER_STOP_FILE="$work/stop"

start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: Thumbs session got 50"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
