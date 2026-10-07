(** Source provenance side table: [fn_name -> origin].

    TIR's [fn_def] carries no span (lib/tir/tir.ml), and adding one would
    churn every TIR snapshot and [Serialize]; this table is the side-table
    alternative (specs/plans/incremental-codegen-cas-plan.md §7, A2), the same
    shape as [Js_emit]'s [fn_lines].

    Lifecycle (one table per lowering, module-level like [Mono.repr_table]):
    - [reset] at the start of [Lower.lower_module]; the REPL/JIT lowers one
      fragment per call, so its table is per-fragment with no opt-out needed.
    - lowering [note_span]s every parsed fn (top-level and nested) under the
      name it has at creation, and [rename]s it at each later rename site;
    - [seed_from_lowering] at the END of [Lower.lower_module] turns the noted
      spans into origins for the final [tm_fns];
    - passes that create functions [record] a derivation; [sweep] after each
      pass names the pass for anything that slipped through, so every emitted
      function has an origin even when a pass forgets to record.

    Consumers: [Llvm_toplevel] (function-level [!dbg] under [--debug-info] and
    the [!march.provenance] named metadata), and [--dump-provenance]. *)

type derivation =
  | Mono_of of string * Tir.ty list      (* generic fn, type args *)
  | Fusion_of of string * string         (* producer, consumer *)
  | Hof_spec_of of string * string       (* g, specialised argument symbol *)
  | Defun_of of string                   (* the lambda's lowering-time name *)
  | Join_point_of of string
  | Inlined_from of string
  | Clone_of of string * string          (* original, reason (dps, unboxed, …) *)

type origin = {
  src_span : March_ast.Ast.span option;
  host     : string option;
  derived  : derivation list;
  passes   : string list;
}

let table : (string, origin) Hashtbl.t = Hashtbl.create 1024

(* Spans noted during lowering, by the name the fn carries at that moment.
   Kept after seeding: nested fns (lambdas, local [fn]s) never reach [tm_fns]
   but Defun's apply fn inherits their span from here. *)
let pending : (string, March_ast.Ast.span) Hashtbl.t = Hashtbl.create 1024

let module_file : string option ref = ref None
let current_host : string option ref = ref None

let reset () =
  Hashtbl.reset table;
  Hashtbl.reset pending;
  module_file := None;
  current_host := None

let note_span name (sp : March_ast.Ast.span) =
  (* [Ast.dummy_span] (derived/synthesised decls) has line 0: skip it so
     [span_of] falls through to the host's span.  An EMPTY file name is not
     a reason to skip: a module parsed from a string (tests, the REPL) has
     real lines and no file. *)
  if sp.March_ast.Ast.start_line > 0 then Hashtbl.replace pending name sp

let rename ~old ~new_ =
  if old <> new_ then begin
    (match Hashtbl.find_opt pending old with
     | Some sp -> Hashtbl.remove pending old; Hashtbl.replace pending new_ sp
     | None -> ());
    (match Hashtbl.find_opt table old with
     | Some o -> Hashtbl.remove table old; Hashtbl.replace table new_ o
     | None -> ())
  end

let find name = Hashtbl.find_opt table name

let span_of name =
  match Hashtbl.find_opt table name with
  | Some { src_span = Some sp; _ } -> Some sp
  | _ -> Hashtbl.find_opt pending name

let seed_from_lowering ~file (m : Tir.tir_module) =
  if file <> "" then module_file := Some file;
  List.iter (fun (fn : Tir.fn_def) ->
      let name = fn.Tir.fn_name in
      if not (Hashtbl.mem table name) then
        Hashtbl.replace table name
          { src_span = Hashtbl.find_opt pending name; host = None;
            derived = []; passes = ["lower"] })
    m.Tir.tm_fns

let record name ?host ?from ?derived ~pass () =
  let inherited = Option.bind from (fun n -> Hashtbl.find_opt table n) in
  let host = match host with
    | Some h -> Some h
    | None ->
      (match !current_host with
       | Some h -> Some h
       | None -> Option.bind inherited (fun o -> o.host)) in
  let src_span = match Option.bind from span_of with
    | Some sp -> Some sp
    | None -> Hashtbl.find_opt pending name in
  let derived = (match derived with Some d -> [d] | None -> [])
                @ (match inherited with Some o -> o.derived | None -> []) in
  let passes = match inherited with
    | Some o -> pass :: o.passes | None -> [pass] in
  Hashtbl.replace table name { src_span; host; derived; passes }

let with_host host f =
  let saved = !current_host in
  current_host := Some host;
  Fun.protect ~finally:(fun () -> current_host := saved) f

let sweep ~pass (m : Tir.tir_module) =
  List.iter (fun (fn : Tir.fn_def) ->
      if not (Hashtbl.mem table fn.Tir.fn_name) then
        Hashtbl.replace table fn.Tir.fn_name
          { src_span = Hashtbl.find_opt pending fn.Tir.fn_name; host = None;
            derived = []; passes = [pass] })
    m.Tir.tm_fns

(** Every nested [fn_def] (lambda, local fn, join point) in [m], mapped to the
    top-level function whose body contains it. *)
let nested_fn_hosts (m : Tir.tir_module) : (string, string) Hashtbl.t =
  let hosts = Hashtbl.create 256 in
  let rec walk host (e : Tir.expr) =
    match e with
    | Tir.ELetRec (fns, body) ->
      List.iter (fun (f : Tir.fn_def) ->
          Hashtbl.replace hosts f.Tir.fn_name host;
          walk host f.Tir.fn_body) fns;
      walk host body
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> walk host e1; walk host e2
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (b : Tir.branch) -> walk host b.Tir.br_body) brs;
      Option.iter (walk host) def
    | _ -> ()
  in
  List.iter (fun (f : Tir.fn_def) -> walk f.Tir.fn_name f.Tir.fn_body) m.Tir.tm_fns;
  hosts

(** The span to emit for [name]: its own, else its host's (transitively),
    else [None] (the emitter falls back to the module file, line 1). *)
let effective_span name =
  let rec go seen name =
    if List.mem name seen then None else
    match span_of name with
    | Some sp -> Some sp
    | None ->
      (match Hashtbl.find_opt table name with
       | Some { host = Some h; _ } -> go (name :: seen) h
       | _ -> None)
  in
  go [] name

let string_of_span (sp : March_ast.Ast.span) =
  Printf.sprintf "%s:%d:%d" sp.March_ast.Ast.file sp.March_ast.Ast.start_line
    sp.March_ast.Ast.start_col

let string_of_derivation = function
  | Mono_of (g, tys) ->
    Printf.sprintf "mono(%s[%s])" g (String.concat "," (List.map Pp.string_of_ty tys))
  | Fusion_of (p, c) -> Printf.sprintf "fusion(%s,%s)" p c
  | Hof_spec_of (g, a) -> Printf.sprintf "hof_spec(%s,%s)" g a
  | Defun_of l -> Printf.sprintf "defun(%s)" l
  | Join_point_of f -> Printf.sprintf "join_point(%s)" f
  | Inlined_from f -> Printf.sprintf "inlined_from(%s)" f
  | Clone_of (f, why) -> Printf.sprintf "clone(%s,%s)" f why

(** One-line rendering used by [!march.provenance] and [--dump-provenance]:
    [span<TAB>host<TAB>derivations<TAB>passes]. *)
let render_fields (o : origin) =
  [ (match o.src_span with Some sp -> string_of_span sp | None -> "-");
    (match o.host with Some h -> h | None -> "-");
    (match o.derived with [] -> "-"
      | ds -> String.concat ";" (List.map string_of_derivation ds));
    String.concat ";" (List.rev o.passes) ]

let render (o : origin) = String.concat "\t" (render_fields o)

(** The same fields, space-separated, for an LLVM metadata string. *)
let render_meta (o : origin) =
  String.concat " " (List.map2 (fun k v -> k ^ "=" ^ v)
                       ["span"; "host"; "derived"; "passes"] (render_fields o))

let all () =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) table []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

let dump oc =
  List.iter (fun (name, o) ->
      output_string oc name; output_char oc '\t';
      output_string oc (render o); output_char oc '\n') (all ())
