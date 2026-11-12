#!/usr/bin/env bash
# release-gate.sh: is this commit green on main?
#
#   scripts/release-gate.sh SHA|REF          exit 0 only if SHA is on main and
#                                            every gating workflow (ci.yml,
#                                            doc-lint.yml) has a verdict of
#                                            `success` for it
#   scripts/release-gate.sh --newest-green   print the newest main commit whose
#                                            ci.yml push run is green; exit 1
#                                            (reason on stderr) if main is red
#                                            or has no verdict
#
# release.yml's `gate` job runs the first form for a pushed v* tag, so a tag on
# a red commit cannot ship. nightly.yml's `gate` job runs the second to pick
# the commit it builds. Both read a workflow's runs the same way:
#
#   - Only `push` runs on main and `workflow_dispatch` runs count. A pull
#     request's run tested a merge ref, not this commit.
#   - A run that is `cancelled` (or skipped, neutral, ...) is no verdict. ci.yml
#     pushes to main share one concurrency group, so a commit in the middle of
#     a burst of merges has its pending run cancelled by the next merge.
#   - For one commit, the NEWEST run with a verdict decides, so a dispatched
#     run supersedes an earlier push run of the same commit. A run still in
#     progress is not a success: wait for it.
#
# A commit with no verdict (cancelled in a burst, or a Markdown-only commit
# that ci.yml's paths-ignore skipped) gets one from a manual run; the failure
# message prints the commands.
#
# Environment: REPO (owner/name; default $GITHUB_REPOSITORY, then `gh repo
# view`), GH (the gh binary; scripts/test-release-gate.sh substitutes a fake),
# GH_TOKEN as gh wants it. Needs `actions: read` and `contents: read`.
set -euo pipefail

GH=${GH:-gh}
GATING_WORKFLOWS="ci.yml doc-lint.yml"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -eq 1 ] || usage
case "$1" in -h|--help) usage ;; esac

REPO=${REPO:-${GITHUB_REPOSITORY:-}}
[ -n "$REPO" ] || REPO=$("$GH" repo view --json nameWithOwner --jq .nameWithOwner)

# classify CONCLUSION -> green | red | none
classify() {
  case "$1" in
    success) echo green ;;
    failure|timed_out|startup_failure) echo red ;;
    *) echo none ;;
  esac
}

# runs WORKFLOW QUERY: one line per counted run, newest first:
#   head_sha status conclusion event url
runs() {
  "$GH" api "repos/$REPO/actions/workflows/$1/runs?$2" --jq '
    .workflow_runs[]
    | select((.event == "push" and .head_branch == "main") or .event == "workflow_dispatch")
    | "\(.head_sha) \(.status) \(.conclusion) \(.event) \(.html_url)"'
}

# ── --newest-green ───────────────────────────────────────────────────────────
if [ "$1" = "--newest-green" ]; then
  # Captured first, so a failed API call fails the script instead of reading as "no runs".
  listing=$(runs ci.yml "branch=main&event=push&per_page=50")
  while read -r sha status conclusion _event _url; do
    [ "$status" = "completed" ] || continue   # a merge minutes ago must not cost the night
    case "$(classify "$conclusion")" in
      green) echo "$sha"; exit 0 ;;
      red)   echo "main is red (CI $conclusion on $sha)" >&2; exit 1 ;;
    esac
  done <<< "$listing"
  echo "no completed green CI run among main's last 50" >&2
  exit 1
fi

# ── SHA ──────────────────────────────────────────────────────────────────────
sha=$("$GH" api "repos/$REPO/commits/$1" --jq .sha) || {
  echo "release gate: cannot resolve '$1' in $REPO" >&2; exit 1; }

report=""
say() { report+="$1"$'\n'; }
ok=true
need_run=""

# compare BASE...HEAD: main is `ahead` of (or `identical` to) a commit it contains.
rel=$("$GH" api "repos/$REPO/compare/$sha...main" --jq .status)
case "$rel" in
  ahead|identical) ;;
  *) ok=false; say "  not on main (main is '$rel' relative to it)" ;;
esac

for wf in $GATING_WORKFLOWS; do
  verdict="" cancelled=0
  listing=$(runs "$wf" "head_sha=$sha&per_page=100")
  while read -r _sha status conclusion event url; do
    [ -n "$_sha" ] || continue
    if [ "$status" != "completed" ]; then
      verdict="running"; say "  $wf: still $status ($event) $url"; break
    fi
    case "$(classify "$conclusion")" in
      green) verdict=green; say "  $wf: success ($event) $url"; break ;;
      red)   verdict=red;   say "  $wf: $conclusion ($event) $url"; break ;;
      none)  cancelled=$((cancelled + 1)) ;;
    esac
  done <<< "$listing"
  if [ -z "$verdict" ]; then
    if [ "$cancelled" -gt 0 ]; then
      say "  $wf: no verdict ($cancelled run(s), all cancelled or skipped)"
    else
      say "  $wf: no verdict (no run for this commit)"
    fi
    need_run="$need_run $wf"
  fi
  [ "$verdict" = green ] || ok=false
done

emit() {
  printf '%s\n' "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo '```'; printf '%s\n' "$1"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
  fi
}

if $ok; then
  emit "release gate: GREEN for $sha"$'\n'"${report%$'\n'}"
  exit 0
fi

msg="release gate: RED for $sha"$'\n'"$report"
if [ -n "$need_run" ]; then
  short=${sha:0:9}
  msg+="A commit in the middle of a burst of merges, or one that changed only Markdown,"$'\n'
  msg+="gets no CI verdict of its own. Run CI on the commit, wait for it, then re-run"$'\n'
  msg+="this gate (for a pushed tag: re-run the failed \`gate\` job of the Release run)."$'\n'
  msg+="If the commit is main's HEAD:"$'\n'
  for wf in $need_run; do msg+="  gh workflow run $wf --ref main"$'\n'; done
  msg+="Otherwise, through a temporary branch at the commit:"$'\n'
  msg+="  git push origin $sha:refs/heads/release-check-$short"$'\n'
  for wf in $need_run; do msg+="  gh workflow run $wf --ref release-check-$short"$'\n'; done
  msg+="  git push origin --delete release-check-$short   # once the run has finished"$'\n'
  msg+="(A tag already at the commit works as --ref too.)"$'\n'
else
  msg+="Do not release this commit. Fix main, or tag a commit whose runs are green."$'\n'
fi
emit "${msg%$'\n'}" >&2
exit 1
