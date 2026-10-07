#!/bin/bash
# post-failure-hint.sh
# After a Bash tool call that compiled or tested March and FAILED, point the
# agent at the triage tooling. Silent on success and on unrelated commands.
#
# Registered for PostToolUse (matcher Bash) next to post-commit-reminder.sh,
# and for PostToolUseFailure (matcher Bash): depending on the Claude Code
# version, a non-zero Bash exit arrives as PostToolUse with a non-zero exit
# code in the payload, or as a separate PostToolUseFailure event whose `error`
# names the exit code. Both shapes are handled.
#
# Test by hand:
#   echo '{"hook_event_name":"PostToolUse","tool_name":"Bash",
#          "tool_input":{"command":"scripts/run-tests.sh compiler"},
#          "tool_response":{"stdout":"","stderr":"FAIL"},"tool_exit_code":1}' \
#     | .claude/hooks/post-failure-hint.sh

input=$(cat)

printf '%s' "$input" | python3 -c '
import json, re, sys

try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cmd = (p.get("tool_input") or {}).get("command") or ""
if not re.search(r"march(\.exe)?\s.*--compile|main\.exe\s.*--compile|run-tests\.sh|dune\s+runtest|dune\s+build", cmd):
    sys.exit(0)

event = p.get("hook_event_name") or "PostToolUse"

def nonzero(v):
    try:
        return v is not None and int(v) != 0
    except (TypeError, ValueError):
        return False

failed = event == "PostToolUseFailure"
failed = failed or nonzero(p.get("tool_exit_code"))
resp = p.get("tool_response")
if isinstance(resp, dict):
    for k in ("exit_code", "exitCode", "returncode", "code"):
        failed = failed or nonzero(resp.get(k))
    failed = failed or bool(resp.get("is_error"))
err = p.get("error") or ""
if isinstance(err, str) and re.search(r"(exit(ed)?( with)? code|Exit code)\s*[1-9]", err):
    failed = True

if not failed:
    sys.exit(0)

hint = ("scripts/triage.sh and the march-debug skill exist; "
        "see CLAUDE.md \x27When something breaks\x27")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": event, "additionalContext": hint}}))
'
exit 0
