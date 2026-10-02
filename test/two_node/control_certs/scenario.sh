# Scenario "control_certs" (dd step 12b): the control plane delivers
# operator-issued certificates and revocations as items of a release
# (`forge cluster cert|revoke --deliver`). Three nodes in certificate mode,
# a and b control candidates, c a plain node; every node runs the Agent.
#   - Rotation: node b is delivered a certificate that lives 40 s, then a
#     renewal of it, both for the key b holds. b takes each live
#     (ClusterNode.replace_cert), saves it to its MARCH_NODE_CERT file, and
#     its peers take it over their links. Past the short certificate's
#     expiry nobody has seen b die, and b still talks to the leader (it
#     reports the next release's revocation). The short certificate is
#     delivered, not issued at start, so a slow start cannot spend its life.
#   - Refusals, by the node itself: a certificate item for a that names
#     another node (sent raw: forge never writes one), and one for a signed
#     by another operator. Each halts its release on a, and a keeps its
#     certificate.
#   - Revocation: every certificate of node c is revoked through a release;
#     a and b drop c's links ("certificate revoked"), and the release
#     completes without waiting for c, which it cut off.
source "$root/test/two_node/control_plane/lib.sh"
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
CC="$root/test/two_node/control_certs"

# The app, built once (every node runs the same binary): ctl_prepare's
# keys and topology, without the patches (nothing here is hot-deployed).
mkdir -p "$work/keys" "$work/p1" "$work/fakebin" "$work/nodes"
"$HCR" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")
printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.log"\nexit 1\n' "$work" > "$work/fakebin/ssh"
chmod +x "$work/fakebin/ssh"
export PATH="$work/fakebin:$PATH"
cat > "$work/topology.json" <<JSON
{ "version": 1, "env": null, "sources": ["topology.toml"], "roles": [],
  "pools": [ { "name": "main", "start": "CtlApp.start", "serves": [], "serves_all": false, "initiates": null,
               "caps": null, "isolate": false, "public": [], "main": null, "replicas": null, "hosts": [] } ],
  "drain": { "soft_ms": 2000, "hard_ms": 5000 }, "backend": null,
  "control": { "candidates": "control", "port": 7947 } }
JSON
cp "$CC/app.march" "$work/p1/ctl_app.march"
(cd "$work/p1" && "$MARCH" --compile --hot-reload CtlApp --signing-pubkey "$pk" --topology "$work/topology.json" \
   -o "$work/node_a" ctl_app.march) > "$work/compile.log" 2>&1 \
  || { cat "$work/compile.log" >&2; fail "the app did not compile"; }
cp "$work/node_a" "$work/node_b"; cp "$work/node_a" "$work/node_c"
socks=$(mktemp -d /tmp/hs.XXXXXX)

# The PKI, issued after compiling so b's short certificate is not spent on it.
export PKI="$work/pki"
mkdir -p "$PKI" "$work/new" "$work/rogue"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
"$forge" cluster keygen --out "$work/rogue" >> "$work/pki.log" || fail "forge cluster keygen (rogue) failed"
agent="Ctl.Agent:initiate"
cert() {  # <node> <roles> <operator key> <out> [forge cluster cert flags...]
  local n=$1 roles=$2 key=$3 out=$4; shift 4
  "$forge" cluster cert "$n" --roles "$roles" --trust-domain test.local --pool main --operator-key "$key" --out "$out" "$@"
}
cert a "$agent,Ctl.Control:offer" "$PKI/operator.key" "$PKI" --days 1 >> "$work/pki.log" || fail "cert a"
cert b "$agent,Ctl.Control:offer" "$PKI/operator.key" "$PKI" --days 1 >> "$work/pki.log" || fail "cert b"
cert c "$agent" "$PKI/operator.key" "$PKI" --days 1 >> "$work/pki.log" || fail "cert c"
serial_of() { sed -n 's/^serial //p' "$1" | tail -1; }
a_serial=$(sed -n 's/^serial //p' "$work/pki.log" | head -1)

ctl_up
ctl_until 60 "a leader" ctl_leader
ctl_until 60 "every node reporting" ctl_all_reporting a b c
eps="$(ctl_api_ep a),$(ctl_api_ep b)"
deliver=(--deliver "$eps" --deploy-key "$work/keys/sk" --env test)
# The leader's raw STATUS line for a node carries the serial it presents.
status_raw() { "$HCR" api "$(ctl_api_ep "$(ctl_leader)")" STATUS; }
presents() { status_raw | grep -q "^NODE $1 .*cert:$2"; }

# ── rotation ────────────────────────────────────────────────────────────────
# b's short-lived certificate, then its renewal, each for the key b holds.
mkdir -p "$work/short"
cert b "$agent,Ctl.Control:offer" "$PKI/operator.key" "$work/short" --seconds 40 --node-key "$PKI/b.key" "${deliver[@]}" \
  > "$work/short.out" 2>&1 || { cat "$work/short.out" >&2; fail "delivering b's short-lived certificate failed"; }
short_expiry=$(( $(date +%s) + 40 ))
grep -q "complete" "$work/short.out" || fail "the first rotation release did not complete: $(cat "$work/short.out")"
short_serial=$(serial_of "$work/short.out")
presents b "$short_serial" || fail "the leader does not see b present certificate $short_serial: $(status_raw)"
wait_line a "serial $short_serial"
cert b "$agent,Ctl.Control:offer" "$PKI/operator.key" "$work/new" --days 1 --node-key "$PKI/b.key" "${deliver[@]}" \
  > "$work/rotate.out" 2>&1 || { cat "$work/rotate.out" >&2; fail "delivering b's new certificate failed"; }
grep -q "complete" "$work/rotate.out" || fail "the rotation release did not complete: $(cat "$work/rotate.out")"
new_serial=$(serial_of "$work/rotate.out")
[ -n "$new_serial" ] || fail "no serial in: $(cat "$work/rotate.out")"
presents b "$new_serial" || fail "the leader does not see b present certificate $new_serial: $(status_raw)"
wait_line b "serial $new_serial"
wait_line a "serial $new_serial"
wait_line c "serial $new_serial"
# b saved the delivered certificate where it reads it at start.
saved_is_new() { cmp -s "$PKI/b.cert" "$work/new/b.cert"; }
ctl_until 20 "b to save its new certificate to its MARCH_NODE_CERT file" saved_is_new

# ── refusals, by the node ───────────────────────────────────────────────────
# A certificate item for a that names c: the leader passes it on (it checks
# items for shape only, holding no operator key), and a refuses it.
if FOLLOW_S=60 "$HCR" certs "$work/keys" "$eps" "cert:a:$PKI/c.cert" > "$work/other.out" 2> "$work/other.err"; then
  fail "a took a certificate naming another node: $(cat "$work/other.out")"
fi
grep -q "HALTED on a: the certificate for a names spiffe://test.local/pool/main/node/c, not this node" "$work/other.err" \
  || fail "the release did not halt on a's refusal: $(cat "$work/other.err")"
# One for a signed by another operator, for a's own key: a refuses it.
if cert a "$agent,Ctl.Control:offer" "$work/rogue/operator.key" "$work/rogue" --days 1 --node-key "$PKI/a.key" "${deliver[@]}" \
     > "$work/rogue.out" 2>&1; then
  fail "a took a certificate signed by another operator: $(cat "$work/rogue.out")"
fi
grep -q "HALTED on a: cluster_node: the new certificate: certificate not signed by the cluster operator" "$work/rogue.out" \
  || fail "the release did not halt on a's refusal of the rogue certificate: $(cat "$work/rogue.out")"
presents a "$a_serial" || fail "a no longer presents its own certificate $a_serial: $(status_raw)"
cmp -s "$PKI/a.cert" "$work/rogue/a.cert" && fail "a saved the refused certificate"

# ── past b's short-lived certificate's expiry ───────────────────────────────
while [ "$(date +%s)" -le $(( short_expiry + 3 )) ]; do sleep 1; done
for n in a c; do
  grep -q "app $n: b dead" "$work/$n.out" && fail "node $n saw b die: $(grep "b dead" "$work/$n.out")"
done

# ── revocation ──────────────────────────────────────────────────────────────
# Every certificate of c, revoked through a release. b reporting it also
# shows b still talks to the leader past its short certificate's expiry.
"$forge" cluster revoke --node c --trust-domain test.local --pool main --operator-key "$PKI/operator.key" "${deliver[@]}" \
  > "$work/revoke.out" 2>&1 || { cat "$work/revoke.out" >&2; fail "delivering c's revocation failed"; }
grep -q "complete" "$work/revoke.out" || fail "the revocation release did not complete: $(cat "$work/revoke.out")"
wait_line a "app a: c dead: certificate revoked"
wait_line b "app b: c dead: certificate revoked"
grep -q "app a: b dead\|app c: b dead" "$work/a.out" "$work/c.out" && fail "b died"

ctl_no_ssh
ctl_done
