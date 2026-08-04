#!/usr/bin/env python3
"""Render a benchmark JSONL run (from run_benchmarks.sh MACHINE_OUT) as an SVG.

    MACHINE_OUT=bench/results/run.jsonl bash bench/run_benchmarks.sh
    python3 bench/chart.py bench/results/run.jsonl bench/results/run.svg

The chart is generated FROM the committed data, never hand-drawn — so a number
on the page is traceable to the run that produced it. No external libraries:
the SVG is emitted directly, matching the rest of bench/'s no-dependency stance.

Each benchmark becomes a grouped horizontal bar chart (one bar per language),
bars labelled with the median in ms. The run's provenance (the `meta` record) is
printed as a caption so the image documents its own conditions.
"""
import html
import json
import sys

# Fixed language order + colours so successive charts read consistently. A
# language absent from a benchmark simply has no bar (the honest "not run").
LANG_ORDER = ["March", "OCaml", "Rust", "Elixir", "Python", "NumPy"]
COLOR = {
    "March":  "#4c9be8",
    "OCaml":  "#e5883a",
    "Rust":   "#d0563a",
    "Elixir": "#9a6fce",
    "Python": "#e0b93a",
    "NumPy":  "#3aae8f",
}
FALLBACK = "#8b98a8"


def load(path):
    meta = {}
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("meta"):
                meta = obj
            else:
                rows.append(obj)
    if not rows:
        sys.exit(f"{path}: no benchmark rows")
    return meta, rows


def group(rows):
    """benchmark -> [(language, median), ...] in LANG_ORDER, then any extras."""
    out = {}
    for r in rows:
        out.setdefault(r["benchmark"], {})[r["language"]] = r["median_ms"]
    ordered = {}
    for bench, langs in out.items():
        seq = [(l, langs[l]) for l in LANG_ORDER if l in langs]
        seq += [(l, v) for l, v in langs.items() if l not in LANG_ORDER]
        ordered[bench] = seq
    return ordered


def svg(meta, grouped):
    # Layout constants (px).
    W = 900
    pad_l, pad_r, pad_top = 210, 90, 64
    bar_h, bar_gap, group_gap = 22, 6, 26
    label_w = pad_l - 16

    # Height: sum of all bars + per-group gaps.
    total_bars = sum(len(v) for v in grouped.values())
    n_groups = len(grouped)
    plot_h = total_bars * (bar_h + bar_gap) + n_groups * group_gap
    H = pad_top + plot_h + 74

    def esc(s):
        return html.escape(str(s))

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
        f'font-family="ui-sans-serif,-apple-system,Segoe UI,Roboto,sans-serif">',
        f'<rect width="{W}" height="{H}" fill="#0b0f14"/>',
        f'<text x="{pad_l}" y="30" fill="#e6edf3" font-size="18" '
        f'font-weight="700">Cross-language benchmarks — median wall-clock (ms), lower is better</text>',
    ]
    cap = "  ·  ".join(
        f"{k}: {esc(meta[k])}" for k in ("cpu", "cores", "runs", "load") if k in meta)
    if meta.get("date"):
        cap = f"{meta['date']}  ·  " + cap
    parts.append(
        f'<text x="{pad_l}" y="50" fill="#7d8b9c" font-size="12">{esc(cap)}</text>')

    y = pad_top
    for bench, seq in grouped.items():
        gmax = max(v for _, v in seq) or 1.0
        parts.append(
            f'<text x="{label_w}" y="{y + 13}" fill="#c8d3e0" font-size="13" '
            f'font-weight="650" text-anchor="end">{esc(bench)}</text>')
        for lang, val in seq:
            bw = (W - pad_l - pad_r) * (val / gmax)
            bw = max(bw, 2.0)
            color = COLOR.get(lang, FALLBACK)
            parts.append(
                f'<rect x="{pad_l}" y="{y}" width="{bw:.1f}" height="{bar_h}" '
                f'rx="3" fill="{color}"/>')
            parts.append(
                f'<text x="{pad_l - 8}" y="{y + 15}" fill="#8b98a8" font-size="11" '
                f'text-anchor="end">{esc(lang)}</text>')
            parts.append(
                f'<text x="{pad_l + bw + 6:.1f}" y="{y + 15}" fill="#c8d3e0" '
                f'font-size="11">{val:.1f}</text>')
            y += bar_h + bar_gap
        y += group_gap

    parts.append(
        f'<text x="{pad_l}" y="{H - 20}" fill="#5c6875" font-size="11">'
        f'Generated from committed data by bench/chart.py — bars scaled per '
        f'benchmark (each group\'s slowest = full width).</text>')
    parts.append('</svg>')
    return "\n".join(parts)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: chart.py RUN.jsonl [OUT.svg]")
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".svg"
    meta, rows = load(src)
    open(out, "w").write(svg(meta, group(rows)))
    print(f"wrote {out} ({len(rows)} rows, {len(group(rows))} benchmarks)")


if __name__ == "__main__":
    main()
