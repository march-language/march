# Doctest & Coverage Plan for March

## Overview

This plan covers two tightly coupled features: **doctests** (executable examples embedded in doc comments) and **test coverage measurement** (instrumenting the interpreter to track what code tests actually exercise). Together they close the loop on "is this stdlib well-documented and well-tested?"

---

## Part 1: Doctests

### Design Philosophy

March's doctest system draws from Elixir's `ExUnit.DocTest` but adapts it to March's existing infrastructure. The key insight from the Elixir research: doctests are extracted at compile time from doc chunks, then expanded into real test cases. March can do the same — extract examples from `fn_doc` strings, parse them as March expressions, and run them as test cases during `march test`.

### Syntax

Doc comments already support `doc "..."` and `doc """..."""` on functions. We add a prompt syntax inside doc strings:

```march
doc """
Returns the sum of two integers.

    march> add(2, 3)
    5

    march> add(0, 0)
    0

    march> add(-1, 1)
    0
"""
pub fn add(x : Int, y : Int) : Int do
  x + y
end
```

**Design decisions:**

- **Prompt prefix: `march>`** (not `iex>` or `>>`). Unambiguous, grep-friendly, and establishes March identity. Multi-line expressions use `...>` continuation.
- **Expected output on the next line(s).** The line immediately after `march>` (or `...>`) is the expected result, rendered via `to_string`. Blank line or next `march>` terminates the expected output.
- **Indentation-based extraction.** Examples must be indented by at least 4 spaces within the doc string. This avoids false positives from prose that happens to contain `march>`.
- **Triple-quoted strings only for doctests.** Single-quoted doc strings won't contain doctests (too cramped). This matches how `doc """..."""` is used for longer documentation.

### Multi-line expressions

```march
doc """
Sorts a list using the provided comparator.

    march> Sort.mergesort_by(
    ...>     Cons(3, Cons(1, Cons(2, Nil))),
    ...>     fn a -> fn b -> a <= b
    ...>   )
    Cons(1, Cons(2, Cons(3, Nil)))
"""
```

### Exception testing

```march
doc """
Panics on empty list.

    march> List.head(Nil)
    ** panic: head of empty list
"""
```

The `** panic: <message>` syntax indicates the expression should panic with a matching message substring.

### Comparison semantics

Expected output is compared as strings via `to_string(result) == expected_text`. This sidesteps type equality issues and matches what the user sees in the REPL. For types that don't have meaningful `to_string` (like closures), doctests should use assertions instead:

```march
doc """
    march> is_even = Math.is_even
    march> is_even(4)
    true
"""
```

### Implementation Plan

#### Phase 1: Doctest extraction (OCaml-side)

**New module: `lib/doctest/doctest.ml`**

```
Input: module AST (after parsing)
Output: list of (fn_name, example_expr_string, expected_output_string, span)
```

Walk all `DFn` declarations. For each one with `fn_doc = Some s`, scan the string for `march>` lines. Parse each example group into:
- The expression text (everything after `march>` / `...>`, joined)
- The expected output text (lines until blank line or next `march>`)
- A synthetic span pointing back to the doc string's location

This is pure string processing on the OCaml side — no changes to the lexer or parser needed. The doc strings are already plain OCaml strings in the AST.

**Key function signatures:**
```ocaml
type doctest_example = {
  dt_fn_name : string;
  dt_expr_text : string;        (* "add(2, 3)" *)
  dt_expected : string;         (* "5" *)
  dt_expects_panic : string option;  (* Some "head of empty list" *)
  dt_span : Errors.span;        (* location in source for error reporting *)
}

val extract_doctests : Ast.decl list -> doctest_example list
```

#### Phase 2: Doctest execution

Integrate with the existing test runner. When `march test file.march` runs:

1. Parse + desugar + typecheck as normal
2. Call `extract_doctests` on the module's declarations
3. For each example:
   a. Parse `dt_expr_text` as a March expression (call the parser on the string)
   b. Evaluate it in the module's environment (after all module definitions are loaded)
   c. Compare `to_string(result)` with `dt_expected`
   d. Or, if `dt_expects_panic` is set, catch the panic and check the message
4. Report results in the same format as `test "name" do...end` blocks

Doctest names appear as: `doctest List.head (1)`, `doctest List.head (2)`, etc. — matching Elixir's convention.

#### Phase 3: `doctest` directive

Add a declaration to March syntax:

```march
-- In a test file:
mod TestList do
  doctest List    -- runs all doctests from the List module
  doctest Map     -- runs all doctests from the Map module

  -- Regular tests can coexist:
  test "custom edge case" do
    assert (List.head(Cons(1, Nil)) == 1)
  end
end
```

This requires:
- Lexer: add `DOCTEST` keyword
- Parser: `doctest_decl : DOCTEST UPPER_IDENT` → `DDoctest of string * span`
- AST: new `DDoctest` variant
- Eval: during `run_tests`, resolve the module name, find its declarations, extract and run doctests

#### Phase 4: Forge integration

```bash
forge test --doctest              # run only doctests
forge test --doctest stdlib/      # run doctests for all stdlib modules
forge test --no-doctest           # skip doctests, run only test blocks
```

### Tree-sitter grammar update

Add highlighting for `march>` inside doc strings. This requires an injection query:

```scheme
; queries/injections.scm
((doc_annotation
  (string_content) @injection.content)
 (#match? @injection.content "march>")
 (#set! injection.language "march"))
```

This is the hardest part from an editor perspective. Elixir hasn't solved this either — even `tree-sitter-elixir` doesn't highlight `iex>` inside doc strings. For March, we can start with just highlighting the `march>` prefix as a keyword and the expected output as a comment, which is achievable with tree-sitter highlights alone (no injection needed):

```scheme
; In highlights.scm, within doc string context
((string_content) @keyword.operator
 (#match? @keyword.operator "march>"))
```

---

## Part 2: Test Coverage

### What coverage means for March

March uses a tree-walking interpreter. Traditional coverage tools (gcov, bisect_ppx) instrument compiled code — they won't help here. Instead, we instrument `eval_expr` itself to record which AST nodes get evaluated during a test run.

Every expression in March's AST carries a `span` (file, start line/col, end line/col). This is our coverage key.

### Coverage levels

**Level 1: Expression coverage** (implement first)
- Track which `expr` nodes (by span) get evaluated at least once
- Metric: `covered_exprs / total_exprs` per file
- This is the equivalent of line coverage but more precise

**Level 2: Branch coverage**
- Track which arms of `match` expressions get taken
- Track which side of `if/then/else` executes
- Metric: `covered_branches / total_branches` per file
- More useful than expression coverage for functional code where pattern matching is the primary control flow

**Level 3: Function coverage**
- Track which named functions get called at least once
- Metric: `covered_fns / total_fns` per module
- Cheapest to implement, easiest to understand

**Level 4: Documentation coverage** (new concept)
- Track which public functions have doc strings
- Track which doc strings have doctest examples
- Track which doctests pass
- Metric: `documented_fns / pub_fns`, `doctested_fns / documented_fns`

### Implementation

#### Architecture

```
┌─────────────────────────────────────────────┐
│  eval_expr(env, expr)                       │
│    if !coverage_enabled then                │
│      Coverage.record_expr(expr.span);       │
│    match expr with                          │
│    | EIf(c,t,e,s) ->                       │
│        let cv = eval c in                   │
│        if cv then (Coverage.record_branch   │
│          (s, true); eval t)                 │
│        else (Coverage.record_branch         │
│          (s, false); eval e)               │
│    | EMatch(scrut, arms, s) ->             │
│        ... Coverage.record_arm(s, i) ...   │
│    | ...                                    │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  Coverage module (lib/coverage/coverage.ml) │
│                                             │
│  expr_hits : (span, int) Hashtbl.t          │
│  branch_hits : (span * bool, int) Hashtbl.t │
│  arm_hits : (span * int, int) Hashtbl.t     │
│  fn_hits : (string, int) Hashtbl.t          │
│                                             │
│  record_expr : span -> unit                 │
│  record_branch : span * bool -> unit        │
│  record_arm : span * int -> unit            │
│  record_fn_call : string -> unit            │
│                                             │
│  report_json : unit -> string               │
│  report_summary : unit -> string            │
│  report_lcov : unit -> string               │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  AST walker (total expression counter)      │
│                                             │
│  Walks the parsed AST to count ALL exprs,   │
│  branches, arms, functions — the denominator│
│  for coverage percentages.                  │
└─────────────────────────────────────────────┘
```

#### `lib/coverage/coverage.ml`

```ocaml
(* Global mutable state, gated by coverage_enabled flag *)
let coverage_enabled = ref false

(* span -> hit count *)
let expr_hits : (string, int) Hashtbl.t = Hashtbl.create 4096
let branch_hits : (string, int) Hashtbl.t = Hashtbl.create 256

let span_key (s : Errors.span) =
  Printf.sprintf "%s:%d:%d-%d:%d"
    s.file s.start_line s.start_col s.end_line s.end_col

let record_expr (s : Errors.span) =
  if !coverage_enabled then begin
    let k = span_key s in
    let n = try Hashtbl.find expr_hits k with Not_found -> 0 in
    Hashtbl.replace expr_hits k (n + 1)
  end

let record_branch (s : Errors.span) (taken : bool) =
  if !coverage_enabled then begin
    let k = span_key s ^ (if taken then ":T" else ":F") in
    let n = try Hashtbl.find branch_hits k with Not_found -> 0 in
    Hashtbl.replace branch_hits k (n + 1)
  end
```

#### Performance

The `if !coverage_enabled` check is a single pointer dereference + branch prediction (always false in production). When disabled, overhead is effectively zero. When enabled, one hash table insert per expression — this is O(1) amortized and adds roughly 10-20% overhead based on Python's `coverage.py` benchmarks on similar interpreter architectures.

#### CLI integration

```bash
march test test/stdlib/ --coverage          # run tests with coverage
march test test/stdlib/ --coverage --json   # output coverage.json
march test test/stdlib/ --coverage --lcov   # output coverage.lcov
march test test/stdlib/ --coverage --summary # print table to stdout
```

Example summary output:
```
Coverage Report
═══════════════════════════════════════════════════════════
File                    Exprs    Branches  Functions  Doc%
───────────────────────────────────────────────────────────
stdlib/list.march       94.2%    87.3%     100.0%    82%
stdlib/map.march        91.0%    83.1%     100.0%    75%
stdlib/sort.march       88.7%    79.5%     100.0%    90%
stdlib/hamt.march       76.3%    71.2%     100.0%    60%
stdlib/seq.march        82.1%    74.0%     95.0%     45%
...
───────────────────────────────────────────────────────────
Total                   87.4%    80.2%     98.7%     71%
═══════════════════════════════════════════════════════════
```

#### LCOV output

LCOV format is understood by most CI tools (Codecov, Coveralls, GitHub Actions). The format maps cleanly:

```
SF:stdlib/list.march
DA:1,0          # line 1, not hit
DA:5,3          # line 5, hit 3 times
DA:6,3
BRDA:10,0,0,1  # line 10, block 0, branch 0 (true), hit 1 time
BRDA:10,0,1,0  # line 10, block 0, branch 1 (false), not hit
FN:5,List.map
FNDA:3,List.map # List.map called 3 times
end_of_record
```

March's span-based tracking maps to LCOV lines by using `start_line` of each span.

### Functional language challenges

**Pattern match coverage** is the most important metric for March. Expression coverage can be 90%+ while missing entire match arms that handle edge cases (empty list, None, Err). Branch coverage specifically tracks this.

**Higher-order functions:** A lambda `fn x -> x + 1` passed to `List.map` is its own coverage unit, keyed to the lambda's definition span. If `map` is called with an empty list, the lambda body is never evaluated — this shows as uncovered, which is correct and useful.

**Curried functions:** `fn a -> fn b -> a + b` creates two closures. The outer closure's body (`fn b -> ...`) is covered when it's called. The inner closure's body (`a + b`) is covered when *that* is called. Each has its own span.

### Documentation coverage

This is a distinct metric from code coverage. It answers: "are the public APIs documented and do the examples work?"

```ocaml
type doc_coverage = {
  total_pub_fns : int;
  documented_fns : int;       (* have doc string *)
  doctested_fns : int;        (* have at least one march> example *)
  passing_doctests : int;     (* examples that pass *)
  total_doctests : int;       (* total march> examples *)
}
```

Computed by walking the module AST — no interpreter instrumentation needed.

---

## Part 3: Implementation Phases

### Phase 1: Coverage infrastructure (2-3 sessions)
1. Create `lib/coverage/coverage.ml` with expr/branch/fn tracking
2. Add `record_expr` calls to `eval_expr` in eval.ml (gated by flag)
3. Add `record_branch` to `EIf` and `EMatch` evaluation
4. Add `--coverage` flag to `march test` command
5. Implement summary text output
6. Test with existing test suite — verify percentages make sense

### Phase 2: Coverage reporting (1-2 sessions)
1. AST walker to count total expressions/branches/functions (the denominator)
2. JSON output format
3. LCOV output format
4. Per-file and per-module breakdown
5. Forge integration: `forge test --coverage`

### Phase 3: Doctest extraction (2-3 sessions)
1. Create `lib/doctest/doctest.ml` with `march>` line parser
2. Expression text extraction from doc strings
3. Expected output extraction
4. Panic expectation syntax (`** panic:`)
5. Multi-line expression support (`...>`)
6. Unit tests for the extractor itself (OCaml alcotest)

### Phase 4: Doctest execution (2 sessions)
1. Parse extracted expression strings as March expressions
2. Evaluate in module environment
3. Compare results via `to_string`
4. Integrate with test runner output format
5. Error reporting with span pointing into doc string

### Phase 5: Doctest syntax + directive (1-2 sessions)
1. Add `DOCTEST` token to lexer
2. Add `DDoctest` to AST and parser
3. Eval support for `doctest ModuleName` in test files
4. Module resolution (find the module's source, extract its doctests)

### Phase 6: Documentation coverage (1 session)
1. AST walker to count pub fns, documented fns, doctested fns
2. Integrate with coverage summary output
3. `--doc-coverage` flag

### Phase 7: Tree-sitter + editor support (1 session)
1. Update `tree-sitter-march/grammar.js` with `test`, `describe`, `assert` rules
2. Add `march>` highlighting in doc strings
3. Update `highlights.scm`
4. Rebuild grammar

---

## Open Questions

1. **Should doctests run in isolation or share module state?** Elixir runs each doctest in a fresh context. This prevents inter-example dependencies but means you can't build up state across examples. Recommendation: fresh context per `march>` group (separated by blank lines), shared within a group.

2. **Should `march>` examples be typechecked?** The typechecker runs on the full module before doctests execute. But doctest expressions are parsed separately — they'd need their own typecheck pass with the module's type environment in scope. Phase 1 can skip this (just eval and catch runtime errors). Phase 2 can add typecheck for better error messages.

3. **How to handle non-deterministic output?** Functions like `Random.int()` produce different output each run. Options: (a) ignore — doctests shouldn't use non-deterministic functions, (b) add a `march> # ignore-output` directive that only checks the expression doesn't panic, (c) seed the RNG in doctest mode.

4. **Coverage for stdlib loaded as prelude?** The stdlib is prepended to every file. Should its expressions count toward coverage of the user's file, or be filtered out? Recommendation: filter by file path — only count spans whose `file` field matches the file under test.

5. **Hit count vs boolean coverage?** Hit counts are more informative (hot paths vs cold paths) but boolean "covered/uncovered" is simpler to reason about. Recommendation: store hit counts internally, report both in JSON, use boolean for summary percentages.
