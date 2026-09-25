(* `<actor>_migrate_msg`'s old message type -> the actor it migrates for.

   A hot-reload `fn tally_migrate_msg(m : TallyMsgV1.Msg) : Option(Tally.Msg)`
   is called by the runtime with a REAL old-format message: a heap cell the
   previous build allocated as a `Tally_Msg` constructor, so it carries that
   build's actor-message representation (forced Boxed, see [Kind.repr_of]) and
   its actor-message constructor tag ([Llvm_toplevel.variant_ctor_tags]). The
   user's `TallyMsgV1.Msg` is an ordinary variant to the typechecker and stays
   one; this table is what tells codegen to compile it with the old actor's
   representation instead: Boxed, and each constructor carrying the tag
   `Tally_Msg.<Ctor>` has in every build (actor-message tags are a stable
   function of the qualified constructor name). Without it the compiled match
   switched on 0, 1, ... and fell to "non-exhaustive pattern match"
   (specs/progress/2026-09-25-migrate-msg-actor-message-tags.md).

   Lowering records each `*_migrate_msg` with the module prefix it was
   declared under and its parameter type as written; the lowered parameter
   type is the canonical BARE name (`Msg`) and loses the qualifier, which is
   ambiguous as soon as two actors migrate (`TallyMsgV1.Msg`, `OtherV1.Msg`).
   [resolve] runs once lowering has every type declaration and binds each
   record to one declaration.

   Process-global and reset at the top of [Lower.lower_module], the same
   lifecycle as [Handler_owner]. *)

type pending = {
  p_fn : string;            (* TIR name of the migrate_msg fn *)
  p_candidates : string list;  (* declaration names to try, innermost scope first *)
  p_actor_msg : string;     (* `<Actor>_Msg` from the declared return type *)
}

let pending : pending list ref = ref []

(* old type declaration name -> `<Actor>_Msg` *)
let pins : (string, string) Hashtbl.t = Hashtbl.create 8

(* every name the pinned types are referred to by: the declaration name and,
   when it is unambiguous, the bare short name TIR uses in signatures *)
let pinned_names : (string, unit) Hashtbl.t = Hashtbl.create 8

(* fn name -> resolved old type declaration (for the .schemas.json writer) *)
let by_fn : (string, string) Hashtbl.t = Hashtbl.create 8

let reset () =
  pending := [];
  Hashtbl.reset pins;
  Hashtbl.reset pinned_names;
  Hashtbl.reset by_fn

let short_name s =
  match String.rindex_opt s '.' with
  | None -> s
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)

(** [register ~fn_name ~prefix ~written ~actor_msg]: [prefix] is the module
    prefix the fn was lowered under ("" or "A.B."), [written] the parameter
    type's name as the source spells it ("TallyMsgV1.Msg"). *)
let register ~fn_name ~prefix ~written ~actor_msg =
  let rec prefixes p =
    (* "A.B." -> ["A.B."; "A."; ""] *)
    if p = "" then [ "" ]
    else
      let body = String.sub p 0 (String.length p - 1) in
      match String.rindex_opt body '.' with
      | None -> [ p; "" ]
      | Some i -> p :: prefixes (String.sub body 0 (i + 1))
  in
  let candidates = List.map (fun p -> p ^ written) (prefixes prefix) in
  pending := { p_fn = fn_name; p_candidates = candidates; p_actor_msg = actor_msg } :: !pending

(** Bind every registered migrate_msg to its old type's declaration in
    [type_defs]. A parameter that already names an actor message type needs
    no pin. Raises [Failure] when one old type is claimed by two actors: its
    constructors cannot carry both actors' tags. *)
let resolve (type_defs : Tir.type_def list) =
  let decls = List.filter_map (function
      | Tir.TDVariant (n, _) -> Some n | _ -> None) type_defs in
  let short_count = Hashtbl.create 64 in
  List.iter (fun n ->
      let s = short_name n in
      Hashtbl.replace short_count s
        (1 + Option.value ~default:0 (Hashtbl.find_opt short_count s)))
    (List.sort_uniq compare decls);
  List.iter (fun p ->
      let found =
        match List.find_opt (fun c -> List.mem c decls) p.p_candidates with
        | Some d -> Some d
        | None ->
          (* A spelling the scope walk does not cover (e.g. qualified by the
             entry module's own name): accept a unique suffix match. *)
          let w = List.nth p.p_candidates (List.length p.p_candidates - 1) in
          let sfx = "." ^ w in
          (match List.filter (fun d ->
               let dl = String.length d and sl = String.length sfx in
               dl > sl && String.sub d (dl - sl) sl = sfx) decls with
           | [ d ] -> Some d
           | _ -> None)
      in
      match found with
      | None -> ()
      | Some d when Tir_names.is_actor_msg_name d -> ()
      | Some d ->
        (match Hashtbl.find_opt pins d with
         | Some other when other <> p.p_actor_msg ->
           failwith (Printf.sprintf
             "%s: the old message type %s is already the migrate_msg type of %s; \
              each actor's migrate_msg needs its own old type (its constructors \
              carry that actor's message tags)" p.p_fn d other)
         | _ -> ());
        Hashtbl.replace pins d p.p_actor_msg;
        Hashtbl.replace by_fn p.p_fn d;
        Hashtbl.replace pinned_names d ();
        let s = short_name d in
        if Hashtbl.find_opt short_count s = Some 1 then
          Hashtbl.replace pinned_names s ())
    (List.rev !pending)

(** The `<Actor>_Msg` whose tags declaration [decl] carries, if pinned. *)
let actor_of_decl (decl : string) : string option = Hashtbl.find_opt pins decl

(** The resolved old type declaration of migrate_msg fn [fn_name]. *)
let old_type_of_fn (fn_name : string) : string option = Hashtbl.find_opt by_fn fn_name

let is_pinned (name : string) : bool = Hashtbl.mem pinned_names name

(** An actor message type, or a type compiled with one's representation. *)
let has_actor_msg_repr (name : string) : bool =
  Tir_names.is_actor_msg_name name || is_pinned name
