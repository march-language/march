# Elm-like Compiler Error/Warning Improvements

**Date:** 2026-06-22  
**Status:** Spec — not yet implemented  
**Priority order:** Listed highest-to-lowest impact relative to effort.

---

## 1. Render secondary labels in `render_diagnostic`

### Problem

`diagnostic` carries a `labels : label list` field with secondary source spans
and messages (defined in `lib/errors/errors.ml:16-24`). The typechecker already
populates them — e.g., type mismatch errors produce a label `"the expected type
comes from here"` pointing at the annotation or binding that required the type
(`lib/typecheck/typecheck.ml:1888-1900`). But `render_diagnostic`
(`lib/errors/errors.ml:76-127`) ignores the `labels` field entirely. They are
generated and then silently dropped.

### What to build

Extend `render_diagnostic` to render each label as an additional source snippet
below the primary span, formatted identically to the main snippet but with the
label message as a secondary header line:

```
-- ERROR -------------------------------------------------- foo.march

I found a type mismatch.

14 | let x : String = 42
                      ^^  expected `String` but got `Int`

    The expected type comes from here:

10 |   fn greet(name : String) : String do
                         ^^^^^^
```

**Formatting rules:**
- Emit a blank line, then `    <lbl_message>:`, then blank line, then the
  gutter + source line + underline — same format as the primary span.
- Omit a label if its span is identical to the primary span (avoids doubling).
- Omit a label if `lbl_span.start_line <= 0` (no source info).

**Files to change:**
- `lib/errors/errors.ml` — `render_diagnostic` only. ~20 lines added.

**Tests:**
- Existing `test/run_compiler.exe` cases covering type annotations should show
  the secondary span once this lands (no new test input needed; output
  expectations need updating).
- Add a dedicated case: a function with an explicit return type annotation that
  returns the wrong type — verify the annotation line is underlined with the
  label message.

---

## 2. Per-arm span labeling for `if`/`match` branch type mismatches

### Problem

When the `then` and `else` branches of an `if` have incompatible types, the
error span is the entire `if` expression and the message is the generic type
mismatch headline. The user has no idea which branch is "wrong" relative to the
other.

Same issue in `infer_match` (`lib/typecheck/typecheck.ml:4008`): every arm is
checked against a shared `result_ty`; when arm N mismatches, the error span is
the whole `match` span.

### What to build

**`if` expressions** (`lib/typecheck/typecheck.ml`, `EIf` case):

1. Infer `t_then` from the `then` branch.
2. Infer `t_else` from the `else` branch.
3. Call `unify` with `span = else_branch_span` (not the whole `if` span).
4. Pass `~reason:(Some (RIfBranch (then_span, t_then)))` — a new reason variant
   that points at the `then` branch and captures its type.

The `report_mismatch` function already converts `reason` into a secondary label
via `span_of_reason`. Adding `RIfBranch` lets it generate:

```
-- ERROR -------------------------------------------- example.march

The two branches of this if expression return different types.

12 |       else
13 |         42
              ^^  this branch has type `Int`

    The then branch has type `String`:

10 |       "hello"
            ^^^^^^^
```

**`match` expressions** — same pattern: check each arm's body at `br.branch_body`
span, and pass a reason that points at the _first_ arm as the source of the
expected type. New reason variant: `RMatchFirstArm of span * ty`.

**New reason variants to add** (in the `reason` type near
`lib/typecheck/typecheck.ml:1760`):
```ocaml
| RIfBranch   of span * ty   (* then-branch span + its type *)
| RMatchFirstArm of span * ty (* first-arm span + its type *)
```

Update `string_of_reason`, `span_of_reason`, and `report_mismatch` accordingly.

**Files to change:**
- `lib/typecheck/typecheck.ml` — `EIf` infer case, `infer_match`, reason type
  and its handlers.

**Tests:**
- Add cases: `if true do 1 else "a" end` — expect error at `else` arm span
  with note pointing at `then` arm.
- Match with arms of different types — same.

---

## 3. Arity mismatch includes the function definition span

### Problem

Line 3482: `"Function foo expects 3 arguments, but got 1. March has no partial
application."` — correct, but gives no pointer to _where_ `foo` is defined or
what its full signature looks like. The user has to search for the declaration.

### What to build

Store the definition span alongside the arity count in `env.fn_arities`.

**Current:**
```ocaml
fn_arities : int StrMap.t
```

**New:**
```ocaml
fn_arities : (int * span) StrMap.t   (* arity × definition span *)
```

Update all sites that write `fn_arities` (pass-1 pre-registration and
`check_decl`'s `DFn` handler) to include `fn_span`.

In the arity-error branch (line 3479-3491), produce a `report` call with a
label on `def_span`:

```
-- ERROR -------------------------------------------- example.march

Function `process` expects 3 arguments, but I got 1.
March has no partial application — supply all arguments at once.

27 |   process(x)
      ^^^^^^^^^^^

    Defined here with 3 parameters:

 4 | fn process(input, options, callback) do
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

**Files to change:**
- `lib/typecheck/typecheck.ml` — `fn_arities` type, all write sites, error
  reporting site.

**Tests:**
- Call a 3-arg function with 1 arg — verify definition line appears in output.

---

## 4. Record field access — fuzzy name suggestion

### Problem

Line 3740: `"This record does not have a field called X. The fields I see are:
a, b, c."` lists all fields but does not suggest the closest match. A typo like
`rec.lenght` gets no "did you mean `length`?" guidance.

### What to build

After computing the flat list of known field names, run the same
`edit_distance` check used by `suggest_var_in_scope`
(`lib/typecheck/typecheck.ml:685`) and `qualified_error_msg` (line 725).

Replace:
```ocaml
(Printf.sprintf
   "This record does not have a field called `%s`.\n\
    The fields I see are: %s"
   name.txt
   (String.concat ", " (List.map fst flds)));
```

With:
```ocaml
let suggestion =
  List.find_opt (fun (fn, _) ->
    edit_distance
      (String.lowercase_ascii name.txt)
      (String.lowercase_ascii fn) <= 2
  ) flds
in
let did_you_mean = match suggestion with
  | Some (fn, _) ->
    Printf.sprintf " Did you mean `%s`?" fn
  | None -> ""
in
(Printf.sprintf
   "This record does not have a field called `%s`.%s\n\
    The fields I see are: %s"
   name.txt did_you_mean
   (String.concat ", " (List.map fst flds)));
```

**Files to change:**
- `lib/typecheck/typecheck.ml` — field-not-found branch (~5 lines).

**Tests:**
- `rec.naem` where `name` exists → expect "Did you mean `name`?" in output.
- `rec.xyz` with no close match → expect no spurious suggestion.

---

## 5. `let?` shows the actual RHS type

### Problem

Line 3876-3878: when the RHS of `let?` is not a `Result`, the error says:
`"The right-hand side of let? must be a Result value."` It does not say what
the RHS actually is, forcing the user to figure that out themselves.

### What to build

Infer the RHS type before unifying, then include it in the message if
unification fails:

```ocaml
let result_ty = infer_expr env result_expr in
let t_ok  = fresh_var env.level in
let t_err = fresh_var env.level in
(* Unification will call report_mismatch; supply a richer reason string
   so the "why" note names the actual type. *)
let why =
  Printf.sprintf
    "The right-hand side of `let?` has type `%s`, but `let?` requires \
     a `Result` value to propagate errors automatically."
    (pp_ty (repr result_ty))
in
unify env ~span:sp
  ~reason:(Some (RBuiltin why))
  result_ty (t_result t_ok t_err);
```

The `RBuiltin` reason text appears as a note below the mismatch headline, so the
user sees both what was expected and what was found, plus the explanation.

**Files to change:**
- `lib/typecheck/typecheck.ml` — `ELetQ` case, ~4 lines.

**Tests:**
- `let? x = Some(1)` — expect error naming `Option(Int)` in the message.
- `let? x = 42` — expect error naming `Int`.

---

## 6. Redundant / unreachable match arm warning

### Problem

`check_exhaustiveness` (`lib/typecheck/typecheck.ml:2945`) only checks for
_missing_ patterns using a "useful" / "missing" matrix algorithm. It does not
check for _redundant_ arms — arms whose patterns are subsumed by earlier arms
and can never be reached. Elm and OCaml both warn on these. Silent acceptance
misleads the programmer into thinking a case is being handled when it is not.

### What to build

Add a redundancy check inside `infer_match`, after exhaustiveness:

```
for each arm i (0-indexed):
  let prefix_matrix = patterns of arms 0..i-1
  if arm_i's pattern is NOT "useful" relative to prefix_matrix:
    emit Warning on arm_i's span: "This pattern can never be reached."
    note: "An earlier arm already covers all values this pattern matches."
```

Reuse the existing `useful` / `find_missing_mc` infrastructure. The check is:
`find_missing_mc` run with just `[arm_i_pattern]` as the "missing" query
against the prefix matrix returns `None` (meaning the prefix matrix already
covers it).

Alternatively — and more directly — implement `is_useful(pat, matrix)` which
returns `false` if `pat` adds no coverage. This is the standard algorithm used
in OCaml's `parmatch.ml`.

**Special cases:**
- Arms with guards (`branch_guard = Some _`) are never flagged redundant (a
  guard can make any pattern unreachable in ways static analysis can't prove,
  and false positives here would be very annoying).
- `_` wildcard as the _last_ arm is never flagged (it's idiomatic catch-all).
- `_` wildcard that is NOT last should be flagged if it makes subsequent arms
  unreachable.

**Files to change:**
- `lib/typecheck/typecheck.ml` — `infer_match`, plus a new `is_arm_redundant`
  helper near `check_exhaustiveness`.

**Tests:**
- `match x do A -> 1 | A -> 2 end` (duplicate ctor arm) → warning on second `A`.
- `match x do _ -> 0 | A -> 1 end` → warning on `A`.
- `match x do A when guard -> 1 | A -> 2 end` → no warning (guarded arm).

---

## 7. Parser errors — promote to `diagnostic` structure with `notes`

### Problem

`render_parse_error` (`lib/errors/errors.ml:129-157`) accepts a single optional
`hint` string. It uses a flat string format with no `notes []` mechanism. The
call sites in the parser's error recovery pass a single concatenated string.
This makes it impossible to give structured, multi-point guidance, and the
resulting format is visually different from typecheck diagnostics.

### What to build

**Phase A — unify the rendering:** Create a `parse_diagnostic` constructor or
reuse `diagnostic` for parse errors by mapping `render_parse_error` into a
`report` call before rendering. The simplest approach: make `render_parse_error`
produce a `diagnostic` value that the caller can then accumulate and render
through the same `render_diagnostic` path.

```ocaml
val parse_error_diagnostic :
  ?hint:string -> msg:string -> Lexing.lexbuf -> diagnostic
```

This keeps `render_parse_error` as a convenience wrapper but routes through the
shared renderer, which automatically gains label support from improvement #1.

**Phase B — structured hints for common parse errors:** The menhir error
message file (`lib/parser/parser.messages` or inline error rules) currently
produces bare strings. Extend the format to embed `\n` separators that
`render_parse_error` splits into `notes` entries. Each note gets the standard
4-space-indented treatment.

Key parse errors worth enriching with notes:

| Situation | Current | With notes |
|---|---|---|
| `if cond then ...` | "unexpected token `then`" | Note: "March uses `do`/`end`, not `then`. Write: `if cond do ... end`" |
| `fn x =>` (wrong arrow) | "unexpected `=>`" | Note: "Use `->` for function bodies in March: `fn x -> ...`" |
| Missing `end` on `mod`/`if`/`match` | "unexpected EOF" | Note: "Every `mod`/`if`/`match`/`fn` block needs a closing `end`." |
| `;` semicolon between expressions | "unexpected `;`" | Note: "March uses newlines to separate expressions, not semicolons." |

**Files to change:**
- `lib/errors/errors.ml` — new `parse_error_diagnostic` function.
- `bin/main.ml` or wherever `render_parse_error` is called — use new API.
- `lib/parser/parser.mly` — update error rule strings to embed notes markers.

**Tests:**
- `if x then 1 end` — expect note about `do`/`end`.
- `fn x => x` — expect note about `->`.

---

## 8. `qualified_error_msg` — distinguish module-not-found vs member-not-found at call sites

### Problem

`qualified_error_msg` (`lib/typecheck/typecheck.ml:703`) already distinguishes
these cases and produces good messages. But the bare `Err.error` call sites that
use it concatenate the result into a flat string:

```ocaml
Err.error env.errors ~span:name.span
  (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
     name.txt hint);
```

The headline and the suggestion are jammed into one string, sharing a single
source span. When `labels` rendering (improvement #1) is in place, these should
instead be:

- **Headline** as `message`
- **Module-not-found suggestion** or **member-not-found suggestion** as a `note`
- Optionally a **secondary label** on the import/use site if we have a span for it

### What to build

Refactor the three call sites that use `qualified_error_msg` as a string to
instead call a structured helper:

```ocaml
let report_qualified_error env span name =
  let msg, notes = qualified_error_structured name in
  Err.report env.errors
    { Err.severity = Error; span; message = msg;
      labels = []; notes; code = None }
```

Where `qualified_error_structured` returns `(headline, notes_list)` instead of
a flat string.

**Files to change:**
- `lib/typecheck/typecheck.ml` — `qualified_error_msg` and its 3 call sites.

**Tests:**
- `Foo.bar` where `Foo` exists but `bar` doesn't → headline + note as separate
  lines in the rendered output.
- `Unknown.anything` → headline + "Did you mean `KnownModule`?" as a note, not
  appended to the headline string.

---

## Implementation order

These are independent changes — any can be implemented in any order. Suggested
sequence for maximum visible impact early:

1. **#1 — Render labels** (unlocks all secondary spans across all other fixes)
2. **#4 — Record field fuzzy match** (5 lines, high user value)
3. **#5 — `let?` actual type** (4 lines, frequent confusion)
4. **#2 — if/match per-arm labeling** (medium; builds on #1)
5. **#3 — Arity + definition span** (medium; builds on #1)
6. **#6 — Redundant arm warning** (medium; self-contained)
7. **#8 — Qualified error restructuring** (small cleanup; builds on #1)
8. **#7 — Parser error notes** (largest; best done last)
