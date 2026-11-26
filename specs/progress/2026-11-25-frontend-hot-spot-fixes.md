# Four front-end hot spots replaced by tables (2026-11-25)

Profiling hello world's `typecheck` and `lower` stages (the refinement checker runs inside
`typecheck`) showed four places that redid a whole scan per item. Each now builds a table
once. No diagnostic, emitted IR or hash changes.

## The four

1. **`Lower_decls.rename_tir_vars`** (`lib/tir/lower_decls.ml`). Every variable occurrence in
   a module's functions was tested with `List.mem v_name names`, where `names` is all of the
   module's function names (hundreds for a stdlib module). `names` is now loaded into a
   `Hashtbl` once per call.

2. **`Refine_reflect.install`, the three span readers** (`lib/refinecheck/refine_reflect.ml`:
   `source_of`, `span_text`, the contract hash's head text). Each had its own local
   `offset (line, col)` that walked the file text from byte 0 counting newlines, for both
   ends of every unit's span. One `line_start` now keeps, per file, an array of the byte
   offset at which each line starts. It answers as the scan did: `Some 0` for a line `<= 1`,
   `None` for a line with fewer than `line - 1` newlines before it (so the callers still
   give `None` / `""`), and the offset just past the final newline for the line after it.

3. **`Solver.identity`** (`lib/refine/solver.ml`), called by `Vc_cache.key_of_vc` for every
   VC key. Each call ran `find_z3` (a `realpath` of the executable, a scan of `PATH`) and a
   `stat`; about 23 microseconds here with z3 the 28th-or-earlier `PATH` entry. The last
   answer is now kept together with everything it was computed from, and is served only
   while all of it reads the same: `MARCH_Z3`, `PATH`, both rlimit refs, the chosen binary's
   size, mtime and mode, and the candidates `find_z3` passed over before choosing it (the
   bundled path and earlier `PATH` entries), none of which may have become executable. A
   hit costs two `getenv`s, one `stat` and one `access` per passed-over candidate.
   `clear_probe_memo` clears it too. "No usable z3" is never kept. `identity` no longer goes
   through `health ()`; it reads `find_z3` and `probe_version` directly, which is the same
   mapping (Healthy and Mismatch are "found, and the probe returned a version").

   Not in the key: the symlink chain of the running executable (it decides the bundled
   path), and `XDG_CACHE_HOME` / `HOME` (where `probe_version` keeps its disk cache; they do
   not change the version a given binary reports). A binary rewritten with the same size,
   mtime and mode is not noticed, as `probe_version`'s own memo already did not.

4. **Lemma handling in `Refine_check.check_module_pass`** (`lib/refinecheck/refine_check.ml`).
   Per `@[lemma]`, the manifest digest filtered all of the termination graph's call sites
   by source unit and all predicate sites by file, and the L4 check scanned every unit for
   one with the lemma's span that is recursive and recomputed `lemma_fns_q` over the whole
   program (twice more for `lemma_defs`). Now: call sites are indexed by source unit and
   predicate sites by file, both filled back to front so `Hashtbl.find_all` returns list
   order (the result only feeds a `sort_uniq`, but the order is kept anyway); the spans of
   recursive units are collected once, lazily, into a table; the L4 loop and `lemma_defs`
   use the `lemmas_q` already computed above them. The `f == fd` lookup is unchanged: the
   list holds the same physical `fn_def`s, since `m` is not rebound in between.

## Measured

Hello world (`needs IO.Console`, one `println`), `--emit-llvm --opt 2 --timings`, warm
caches, private `HOME`, a different unreachable `pfn probe_N` per run so the source-level
cache misses; 9 runs each, alternating a build of `ff07e1a20` (origin/main) and this tree.
Load average at the time: 6.5. Medians:

| stage | before | after | change |
|---|---|---|---|
| typecheck (after stdlib-load) | 0.854 s | 0.737 s | -117 ms |
| lower | 0.344 s | 0.269 s | -75 ms |
| total to the last stamp (`alloc-contract`) | 1.320 s | 1.125 s | -195 ms |

`--emit-llvm` returns before the CAS path, so it prints no `cas-hash` stamp; the total is
to the last stage it does print. Every one of the 9 pairs showed the saving (smallest
0.179 s, largest 0.225 s).

## How it was checked

- `scripts/oracle-base.sh ir refine types` against the merge-base `ff07e1a20`: IR identical
  across 531 programs, refinement diagnostics identical (13,005 lines over 619 fixtures),
  types identical.
- The ir oracle goes red on a perturbation of fix 1 (the name table made to miss every
  four-letter name): `IR CHANGED — 148 differing lines`.
- **None of the three oracles sees fix 2.** With the line table deliberately off by one
  byte, `scripts/oracle-base.sh refine ir` still printed `REFINEMENT DIAGNOSTICS IDENTICAL`
  and `IR IDENTICAL`: the text the table cuts out only feeds the D17 logic hashes and the
  contract hashes, which neither diagnostics nor IR carry. It was therefore checked on the
  outputs that do print those hashes, comparing a build of `ff07e1a20` with this tree, each
  under a private `HOME`:
  - `--emit-llvm --dump-impl-hashes` over 111 programs (every fourth `test/native` fixture
    and three stdlib modules): 3,117 definitions, 331 with a logic hash, byte-identical.
    The off-by-one build changes all 331.
  - `--check --reflect-deps` and `--check --emit-lemma-manifest` over 36 programs (the
    `@[reflect]` / `@[lemma]` fixtures among them): 5,934 lines, 345 hash lines,
    byte-identical. The off-by-one build changes all 345. The lemma manifest lines also
    cover fix 4's digests.
- The new line table against the old scan on 960,000 random (text, line) pairs, lines from
  -2 to past the end: equal on all.
- **Not done when this was committed:** `scripts/run-tests.sh compiler eval codegen stdlib`
  and `scripts/run-tests.sh refinecheck`. The machine went to sleep during `run_compiler`
  (about 225 cases in, none failing) and the run had not finished. Run both, and
  `test/test_refine.exe` and `test/test_z3_lookup.exe`, before merging: `test_refine`'s
  `key_changes_with_version`, `key_changes_with_rlimit` and `key_has_no_path` are the cases
  that swap z3 and move the rlimit inside one process, which is what fix 3's memo key has
  to survive.
