# Scenario "cert_initiate_denied" (dd step 11b, the offer's half of the
# two-way role check): both nodes in certificate mode. node-b's certificate
# names Checkout.Ledger:offer and it offers the role; node-a's names only
# Thumbs.Client:initiate, so node-b's offer refuses node-a's invitation to a
# Checkout session ("initiator node-a not authorized for Checkout.Client")
# and node-a's initiate ends in NoOffer with that reason.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster cert node-a --roles Thumbs.Client:initiate --days 1 \
  --trust-domain test.local --pool web --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-a"
"$forge" cluster cert node-b --roles Checkout.Ledger:offer --days 1 \
  --trust-domain test.local --pool ledger --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-b"
export CLUSTER_STOP_FILE="$work/stop"

start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: Checkout:"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
