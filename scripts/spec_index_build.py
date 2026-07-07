#!/usr/bin/env python3
"""Builds the FTS5 spec-search index from vendored markdown docs.

Usage: spec_index_build.py <skill_dir> <commit> <date>

<skill_dir>/docs/*/*.md are parsed into per-heading sections and written to
<skill_dir>/spec-search.db as an FTS5 table. Called by
scripts/build-spec-index.sh after it vendors the docs.
"""
import re
import sqlite3
import sys
from pathlib import Path

HEADING_RE = re.compile(r'^(#{1,3})\s+(.*\S)\s*$')


def parse_sections(text):
    """Split markdown text into (heading_path, start_line, end_line, content)
    tuples on H1/H2/H3 boundaries. Lines are 1-based. end_line is the line
    number of the next heading, or len(lines)+1 at EOF."""
    lines = text.splitlines()
    heading_stack = []  # list of (level, text)
    raw_sections = []   # list of dicts with 0-based start/end indices
    current = None

    def path_str():
        return " > ".join(h[1] for h in heading_stack)

    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if m:
            if current is not None:
                current['end'] = i
                raw_sections.append(current)
            level = len(m.group(1))
            heading_text = m.group(2)
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            heading_stack.append((level, heading_text))
            current = {'heading_path': path_str(), 'start': i, 'end': None}
        elif current is None:
            current = {'heading_path': '(preamble)', 'start': i, 'end': None}

    if current is not None:
        current['end'] = len(lines)
        raw_sections.append(current)

    out = []
    for s in raw_sections:
        start_line = s['start'] + 1
        end_line = s['end'] + 1
        content = "\n".join(lines[s['start']:s['end']])
        out.append((s['heading_path'], start_line, end_line, content))
    return out


def build_db(skill_dir, commit, date):
    docs_dir = skill_dir / "docs"
    db_path = skill_dir / "spec-search.db"
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE VIRTUAL TABLE sections USING fts5("
        "file, heading_path, content, lineno UNINDEXED, end_lineno UNINDEXED)"
    )
    conn.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("INSERT INTO meta VALUES ('built_from_commit', ?)", (commit,))
    conn.execute("INSERT INTO meta VALUES ('built_at_date', ?)", (date,))

    count = 0
    for md_file in sorted(docs_dir.glob("*/*.md")):
        rel = md_file.relative_to(docs_dir).as_posix()
        text = md_file.read_text()
        for heading_path, start, end, content in parse_sections(text):
            if not content.strip():
                continue
            conn.execute(
                "INSERT INTO sections (file, heading_path, content, lineno, end_lineno) "
                "VALUES (?, ?, ?, ?, ?)",
                (rel, heading_path, content, start, end),
            )
            count += 1
    conn.commit()
    conn.close()
    print(f"indexed {count} sections", file=sys.stderr)


def main():
    if len(sys.argv) != 4:
        print("usage: spec_index_build.py <skill_dir> <commit> <date>", file=sys.stderr)
        sys.exit(1)
    skill_dir = Path(sys.argv[1])
    commit = sys.argv[2]
    date = sys.argv[3]
    build_db(skill_dir, commit, date)


if __name__ == "__main__":
    main()
