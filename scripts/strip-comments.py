#!/usr/bin/env python3
"""Print the CODE lines of an OCaml source file, with comments removed.

Used by the refactor verification steps in
specs/plans/2026-08-28-refine-check-decomposition.md:

  * the SPLICE CHECK — an extracted band, spliced back at its `include` site,
    must reproduce the original file's code sequence exactly.  Comments must be
    stripped because a move legitimately rewrites module headers.

  * the SINGLE-DEFINITION assertion for shared mutable cells.  A plain `grep`
    over the sources matches the prose in the module headers, which name the
    very cells being counted — during the finding-3 work that made an
    `install_lower_expr` invariant report 2/2 when the true code count was 1/0.

Handles NESTED `(* ... *)` (OCaml comments nest), ordinary string literals
with backslash escapes, and QUOTED string literals `{id|...|id}` -- so a
`"(*"` inside a string does not open a comment, a `"\\"` does not swallow the
closing quote, and neither does a `(*` inside a `{|...|}` fixture.  Blank
lines are dropped so that reflowing whitespace cannot show up as a diff.

The quoted-string case is not hypothetical: lsp/test/test_lsp.ml embeds 297
`{|...|}` March fixtures, several containing `(*`.  Without this the stripper
enters comment mode inside a fixture and swallows to the next `*)`, which
makes its output depend on where a file happens to be CUT -- exactly the
property a splice check assumes it does not have.

Usage:  scripts/strip-comments.py FILE
"""
import sys


def strip(src: str) -> str:
    out = []
    i, n, depth = 0, len(src), 0
    while i < n:
        if depth == 0 and src.startswith('(*', i):
            depth = 1
            i += 2
            continue
        if depth > 0:
            if src.startswith('(*', i):
                depth += 1
                i += 2
                continue
            if src.startswith('*)', i):
                depth -= 1
                i += 2
                continue
            if src[i] == '\n':
                out.append('\n')
            i += 1
            continue
        c = src[i]
        if c == '{':
            # OCaml quoted string literal: {id|...|id} with an optional
            # lowercase identifier.  Scan for the matching |id} terminator.
            j = i + 1
            while j < n and (src[j].islower() or src[j] == '_'):
                j += 1
            if j < n and src[j] == '|':
                tag = src[i + 1:j]
                close = '|' + tag + '}'
                k = src.find(close, j + 1)
                if k == -1:
                    k = n
                seg = src[i:k + len(close)]
                out.append(seg)
                i = k + len(close)
                continue
        if c == '"':
            out.append(c)
            i += 1
            while i < n:
                if src[i] == '\\':
                    out.append(src[i:i + 2])
                    i += 2
                    continue
                out.append(src[i])
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: strip-comments.py FILE", file=sys.stderr)
        return 2
    with open(sys.argv[1], errors='ignore') as fh:
        for line in strip(fh.read()).split('\n'):
            line = line.rstrip()
            if line.strip():
                print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
