# March Compiler Error Audit

**Date:** 2026-04-10  
**Phases audited:** lexer, parser, desugarer, typechecker, eval

---

## Summary

The March compiler has a solid error infrastructure (`lib/errors/errors.ml` — diagnostic types, span-tagged messages, recovery contexts) and the typechecker uses it well. However, several phases have gaps: the desugarer uses raw `failwith` (crashes with no span), some errors are silently swallowed, and a handful of programmer mistakes aren't caught at all.

---

## Findings by Phase

### Desugarer (`lib/desugar/desugar.ml`)

#### 1. `check_app_main_exclusivity` — `failwith` with no span [HIGH]
**Line:** 1335  
**Problem:** If a module defines both `main()` and `app Name do...end`, the compiler crashes with a raw OCaml `Failure(...)` exception. The message gives no file/line info and hits users as `Fatal error: exception Failure(...)`.  
**Fix:** Extract spans from the offending declarations and include file+line in the message (or raise a `ParseError`).

#### 2. `expr_to_pat` in pipe-to-match desugaring — `failwith` with no span [MEDIUM]
**Line:** 416  
**Problem:** `x |> match do (1+2) -> ... end` — if the LHS of a cond arm can't be converted to a pattern, the compiler crashes with a raw exception that omits the source location.  
**Fix:** Pass the enclosing `EPipe` span to the function and include it in the error.

#### 3. Unknown `derive` interface silently skipped [HIGH]
**Line:** 1306  
**Problem:** `derive SomeMisspelledInterface for MyType` produces no error and no impl — the derive silently generates nothing. Users have no indication that their derive had no effect.  
**Fix:** Check the interface name against the known set (`Eq`, `Show`, `Hash`, `Ord`, `Json`) and emit a `ParseError` or typechecker error with the span.

#### 4. `expand_derive` — type not found silently skipped [MEDIUM]
**Line:** 1317  
**Problem:** `DDeriving` with a type name that doesn't exist in the module silently produces nothing. This can happen during incremental editing and is confusing.  
**Fix:** Emit a warning/error if the derived type is not in scope.

---

### Typechecker (`lib/typecheck/typecheck.ml`)

#### 5. Duplicate variant names in a type definition — not checked [HIGH]
**Lines:** 4097–4108 (`DType` / `TDVariant` handling)  
**Problem:** `type Color = Red | Red | Blue` — the second `Red` is silently deduplicated by `add_ctor` (which no-ops if `ci_type` already exists) with no diagnostic. The user gets no error and may be confused why one constructor seems to vanish.  
**Fix:** Before calling `add_ctor`, check if the constructor name is already in the type's variant list and emit an error with the duplicate's span.

#### 6. Duplicate record field names — not checked [HIGH]
**Lines:** 4109–4122 (`DType` / `TDRecord` handling)  
**Problem:** `type Point = { x: Int, x: Float }` — the duplicate field is silently added to `field_pairs` as a list. Record lookup will always find the first entry, so the second declaration is unreachable with no diagnostic.  
**Fix:** Check for duplicate field names when building `field_pairs` and emit an error with the offending span.

#### 7. Non-exhaustive pattern match — message already decent, could list all missing cases [LOW]
**Lines:** 2317–2323  
**Problem:** The exhaustiveness checker reports the first missing example (`"Non-exhaustive pattern match — missing case: %s"`). For enum-like types it's fine; for complex types users might want all missing constructors listed.  
**Status:** Low priority; the current message is actionable.

#### 8. `multi-param superclasses not yet supported` — silent [LOW]
**Line:** 4502 (approx)  
**Problem:** A `when` clause with multiple type params silently does nothing. This is a known limitation but produces no diagnostic.

---

### Eval (`lib/eval/eval.ml`)

#### 9. Actor message silently dropped when actor is dead [LOW]
**Lines:** 5650–5651  
**Problem:** Sending a message to a dead/killed actor silently returns `None`. In a debug build, a runtime warning would help diagnose actor lifecycle bugs.  
**Status:** Runtime behavior; not a compile-time issue. Low priority.

#### 10. No handler for message type — silently dropped [LOW]
**Line:** ~5863  
**Problem:** If a message is sent to an actor that has no matching handler, the message is silently dropped. A runtime warning would surface mismatch bugs.  
**Status:** Runtime behavior; low priority.

---

### Lexer (`lib/lexer/lexer.mll`)

#### 11. Unterminated string/comment errors lack position [LOW]
**Lines:** 163, 174, 190, 204, 217, 233  
**Problem:** `raise (Lexer_error "Unterminated string literal")` — the span is available from `lexbuf` but not included in the exception. The parser's `ParseError` renderer already extracts position from `lexbuf`, so these are effectively okay as-is.  
**Status:** The `render_parse_error` function uses `lexbuf` directly, so position is recoverable. Low priority.

---

## Priority Matrix

| # | Issue | Impact | Effort | Phase |
|---|-------|--------|--------|-------|
| 5 | Duplicate variant names | HIGH | Low | Typecheck |
| 6 | Duplicate record fields | HIGH | Low | Typecheck |
| 3 | Unknown derive interface | HIGH | Low | Desugar |
| 1 | app+main `failwith` | HIGH | Low | Desugar |
| 2 | `expr_to_pat` `failwith` | MEDIUM | Low | Desugar |
| 4 | Derive type-not-found | MEDIUM | Low | Desugar |
| 7 | Exhaustiveness message | LOW | Medium | Typecheck |
| 8 | Multi-param superclass | LOW | High | Typecheck |
| 9 | Dead actor message drop | LOW | Low | Eval (runtime) |
|10 | No handler message drop | LOW | Low | Eval (runtime) |
|11 | Lexer unterminated errors | LOW | Low | Lexer |

---

## Fixes Implemented

The following were fixed in this pass (run `dune runtest` to verify):

- **[5]** Duplicate variant names → error with span on the duplicate
- **[6]** Duplicate record field names → error with span on the duplicate
- **[3]** Unknown derive interface → error with the span of the interface name
- **[1]** `check_app_main_exclusivity` → reports file+line instead of crashing
- **[2]** `expr_to_pat` → passes the pipe's span to the error message
