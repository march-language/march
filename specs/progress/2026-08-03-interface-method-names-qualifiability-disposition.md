# Interface method names — disposed as won't-fix, with a bounded consolation diagnostic

**Filed:** 2026-07-31 · **Disposed:** 2026-08-03 (task 7 of the
refinement-followups-seven plan).

## Background

`Foo.speak(x)` never resolves — for a nested module or the entry module
alike — when `Foo` declares `interface Speak(a) do fn speak : a -> String
end` and dispatches `speak` via `impl Speak(...)`, because dispatch resolves
the bare method name, not a module-qualified member. The original todo
(`specs/todos/2026-07-31-interface-method-names-not-module-qualifiable.md`,
now folded into this file) documented that making it work needs interface
methods to become qualifiable in general — a dispatch-side change — and that
the naive fix (folding method names into
`Desugar.collect_direct_names`, which feeds `strip_entry_self_qual`) was
**already tried and measured to regress working code**: it made
`qualify_module_refs` rewrite a bare `greet(1)` inside the declaring module
into `Bar.greet(1)`, breaking it. That door stays closed.

The todo also flagged a landmine: `accept/t126` and `accept/t127` pin
`stdlib_member_defs_ok`'s entry-module walk start using an `interface`/`impl`
competitor *specifically because* `strip_entry_self_qual` does not rewrite
method names. Touching `collect_direct_names` again would silently re-vacuate
both witnesses.

## Step 1 — measuring the exposure

- `grep -rn "^\s*interface " stdlib/*.march` → **zero matches**. The
  standard library declares no interfaces at all, so no stdlib call site can
  hit this shape.
- The compiler's own test corpus (`specs/lang/types/accept|reject/`,
  `test/native/`, `examples/`) declares interfaces in ~30 files, confirming
  the language feature itself is exercised, but none of those write the
  broken `Mod.method(...)` qualified-call shape — they all call bare, which
  is the working spelling.
- Reproduced the gap directly against unmodified source (required per this
  plan's "verify before implementing" rule, since two earlier tasks in this
  plan turned out to already be fixed by a prior PR): a hand-written probe
  (`interface Speak(a) do fn speak : a -> String end`, `impl Speak(Dog)`,
  called as `Probe.speak(Dog("Rex"))`) still fails with a bare
  `unbound variable: Probe.speak` on `./_build/default/bin/main.exe`
  (pre-fix), confirming the gap is real and unchanged since the todo was
  filed. `--check` (typecheck-only) passes silently on the same file — the
  typechecker's own suffix-stripping fallback (`qualified_error_msg` /
  `try_suffix` in `lib/typecheck/typecheck.ml`) accepts the qualified spelling
  because *some* suffix resolves to *some* known name (the interface method's
  bare scheme), so the failure surfaces only at eval time, with no span and
  no note.

**Conclusion:** stdlib exposure is zero, but the shape itself (a user
declaring their own interface and reasonably trying to call it qualified
from outside, an easy mistake coming from OOP-style languages) is real and
reachable, and the resulting error today gives no hint toward the fix. That's
enough audience to justify the bounded diagnostic from Step 2, short of
attempting real qualifiability.

## Step 2 — the bounded diagnostic (shipped)

Added `interface_method_hint : module_ -> string -> string option` in
`lib/eval/eval.ml` (near the `Eval_error`/`Match_failure` exception
declarations, ahead of `lookup`, whose `strip_lookup` fallback is the exact
site that raises this class of error). Given the desugared top-level module
and the raw `Eval_error` message, it:

1. Matches the message against the literal `"unbound variable: "` prefix
   used only by `lookup`'s terminal fallback (`eval.ml`, `strip_lookup`);
   anything else (a non-dotted name, a different error entirely) yields
   `None` unchanged.
2. Splits the dotted name into a module path and a trailing member name, and
   walks every module in the program (the top-level module and every nested
   `DMod`, recursively) whose own name matches either the full path or its
   last segment — mirroring `strip_lookup`'s own left-to-right stripping so
   the hint fires exactly where the runtime lookup itself would have found a
   match if qualification worked.
3. For a matching module, checks whether it declares a `DInterface` whose
   `iface_methods` contains the member name. If so, returns a note naming
   the interface, the declaring module, and the working bare-call spelling;
   otherwise `None`.

`bin/main.ml`'s `Eval_error` catch site (previously a bare
`Printf.eprintf "%s\n" msg`) now appends this note when present, e.g.:

```
unbound variable: Probe.speak
note: `speak` is a method of interface `Speak` declared in module `Probe` — interface methods aren't module-qualifiable (dispatch resolves the bare name, not the qualified one). Call it as `speak(...)` instead of `Probe.speak(...)`.
```

This is diagnostic-quality only — it does not change what resolves, does not
touch `Desugar.collect_direct_names` or `strip_entry_self_qual`, and carries
none of the landmine risk of the full fix. `accept/t126`/`accept/t127`
required no re-verification since neither `desugar.ml` function was touched.

**Scope note:** the note fires for the interpreter's `Eval_error` path only
(the default `march file.march` invocation), which is the path that
surfaces this gap today (`--check` passes silently, and a `--compile` build
fails at the link stage with a different, `Undefined symbols` error, out of
scope for this bounded fix).

## Full qualifiability remains open

Making `Foo.speak(x)` actually resolve needs interface methods to become
first-class qualifiable members — a dispatch-side redesign of how
`impl_tbl`/interpreter dispatch relates to module-qualified lookup, not a
classification tweak in `collect_direct_names`. That's a substantially larger
change than this task's scope, and the one attempt at a shortcut (teaching
`collect_direct_names` about method names) is on record as measured to
regress working code. Any future attempt must budget for a genuine dispatch
change and must re-verify `accept/t126`/`accept/t127` by mutation (revert the
entry-module walk start to `go false`, confirm both still reject with the
false `len(_) > 0` violation) before landing.

## Tests

`test/test_compiler.ml`, group `interface_method_qualifiability`:

- `Mod.method for an interface method gets a hint` — reproduces the exact
  `Probe.speak(Dog(...))` shape, asserts the base `Eval_error` message is
  unchanged (`"unbound variable: Probe.speak"`) and that
  `interface_method_hint` returns a note naming the interface, the declaring
  module, and the bare-call spelling.
- `genuinely unbound dotted name gets no hint` — control: a dotted name with
  no matching interface/method anywhere in the program must get `None`, not
  a spurious note.

## Verification

- `dune build --root . bin/main.exe test/run_compiler.exe` — exit 0.
- `./_build/default/test/run_compiler.exe -e` — 643 tests run (641 + 2 new),
  all green, including the manual probes reproducing the pre-fix gap and the
  post-fix note text (top-level and nested-module cases).
- `dune build --root . @types-check` — exit 0.
