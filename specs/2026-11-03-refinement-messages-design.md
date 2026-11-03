# Author-written messages on refinement conjuncts

Filed and built 2026-11-03. Item 6 of the OxCaml review (OxCaml's
`[@error_message]` on a kind or type constraint), reshaped for March.

## Why

A caller who breaks a stdlib bound reads the checker's notation:
`argument `n` of `List.nth` does not satisfy precondition `_ >= 0 && _ < len(xs)``.
They have to translate `_` to their argument and `len(xs)` to their list, and work
out which half they broke. The author of the function knows what each half means;
the diagnostic should say it in their words.

## Decisions (agreed with the user)

- **One message per `&&` conjunct**, so the caller is told which side they broke.
- **Syntax:** `{Int | _ >= 0 else "index must not be negative" && _ < len(xs) else "…"}`.
  `else` binds tighter than `&&`; a message is optional per conjunct; plain text,
  no interpolation; only top-level `&&` conjuncts.
- **Alongside, not instead of, the predicate:** the message leads, and the next line
  names the argument and the broken conjunct.
- **Stdlib:** the two-sided bounds get messages in the same change (`List.nth`,
  `Array.get`/`set`, the `Simd` lane accessors, `DateTime.fixed_zone`/`fixed_zone_hm`,
  `Random.bernoulli`, `Stats.percentile`/`quantile`/`quantile_default`).

## How it is built (implementer's calls)

- **AST:** a new `ERefineMsg (conjunct, message, span)` node, built only by the
  parser (`refine_pred` in `lib/parser/parser.mly`) at a top-level conjunct of a
  `TyRefine` predicate. Every expression traversal got the obvious recursive arm.
- **Stripped at desugar.** `Desugar.desugar_ty` removes every wrapper
  (`March_ast.Refine_msg.strip`) and records the message in a table keyed by the
  conjunct's span. No pass after desugar sees the node, so no predicate reasoning
  had to change: a missed case there would silently weaken a proof.
- **Staleness:** the first time a desugar pass meets a predicate from a file, the
  file's older entries are dropped (an editor re-checking a file after the author
  deleted a message).
- **The stdlib AST cache stores desugared decls**, so it stores the stdlib's table
  entries beside them (`bin/toolchain.ml`, `Refine_msg.entries_for`/`restore`); its
  key includes the compiler build, so the blob's new shape cannot be misread.
- **Violation:** when a conjunct of the refuted predicate carries a message, each
  messaged conjunct is discharged on its own (`refuted_messages` in
  `lib/refinecheck/refine_call.ml`); the refuted ones lead the message. A predicate
  with no messages costs no extra solver query, and a call that breaks only the
  conjunction falls back to today's text.
- **Unproven call:** `Partial_conjunct` gained `messages`, rendered after the
  missing conjuncts.
- **Unchanged:** verdicts, the `--refine-audit` comparison (`pred_str` prints a
  wrapped conjunct as the conjunct), IR (predicates are never lowered).

## Not done

- Messages on postconditions are parsed and stripped like any other, but no
  postcondition diagnostic quotes them yet.
- No interpolation of the offending value into the message.
- The source label under the argument still quotes the whole predicate.
