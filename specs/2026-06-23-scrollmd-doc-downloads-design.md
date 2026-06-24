# Design: Download docs guides & cookbooks as runnable `.scrollmd` notebooks

**Status:** Proposed (v2 — revised after reading Scroll's runner) · **Date:** 2026-06-23

## Goal

Let a reader on the March docs site take a tutorial-style page — a guide
(`tour`, `build-a-cli`, `memory-model`, …) or a cookbook recipe (`cli`, `files`,
`config`, …) — and **download it as a `.scrollmd` file** they can open in
[Scroll](https://github.com/march-language/scroll) and run cell-by-cell, with
inline instructions for how to run it.

## How Scroll actually runs a notebook (corrected model)

Scroll does **not** keep a persistent in-process REPL. Reading
`lib/runner.march`, running a cell calls `generate_runner(cells, n)`, which
**regenerates one whole program from cells `0..n` and runs it as a fresh
subprocess** every time. The generated program has a fixed shape:

```march
mod NotebookRunner do
  <each module cell, embedded as a NESTED mod>
  fn main() do
    <each non-module cell, inlined as statements; last expr auto-printed>
  end
end
```

Two consequences drive this whole design:

- **Module cells** (`is_mod_cell`: first non-blank line starts with `mod `) are
  embedded as **nested mods** inside `NotebookRunner`; their `Qualified.name`s
  resolve from later cells. Multiple module cells are fine (nested siblings).
  Because everything is nested inside one outer mod, the *top-level* "one `mod`
  per file / no `mod`+sibling-`fn`" limitation never bites a notebook.
- **Non-module cells** are inlined **as statements inside `main()`**. Therefore a
  non-module cell may contain only expressions and `let` bindings — **not** a bare
  top-level `type` or `fn` declaration (those are illegal inside a function body),
  and not a `fn main` (it collides with the runner's `main`).

Also: cells share state by **re-execution**, not by a live session — running cell
`n` re-runs `0..n`. So **every side effect in earlier cells re-fires on each
later run.** A cell that is exactly ` ```march ` becomes a Code cell; **any other
fence** (` ```toml `, ` ```python `, ` ```bash `, ` ```march-static `) falls
through to prose. `<!-- section: Title -->` becomes a divider.

## The core constraint this imposes

Our docs are Markdown with ` ```march ` blocks, so delivery is mostly a transform
— **but** the cell model rejects a lot of ordinary doc Markdown. A page is only
*notebook-shaped* if, on every **runnable** ` ```march ` block:

> **Cell-shape rule.** A runnable cell is **either** a single `mod …` block (any
> decls allowed inside it) **or** expression / `let` statements only — never a
> bare top-level `type`/`fn`/`import`, never a cell named `fn main`.

Bare `type`/`fn` references, signature fragments, anti-patterns, and
non-March-but-fenced examples must be **marked non-runnable** so they render as
display-only. So the real work isn't "flip a flag" — it's **auditing and lightly
restructuring examples** on opted-in pages (wrap a stray `type`/`fn` in a `mod`,
split a mixed cell, mark fragments) and verifying with a faithful check.

## Design

### 1. Opt-in per page

Front-matter flag (opt-in, because reference/landing pages aren't notebooks):

```yaml
---
layout: cookbook
title: "Cookbook: Config"
scrollmd: true
---
```

Opt in pages whose examples fit the cell-shape rule after a light audit (mark
fragments, maybe wrap one stray decl in a `mod`). See **Status** below for the
pages actually opted in and the ones deliberately left out. `actors` /
`supervision` remain out until their examples are confirmed runnable headless.

### 2. Authoring markers (invisible in rendered docs — HTML comments)

| Marker (line before a fence, or standalone) | Effect in `.scrollmd` |
|---|---|
| `<!-- scroll:skip -->` before a ` ```march ` block | Demoted: fence rewritten to ` ```march-static ` → Scroll renders it as a display-only code block, never a cell. Use for fragments, signatures, anti-patterns, bare `type`/`fn` references. |
| `<!-- scroll:run EXPR -->` | Replaced by a runnable ` ```march `/`EXPR`/` ``` ` cell — used to produce visible output after module-defining cells. |

No Scroll change is needed: demotion works because Scroll only runs *exact*
` ```march `.

### 3. The converter (`scripts/gen-scrollmd.py`)

Pure-Python, no March dependency for emit (so it runs in the Pages workflow
without OCaml). Two modes.

**`--emit` (default):** doc Markdown → `.scrollmd`.
1. Strip Jekyll front-matter; capture `title`, `permalink`, `scrollmd`.
2. Prepend a **header cell** (provenance + run instructions + version + trust
   note — see §5).
3. **Demote** each ` ```march ` preceded by `<!-- scroll:skip -->`: drop the
   marker, rewrite that fence to ` ```march-static `.
4. **Expand** each `<!-- scroll:run EXPR -->` into a ` ```march ` cell.
5. **Rewrite links permalink-relative** (see §4).
6. Everything else passes through unchanged.

**`--check`:** verify the notebook compiles *the way Scroll runs it*. Tokenize the
emitted `.scrollmd` with the **same line rules as Scroll's `parse_cells`** (exact
` ```march ` opens a Code cell; ` ``` ` closes; `march-static` is prose), then
build the `NotebookRunner` program (§How Scroll runs) — nested mod-cells +
non-mod cells inlined into `main()` — and run `march --check` on it. This replaces
the unsound "concatenate + check" idea: it mirrors the real runner, so it catches
exactly the failures Scroll would (bare `type`/`fn` in an inline cell, name
collisions, undefined refs) and doesn't false-fail on multi-module notebooks.
Network/IO cells can't be exercised by `--check` (typecheck only), which is fine —
typecheck is the rot we're guarding against.

### 4. Link rewriting (permalink-relative)

Resolve against the page's own `permalink`, not a fixed prefix:
- `{{ site.baseurl }}/docs/x/` → `https://march-lang.org/docs/x/`.
- Leading-slash `/docs/x/` → `https://march-lang.org/docs/x/`.
- Bare-relative `](foo/)` / `](foo.md)` / `](../foo/)` → resolved against the
  page's permalink directory, then absolutized. (A cookbook page at
  `/docs/cookbook/config/` turns `[HTTP](http/)` into
  `https://march-lang.org/docs/cookbook/http/`.)
- Anchor-only `#sec` → absolutized against the page's canonical URL.
- `{{ site.baseurl }}/assets/...` images → absolute (they load from the site).

### 5. Header cell (self-documenting, version-pinned)

```markdown
> **Generated from the [March docs](https://march-lang.org/docs/<slug>/).**
> Runnable Scroll notebook. To use it:
>
> 1. Install Scroll once: `forge install scroll@https://github.com/march-language/scroll`
> 2. Run it: `forge scroll.serve <file>.scrollmd`
> 3. **Shift+Enter** runs a cell. Cells share state top-to-bottom, and running a
>    cell re-runs the ones above it — so keep cells side-effect-free or idempotent.
>
> Generated for March <VERSION>. Blocks shown for reference only won't run.
> This runs code on your machine — it's the same code shown on the docs page.
```

`<VERSION>` is stamped from `march --version` at generation time (passed in by the
build; omitted with a "see docs" note if unavailable).

### 6. Re-execution safety (authoring rule for IO examples)

Because prefixes re-run, opted-in pages should prefer **pure / read-only**
examples, or a **single idempotent setup cell**. Pages whose point is a mutating
side effect (POST, append, `Process.run`) should mark those blocks
`scroll:skip` and demonstrate with prose, or show a pure in-memory variant
(e.g. `Toml.parse("…")` on a literal string instead of reading a file).

### 7. Delivery / UX

- **Output:** `docs/downloads/<flat-slug>.scrollmd`. Flat-slug = permalink path
  with `/` → `-`, trimmed (`/docs/cookbook/config/` → `cookbook-config`,
  `/docs/build-a-cli/` → `build-a-cli`) so cookbook and top-level pages can't
  collide. The dir is generated output (gitignored; regenerated in CI like the
  stdlib reference).
- **Button:** an `_includes/scrollmd-button.html` rendered in `docs.html` and
  `cookbook.html` only when `page.scrollmd`, linking to the download with the
  `download` attribute.

### 8. Build integration

- Add a "Generate .scrollmd downloads" step to `deploy-pages.yml` **before** the
  Jekyll build: `python3 scripts/gen-scrollmd.py --emit --out docs/downloads`.
  Pure Python, no toolchain needed.
- **CI gate (separate, needs the compiler):** a job that runs
  `gen-scrollmd.py --check` against every opted-in page, using a built `march`.
  This is the rot guard — if an edit breaks a notebook cell, CI fails. It belongs
  in `ci.yml` (which already builds the compiler), not the Pages workflow.

## What this is not

- **Not two-way:** the download is a snapshot; edits in Scroll don't flow back to
  the docs.
- **Not a sandbox:** running a notebook executes March on the reader's machine
  (same trust model as the code printed on the page; stated in the header).

## Scroll-side notes (no blocking changes)

- **Server cells:** the README documents ` ```march:server `, but
  `parse_cells` only matches exact ` ```march `. A `scroll:server` marker is
  **deferred** until Scroll's server fence is confirmed; for now such blocks are
  `scroll:skip`-ed.
- **Nested fences:** `parse_cells` matches ` ```march ` even inside a ````markdown
  block, so a page that *documents the notebook format* would mis-tokenize. The
  converter mirrors this behavior; **meta-docs are excluded from the opt-in set**
  for v1 rather than worked around.

## Status (built)

The converter (`scripts/gen-scrollmd.py`, `--emit` + faithful `--check`), the
download button (`_includes/scrollmd-button.html`, wired into `docs.html` /
`cookbook.html`), the Pages-workflow emit step, and the `ci.yml` `--check` gate
are all in place. `docs/downloads/` is generated (gitignored).

**Opted in (7 — all pass `--check`):** `cookbook/config`, `cookbook/files`,
`cookbook/cli`, `cookbook/json-api`, `build-a-cli`, `flow`, `memory-model`.
Each was audited to the cell-shape rule: fragments / bare-decl references /
anti-patterns marked `scroll:skip`, a pure runnable demo added where one fit, and
mutating/network cells kept define-only (never auto-run).

**Left out (quality over coverage):**
- `session-types` — a `protocol` nested in Scroll's `NotebookRunner` isn't visible
  to `Chan.new` at the call site, and the `offer`/`match` handler example hits the
  linear-checker limitation; a runnable version would need restructuring the page.
- `safety-by-construction` — entirely illustrative signatures (the page's *value*);
  nothing compiles standalone, by design.
- `tour` — almost every block is a bare top-level `fn`/`type` one-liner; faithful
  conversion would mean skipping/wrapping dozens of blocks, gutting the tour.

## Remaining / next

- **Manual confirm** one generated notebook opens and *runs* (with output) in
  Scroll — the one thing `--check` (typecheck-only) can't cover.
- **v.next:** revisit `session-types` if Scroll exposes top-level protocol
  visibility; server cells once Scroll's `march:server` fence lands; a possible
  "download all recipes" bundle.
