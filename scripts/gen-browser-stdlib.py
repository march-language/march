#!/usr/bin/env python3
"""Regenerate docs/assets/march_stdlib.js (window.marchStdlib).

The FILES list must match `browser_stdlib_files` in js/march_browser.ml.
Run from the project (worktree) root: python3 scripts/gen-browser-stdlib.py
"""
import json
import os

FILES = [
    "prelude.march", "option.march", "result.march", "list.march",
    "task.march",
    "hamt.march", "map.march", "math.march", "string.march", "sort.march",
    "seq.march", "set.march", "array.march", "tuple.march", "char.march",
    "range.march", "enum.march", "random.march", "json.march",
    "http.march", "http_transport.march", "http_client.march",
    "crypto.march", "deque.march", "vector_clock.march", "merkle.march",
    "crdt.march", "consistent_hash.march",
]


def main():
    root = os.getcwd()
    out = ["window.marchStdlib = {};"]
    for name in FILES:
        with open(os.path.join(root, "stdlib", name), encoding="utf-8") as fh:
            src = fh.read()
        out.append("window.marchStdlib[%s] = %s;" % (json.dumps(name), json.dumps(src)))
    dest = os.path.join(root, "docs", "assets", "march_stdlib.js")
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("wrote %d modules to %s" % (len(FILES), dest))


if __name__ == "__main__":
    main()
