#!/bin/bash
# Content-presence audit. Patch application is useless after months of drift,
# so instead: take each commit's substantive ADDED code lines and ask how many
# of them exist in the current tree at all. A fix that was merged, rebased, or
# re-implemented still leaves its distinctive lines behind; one that was lost
# leaves none.
#
# Usage: content_audit.sh <rev-range-or-branch>
set -uo pipefail
RANGE="${1:?rev range, e.g. main..docs/core-march-types-skeleton}"
CODE_RE='^(lib|bin|runtime|stdlib|forge|lsp|js)/'

git log --no-merges --pretty="%H" $RANGE | while read -r sha; do
  subj=$(git log -1 --pretty="%s" "$sha")
  date=$(git log -1 --pretty="%ad" --date=short "$sha")
  files=$(git show --stat --format="" --name-only "$sha" | grep -E "$CODE_RE" || true)
  if [ -z "$files" ]; then
    printf 'DOCS-ONLY   | %s | %s | %s\n' "${sha:0:8}" "$date" "$subj"
    continue
  fi

  total=0; found=0
  for f in $files; do
    [ -f "$f" ] || continue
    # substantive added lines: real code, long enough to be distinctive,
    # skipping comment-only and brace-only noise
    while IFS= read -r line; do
      [ ${#line} -lt 25 ] && continue
      case "$line" in \(\**|\**|//*|/\**|"#"*) continue ;; esac
      total=$((total+1))
      if grep -Fq -- "$line" "$f" 2>/dev/null; then
        found=$((found+1))
      elif grep -RFq --include='*.ml' --include='*.mly' --include='*.mll' \
             --include='*.c' --include='*.h' --include='*.march' \
             -- "$line" lib bin runtime stdlib forge lsp js 2>/dev/null; then
        found=$((found+1))   # moved to another file / superseded elsewhere
      fi
    done < <(git show "$sha" -- "$f" | sed -n 's/^+\([^+].*\)/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u)
  done

  if [ "$total" -eq 0 ]; then
    printf 'NO-SIGNAL   | %s | %s | %s\n' "${sha:0:8}" "$date" "$subj"
    continue
  fi
  pct=$(( found * 100 / total ))
  if   [ "$pct" -ge 80 ]; then v='PRESENT    '
  elif [ "$pct" -le 15 ]; then v='*** LOST **'
  else v='PARTIAL    '; fi
  printf '%s | %s | %s | %s  [%d/%d = %d%%]\n' "$v" "${sha:0:8}" "$date" "$subj" "$found" "$total" "$pct"
done
