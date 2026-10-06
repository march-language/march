# Scenario "cert_order": the multi-host lab's Order protocol and certificate
# layout on three nodes, in certificate mode. Shop is initiated on node-a;
# Stock is offered on node-b AND node-c; Ledger is hosted in an actor on
# node-c only. Each work node's certificate names both work roles and
# node-a's names Shop:initiate, as `forge host init` issues them. In the lab
# (specs/todos/2026-10-05-lab-cert-mode-offer-to-offer-session-hangs.md)
# every session whose Stock ran on another node than the Ledger stalled after
# its first message; here those are the sessions whose Stock lands on node-b.
# node-a's twelve sessions (three rounds of four at once) must all finish.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
cert() {
  "$forge" cluster cert "$1" --roles "$2" --days 1 --trust-domain test.local --pool "$3" \
    --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert $1"
}
cert node-a Order.Shop:initiate ingress
cert node-b Order.Stock:offer,Order.Ledger:offer work
cert node-c Order.Stock:offer,Order.Ledger:offer work

compile a
compile b
compile c

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: offering"
start_node c
wait_line c "node-c: offering"
wait_exit a
# Non-vacuous only if some session put Stock on node-b, away from the Ledger.
b_sessions=$(grep -c "stock: a session on node-b" "$work/b.out")
[ "$b_sessions" -gt 0 ] || fail "no session put Stock on node-b: the cross-node Stock -> Ledger edge never ran"
echo "two-node[cert_order]: $b_sessions of 12 sessions ran Stock on node-b"
kill_node b
kill_node c
