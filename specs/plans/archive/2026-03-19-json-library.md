# JSON Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `Json` stdlib module with yyjson (compiled path) and Yojson (interpreter path), giving March programs full JSON parse/encode/query support.

**Architecture:** Two independent milestones. Milestone A (Tasks 1–5) delivers working JSON in the tree-walking interpreter using Yojson — fully testable today. Milestone B (Tasks 6–9) extends JSON to the LLVM compiled path using yyjson in C. Both expose the same `Json` module API; the split is invisible to March programs.

**Tech Stack:** OCaml 5.3.0, Yojson (opam), yyjson (vendored C single-file library), Alcotest (tests), March stdlib (`.march` files).

**Spec:** `docs/superpowers/specs/2026-03-19-json-design.md`

---

## File Structure

| File | Status | Responsibility |
|------|--------|---------------|
| `stdlib/json.march` | Create | March `Json` module — type, builtins, pure March helpers |
| `lib/eval/eval.ml` | Modify | Add `json_parse`, `json_encode`, `json_encode_pretty` OCaml builtins (Yojson) |
| `lib/eval/dune` | Modify | Add `yojson` library dependency |
| `dune-project` | Modify | Add `yojson` to package dependencies |
| `bin/main.ml` | Modify | Add `json.march` to stdlib load order; extend clang command to compile `march_json.c` and `yyjson.c` |
| `test/test_march.ml` | Modify | Add JSON test suite |
| `runtime/yyjson.h` | Create | Vendored yyjson header (untouched) |
| `runtime/yyjson.c` | Create | Vendored yyjson implementation (untouched) |
| `runtime/march_json.c` | Create | C wrapper: yyjson tree → March ADT heap objects |
| `runtime/march_runtime.h` | Modify | Add `march_json_*` declarations |
| `lib/tir/llvm_emit.ml` | Modify | Add declare lines + `is_builtin_fn` / `builtin_ret_ty` / `mangle_extern` entries |

---

## Milestone A: Interpreter Path

---

### Task 1: Add Yojson dependency

**Files:**
- Modify: `lib/eval/dune`
- Modify: `dune-project`

- [ ] **Step 1: Add yojson to eval library dune**

Edit `lib/eval/dune`. Change:
```
(library
 (name march_eval)
 (libraries march_ast march_scheduler unix))
```
To:
```
(library
 (name march_eval)
 (libraries march_ast march_scheduler unix yojson))
```

- [ ] **Step 2: Add yojson to dune-project package dependencies**

Edit `dune-project`. In the `(depends ...)` stanza, add after the `alcotest` line:
```
  (yojson (>= 2.0.0))
```

- [ ] **Step 3: Install yojson**

```bash
opam install yojson
```

- [ ] **Step 4: Verify build still works**

```bash
dune build
```
Expected: clean build, no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/dune dune-project march.opam
git commit -m "build: add yojson dependency for JSON stdlib"
```

---

### Task 2: Add eval builtins for JSON

**Files:**
- Modify: `lib/eval/eval.ml` (find the end of the builtins list, just before the `]` that closes the `http_parse_response` entry at line ~1459)

- [ ] **Step 1: Write the failing test — json_parse returns Ok**

In `test/test_march.ml`, add this helper and test near the end of the file (before the `let () = Alcotest.run` block):

```ocaml
let eval_with_json src =
  let option_decl = load_stdlib_file_for_test "option.march" in
  let result_decl = load_stdlib_file_for_test "result.march" in
  let list_decl   = load_stdlib_file_for_test "list.march" in
  let string_decl = load_stdlib_file_for_test "string.march" in
  let json_decl   = load_stdlib_file_for_test "json.march" in
  (* Order matches bin/main.ml production load order: option → result → list → string → json *)
  eval_with_stdlib [option_decl; result_decl; list_decl; string_decl; json_decl] src

let test_json_parse_null () =
  let env = eval_with_json {|mod Test do
    fn f() do
      match Json.parse("null") with
      | Ok(Json.Null) -> true
      | _ -> false
      end
    end
  end|} in
  Alcotest.(check bool) "parse null" true (vbool (call_fn env "f" []))
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
dune runtest
```
Expected: FAIL — `json.march` does not exist yet, `json_parse` not defined.

- [ ] **Step 3: Add the three JSON builtins to eval.ml**

Find the end of the builtins list in `lib/eval/eval.ml` — the line that reads:
```ocaml
        | _ -> eval_error "http_parse_response(raw_string)"))
  ]
```

Add before the closing `]`:

```ocaml
  (* ---- JSON builtins (interpreter path — uses Yojson) ---- *)
  ; ("json_parse", VBuiltin ("json_parse", function
        | [VString s] ->
          let rec to_march = function
            | `Null       -> VCon ("Null", [])
            | `Bool b     -> VCon ("Bool", [VBool b])
            | `Int n      -> VCon ("Int",  [VInt n])
            | `Float f    -> VCon ("Float", [VFloat f])
            | `String s   -> VCon ("Str",  [VString s])
            | `List xs    ->
              let items = List.map to_march xs in
              let lst = List.fold_right
                (fun v acc -> VCon ("Cons", [v; acc]))
                items (VCon ("Nil", [])) in
              VCon ("Array", [lst])
            | `Assoc pairs ->
              let march_pairs = List.map (fun (k, v) ->
                VTuple [VString k; to_march v]) pairs in
              let lst = List.fold_right
                (fun v acc -> VCon ("Cons", [v; acc]))
                march_pairs (VCon ("Nil", [])) in
              VCon ("Object", [lst])
          in
          (try
            let j = Yojson.Basic.from_string s in
            VCon ("Ok", [to_march j])
          with Yojson.Json_error msg ->
            let err = VCon ("JsonError", [VString msg; VInt 0]) in
            VCon ("Err", [err]))
        | _ -> eval_error "json_parse: expected string"))
  ; ("json_encode", VBuiltin ("json_encode", function
        | [v] ->
          let rec to_yojson = function
            | VCon ("Null",   [])          -> `Null
            | VCon ("Bool",   [VBool b])   -> `Bool b
            | VCon ("Int",    [VInt n])    -> `Int n
            | VCon ("Float",  [VFloat f])  -> `Float f
            | VCon ("Str",    [VString s]) -> `String s
            | VCon ("Array",  [lst])       ->
              let rec items = function
                | VCon ("Nil", [])         -> []
                | VCon ("Cons", [h; t])    -> to_yojson h :: items t
                | _ -> eval_error "json_encode: malformed list"
              in `List (items lst)
            | VCon ("Object", [lst])       ->
              let rec pairs = function
                | VCon ("Nil", [])              -> []
                | VCon ("Cons", [VTuple [VString k; v]; t]) ->
                  (k, to_yojson v) :: pairs t
                | _ -> eval_error "json_encode: malformed object"
              in `Assoc (pairs lst)
            | _ -> eval_error "json_encode: not a Json value"
          in
          VString (Yojson.Basic.to_string (to_yojson v))
        | _ -> eval_error "json_encode: expected one argument"))
  ; ("json_encode_pretty", VBuiltin ("json_encode_pretty", function
        | [v] ->
          let rec to_yojson = function
            | VCon ("Null",   [])          -> `Null
            | VCon ("Bool",   [VBool b])   -> `Bool b
            | VCon ("Int",    [VInt n])    -> `Int n
            | VCon ("Float",  [VFloat f])  -> `Float f
            | VCon ("Str",    [VString s]) -> `String s
            | VCon ("Array",  [lst])       ->
              let rec items = function
                | VCon ("Nil", [])         -> []
                | VCon ("Cons", [h; t])    -> to_yojson h :: items t
                | _ -> eval_error "json_encode_pretty: malformed list"
              in `List (items lst)
            | VCon ("Object", [lst])       ->
              let rec pairs = function
                | VCon ("Nil", [])              -> []
                | VCon ("Cons", [VTuple [VString k; v]; t]) ->
                  (k, to_yojson v) :: pairs t
                | _ -> eval_error "json_encode_pretty: malformed object"
              in `Assoc (pairs lst)
            | _ -> eval_error "json_encode_pretty: not a Json value"
          in
          VString (Yojson.Basic.pretty_to_string (to_yojson v))
        | _ -> eval_error "json_encode_pretty: expected one argument"))
```

- [ ] **Step 4: Build**

```bash
dune build
```
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml
git commit -m "feat(eval): add json_parse, json_encode, json_encode_pretty builtins"
```

---

### Task 3: Write `stdlib/json.march`

**Files:**
- Create: `stdlib/json.march`

- [ ] **Step 1: Create the file**

```bash
# Verify stdlib/ exists and contains other modules
ls stdlib/
```

- [ ] **Step 2: Write `stdlib/json.march`**

```march
-- Json module: JSON parse, encode, and query.
--
-- Type uses List((String, Json)) for Object — Map is not yet implemented.
-- Constructor order is alphabetical and must not change (C tag constants
-- in runtime/march_json.c depend on declaration order).

mod Json do

  type Json
    = Array(List(Json))
    | Bool(Bool)
    | Float(Float)
    | Int(Int)
    | Null
    | Object(List((String, Json)))
    | Str(String)

  type JsonError = JsonError(message : String, offset : Int)

  -- Core: these three call runtime builtins.

  pub fn parse(s : String) : Result(Json, JsonError) do
    json_parse(s)
  end

  pub fn encode(v : Json) : String do
    json_encode(v)
  end

  pub fn encode_pretty(v : Json) : String do
    json_encode_pretty(v)
  end

  pub fn parse_or_panic(s : String) : Json do
    match parse(s) with
    | Ok(v) -> v
    | Err(JsonError(msg, offset)) ->
      panic("JSON parse error at byte " ++ String.from_int(offset) ++ ": " ++ msg)
    end
  end

  -- Object access: linear search, first match wins on duplicate keys.

  pub fn get(v : Json, key : String) : Option(Json) do
    match v with
    | Object(pairs) ->
      match List.find(pairs, fn pair ->
        match pair with | (k, _) -> k == key end
      ) with
      | Some((_, val)) -> Some(val)
      | None -> None
      end
    | _ -> None
    end
  end

  -- Array access by index.

  pub fn at(v : Json, idx : Int) : Option(Json) do
    match v with
    | Array(xs) -> List.nth_opt(xs, idx)
    | _ -> None
    end
  end

  -- Nested path: path(j, ["user", "address", "city"])
  -- Integer array indices written as strings: path(j, ["items", "0"])
  -- Returns None if any step misses or the node is not an Object/Array.

  pub fn path(v : Json, keys : List(String)) : Option(Json) do
    List.fold_left(Some(v), keys, fn (acc, key) ->
      match acc with
      | None -> None
      | Some(node) ->
        match String.to_int(key) with
        | Ok(idx) -> at(node, idx)
        | Err(_)  -> get(node, key)
        end
      end
    )
  end

  -- Type coercions — all return Option.

  pub fn as_str(v : Json) : Option(String) do
    match v with | Str(s) -> Some(s) | _ -> None end
  end

  pub fn as_int(v : Json) : Option(Int) do
    match v with | Int(n) -> Some(n) | _ -> None end
  end

  pub fn as_float(v : Json) : Option(Float) do
    match v with | Float(f) -> Some(f) | _ -> None end
  end

  pub fn as_bool(v : Json) : Option(Bool) do
    match v with | Bool(b) -> Some(b) | _ -> None end
  end

  pub fn as_list(v : Json) : Option(List(Json)) do
    match v with | Array(xs) -> Some(xs) | _ -> None end
  end

  pub fn as_object(v : Json) : Option(List((String, Json))) do
    match v with | Object(pairs) -> Some(pairs) | _ -> None end
  end

  -- Constructors (convenience wrappers — ADT constructors also work directly).

  pub fn null() : Json do Null end
  pub fn bool(b : Bool) : Json do Bool(b) end
  pub fn int(n : Int) : Json do Int(n) end
  pub fn float(f : Float) : Json do Float(f) end
  pub fn str(s : String) : Json do Str(s) end
  pub fn array(xs : List(Json)) : Json do Array(xs) end
  pub fn object(pairs : List((String, Json))) : Json do Object(pairs) end

end
```

- [ ] **Step 3: Run the first test to see it pass**

```bash
dune runtest
```
Expected: `test_json_parse_null` passes.

- [ ] **Step 4: Commit**

```bash
git add stdlib/json.march
git commit -m "feat(stdlib): add Json module"
```

---

### Task 4: Register `json.march` in the compiler stdlib load order

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Find the stdlib load list**

In `bin/main.ml`, find the list around line 78 that reads:
```ocaml
      "iolist.march";
      "http.march";
```

- [ ] **Step 2: Add `json.march` after `string.march`, before `iolist.march`**

The Json module depends on `list.march`, `option.march`, `result.march`, `string.march`. All four load before `iolist.march`. Insert `"json.march"` so the list reads:
```ocaml
      "string.march";
      "json.march";
      "iolist.march";
```

- [ ] **Step 3: Build and run tests**

```bash
dune build && dune runtest
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add bin/main.ml
git commit -m "feat(stdlib): register json.march in stdlib load order"
```

---

### Task 5: Full JSON test suite

**Files:**
- Modify: `test/test_march.ml`

Add all tests after the `eval_with_json` helper from Task 2. Add the test group to the `Alcotest.run` call at the bottom.

- [ ] **Step 1: Add parse tests**

```ocaml
let test_json_parse_bool_true () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("true") with | Ok(Json.Bool(b)) -> b | _ -> false end
    end
  end|} in
  Alcotest.(check bool) "parse true" true (vbool (call_fn env "f" []))

let test_json_parse_int () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("42") with | Ok(Json.Int(n)) -> n | _ -> 0 end
    end
  end|} in
  Alcotest.(check int) "parse int" 42 (vint (call_fn env "f" []))

let test_json_parse_float () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("3.14") with | Ok(Json.Float(_)) -> true | _ -> false end
    end
  end|} in
  Alcotest.(check bool) "parse float" true (vbool (call_fn env "f" []))

let test_json_parse_string () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("\"hello\"") with | Ok(Json.Str(s)) -> s | _ -> "" end
    end
  end|} in
  Alcotest.(check string) "parse string" "hello" (vstr (call_fn env "f" []))

let test_json_parse_array () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("[1,2,3]") with | Ok(Json.Array(_)) -> true | _ -> false end
    end
  end|} in
  Alcotest.(check bool) "parse array" true (vbool (call_fn env "f" []))

let test_json_parse_object () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("{\"a\":1}") with | Ok(Json.Object(_)) -> true | _ -> false end
    end
  end|} in
  Alcotest.(check bool) "parse object" true (vbool (call_fn env "f" []))

let test_json_parse_error () =
  let env = eval_with_json {|mod Test do
    fn f() do match Json.parse("{bad}") with | Err(_) -> true | Ok(_) -> false end
    end
  end|} in
  Alcotest.(check bool) "parse error" true (vbool (call_fn env "f" []))
```

- [ ] **Step 2: Add encode tests**

```ocaml
let test_json_encode_null () =
  let env = eval_with_json {|mod Test do
    fn f() do Json.encode(Json.Null) end
  end|} in
  Alcotest.(check string) "encode null" "null" (vstr (call_fn env "f" []))

let test_json_encode_int () =
  let env = eval_with_json {|mod Test do
    fn f() do Json.encode(Json.Int(42)) end
  end|} in
  Alcotest.(check string) "encode int" "42" (vstr (call_fn env "f" []))

let test_json_encode_string () =
  let env = eval_with_json {|mod Test do
    fn f() do Json.encode(Json.Str("hi")) end
  end|} in
  Alcotest.(check string) "encode string" {|"hi"|} (vstr (call_fn env "f" []))

let test_json_encode_object () =
  let env = eval_with_json {|mod Test do
    fn f() do Json.encode(Json.object([("x", Json.Int(1))])) end
  end|} in
  Alcotest.(check string) "encode object" {|{"x":1}|} (vstr (call_fn env "f" []))
```

- [ ] **Step 3: Add accessor tests**

```ocaml
let test_json_get_hit () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("{\"name\":\"alice\"}")
      match Json.get(j, "name") with
      | Some(Json.Str(s)) -> s
      | _ -> ""
      end
    end
  end|} in
  Alcotest.(check string) "get hit" "alice" (vstr (call_fn env "f" []))

let test_json_get_miss () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("{\"name\":\"alice\"}")
      match Json.get(j, "age") with
      | None -> true
      | _ -> false
      end
    end
  end|} in
  Alcotest.(check bool) "get miss" true (vbool (call_fn env "f" []))

let test_json_at () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("[10,20,30]")
      match Json.at(j, 1) with
      | Some(Json.Int(n)) -> n
      | _ -> 0
      end
    end
  end|} in
  Alcotest.(check int) "at index 1" 20 (vint (call_fn env "f" []))

let test_json_path () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("{\"user\":{\"id\":99}}")
      match Json.path(j, ["user", "id"]) with
      | Some(Json.Int(n)) -> n
      | _ -> 0
      end
    end
  end|} in
  Alcotest.(check int) "nested path" 99 (vint (call_fn env "f" []))

let test_json_path_array_index () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("{\"items\":[1,2,3]}")
      match Json.path(j, ["items", "2"]) with
      | Some(Json.Int(n)) -> n
      | _ -> 0
      end
    end
  end|} in
  Alcotest.(check int) "path array index" 3 (vint (call_fn env "f" []))

let test_json_path_miss () =
  let env = eval_with_json {|mod Test do
    fn f() do
      let j = Json.parse_or_panic("{\"a\":1}")
      match Json.path(j, ["a", "b"]) with
      | None -> true
      | _ -> false
      end
    end
  end|} in
  Alcotest.(check bool) "path miss" true (vbool (call_fn env "f" []))
```

- [ ] **Step 4: Register the test group in the `Alcotest.run` call**

Find the closing of the `Alcotest.run` list (last `]` before the `)` of the run call) and add:

```ocaml
      ("json stdlib", [
        Alcotest.test_case "parse null"         `Quick test_json_parse_null;
        Alcotest.test_case "parse bool true"    `Quick test_json_parse_bool_true;
        Alcotest.test_case "parse int"          `Quick test_json_parse_int;
        Alcotest.test_case "parse float"        `Quick test_json_parse_float;
        Alcotest.test_case "parse string"       `Quick test_json_parse_string;
        Alcotest.test_case "parse array"        `Quick test_json_parse_array;
        Alcotest.test_case "parse object"       `Quick test_json_parse_object;
        Alcotest.test_case "parse error"        `Quick test_json_parse_error;
        Alcotest.test_case "encode null"        `Quick test_json_encode_null;
        Alcotest.test_case "encode int"         `Quick test_json_encode_int;
        Alcotest.test_case "encode string"      `Quick test_json_encode_string;
        Alcotest.test_case "encode object"      `Quick test_json_encode_object;
        Alcotest.test_case "get hit"            `Quick test_json_get_hit;
        Alcotest.test_case "get miss"           `Quick test_json_get_miss;
        Alcotest.test_case "at index"           `Quick test_json_at;
        Alcotest.test_case "path nested"        `Quick test_json_path;
        Alcotest.test_case "path array index"   `Quick test_json_path_array_index;
        Alcotest.test_case "path miss"          `Quick test_json_path_miss;
      ]);
```

- [ ] **Step 5: Run full test suite**

```bash
dune runtest
```
Expected: all tests pass including all 18 JSON tests.

- [ ] **Step 6: Commit**

```bash
git add test/test_march.ml
git commit -m "test: add JSON stdlib test suite (18 tests)"
```

---

## Milestone B: Compiled Path (LLVM / yyjson)

> These tasks extend JSON to the LLVM-compiled path. They are independent of Milestone A and can be done separately. Milestone A must be complete first (the March module and eval builtins must exist).

---

### Task 6: Vendor yyjson

**Files:**
- Create: `runtime/yyjson.h`
- Create: `runtime/yyjson.c`

yyjson is a single-file C library. The amalgamated release is two files: `yyjson.h` and `yyjson.c`.

- [ ] **Step 1: Download yyjson release files**

```bash
cd runtime
curl -LO https://raw.githubusercontent.com/ibireme/yyjson/master/src/yyjson.h
curl -LO https://raw.githubusercontent.com/ibireme/yyjson/master/src/yyjson.c
cd ..
```

Verify both files exist and are non-empty:
```bash
wc -l runtime/yyjson.h runtime/yyjson.c
```
Expected: yyjson.h ~100 lines (or more), yyjson.c ~5000+ lines.

- [ ] **Step 2: Verify the files compile**

```bash
cc -c runtime/yyjson.c -o /tmp/yyjson_test.o
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add runtime/yyjson.h runtime/yyjson.c
git commit -m "vendor: add yyjson single-file C JSON library"
```

---

### Task 7: Write `runtime/march_json.c`

**Files:**
- Create: `runtime/march_json.c`

This file walks a yyjson document tree and produces March ADT heap objects. Tag constants must match the alphabetical constructor order in `stdlib/json.march`.

- [ ] **Step 1: Create `runtime/march_json.c`**

```c
#include "march_runtime.h"
#include "yyjson.h"
#include <string.h>

/* Tag assignments — MUST match alphabetical constructor order in json.march:
 *   Array=0, Bool=1, Float=2, Int=3, Null=4, Object=5, Str=6           */
#define JSON_TAG_ARRAY  0
#define JSON_TAG_BOOL   1
#define JSON_TAG_FLOAT  2
#define JSON_TAG_INT    3
#define JSON_TAG_NULL   4
#define JSON_TAG_OBJECT 5
#define JSON_TAG_STR    6

/* Tuple tag for (String, Json) pair — 2-field product, tag 0 */
#define TUPLE2_TAG 0

/* Forward declaration */
static void *yyjson_val_to_march(yyjson_val *val);

/* Build a March Cons(head, tail) cell */
static void *march_cons(void *head, void *tail) {
    /* Cons is tag 1, fields: [head, tail] */
    march_hdr *cell = march_alloc(16 + 2 * 8);
    cell->tag = 1;
    int64_t *fields = (int64_t *)(cell + 1);
    fields[0] = (int64_t)head;
    fields[1] = (int64_t)tail;
    return cell;
}

/* Build a March Nil value */
static void *march_nil(void) {
    march_hdr *nil = march_alloc(16);
    nil->tag = 0;
    return nil;
}

/* Build a 2-field tuple: (a, b) */
static void *march_tuple2(void *a, void *b) {
    march_hdr *t = march_alloc(16 + 2 * 8);
    t->tag = TUPLE2_TAG;
    int64_t *fields = (int64_t *)(t + 1);
    fields[0] = (int64_t)a;
    fields[1] = (int64_t)b;
    return t;
}

/* Convert a yyjson array to a March List(Json) */
static void *yyjson_arr_to_march_list(yyjson_val *arr) {
    size_t idx, max;
    yyjson_val *val;
    /* Collect into a temporary C array for reversal */
    size_t len = yyjson_arr_size(arr);
    void **items = malloc(len * sizeof(void *));
    yyjson_arr_foreach(arr, idx, max, val) {
        items[idx] = yyjson_val_to_march(val);
    }
    /* Build list in reverse so head = items[0] */
    void *list = march_nil();
    for (size_t i = len; i > 0; i--) {
        list = march_cons(items[i-1], list);
    }
    free(items);
    return list;
}

/* Convert a yyjson object to a March List((String, Json)) */
static void *yyjson_obj_to_march_list(yyjson_val *obj) {
    size_t idx, max;
    yyjson_val *key, *val;
    size_t len = yyjson_obj_size(obj);
    void **pairs = malloc(len * sizeof(void *));
    yyjson_obj_foreach(obj, idx, max, key, val) {
        void *k = march_string_lit(yyjson_get_str(key),
                                   (int64_t)yyjson_get_len(key));
        void *v = yyjson_val_to_march(val);
        pairs[idx] = march_tuple2(k, v);
    }
    void *list = march_nil();
    for (size_t i = len; i > 0; i--) {
        list = march_cons(pairs[i-1], list);
    }
    free(pairs);
    return list;
}

static void *yyjson_val_to_march(yyjson_val *val) {
    march_hdr *node;
    int64_t *fields;

    switch (yyjson_get_type(val)) {
    case YYJSON_TYPE_NULL:
        node = march_alloc(16);
        node->tag = JSON_TAG_NULL;
        return node;

    case YYJSON_TYPE_BOOL:
        node = march_alloc(16 + 8);
        node->tag = JSON_TAG_BOOL;
        fields = (int64_t *)(node + 1);
        fields[0] = yyjson_get_bool(val) ? 1 : 0;
        return node;

    case YYJSON_TYPE_NUM:
        switch (yyjson_get_subtype(val)) {
        case YYJSON_SUBTYPE_UINT:
        case YYJSON_SUBTYPE_SINT:
            node = march_alloc(16 + 8);
            node->tag = JSON_TAG_INT;
            fields = (int64_t *)(node + 1);
            fields[0] = yyjson_get_subtype(val) == YYJSON_SUBTYPE_UINT
                        ? (int64_t)yyjson_get_uint(val)
                        : yyjson_get_sint(val);
            return node;
        default: /* REAL */
            node = march_alloc(16 + 8);
            node->tag = JSON_TAG_FLOAT;
            double *df = (double *)(node + 1);
            df[0] = yyjson_get_real(val);
            return node;
        }

    case YYJSON_TYPE_STR: {
        const char *s = yyjson_get_str(val);
        size_t len = yyjson_get_len(val);
        node = march_alloc(16 + 8);
        node->tag = JSON_TAG_STR;
        fields = (int64_t *)(node + 1);
        fields[0] = (int64_t)march_string_lit(s, (int64_t)len);
        return node;
    }

    case YYJSON_TYPE_ARR: {
        void *list = yyjson_arr_to_march_list(val);
        node = march_alloc(16 + 8);
        node->tag = JSON_TAG_ARRAY;
        fields = (int64_t *)(node + 1);
        fields[0] = (int64_t)list;
        return node;
    }

    case YYJSON_TYPE_OBJ: {
        void *list = yyjson_obj_to_march_list(val);
        node = march_alloc(16 + 8);
        node->tag = JSON_TAG_OBJECT;
        fields = (int64_t *)(node + 1);
        fields[0] = (int64_t)list;
        return node;
    }

    default:
        /* Unknown type — return Null */
        node = march_alloc(16);
        node->tag = JSON_TAG_NULL;
        return node;
    }
}

/* march_json_parse: returns March Result(Json, JsonError) */
void *march_json_parse(const char *s, int64_t len) {
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_opts((char *)s, (size_t)len,
                                       0, NULL, &err);
    if (!doc) {
        /* Build Err(JsonError(message, offset))
         * Result tag convention (alphabetical): Ok=0, Err=1  */
        void *msg = march_string_lit(err.msg, (int64_t)strlen(err.msg));
        march_hdr *json_err = march_alloc(16 + 2 * 8);
        json_err->tag = 0; /* JsonError has one constructor, tag 0 */
        int64_t *ef = (int64_t *)(json_err + 1);
        ef[0] = (int64_t)msg;
        ef[1] = (int64_t)err.pos;
        march_hdr *result = march_alloc(16 + 8);
        result->tag = 1; /* Err = tag 1  (Ok=0, Err=1 — alphabetical) */
        ((int64_t *)(result + 1))[0] = (int64_t)json_err;
        return result;
    }
    void *march_val = yyjson_val_to_march(yyjson_doc_get_root(doc));
    yyjson_doc_free(doc);
    /* Build Ok(march_val) */
    march_hdr *result = march_alloc(16 + 8);
    result->tag = 0; /* Ok = tag 0  (Ok=0, Err=1 — alphabetical) */
    ((int64_t *)(result + 1))[0] = (int64_t)march_val;
    return result;
}

/* ---- Encode helpers ---- */

static yyjson_mut_val *march_to_yyjson_mut(void *v, yyjson_mut_doc *doc);

static yyjson_mut_val *march_list_to_yyjson_arr(void *list, yyjson_mut_doc *doc) {
    yyjson_mut_val *arr = yyjson_mut_arr(doc);
    /* Walk the cons-list */
    void *cur = list;
    while (1) {
        march_hdr *node = (march_hdr *)cur;
        if (node->tag == 0) break; /* Nil */
        int64_t *fields = (int64_t *)(node + 1);
        yyjson_mut_arr_append(arr, march_to_yyjson_mut((void *)fields[0], doc));
        cur = (void *)fields[1];
    }
    return arr;
}

static yyjson_mut_val *march_list_to_yyjson_obj(void *list, yyjson_mut_doc *doc) {
    yyjson_mut_val *obj = yyjson_mut_obj(doc);
    void *cur = list;
    while (1) {
        march_hdr *node = (march_hdr *)cur;
        if (node->tag == 0) break; /* Nil */
        int64_t *fields = (int64_t *)(node + 1);
        /* fields[0] = tuple (String, Json) */
        march_hdr *pair = (march_hdr *)(void *)fields[0];
        int64_t *pf = (int64_t *)(pair + 1);
        march_string *key_str = (march_string *)(void *)pf[0];
        yyjson_mut_val *k = yyjson_mut_strncpy(doc, key_str->data, (size_t)key_str->len);
        yyjson_mut_val *val_v = march_to_yyjson_mut((void *)pf[1], doc);
        yyjson_mut_obj_add(obj, k, val_v);
        cur = (void *)fields[1];
    }
    return obj;
}

static yyjson_mut_val *march_to_yyjson_mut(void *v, yyjson_mut_doc *doc) {
    march_hdr *node = (march_hdr *)v;
    int64_t *fields = (int64_t *)(node + 1);
    switch (node->tag) {
    case JSON_TAG_NULL:  return yyjson_mut_null(doc);
    case JSON_TAG_BOOL:  return yyjson_mut_bool(doc, fields[0] != 0);
    case JSON_TAG_INT:   return yyjson_mut_sint(doc, (int64_t)fields[0]);
    case JSON_TAG_FLOAT: return yyjson_mut_real(doc, *(double *)fields);
    case JSON_TAG_STR: {
        march_string *ms = (march_string *)(void *)fields[0];
        return yyjson_mut_strncpy(doc, ms->data, (size_t)ms->len);
    }
    case JSON_TAG_ARRAY:  return march_list_to_yyjson_arr((void *)fields[0], doc);
    case JSON_TAG_OBJECT: return march_list_to_yyjson_obj((void *)fields[0], doc);
    default: return yyjson_mut_null(doc);
    }
}

static void *encode_impl(void *json_val, yyjson_write_flag flags) {
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *root = march_to_yyjson_mut(json_val, doc);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_write_err err;
    size_t out_len;
    char *out = yyjson_mut_write_opts(doc, flags, NULL, &out_len, &err);
    yyjson_mut_doc_free(doc);
    if (!out) {
        void *empty = march_string_lit("", 0);
        return empty;
    }
    void *result = march_string_lit(out, (int64_t)out_len);
    free(out);
    return result;
}

void *march_json_encode(void *json_val) {
    return encode_impl(json_val, 0);
}

void *march_json_encode_pretty(void *json_val) {
    return encode_impl(json_val, YYJSON_WRITE_PRETTY);
}
```

- [ ] **Step 2: Verify C compiles (standalone check)**

```bash
cc -c runtime/march_json.c -Iruntime -o /tmp/march_json_test.o
```
Expected: no errors or warnings about undefined types (march_runtime.h provides them).

- [ ] **Step 3: Commit**

```bash
git add runtime/march_json.c
git commit -m "feat(runtime): add march_json C wrapper around yyjson"
```

---

### Task 8: Update `runtime/march_runtime.h`

**Files:**
- Modify: `runtime/march_runtime.h`

- [ ] **Step 1: Add JSON function declarations**

At the end of `runtime/march_runtime.h`, add:

```c
/* JSON builtins (compiled path — uses yyjson). */
/* Returns a March Result(Json, JsonError) heap object. */
void *march_json_parse(const char *s, int64_t len);
/* Returns a march_string*. */
void *march_json_encode(void *json_val);
void *march_json_encode_pretty(void *json_val);
```

- [ ] **Step 2: Build**

```bash
dune build
```
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add runtime/march_runtime.h
git commit -m "feat(runtime): declare march_json_* in march_runtime.h"
```

---

### Task 9: Update `lib/tir/llvm_emit.ml`

**Files:**
- Modify: `lib/tir/llvm_emit.ml`

Four locations need changes. All are in the same file.

- [ ] **Step 1: Add to `is_builtin_fn` list (line ~131)**

Find:
```ocaml
                 "get_work_pool"]
```
Change to:
```ocaml
                 "get_work_pool";
                 "json_parse"; "json_encode"; "json_encode_pretty"]
```

- [ ] **Step 2: Add to `builtin_ret_ty` (line ~150)**

Find:
```ocaml
  | "send"                        -> Some (Tir.TCon ("Option", [Tir.TUnit]))
  | _ -> None
```
Add before the `| _ -> None`:
```ocaml
  | "json_parse"         -> Some (Tir.TCon ("Result",
                              [Tir.TCon ("Json", []); Tir.TCon ("JsonError", [])]))
  | "json_encode"        -> Some Tir.TString
  | "json_encode_pretty" -> Some Tir.TString
```

- [ ] **Step 3: Add to `mangle_extern` (line ~167)**

Find:
```ocaml
  | "send"          -> "march_send"
```
Add after it:
```ocaml
  | "json_parse"         -> "march_json_parse"
  | "json_encode"        -> "march_json_encode"
  | "json_encode_pretty" -> "march_json_encode_pretty"
```

- [ ] **Step 4: Add `declare` lines to the LLVM IR preamble string (line ~1094)**

Find:
```
declare ptr  @march_send(ptr %actor, ptr %msg)
```
Add after it:
```
declare ptr  @march_json_parse(ptr %s, i64 %len)
declare ptr  @march_json_encode(ptr %json_val)
declare ptr  @march_json_encode_pretty(ptr %json_val)
```

- [ ] **Step 5: Extend the clang command in `bin/main.ml` to compile JSON C files**

The compiler drives clang directly from `bin/main.ml` (around line 192–213). Find this block:

```ocaml
        let candidates = [
          "runtime/march_runtime.c";
          Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
          Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
        ] in
        let runtime = match List.find_opt Sys.file_exists candidates with
          | Some p -> p
          | None ->
            Printf.eprintf "march: cannot find runtime/march_runtime.c\n"; exit 1
        in
```

And the command line:
```ocaml
        let cmd = Printf.sprintf "clang%s %s %s -o %s" opt_flag runtime ll_file out_bin in
```

Replace with:

```ocaml
        let find_runtime name =
          let candidates = [
            Filename.concat "runtime" name;
            Filename.concat (Filename.dirname Sys.executable_name) (Filename.concat "../runtime" name);
            Filename.concat (Filename.dirname Sys.executable_name) (Filename.concat "../../runtime" name);
          ] in
          match List.find_opt Sys.file_exists candidates with
          | Some p -> p
          | None ->
            Printf.eprintf "march: cannot find runtime/%s\n" name; exit 1
        in
        let runtime       = find_runtime "march_runtime.c" in
        let runtime_json  = find_runtime "march_json.c" in
        let runtime_yyjson = find_runtime "yyjson.c" in
        let runtime_dir   = Filename.dirname runtime in
```

And:
```ocaml
        let cmd = Printf.sprintf "clang%s -I%s %s %s %s %s -o %s"
          opt_flag runtime_dir runtime runtime_json runtime_yyjson ll_file out_bin in
```

The `-I%s` flag passes the `runtime/` directory so `march_json.c` can `#include "yyjson.h"` and `#include "march_runtime.h"`.

- [ ] **Step 6: Build and run tests**

```bash
dune build && dune runtest
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/llvm_emit.ml bin/main.ml
git commit -m "feat(codegen): register json builtins in LLVM emit; extend clang command for JSON C files"
```
