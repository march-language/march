# Scenario "cert_update_replay" (security review, dd step 12b): a recorded
# CERT_UPDATE frame cannot be replayed on another link. node-a reaches
# node-b only through node-c, a proxy that records node-b's frames. node-b
# rotates to a certificate for a NEW key (its old key has leaked to node-c)
# and tells node-a over the link (CERT_UPDATE); node-c records that frame
# off the wire (frames are MAC'd, not encrypted). node-b stops. node-c then
# handshakes with node-a AS node-b, with node-b's old certificate and key
# (still valid: the revocation has not reached node-a), and replays the
# recorded frame on its own link. The claims:
#   - node-a refuses the replay: the update's proof covers the handshake
#     transcript of the link it was made for (and a per-link counter), so
#     it is good on node-b's link only. Before the fix node-a took it and
#     held node-b's NEW certificate for node-c's link, so the old
#     certificate's revocation would no longer have dropped it;
#   - node-a takes node-b's real update exactly once.
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI" "$work/old" "$work/new"
export CLUSTER_STOP_FILE="$work/stop" ROTATE_FILE="$work/rotate" B_STOP_FILE="$work/b_stop" GO_FILE="$work/go" REPLAY_FILE="$work/replay"
export OLD_PKI="$work/old" NEW_PKI="$work/new"
cert() { "$forge" cluster cert "$@" --trust-domain test.local --pool web >> "$work/pki.log" || fail "forge cluster cert $*"; }

compile a
compile b
compile c
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen"
cert node-a --roles Replay.Peer:offer --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
cert node-b --roles Replay.Peer:initiate --days 1 --operator-key "$PKI/operator.key" --out "$PKI"
cp "$PKI/node-b.cert" "$PKI/node-b.key" "$work/old/"
# node-b's rotation: a new key, and a certificate for it.
cert node-b --roles Replay.Peer:initiate --days 1 --operator-key "$PKI/operator.key" --out "$work/new"

start_node b
wait_line b "node-b: up"
start_node c
wait_line c "node-c: up"
start_node a
wait_line a "node-a: linked to node-b"

touch "$ROTATE_FILE"
wait_line b "node-b: my certificate replaced"
wait_line a "node-a: node-b's certificate replaced (1)"
wait_line c "node-c: recorded node-b's certificate update"
touch "$B_STOP_FILE"
wait_exit b

touch "$GO_FILE"
# node-c replays only once node-a has installed its link as node-b. It used
# to replay after a fixed one-second sleep, and once under ASan in CI node-a
# never answered that replay. node-a's stderr logs every member and security
# event, so a timeout here shows what node-a saw.
wait_line a "node-a: linked to node-b again (creation 2)"
touch "$REPLAY_FILE"
wait_line c "node-c: replayed it on its own link as node-b"
wait_line a "node-a: refused node-b's certificate update"
sleep 1
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit c
