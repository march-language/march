# File Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Path`, `File`, `Dir`, and `Seq` stdlib modules giving March programs full filesystem I/O with lazy streaming.

**Architecture:** OCaml builtins in `eval.ml` provide low-level I/O (open/read/close/stat). March-level stdlib files wrap them with `Result`-based error handling, a scoped `with_lines`/`with_chunks` resource pattern (mirroring `HttpClient.with_connection`), and a church-encoded `Seq(a)` type with lazy combinators. `Path` is pure March string manipulation — no builtins needed.

**Tech Stack:** OCaml 5.3.0 / Dune, March stdlib (`.march`), Alcotest tests in `test/test_march.ml`. Build: `dune build`. Test: `dune runtest`.

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `lib/eval/eval.ml` | Modify | Add ~20 file/dir builtins + `string_last_index_of` to `base_env` |
| `stdlib/file.march` | Create | `FileError`, `FileStat`, `File` module |
| `stdlib/dir.march` | Create | `Dir` module |
| `stdlib/path.march` | Create | `Path` module (pure March, no builtins) |
| `stdlib/seq.march` | Create | `Step`, `Seq` type + all combinators |
| `test/test_march.ml` | Modify | Add test suite for all four modules |

---

## Task 1: Add file builtins to eval.ml

**Files:**
- Modify: `lib/eval/eval.ml` (near the TCP builtins, search for `tcp_connect`)

### What we're building

Add these builtins to `base_env` in `eval.ml`. Each returns `VCon("Ok", [...])` or `VCon("Err", [VString msg])`.

Error helper to avoid repetition:

```ocaml
let file_err msg = VCon ("Err", [VCon ("IoError", [VString msg])])
let file_unix_err err path =
  let msg = Unix.error_message err in
  match err with
  | Unix.ENOENT  -> VCon ("Err", [VCon ("NotFound",    [VString path])])
  | Unix.EACCES  -> VCon ("Err", [VCon ("Permission",  [VString path])])
  | Unix.EISDIR  -> VCon ("Err", [VCon ("IsDirectory", [VString path])])
  | Unix.ENOTEMPTY -> VCon ("Err", [VCon ("NotEmpty",  [VString path])])
  | _            -> VCon ("Err", [VCon ("IoError",     [VString (path ^ ": " ^ msg)])])
```

- [ ] **Step 1: Write a failing Alcotest test for a builtin**

Add to `test_march.ml` (you'll flesh out the full builtin test suite after implementation):

```ocaml
let test_file_builtin_exists_false () =
  (* If file_exists builtin is missing, this will raise an eval error *)
  let env = eval_with_stdlib [] {|mod T do
    fn f() do file_exists("/nonexistent_march_test_xyz") end
  end|} in
  Alcotest.(check bool) "file_exists returns false" false
    (vbool (call_fn env "f" []))
```

Add to the test runner:
```ocaml
("file_builtins", [
  Alcotest.test_case "file_exists false" `Quick test_file_builtin_exists_false;
]);
```

Run:
```bash
dune runtest 2>&1 | grep -A5 "file_builtins"
```
Expected: fails with eval error (builtin not found).

- [ ] **Step 2: Add the file error helper and builtins**

Find the line with `; ("tcp_connect", ...)` in `eval.ml` and add the following block just before it:

```ocaml
(* ── File I/O ──────────────────────────────────────────────────── *)
; ("file_exists", VBuiltin ("file_exists", function
    | [VString path] -> VBool (Sys.file_exists path = `Yes)
    | _ -> eval_error "file_exists(path)"))

; ("file_read", VBuiltin ("file_read", function
    | [VString path] ->
      (try
         let ic = open_in path in
         let n = in_channel_length ic in
         let s = Bytes.create n in
         really_input ic s 0 n;
         close_in ic;
         VCon ("Ok", [VString (Bytes.to_string s)])
       with
       | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_read(path)"))

; ("file_write", VBuiltin ("file_write", function
    | [VString path; VString data] ->
      (try
         let oc = open_out path in
         output_string oc data;
         close_out oc;
         VCon ("Ok", [VAtom "ok"])
       with
       | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_write(path, data)"))

; ("file_append", VBuiltin ("file_append", function
    | [VString path; VString data] ->
      (try
         let oc = open_out_gen [Open_append; Open_creat] 0o644 path in
         output_string oc data;
         close_out oc;
         VCon ("Ok", [VAtom "ok"])
       with
       | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_append(path, data)"))

; ("file_delete", VBuiltin ("file_delete", function
    | [VString path] ->
      (try Sys.remove path; VCon ("Ok", [VAtom "ok"])
       with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_delete(path)"))

; ("file_copy", VBuiltin ("file_copy", function
    | [VString src; VString dst] ->
      (try
         let ic = open_in_bin src in
         (try
            let oc = open_out_bin dst in
            (try
               let buf = Bytes.create 65536 in
               let rec loop () =
                 let n = input ic buf 0 65536 in
                 if n > 0 then (output oc buf 0 n; loop ())
               in
               loop ();
               close_in ic; close_out oc;
               VCon ("Ok", [VAtom "ok"])
             with e -> close_in ic; close_out oc; raise e)
          with e -> close_in ic; raise e)
       with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_copy(src, dst)"))

; ("file_rename", VBuiltin ("file_rename", function
    | [VString src; VString dst] ->
      (try Sys.rename src dst; VCon ("Ok", [VAtom "ok"])
       with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "file_rename(src, dst)"))

; ("file_stat", VBuiltin ("file_stat", function
    | [VString path] ->
      (try
         let st = Unix.stat path in
         let kind = match st.Unix.st_kind with
           | Unix.S_REG  -> VCon ("RegularFile", [])
           | Unix.S_DIR  -> VCon ("Directory", [])
           | Unix.S_LNK  -> VCon ("Symlink", [])
           | _           -> VCon ("Other", [])
         in
         (* FileStat is a positional constructor: FileStat(size, kind, modified, accessed) *)
         VCon ("Ok", [VCon ("FileStat", [
           VInt st.Unix.st_size;
           kind;
           VInt (int_of_float st.Unix.st_mtime);
           VInt (int_of_float st.Unix.st_atime);
         ])])
       with
       | Unix.Unix_error (Unix.ENOENT, _, _) ->
         VCon ("Err", [VCon ("NotFound", [VString path])])
       | Unix.Unix_error (err, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "file_stat(path)"))

; ("file_open", VBuiltin ("file_open", function
    | [VString path] ->
      (try
         let fd = Unix.openfile path [Unix.O_RDONLY] 0 in
         let ic = Unix.in_channel_of_descr fd in
         VCon ("Ok", [VInt (Obj.magic ic : int)])
       with
       | Unix.Unix_error (Unix.ENOENT, _, _) ->
         VCon ("Err", [VCon ("NotFound", [VString path])])
       | Unix.Unix_error (Unix.EACCES, _, _) ->
         VCon ("Err", [VCon ("Permission", [VString path])])
       | Unix.Unix_error (err, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "file_open(path)"))

; ("file_read_line", VBuiltin ("file_read_line", function
    | [VInt ic_int] ->
      let ic : in_channel = Obj.magic ic_int in
      (try VCon ("Some", [VString (input_line ic)])
       with End_of_file -> VCon ("None", []))
    | _ -> eval_error "file_read_line(fd)"))

; ("file_read_chunk", VBuiltin ("file_read_chunk", function
    | [VInt ic_int; VInt size] ->
      let ic : in_channel = Obj.magic ic_int in
      let buf = Bytes.create size in
      (try
         let n = input ic buf 0 size in
         if n = 0 then VCon ("None", [])
         else VCon ("Some", [VString (Bytes.sub_string buf 0 n)])
       with End_of_file -> VCon ("None", []))
    | _ -> eval_error "file_read_chunk(fd, size)"))

; ("file_close", VBuiltin ("file_close", function
    | [VInt ic_int] ->
      let ic : in_channel = Obj.magic ic_int in
      (try close_in ic with _ -> ());
      VAtom "ok"
    | _ -> eval_error "file_close(fd)"))

(* ── Dir I/O ───────────────────────────────────────────────────── *)
; ("dir_exists", VBuiltin ("dir_exists", function
    | [VString path] ->
      (match Sys.file_exists path with
       | `Yes -> VBool (Sys.is_directory path)
       | _    -> VBool false)
    | _ -> eval_error "dir_exists(path)"))

; ("dir_list", VBuiltin ("dir_list", function
    | [VString path] ->
      (try
         let entries = Sys.readdir path in
         Array.sort String.compare entries;
         let lst = Array.fold_right
           (fun e acc -> VCon ("Cons", [VString e; acc]))
           entries (VCon ("Nil", [])) in
         VCon ("Ok", [lst])
       with
       | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
    | _ -> eval_error "dir_list(path)"))

; ("dir_mkdir", VBuiltin ("dir_mkdir", function
    | [VString path] ->
      (try Unix.mkdir path 0o755; VCon ("Ok", [VAtom "ok"])
       with
       | Unix.Unix_error (Unix.EEXIST, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (path ^ ": already exists")])])
       | Unix.Unix_error (err, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "dir_mkdir(path)"))

; ("dir_mkdir_p", VBuiltin ("dir_mkdir_p", function
    | [VString path] ->
      let parts = String.split_on_char '/' path
        |> List.filter (fun s -> s <> "") in
      let prefix = if String.length path > 0 && path.[0] = '/' then "/" else "" in
      (try
         List.fold_left (fun acc part ->
           let p = if acc = "" || acc = "/" then acc ^ part else acc ^ "/" ^ part in
           (* Ignore EEXIST: another process may have created the dir between check and mkdir *)
           (try
              if Sys.file_exists p <> `Yes then Unix.mkdir p 0o755
            with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
           p
         ) prefix parts |> ignore;
         VCon ("Ok", [VAtom "ok"])
       with
       | Unix.Unix_error (err, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "dir_mkdir_p(path)"))

; ("dir_rmdir", VBuiltin ("dir_rmdir", function
    | [VString path] ->
      (try Unix.rmdir path; VCon ("Ok", [VAtom "ok"])
       with
       | Unix.Unix_error (Unix.ENOTEMPTY, _, _) ->
         VCon ("Err", [VCon ("NotEmpty", [VString path])])
       | Unix.Unix_error (Unix.ENOENT, _, _) ->
         VCon ("Err", [VCon ("NotFound", [VString path])])
       | Unix.Unix_error (err, _, _) ->
         VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "dir_rmdir(path)"))

; ("dir_rm_rf", VBuiltin ("dir_rm_rf", function
    | [VString path] ->
      if path = "" || path = "/" then
        VCon ("Err", [VCon ("IoError", [VString "refusing to delete root"])])
      else
        let rec rm_rf p =
          match Unix.lstat p with
          | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
          | st ->
            if st.Unix.st_kind = Unix.S_DIR then begin
              let entries = Sys.readdir p in
              Array.iter (fun e -> rm_rf (p ^ "/" ^ e)) entries;
              Unix.rmdir p
            end else
              Sys.remove p
        in
        (try rm_rf path; VCon ("Ok", [VAtom "ok"])
         with
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
    | _ -> eval_error "dir_rm_rf(path)"))
```

- [ ] **Step 3: Build**

```bash
dune build
```
Expected: exits 0, no errors.

- [ ] **Step 4: Smoke test**

```bash
echo 'mod T do fn main() do println(file_exists("/tmp")) end end' | dune exec march -- /dev/stdin
```
Expected: prints `true`.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml
git commit -m "feat: add file/dir builtins to eval.ml"
```

---

## Task 2: Seq module (`stdlib/seq.march`)

**Files:**
- Create: `stdlib/seq.march`

The `Seq(a)` type is a church-encoded fold. In March, we represent it as an opaque ADT wrapping a closure.

- [ ] **Step 1: Write failing test** (in `test/test_march.ml`, in a new `test_seq_*` group)

Add this to the test file (after the existing stdlib tests):

```ocaml
let load_seq () = load_stdlib_file_for_test "seq.march"

let eval_with_seq src =
  eval_with_stdlib [load_seq ()] src

let test_seq_from_list () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, to_list}
    fn f() do from_list([1, 2, 3]) |> to_list end
  end|} in
  Alcotest.(check (list int)) "from_list round trips"
    [1; 2; 3]
    (vlist vint (call_fn env "f" []))

let () =
  Alcotest.run "march" [
    (* ... existing suites ... *)
    ("seq", [
      Alcotest.test_case "from_list round trips" `Quick test_seq_from_list;
    ]);
  ]
```

Run:
```bash
dune runtest 2>&1 | grep -A5 "seq"
```
Expected: compile error or test failure because `seq.march` doesn't exist yet.

- [ ] **Step 2: Write `stdlib/seq.march`**

```
-- Seq module: lazy fold-based sequences (church-encoded).
-- Seq(a) wraps fn(b, fn(b, a) -> b) -> b.
-- Enum operates eagerly on Lists; Seq operates lazily over I/O or generated sequences.

type Step(a) = Continue(a) | Halt(a)

-- Seq wraps a closure. March's type syntax cannot express the rank-2 type,
-- so we omit the type annotation — the constructor takes any value (the fold fn).
type Seq(a) = Seq(a)

mod Seq do

-- Construction

pub fn from_list(xs) do
  Seq(fn(acc, f) do
    fn go(lst, a) do
      match lst with
      | Nil -> a
      | Cons(h, t) -> go(t, f(a, h))
      end
    end
    go(xs, acc)
  end)
end

pub fn empty() do
  Seq(fn(acc, _f) do acc end)
end

pub fn unfold(seed, next) do
  Seq(fn(acc, f) do
    fn go(s, a) do
      match next(s) with
      | None -> a
      | Some((value, s2)) -> go(s2, f(a, value))
      end
    end
    go(seed, acc)
  end)
end

pub fn concat(s1, s2) do
  match s1 with
  | Seq(fold1) ->
    match s2 with
    | Seq(fold2) ->
      Seq(fn(acc, f) do
        let mid = fold1(acc, f)
        fold2(mid, f)
      end)
    end
  end
end

-- Transformation (lazy)

pub fn map(seq, f) do
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, g) do
      fold(acc, fn(a, x) -> g(a, f(x)) end)
    end)
  end
end

pub fn filter(seq, pred) do
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, f) do
      fold(acc, fn(a, x) ->
        if pred(x) then f(a, x) else a
      end)
    end)
  end
end

pub fn flat_map(seq, f) do
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, g) do
      fold(acc, fn(a, x) ->
        match f(x) with
        | Seq(inner_fold) -> inner_fold(a, g)
        end
      end)
    end)
  end
end

pub fn take(seq, n) do
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, f) do
      let result = fold((acc, 0), fn((a, count), x) ->
        if count >= n then (a, count)
        else (f(a, x), count + 1)
      end)
      match result with
      | (a, _) -> a
      end
    end)
  end
end

pub fn drop(seq, n) do
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, f) do
      let result = fold((acc, 0), fn((a, skipped), x) ->
        if skipped < n then (a, skipped + 1)
        else (f(a, x), skipped + 1)
      end)
      match result with
      | (a, _) -> a
      end
    end)
  end
end

pub fn zip(s1, s2) do
  -- Convert s2 to a list for indexed access, then zip
  let lst2 = to_list(s2)
  match s1 with
  | Seq(fold) ->
    Seq(fn(acc, f) do
      let result = fold((acc, lst2), fn((a, remaining), x) ->
        match remaining with
        | Nil -> (a, Nil)
        | Cons(y, rest) -> (f(a, (x, y)), rest)
        end
      end)
      match result with
      | (a, _) -> a
      end
    end)
  end
end

pub fn batch(seq, n) do
  -- Group elements into lists of size n.
  -- Uses Nil (not []) — March list syntax.
  -- List.reverse is used (not bare reverse) for clarity.
  match seq with
  | Seq(fold) ->
    Seq(fn(acc, f) do
      let result = fold((acc, Nil, 0), fn((a, buf, count), x) ->
        if count + 1 >= n then
          (f(a, List.reverse(Cons(x, buf))), Nil, 0)
        else
          (a, Cons(x, buf), count + 1)
      end)
      match result with
      | (a, Nil, _) -> a
      | (a, buf, _) -> f(a, List.reverse(buf))
      end
    end)
  end
end

-- Consumption (eager)

pub fn to_list(seq) do
  match seq with
  | Seq(fold) ->
    fold(Nil, fn(acc, x) -> Cons(x, acc) end)
    |> List.reverse
  end
end

pub fn fold(seq, init, f) do
  match seq with
  | Seq(folder) -> folder(init, f)
  end
end

pub fn fold_while(seq, init, f) do
  match seq with
  | Seq(folder) ->
    let result = folder(
      Continue(init),
      fn(step, x) ->
        match step with
        | Halt(a) -> Halt(a)
        | Continue(a) -> f(a, x)
        end
      end
    )
    match result with
    | Continue(a) -> a
    | Halt(a) -> a
    end
  end
end

pub fn each(seq, f) do
  match seq with
  | Seq(folder) ->
    folder(:ok, fn(_, x) -> f(x) end)
    :ok
  end
end

pub fn count(seq) do
  match seq with
  | Seq(fold) ->
    fold(0, fn(n, _) -> n + 1 end)
  end
end

pub fn find(seq, pred) do
  fold_while(seq, None, fn(_, x) ->
    if pred(x) then Halt(Some(x))
    else Continue(None)
  end)
end

-- Note: March identifiers cannot contain '?', so these are named `any` and `all`
pub fn any(seq, pred) do
  fold_while(seq, false, fn(_, x) ->
    if pred(x) then Halt(true)
    else Continue(false)
  end)
end

pub fn all(seq, pred) do
  fold_while(seq, true, fn(_, x) ->
    if pred(x) then Continue(true)
    else Halt(false)
  end)
end

end
```

**Note on `List.reverse`:** Use `List.reverse` (not bare `reverse`) throughout. Verify it is exported from `list.march` — if it's only in the prelude as `reverse`, adjust accordingly after reading `lib/eval/eval.ml`'s base_env.

**Note on `fold_while` and short-circuiting:** `fold_while` does NOT truly short-circuit the underlying iteration — with a church-fold model, the fold still visits every element but skips the user function on `Halt`. For finite lists this is correct but slightly inefficient. For file streaming (the primary use case), this means the file is always read to EOF even after `Halt`. This is acceptable for v1 — do not add exception-based short-circuit unless profiling shows it matters.

- [ ] **Step 3: Build**

```bash
dune build
```
Expected: exits 0.

- [ ] **Step 4: Run the seq tests**

```bash
dune runtest 2>&1 | grep -A10 "seq"
```
Expected: `test_seq_from_list` passes.

- [ ] **Step 5: Add more seq tests and run them**

Add these to the `("seq", [...])` list in `test_march.ml`:

```ocaml
let test_seq_map () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, map, to_list}
    fn f() do from_list([1, 2, 3]) |> map(fn(x) -> x * 2 end) |> to_list end
  end|} in
  Alcotest.(check (list int)) "map doubles" [2; 4; 6]
    (vlist vint (call_fn env "f" []))

let test_seq_filter () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, filter, to_list}
    fn f() do from_list([1,2,3,4,5]) |> filter(fn(x) -> x > 2 end) |> to_list end
  end|} in
  Alcotest.(check (list int)) "filter" [3; 4; 5]
    (vlist vint (call_fn env "f" []))

let test_seq_take () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, take, to_list}
    fn f() do from_list([1,2,3,4,5]) |> take(3) |> to_list end
  end|} in
  Alcotest.(check (list int)) "take 3" [1; 2; 3]
    (vlist vint (call_fn env "f" []))

let test_seq_fold_while () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, fold_while}
    fn f() do
      from_list([1,2,3,4,5])
      |> fold_while(0, fn(sum, x) ->
        if sum + x > 6 then Halt(sum)
        else Continue(sum + x)
      end)
    end
  end|} in
  Alcotest.(check int) "fold_while halts" 6
    (vint (call_fn env "f" []))

let test_seq_concat () =
  let env = eval_with_seq {|mod T do
    use Seq.{from_list, concat, to_list}
    fn f() do concat(from_list([1,2]), from_list([3,4])) |> to_list end
  end|} in
  Alcotest.(check (list int)) "concat" [1; 2; 3; 4]
    (vlist vint (call_fn env "f" []))
```

```bash
dune runtest 2>&1 | grep -E "(PASS|FAIL|seq)"
```
Expected: all seq tests pass.

- [ ] **Step 6: Commit**

```bash
git add stdlib/seq.march test/test_march.ml
git commit -m "feat: add Seq module with lazy fold-based combinators"
```

---

## Task 3: Path module (`stdlib/path.march`)

**Files:**
- Create: `stdlib/path.march`

Pure March — no builtins. Uses `String.*` functions from the stdlib.

- [ ] **Step 1: Write failing tests**

Add to `test_march.ml`:

```ocaml
let load_path () = load_stdlib_file_for_test "path.march"

let eval_with_path src =
  (* path.march uses string operations — load string.march first *)
  eval_with_stdlib [load_stdlib_file_for_test "string.march"; load_path ()] src

let test_path_join () =
  let env = eval_with_path {|mod T do
    use Path.{join}
    fn f() do join("foo/bar", "baz.txt") end
  end|} in
  Alcotest.(check string) "join" "foo/bar/baz.txt"
    (vstr (call_fn env "f" []))

let test_path_basename () =
  let env = eval_with_path {|mod T do
    use Path.{basename}
    fn f() do basename("/foo/bar/baz.txt") end
  end|} in
  Alcotest.(check string) "basename" "baz.txt"
    (vstr (call_fn env "f" []))

let test_path_extension () =
  let env = eval_with_path {|mod T do
    use Path.{extension}
    fn f() do extension("photo.png") end
  end|} in
  Alcotest.(check string) "extension" "png"
    (vstr (call_fn env "f" []))

let test_path_normalize () =
  let env = eval_with_path {|mod T do
    use Path.{normalize}
    fn f() do normalize("a/../b/./c") end
  end|} in
  Alcotest.(check string) "normalize" "b/c"
    (vstr (call_fn env "f" []))
```

Run:
```bash
dune runtest 2>&1 | grep -E "(path|FAIL)"
```
Expected: fails (path.march missing).

- [ ] **Step 2: Write `stdlib/path.march`**

```
-- Path module: pure path manipulation (no I/O).
-- All operations are pure string functions.

mod Path do

pub fn join(a, b) do
  if String.ends_with(a, "/") then a ++ b
  else a ++ "/" ++ b
end

pub fn basename(path) do
  -- List.last panics on empty; use fold to get last element safely
  let parts = String.split(path, "/")
  |> List.filter(fn(s) -> not (String.is_empty(s)) end)
  match parts with
  | Nil -> path
  | _ ->
    -- fold_left(acc, list, f) — accumulator first
    List.fold_left("", parts, fn(_, s) -> s end)
  end
end

pub fn dirname(path) do
  let parts = String.split(path, "/")
  |> List.filter(fn(s) -> not (String.is_empty(s)) end)
  match List.drop_last(parts) with
  | Nil -> if is_absolute(path) then "/" else "."
  | dirs ->
    -- String.join(list, sep) — list first, separator second
    let joined = String.join(dirs, "/")
    if is_absolute(path) then "/" ++ joined else joined
  end
end

pub fn extension(path) do
  let base = basename(path)
  match String.last_index_of(base, ".") with
  | None -> ""
  | Some(i) ->
    -- String.slice_bytes(s, start, len) — third arg is length, not end index
    let len = String.byte_size(base) - i - 1
    String.slice_bytes(base, i + 1, len)
  end
end

pub fn strip_extension(path) do
  let base = basename(path)
  let dir = dirname(path)
  match String.last_index_of(base, ".") with
  | None -> path
  | Some(i) ->
    let stem = String.slice_bytes(base, 0, i)
    if dir == "." then stem else dir ++ "/" ++ stem
  end
end

pub fn is_absolute(path) do
  String.starts_with(path, "/")
end

pub fn components(path) do
  String.split(path, "/")
  |> List.filter(fn(s) -> not (String.is_empty(s)) end)
end

pub fn normalize(path) do
  let abs = is_absolute(path)
  let parts = components(path)
  fn process(parts, stack) do
    match parts with
    | Nil -> stack
    | Cons(".", rest) -> process(rest, stack)
    | Cons("..", rest) ->
      match stack with
      | Nil ->
        if abs then process(rest, Nil)
        else process(rest, Cons("..", Nil))
      | Cons("..", _) -> process(rest, Cons("..", stack))
      | Cons(_, parent) -> process(rest, parent)
      end
    | Cons(seg, rest) -> process(rest, Cons(seg, stack))
    end
  end
  let stack = process(parts, Nil)
  let segs = List.reverse(stack)
  -- String.join(list, sep) — list first, separator second
  let joined = String.join(segs, "/")
  if abs then "/" ++ joined
  else if String.is_empty(joined) then "."
  else joined
end

end
```

Note: This requires `String.split`, `String.join`, `String.last_index_of`, and `List.last`, `List.drop_last`, `List.filter`, `List.reverse`. Check which are available in `string.march` and `list.march` — add missing helpers if needed (see Step 3).

- [ ] **Step 3: Check String and List dependencies**

```bash
grep -n "pub fn" stdlib/string.march stdlib/list.march
```

**Critical stdlib dependencies to verify and add if missing:**

- `String.split(s, sep)` — split string by separator, returns `List(String)`
- `String.join(xs, sep)` — join list with separator, returns `String` (**list first, sep second**)
- `String.last_index_of(s, sub)` — returns `Option(Int)` (byte index of last occurrence)
- `String.is_empty(s)` — returns `Bool`
- `String.slice_bytes(s, start, len)` — slice by byte offset+**length** (not end index)
- `List.drop_last(xs)` — all elements except last, returns `List(a)`
- `List.filter(xs, f)` — filter list (likely already in `list.march`)
- `List.fold_left(acc, xs, f)` — left fold (**accumulator first**, then list)
- `List.reverse(xs)` — reverse list

**Do NOT use `List.last`** — it returns `a` (panics on empty), not `Option(a)`.

**`String.last_index_of` requires an OCaml builtin.** Add this to `eval.ml` alongside the other string builtins:

```ocaml
; ("string_last_index_of", VBuiltin ("string_last_index_of", function
    | [VString s; VString sub] ->
      let slen = String.length s and sublen = String.length sub in
      if sublen = 0 then VCon ("Some", [VInt (slen)])
      else if sublen > slen then VCon ("None", [])
      else
        let result = ref None in
        for i = 0 to slen - sublen do
          if String.sub s i sublen = sub then result := Some i
        done;
        (match !result with
         | None -> VCon ("None", [])
         | Some i -> VCon ("Some", [VInt i]))
    | _ -> eval_error "string_last_index_of(s, sub)"))
```

Then wrap in `string.march`:
```
pub fn last_index_of(s, sub) do string_last_index_of(s, sub) end
```

**`List.drop_last` — add to `list.march`:**
```
pub fn drop_last(xs) do
  match List.reverse(xs) with
  | Nil -> Nil
  | Cons(_, rest) -> List.reverse(rest)
  end
end
```

Add any other missing functions before building `path.march`.

- [ ] **Step 4: Build and run path tests**

```bash
dune build && dune runtest 2>&1 | grep -E "(path|FAIL)"
```
Expected: all path tests pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/path.march stdlib/string.march stdlib/list.march test/test_march.ml
git commit -m "feat: add Path module (pure path manipulation)"
```

---

## Task 4: File module (`stdlib/file.march`)

**Files:**
- Create: `stdlib/file.march`

Depends on: `seq.march` (for `Seq` type and module).

- [ ] **Step 1: Write failing tests**

Add to `test_march.ml`:

```ocaml
let load_file_stdlib () =
  [ load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "file.march" ]

let eval_with_file src =
  eval_with_stdlib (load_file_stdlib ()) src

(* Helper: write a temp file and return its path *)
let with_temp_file content f =
  let path = Filename.temp_file "march_test_" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  let result = f path in
  (try Sys.remove path with _ -> ());
  result

let test_file_read () =
  with_temp_file "hello world" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn f() do
        match File.read("%s") with
        | Ok(s) -> s
        | Err(_) -> "fail"
        end
      end
    end|} path) in
    Alcotest.(check string) "read file" "hello world"
      (vstr (call_fn env "f" [])))

let test_file_write_read () =
  let path = Filename.temp_file "march_test_" ".txt" in
  (try
     let env = eval_with_file (Printf.sprintf {|mod T do
       fn f() do
         match File.write("%s", "written data") with
         | Ok(_) ->
           match File.read("%s") with
           | Ok(s) -> s
           | Err(_) -> "read fail"
           end
         | Err(_) -> "write fail"
         end
       end
     end|} path path) in
     let result = vstr (call_fn env "f" []) in
     (try Sys.remove path with _ -> ());
     Alcotest.(check string) "write then read" "written data" result
   with e -> (try Sys.remove path with _ -> ()); raise e)

let test_file_exists () =
  with_temp_file "x" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn f() do File.exists("%s") end
    end|} path) in
    Alcotest.(check bool) "exists" true
      (vbool (call_fn env "f" [])))

let test_file_with_lines () =
  with_temp_file "a\nb\nc" (fun path ->
    let env = eval_with_file (Printf.sprintf {|mod T do
      fn f() do
        match File.with_lines("%s", fn(lines) ->
          lines |> Seq.map(fn(l) -> l ++ "!" end) |> Seq.to_list
        end) with
        | Ok(xs) -> xs
        | Err(_) -> []
        end
      end
    end|} path) in
    Alcotest.(check (list string)) "with_lines" ["a!"; "b!"; "c!"]
      (vlist vstr (call_fn env "f" [])))
```

Run: confirm tests fail.

- [ ] **Step 2: Write `stdlib/file.march`**

```
-- File module: filesystem I/O.
-- All I/O functions return Result(value, FileError).
-- Use with_lines / with_chunks for streaming (resource cleanup guaranteed).

type FileError = NotFound(String)
               | Permission(String)
               | IsDirectory(String)
               | NotEmpty(String)
               | IoError(String)

type FileKind = RegularFile | Directory | Symlink | Other

-- FileStat uses a positional constructor (record syntax not valid inside variant args)
-- Access via pattern: FileStat(size, kind, modified, accessed)
type FileStat = FileStat(Int, FileKind, Int, Int)

mod File do

-- Read

pub fn read(path) do
  -- file_read returns Ok(String) or Err(IoError(msg)) — pass through
  file_read(path)
end

pub fn read_lines(path) do
  match file_read(path) with
  | Err(e) -> Err(e)
  | Ok(s) ->
    let lines = String.split(s, "\n")
    -- Remove trailing empty line from trailing newline
    match List.reverse(lines) with
    | Cons("", rest) -> Ok(List.reverse(rest))
    | _ -> Ok(lines)
    end
  end
end

-- Note: '?' is not valid in March identifiers; name is `exists` not `exists?`
pub fn exists(path) do
  file_exists(path)
end

pub fn stat(path) do
  file_stat(path)
end

-- Write

-- All write/mutate builtins return Ok(:ok) or Err(FileError(...)) directly — pass through

pub fn write(path, data) do file_write(path, data) end
pub fn append(path, data) do file_append(path, data) end
pub fn delete(path) do file_delete(path) end
pub fn copy(src, dest) do file_copy(src, dest) end
pub fn rename(src, dest) do file_rename(src, dest) end

-- Streaming (scoped, guarantees file handle cleanup)

pub fn with_lines(path, callback) do
  match file_open(path) with
  | Err(e) -> Err(e)
  | Ok(fd) ->
    let seq = Seq(fn(acc, f) do
      fn loop(a) do
        match file_read_line(fd) with
        | None -> a
        | Some(line) -> loop(f(a, line))
        end
      end
      loop(acc)
    end)
    let result = callback(seq)
    file_close(fd)
    Ok(result)
  end
end

pub fn with_chunks(path, size, callback) do
  match file_open(path) with
  | Err(e) -> Err(e)
  | Ok(fd) ->
    let seq = Seq(fn(acc, f) do
      fn loop(a) do
        match file_read_chunk(fd, size) with
        | None -> a
        | Some(chunk) -> loop(f(a, chunk))
        end
      end
      loop(acc)
    end)
    let result = callback(seq)
    file_close(fd)
    Ok(result)
  end
end

-- Low-level callbacks (side-effect iteration; prefer with_lines when callback returns a value)

pub fn each_line(path, f) do
  match file_open(path) with
  | Err(e) -> Err(e)
  | Ok(fd) ->
    fn loop() do
      match file_read_line(fd) with
      | None -> :ok
      | Some(line) ->
        f(line)
        loop()
      end
    end
    loop()
    file_close(fd)
    Ok(:ok)
  end
end

pub fn each_chunk(path, size, f) do
  match file_open(path) with
  | Err(e) -> Err(e)
  | Ok(fd) ->
    fn loop() do
      match file_read_chunk(fd, size) with
      | None -> :ok
      | Some(chunk) ->
        f(chunk)
        loop()
      end
    end
    loop()
    file_close(fd)
    Ok(:ok)
  end
end

end
```

- [ ] **Step 3: Build**

```bash
dune build
```
Expected: exits 0.

- [ ] **Step 4: Run file tests**

```bash
dune runtest 2>&1 | grep -E "(file|FAIL)"
```
Expected: all file tests pass.

- [ ] **Step 5: Add edge case tests**

```ocaml
let test_file_not_found () =
  let env = eval_with_file {|mod T do
    fn f() do
      match File.read("/nonexistent/path/xyz.txt") with
      | Ok(_) -> "ok"
      | Err(_) -> "err"
      end
    end
  end|} in
  Alcotest.(check string) "not found returns Err" "err"
    (vstr (call_fn env "f" []))

let test_file_append () =
  let path = Filename.temp_file "march_append_" ".txt" in
  (try
     let env = eval_with_file (Printf.sprintf {|mod T do
       fn f() do
         File.write("%s", "line1\n")
         File.append("%s", "line2\n")
         match File.read("%s") with
         | Ok(s) -> s
         | Err(_) -> "fail"
         end
       end
     end|} path path path) in
     let result = vstr (call_fn env "f" []) in
     (try Sys.remove path with _ -> ());
     Alcotest.(check string) "append" "line1\nline2\n" result
   with e -> (try Sys.remove path with _ -> ()); raise e)
```

```bash
dune runtest 2>&1 | grep -E "(file|FAIL)"
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add stdlib/file.march test/test_march.ml
git commit -m "feat: add File module with Result-based I/O and streaming"
```

---

## Task 5: Dir module (`stdlib/dir.march`)

**Files:**
- Create: `stdlib/dir.march`

- [ ] **Step 1: Write failing tests**

```ocaml
let load_dir_stdlib () =
  [ load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "file.march"
  ; load_stdlib_file_for_test "dir.march" ]

let eval_with_dir src =
  eval_with_stdlib (load_dir_stdlib ()) src

let test_dir_mkdir_list_rmdir () =
  let base = Filename.temp_dir "march_dir_" "" in
  let path = base ^ "/subdir" in
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.mkdir("%s") with
      | Err(_) -> "mkdir failed"
      | Ok(_) ->
        match Dir.list("%s") with
        | Err(_) -> "list failed"
        | Ok(entries) ->
          match Dir.rmdir("%s") with
          | Err(_) -> "rmdir failed"
          | Ok(_) -> "ok"
          end
        end
      end
    end
  end|} path base path) in
  (try Unix.rmdir path with _ -> ());
  (try Unix.rmdir base with _ -> ());
  Alcotest.(check string) "mkdir/list/rmdir" "ok"
    (vstr (call_fn env "f" []))
```

- [ ] **Step 2: Write `stdlib/dir.march`**

```
-- Dir module: directory I/O.
-- All operations return Result(value, FileError).

mod Dir do

pub fn list(path) do
  dir_list(path)
end

pub fn list_full(path) do
  match dir_list(path) with
  | Err(e) -> Err(e)
  | Ok(names) ->
    let prefix = if String.ends_with(path, "/") then path else path ++ "/"
    Ok(List.map(names, fn(name) -> prefix ++ name end))
  end
end

pub fn mkdir(path) do
  dir_mkdir(path)
end

pub fn mkdir_p(path) do
  dir_mkdir_p(path)
end

pub fn rmdir(path) do
  dir_rmdir(path)
end

pub fn rm_rf(path) do
  dir_rm_rf(path)
end

pub fn exists(path) do
  dir_exists(path)
end

end
```

- [ ] **Step 3: Build and test**

```bash
dune build && dune runtest 2>&1 | grep -E "(dir|FAIL)"
```
Expected: dir tests pass.

- [ ] **Step 4: Add rm_rf test**

```ocaml
let test_dir_rm_rf () =
  let base = Filename.temp_dir "march_rmrf_" "" in
  (* Create nested structure *)
  Unix.mkdir (base ^ "/sub") 0o755;
  let oc = open_out (base ^ "/sub/file.txt") in
  output_string oc "x"; close_out oc;
  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.rm_rf("%s") with
      | Ok(_) -> "ok"
      | Err(_) -> "err"
      end
    end
  end|} base) in
  Alcotest.(check string) "rm_rf nested" "ok"
    (vstr (call_fn env "f" []))

let test_dir_rm_rf_refuses_root () =
  let env = eval_with_dir {|mod T do
    fn f() do
      match Dir.rm_rf("/") with
      | Ok(_) -> "deleted root"
      | Err(_) -> "refused"
      end
    end
  end|} in
  Alcotest.(check string) "rm_rf refuses root" "refused"
    (vstr (call_fn env "f" []))
```

```bash
dune runtest 2>&1 | grep -E "(dir|FAIL)"
```

- [ ] **Step 5: Commit**

```bash
git add stdlib/dir.march test/test_march.ml
git commit -m "feat: add Dir module for directory operations"
```

---

## Task 6: Integration test & full test run

- [ ] **Step 1: Write an end-to-end integration test**

This tests Path + File + Dir + Seq together:

```ocaml
let test_integration_file_pipeline () =
  (* Create a temp dir with .txt files *)
  let base = Filename.temp_dir "march_integ_" "" in
  let write path content =
    let oc = open_out path in output_string oc content; close_out oc in
  write (base ^ "/a.txt") "hello\nworld\n";
  write (base ^ "/b.txt") "foo\nbar\n";
  write (base ^ "/c.csv") "ignore me";

  let env = eval_with_dir (Printf.sprintf {|mod T do
    fn f() do
      match Dir.list_full("%s") with
      | Err(_) -> []
      | Ok(files) ->
        files
        |> List.filter(fn(p) -> Path.extension(p) == "txt" end)
        |> List.flat_map(fn(p) ->
          match File.read_lines(p) with
          | Ok(ls) -> ls
          | Err(_) -> []
          end
        end)
      end
    end
  end|} base) in

  (* cleanup *)
  (try Sys.remove (base ^ "/a.txt") with _ -> ());
  (try Sys.remove (base ^ "/b.txt") with _ -> ());
  (try Sys.remove (base ^ "/c.csv") with _ -> ());
  (try Unix.rmdir base with _ -> ());

  let result = vlist vstr (call_fn env "f" []) in
  Alcotest.(check (list string)) "integration pipeline"
    ["hello"; "world"; "foo"; "bar"] result
```

Note: this test also requires loading `path.march` in the eval context. Update `load_dir_stdlib` to include it:

```ocaml
let load_dir_stdlib () =
  [ load_stdlib_file_for_test "string.march"
  ; load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "path.march"
  ; load_stdlib_file_for_test "file.march"
  ; load_stdlib_file_for_test "dir.march" ]
```

- [ ] **Step 2: Run full test suite**

```bash
dune runtest
```
Expected: all 50+ tests pass (the suite count will have grown).

- [ ] **Step 3: Final commit**

```bash
git add test/test_march.ml
git commit -m "test: add integration test for File/Dir/Path/Seq pipeline"
```

---

## Task 7: Update progress docs

- [ ] **Step 1: Add file module status to `specs/progress.md`**

Open `specs/progress.md` and find the stdlib section. Add:

```
## Stdlib: File System (added 2026-03-20)
- [x] Path module — pure path manipulation (join, basename, dirname, extension, normalize)
- [x] Seq module — lazy church-encoded fold sequences (map, filter, take, drop, fold_while, etc.)
- [x] File module — Result-based I/O (read, write, append, delete, copy, rename, with_lines, with_chunks)
- [x] Dir module — directory operations (list, mkdir, mkdir_p, rmdir, rm_rf)
- [x] FileError ADT — NotFound, Permission, IsDirectory, NotEmpty, IoError
- [x] Step(a) type — Continue/Halt for fold_while early termination
```

- [ ] **Step 2: Commit**

```bash
git add specs/progress.md
git commit -m "docs: update progress.md with file module status"
```
