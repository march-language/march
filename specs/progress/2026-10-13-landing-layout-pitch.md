# Landing layout: the agreed pitch, in the file the site actually renders (2026-10-13)

The live site's home page is `docs/_layouts/landing.html`, which contains no
`{{ content }}`: the body of `docs/index.md` is never rendered there. So the two
`docs/index.md` passes earlier today (PR #977 claim fixes and Documentation table, PR #978
pitch rewrite) changed the GitHub-rendered page only, and the hero paragraph the owner
quoted from the live site was the layout's hard-coded copy. This change ports the agreed
pitch into the layout.

- **Hero**: h1 `ML types. / Effects as capabilities. / Actors, compiled native.` (the agreed
  tagline, shortened so it stays three lines at 56px); the owner's lead paragraph as the
  hero copy, with one link (memory model). `<meta name="description">` updated to match.
- **Features section**: the h2 is now the safety claim ("Safety is the compiler's job, not
  the test suite's."), followed by a new `.m-section-lead` paragraph (the safety paragraph
  with its four links: capabilities, linear types, refinement types, hot code reload).
- **Six cards in the agreed order**: the grant (new, with the real diagnostic as `-- !`
  alert lines), three safety layers on one function (new, the chunk-reader example),
  typed protocols for two parties or twenty (new, the `@[endpoints]` `Fan` protocol and
  role B's typed body), hot deploy gated by authority (new, the `--grant-cap` refusal
  transcript), actors with supervision (unchanged card, moved to fifth), FBIP flip card
  (unchanged, moved to sixth). The Type System, Memory, Refinement Types and Capabilities
  cards are retired; their samples (`TYPES`, `LINEAR`, `REFINE`, `CAP`) and `tryTYPES`
  are removed from the script, and `pfn`, `protocol`, `tag`, `always_linear` are added
  to the highlighter's keyword set so the new samples colour correctly.

Verified by building the site with the same Jekyll invocation the launch config uses
(`mise exec ruby@3.3 -- bundle exec jekyll build`) and viewing it in the browser pane at
1280px and at phone width: no console errors; the hero stays three lines; the lead and
all six cards render. `docs/index.md` is left as the GitHub-facing page; its Documentation
table is not shown on the site, which has no equivalent index (the Docs link goes to
Getting Started).
