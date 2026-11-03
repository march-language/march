`[P2]` Diagnostics for capabilities (specs/plans/2026-11-02-diagnostics-depth-plan.md §F1),
filed 2026-11-02, landed 2026-11-03.

Was: passing `Cap(IO.Console)` where `Cap(IO.FileRead)` is needed was a plain `type_mismatch`
plus `cap_grant_exceeded`; IO in an actor handler named neither the handler nor `println`; one
missing authority gave up to three reports.

Landed:

- **`cap_mismatch`** (new code). `Typecheck_unify.report_mismatch` routes a mismatch between two
  IO-lattice capabilities whose provided expression is the capability value to
  `report_cap_mismatch`: "`read` needs file-read access, but `c` is the console capability.",
  one lattice line from `Cap_lattice.relation` (siblings under their least common ancestor,
  contains, contained-by), and a help line. The site is recorded in `env.cap_mismatch_sites`;
  `Typecheck.refine_cap_mismatches` (end of module, before the grant check) names the callee
  and attaches the fix: `cap_narrow(c)` when the passed capability contains the needed one,
  otherwise, for a call in `main`, a new `_cap_x : Cap(X)` parameter on `main` passed to the
  call (or `main`'s existing `Cap(X)` parameter). A call outside `main` keeps the help line and
  no fix (threading through every caller is not mechanical).
- **Named context.** `Typecheck_caps.check_module_needs` carries each body use's subject (a
  function, "the `Inc` handler of actor `Counter`", a module-level `let`): the missing-`needs`
  error reads "the `Inc` handler of actor `Counter` prints, but module `Main` declares no `needs
  IO.Console`." at the call, other capabilities' first uses as labels. A Check-1 error
  (`Cap(X)` in a signature) moves to a body use it covers, with the signature as a label.
  `role_grant_exceeded` points at the call with a span trace inside the callback
  (`cap_chain_trace ?root`): "the body of role `Cons` writes a file, but the role is granted
  only `Cap(IO.Console)`", labels on each hop, the callback and the `role … needs` line, and a
  fix appending the capability to that line. Verbs/nouns per lattice node live in
  `Cap_lattice.{access,action,the_capability}`.
- **One report per missing authority.** `check_main_grant` folds `cap_grant` (no grant) and
  `cap_grant_exceeded` into a use-site `cap_needs` error for the same capability, and
  `cap_grant_exceeded` into a `cap_mismatch` that threads the capability; the
  `cap_needs:X` of the callee's signature folds into the `cap_mismatch`. The merged error keeps
  the other's span as a label and both edits as one fix: new `Errors.FMulti` /
  `{"kind":"multi","edits":[…]}` in `--check-json`, applied by `forge fix`, the LSP quick fix
  and `test/run_errors.ml` (all now sort edits by line, then column). A standalone
  `cap_grant_exceeded` gains a fix (one more `main` parameter).
- Corpus: `test/errors/cap_mismatch_{1,2,3}` (siblings, contains, contained-by),
  `cap_needs_9` (actor handler, merged needs + grant), `cap_needs_10` (merged needs +
  too-narrow grant); every fix applies to `exit 0`.

Deferred: the `--explain` pages for the capability codes (item 5, a sibling session),
`cap_root_broad`'s "this field / this type" wording (item 6).
