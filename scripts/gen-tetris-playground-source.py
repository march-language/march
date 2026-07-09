#!/usr/bin/env python3
"""Regenerate docs/assets/tetris/tetris-source.march.txt — the single
editable source shown in the Tetris playground's left pane.

The playground compiles exactly one user source string (see
js/march_browser_compile.ml), and March's grammar allows exactly one
top-level `mod` per file, so demo_app/tetris_logic/lib/tetris_logic.march
(its own forge project, kept separate so `forge test` stays native-safe —
see demo_app/tetris/forge.toml's path dependency) is nested INSIDE
`mod Tetris do ... end` here rather than being a sibling top-level mod.

Run from the project (worktree) root:
    python3 scripts/gen-tetris-playground-source.py
"""
import os

ROOT = os.getcwd()
LOGIC_PATH = os.path.join(ROOT, "demo_app", "tetris_logic", "lib", "tetris_logic.march")
TETRIS_PATH = os.path.join(ROOT, "demo_app", "tetris", "lib", "tetris.march")
DEST = os.path.join(ROOT, "docs", "assets", "tetris", "tetris-source.march.txt")


def main():
    logic_lines = open(LOGIC_PATH, encoding="utf-8").read().splitlines()
    tetris_lines = open(TETRIS_PATH, encoding="utf-8").read().splitlines()

    mod_idx = next(i for i, l in enumerate(logic_lines) if l.strip() == "mod TetrisLogic do")
    assert logic_lines[-1].strip() == "end", "tetris_logic.march must end with a bare 'end'"
    logic_header = logic_lines[:mod_idx]
    logic_body = logic_lines[mod_idx:]  # 'mod TetrisLogic do' .. closing 'end'

    tetris_mod_idx = next(i for i, l in enumerate(tetris_lines) if l.strip() == "mod Tetris do")

    out = []
    out += logic_header
    out.append("")
    out += tetris_lines[: tetris_mod_idx + 1]  # header comment + 'mod Tetris do'
    out.append("")
    out += ["  " + l if l.strip() else l for l in logic_body]  # nested, +2 indent
    out.append("")
    out += tetris_lines[tetris_mod_idx + 1 :]  # rest of Tetris body + trailing 'end'

    with open(DEST, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("wrote %d lines to %s" % (len(out), DEST))


if __name__ == "__main__":
    main()
