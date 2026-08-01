- ✅ **`collect_direct_names`' inner pattern walk is exhaustive** —
  `lib/desugar/desugar.ml`. #146 made `collect_direct_names`' outer `decl`
  match exhaustive with no wildcard, so that a newly-added *declaration* form
  is a compile error rather than a silent omission. Its inner `from_pat`
  (which decides, for a top-level `let`, which binders count as module
  members) still ended in `| _ -> []`, handling only `PatVar`, `PatTuple` and
  `PatCon` — so the guarantee stopped one level short and four of the nine
  `Ast.pattern` constructors were silently dropped.

  **Reproduces today via `PatRecord`.** The list feeds
  `strip_entry_self_qual`, so a member bound by a record-pattern `let` was
  invisible to the self-qualification rewrite — the bare spelling resolved and
  the self-qualified one did not, the same asymmetry the extern fix closed in
  #146:

  ```march
  mod Foo do
    let { port, host } = { port: 8080, host: "h" }
    fn main() : Int do Foo.port end   -- unbound variable: Foo.port
  end
  ```

  Note the failure surfaces at **eval**, not typecheck: `--check` on this
  shape exited 0 both before and after the fix. A `has_errors (typecheck …)`
  assertion would have been green on both sides and proven nothing, so the
  two regression tests in `test/test_compiler.ml`
  (`entry_mod_qual_erasure`) go through `eval_module` / `call_fn` and assert
  the returned value.

  **Pre-existing and latent.** Byte-identical before #146, and there are zero
  record-pattern top-level `let`s in the stdlib or the ecosystem — the tuple
  form that *is* used was already handled (pinned as a control). Fixed
  because the guarantee should mean what it says and because `add_pat_vars`,
  twenty lines below in the same file, is already a complete walk.

  `from_pat` now covers all nine constructors with no wildcard: `PatVar`,
  `PatCon`, `PatTuple`, `PatAtom`, `PatRecord`, `PatAs`, `PatOr`, `PatWild`,
  `PatLit`. (`PatOr` binds the same names in every alternative, so the first
  alternative suffices.) A future pattern form is now a compile error here.
