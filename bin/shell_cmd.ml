(* `march shell`: a remote shell on a running node (R6 of
   specs/plans/2026-09-28-observe-recon-shell-plan.md; design §6.9).

   The driver typechecks the program once (exactly as it compiles it), then
   hands it here.  Each input is compiled into a self-contained fragment
   (Repl_jit.shell_compile), signed with the deploy key, and sent to the
   node's shell listener (runtime/march_shell.c) as one EVAL; the node runs
   it and answers with the rendered result and whatever it printed.  The
   fragment renders its own result, with a renderer generated from the
   input's static type (bin/shell_render_gen.ml, stdlib ShellRender).

   Input forms:
     <expr> [limit: N | limit: all]   evaluate and print
     let <name> = <expr>              evaluate on the node, keep the value
     :limit N   :caps   :t <expr>   :help   :quit

   Pre-bound capabilities (they exist only as names the input may use; the
   node checks the ones an input uses against $MARCH_SHELL_POLICY):
     console  Cap(IO.Console)     clock  Cap(IO.Clock)
     intro    Cap(Actor.Introspect)
     debug    Cap(Actor.Debug)

   A deploy ends the session (the node answers `epoch_changed`). *)

module Ast = March_ast.Ast
module TC = March_typecheck.Typecheck

let default_limit = 50

(* name, cap path, how the fragment obtains it *)
let caps = [
  ("console", "IO.Console", "cap_narrow(root_cap)", "Cap(IO.Console)");
  ("clock", "IO.Clock", "cap_narrow(root_cap)", "Cap(IO.Clock)");
  ("intro", "Actor.Introspect", "Actor.introspect(root_cap)", "Cap(Actor.Introspect)");
  ("debug", "Actor.Debug", "Actor.debug(root_cap)", "Cap(Actor.Debug)");
]

(* ── small helpers ── *)

let b64_alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let b64_encode (s : string) : string =
  let n = String.length s in
  let b = Buffer.create (4 * ((n + 2) / 3)) in
  let i = ref 0 in
  while !i < n do
    let c k = if !i + k < n then Char.code s.[!i + k] else 0 in
    let v = (c 0 lsl 16) lor (c 1 lsl 8) lor c 2 in
    Buffer.add_char b b64_alpha.[(v lsr 18) land 63];
    Buffer.add_char b b64_alpha.[(v lsr 12) land 63];
    Buffer.add_char b (if !i + 1 < n then b64_alpha.[(v lsr 6) land 63] else '=');
    Buffer.add_char b (if !i + 2 < n then b64_alpha.[v land 63] else '=');
    i := !i + 3
  done;
  Buffer.contents b

let b64_decode (s : string) : string =
  let b = Buffer.create (String.length s) in
  let acc = ref 0 and bits = ref 0 in
  String.iter (fun c ->
      match String.index_opt b64_alpha c with
      | Some x ->
        acc := (!acc lsl 6) lor x;
        bits := !bits + 6;
        if !bits >= 8 then begin
          bits := !bits - 8;
          Buffer.add_char b (Char.chr ((!acc lsr !bits) land 0xff))
        end
      | None -> ()) s;
  Buffer.contents b

let starts_with s p = String.length s >= String.length p && String.sub s 0 (String.length p) = p

let words s = String.split_on_char ' ' s

let field r key =
  List.find_map (fun w ->
      if starts_with w (key ^ ":") then
        Some (String.sub w (String.length key + 1) (String.length w - String.length key - 1))
      else None) (words r)

let read_file f = In_channel.with_open_bin f In_channel.input_all

(* A printed type with its variables renamed a, b, ... in order of first
   appearance, so `Pid(h)` from one session reads `Pid(a)` in every one.
   Type names are capitalised; a lowercase word is a variable unless a ` :`
   follows it (a record field). *)
let normalize_type_vars (t : string) : string =
  let n = String.length t in
  let b = Buffer.create n and names = Hashtbl.create 4 in
  let is_id c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c = '\'' in
  let i = ref 0 in
  while !i < n do
    let c = t.[!i] in
    if (c >= 'a' && c <= 'z') && (!i = 0 || not (is_id t.[!i - 1])) then begin
      let j = ref !i in
      while !j < n && is_id t.[!j] do incr j done;
      let w = String.sub t !i (!j - !i) in
      let field = !j + 1 < n && t.[!j] = ' ' && t.[!j + 1] = ':' in
      if field then Buffer.add_string b w
      else begin
        let v = match Hashtbl.find_opt names w with
          | Some v -> v
          | None ->
            let k = Hashtbl.length names in
            let v = if k < 26 then String.make 1 (Char.chr (97 + k)) else Printf.sprintf "t%d" k in
            Hashtbl.replace names w v; v in
        Buffer.add_string b v
      end;
      i := !j
    end else begin Buffer.add_char b c; incr i end
  done;
  Buffer.contents b

(* Identifier-boundary occurrence of [name] in [src]. *)
let mentions src name =
  let is_id c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' in
  let n = String.length src and m = String.length name in
  let rec go i =
    i + m <= n
    && ((String.sub src i m = name
         && (i = 0 || not (is_id src.[i - 1]))
         && (i + m = n || not (is_id src.[i + m])))
        || go (i + 1))
  in
  go 0

(* ── the connection ── *)

type conn = { fd : Unix.file_descr; inbuf : Buffer.t }

let connect path =
  let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.connect fd (Unix.ADDR_UNIX path);
  { fd; inbuf = Buffer.create 4096 }

let send c line =
  let s = line ^ "\n" in
  let rec go off =
    if off < String.length s then
      go (off + Unix.write_substring c.fd s off (String.length s - off)) in
  go 0

let recv c =
  let chunk = Bytes.create 65536 in
  let rec go () =
    let s = Buffer.contents c.inbuf in
    match String.index_opt s '\n' with
    | Some i ->
      Buffer.clear c.inbuf;
      Buffer.add_string c.inbuf (String.sub s (i + 1) (String.length s - i - 1));
      String.sub s 0 i
    | None ->
      (match Unix.read c.fd chunk 0 (Bytes.length chunk) with
       | 0 -> if s = "" then "BYE connection_closed" else s
       | n -> Buffer.add_subbytes c.inbuf chunk 0 n; go ())
  in
  go ()

(* ── a session ── *)

type session = {
  conn : conn;
  epoch : int;
  (* The node's HELLO challenge, signed into every EVAL, so a captured line
     runs on no other connection, node or restart. *)
  challenge : string;
  sk : bytes;
  jit : March_jit.Repl_jit.t;
  mutable tc_env : TC.env;
  program_name : string;
  program_decls : Ast.decl list;
  program_type_map : (Ast.span, TC.ty) Hashtbl.t;
  shows : (string, bool) Hashtbl.t;  (* Show impls, for the renderer (Shell_render_gen) *)
  mutable limit : int;          (* 0 = no limit *)
  timeout_ms : int;
  mutable n : int;
  mutable bound : string list;  (* `let` names, newest first *)
  mutable failed : bool;        (* some input failed (exit 1 with --shell-inputs) *)
  triple : string option;       (* the node's target, from HELLO *)
  (* The node's build identity and ours (lib/jit/shell_ident.ml); [None]
     against a node built before it, which is not checked. *)
  ident : March_jit.Shell_ident.check option;
}

exception Session_over of string

(* The current input failed (refused, panicked, timed out, did not compile). *)
let last_failed = ref false

let nonce_n = ref 0
let fresh_nonce () =
  incr nonce_n;
  Printf.sprintf "%016x%08x%08x" (int_of_float (Unix.gettimeofday () *. 1e6)) (Unix.getpid ()) !nonce_n

(* MARCH_SHELL_TIMING=1: per input, on stderr, the time spent compiling
   (every fragment the input built, renderer attempts included) and waiting
   on the node (signing, the EVAL round trip: upload, load, run, reply), in
   ms.  The R6 latency gate reads these. *)
let timing = Sys.getenv_opt "MARCH_SHELL_TIMING" <> None
let t_compile = ref 0.0
let t_node = ref 0.0
let timed (acc : float ref) (f : unit -> 'a) : 'a =
  if not timing then f ()
  else begin
    let t0 = Unix.gettimeofday () in
    Fun.protect ~finally:(fun () -> acc := !acc +. (Unix.gettimeofday () -. t0) *. 1000.) f
  end

(* The signed `caps:` is what the fragment's code uses ([sf_caps]), which the
   node checks against the fragment's own manifest and then its policy. *)
let eval_on_node s ~(kind : string) ~(src : string)
    (frag : March_jit.Repl_jit.shell_fragment) : string =
  timed t_node @@ fun () ->
  let so = read_file frag.March_jit.Repl_jit.sf_so in
  let now = int_of_float (Unix.gettimeofday () *. 1000.) in
  let body =
    Printf.sprintf "name:%s kind:%s epoch:%d session:%s nonce:%s not_after_ms:%d timeout_ms:%d caps:%s src_b64:%s so_b64:%s"
      frag.sf_entry kind s.epoch s.challenge (fresh_nonce ()) (now + 30_000) s.timeout_ms
      (match frag.sf_caps with [] -> "-" | l -> String.concat "," l)
      (b64_encode src) (b64_encode so) in
  let signature =
    March_ed25519.Ed25519.(sig_to_base64 (sign_str ("EVAL " ^ body) s.sk)) in
  send s.conn ("EVAL " ^ signature ^ " " ^ body);
  recv s.conn

(* Generated source for one fragment.  [body] is the block after the caps. *)
let fragment_source ?(fns = "") s ~src ~body =
  let used = List.filter (fun (name, _, _, _) -> mentions src name) caps in
  let needs =
    String.concat "" (List.map (fun (_, path, _, _) -> Printf.sprintf "  needs %s\n" path) caps) in
  let cap_lets =
    String.concat "" (List.map (fun (name, _, how, ty) ->
        Printf.sprintf "    let %s : %s = %s\n" name ty how) used) in
  let text =
    Printf.sprintf "mod Shell_%d do\n%s%s  fn %s() do\n%s%s\n  end\nend\n" s.n needs fns
      March_jit.Repl_jit.shell_entry_fn cap_lets body in
  text

let parse_module text =
  (* No file name: Repl_jit counts only diagnostics whose span file is "",
     the fragment's own (checked_type_map). *)
  match March_parser.Parse.module_ text with
  | Ok m -> Ok (March_desugar.Desugar.desugar_module m)
  | Error e -> Error e

let report_error e =
  last_failed := true;
  Printf.printf "error: %s\n%!"
    (match e with
     | March_jit.Repl_jit.Typecheck_failed m -> m
     | Failure m -> m
     | e -> Printexc.to_string e)

(* Compile [text] (a whole fragment module); typecheck errors are printed. *)
let compile s ?store_as text =
  match parse_module text with
  | Error e ->
    last_failed := true;
    List.iter (fun (d : March_errors.Errors.diagnostic) -> Printf.printf "error: %s\n%!" d.message) e; None
  | Ok m ->
    (try
       Some (m, timed t_compile @@ fun () ->
               March_jit.Repl_jit.shell_compile ?triple:s.triple ?ident:s.ident s.jit ~tc_env:s.tc_env
               ~program_name:s.program_name ~program_decls:s.program_decls ~program_type_map:s.program_type_map
               ?store_as m)
     with e -> report_error e; None)

(* Print a node reply; raise [Session_over] when the session ended. *)
let print_reply ~show_result r =
  let out = match field r "out" with Some o -> b64_decode o | None -> "" in
  if out <> "" then print_string out;
  last_failed := not (starts_with r "OK ");
  match words r with
  | "OK" :: v :: _ -> if show_result then print_endline (b64_decode v); true
  | "PANIC" :: m :: _ -> Printf.printf "** panic: %s\n%!" (b64_decode m); false
  | "TIMEOUT" :: "uncancellable" :: _ ->
    print_endline "** timeout: the input did not stop when cancelled; it is still running on the node"; false
  | "TIMEOUT" :: _ -> print_endline "** timeout"; false
  | "ERR" :: "epoch_changed" :: rest ->
    raise (Session_over ("the node was redeployed (epoch " ^ String.concat " -> " rest
                         ^ "); this session and its bindings are gone"))
  | "BYE" :: rest -> raise (Session_over ("the node ended the session: " ^ String.concat " " rest))
  | "ERR" :: rest -> Printf.printf "** refused: %s\n%!" (String.concat " " rest); false
  | _ -> Printf.printf "** unexpected reply: %s\n%!" r; false

(* The last expression of the fragment's entry function: the input. *)
let entry_last_expr (m : Ast.module_) =
  List.find_map (function
      | Ast.DFn (d, _) when d.Ast.fn_name.Ast.txt = March_jit.Repl_jit.shell_entry_fn ->
        (match d.Ast.fn_clauses with
         | c :: _ ->
           (match c.Ast.fc_body with
            | Ast.EBlock (es, _) -> (match List.rev es with e :: _ -> Some e | [] -> None)
            | e -> Some e)
         | [] -> None)
      | _ -> None) m.Ast.mod_decls

(* The type of a fragment's input, when the fragment typechecks (counting
   its own errors only, as Repl_jit.checked_type_map does).  Into a table of
   its own: the session's (the program's) is the one lowering reads, and
   this probe's spans are not the compiled fragment's. *)
let input_type s (m : Ast.module_) =
  let errors = March_errors.Errors.create () in
  let env = { s.tc_env with TC.errors; refs = ref []; current_decl = ref "";
                            type_map = Hashtbl.create 256 } in
  let (errs, tm) = TC.check_module_with_env env m in
  let own = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && d.span.Ast.file = "")
      (March_errors.Errors.sorted errs) in
  if own then None
  else Option.bind (entry_last_expr m) (fun e -> Hashtbl.find_opt tm (TC.span_of_expr e))

(* MARCH_SHELL_DEBUG=1 prints each generated renderer on stderr. *)
let debug = Sys.getenv_opt "MARCH_SHELL_DEBUG" <> None

(* An expression: typecheck it alone for its type, then compile it with the
   renderer generated from that type (bin/shell_render_gen.ml), so the
   fragment returns the rendered String.  Anything that goes wrong on the way
   (the input does not typecheck, reaches code that differs from the node's,
   or the generated renderer itself does not compile, which would be a
   renderer bug) falls back to the plain `to_string` fragment, whose compile
   reports the input's own errors as before. *)
let eval_expr s src ~limit =
  s.n <- s.n + 1;
  let run frag = ignore (print_reply ~show_result:true (eval_on_node s ~kind:"value" ~src frag)) in
  let run_plain () =
    match compile s (fragment_source s ~src ~body:(Printf.sprintf "    to_string(%s)" src)) with
    | Some (_, frag) -> run frag
    | None -> () in
  let ty = match parse_module (fragment_source s ~src ~body:(Printf.sprintf "    (%s)" src)) with
    | Ok m -> timed t_compile (fun () -> input_type s m)
    | Error _ -> None in
  match ty with
  | None -> run_plain ()
  | Some ty ->
    let fns, e = Shell_render_gen.generate ~env:s.tc_env ~shows:s.shows ~tag:s.n
        ~program_name:s.program_name ty "__r" in
    let text = fragment_source s ~fns ~src
        ~body:(Printf.sprintf "    let __r = (%s)\n    let __l = %d\n    %s" src limit e) in
    if debug then prerr_string text;
    let frag = match parse_module text with
      | Error _ -> None
      | Ok m ->
        (try Some (timed t_compile @@ fun () ->
                   March_jit.Repl_jit.shell_compile ?triple:s.triple ?ident:s.ident s.jit ~tc_env:s.tc_env
                     ~program_name:s.program_name ~program_decls:s.program_decls
                     ~program_type_map:s.program_type_map m)
         with e ->
           if debug then Printf.eprintf "[shell] the rendered fragment did not compile: %s\n%!"
               (match e with March_jit.Repl_jit.Typecheck_failed m | Failure m -> m
                           | e -> Printexc.to_string e);
           None) in
    match frag with
    | Some frag -> run frag
    | None -> run_plain ()

let eval_let s name src =
  s.n <- s.n + 1;
  let text = fragment_source s ~src ~body:(Printf.sprintf "    (%s)" src) in
  (* The slot is bound only once the value is on the node. *)
  let slot = March_jit.Repl_jit.shell_bind_slot s.jit ~name:("__pending_" ^ name)
      ~ty:March_tir.Tir.TUnit in
  match compile s ~store_as:slot text with
  | None -> ()
  | Some (m, frag) ->
    let r = eval_on_node s ~kind:"init" ~src:("let " ^ name ^ " = " ^ src) frag in
    if print_reply ~show_result:false r then begin
      (* Bind [name] for later inputs: its TIR type for the slot, its
         typechecker type for the environment (the type of the block's last
         expression, from a second typecheck of the same module). *)
      March_jit.Repl_jit.shell_name_slot s.jit ~name ~slot ~ty:frag.sf_ret;
      let ty =
        let errors = March_errors.Errors.create () in
        let env = { s.tc_env with TC.errors; refs = ref []; current_decl = ref "" } in
        let (_, tm) = TC.check_module_with_env env m in
        Option.bind (entry_last_expr m) (fun e -> Hashtbl.find_opt tm (TC.span_of_expr e)) in
      (match ty with
       | Some t ->
         s.tc_env <- { s.tc_env with TC.vars = TC.StrMap.add name (TC.Mono t) s.tc_env.TC.vars };
         s.bound <- name :: s.bound;
         Printf.printf "%s : %s\n%!" name (normalize_type_vars (TC.pp_ty t))
       | None -> Printf.printf "%s bound (type unknown to the shell; later uses may not typecheck)\n%!" name)
    end

let type_of s src =
  s.n <- s.n + 1;
  let text = fragment_source s ~src ~body:(Printf.sprintf "    (%s)" src) in
  match parse_module text with
  | Error e -> List.iter (fun (d : March_errors.Errors.diagnostic) -> Printf.printf "error: %s\n%!" d.message) e
  | Ok m ->
    let errors = March_errors.Errors.create () in
    let env = { s.tc_env with TC.errors; refs = ref []; current_decl = ref "" } in
    let (errs, tm) = TC.check_module_with_env env m in
    if March_errors.Errors.has_errors errs then
      List.iter (fun (d : March_errors.Errors.diagnostic) -> print_endline d.message)
        (March_errors.Errors.sorted errs)
    else
      match Option.bind (entry_last_expr m) (fun e -> Hashtbl.find_opt tm (TC.span_of_expr e)) with
      | Some t -> print_endline (normalize_type_vars (TC.pp_ty t))
      | None -> print_endline "?"

let help : (int -> unit, out_channel, unit) format = {|  <expr>                  evaluate on the node and print the result
  <expr> limit: N         print at most N elements of each collection and N characters
                          of each string, at every depth (limit: all for everything)
  let <name> = <expr>     evaluate on the node and keep the value for later inputs
  :t <expr>               the type of an expression (nothing runs)
  :limit N                the session's default limit (now %d)
  :caps                   the capabilities an input may use
  :quit                   end the session
|}

(* A trailing `limit: N` / `limit: all`. *)
let split_limit line =
  let line = String.trim line in
  match String.rindex_opt line ' ' with
  | Some i when i > 0 ->
    let before = String.trim (String.sub line 0 i)
    and last = String.sub line (i + 1) (String.length line - i - 1) in
    if String.length before > 6 && String.sub before (String.length before - 6) 6 = "limit:" then
      let expr = String.trim (String.sub before 0 (String.length before - 6)) in
      (match last with
       | "all" -> (expr, Some 0)
       | n -> (match int_of_string_opt n with Some k when k >= 0 -> (expr, Some k) | _ -> (line, None)))
    else (line, None)
  | _ -> (line, None)

let parse_let line =
  let line = String.trim line in
  if starts_with line "let " then
    match String.index_opt line '=' with
    | Some i ->
      let name = String.trim (String.sub line 4 (i - 4)) in
      let ok_name = name <> "" && String.for_all (fun c ->
          (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_') name in
      if ok_name then Some (name, String.trim (String.sub line (i + 1) (String.length line - i - 1)))
      else None
    | None -> None
  else None

let handle s line =
  let line = String.trim line in
  if line = "" then ()
  else if line = ":quit" || line = ":q" then raise (Session_over "")
  else if line = ":help" then Printf.printf help s.limit
  else if line = ":caps" then
    List.iter (fun (name, path, _, _) -> Printf.printf "  %-8s Cap(%s)\n" name path) caps
  else if starts_with line ":limit " then
    (match int_of_string_opt (String.trim (String.sub line 7 (String.length line - 7))) with
     | Some k when k >= 0 -> s.limit <- k
     | _ -> print_endline "usage: :limit N")
  else if starts_with line ":t " then type_of s (String.sub line 3 (String.length line - 3))
  else if mentions line "root_cap" then
    print_endline "error: the shell's capabilities are the pre-bound names (:caps), not root_cap"
  else
    match parse_let line with
    | Some (name, rhs) -> eval_let s name rhs
    | None ->
      let expr, lim = split_limit line in
      eval_expr s expr ~limit:(Option.value lim ~default:s.limit)

(* Entry point from the driver.  [socket] is the node's `<reload>.shell`. *)
let run ~socket ~(program : Ast.module_) ~type_map ~tc_env ~timeout_ms ~(inputs : string option) =
  let sk = match March_forge.Cmd_hot_reload.read_sk_raw () with
    | Ok sk -> sk
    | Error m -> Printf.eprintf "march shell: %s\n" m; exit 1 in
  let conn = try connect socket with Unix.Unix_error (e, _, _) ->
    Printf.eprintf "march shell: %s: %s\n" socket (Unix.error_message e); exit 1 in
  let hello = send conn "HELLO"; recv conn in
  let epoch, lo =
    match words hello with
    | "OK" :: _ ->
      let e = Option.bind (field hello "epoch") int_of_string_opt in
      let lo = Option.bind (field hello "slots") (fun r ->
          match String.split_on_char '-' r with a :: _ -> int_of_string_opt a | [] -> None) in
      (match e, lo with Some e, Some lo -> (e, lo) | _ ->
          Printf.eprintf "march shell: bad HELLO reply: %s\n" hello; exit 1)
    | _ -> Printf.eprintf "march shell: %s\n" hello; exit 1 in
  let ident =
    (* The summary, then only the groups that differ from ours
       (Shell_ident.fetch); the whole table from a node that predates it. *)
    let ask verb =
      let r = send conn verb; recv conn in
      match words r with
      | [ "OK"; b64 ] -> Ok (b64_decode b64)
      | _ -> Error r in
    match March_jit.Shell_ident.fetch_check ~ask program.Ast.mod_decls with
    | Ok c ->
      (match March_jit.Shell_ident.differing c with
       | [] -> ()
       | diffs ->
         let n = List.length diffs in
         Printf.eprintf
           "march shell: %d declaration%s here differ%s from the node's build (%s%s); \
            inputs that reach %s are refused\n%!"
           n (if n = 1 then "" else "s") (if n = 1 then "s" else "")
           (String.concat ", " (List.map March_jit.Shell_ident.describe_key
                                  (List.filteri (fun i _ -> i < 5) diffs)))
           (if n > 5 then ", ..." else "") (if n = 1 then "it" else "them"));
      Some c
    | Error r ->
      Printf.eprintf "march shell: the node does not report its build identity (%s); \
                      inputs are not checked against its code\n%!" r;
      None in
  let jit = March_jit.Repl_jit.create_shell () in
  March_jit.Repl_jit.shell_set_slot_base jit lo;
  let s = { conn; epoch; sk; jit; tc_env; program_name = program.Ast.mod_name.Ast.txt;
            program_decls = program.Ast.mod_decls;
            program_type_map = type_map; shows = Shell_render_gen.show_impls program.Ast.mod_decls;
            limit = default_limit; timeout_ms; n = 0; bound = [];
            failed = false; triple = field hello "triple"; ident;
            challenge = (match field hello "session" with
                | Some c -> c
                | None ->
                  Printf.eprintf "march shell: the node's HELLO has no session challenge \
                                  (it predates replay protection): %s\n%!" hello;
                  exit 1) } in
  (* Lower the program now, before the first prompt, rather than on the
     first input. *)
  March_jit.Repl_jit.shell_lower_program jit ~program_name:s.program_name
    ~program_decls:s.program_decls ~program_type_map:s.program_type_map;
  let interactive = inputs = None && Unix.isatty Unix.stdin in
  let lines = match inputs with
    | Some text -> ref (String.split_on_char '\n' text)
    | None -> ref [] in
  (* Line editing + persistent history, on a terminal only: stdin and stdout
     both ttys.  Anything else (pipe, redirect, --shell-inputs, forge rpc)
     takes the plain path below, byte for byte as before. *)
  let editing = interactive && Shell_tty.available () in
  let history_path = if editing then March_repl.Shell_line.default_path () else None in
  let history = ref (match history_path with
      | Some p -> March_repl.Shell_line.load p
      | None -> [||]) in
  let next_line () =
    match inputs with
    | Some _ -> (match !lines with l :: rest -> lines := rest; Some l | [] -> None)
    | None when editing ->
      (match Shell_tty.read_line ~prompt:"march> " !history with
       | Shell_tty.End_of_input -> None
       | Shell_tty.Line l ->
         let h, added = March_repl.Shell_line.record !history l in
         history := h;
         (if added then
            match history_path, March_repl.Shell_line.history_entry l with
            | Some p, Some e -> March_repl.Shell_line.append p e
            | _ -> ());
         Some l)
    | None ->
      if interactive then (print_string "march> "; flush stdout);
      In_channel.input_line stdin in
  if interactive then
    Printf.printf "attached at epoch %d (:help for commands, :quit to leave)\n%!" epoch;
  let code =
    try
      let rec loop () =
        match next_line () with
        | None -> ()
        | Some l ->
          last_failed := false;
          t_compile := 0.0; t_node := 0.0;
          let t0 = Unix.gettimeofday () in
          (try handle s l with Unix.Unix_error (e, f, _) ->
             raise (Session_over (Printf.sprintf "%s: %s" f (Unix.error_message e))));
          if timing && String.trim l <> "" then
            Printf.eprintf "[shell-timing] compile %.1f node %.1f total %.1f ms\n%!"
              !t_compile !t_node ((Unix.gettimeofday () -. t0) *. 1000.);
          if !last_failed then s.failed <- true;
          loop ()
      in
      loop ();
      (* Scripted (--shell-inputs, forge rpc): fail when any input did. *)
      if inputs <> None && s.failed then 1 else 0
    with Session_over "" -> 0
       | Session_over m -> print_endline m; 2
  in
  (try send conn "BYE"; Unix.close conn.fd with _ -> ());
  exit code
