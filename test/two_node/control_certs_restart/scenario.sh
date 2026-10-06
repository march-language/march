# Scenario "control_certs_restart" (security review, dd step 12b): a node
# that restarts does not take back a certificate a later release replaced.
# Three nodes in certificate mode (a and b control candidates, c a plain
# node). Node c is delivered certificate X (with raw_send), then Y (without:
# the operator narrows c), each through a release. Then c restarts:
#   - its Agent reads its certificate floor back from disk (the newest
#     release it took certificates from), where before the fix that floor
#     lived only in memory and a cert-only release never moved the reload
#     server's persisted head;
#   - X, delivered again, is refused by c itself: it was issued before Y,
#     the certificate c restarted on (`NodeCert.supersedes`), so it halts
#     its release on c and c keeps Y (on its link and in its file);
#   - a normal rotation still works after the restart.
source "$root/test/two_node/control_plane/lib.sh"
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
CC="$root/test/two_node/control_certs"   # its app

# The app, built once (every node runs the same binary), as control_certs.
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

export PKI="$work/pki"
mkdir -p "$PKI" "$work/x" "$work/y" "$work/z"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
agent="Ctl.Agent:initiate"
cert() {  # <node> <roles> <out> [forge cluster cert flags...]
  local n=$1 roles=$2 out=$3; shift 3
  "$forge" cluster cert "$n" --roles "$roles" --trust-domain test.local --pool main --operator-key "$PKI/operator.key" --out "$out" "$@"
}
cert a "$agent,Ctl.Control:offer" "$PKI" --days 1 >> "$work/pki.log" || fail "cert a"
cert b "$agent,Ctl.Control:offer" "$PKI" --days 1 >> "$work/pki.log" || fail "cert b"
cert c "$agent" "$PKI" --days 1 >> "$work/pki.log" || fail "cert c"
serial_of() { sed -n 's/^serial //p' "$1" | tail -1; }

ctl_up
ctl_until 60 "a leader" ctl_leader
ctl_until 60 "every node reporting" ctl_all_reporting a b c
eps="$(ctl_api_ep a),$(ctl_api_ep b)"
deliver=(--deliver "$eps" --deploy-key "$work/keys/sk" --env test)
status_raw() { "$HCR" api "$(ctl_api_ep "$(ctl_leader)")" STATUS; }
presents() { status_raw | grep -q "^NODE $1 .*cert:$2"; }

# ── X, then Y (the operator narrows c) ─────────────────────────────────────
cert c "$agent" "$work/x" --days 1 --flags raw_send --node-key "$PKI/c.key" "${deliver[@]}" \
  > "$work/x.out" 2>&1 || { cat "$work/x.out" >&2; fail "delivering c's certificate X failed"; }
grep -q "complete" "$work/x.out" || fail "the release of X did not complete: $(cat "$work/x.out")"
x_serial=$(serial_of "$work/x.out")
ctl_until 20 "c to present X" presents c "$x_serial"
cert c "$agent" "$work/y" --days 1 --node-key "$PKI/c.key" "${deliver[@]}" \
  > "$work/y.out" 2>&1 || { cat "$work/y.out" >&2; fail "delivering c's certificate Y failed"; }
grep -q "complete" "$work/y.out" || fail "the release of Y did not complete: $(cat "$work/y.out")"
y_serial=$(serial_of "$work/y.out")
ctl_until 20 "c to present Y" presents c "$y_serial"
saved_is_y() { cmp -s "$PKI/c.cert" "$work/y/c.cert"; }
ctl_until 20 "c to save Y to its MARCH_NODE_CERT file" saved_is_y
floor_file="$work/nodes/c/control/cert-floor-c"
floor_saved() { [ -s "$floor_file" ]; }
ctl_until 20 "c to save its certificate floor" floor_saved
floor=$(cat "$floor_file")
[ "$floor" -gt 0 ] 2>/dev/null || fail "c's certificate floor is not a release seq: $(cat "$floor_file")"

# ── c restarts ──────────────────────────────────────────────────────────────
kill_node c
ctl_start c "" "127.0.0.1:$(ctl_port a),127.0.0.1:$(ctl_port b)"
wait_line c "control: certificate releases older than $floor are refused"
ctl_until 60 "c to report again" presents c "$y_serial"

# X again, in a new release: c refuses it, by issue order.
if FOLLOW_S=60 "$HCR" certs "$work/keys" "$eps" "cert:c:$work/x/c.cert" > "$work/replay.out" 2> "$work/replay.err"; then
  fail "c took back its superseded certificate X after a restart: $(cat "$work/replay.out")"
fi
grep -q "HALTED on c: cluster_node: the new certificate: certificate $x_serial was issued before $y_serial, the certificate in use" "$work/replay.err" \
  || fail "the release did not halt on c's refusal of X: $(cat "$work/replay.err")"
presents c "$y_serial" || fail "c no longer presents Y: $(status_raw)"
saved_is_y || fail "c saved the refused certificate X"

# ── a normal rotation after the restart ─────────────────────────────────────
cert c "$agent" "$work/z" --days 1 --node-key "$PKI/c.key" "${deliver[@]}" \
  > "$work/z.out" 2>&1 || { cat "$work/z.out" >&2; fail "delivering c's certificate Z failed"; }
grep -q "complete" "$work/z.out" || fail "the release of Z did not complete: $(cat "$work/z.out")"
z_serial=$(serial_of "$work/z.out")
ctl_until 20 "c to present Z" presents c "$z_serial"
wait_line a "serial $z_serial"
[ "$(cat "$floor_file")" -gt "$floor" ] || fail "c's certificate floor did not advance past $floor: $(cat "$floor_file")"

ctl_no_ssh
ctl_done
