# Landing page: wrong claims fixed, every doc page linked (2026-10-13)

`docs/index.md` (the site root) made five claims the chapters now contradict, and its
Documentation table linked 24 of the 44 pages.

Claims fixed:
- "spawn them, link them, monitor them" and the Actors row's "linking": there are no actor
  links (the actors chapter's "Why there are no links"); the fault model is monitors plus
  supervisors. Now "spawn them, monitor them".
- Session types "including that neither side will deadlock" / "deadlocks caught at compile
  time": the chapter's guarantees list a no-scheduler gap (two sides driven in the wrong
  order deadlock at runtime). Now states what is caught: non-dual protocols, a send out of
  turn, a closed channel, an unhandled branch. Choreography is mentioned beside it.
- "Structured concurrency via `Task(a)` and `Future(a)`": no `Future` module exists. Now
  names `Task.async`, `await_many`, `race` and `scope`.
- Restart strategies spelled `OneForOne` etc.; now `one_for_one` as in the language.
- The FBIP benchmark table now links `bench/tree_transform.march` and `bench/RESULTS.md`.

The Documentation table is regrouped (Start here, The language, Safety at compile time,
Concurrency, Distribution and operations, Tooling, Upgrading) and links every page in
`docs/` except the Tetris demo embed: 20 pages were previously unreachable from the
landing page, including hot code reload, observe, topology, cluster certificates,
capability enforcement and audit, LSP, property testing, sigils and parsing. The
"Concurrency" feature list gains choreographies and hot code reload. "What makes March
different" is untouched in this change.
