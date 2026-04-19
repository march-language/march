# Good Backtraces — Panic, assertion, and runtime error reporting

**Status:** Planning
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
| **Compiled binary** (`--compile`) | Native via LLVM | DWARF + runtime unwind table |

Both need to produce the same output format. We tackle the interpreter first
(simpler, faster iteration), then the compiled path.

---

## Target output format

```
panic: index out of bounds (index 5, length 3)

Stack trace (most recent call first):
  [0] List.get           stdlib/list.march:142
  [1] process_items      src/worker.march:67     in process_batch()
  [2] process_batch      src/worker.march:51
  [3] main               src/main.march:12

note: set MARCH_BACKTRACE=full for all frames including stdlib
```

Design choices:
- Most-recent-first (Go/Python convention — familiar to most developers)
- File path is relative to the project root
- Function name includes the containing module if not at top level
- `MARCH_BACKTRACE=full` shows stdlib frames (hidden by default to reduce noise)
- Annotation shows the *caller* function name for context

---

## Part 1: Interpreter backtraces

### Current state

`lib/eval/eval.ml` is a tree-walking interpreter. It calls OCaml functions
recursively. When `panic()` fires, it raises an OCaml exception
(`EvalError`), which is caught at the top level and printed. No March call
stack is recorded.

### Plan

Add a *March call stack* thread-local to the evaluator.

**New type:**

```ocaml
(* lib/eval/eval.ml *)
type frame = {
  fn_name : string;
  file    : string;
  line    : int;
  col     : int;
}

let march_call_stack : frame list ref = ref []
```

**Push/pop on every March function call:**

```ocaml
let eval_call fn_name span args =
  let frame = { fn_name; file = span.file; line = span.start_line; col = span.start_col } in
  march_call_stack := frame :: !march_call_stack;
  let result =
    (try eval_fn args
     with EvalError _ as e ->
       march_call_stack := List.tl !march_call_stack;
       raise e)
  in
  march_call_stack := List.tl !march_call_stack;
  result
```

**In the `EvalError` handler** (top of `bin/main.ml`):

```ocaml
| EvalError msg ->
    Printf.eprintf "panic: %s\n\nStack trace (most recent call first):\n" msg;
    List.iteri (fun i frame ->
      Printf.eprintf "  [%d] %-24s %s:%d\n" i frame.fn_name frame.file frame.line
    ) !march_call_stack;
    exit 1
```

**Cost:** One list prepend and one tail-call per March function invocation.
This is acceptable; the interpreter is for development, not production
performance.

**stdlib frame filtering:**

```ocaml
let filter_frames frames =
  let is_stdlib f = String.length f.file > 7 && String.sub f.file 0 7 = "stdlib/" in
  match Sys.getenv_opt "MARCH_BACKTRACE" with
  | Some "full" -> frames
  | _ -> List.filter (fun f -> not (is_stdlib f)) frames
```

---

## Part 2: Compiled binary backtraces

### Current state

The LLVM backend emits native code. `panic()` calls a C runtime function
(`march_panic`) which calls `abort()`. No DWARF frames, no unwind table, no
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
static __thread march_frame_t *march_call_stack_top = NULL;

/* Called by every March function entry */
void march_frame_push(march_frame_t *frame) {
  frame->prev = march_call_stack_top;
  march_call_stack_top = frame;
}

/* Called on every March function return */
void march_frame_pop(void) {
  if (march_call_stack_top)
    march_call_stack_top = march_call_stack_top->prev;
}

/* Called by march_panic */
void march_print_backtrace(void) {
  fprintf(stderr, "\nStack trace (most recent call first):\n");
  march_frame_t *f = march_call_stack_top;
  int i = 0;
  while (f) {
    fprintf(stderr, "  [%d] %-24s %s:%d\n", i++, f->fn_name, f->file, f->line);
    f = f->prev;
  }
}

void march_panic(const char *msg) {
  fprintf(stderr, "panic: %s\n", msg);
  march_print_backtrace();
  exit(1);
}
```

The `march_frame_t` is stack-allocated at each call site — no heap allocation.
On function entry and return, the compiler inserts the push/pop calls.

#### LLVM codegen side (`lib/tir/llvm_emit.ml`)

For every compiled March function, emit entry and exit instrumentation:

```ocaml
(* In lower_fun_def, after alloca setup: *)
let frame_ty = struct_ty ["fn_name_ptr", ptr_ty; "file_ptr", ptr_ty; "line", i32; "prev_ptr", ptr_ty] in
let frame = build_alloca frame_ty "march_frame" builder in
build_store (global_string fn_name) (gep frame [0; 0]) builder;
build_store (global_string span.file) (gep frame [0; 1]) builder;
build_store (const_int32 span.start_line) (gep frame [0; 2]) builder;
build_call march_frame_push [frame] "" builder;

(* Before every `ret` instruction: *)
build_call march_frame_pop [] "" builder;
```

For tail-recursive functions, the frame is pushed once and popped once at the
actual `ret` — the optimizer must not hoist these past call sites.

#### Performance

Each function call: 2 pointer stores + 1 pointer load + 1 pointer write.
On modern CPUs this is ~3–5 ns overhead per call. For a tight loop calling a
small function 10M times, that's ~50 ms — meaningful for hot inner loops.

**Opt-out:** `#[no_backtrace]` annotation on a function skips push/pop for that
function. The loop body of a tight numeric computation should use this. Long
term, the compiler can infer when to elide frames (leaf functions with no
panic-capable calls, functions under a threshold).

**Opt-in mode:** The default in release builds is `--no-backtrace`
(frames not emitted). Pass `--backtrace` to get them. Debug builds (`--debug`)
always include frames.

---

## Part 3: assert and unwrap messages

### `unwrap()` on `None` / `Err`

Current behavior: `panic("unwrap: None")` — no location.

With source spans available at the call site, the compiler can inject the
location into the panic message:

```march
-- Conceptual desugaring of unwrap()
pfn unwrap_impl(v : Option(a), file : String, line : Int) : a
  match v do
  Some(x) -> x
  None -> panic("unwrap called on None at " ++ file ++ ":" ++ int_to_string(line))
  end
end
```

The `file` and `line` constants are injected by the desugarer at each call site
— similar to C's `__FILE__` / `__LINE__` macros or Rust's `panic!` macro.

```march
-- User writes:
let x = some_option |> unwrap()

-- Desugared to:
let x = unwrap_impl(some_option, "src/main.march", 42)
```

### `assert_eq` failure message

```march
-- Current output:
-- assertion failed: expected 5, got 7

-- Target output:
-- assertion failed at src/tests/foo.march:88
--   left:  5
--   right: 7
--   expression: assert_eq(compute(x), expected)
```

The "expression" field requires storing the source text of the arguments at the
call site — similar to how Rust's `assert_eq!` macro works. This is a
desugarer change: when desugaring `Test.assert_eq(a, b)`, record `a` and `b`
as string literals alongside.

---

## Part 4: panic formatting

All panics share a consistent format. The C runtime owns the top-level
presentation:

```
panic: <message>

  --> <file>:<line>
   |
42 |   let result = List.get(xs, 99)
   |                ^^^^^^^^^^^^^^^^^^
   |
   = note: index 99 is out of bounds (length: 3)

Stack trace (most recent call first):
  [0] List.get      stdlib/list.march:142
  [1] find_item     src/worker.march:67

note: set MARCH_BACKTRACE=full for all frames
```

The source snippet (the `42 | ...` block) requires the runtime to read the
source file at panic time. This is only done if:
1. The source file exists on disk (development builds)
2. `MARCH_BACKTRACE=pretty` is set

Production binaries can strip this; debug builds enable it by default.

---

## Implementation order

1. **Interpreter call stack** (Part 1) — affects the dev experience immediately;
   pure OCaml change, no compiler changes needed
2. **`unwrap`/`assert` location injection** (Part 3) — desugarer change, high
   user-visible payoff, no runtime changes needed
3. **C runtime frame table** (Part 2, runtime side) — prerequisite for compiled backtraces
4. **LLVM codegen instrumentation** (Part 2, codegen side) — requires (3)
5. **Panic source snippets** (Part 4) — polish; implement last

## Out of scope

- DWARF-based unwinding (adds `libunwind` dependency, complex, fragile across
  platforms — the frame table approach is more reliable and portable)
- Async task backtraces (actor message traces are a separate concern)
- Crash dump files / core dump symbolization
- Integration with external error trackers (Sentry etc.) — possible via
  `march_panic` hook, but not in this plan
