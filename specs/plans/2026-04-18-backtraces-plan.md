# Good Backtraces — Panic, assertion, and runtime error reporting

**Status:** In Progress
**Date:** 2026-04-18

## Motivation

When a March program panics today (via `panic()`, `unwrap()` on `None`, or an
out-of-bounds access), the output is one of:
- A C abort with a raw address (`Abort trap: 6`)
- A message like `panic: index out of bounds` with no location
- An OCaml backtrace (in the interpreter) pointing at internal compiler frames

None of these tell the user *where in their March code* the error happened.
This is one of the strongest signals that a language is "not production-ready."
Every popular language — Go, Rust, Python, Elixir, Ruby — prints March-level
stack frames with file, line, and function name. We need to do the same.

---

## Two execution contexts

March programs run in two modes with different backtrace strategies:

| Mode | How it runs | Backtrace approach |
|------|-------------|-------------------|
| **Tree-walking interpreter** (`dune exec march`) | OCaml call stack | Maintain a March call stack alongside |
| **Compiled binary** (`--compile`) | Native via LLVM | Per-thread linked-list frame table in C runtime |

Both need to produce the same output format. We tackle the interpreter first
(simpler, faster iteration), then the compiled path.

---

## Target output format

```
panic: index out of bounds (index 5, length 3)

Stack trace (most recent call first):
  [0] List.get           stdlib/list.march:142
  [1] process_items      src/worker.march:67
  [2] process_batch      src/worker.march:51
  [3] main               src/main.march:12

note: set MARCH_BACKTRACE=full for all frames including stdlib
```

Design choices:
- Most-recent-first (Go/Python convention — familiar to most developers)
- File path is relative to the project root
- Function name includes the containing module if not at top level
- `MARCH_BACKTRACE=full` shows stdlib frames (hidden by default to reduce noise)
- Default (no env var) hides frames from `stdlib/` prefix to reduce noise

---

## Part 1: Interpreter backtraces ✓

### Current state

`lib/eval/eval.ml` is a tree-walking interpreter. It calls OCaml functions
recursively. When `panic()` fires, it raises an OCaml exception
(`Eval_error`), which is caught at the top level and printed. No March call
stack is recorded.

Note: Three exception types can represent a March-level panic:
- `Eval_error` — runtime errors (`panic()`, bad ops, etc.)
- `Match_failure` — non-exhaustive pattern match
- `Assert_failure` — failed `assert` expression

All three must print a backtrace.

### Threading note

The interpreter is effectively single-threaded during evaluation. The actor/task
system uses cooperative scheduling (via the `Yield` exception and a reduction
budget), not OS threads or OCaml domains. A plain `ref` for the call stack is
safe; no `Domain.DLS` is needed.

### Plan

Add a *March call stack* to the evaluator. Because `EApp` expressions carry a
span (currently discarded), we can push a frame just before `apply` and pop
it on return or exception.

**New types and stack (near the exception definitions):**

```ocaml
(* lib/eval/eval.ml *)
type march_frame = {
  mf_name : string;
  mf_file : string;
  mf_line : int;
}

let march_stack : march_frame list ref = ref []

let march_stack_push (name : string) (sp : span) : unit =
  march_stack := { mf_name = name; mf_file = sp.file; mf_line = sp.start_line }
                 :: !march_stack

let march_stack_pop () : unit =
  match !march_stack with _ :: rest -> march_stack := rest | [] -> ()

let get_march_stack () : march_frame list = !march_stack

let clear_march_stack () : unit = march_stack := []
```

**Push/pop in the `EApp` evaluator:**

```ocaml
| EApp (f, args, sp) ->
  check_reductions ();
  let fn_name = match f with
    | EVar n -> n.txt
    | EField (_, field, _) -> field.txt
    | _ -> "<anon>"
  in
  (if !March_coverage.Coverage.coverage_enabled then
    March_coverage.Coverage.record_fn_call fn_name);
  let fn_val = eval_expr env f in
  let arg_vals = List.map (eval_expr env) args in
  march_stack_push fn_name sp;
  let result =
    (try `Ok (apply fn_val arg_vals)
     with exn -> `Err exn)
  in
  march_stack_pop ();
  (match result with `Ok v -> v | `Err exn -> raise exn)
```

Frames are pushed AFTER evaluating `f` and `args` (so nested calls have their
own frames first) and BEFORE `apply` (so the frame is live while the body runs).
The try/with ensures the frame is always popped, even on exceptions.

**Clear between tests** (in `run_tests`, at the start of each test iteration):

```ocaml
clear_march_stack ();
let result = try ...
```

**Stdlib frame filtering** (in `bin/main.ml`, at the backtrace print site):

```ocaml
let is_stdlib f = String.starts_with ~prefix:"stdlib/" f.mf_file in
let frames = match Sys.getenv_opt "MARCH_BACKTRACE" with
  | Some "full" -> !March_eval.Eval.march_stack
  | _ -> List.filter (fun f -> not (is_stdlib f)) !March_eval.Eval.march_stack
```

`String.starts_with` (OCaml 4.13+, available in our OCaml 5.3) avoids the
off-by-one in the original `String.length f.file > 7 && String.sub f.file 0 7`
check.

**In the error handlers** (top of `bin/main.ml`):

```ocaml
let print_backtrace () =
  let all = March_eval.Eval.get_march_stack () in
  let frames = match Sys.getenv_opt "MARCH_BACKTRACE" with
    | Some "full" -> all
    | _ -> List.filter (fun f ->
        not (String.starts_with ~prefix:"stdlib/" f.March_eval.Eval.mf_file)) all
  in
  if frames <> [] then begin
    Printf.eprintf "\nStack trace (most recent call first):\n";
    List.iteri (fun i f ->
      Printf.eprintf "  [%d] %-24s %s:%d\n"
        i f.March_eval.Eval.mf_name f.March_eval.Eval.mf_file f.March_eval.Eval.mf_line
    ) frames;
    if not (Sys.getenv_opt "MARCH_BACKTRACE" = Some "full") then
      Printf.eprintf "\nnote: set MARCH_BACKTRACE=full for all frames including stdlib\n"
  end

(* Then in the run_module handler: *)
| March_eval.Eval.Eval_error msg ->
    Printf.eprintf "panic: %s\n" msg;
    print_backtrace ();
    exit 1
| March_eval.Eval.Match_failure msg ->
    Printf.eprintf "panic: match failure: %s\n" msg;
    print_backtrace ();
    exit 1
| March_eval.Eval.Assert_failure msg ->
    Printf.eprintf "panic: %s\n" msg;
    print_backtrace ();
    exit 1
```

**Cost:** One list prepend, one `try/with`, and one tail-call per March function
invocation. This is acceptable for the interpreter (a development tool, not a
production runtime).

---

## Part 2: Compiled binary backtraces

### Current state

The LLVM backend emits native code. `panic()` calls a C runtime function
(`march_panic`) which calls `exit(1)`. No DWARF frames, no unwind table, no
March-level source info.

### Approach: runtime March call stack table

Rather than relying on DWARF unwinding (which requires `libunwind` or platform
`backtrace(3)` and DWARF `.debug_info`), maintain a **per-thread linked list of
March frames** in the C runtime. This is the same approach Go takes with its
goroutine stacks and Erlang takes with process dictionaries.

#### C runtime side (`runtime/march_runtime.c`)

```c
typedef struct march_frame_t {
  const char          *fn_name;
  const char          *file;
  int                  line;
  struct march_frame_t *prev;
} march_frame_t;

/* Thread-local top of call stack */
static _Thread_local march_frame_t *march_call_stack_top = NULL;

void march_frame_push(march_frame_t *frame) {
  frame->prev = march_call_stack_top;
  march_call_stack_top = frame;
}

void march_frame_pop(void) {
  if (march_call_stack_top)
    march_call_stack_top = march_call_stack_top->prev;
}

static void march_print_backtrace(void) {
  const char *full = getenv("MARCH_BACKTRACE");
  int show_stdlib = full && strcmp(full, "full") == 0;
  fprintf(stderr, "\nStack trace (most recent call first):\n");
  march_frame_t *f = march_call_stack_top;
  int i = 0;
  while (f) {
    int is_std = strncmp(f->file, "stdlib/", 7) == 0;
    if (show_stdlib || !is_std)
      fprintf(stderr, "  [%d] %-24s %s:%d\n", i++, f->fn_name, f->file, f->line);
    f = f->prev;
  }
  if (!show_stdlib)
    fprintf(stderr, "\nnote: set MARCH_BACKTRACE=full for all frames including stdlib\n");
}

void march_panic(void *s) {
  march_string *ms = (march_string *)s;
  if (march_test_in_test) {
    int len = (int)ms->len < (int)sizeof(march_test_fail_buf) - 1
              ? (int)ms->len : (int)sizeof(march_test_fail_buf) - 1;
    memcpy(march_test_fail_buf, ms->data, (size_t)len);
    march_test_fail_buf[len] = '\0';
    longjmp(march_test_jmp_buf, 1);
  }
  fprintf(stderr, "panic: ");
  fwrite(ms->data, 1, (size_t)ms->len, stderr);
  fputc('\n', stderr);
  march_print_backtrace();
  fflush(stderr);
  exit(1);
}
```

The `march_frame_t` is stack-allocated at each call site — no heap allocation.
The thread-local pointer means each OS thread has an independent call stack,
matching the `_Thread_local` pattern already used in the runtime (`g_in_scheduler`).

#### Frame lifetime and safety

`march_frame_t` instances live on the C call stack. Each is allocated at
function entry and freed automatically on return. The `prev` pointer always
points to a live frame (the caller's) because the caller is on the call stack
whenever the callee runs. This is safe.

#### LLVM codegen side (`lib/tir/llvm_emit.ml`)

For every compiled March function, emit entry and exit instrumentation.
`march_frame_push` and `march_frame_pop` must be declared `noinline` (or use a
memory barrier) to prevent LLVM from hoisting them past other calls:

```ocaml
(* In emit_fn, after alloca setup: *)
(* Declare the frame struct on the stack *)
let frame_ptr = build_alloca frame_struct_ty "march_frame" builder in
(* Store fn_name, file, line into the struct *)
build_store (global_string fn_name "fn_name") (gep frame_ptr 0 0) builder;
build_store (global_string span.file "file")  (gep frame_ptr 0 1) builder;
build_store (const_i32 span.start_line)        (gep frame_ptr 0 2) builder;
(* prev is set by march_frame_push itself — no init needed *)
build_call march_frame_push_fn [frame_ptr] "" builder;

(* Before every `ret` instruction: *)
build_call march_frame_pop_fn [] "" builder;
```

Declare `march_frame_push` and `march_frame_pop` with the `noinline` attribute
so LLVM cannot hoist the pop past the actual return or reorder push past a
downstream call.

#### Tail call interaction

For TCO loops (`is_tco = true`), the frame is pushed once at function entry
and popped once at the single `ret`. The loop body does not re-push, so the
frame stays live for the duration of the recursive loop. The function name shown
is the outer function's name, which is correct.

For mutual tail calls between `f` and `g`: `f` pushes its frame, tail-calls `g`
(which pushes its own frame before `f`'s is popped). Because TCO in LLVM is
via `musttail`, the actual frame for `f` is gone when `g` runs. We must pop
`f`'s march frame before the musttail call:

```ocaml
(* Before a musttail call: pop current frame, then let callee push its own *)
build_call march_frame_pop_fn [] "" builder;
(* ... musttail call to g ... *)
```

#### Performance

Each function call: 2 pointer stores + 1 pointer load + 1 pointer write.
On modern CPUs this is ~3–5 ns overhead per call.

**Default in release and debug builds:** frames are always emitted. The overhead
is only paid per function call — the print only happens on panic. Following
Rust's `RUST_BACKTRACE` model: the binary always has the capability; display
is controlled by `MARCH_BACKTRACE`. A `--no-backtrace` flag can be added later
to strip frames for extreme-performance builds.

**Future: `#[no_backtrace]` annotation** — Requires adding attribute/annotation
syntax to the parser and AST. Out of scope for this plan; can be added once
March has attribute support.

---

## Part 3: assert and unwrap messages ✓ (partial)

### `EAssert` location injection

`EAssert (inner, sp)` already carries the span in the AST. The evaluator can
include `sp.file:sp.start_line` in the `Assert_failure` message directly —
no desugarer changes needed:

```ocaml
| EAssert (inner, sp) ->
  ...
  raise (Assert_failure (Printf.sprintf
    "assert %s %s %s\n    left:  %s\n    right: %s\n  --> %s:%d"
    ... sp.file sp.start_line))
```

### `unwrap()` on `None` / `Err`

With the interpreter call stack from Part 1, the stack trace will already show
the `unwrap` frame and the call site that called it. This alone is a significant
improvement over the current "unwrap called on None" message.

For an even more precise message, the desugarer can inject the call-site
location. This requires:

```march
-- Private: accepts call-site location
pfn unwrap_at(opt : Option(a), loc : String) : a
  match opt do
  Some(x) -> x
  None -> panic("unwrap called on None at " ++ loc)
  end
end
```

The desugarer rewrites `unwrap(expr)` → `unwrap_at(expr, "file:line")` using
the span of the `EApp` call. Implementing this desugarer pass is deferred —
the call stack alone satisfies the immediate need.

### `assert_eq` failure message

`assert_eq` is a regular function in `stdlib/test.march`. Its panic message
already includes the expected and actual values. With the call stack, the
failing line is visible. The "expression text" feature (showing source of the
arguments) requires macro-style source capture and is out of scope.

---

## Part 4: panic formatting (future)

All panics share a consistent format. The C runtime owns the top-level
presentation. A future enhancement adds a source snippet:

```
panic: index out of bounds (index 99, length 3)

  --> src/worker.march:67
   |
67 |   let result = List.get(xs, 99)
   |                ^^^^^^^^^^^^^^^^^^

Stack trace (most recent call first):
  [0] List.get      stdlib/list.march:142
  [1] find_item     src/worker.march:67
```

The source snippet requires reading the source file at panic time. This is only
feasible if:
1. The source file exists on disk (development builds)
2. The full source path is embedded in the binary (DWARF or a custom section)

This is deferred — the stack trace alone is a large improvement.

---

## Testing strategy

Add `test/test_backtraces.march` with tests that:
1. Verify the stack trace format on a known panic sequence
2. Verify `assert` failure includes file/line
3. Verify `MARCH_BACKTRACE=full` shows stdlib frames

The March test framework supports `@capture_io` for capturing output and
`ExpectPanic` in doctests. The backtrace tests can use the `@capture_io`
directive and check `stderr`-captured output.

For `dune runtest` integration, add expect-test `.expected` files alongside
small `.march` programs that panic, so that `dune runtest --auto-promote`
manages the golden output.

---

## Implementation order

1. **Interpreter call stack** (Part 1) — affects the dev experience immediately;
   pure OCaml change, no compiler changes needed ✓
2. **EAssert location in message** (Part 3) — one-line fix in the evaluator ✓
3. **Assert_failure handler in main.ml** — catch the third exception type ✓
4. **C runtime frame table** (Part 2, runtime side) — prerequisite for compiled backtraces ✓
5. **LLVM codegen instrumentation** (Part 2, codegen side) — requires (4)
6. **Panic source snippets** (Part 4) — polish; implement last

## Out of scope

- DWARF-based unwinding (adds `libunwind` dependency, complex, fragile across
  platforms — the frame table approach is more reliable and portable)
- Async task backtraces (actor message traces are a separate concern)
- Crash dump files / core dump symbolization
- Integration with external error trackers (Sentry etc.) — possible via
  `march_panic` hook, but not in this plan
- `#[no_backtrace]` annotation — requires attribute syntax in parser/AST first
- `unwrap` desugarer injection — deferred; call stack covers the immediate need
- Panic source snippets — deferred (Part 4)
