Diagnostics: fix applicability tiers and emit-time fix verification (2026-11-06)

Background: the error-message literature survey (`reports/Compiler error message research.md`,
not committed) ranked "confidence tiers on fixes" third, after rustc's `Applicability` and
PyFiXV's validate-before-show. A wrong fix that looks certain does harm; the one-turn log
(`2026-11-02-diag-one-turn-metric.md`) has two examples.

## What landed

- **The tier.** `Errors.applicability` = `Machine_applicable | Has_placeholders |
  Maybe_incorrect`. A diagnostic's `fix` is now `fix option`, a record `{ edit : fix_kind;
  tier }`. `Errors.fix ?tier edit` builds one; the default tier is machine-applicable.
  `fix_opt` maps over an option, and `merge_fixes` combines two diagnostics' fixes at the
  weaker tier. `--check-json` prints the tier as `"applicability"` inside the fix object,
  after the edit's own fields, so an older reader still parses the edit.
- **Verification (`bin/fix_verify.ml`).** Before `--check-json` prints its diagnostics, every
  machine-applicable fix on an error or warning is tried:
  - All of them are applied to a copy of the source (`Errors.apply_edits`, `forge fix`'s
    semantics plus multi-line replace). The copy is checked by a child run of the same
    executable with the same arguments plus `--fix-verify-source TMP`, which reads the text
    from TMP but keeps the file name, so sibling modules and `MARCH_LIB_PATH` resolve as
    before.
  - The batch passes when, for every error/warning code, its count after is at most its
    count before minus the fixes for that code. Hints are ignored: `needs IO` draws a
    "narrow this" hint.
  - If the batch fails, up to 8 fixes are tried one at a time. A fix passes when its own
    code's count drops and no other code's count rises. Failures, and any fixes past 8,
    become `maybe-incorrect`.
  - Counting codes rather than spans tolerates the corpus's programs with two independent
    mistakes, and the line shifts an insert or delete causes.
  - A parse error is verified in-process (`Fix_verify.verify_parse`): the patched source
    must parse, or its first error must start after the lines the fix touched.
  - `MARCH_FIX_VERIFY=0` turns verification off; the child run sets it.
  - Cost: one extra check when there are fixes, ~1.2 s on a corpus program.
- **Consumers.**
  - `forge fix` applies only machine-applicable fixes; a fix with no tier counts as one.
  - The LSP generic quick-fix adapter sets `isPreferred` only for machine-applicable fixes,
    and labels the others "(a guess: check it)" or "(fill in the placeholder)".
  - The golden corpus shows the tier in each `fix [code] (tier):` header, and applies only
    machine-applicable fixes for its `after fix:` line.
  - The corpus's fix gate accepts a parse fix that uncovers later errors.
- **New fixes:**
  - `unbound_variable` and `unknown_qualified_name`, when the message suggests one name.
    `Typecheck_env.qualified_fix` handles a misspelt module, or a member with one public
    export within edit distance 2.
  - `unknown_constructor` with one suggestion (`unknown_ctor_fix`). The edit covers only
    the name (`name_only`), not the arguments.
  - `unknown_record_field`, on both field access and record update.
    `field_guess_tier` makes it maybe-incorrect when another field is as close.
  - `codec_missing`: `derive Json for T` inserted after `T`'s declaration, when it is in
    the same file.
  - `let?` / `let*` with a type annotation: the annotation is deleted, up to the `=`
    (`Parse.annotation_fix`).
  - `non_exhaustive_match`: the first missing case inserted after the last arm, with body
    `todo("handle <case>")`, at tier has-placeholders. Not offered for list cases, whose
    printed form names internal constructors.
- **Corpus:**
  - 138 of 414 programs carry a fix, up from 123. In 132 the fix is machine-applicable.
  - Five fixes are maybe-incorrect:
    - `extern_needs_foreign` in a `cap no_extern` module, where verification caught that
      the fix makes it worse;
    - `clsoe` -> `close`, which uncovers a real `linear_used_twice`;
    - two `unknown_constructor` fixes;
    - `conut` with fields `cont` and `count`.
  - Three fixes have placeholders.
  - `no_extern_violation_1`'s stale `EXPECT-FIX-PARTIAL` marker is removed. It was the last
    line of the file, so no line numbers moved.

## Follow-up the same day: fixes in the text output, re-checked in the editor

- **`--check` text.** `Errors.render_fix_block` renders a diagnostic's fix under it (after
  its labels, before the explain pointer) as the lines it changes: `N - old`, `N + new`,
  and for an insert the line it follows (`N | ...`). The heading names the tier:
  - "fix (`forge fix` applies it):";
  - "fix, with a placeholder to fill in:";
  - "possible fix (a guess: check it before applying it):".

  Under `--check`, the driver runs `Fix_verify.verify` before printing, so the text shows
  the tier `--check-json` would print. A parse error goes through `verify_parse`.
  Builds and runs show the declared tier: re-checking would mean rerunning a compile.
  The child run is always given `--check-json`, since its codes are read from that.
- **Golden corpus.** The `.expected` files no longer append the runner's own diff of
  each fix: the rendered output carries it. The `.json.expected` files still pin each
  edit.
- **Editor.** `Code_actions_diag.fix_holds` applies a machine-applicable fix's text edits
  to the buffer and runs `Analysis.analyse` on the result. It uses the same rule as
  `Fix_verify`'s individual check. A fix that fails is offered as "(a guess: check it)"
  and is not preferred.
  - `analyse` is reached through the `reanalyse` ref, which `Analysis` sets after
    `include Code_actions_diag`.
  - Verdicts are cached by the patched text's digest, so moving the cursor does not
    re-check again.
  - The re-analysis refreshes the checker's global tables for the patched text; the
    server re-analyses the real buffer on its next change.
  - Tests are in `lsp/test/test_lsp_actions.ml` ("fix tiers"): `fn _ -> 42` stays
    preferred; `clsoe` -> `close` is demoted because it uncovers `c` used twice.

- **One-turn metric** (`scripts/error-one-turn.sh`, Haiku): 375/400 (93.8%), 14 intent,
  11 rejected. The previous run was 377/400.
  - Showing the fix changed the prompt of 137 cases. Their answers to unchanged prompts
    were carried over. Those 137 cases already passed 133 times before and 131 now.
  - Two cases got worse:
    - `cap_grant_27` became intent;
    - `cap_grant_32` became rejected.
  - One improved: `cap_root_broad_2` went from rejected to intent.
  - In `cap_grant_32` the model applied the shown grant fix both times and differed only
    on the program's second, unrelated error (`MPST.new`'s result).
  - So in a single run the change is within noise. The cases that carry a fix were already
    near the ceiling, since the notes describe most fixes in words.

## Not done

- `--why-copies-json` and `--report-contracts` fixes are not re-checked.
- **`unknown_attribute`** has no fix: the AST keeps no span for an attribute.
