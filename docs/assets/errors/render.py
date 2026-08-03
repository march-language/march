#!/usr/bin/env python3
"""Render March's real diagnostic output as HTML cards, for the site.

Run from anywhere:

    python3 docs/assets/errors/render.py [path/to/march]

For each source in ./src it runs `march --check` with MARCH_COLOR=always,
converts the ANSI the compiler actually emitted, and writes a self-contained
card next to this script. Nothing about the text is hand-edited — if a message
changes, re-running this is the whole update, and a card that no longer matches
the compiler is a bug in the card rather than something to patch by hand.

Sources live in ./src and are compiled from THAT directory, so the filename in
the header stays short instead of an absolute path.
"""
import html
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / "src"

# One card per source: (stem, tag, caption).
CARDS = [
    ("session", "Linearity",
     "A double-use names the earlier consumption site, not just the reuse."),
    ("divide", "Refinement",
     "The violation names the parameter and callee, and underlines the argument."),
    ("scale", "Unverified contract",
     "What the checker could not decide, and how to make that an error."),
    ("tokens", "Capability",
     "The call chain from <code>main</code> that forced the capability."),
]

SGR = re.compile(r"\x1b\[([0-9;]*)m")
COLOR = {"31": "#ff6b6b", "33": "#e5c07b", "34": "#61afef",
         "35": "#c678dd", "36": "#56b6c2"}


def ansi_to_html(text: str) -> str:
    """Faithful SGR → span conversion. March uses 0/1/2 and 31/33/34/35/36
    (lib/errors/errors.ml); anything else is ignored rather than guessed at."""
    out, bold, dim, color, is_open = [], False, False, None, False

    def close():
        nonlocal is_open
        if is_open:
            out.append("</span>")
            is_open = False

    def open_():
        nonlocal is_open
        styles = []
        if bold:
            styles.append("font-weight:700")
        if dim:
            styles.append("opacity:.62")
        if color:
            styles.append(f"color:{COLOR[color]}")
        if styles:
            out.append('<span style="%s">' % ";".join(styles))
            is_open = True

    pos = 0
    for m in SGR.finditer(text):
        if text[pos:m.start()]:
            out.append(html.escape(text[pos:m.start()]))
        close()
        for p in (m.group(1).split(";") if m.group(1) else ["0"]):
            if p in ("", "0"):
                bold = dim = False
                color = None
            elif p == "1":
                bold = True
            elif p == "2":
                dim = True
            elif p in COLOR:
                color = p
        open_()
        pos = m.end()
    if text[pos:]:
        out.append(html.escape(text[pos:]))
    close()
    return "".join(out)


PAGE = """<meta charset="utf-8">
<title>March diagnostics — {tag}</title>
<style>
  :root {{ color-scheme: dark; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:34px; background:#0b0f14;
         font-family: ui-sans-serif, -apple-system, "Segoe UI", Roboto, sans-serif; }}
  .card {{ max-width:1120px; margin:0 auto; background:#11161d;
           border:1px solid #1e2732; border-radius:12px; overflow:hidden;
           box-shadow:0 18px 44px rgba(0,0,0,.45); }}
  .bar {{ display:flex; align-items:center; gap:9px; padding:11px 15px;
          background:#151b23; border-bottom:1px solid #1e2732; }}
  .dot {{ width:11px; height:11px; border-radius:50%; }}
  .tag {{ margin-left:7px; font-size:12.5px; font-weight:650;
          letter-spacing:.02em; color:#8b98a8; }}
  pre {{ margin:0; padding:20px 22px 24px;
         font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
         font-size:13px; line-height:1.62; color:#c8d3e0;
         white-space:pre; overflow-x:auto; }}
  .cap {{ max-width:1120px; margin:16px auto 0; font-size:13px;
          color:#7d8b9c; text-align:center; }}
  code {{ font-family: ui-monospace, Menlo, monospace; color:#9fb0c4; }}
</style>
<div class="card">
  <div class="bar">
    <span class="dot" style="background:#ff5f57"></span>
    <span class="dot" style="background:#febc2e"></span>
    <span class="dot" style="background:#28c840"></span>
    <span class="tag">{tag}</span>
  </div>
  <pre>{body}</pre>
</div>
<p class="cap">{caption}</p>
"""


def main() -> int:
    march = sys.argv[1] if len(sys.argv) > 1 else "march"
    for stem, tag, caption in CARDS:
        src = SRC / f"{stem}.march"
        if not src.exists():
            print(f"missing source: {src}", file=sys.stderr)
            return 1
        # cwd=SRC so the diagnostic header shows `session.march`, not a path.
        proc = subprocess.run(
            [march, "--check", src.name],
            cwd=SRC, capture_output=True, text=True,
            env={"MARCH_COLOR": "always", "PATH": "/usr/bin:/bin"},
        )
        raw = (proc.stdout + proc.stderr).strip("\n")
        if not raw:
            print(f"{stem}: compiler produced no diagnostic — the sample no "
                  f"longer demonstrates anything", file=sys.stderr)
            return 1
        (HERE / f"{stem}.html").write_text(
            PAGE.format(tag=tag, body=ansi_to_html(raw), caption=caption))
        print(f"wrote {stem}.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
