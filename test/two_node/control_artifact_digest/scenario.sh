# Scenario "control_artifact_digest" (review 2026-10-04, dd12 P1: a signed
# activation loaded unverified artifact bytes). A release (v1 -> v2) goes
# through the control plane as forge sends it, so every node holds v2's
# operator-signed ACTIVATE7 line in its persisted patch stack. Then, through
# the node's reload socket (the control API's CAS_PUT now takes only hashes a
# release staged on the same connection names -- ERR not_staged -- so the
# writer left is a local user who can open the socket), the attacker replaces
# v2's bytes in that node's CAS with
# another patch of the same build -- identity markers and all -- whose
# `Ver.version` is 666, and the node restarts. The signed line still
# verifies; the bytes do not hash to its signed so_blake3, so the node does
# not replay it: it comes back on its base build, never on the attacker's code.
# Along the way: a CAS_PUT that names the signed digest refuses other bytes,
# and CAS_CHECK with the digest tells the substituted artifact from the real
# one (so forge uploads it again).
source "$root/test/two_node/control_plane/lib.sh"
ctl_prepare

# The attacker's patch: the same build, another body.
mkdir -p "$work/p3"
sed 's/fn version() : Int do 2 end/fn version() : Int do 666 end/' "$CP/app_v2.march" > "$work/p3/ctl_app.march"
grep -q "do 666 end" "$work/p3/ctl_app.march" || fail "could not make the attacker's source"
(cd "$work/p3" && "$MARCH" --compile --compile-so --hot-reload CtlApp --signing-pubkey "$pk" \
   --topology "$work/topology.json" -o "$work/p3/v3.so" ctl_app.march) > "$work/patch3.log" 2>&1 \
  || { cat "$work/patch3.log" >&2; fail "the attacker's patch did not build"; }

ctl_up
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "every node reporting" ctl_all_reporting a b c
ctl_release 1 1500 > "$work/release.out" 2>&1 || { cat "$work/release.out" >&2; fail "the release did not complete"; }
grep -q "complete" "$work/release.out" || fail "the release did not report completion"

art=$("$HCR" reload "$(ctl_sock a)" NODE_STATE | sed -n 's/^ARTIFACT //p' | head -1)
[ -n "$art" ] || fail "node a reports no patch artifact: $("$HCR" reload "$(ctl_sock a)" NODE_STATE)"
good=$("$HCR" digest "$work/p2/v2.so")
api=$(ctl_api_ep a)

r=$("$HCR" api "$api" "CAS_CHECK $art so_blake3:$good")
[ "$r" = PRESENT ] || fail "node a does not hold the signed bytes of $art: $r"

# A CAS_PUT that names the signed digest refuses other bytes.
r=$("$HCR" reload-put "$(ctl_sock a)" "$art" "$work/p3/v3.so" "$good")
[ "$r" = "ERR digest_mismatch" ] || fail "a digested CAS_PUT of other bytes was not refused: $r"

# The control API no longer takes an unstaged upload at all.
r=$("$HCR" api-put "$api" "$art" "$work/p3/v3.so")
[ "$r" = "ERR not_staged" ] || fail "the control API took an unstaged CAS_PUT: $r"

# Without a digest the reload socket stores whatever it is sent: the
# attacker's bytes are now node a's copy of v2.
r=$("$HCR" reload-put "$(ctl_sock a)" "$art" "$work/p3/v3.so")
case "$r" in OK*) ;; *) fail "the substitution did not reach the CAS: $r" ;; esac
r=$("$HCR" api "$api" "CAS_CHECK $art so_blake3:$good")
[ "$r" = MISSING ] || fail "CAS_CHECK with the signed digest did not see the substitution: $r"

# Node a restarts: its signed stack entry is replayed only if the bytes are
# the signed ones.
kill_node a
ctl_start a control "127.0.0.1:$(ctl_port b)"
ctl_until 40 "node a's reload server" "$HCR" reload "$(ctl_sock a)" PING
detail=$("$HCR" reload "$(ctl_sock a)" VERSIONS_DETAIL)
echo "$detail" | grep -q "^RESTORED entries:0 skipped:1 mode:replayed " \
  || fail "node a replayed the substituted artifact, or skipped something else: $(echo "$detail" | grep RESTORED)"
grep -q '"result":"err_restore_digest"' "$work/nodes/a/home/.local/share/march/audit.jsonl" \
  || fail "node a's audit log has no err_restore_digest line"

# Its pool starts again (it prints the version it runs once, at start), on
# the base build: the attacker's code never runs.
ctl_until 40 "node a's pool to start again" sh -c "[ \$(grep -c 'app: version' '$work/a.out') -ge 2 ]"
grep -q "app: version 666" "$work/a.out" && fail "node a ran the attacker's code: $(cat "$work/a.out")"
[ "$(grep 'app: version' "$work/a.out" | tail -1)" = "app: version 1" ] \
  || fail "node a did not come back on its base build: $(cat "$work/a.out")"
ctl_no_ssh
ctl_done
