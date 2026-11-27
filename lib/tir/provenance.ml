(** Source provenance side table: [fn_name -> origin].

    TIR's [fn_def] carries no span (lib/tir/tir.ml), and adding one would
    churn every TIR snapshot and [Serialize]; this table is the side-table
    alternative (specs/plans/incremental-codegen-cas-plan.md §7, A2), the same
    shape as [Js_emit]'s [fn_lines].

    Lifecycle (one table per lowering, module-level like [Mono.repr_table]):
    - [reset] at the start of [Lower.lower_module]; the REPL/JIT lowers one
      fragment per call, so its table is per-fragment with no opt-out needed.
    - lowering [note_span]s every parsed fn (top-level, lambda) under the
      name it has at creation, and [rename]s it at each later rename site;
    - a local NAMED fn (`fn go(...)` inside a body) keeps its source name, so
      that name is not a key: lowering [note_local]s it into the list of the
      top-level fn being lowered ([attach_locals]), and Defun asks
      [local_span] for the k-th `go` of the host it is lifting from;
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

(* Local named fns.  A local `fn go` is called [go] in the TIR until Defun
   lifts it, and a program has many: `pending` keyed by that name gave every
   [go] the span of whichever was lowered LAST (prelude `length`'s helper
   reported at a line of stdlib/shell_render.march).  So they are kept per
   top-level fn instead, in lowering order: [staged] collects them while one
   fn's body lowers, [locals] holds the finished lists under the fn's name
   ([rename] moves a list with its fn, [record ~from] hands a clone its
   original's).  specs/progress/2026-11-26-local-fn-provenance.md *)
type locals = (string * March_ast.Ast.span) list

let staged : locals ref = ref []
let locals : (string, locals) Hashtbl.t = Hashtbl.create 256

(* A fn is noted under its bare creation-time name and, when it belongs to a
   module, [rename]d to the qualified one right after.  Until then it sits on
   the key of any earlier fn that KEEPS that bare name (a prelude fn, an
   entry-module fn): prelude `reverse` lost its span and its local fns to
   whichever `Mod.reverse` was lowered after it.  So a note that lands on an
   occupied key sets the occupant aside, and the rename that moves the
   newcomer away puts it back. *)
let displaced_spans : (string, March_ast.Ast.span) Hashtbl.t = Hashtbl.create 16
let displaced_locals : (string, locals) Hashtbl.t = Hashtbl.create 16

let module_file : string option ref = ref None
let current_host : string option ref = ref None

let reset () =
  Hashtbl.reset table;
  Hashtbl.reset pending;
  Hashtbl.reset locals;
  Hashtbl.reset displaced_spans;
  Hashtbl.reset displaced_locals;
  staged := [];
  module_file := None;
  current_host := None

let note_local name (sp : March_ast.Ast.span) =
  if sp.March_ast.Ast.start_line > 0 then staged := (name, sp) :: !staged

let enter_locals () : locals =
  let saved = !staged in
  staged := [];
  saved

let leave_locals (saved : locals) : locals =
  let got = List.rev !staged in
  staged := saved;
  got

let attach_locals name (ls : locals) =
  (match Hashtbl.find_opt locals name with
   | Some prev -> Hashtbl.add displaced_locals name prev; Hashtbl.remove locals name
   | None -> ());
  if ls <> [] then Hashtbl.replace locals name ls

(* The source name of a local fn as Defun meets it.
   [Lower_decls.uniquify_fn] renames one that shadows to [go$sh<n>], and TRMC
   puts a [go$dps] helper beside a modulo-cons [go]: the same declaration. *)
let dps_suffix = "$dps"

let is_dps_local (name : string) : bool =
  let n = String.length name and k = String.length dps_suffix in
  n > k && String.sub name (n - k) k = dps_suffix

let source_name_of_local (name : string) : string =
  let name =
    if is_dps_local name
    then String.sub name 0 (String.length name - String.length dps_suffix) else name in
  let n = String.length name in
  let rec digits i = if i > 0 && name.[i - 1] >= '0' && name.[i - 1] <= '9' then digits (i - 1) else i in
  let d = digits n in
  if d < n && d >= 3 && String.sub name (d - 3) 3 = "$sh" then String.sub name 0 (d - 3)
  else name

let local_span ~host name (k : int) : March_ast.Ast.span option =
  match Hashtbl.find_opt locals host with
  | None -> None
  | Some ls ->
    let src = source_name_of_local name in
    (match List.filter (fun (n, _) -> n = src) ls with
     | [] -> None
     | same ->
       (* The k-th local of that name in the host, by lowering order.  Past
          the end (a pass duplicated a body) the first is the best answer. *)
       Some (snd (match List.nth_opt same k with Some e -> e | None -> List.hd same)))

let note_span name (sp : March_ast.Ast.span) =
  (* [Ast.dummy_span] (derived/synthesised decls) has line 0: skip it so
     [span_of] falls through to the host's span.  An EMPTY file name is not
     a reason to skip: a module parsed from a string (tests, the REPL) has
     real lines and no file. *)
  (match Hashtbl.find_opt pending name with
   | Some prev -> Hashtbl.add displaced_spans name prev; Hashtbl.remove pending name
   | None -> ());
  if sp.March_ast.Ast.start_line > 0 then Hashtbl.replace pending name sp

(* Undo one displacement of [name] in [tbl], if there is one. *)
let restore_displaced displaced tbl name =
  match Hashtbl.find_opt displaced name with
  | Some prev -> Hashtbl.remove displaced name; Hashtbl.replace tbl name prev
  | None -> ()

let rename ~old ~new_ =
  if old <> new_ then begin
    (match Hashtbl.find_opt pending old with
     | Some sp -> Hashtbl.remove pending old; Hashtbl.replace pending new_ sp
     | None -> ());
    restore_displaced displaced_spans pending old;
    (match Hashtbl.find_opt table old with
     | Some o -> Hashtbl.remove table old; Hashtbl.replace table new_ o
     | None -> ());
    (match Hashtbl.find_opt locals old with
     | Some ls -> Hashtbl.remove locals old; Hashtbl.replace locals new_ ls
     | None -> ());
    restore_displaced displaced_locals locals old
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

let record name ?host ?from ?span ?derived ~pass () =
  let inherited = Option.bind from (fun n -> Hashtbl.find_opt table n) in
  (* A clone of a top-level fn has the same local fns as its original. *)
  (match Option.bind from (Hashtbl.find_opt locals) with
   | Some ls when not (Hashtbl.mem locals name) -> Hashtbl.replace locals name ls
   | _ -> ());
  let host = match host with
    | Some h -> Some h
    | None ->
      (match !current_host with
       | Some h -> Some h
       | None -> Option.bind inherited (fun o -> o.host)) in
  let src_span = match span with
    | Some given -> given
    | None ->
      (match Option.bind from span_of with
       | Some sp -> Some sp
       | None -> Hashtbl.find_opt pending name) in
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

(** How a crash report names a source file: a stdlib file (one whose
    directory is literally named "stdlib", the rule bin/main.ml's backtrace
    uses) as "stdlib/<name>.march", so where the compiler is installed does
    not end up in the program; any other file as the compiler was given it. *)
let display_file (file : string) : string =
  if Filename.basename (Filename.dirname file) = "stdlib"
  then "stdlib/" ^ Filename.basename file
  else file

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
