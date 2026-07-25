(* Long-lived `z3 -in` subprocess driver.  One process per compilation unit;
   each VC is checked inside a (push)/(pop) pair so assumptions don't leak. *)

type t = { ic : in_channel; oc : out_channel; pid : int }

type result =
  | Unsat                          (* goal holds — verified *)
  | Sat of (string * string) list  (* goal can fail — counterexample model *)
  | Unknown                        (* solver could not decide *)

(* Locate z3: MARCH_Z3 override, else first "z3" on PATH.  None => unavailable. *)
let find_z3 () : string option =
  match Sys.getenv_opt "MARCH_Z3" with
  | Some p -> if Sys.file_exists p then Some p else None
  | None -> (
      match Sys.getenv_opt "PATH" with
      | None -> None
      | Some path ->
          String.split_on_char ':' path
          |> List.find_map (fun dir ->
                 let p = Filename.concat dir "z3" in
                 if Sys.file_exists p then Some p else None))

let create () : t option =
  match find_z3 () with
  | None -> None
  | Some path ->
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
      let ic = Unix.in_channel_of_descr stdout_r in
      (* print-success off: we only read explicit (check-sat)/(get-model) output *)
      output_string oc "(set-option :print-success false)\n";
      (* Scope declarations (declare-sort, declare-datatypes, declare-fun) inside
         push/pop so they are undone by pop. Without this, Z3 keeps declarations
         globally even after pop, causing "sort already declared" errors when the
         same preamble is sent again in a subsequent query (e.g. across test
         modules in the same process). *)
      output_string oc "(set-option :global-decls false)\n";
      (* Per-query wall-clock cap: a hard (e.g. quantified-datatype) query returns
         `unknown` instead of looping — definite-failure then treats it as skip. *)
      output_string oc "(set-option :timeout 3000)\n";
      flush oc;
      Some { ic; oc; pid }

(* Read one balanced-parens s-expression block (the (get-model) reply). *)
let read_balanced (ic : in_channel) : string =
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

let rec read_verdict (ic : in_channel) ~(saw_error : bool) : string * bool =
  let line = String.trim (input_line ic) in
  if line = "" then read_verdict ic ~saw_error
  else if String.starts_with ~prefix:"(error" line then begin
    (* Consume the rest of this error s-expression, however many lines it takes. *)
    let d = ref 0 and q = ref false in
    let d0, q0 = scan_sexp ~depth:0 ~in_string:false line in
    d := d0;
    q := q0;
    while !d > 0 do
      let d1, q1 = scan_sexp ~depth:!d ~in_string:!q (input_line ic) in
      d := d1;
      q := q1
    done;
    read_verdict ic ~saw_error:true
  end
  else (line, saw_error)

let check ?(preamble = "") (t : t) (vc : Smt.vc) : result =
  output_string t.oc "(push 1)\n";
  (* Measure-axiom preamble (datatype + uninterpreted-fn declarations + axioms);
     scoped inside the push so it never leaks across VCs. *)
  if preamble <> "" then (output_string t.oc preamble; output_string t.oc "\n");
  output_string t.oc (Smt.assertion_block vc);
  output_string t.oc "(check-sat)\n";
  flush t.oc;
  let verdict, saw_error = read_verdict t.ic ~saw_error:false in
  let result =
    if saw_error then
      (* Malformed VC: the verdict is untrustworthy (see [read_verdict]).  We
         deliberately do NOT request a model even on `sat`, so nothing extra is
         left unread and the next VC starts aligned. *)
      Unknown
    else
      match verdict with
      | "unsat" -> Unsat
      | "unknown" -> Unknown
      | "sat" ->
          output_string t.oc "(get-model)\n";
          flush t.oc;
          Sat (Model.of_string (read_balanced t.ic))
      (* Not an error line and not a verdict => the child is wedged or dead.
         Raising here is correct: Refine reaps and respawns it. *)
      | other -> failwith ("refine: unexpected z3 verdict: " ^ other)
  in
  output_string t.oc "(pop 1)\n";
  flush t.oc;
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
  (try close_in t.ic with _ -> ());
  (try Unix.kill t.pid Sys.sigkill with _ -> ());
  (try ignore (Unix.waitpid [] t.pid) with _ -> ())
