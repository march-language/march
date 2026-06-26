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
      let stdin_r, stdin_w = Unix.pipe () in
      let stdout_r, stdout_w = Unix.pipe () in
      let pid =
        Unix.create_process path [| path; "-in" |] stdin_r stdout_w Unix.stderr
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

let check ?(preamble = "") (t : t) (vc : Smt.vc) : result =
  output_string t.oc "(push 1)\n";
  (* Measure-axiom preamble (datatype + uninterpreted-fn declarations + axioms);
     scoped inside the push so it never leaks across VCs. *)
  if preamble <> "" then (output_string t.oc preamble; output_string t.oc "\n");
  output_string t.oc (Smt.assertion_block vc);
  output_string t.oc "(check-sat)\n";
  flush t.oc;
  let verdict = String.trim (input_line t.ic) in
  let result =
    match verdict with
    | "unsat" -> Unsat
    | "unknown" -> Unknown
    | "sat" ->
        output_string t.oc "(get-model)\n";
        flush t.oc;
        Sat (Model.of_string (read_balanced t.ic))
    | other -> failwith ("refine: unexpected z3 verdict: " ^ other)
  in
  output_string t.oc "(pop 1)\n";
  flush t.oc;
  result

let close (t : t) : unit =
  (try
     output_string t.oc "(exit)\n";
     flush t.oc
   with _ -> ());
  (try close_out t.oc with _ -> ());
  (try close_in t.ic with _ -> ());
  (try ignore (Unix.waitpid [] t.pid) with _ -> ())
