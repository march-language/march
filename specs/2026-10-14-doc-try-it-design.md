# "Try it" buttons on the stdlib API reference

Date: 2026-10-14
Status: design approved in conversation ("build it"); implemented the same day

Project 3 of 4 toward runnable documentation examples, for learning.
- Project 1, the release-built browser bundle: `specs/2026-10-14-browser-repl-bundle-design.md`.
- Project 2, on-demand modules, unavailable modules and Int overflow:
  `specs/2026-10-14-browser-repl-modules-design.md`.
- Project 4 extends checking to whole-program examples.

## Decisions (from the conversation)

- **Opt-in, aiming for almost everything**, with both a module default and per-block
  tags.
- **A click** opens a sidebar REPL, loads the example and runs it. A `march>`
  transcript runs its expressions; prompts and expected outputs are dropped.
- **Examples share one session.** The sidebar header has clear and reset.
- **The REPL loads on the first click.** Nothing is fetched with the page.
- **Stdlib only for now.** Package docs on the registry (forgepm) are served with
  `script-src 'self'`
  (`forgepm/lib/forgepm/web/security_headers.march`, deliberately: package HTML is
  untrusted), so no external or inline script runs there. A sidebar REPL is impossible
  on those pages without weakening that policy. Packages get their own design later.

## Opting in (source)

- **Module default.** A line `-- doc: try` in a module's header comment. It covers that
  module's `march>` transcripts, which project 2's CI sweep already runs in the
  browser.
- **Per block.**
  - ` ```march try ` opts one block in; this is required for whole-program examples
    until project 4 checks them.
  - ` ```march norun ` opts a block out.
  - Indented blocks can't carry tags: they follow the module default; turn one into a
    tagged fence to override.
- **The marker is hidden** from the rendered page, the index blurb, the search index and
  the scroll notebooks (`Parser.module_comment`).
- **Initial rollout.** The 14 stdlib files that have `march>` examples and can run in a
  browser are marked (3 more are unavailable: Cluster, Dir, HttpServer).

## march_doc

- **Flags.** `forge doc --try-it [--site-base PATH]`; the march repo's forge passes
  both through to the `march_doc.doc` task. `scripts/gen-stdlib-docs.sh` passes
  `--try-it`. Without the flag, output is byte-identical to before (mode 0).
- **Markdown.** `Markdown.md_to_html_mode(md, mode)`:
  - 0: off;
  - 1: only ` ```march try `;
  - 2: also `march>` transcripts.

  A marked block is `<pre data-try="<code>" data-try-kind="transcript|program">`. A
  tagged fence keeps its `language-march` class and highlighting.
- **Page.** `DocHtml.render_module_try` appends `TryIt.panel(site_base)`: the sidebar
  (clear, reset, close, transcript, input), its CSS (theme tokens, both themes) and a
  script.
  - The script adds a "Try it" button to each `pre[data-try]`.
  - On the first click it loads `<site_base>/assets/march-repl.js`, creates a
    `MarchRepl` on the sidebar, and runs the example: one REPL input per transcript
    expression, or the whole program as one input.
  - No timestamps or random IDs, so regeneration stays byte-reproducible.
- **Found and fixed while building.** An attribute line (`@[assume]`,
  `@[trusted_linear(v)]`) between a `doc` and its `fn` made the parser drop the doc. 56
  stdlib declarations carry one (Set 14, Map 12, LinearMap 11, Array 7, ...), which is
  much of why the 2026-10-14 audit found Set and Map mostly empty.

## march repo

- **`docs/assets/march-repl.js`.**
  - Public `run(code)`.
  - A run queue, so inputs run strictly in order even while one waits on the
    interpreter or an on-demand module. A transcript sends several inputs at once.
    Previously `_loadBundle` kept only the last pending callback, so inputs submitted
    during the first load were lost.
  - A failed interpreter download now calls back, so waiting inputs report "Interpreter
    not available." instead of hanging the queue.
- **`stdlib/hash_map.march`.** Its six `march>` examples were flush with the prose, so
  they rendered as paragraph text. They are now indented as code.
- **Check.** `scripts/check-doc-try-it.js` replays every `data-try` example on the
  committed `docs/docs/stdlib/` pages through `scripts/browser-repl-node.js`, one session
  per page. It fails when:
  - an example errors, beyond the documented failures (panics) in
    `browser-repl-doc-sweep.js`;
  - a module on the "unavailable" list has a button;
  - there are no examples at all.

  It runs in CI (`browser-repl` job) and was shown red on an injected bad example and on
  a button on File's page.

## Merge order

`scripts/gen-stdlib-docs.sh` clones `march_doc`'s main branch, and the
`gen-stdlib-docs.yml` bot regenerates the pages after every stdlib merge. So the
`march_doc` change must merge first. Otherwise the bot regenerates the pages without
buttons, and `check-doc-try-it.js` then fails ("no Try it examples found").

## Non-goals

- Package docs (see above).
- Checking whole-program examples (project 4).
- Typechecking in the browser REPL.
