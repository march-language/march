# Scenario "control_cert" (dd step 12a): leadership is gated by certificates.
# Every node is in certificate mode. All certificates carry Ctl.Agent:initiate
# so every node can be an Agent; only node b's
# also carries Ctl.Control:offer. Node a is labelled "control" too, so placement
# ranks it as a candidate, but its offer of Ctl.Control is refused
# (SessionAP.authorize): with a alone, nothing leads. Once b joins, b leads, and
# a never does.
source "$root/test/two_node/control_plane/lib.sh"
forge="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
[ -x "$forge" ] || fail "forge not built: $forge (dune build forge/bin/main.exe)"
export PKI="$work/pki"
mkdir -p "$PKI"
"$forge" cluster keygen --out "$PKI" > "$work/pki.log" || fail "forge cluster keygen failed"
issue() {  # <node> <roles>
  "$forge" cluster cert "$1" --roles "$2" --days 1 --trust-domain test.local --pool main \
    --operator-key "$PKI/operator.key" --out "$PKI" >> "$work/pki.log" || fail "cert $1"
}
agent="Ctl.Agent:initiate"
issue a "$agent"
issue b "$agent,Ctl.Control:offer"
issue c "$agent"
ctl_prepare

pa=$(ctl_port a); pb=$(ctl_port b)
ctl_start a control ""
ctl_start c "" "127.0.0.1:$pa"
# a is the only candidate and may not lead: for a good while, nobody does.
sleep 8
[ "$("$HCR" api "$(ctl_api_ep a)" LEADER | head -1)" = "LEADER no a" ] || fail "node a leads without Ctl.Control:offer"
grep -q "Ctl.Control: could not offer" "$work/a.out" || fail "node a did not report that its Ctl.Control offer was refused: $(cat "$work/a.out")"

# b, whose certificate allows it, joins and leads.
ctl_start b control "127.0.0.1:$pa"
leader_is_b() { [ "$(ctl_leader)" = b ]; }
ctl_until 60 "node b to lead" leader_is_b
ctl_until 60 "every node reporting" ctl_all_reporting a b c
sleep 3
[ "$("$HCR" api "$(ctl_api_ep a)" LEADER | head -1)" = "LEADER no a" ] || fail "node a leads"
ctl_no_ssh
ctl_done
