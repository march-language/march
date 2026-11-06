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

## Not done

- **Human `--check` output** still shows no fixes. Only the JSON, the editor and
  `forge fix` see them, and the one-turn metric's prompt (`--check` text) does not
  include them.
- **Only `--check-json` verifies.** The LSP computes diagnostics in-process and shows the
  tier the compiler declared, without re-checking. `--why-copies-json` and
  `--report-contracts` fixes are not verified either.
- **`unknown_attribute`** has no fix: the AST keeps no span for an attribute.
