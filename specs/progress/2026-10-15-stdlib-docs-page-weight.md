# Stdlib API reference: lighter pages (2026-10-15)

Reported: the docs pages load slowly.

**Measured** on march-lang.org:
- Nothing from the in-browser REPL loads before a "Try it" click.
- A warm page load is about 190 ms; the slowness was cold loads.
- Each stdlib page was about 400 KB of HTML. 343 KB of that was a sidebar listing all
  2,964 entries of all 132 modules, repeated on every page (about 7,300 DOM nodes).
- Every page eagerly fetched the 424 KB `search-index.json`, about 1 s cold.
- The first byte from GitHub Pages' CDN on a cache miss took about 1.8 s once, then
  150-250 ms. That part is outside our control.

**Fix** (march_doc, march-language/march_doc#5):
- The sidebar lists every module, but expands only the current module
  (`DocHtml.sidebar_nav_for`).
- The search index loads when search is first opened (`loadSI`).

The pages here are regenerated:

| | Before | After |
|---|---|---|
| HTML for 133 pages | 50.5 MB | 8.3 MB |
| Http page | 404 KB | 93 KB |
| BigInt page | 372 KB | 57 KB |
| List page DOM nodes | 7,300 | 1,458 |

Checked in a browser:
- the current module is expanded and the others are listed;
- the index is not fetched before search;
- a query typed before the index arrived still gets results;
- "Try it" works.
