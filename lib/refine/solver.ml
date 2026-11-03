(* Long-lived `z3 -in` subprocess driver.  One process per compilation unit;
   z3 is (reset) before every query, so a verdict depends only on the query,
   the z3 version and the rlimit — never on what ran before it. *)

(* z3's stdout, read through our own buffer rather than an in_channel so the
   hang backstop can tell "a line is already buffered" from "must wait on the
   fd": an in_channel hides how much it has buffered. *)
type reader = { fd : Unix.file_descr; buf : Bytes.t; mutable pos : int; mutable len : int }

type t = { ic : reader; oc : out_channel; pid : int }

type result =
  | Unsat                          (* goal holds — verified *)
  | Sat of (string * string) list  (* goal can fail — counterexample model *)
  | Unknown                        (* z3 said `unknown`: the rlimit ran out, or the
                                      query is outside what it decides.  Deterministic
                                      for a fixed query, z3 and rlimit, so cacheable. *)
  | Rejected                       (* z3 rejected the query (malformed): never cached *)

(* The driver's only wall clock: a z3 that has not answered after this long
   is wedged, not working.  It never fires on a healthy solver, whose work is
   bounded by the rlimit.  MARCH_Z3_BACKSTOP_MS overrides it (tests). *)
exception Hung

let backstop_ms () : int =
  match Sys.getenv_opt "MARCH_Z3_BACKSTOP_MS" with
  | Some s -> (match int_of_string_opt (String.trim s) with Some n when n > 0 -> n | _ -> 60_000)
  | None -> 60_000

(* Per-query resource limits (z3's `:rlimit`, a count of solver steps, not
   time).  The values are measured against the corpus and the stdlib
   (specs/progress/2026-11-02-z3-rlimit-measurement.md).  Stage-2 reflection
   queries get their own, smaller limit. *)
let default_rlimit = ref 3_000_000

let stage2_rlimit = ref 1_000_000

(* ── Lookup ────────────────────────────────────────────────────────────────
   One lookup, used by the CLI, forge (which runs march) and the editor's
   background `march --check`: MARCH_Z3 (an explicit override), then the z3
   shipped next to the running march (<real exe dir>/../libexec/z3), then
   PATH.  The exe is resolved through symlinks, so forge's ~/.march/current
   link finds the real install.  A set MARCH_Z3 that does not exist is an
   error, never a silent fall-through: someone pointed it somewhere on purpose.
   An empty MARCH_Z3 counts as unset. *)
type source = Env | Bundled | Path

let bundled_path () : string =
  let exe = try Unix.realpath Sys.executable_name with _ -> Sys.executable_name in
  Filename.concat (Filename.dirname (Filename.dirname exe)) (Filename.concat "libexec" "z3")

let is_executable p =
  try Unix.access p [ Unix.X_OK ]; not (Sys.is_directory p) with _ -> false

let find_z3 () : (string * source, string) Stdlib.result =
  match Sys.getenv_opt "MARCH_Z3" with
  | Some p when p <> "" ->
      if Sys.file_exists p then Ok (p, Env) else Error (Printf.sprintf "MARCH_Z3 is set to %s, which does not exist" p)
  | _ -> (
      let b = bundled_path () in
      if is_executable b then Ok (b, Bundled)
      else
        let on_path =
          match Sys.getenv_opt "PATH" with
          | None -> None
          | Some path ->
              String.split_on_char ':' path
              |> List.find_map (fun dir ->
                     let p = Filename.concat (if dir = "" then "." else dir) "z3" in
                     if is_executable p then Some p else None)
        in
        match on_path with Some p -> Ok (p, Path) | None -> Error "not found")

(* ── Version probe ─────────────────────────────────────────────────────────
   `z3 --version` prints `Z3 version 4.16.0 - 64 bit`.  The answer is memoised
   in process per (path, size, mtime) and on disk under
   $XDG_CACHE_HOME (or ~/.cache)/march/z3-probe/, keyed by a hash of the path,
   size, mtime and inode, so a warm machine never execs z3 just to learn its
   version.  Only successful probes are written to disk. *)
let parse_version (out : string) : string option =
  let words = String.split_on_char ' ' (String.trim out) in
  let rec go = function
    | "Z3" :: "version" :: v :: _ ->
        let ok = v <> "" && String.for_all (fun c -> (c >= '0' && c <= '9') || c = '.') v in
        if ok then Some v else None
    | _ :: rest -> go rest
    | [] -> None
  in
  go words

let probe_memo : (string, (string, string) Stdlib.result) Hashtbl.t = Hashtbl.create 4

let clear_probe_memo () = Hashtbl.reset probe_memo

let probe_cache_dir () : string option =
  let base =
    match Sys.getenv_opt "XDG_CACHE_HOME" with
    | Some d when d <> "" -> Some d
    | _ -> Option.map (fun h -> Filename.concat h ".cache") (Sys.getenv_opt "HOME")
  in
  Option.map (fun b -> Filename.concat (Filename.concat b "march") "z3-probe") base

let rec mkdir_p dir =
  if dir = "/" || dir = "." || dir = Filename.dirname dir || Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(* `<path> --version`, with no stdin (a z3 that read it would wait on ours)
   and under the hang backstop, so a wedged z3 cannot hang the compiler. *)
let exec_version (path : string) : (string, string) Stdlib.result =
  match
    let null = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
    let out_r, out_w = Unix.pipe ~cloexec:true () in
    let pid =
      Fun.protect
        ~finally:(fun () -> Unix.close null; Unix.close out_w)
        (fun () ->
          try Unix.create_process path [| path; "--version" |] null out_w Unix.stderr
          with e -> Unix.close out_r; raise e)
    in
    (pid, out_r)
  with
  | exception Unix.Unix_error (e, _, _) -> Error ("could not be started (" ^ Unix.error_message e ^ ")")
  | pid, out_r ->
      let deadline = Unix.gettimeofday () +. (float_of_int (backstop_ms ()) /. 1000.) in
      let buf = Buffer.create 128 and chunk = Bytes.create 4096 in
      let rec read () =
        let left = deadline -. Unix.gettimeofday () in
        if left <= 0. then false
        else
          match Unix.select [ out_r ] [] [] left with
          | [], _, _ -> false
          | _ -> (
              match Unix.read out_r chunk 0 (Bytes.length chunk) with
              | 0 -> true
              | n -> Buffer.add_subbytes buf chunk 0 n; read ()
              | exception Unix.Unix_error (Unix.EINTR, _, _) -> read ())
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> read ()
      in
      let finished = read () in
      Unix.close out_r;
      if not finished then (try Unix.kill pid Sys.sigkill with _ -> ());
      let rec wait () =
        try snd (Unix.waitpid [] pid) with Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
      in
      let status = wait () in
      if not finished then Error "did not answer `--version`"
      else
        match status with
        | Unix.WEXITED 0 -> (
            match parse_version (Buffer.contents buf) with
            | Some v -> Ok v
            | None -> Error "printed an unrecognised version (`z3 --version` did not say `Z3 version X.Y.Z`)")
        | Unix.WEXITED n -> Error (Printf.sprintf "exited with status %d on `--version`" n)
        | Unix.WSIGNALED n | Unix.WSTOPPED n -> Error (Printf.sprintf "was killed by signal %d on `--version`" n)

let probe_disk_file path (st : Unix.stats) : string option =
  Option.map
    (fun d ->
      Filename.concat d
        (March_cas.Blake3.hash_string
           (Printf.sprintf "%s\x00%d\x00%.6f\x00%d" path st.Unix.st_size st.Unix.st_mtime st.Unix.st_ino)))
    (probe_cache_dir ())

let read_probe_file (f : string) : string option =
  if Sys.file_exists f then
    try
      let v = String.trim (In_channel.with_open_bin f In_channel.input_all) in
      if v <> "" then Some v else None
    with _ -> None
  else None

(* The version a previous probe recorded for [path], without running z3. *)
let cached_version (path : string) : string option =
  match Unix.stat path with
  | exception Unix.Unix_error _ -> None
  | st -> Option.bind (probe_disk_file path st) read_probe_file

let probe_version (path : string) : (string, string) Stdlib.result =
  match Unix.stat path with
  | exception Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)
  | st -> (
      let memo_key = Printf.sprintf "%s\x00%d\x00%.6f" path st.Unix.st_size st.Unix.st_mtime in
      match Hashtbl.find_opt probe_memo memo_key with
      | Some r -> r
      | None ->
          let disk = probe_disk_file path st in
          let cached = Option.map (fun v -> Ok v) (Option.bind disk read_probe_file) in
          let r =
            match cached with
            | Some r -> r
            | None ->
                let r = exec_version path in
                (match (r, disk) with
                 | Ok v, Some f -> (
                     try
                       mkdir_p (Filename.dirname f);
                       let tmp = f ^ Printf.sprintf ".%d.tmp" (Unix.getpid ()) in
                       Out_channel.with_open_bin tmp (fun oc -> output_string oc v);
                       Sys.rename tmp f
                     with _ -> ())
                 | _ -> ());
                r
          in
          Hashtbl.replace probe_memo memo_key r;
          r)

(* ── Health ─────────────────────────────────────────────────────────────────
   What a run reports about its z3: the pinned version (Healthy), another
   version (Mismatch: used, with a warning), none found (Missing), or one that
   is there but unusable (Broken: MARCH_Z3 points nowhere, or `--version`
   failed or did not parse). *)
type health =
  | Healthy of { path : string; version : string; source : source }
  | Mismatch of { path : string; version : string; source : source }
  | Missing of string
  | Broken of { path : string; reason : string }

let health () : health =
  match find_z3 () with
  | Error "not found" -> Missing (bundled_path ())
  | Error _ -> (
      match Sys.getenv_opt "MARCH_Z3" with
      | Some p -> Broken { path = p; reason = "does not exist (MARCH_Z3 points to it)" }
      | None -> Missing (bundled_path ()))
  | Ok (path, source) -> (
      match probe_version path with
      | Ok version when version = Z3_pin.version -> Healthy { path; version; source }
      | Ok version -> Mismatch { path; version; source }
      | Error reason -> Broken { path; reason })

(* ── Identity: what a cached verdict depends on ─────────────────────────────
   A verdict is a function of the query text, the z3 version, the limits and
   (to be safe across machines sharing a cache) the platform.  Never the z3
   path: the determinism oracle runs from two HOMEs and cwds, and the same z3
   at two paths must share verdicts. *)
let platform : string Lazy.t =
  lazy
    (let raw =
       try
         let ic = Unix.open_process_args_in "uname" [| "uname"; "-sm" |] in
         let s = try input_line ic with End_of_file -> "" in
         ignore (Unix.close_process_in ic);
         s
       with _ -> ""
     in
     match String.split_on_char ' ' (String.trim raw) with
     | [ os; arch ] -> String.lowercase_ascii os ^ "-" ^ arch
     | _ -> String.lowercase_ascii Sys.os_type)

let limits_tag () = Printf.sprintf "rl-%d-%d" !default_rlimit !stage2_rlimit

let identity () : string option =
  match health () with
  | Healthy { version; _ } | Mismatch { version; _ } ->
      Some (Printf.sprintf "z3-%s/%s/%s" version (limits_tag ()) (Lazy.force platform))
  | Missing _ | Broken _ -> None

(* The build (CAS) cache's z3 fragment.  It never runs z3: a compile with no
   refinement obligations must not start one.  The version comes from a
   probe already cached on disk, else "unprobed"; a new z3 binary has a new
   mtime and so no cached probe, so a build made with another z3 is never
   replayed. *)
let cas_tag () : string list =
  match find_z3 () with
  | Error _ -> [ "noz3" ]
  | Ok (path, _) ->
      let v = Option.value ~default:"unprobed" (cached_version path) in
      [ Printf.sprintf "z3:%s/%s/%s" v (limits_tag ()) (Lazy.force platform) ]

(* The options every query starts with, sent after its (reset). *)
let init_options : string =
  (* print-success off: we only read explicit (check-sat)/(get-model) output *)
  "(set-option :print-success false)\n"
  (* Declarations are global anyway between resets; scoping them keeps a
     stray push (none is sent today) from leaking them. *)
  ^ "(set-option :global-decls false)\n"

let create () : t option =
  match find_z3 () with
  | Error _ -> None
  | Ok (path, _) ->
      (* A write to a dead z3's stdin must surface as a catchable EPIPE error
         (so Refine can restart the solver), not SIGPIPE process death.  Only
         claim the signal if the host application hasn't installed a handler. *)
      (try
         match Sys.signal Sys.sigpipe Sys.Signal_ignore with
         | Sys.Signal_default -> ()
         | prev -> Sys.set_signal Sys.sigpipe prev
       with Invalid_argument _ -> ());
      (* cloexec on all four ends: without it the z3 child inherits the write
         end of its OWN stdin pipe, so after an unclean parent exit it never
         sees EOF and blocks on read(0) forever — an immortal orphan.  With
         cloexec, parent death closes the last write end and z3 exits on EOF.
         (create_process dup2s the child ends onto fd 0/1, which clears
         close-on-exec on those copies.) *)
      let stdin_r, stdin_w = Unix.pipe ~cloexec:true () in
      let stdout_r, stdout_w = Unix.pipe ~cloexec:true () in
      let pid =
        try
          Unix.create_process path [| path; "-in" |] stdin_r stdout_w
            Unix.stderr
        with e ->
          List.iter
            (fun fd -> try Unix.close fd with _ -> ())
            [ stdin_r; stdin_w; stdout_r; stdout_w ];
          raise e
      in
      Unix.close stdin_r;
      Unix.close stdout_w;
      let oc = Unix.out_channel_of_descr stdin_w in
      let ic = { fd = stdout_r; buf = Bytes.create 65536; pos = 0; len = 0 } in
      Some { ic; oc; pid }

(* One line of z3's output, waiting at most until [deadline] (absolute
   Unix time) for more bytes.  Raises [Hung] past the deadline and
   End_of_file when z3 has closed its stdout. *)
let deadline = ref infinity

let rec input_line (r : reader) : string =
  match Bytes.index_from_opt r.buf r.pos '\n' with
  | Some i when i < r.pos + r.len ->
      let line = Bytes.sub_string r.buf r.pos (i - r.pos) in
      r.len <- r.len - (i + 1 - r.pos);
      r.pos <- i + 1;
      line
  | _ ->
      if r.pos > 0 then begin
        Bytes.blit r.buf r.pos r.buf 0 r.len;
        r.pos <- 0
      end;
      if r.len = Bytes.length r.buf then failwith "refine: z3 line too long";
      let rec wait () =
        let left = !deadline -. Unix.gettimeofday () in
        if left <= 0. then raise Hung;
        match Unix.select [ r.fd ] [] [] left with
        | [], _, _ -> raise Hung
        | _ -> ()
        | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
      in
      wait ();
      let n =
        let rec rd () =
          try Unix.read r.fd r.buf r.len (Bytes.length r.buf - r.len)
          with Unix.Unix_error (Unix.EINTR, _, _) -> rd ()
        in
        rd ()
      in
      if n = 0 then raise End_of_file;
      r.len <- r.len + n;
      input_line r

(* Read one balanced-parens s-expression block (the (get-model) reply). *)
let read_balanced (ic : reader) : string =
  let buf = Buffer.create 256 in
  let depth = ref 0 in
  let started = ref false in
  let continue = ref true in
  while !continue do
    let line = input_line ic in
    Buffer.add_string buf line;
    Buffer.add_char buf '\n';
    String.iter
      (fun c ->
        if c = '(' then (
          incr depth;
          started := true)
        else if c = ')' then decr depth)
      line;
    if !started && !depth <= 0 then continue := false
  done;
  Buffer.contents buf

(* Read the (check-sat) verdict, skipping any `(error …)` lines z3 emits for a
   malformed command, and reporting whether one was seen.

   z3 -in does NOT stop at an error: it skips the offending command and still
   answers the (check-sat).  Before this, that error line was read AS the
   verdict, [check] raised Failure, and Refine's supervisor killed the solver,
   respawned it, hit the same error, and then marked z3 unavailable for the
   WHOLE REST OF THE RUN — so a single malformed VC silently disabled
   refinement checking for every later call site, with no diagnostic.

   Skipping the error line instead keeps the shared channel synchronized, so
   one bad VC costs only itself.  The verdict that follows an error is computed
   against an incomplete assertion state and is therefore NOT trusted: [check]
   maps it to [Unknown].  That direction matters — under the definite-failure
   stance a spurious `sat` would be reported as a refinement violation, i.e. a
   false positive on correct code.

   An `(error …)` is a whole s-expression and its quoted message is often
   MULTI-LINE — a sort mismatch prints the offending term and then a second
   line naming the declaration it violates.  Skipping only the first line would
   leave the continuation in the pipe to be consumed as the NEXT query's
   verdict, shifting every later answer by one: precisely the desynchronisation
   this is meant to prevent, and one that manifests as false positives (a
   later, unrelated, CORRECT call inherits some other VC's `unsat`).  So the
   error is consumed to its closing paren, counting parens only OUTSIDE the
   quoted message. *)

(* Advance an s-expression scan across one line: returns the paren depth and
   whether the line ended inside a quoted string.  Parens inside a string
   literal are message text, not structure, so they are not counted.  (SMT-LIB
   escapes an embedded quote as `""`, which this reads as close-then-reopen —
   the same end state, so the escape needs no special case.) *)
let scan_sexp ~(depth : int) ~(in_string : bool) (line : string) : int * bool =
  let d = ref depth and q = ref in_string in
  String.iter
    (fun c ->
      if !q then (if c = '"' then q := false)
      else
        match c with
        | '"' -> q := true
        | '(' -> incr d
        | ')' -> decr d
        | _ -> ())
    line;
  (!d, !q)

(* ── Malformed-query accounting ───────────────────────────────────────────
   A query z3 rejects is reported to callers as [Rejected], which every caller
   treats as "not proved" — so a sort the checker got wrong looks exactly like
   an ordinary skip.  That is the right runtime behaviour and the wrong test
   behaviour: it is how an ill-sorted leaf survives a green suite.  Every
   rejection is therefore counted here, with z3's message, and when
   [MARCH_REFINE_Z3_ERRORS] names a file the full query is appended to it.
   The refinement test suite asserts the count stays at zero
   (specs/2026-09-14-set-refinements-strengthening-design.md §2.5). *)
let malformed_count = ref 0
let malformed_messages : string list ref = ref []

let record_malformed ~(query : string) (messages : string list) : unit =
  incr malformed_count;
  let msg = String.concat " " messages in
  if List.length !malformed_messages < 50 then malformed_messages := msg :: !malformed_messages;
  match Sys.getenv_opt "MARCH_REFINE_Z3_ERRORS" with
  | Some path when path <> "" ->
    (try
       let oc = open_out_gen [ Open_append; Open_creat; Open_wronly ] 0o644 path in
       Printf.fprintf oc ";; ---- z3 rejected this query: %s\n%s\n" msg query;
       close_out oc
     with Sys_error _ -> ())
  | _ -> ()

let rec read_verdict ?(errors = ref []) (ic : reader) ~(saw_error : bool) : string * bool =
  let line = String.trim (input_line ic) in
  if line = "" then read_verdict ~errors ic ~saw_error
  else if String.starts_with ~prefix:"(error" line then begin
    (* Consume the rest of this error s-expression, however many lines it takes. *)
    let d = ref 0 and q = ref false in
    let d0, q0 = scan_sexp ~depth:0 ~in_string:false line in
    d := d0;
    q := q0;
    errors := line :: !errors;
    while !d > 0 do
      let next = input_line ic in
      let d1, q1 = scan_sexp ~depth:!d ~in_string:!q next in
      d := d1;
      q := q1
    done;
    read_verdict ~errors ic ~saw_error:true
  end
  else (line, saw_error)

(* Reflection stage 2 (specs/2026-10-29-refinement-reflection-design.md
   §4.4): a query whose unfoldings are guarded by assumption literals is
   checked with `check-sat-assuming` under its own (smaller) rlimit, and on
   `unsat` the literals in z3's unsat core are read back ([last_core]).  Unsat
   cores are enabled per query, after its (reset), only for such queries. *)
let last_core : string list ref = ref []

let parse_core (s : string) : string list =
  let s = String.trim s in
  let s = if String.length s >= 2 && s.[0] = '(' then String.sub s 1 (String.length s - 2) else s in
  String.split_on_char ' ' s
  |> List.concat_map (String.split_on_char '\n')
  |> List.map (fun w ->
         let w = String.trim w in
         if String.length w >= 2 && w.[0] = '|' then String.sub w 1 (String.length w - 2) else w)
  |> List.filter (( <> ) "")

(* [MARCH_REFINE_RLIMIT_LOG=<file>]: after each query, ask z3 how much of
   the rlimit it used and append `<count>\t<stage>\t<verdict>` to the file;
   the count is also left in [last_rlimit_count].  It is how the default
   limits were measured (scripts/z3-rlimit-measure.sh).  Off by default: it
   costs a round trip per query. *)
let last_rlimit_count : int ref = ref 0

let parse_rlimit_info (s : string) : int option =
  (* `(:rlimit 12345)` *)
  String.split_on_char ' ' (String.trim s)
  |> List.find_map (fun w ->
         let w = String.trim w in
         let w = if String.ends_with ~suffix:")" w then String.sub w 0 (String.length w - 1) else w in
         int_of_string_opt w)

let append_file (path : string) (text : string) : unit =
  try
    let oc = open_out_gen [ Open_append; Open_creat; Open_wronly ] 0o644 path in
    output_string oc text;
    close_out oc
  with Sys_error _ -> ()

let env_file (name : string) : string option =
  match Sys.getenv_opt name with Some p when p <> "" -> Some p | _ -> None

let string_of_verdict = function
  | Unsat -> "unsat" | Sat _ -> "sat" | Unknown -> "unknown" | Rejected -> "rejected"

let check ?(preamble = "") ?(assume : string list = []) ?rlimit (t : t) (vc : Smt.vc) : result =
  let rlimit =
    match rlimit with Some n -> n | None -> if assume = [] then !default_rlimit else !stage2_rlimit
  in
  last_core := [];
  let b = Buffer.create 1024 in
  Buffer.add_string b "(reset)\n";
  Buffer.add_string b init_options;
  if assume <> [] then Buffer.add_string b "(set-option :produce-unsat-cores true)\n";
  Buffer.add_string b (Printf.sprintf "(set-option :rlimit %d)\n" rlimit);
  (* Measure-axiom preamble (datatype + uninterpreted-fn declarations + axioms). *)
  if preamble <> "" then (Buffer.add_string b preamble; Buffer.add_char b '\n');
  Buffer.add_string b (Smt.assertion_block vc);
  if assume = [] then Buffer.add_string b "(check-sat)\n"
  else Buffer.add_string b (Printf.sprintf "(check-sat-assuming (%s))\n" (String.concat " " assume));
  let sent = Buffer.contents b in
  output_string t.oc sent;
  flush t.oc;
  (* [MARCH_REFINE_Z3_LOG=<file>]: append every query, exactly as sent, with
     the verdict z3 gave it.  A debugging aid for comparing solver versions:
     piping z3's stdout through `tee` stalls this driver's line-by-line
     protocol, so the log is written from inside instead. *)
  Option.iter (fun p -> append_file p (";; ==== sent\n" ^ sent)) (env_file "MARCH_REFINE_Z3_LOG");
  deadline := Unix.gettimeofday () +. (float_of_int (backstop_ms ()) /. 1000.);
  let ask cmd =
    output_string t.oc cmd;
    flush t.oc;
    read_balanced t.ic
  in
  let errors = ref [] in
  let verdict, saw_error = read_verdict ~errors t.ic ~saw_error:false in
  if saw_error then
    record_malformed ~query:(preamble ^ "\n" ^ Smt.assertion_block vc) (List.rev !errors);
  let rlimit_log = env_file "MARCH_REFINE_RLIMIT_LOG" in
  if rlimit_log <> None && not saw_error then
    last_rlimit_count := Option.value ~default:0 (parse_rlimit_info (ask "(get-info :rlimit)\n"));
  let result =
    if saw_error then
      (* Malformed VC: the verdict is untrustworthy (see [read_verdict]).  We
         deliberately do NOT request a model even on `sat`, so nothing extra is
         left unread and the next VC starts aligned. *)
      Rejected
    else
      match verdict with
      | "unsat" when assume <> [] ->
          last_core := parse_core (ask "(get-unsat-core)\n");
          Unsat
      | "unsat" -> Unsat
      | "unknown" -> Unknown
      | "sat" -> Sat (Model.of_string (ask "(get-model)\n"))
      (* Not an error line and not a verdict => the child is wedged or dead.
         Raising here is correct: Refine reaps and respawns it. *)
      | other -> failwith ("refine: unexpected z3 verdict: " ^ other)
  in
  Option.iter
    (fun p ->
      append_file p
        (Printf.sprintf "%d\t%s\t%s\n" !last_rlimit_count
           (if assume = [] then "main" else "stage2") (string_of_verdict result)))
    rlimit_log;
  Option.iter
    (fun p -> append_file p (Printf.sprintf ";; ==== verdict: %s\n" (string_of_verdict result)))
    (env_file "MARCH_REFINE_Z3_LOG");
  result

(* Terminate and REAP the child.  Graceful (exit)+EOF first, then SIGKILL so
   the following waitpid can never block on a wedged solver; the unreaped
   child holds its pid, so the kill cannot race a pid reuse. *)
let close (t : t) : unit =
  (try
     output_string t.oc "(exit)\n";
     flush t.oc
   with _ -> ());
  (try close_out t.oc with _ -> ());
  (try Unix.close t.ic.fd with _ -> ());
  (try Unix.kill t.pid Sys.sigkill with _ -> ());
  (try ignore (Unix.waitpid [] t.pid) with _ -> ())
