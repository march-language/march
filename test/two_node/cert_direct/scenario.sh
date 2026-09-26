# Scenario "cert_direct" (dd step 11b, SessionNode's direct path): the
# generated `run_<Role>` in certificate mode (MARCH_NODE_CERT set, so
# `ClusterNode.auth_from_env` picks certificates over the secret), and the
# role check on each peer. Roles number A = 1, B = 2: A listens, B dials.
#   Pair    both certificates allow their roles: the session runs.
#   Audit   node-a's certificate lacks Audit.A: node-b, the dialer, refuses
#           it after the handshake, before the session forms.
#   Ledger  node-b's certificate lacks Ledger.B: node-a, the acceptor,
#           refuses it once node-b's hello names the role.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster cert node-a --roles Pair.A:offer,Ledger.A:offer --days 1 \
  --trust-domain test.local --pool p --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-a"
"$forge" cluster cert node-b --roles Pair.B:initiate,Audit.B:initiate --days 1 \
  --trust-domain test.local --pool p --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert node-b"
export PAIR_A_ADDR=127.0.0.1:$PORT_A
export AUDIT_A_ADDR=127.0.0.1:$PORT_C
export LEDGER_A_ADDR=127.0.0.1:$PORT
export MARCH_SESSION_CONNECT_MS=15000

start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
