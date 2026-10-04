# Scenario "control_api_auth" (security review of dd step 12, 2026-10-04): the
# control API's write verbs are authenticated and bounded, and a normal
# release still goes through.
#
# The review found (specs/progress/2026-10-04-dd12-security-review.md) that
# any TCP peer could append to a candidate's audit log (AUDIT_COPY) and store
# unbounded bytes in its CAS (CAS_PUT, AUDIT_COPY). Now:
# - AUDIT_COPY and RELEASE_COPY need the cluster handshake (a candidate);
# - CAS_PUT takes only a hash a signed release STAGEd on the same connection
#   names, at most 64 MiB, within a quota of not-yet-adopted uploads, and an
#   upload no stored release adopts is collected after a grace period;
# - bodies are size-checked before they are read, connections are capped and
#   closed when idle, and the audit log is rotated.
# The attacks are hcr_deploy's `probe*` subcommands: a plain socket, no
# cluster credentials (the review's api_probe.py, as a test).
source "$root/test/two_node/control_plane/lib.sh"
ctl_prepare

# Small bounds, so the scenario reaches them: the quota leaves room for the
# real patch (and the topology) but not for two probe uploads of 60% of it.
so_bytes=$(wc -c < "$work/p2/v2.so" | tr -d ' ')
quota=$(( so_bytes * 2 + 100000 ))
export MARCH_CONTROL_CAS_PENDING_MAX_BYTES=$quota MARCH_CONTROL_CAS_GRACE_MS=4000 MARCH_CONTROL_GC_MS=1000
export MARCH_CONTROL_MAX_CONNS=12 MARCH_CONTROL_IDLE_MS=3000 MARCH_CONTROL_AUDIT_MAX_BYTES=600
ctl_up
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "every node reporting" ctl_all_reporting a b c
leader=$(ctl_leader)
standby=$([ "$leader" = a ] && echo b || echo a)

# A normal release: forge stages it, uploads, sends; the leader copies the
# release and its audit lines to the standby over the authenticated verbs.
FORGE_RELEASE_OUT="$work/release.body" ctl_release 1 1500 > "$work/release.out" 2>&1 \
  || { cat "$work/release.out" >&2; fail "the release did not complete"; }
grep -q "complete" "$work/release.out" || fail "the release did not report completion"
status=$(ctl_status)
for n in a b c; do
  echo "$status" | grep "^  $n: " | grep -q "versions [*]=" || fail "node $n does not report the patch: $status"
done
ls "$work/nodes/$standby/control/releases/"*.release > /dev/null 2>&1 \
  || fail "the standby $standby holds no copy of the release (RELEASE_COPY over the handshake)"
# Only a leader audits, so any line in the standby's log is a copy.
copied() { "$HCR" api "$(ctl_api_ep "$standby")" "AUDIT 0" | grep -q '"type":"'; }
ctl_until 20 "the leader's audit lines copied to the standby (AUDIT_COPY over the handshake)" copied
grep -q "refused an unauthenticated write" "$work/$standby.out" "$work/$leader.out" \
  && fail "a candidate refused another candidate's write: $(grep -h "refused an unauthenticated" "$work/a.out" "$work/b.out")"
patch_hash=$(sed -n 's/^uploading the [^ ]* patch (\([0-9a-f]*\)).*/\1/p' "$work/release.out" | head -1)
[ -n "$patch_hash" ] || fail "no patch hash in the release output: $(cat "$work/release.out")"

# The attacks, on each candidate.
for n in a b; do
  "$HCR" probe "$work/keys" "$(ctl_api_ep "$n")" > "$work/probe_$n.out" 2>&1 || fail "probe on $n failed: $(cat "$work/probe_$n.out")"
  p() { sed -n "s/^$1: //p" "$work/probe_$n.out"; }
  case "$(p audit_copy)" in refused*) ;; *) fail "$n: an unauthenticated AUDIT_COPY was taken: $(cat "$work/probe_$n.out")" ;; esac
  [ "$(p audit_forged_present)" = false ] || fail "$n: the forged audit line is in the log"
  case "$(p release_copy)" in refused*) ;; *) fail "$n: an unauthenticated RELEASE_COPY was taken: $(p release_copy)" ;; esac
  case "$(p cas_put_unstaged)" in "refused (ERR not_staged)") ;; *) fail "$n: CAS_PUT with nothing staged: $(p cas_put_unstaged)" ;; esac
  case "$(p stage_unsigned)" in "ERR bad_signature") ;; *) fail "$n: an unsigned release was staged: $(p stage_unsigned)" ;; esac
  case "$(p stage)" in "OK staged 1") ;; *) fail "$n: a signed release was not staged: $(p stage)" ;; esac
  [ "$(p cas_put_other)" = "ERR not_staged" ] || fail "$n: CAS_PUT of a hash the staged release does not name: $(p cas_put_other)"
  [ "$(p cas_put_oversize)" = "ERR bad_size" ] || fail "$n: an artifact over 64 MiB: $(p cas_put_oversize)"
  case "$(p cas_put_staged)" in OK*) ;; *) fail "$n: CAS_PUT of the staged hash: $(p cas_put_staged)" ;; esac
  [ "$(p audit_copy_oversize)" = "ERR bad_size" ] || fail "$n: an AUDIT_COPY over 1 MiB: $(p audit_copy_oversize)"
  [ "$(p release_oversize)" = "ERR bad_size" ] || fail "$n: a RELEASE over 1 MiB: $(p release_oversize)"
  grep -q "refused an unauthenticated write" "$work/$n.out" || fail "$n did not report the refused writes"
  "$HCR" probe-stale "$work/keys" "$(ctl_api_ep "$n")" > "$work/stale_$n.out" 2>&1
  grep -q "^stage_stale: ERR stale_release" "$work/stale_$n.out" || fail "$n: a release older than the head was staged: $(cat "$work/stale_$n.out")"
done

# The quota on uploads no stored release names.
"$HCR" probe-quota "$work/keys" "$(ctl_api_ep a)" $(( quota * 6 / 10 )) > "$work/quota.out" 2>&1
grep -q "^quota_first: OK" "$work/quota.out" || fail "the first upload within the quota was refused: $(cat "$work/quota.out")"
grep -q "^quota_second: ERR cas_quota" "$work/quota.out" || fail "the quota was not enforced: $(cat "$work/quota.out")"

# The probe's staged upload is collected once the grace period is over (no
# release adopted it); the deployed patch, which a stored release names, stays.
staged=$(sed -n 's/^staged_hash: //p' "$work/probe_a.out")
missing() { "$HCR" api "$(ctl_api_ep a)" "CAS_CHECK $staged" | grep -q MISSING; }
ctl_until 30 "the unadopted upload collected" missing
grep -q "removed artifact ${staged:0:12}" "$work/a.out" || fail "node a did not report removing the upload"
for n in a b; do
  "$HCR" api "$(ctl_api_ep "$n")" "CAS_CHECK $patch_hash" | grep -q PRESENT || fail "$n: the deployed patch was collected"
done
# ...and the quota has room again.
"$HCR" probe-quota "$work/keys" "$(ctl_api_ep a)" 1000 > "$work/quota2.out" 2>&1
grep -q "^quota_first: OK" "$work/quota2.out" || fail "the quota did not free up after collection: $(cat "$work/quota2.out")"

# Connections: at most 12 at once, and an idle one is closed.
"$HCR" probe-conns "$(ctl_api_ep a)" 20 > "$work/conns.out" 2>&1
busy=$(sed -n 's/^busy: //p' "$work/conns.out")
[ "${busy:-0}" -ge 1 ] || fail "20 connections at once were all served: $(cat "$work/conns.out")"
grep -q "^idle_closed: \([0-9]*\) of \1$" "$work/conns.out" || fail "idle connections were not closed: $(cat "$work/conns.out")"
"$HCR" api "$(ctl_api_ep a)" LEADER | grep -q "^LEADER" || fail "the API does not answer after the connection test"

# The audit log is bounded: rotated past MARCH_CONTROL_AUDIT_MAX_BYTES.
la="$work/nodes/$leader/control/audit.jsonl"
[ -f "$la.1" ] || fail "the leader's audit log was never rotated ($(wc -c < "$la") bytes)"
[ "$(wc -c < "$la")" -le 600 ] || fail "the leader's audit log is over its bound: $(wc -c < "$la") bytes"

ctl_no_ssh
ctl_done
