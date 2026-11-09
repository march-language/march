#!/usr/bin/env python3
"""check-explainer-budget.py: keep docs/protocol-to-cluster.md a 20-minute read.

The explainer's design caps it at a 20-minute read. Technical prose beside code and a
moving graphic reads slowly, so the budget is 3,200 words of prose and cards and 44 cards.
This counts both, per `##` section, and exits 1 when either total is over.

    scripts/check-explainer-budget.py PAGE [--max-words 3200] [--max-cards 44]

Not counted: front matter, HTML comments, fenced code, Liquid tags and outputs, HTML tags,
headings, and anything inside <details> (a collapsed drawer is optional reading).
A card is an element with class `mx-step`.
"""
import re
import sys
from pathlib import Path

MAX_WORDS = 3200
MAX_CARDS = 44


def count(text):
    """{section title: {"words": n, "cards": n}} in page order. Text before the first
    `##` heading is the section "(opening)", present only if it has words or cards."""
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"^```.*?^```[^\n]*$", "", text, flags=re.S | re.M)
    text = re.sub(r"<details\b.*?</details>", "", text, flags=re.S)
    text = re.sub(r"\{%.*?%\}|\{\{.*?\}\}", "", text, flags=re.S)

    sections, title, body = {}, "(opening)", []

    def close():
        chunk = "\n".join(body)
        cards = len(re.findall(r'class="[^"]*\bmx-step\b', chunk))
        words = len(re.sub(r"<[^>]+>", " ", chunk).split())
        if words or cards or title != "(opening)":
            sections[title] = {"words": words, "cards": cards}

    for line in text.splitlines():
        m = re.match(r"^##\s+(.*)$", line)
        if m:
            close()
            title, body = m.group(1).strip(), []
        elif not line.startswith("#"):
            body.append(line)
    close()
    return sections


def main(argv):
    args = list(argv)
    max_words, max_cards = MAX_WORDS, MAX_CARDS
    if "--max-words" in args:
        i = args.index("--max-words"); max_words = int(args[i + 1]); del args[i:i + 2]
    if "--max-cards" in args:
        i = args.index("--max-cards"); max_cards = int(args[i + 1]); del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    sections = count(Path(args[0]).read_text())
    words = sum(s["words"] for s in sections.values())
    cards = sum(s["cards"] for s in sections.values())
    for title, s in sections.items():
        print(f"  {s['words']:5d} words  {s['cards']:3d} cards  {title}")
    print(f"  {words:5d} words  {cards:3d} cards  total (budget {max_words} words, {max_cards} cards)")
    if words > max_words or cards > max_cards:
        print("explainer is over its reading budget")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
