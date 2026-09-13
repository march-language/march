#!/usr/bin/env bash
# Forbid a plain (non-atomic) store to an actor record's refcount word.
#
# Word 0 of an actor record is its refcount, mutated by every other thread
# through march_incrc/march_decrc.  actor_green_thread once bracketed each
# dispatch with `a[0] = 1; ... a[0] = saved_rc;` so an `rc == 1` reuse check
# would pass, which published a false count to every other thread and freed
# live actors (specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md).
# The comment the fix left behind says there is no safe version of that
# window.  test/native/actor_dispatch_rc_window.march pins the window from
# INSIDE a handler; this pins the source pattern, so a reintroduction on a
# dispatch path that test cannot observe is still caught.
#
# What counts as "an int64_t view of an actor": a cast `(int64_t *)EXPR` or
# `(march_hdr *)EXPR` where EXPR names an actor (an identifier containing
# `actor`), directly or through a local alias declared from such a cast
# (`int64_t *a = (int64_t *)actor;`).  A store is `=` (not `==`), a compound
# assignment, or `++`/`--` on index 0, on `*alias`, or on `->rc`.  Comments
# and string literals are stripped first, so the explanatory comments that
# quote the old clobber do not trip it.
#
# This is deliberately a grep-level guard, not an analysis: a reintroduction
# spelled through a differently named pointer evades it.  Its job is the
# pattern that actually regressed.  RC changes go through march_incrc /
# march_decrc (atomic), never through a store here.
#
# Usage: scripts/check-actor-rc-stores.sh     # exit 1 on any store found
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - runtime/*.c <<'PY'
import re, sys

def strip_comments_and_strings(src):
    # Replace comments and string/char literals with spaces, keeping newlines
    # so reported line numbers stay right.
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('/*', i):
            j = src.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j
        elif src.startswith('//', i):
            j = src.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)

ACTORISH = r'[A-Za-z_][A-Za-z0-9_]*(?:(?:->|\.)[A-Za-z_][A-Za-z0-9_]*)*'
CAST = r'\(\s*(?:int64_t|march_hdr)\s*\*\s*\)\s*\(?\s*(' + ACTORISH + r')\s*\)?'
WRITE = r'\s*(?:=(?!=)|\+=|-=|\|=|&=|\+\+|--)'

problems = 0
for path in sys.argv[1:]:
    code = strip_comments_and_strings(open(path, encoding='utf-8', errors='replace').read())
    lines = code.split('\n')
    # Aliases: `int64_t *NAME = (int64_t *)EXPR;` where EXPR names an actor.
    aliases = set()
    for m in re.finditer(r'\b(?:int64_t|march_hdr)\s*\*\s*([A-Za-z_]\w*)\s*=\s*' + CAST, code):
        if 'actor' in m.group(2).lower():
            aliases.add(m.group(1))
    patterns = []
    # Direct: ((int64_t *)actor)[0] = ... / ((march_hdr *)actor)->rc = ...
    patterns.append(re.compile(r'\(\s*' + CAST + r'\s*\)\s*(?:\[\s*0\s*\]|->\s*rc\b)' + WRITE))
    for a in sorted(aliases):
        patterns.append(re.compile(r'\b' + re.escape(a) + r'\s*(?:\[\s*0\s*\]|->\s*rc\b)' + WRITE))
        # `*a = v` only in statement position, so a declaration such as
        # `int64_t *a = ...` or `march_string *a = ...` is not a store.
        patterns.append(re.compile(r'(?:^|[;{}]|\)\s*)\s*\*\s*' + re.escape(a) + r'\b' + WRITE))
        patterns.append(re.compile(r'(?:\+\+|--)\s*' + re.escape(a) + r'\s*\[\s*0\s*\]'))
    for lineno, line in enumerate(lines, 1):
        for p in patterns:
            m = p.search(line)
            if not m:
                continue
            groups = [g for g in m.groups() if g] if m.groups() else []
            if groups and not any('actor' in g.lower() for g in groups):
                continue
            print(f"  {path}:{lineno}: plain store to an actor record's refcount word:"
                  f" {line.strip()}")
            problems += 1
            break

if problems:
    print(f"check-actor-rc-stores FAILED: {problems} store(s). An actor record's "
          "word 0 is shared with every thread; change it only through "
          "march_incrc/march_decrc.")
    sys.exit(1)
print("check-actor-rc-stores passed")
PY
