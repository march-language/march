# Scenario "cert_rotate": live certificate replacement (distributed-deploys
# step 12b, `ClusterNode.replace_cert`). node-b starts with a certificate
# that expires 20 s after it is issued. While a session with node-a runs,
# the operator issues node-b a new certificate for a NEW key, and the files
# node-b was started from are replaced. node-b's ticker sees them change and
# replaces its certificate without a restart; node-a takes the new one over
# the existing link (CERT_UPDATE, proved by the new key). The claims:
#   - node-b keeps talking: the session that was running before the
#     rotation is still running after the OLD certificate's expiry, and
#     node-a never reports node-b dead (a redialled link would have
#     cancelled the session);
#   - an expired old certificate no longer admits: node-c, presenting
#     node-b's old certificate and key, is refused by node-a.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI" "$work/old" "$work/new"
export CLUSTER_STOP_FILE="$work/stop"
export OLD_PKI="$work/old"
export MARCH_NODE_CERT_POLL_MS=200
cert() { "$forge" cluster cert "$@" --trust-domain test.local --pool web >> "$work/pki.log" || fail "forge cluster cert $*"; }

# Compile first: the old certificate's short life must not be spent compiling.
compile a
compile b
compile c
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen"
cert node-a --roles Order.Shop:offer --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
cert node-b --roles Order.Buyer:initiate --seconds 20 --operator-key "$PKI/operator.key" --out "$PKI"
old_expiry=$(( $(date +%s) + 20 ))
cp "$PKI/node-b.cert" "$PKI/node-b.key" "$work/old/"

start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: linked to node-b"
wait_line b "node-b: session running"

# The rotation: a new key and a certificate for it, moved into place (key
# first; node-b refuses the pair until the certificate names the key).
cert node-b --roles Order.Buyer:initiate --days 1 --operator-key "$PKI/operator.key" --out "$work/new"
mv "$work/new/node-b.key" "$PKI/node-b.key"
mv "$work/new/node-b.cert" "$PKI/node-b.cert"
wait_line b "node-b: my certificate replaced"
wait_line a "node-a: node-b's certificate replaced"

# Past the old certificate's expiry the session still runs.
while [ "$(date +%s)" -le $(( old_expiry + 1 )) ]; do sleep 1; done
wait_line a "node-a: session still running after node-b's old certificate expired"

# The old certificate no longer admits anyone.
start_node c
wait_line c "node-c: up"
wait_line a "node-a: refused a handshake: certificate expired"

touch "$CLUSTER_STOP_FILE"
wait_line b "node-b: session finished"
wait_exit a
wait_exit b
wait_exit c
