(** Golden rendered-diagnostic corpus (diagnostics plan §11, D7).

    Every [test/errors/<slug>_<n>.march] is checked with the real compiler
    ([march --check] and [march --check-json]) and its output compared byte for
    byte against two files beside it:

    - [<name>.expected]: the exit code, the full rendered diagnostics on stderr
      (carets, labels, notes, the [[slug]] suffix, the [march --explain]
      pointer), every machine fix rendered as a before/after diff of the
      lines it touches, and, when there is a fix, the result of applying
      every fix the way [forge fix] does and checking the program again
      ([after fix: exit N], plus the first diagnostic line if any): a fix
      the plan calls mechanical must leave a program that compiles (D4);
    - [<name>.json.expected]: the [--check-json] lines, so the machine form
      cannot drift from the human one.

    Nothing else in the tree pins a whole message: the [EXPECT-ERROR] corpora
    and the alcotest assertions pin fragments, so a caret that moves, a label
    that disappears or a fix that changes passes them all. The [.expected] diff
    is the review artifact for any message change.

    A source carrying [-- EXPECT-ERROR: <fragment>] (the programs seeded from
    [specs/lang/*/reject/]) must also contain that fragment in its rendered
    output, so the twin can never silently stop exercising the error it was
    copied for.

    Regenerate after an intentional change:
      [UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e]
    then review [git diff test/errors/].

    Each program is checked in a fresh temp directory as [errors/<file>], with
    a private [HOME], so the rendered header carries the same path wherever the
    suite runs and no cache from another worktree can leak in. One compiler
    process per program, so the once-per-run explain pointer is
    deterministic. [MARCH_JOBS] caps the parallel compiler runs (default 8). *)

let update_mode = Sys.getenv_opt "UPDATE_ERRORS" = Some "1"

let project_root () =
  if Sys.file_exists "test/errors" && Sys.is_directory "test/errors" then "."
  else Test_helpers.march_project_root ()

let errors_dir () = Filename.concat (project_root ()) "test/errors"

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let rec rm_rf p =
  if Sys.file_exists p then
    if Sys.is_directory p then begin
      Array.iter (fun f -> rm_rf (Filename.concat p f)) (Sys.readdir p);
      Sys.rmdir p
    end else Sys.remove p

(* One private HOME for the whole run: the stdlib typecheck cache it fills is
   keyed on the compiler and stdlib, so it is shared safely between programs
   and saves re-checking the stdlib per file. *)
let private_home =
  lazy begin
    let d = Filename.temp_dir "march-errors-home" "" in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    at_exit (fun () -> try rm_rf d with _ -> ());
    d
  end

(* ── Running the compiler, in parallel ─────────────────────────────────

   Each program needs two compiler runs (~0.5 s each); a few hundred programs
   run one at a time would make this the slowest suite in the tree. So every
   program's runs are started up front, [jobs] at a time, as [sh -c] children
   writing into the program's own temp dir; the alcotest cases then only read
   and compare. *)

let jobs =
  match Option.bind (Sys.getenv_opt "MARCH_JOBS") int_of_string_opt with
  | Some n when n > 0 -> n
  | _ -> 8

type result = { code : int; err : string; json : string;
                mutable after : (int * string) option;
                (** exit code and stderr of `--check` on the program with
                    every fix applied; [None] when it has no fix. *)
                mutable after_json : string
                (** the [--check-json] of that same fixed program. *) }

(* A program carrying a [-- MARCH-MODE:] line is not checked with [--check]:
   - [why-copies]: [--why-copies] / [--why-copies-json], the Perceus copy
     report (specs/2026-11-05-why-copies-design.md);
   - [run]: the program is RUN (interpreted) and its stderr pinned: a
     run-time failure report (panic, run-time error, actor crash).  There is
     no JSON form, so its [.json.expected] is empty. *)
let why_copies_marker = "-- MARCH-MODE: why-copies"
let run_marker = "-- MARCH-MODE: run"

let has_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let script ~dir ~rel ~src =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let home = Filename.quote (Lazy.force private_home) in
  let rel = Filename.quote rel in
  let human, json =
    if has_sub src run_marker then
      Printf.sprintf "HOME=%s %s %s" home exe rel, "true"
    else
      let h, j = if has_sub src why_copies_marker
        then "--why-copies", "--why-copies-json" else "--check", "--check-json" in
      Printf.sprintf "HOME=%s %s %s %s" home exe h rel,
      Printf.sprintf "HOME=%s %s %s %s" home exe j rel in
  Printf.sprintf
    "cd %s && %s > check.out 2> check.err; echo $? > check.code; \
     %s > json.out 2> /dev/null; true"
    (Filename.quote dir) human json

(* [run_jobs sources]: every (name, program text) checked in parallel;
   returns name -> result. *)
let run_jobs (sources : (string * string) list) : (string, result) Hashtbl.t =
  let results = Hashtbl.create 64 in
  let pending = Queue.create () in
  List.iter (fun n -> Queue.add n pending) sources;
  let running = Hashtbl.create 16 in
  let start (name, src) =
    let tmp = Filename.temp_dir "march-errors" "" in
    let edir = Filename.concat tmp "errors" in
    Unix.mkdir edir 0o755;
    write_file (Filename.concat edir (name ^ ".march")) src;
    let rel = "errors/" ^ name ^ ".march" in
    let pid =
      Unix.create_process "/bin/sh" [| "/bin/sh"; "-c"; script ~dir:tmp ~rel ~src |]
        Unix.stdin Unix.stdout Unix.stderr in
    Hashtbl.replace running pid (name, tmp)
  in
  let finish pid =
    let (name, tmp) = Hashtbl.find running pid in
    Hashtbl.remove running pid;
    let f x = Filename.concat tmp x in
    let code = int_of_string (String.trim (read_file (f "check.code"))) in
    Hashtbl.replace results name
      { code; err = read_file (f "check.err"); json = read_file (f "json.out");
        after = None; after_json = "" };
    (try rm_rf tmp with _ -> ())
  in
  while not (Queue.is_empty pending) || Hashtbl.length running > 0 do
    while not (Queue.is_empty pending) && Hashtbl.length running < jobs do
      start (Queue.pop pending)
    done;
    let (pid, _) = Unix.wait () in
    if Hashtbl.mem running pid then finish pid
  done;
  results

(* ── Applying the fixes, as forge fix does ─────────────────────────────── *)

let lines_of s = String.split_on_char '\n' s

(* A fix's edits: a multi-edit fix ({"kind":"multi","edits":[...]}) is its
   edits, every other fix is itself. *)
let edits_of_fix (f : Yojson.Safe.t) : Yojson.Safe.t list =
  let open Yojson.Safe.Util in
  match member "kind" f with
  | `String "multi" -> to_list (member "edits" f)
  | _ -> [ f ]

(* The fixes a `--check-json` run carries, in the order they appear, each
   multi-edit fix as its edits. *)
let fixes_of_json json : Yojson.Safe.t list =
  lines_of json
  |> List.filter (fun l -> String.trim l <> "")
  |> List.filter_map (fun l ->
      match Yojson.Safe.from_string l with
      | j -> (match Yojson.Safe.Util.member "fix" j with `Null -> None | f -> Some f)
      | exception _ -> None)
  |> List.concat_map edits_of_fix

(* Apply every fix to [src], bottom-up so earlier line numbers stay valid,
   with forge/lib/cmd_fix.ml's semantics: an insert goes after its line, a
   delete removes whole lines, a replace edits within one line (a multi-line
   replace is skipped, as forge skips it). *)
let apply_fixes ~src (fixes : Yojson.Safe.t list) : string =
  let open Yojson.Safe.Util in
  let int k f = member k f |> to_int in
  (* (line, column), so two replaces on one line apply right to left. *)
  let key f = match member "kind" f |> to_string with
    | "insert" -> (int "after_line" f, max_int) | "delete" -> (int "end_line" f, max_int)
    | _ -> (int "start_line" f, int "start_col" f) in
  let fixes = List.stable_sort (fun a b -> compare (key b) (key a)) fixes in
  let lines = ref (Array.of_list (lines_of src)) in
  List.iter (fun f ->
      let ls = !lines in
      let n = Array.length ls in
      match member "kind" f |> to_string with
      | "insert" ->
        let after = int "after_line" f in
        if after >= 0 && after <= n then
          lines := Array.concat [ Array.sub ls 0 after;
                                  [| member "text" f |> to_string |];
                                  Array.sub ls after (n - after) ]
      | "delete" ->
        let s = int "start_line" f and e = int "end_line" f in
        if s >= 1 && e <= n && s <= e then
          lines := Array.concat [ Array.sub ls 0 (s - 1); Array.sub ls e (n - e) ]
      | "replace" ->
        let sl = int "start_line" f and el = int "end_line" f in
        if sl = el && sl >= 1 && sl <= n then begin
          let orig = ls.(sl - 1) in
          let clamp c = max 0 (min c (String.length orig)) in
          let sc = clamp (int "start_col" f) and ec = clamp (int "end_col" f) in
          let ls = Array.copy ls in
          ls.(sl - 1) <- String.sub orig 0 sc ^ (member "text" f |> to_string)
                         ^ String.sub orig ec (String.length orig - ec);
          lines := ls
        end
      | _ -> ())
    fixes;
  String.concat "\n" (Array.to_list !lines)

(* Phase 1 checks every program; phase 2 re-checks, in the same way, every
   program that carried a fix, with its fixes applied. *)
let run_all (names : string list) : (string, result) Hashtbl.t =
  let src_of name = read_file (Filename.concat (errors_dir ()) (name ^ ".march")) in
  let results = run_jobs (List.map (fun n -> (n, src_of n)) names) in
  let fixed =
    List.filter_map (fun n ->
        let r = Hashtbl.find results n in
        match fixes_of_json r.json with
        | [] -> None
        | fixes -> Some (n, apply_fixes ~src:(src_of n) fixes))
      names
  in
  let after = run_jobs fixed in
  Hashtbl.iter (fun n (r : result) ->
      let o = Hashtbl.find results n in
      o.after <- Some (r.code, r.err); o.after_json <- r.json) after;
  results

(* ── Fixes as diffs ────────────────────────────────────────────────────── *)

let render_fix ~src (j : Yojson.Safe.t) : string option =
  let open Yojson.Safe.Util in
  match member "fix" j with
  | `Null -> None
  | fix ->
    let lines = Array.of_list (lines_of src) in
    let line n = if n >= 1 && n <= Array.length lines then lines.(n - 1) else "" in
    let buf = Buffer.create 128 in
    let code = member "code" j |> to_string in
    Printf.bprintf buf "fix [%s]:\n" code;
    (* A multi-edit fix renders one hunk per edit, in source order. *)
    let pos f = match member "kind" f |> to_string with
      | "insert" -> (member "after_line" f |> to_int, max_int)
      | "delete" -> (member "start_line" f |> to_int, 0)
      | _ -> (member "start_line" f |> to_int, member "start_col" f |> to_int) in
    let edits = List.stable_sort (fun a b -> compare (pos a) (pos b)) (edits_of_fix fix) in
    List.iter (fun fix ->
        match member "kind" fix |> to_string with
        | "insert" ->
          let after = member "after_line" fix |> to_int in
          let text = member "text" fix |> to_string in
          Printf.bprintf buf "@@ after line %d @@\n %s\n" after (line after);
          List.iter (fun l -> Printf.bprintf buf "+%s\n" l) (lines_of text)
        | "delete" ->
          let s = member "start_line" fix |> to_int
          and e = member "end_line" fix |> to_int in
          Printf.bprintf buf "@@ lines %d-%d @@\n" s e;
          for n = s to e do Printf.bprintf buf "-%s\n" (line n) done
        | "replace" ->
          let sl = member "start_line" fix |> to_int
          and sc = member "start_col" fix |> to_int
          and el = member "end_line" fix |> to_int
          and ec = member "end_col" fix |> to_int
          and text = member "text" fix |> to_string in
          let first = line sl and last = line el in
          let clip s n = String.sub s 0 (max 0 (min n (String.length s))) in
          let from s n =
            let n = max 0 (min n (String.length s)) in
            String.sub s n (String.length s - n) in
          let after = clip first sc ^ text ^ from last ec in
          Printf.bprintf buf "@@ lines %d-%d @@\n" sl el;
          for n = sl to el do Printf.bprintf buf "-%s\n" (line n) done;
          List.iter (fun l -> Printf.bprintf buf "+%s\n" l) (lines_of after)
        | k -> Printf.bprintf buf "(unknown fix kind %s)\n" k)
      edits;
    Some (Buffer.contents buf)

(* ── One corpus program ────────────────────────────────────────────────── *)

let expect_error_fragments src =
  let marker = "-- EXPECT-ERROR:" in
  List.filter_map (fun l ->
      let l = String.trim l in
      let n = String.length marker in
      if String.length l >= n && String.sub l 0 n = marker then
        Some (String.trim (String.sub l n (String.length l - n)))
      else None)
    (lines_of src)

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let render results name =
  let src = read_file (Filename.concat (errors_dir ()) (name ^ ".march")) in
  let r = Hashtbl.find results name in
  let fixes =
    lines_of r.json
    |> List.filter (fun l -> String.trim l <> "")
    |> List.filter_map (fun l ->
        match Yojson.Safe.from_string l with
        | j -> render_fix ~src j
        | exception _ -> None)
  in
  (* The program with every fix applied, checked again: its exit code and,
     if it still fails, the first diagnostic headline (the line carrying the
     [slug]), so the .expected shows what the fix leaves behind. *)
  let after =
    match r.after with
    | None -> ""
    | Some (code, err) ->
      (* A headline ends in `[slug]` or `[slug:arg]`: a trailing bracket
         group whose slug is lower-case letters and underscores. *)
      let is_headline l =
        let l = String.trim l in
        let n = String.length l in
        match String.rindex_opt l '[' with
        | Some i when n > i + 2 && l.[n - 1] = ']' ->
          let body = String.sub l (i + 1) (n - i - 2) in
          let slug = match String.index_opt body ':' with
            | Some k -> String.sub body 0 k | None -> body in
          slug <> ""
          && String.for_all (fun c -> (c >= 'a' && c <= 'z') || c = '_') slug
        | _ -> false
      in
      (* The first headline of an ERROR block: a warning or hint block
         (`-- WARNING: …`, `-- HINT: …`) can render ahead of it. *)
      let headline =
        let rec go in_error = function
          | [] -> None
          | l :: rest when String.starts_with ~prefix:"-- " l ->
            go (not (String.starts_with ~prefix:"-- WARNING" l
                     || String.starts_with ~prefix:"-- HINT" l)) rest
          | l :: rest -> if in_error && is_headline l then Some l else go in_error rest
        in
        match go true (lines_of err) with
        | Some h -> Some h
        | None -> List.find_opt is_headline (lines_of err) in
      Printf.sprintf "\nafter fix: exit %d%s\n" code
        (match headline with
         | Some h when code <> 0 -> "\n" ^ String.trim h
         | _ -> "")
  in
  let human =
    Printf.sprintf "exit: %d\n%s%s%s" r.code r.err
      (if fixes = [] then "" else "\n" ^ String.concat "\n" fixes)
      after
  in
  (src, human, r.json)

(* The internals lint (specs/plans/2026-11-02-diagnostics-depth-plan.md §X4):
   a message must not name what the program never wrote.  Scanned: every
   backticked token on a prose line of the rendered output (source snippet
   lines, `N | …`, and caret lines echo the program and are skipped).
   Flagged, word by word, unless the word occurs in the program's own source:
   a `$`-prefixed synthetic binder (`$cb_arg`, `$elem`), a generated session
   state (`S_…`), a generated actor message type (`…_Msg`), and the list
   constructors `Cons` / `Nil`.  Known leaks still to fix are listed in
   [internals-allowlist.txt] as `<case> <token>`; that file may only shrink:
   a listed leak that no longer occurs fails too, so a fix removes its line. *)
let backticked line =
  let rec go i acc =
    match String.index_from_opt line i '`' with
    | None -> List.rev acc
    | Some a ->
      (match String.index_from_opt line (a + 1) '`' with
       | None -> List.rev acc
       | Some b -> go (b + 1) (String.sub line (a + 1) (b - a - 1) :: acc))
  in
  go 0 []

let is_snippet_line l =
  let t = String.trim l in
  t = ""
  || String.for_all (fun c -> c = '^' || c = ' ' || c = '~') t
  || (match String.index_opt t '|' with
      | Some i when i > 0 ->
        String.for_all (fun c -> (c >= '0' && c <= '9') || c = ' ')
          (String.sub t 0 i)
      | _ -> false)

let internal_words ~src tok =
  let words =
    String.split_on_char ' ' tok
    |> List.concat_map (String.split_on_char '(')
    |> List.concat_map (String.split_on_char '.')
    |> List.concat_map (String.split_on_char ',')
    |> List.concat_map (String.split_on_char ')')
  in
  let n = String.length in
  List.filter (fun w ->
      ((n w > 1 && w.[0] = '$')
       || (n w > 2 && String.sub w 0 2 = "S_")
       || (n w > 4 && String.sub w (n w - 4) 4 = "_Msg")
       || w = "Cons" || w = "Nil")
      && not (contains src w))
    words

(* Per word, not per token: a role the program names `Cons` makes
   `Stream.Cons` fine. *)
let internal_leaks ~src (rendered : string) : string list =
  lines_of rendered
  |> List.filter (fun l -> not (is_snippet_line l))
  |> List.concat_map backticked
  |> List.concat_map (internal_words ~src)
  |> List.sort_uniq compare

let internals_allowlist = lazy (
  let f = Filename.concat (errors_dir ()) "internals-allowlist.txt" in
  if not (Sys.file_exists f) then []
  else
    lines_of (read_file f)
    |> List.filter_map (fun l ->
        let l = String.trim l in
        if l = "" || l.[0] = '#' then None
        else match String.index_opt l ' ' with
          | Some i ->
            Some (String.sub l 0 i,
                  String.trim (String.sub l (i + 1) (String.length l - i - 1)))
          | None -> None))

let check_internals ~src name human =
  let leaks = internal_leaks ~src human in
  let allowed =
    List.filter_map (fun (c, t) -> if c = name then Some t else None)
      (Lazy.force internals_allowlist) in
  (match List.filter (fun t -> not (List.mem t allowed)) leaks with
   | [] -> ()
   | ts ->
     Alcotest.failf "%s: the message names %s, which the program never \
                     wrote (internals lint, see run_errors.ml)" name
       (String.concat ", " (List.map (Printf.sprintf "`%s`") ts)));
  List.iter (fun t ->
      if not (List.mem t leaks) then
        Alcotest.failf "%s: `%s` no longer leaks; remove `%s %s` from \
                        test/errors/internals-allowlist.txt" name t name t)
    allowed

(* The house-style lint (specs/plans/2026-11-02-diagnostics-depth-plan.md
   §X5), over each `--check-json` diagnostic's message and notes:

   - [quote]: a code name is in backticks, never in quotes (`'Poke'`):
     no `'ident'` outside a backticked span, in the message or a note;
   - [capital]: the headline (the message's first line) starts with an
     upper-case letter or a backticked name;
   - [period]: the headline ends a sentence (`.`, `?`, `!` or `:`);
   - [prefix]: the message does not repeat its severity (`Warning: …`), which
     the header already shows.

   Codes still to fix are listed in [style-allowlist.txt] as
   `<slug> <rule>`.  That file may only shrink: the full run fails on an
   entry no case violates any more, so a fix removes its line. *)
let style_rules = [ "quote"; "capital"; "period"; "prefix" ]

let strip_backticked s =
  let b = Buffer.create (String.length s) in
  let inside = ref false in
  String.iter (fun c ->
      if c = '`' then inside := not !inside
      else if not !inside then Buffer.add_char b c) s;
  Buffer.contents b

let has_quoted_ident s =
  let s = strip_backticked s in
  let n = String.length s in
  let is_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
  let is_id c = is_start c || (c >= '0' && c <= '9') || c = '.' in
  let rec go i =
    if i >= n then false
    else if s.[i] = '\'' && (i = 0 || not (is_id s.[i - 1]))
            && i + 1 < n && is_start s.[i + 1] then
      let j = ref (i + 1) in
      while !j < n && is_id s.[!j] do incr j done;
      (!j < n && s.[!j] = '\'') || go (i + 1)
    else go (i + 1)
  in
  go 0

(* [(slug, rule, headline)] for every violation in a case's JSON output. *)
let style_violations (json : string) : (string * string * string) list =
  let open Yojson.Safe.Util in
  lines_of json
  |> List.filter (fun l -> String.trim l <> "")
  |> List.concat_map (fun l ->
      match Yojson.Safe.from_string l with
      | exception _ -> []
      | j ->
        let msg = member "message" j |> to_string in
        let notes = match member "notes" j with
          | `List ns -> List.filter_map (function `String s -> Some s | _ -> None) ns
          | _ -> [] in
        let code = member "code" j |> to_string in
        let slug = match String.index_opt code ':' with
          | Some i -> String.sub code 0 i | None -> code in
        let head = String.trim (List.hd (lines_of msg)) in
        let n = String.length head in
        let starts p = String.length head >= String.length p
                       && String.lowercase_ascii (String.sub head 0 (String.length p)) = p in
        List.filter_map (fun (rule, bad) -> if bad then Some (slug, rule, head) else None)
          [ ("quote", List.exists has_quoted_ident (msg :: notes));
            ("capital", n = 0 || not ((head.[0] >= 'A' && head.[0] <= 'Z') || head.[0] = '`'));
            ("period", n = 0 || not (String.contains ".?!:" head.[n - 1]));
            ("prefix", List.exists starts [ "warning:"; "error:"; "hint:" ]) ])

let style_allowlist = lazy (
  let f = Filename.concat (errors_dir ()) "style-allowlist.txt" in
  if not (Sys.file_exists f) then []
  else
    lines_of (read_file f)
    |> List.filter_map (fun l ->
        let l = String.trim l in
        if l = "" || l.[0] = '#' then None
        else match String.split_on_char ' ' l |> List.filter (( <> ) "") with
          | [ slug; rule ] when List.mem rule style_rules -> Some (slug, rule)
          | _ -> failwith ("style-allowlist.txt: bad line: " ^ l)))

let check_style name json =
  let allowed = Lazy.force style_allowlist in
  match List.filter (fun (s, r, _) -> not (List.mem (s, r) allowed))
          (style_violations json) with
  | [] -> ()
  | vs ->
    Alcotest.failf "%s: house-style lint (see run_errors.ml):\n%s" name
      (String.concat "\n"
         (List.map (fun (s, r, h) -> Printf.sprintf "  [%s] %s: %s" s r h) vs))

(* The hint-exclusivity lint (specs/plans/2026-11-02-diagnostics-depth-plan.md
   §X4): one diagnostic carries hints that agree, each said once.  Over each
   case's `--check-json` diagnostics:

   - [repeat]: a note repeats an earlier note or a line of the message;
   - [help]: more than one `help:` / `hint:` line, i.e. two competing fixes
     offered as separate advice (alternatives belong in one line);
   - [did-you-mean]: more than one "Did you mean" suggestion;
   - [convert]: more than one conversion hint (`Use `…` to convert`,
     "does not coerce"): the type mismatch has one likely cause;
   - [stacked]: a HINT on the exact span of an error, where the advisory can
     contradict the error's own fix ([Errors.suppress_cascades] drops it).

   No allowlist: the corpus is clean, and a new violation is a bug in the
   hint selection, not something to record. *)
let hint_violations (json : string) : string list =
  let open Yojson.Safe.Util in
  let ds =
    lines_of json
    |> List.filter_map (fun l ->
        if String.trim l = "" then None
        else match Yojson.Safe.from_string l with
          | exception _ -> None
          | j -> Some j) in
  let span j = List.map (fun k -> member k j) [ "file"; "start_line"; "start_col"; "end_line"; "end_col" ] in
  let sev j = match member "severity" j with `String s -> s | _ -> "" in
  let error_spans = List.filter_map (fun j -> if sev j = "error" then Some (span j) else None) ds in
  let norm s =
    String.split_on_char '\n' s |> List.map String.trim
    |> List.filter (( <> ) "") |> String.concat " " in
  List.concat_map (fun j ->
      let msg = match member "message" j with `String s -> s | _ -> "" in
      let notes = match member "notes" j with
        | `List ns -> List.filter_map (function `String s -> Some s | _ -> None) ns
        | _ -> [] in
      let code = match member "code" j with `String s -> s | _ -> "" in
      let head = String.trim (List.hd (lines_of msg @ [ "" ])) in
      let msg_lines = List.map String.trim (lines_of msg) in
      let all_lines = msg_lines @ List.concat_map (fun n -> List.map String.trim (lines_of n)) notes in
      let count p = List.length (List.filter p all_lines) in
      let starts prefix l = String.starts_with ~prefix (String.lowercase_ascii l) in
      let rec repeated seen = function
        | [] -> false
        | n :: rest ->
          let k = norm n in
          List.mem k seen || List.mem k msg_lines || repeated (k :: seen) rest in
      List.filter_map (fun (rule, bad) ->
          if bad then Some (Printf.sprintf "[%s] %s: %s" rule code head) else None)
        [ ("repeat", repeated [] notes);
          ("help", count (fun l -> starts "help:" l || starts "hint:" l) > 1);
          ("did-you-mean", count (fun l -> contains l "Did you mean") > 1);
          ("convert", count (fun l -> (contains l "Use `" && contains l "to convert")
                                     || contains l "does not coerce") > 1);
          ("stacked", sev j = "hint" && List.mem (span j) error_spans) ])
    ds

let check_hints name json =
  match hint_violations json with
  | [] -> ()
  | vs ->
    Alcotest.failf "%s: hint-exclusivity lint (see run_errors.ml):\n  %s" name
      (String.concat "\n  " vs)

(* A machine fix must fix (plan §X4): a case whose fixes leave the program
   still rejected fails, unless its source says why with
   `-- EXPECT-FIX-PARTIAL: <reason>` (the program has a second, independent
   error the fix is not about).  A case carrying the marker whose fixes do
   reach exit 0 fails too, so a stale marker can't hide a later regression. *)
let fix_partial_marker = "-- EXPECT-FIX-PARTIAL:"

(* The error diagnostics of a [--check-json] run, as (slug, has a fix). *)
let errors_of_json json : (string * bool) list =
  let open Yojson.Safe.Util in
  lines_of json
  |> List.filter_map (fun l ->
      match Yojson.Safe.from_string l with
      | j when (try member "severity" j |> to_string = "error" with _ -> false) ->
        let code = try member "code" j |> to_string with _ -> "" in
        let slug = match String.index_opt code ':' with
          | Some i -> String.sub code 0 i | None -> code in
        Some (slug, member "fix" j <> `Null)
      | _ -> None
      | exception _ -> None)

(* A program can carry an error that has no machine fix beside one that has
   (a refinement violation in a `main` that also forgot its grant).  Its
   fixes cannot reach exit 0, and need not: they pass when every error left
   after applying them is one of the errors that offered no fix, so each
   fix cleared what it was about and broke nothing else. *)
let fixes_did_their_part (r : result) =
  let before = errors_of_json r.json in
  let unfixed = List.filter_map (fun (s, f) -> if f then None else Some s) before in
  unfixed <> []
  && List.for_all (fun (s, _) -> List.mem s unfixed) (errors_of_json r.after_json)

let check_fix_fixes ~src name (r : result) =
  let partial = contains src fix_partial_marker in
  (* A copy report exits 0 either way: its fix must make the copy go away. *)
  (match r.after with
   | Some (_, err) when contains src why_copies_marker && contains err "[copy_shared]" ->
     Alcotest.failf "%s: applying its fixes still reports a copy" name
   | _ -> ());
  match r.after with
  | Some (code, _) when code <> 0 && not partial && fixes_did_their_part r -> ()
  | Some (code, _) when code <> 0 && not partial ->
    Alcotest.failf "%s: applying its machine fixes leaves the program rejected \
                    (exit %d). Fix the fix, or mark the case with %S and the \
                    reason the program still fails" name code fix_partial_marker
  | Some (0, _) when partial ->
    Alcotest.failf "%s: its fixes now make the program check; remove its %S line"
      name fix_partial_marker
  | None when partial ->
    Alcotest.failf "%s: it offers no machine fix; remove its %S line"
      name fix_partial_marker
  | _ -> ()

let check results name () =
  let (src, human, json) = render (Lazy.force results) name in
  let base = Filename.concat (errors_dir ()) name in
  let exp_h = base ^ ".expected" and exp_j = base ^ ".json.expected" in
  List.iter (fun frag ->
      if not (contains human frag) then
        Alcotest.failf "%s: the rendered output no longer contains its \
                        EXPECT-ERROR fragment %S" name frag)
    (expect_error_fragments src);
  if update_mode then begin
    write_file exp_h human; write_file exp_j json
  end else begin
    let cmp what file actual =
      if not (Sys.file_exists file) then
        Alcotest.failf "%s: %s missing (run with UPDATE_ERRORS=1)" name file
      else
        let expected = read_file file in
        if expected <> actual then
          Alcotest.failf
            "%s: %s differs.\n--- expected (%s)\n%s\n--- actual\n%s\n\
             (regenerate with UPDATE_ERRORS=1 if intended, then review \
             `git diff test/errors/`)"
            name what file expected actual
    in
    cmp "rendered diagnostics" exp_h human;
    cmp "--check-json" exp_j json
  end;
  check_internals ~src name human;
  check_style name json;
  check_hints name json;
  check_fix_fixes ~src name (Hashtbl.find (Lazy.force results) name)

(* [ERRORS_ONLY=cap_,linear_used_twice_6] runs only the cases whose name
   starts with one of the comma-separated prefixes: the whole corpus is a
   few minutes on an idle machine, and a change that can reach a few codes
   needs only those during the edit loop.  The full run still gates. *)
let only =
  match Sys.getenv_opt "ERRORS_ONLY" with
  | None | Some "" -> None
  | Some s -> Some (List.filter (( <> ) "") (String.split_on_char ',' s))

let corpus () =
  Sys.readdir (errors_dir ())
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.map Filename.remove_extension
  |> List.filter (fun n ->
      match only with
      | None -> true
      | Some ps -> List.exists (fun prefix -> String.starts_with ~prefix n) ps)
  |> List.sort compare

let () =
  let names = corpus () in
  let results = lazy (run_all names) in
  let cases =
    List.map (fun n -> Alcotest.test_case n `Quick (check results n)) names
  in
  (* The style allowlist may only shrink: on a full run, an entry that no
     case violates any more fails. *)
  let style_current () =
    if only = None then begin
      let seen =
        List.concat_map (fun n ->
            List.map (fun (s, r, _) -> (s, r))
              (style_violations (Hashtbl.find (Lazy.force results) n).json))
          names in
      List.iter (fun (s, r) ->
          if not (List.mem (s, r) seen) then
            Alcotest.failf "no case violates `%s %s` any more; remove it from \
                            test/errors/style-allowlist.txt" s r)
        (Lazy.force style_allowlist)
    end
  in
  let cases = cases @ [ Alcotest.test_case "style allowlist is current" `Quick style_current ] in
  Alcotest.run "errors" [ ("golden diagnostics", cases) ]
