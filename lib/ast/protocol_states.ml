(** Generated session states → the protocol step each one stands for
    (specs/plans/2026-11-02-diagnostics-depth-plan.md §F3), and the
    conversation drawn as a sequence diagram
    (specs/plans/2026-11-05-diag-protocol-sequence-diagram.md).

    `@[endpoints]` turns every node of a role's projection into a state type
    (`Stream_Cons.S_recv_Msg_Prod_Cons_1`, `S_choose_more_done`, `S_end`), and a
    role body is written against those names.  A body that takes a step out of
    order is therefore a type mismatch between two generated names, which says
    nothing about the protocol the user wrote.  [Desugar_endpoints] records here,
    for each state, what the role does there and where the protocol says so;
    [Typecheck_unify] reads it to phrase the mismatch in protocol terms.

    Display only: nothing reads it to decide a type.  Process-global and never
    reset; keys are the role module's qualified state names, which a later
    desugar of the same protocol overwrites with the same facts. *)

(** Where a state sits in the protocol's steps: one index per nesting level,
    into the steps [visible] keeps, in order.  Into a `loop`, the next index
    is into its body; into a `choose`, the next index picks the branch and
    the one after it the step in that branch.  An index equal to the length
    of a list is the slot after its last step: at the top level, the end of
    the conversation.  Both projections ([Desugar_endpoints.project] and
    [Typecheck_session.project_steps_at]) tag the states they build with it.
    A state whose position is not certain (a branch join, a crash branch, a
    second `S_end`) has none, and the diagram is not drawn for it. *)
type pos = int list

type info = {
  ps_proto : string;          (** the protocol, `Stream` *)
  ps_role  : string;          (** the role, `Cons` *)
  ps_doing : string;          (** what the role does in this state, in prose:
                                  "send an `Int` to `Prod`", "close the conversation" *)
  ps_call  : string;          (** the generated function that takes the step,
                                  `Stream_Cons.recv_Msg_Prod_Cons_1` *)
  ps_span  : Ast.span option; (** the protocol step, when it has one *)
  ps_branches : (string * bool) list;
                              (** for an offer: each branch label, and whether
                                  the role's conversation ends right after it *)
  ps_pos : pos option;        (** the state's place in the conversation *)
}

let table : (string, info) Hashtbl.t = Hashtbl.create 16

let record ~state info = Hashtbl.replace table state info

(** The same facts keyed by the generated function that takes the step
    (`Fan_A.send_Number`, `Stream_Prod.offer_more_done`), for errors at a
    call whose state is right but whose other arguments are not: a payload
    of the wrong type, a branch callback left out. *)
let calls : (string, info) Hashtbl.t = Hashtbl.create 16

let record_call ~call info = Hashtbl.replace calls call info

let last_component s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

(** Every state whose last name component is [name]'s: the checker sees a
    role module's state types bare, and two roles may both have `S_end`. *)
let find_all name =
  let short = last_component name in
  Hashtbl.fold (fun k v acc -> if last_component k = short then v :: acc else acc) table []

(** The step [name] calls, matched on its last two components (`Fan_A.send_Number`)
    so a call written through an enclosing module's path still finds it. *)
let find_call name =
  match Hashtbl.find_opt calls name with
  | Some i -> Some i
  | None ->
    let tail2 s = match String.rindex_opt s '.' with
      | Some i -> (match String.rindex_from_opt s (i - 1) '.' with
          | Some j -> String.sub s (j + 1) (String.length s - j - 1)
          | None -> s)
      | None -> s in
    let t = tail2 name in
    if not (String.contains t '.') then None
    else
      match Hashtbl.fold (fun k v acc -> if tail2 k = t then v :: acc else acc) calls [] with
      | [ i ] -> Some i
      | _ -> None

(* ── The conversation as a sequence diagram ───────────────────────────── *)

(** Each protocol's steps as the user wrote them, keyed by protocol name:
    the diagram draws the whole conversation, not one role's projection. *)
let protocols : (string, Ast.protocol_step list) Hashtbl.t = Hashtbl.create 4

let record_protocol ~proto (steps : Ast.protocol_step list) =
  Hashtbl.replace protocols proto steps

(** The steps a position counts: `may crash` and `role R needs` are
    declarations, not steps of the conversation. *)
let visible (steps : Ast.protocol_step list) =
  List.filter (function Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ -> false | _ -> true) steps

(** [pos] is the first step of a `loop` body in [proto]: the state every
    repeating branch comes back to. *)
let at_loop_start ~proto (pos : pos) : bool =
  let rec go (steps : Ast.protocol_step list) = function
    | i :: rest ->
      (match List.nth_opt (visible steps) i with
       | Some (Ast.ProtoLoop (body, _)) -> rest = [ 0 ] || go body rest
       | Some (Ast.ProtoChoice (_, branches)) ->
         (match rest with
          | b :: rest' ->
            (match List.nth_opt branches b with
             | Some (_, body) -> go body rest'
             | None -> false)
          | [] -> false)
       | _ -> false)
    | [] -> false in
  match Hashtbl.find_opt protocols proto with
  | Some steps -> go steps pos
  | None -> false

(** [a] comes before [b] in the conversation: lexicographic, a container
    before anything inside it. *)
let rec pos_before (a : pos) (b : pos) =
  match a, b with
  | [], [] -> false
  | [], _ -> true
  | _, [] -> false
  | x :: xs, y :: ys -> x < y || (x = y && pos_before xs ys)

let rec involves role (s : Ast.protocol_step) =
  match s with
  | Ast.ProtoMsg (a, b, _, _) -> a.Ast.txt = role || b.Ast.txt = role
  | Ast.ProtoLoop (body, _) -> List.exists (involves role) body
  | Ast.ProtoChoice (c, brs) ->
    c.Ast.txt = role || List.exists (fun (_, ss) -> List.exists (involves role) ss) brs
  | Ast.ProtoCrashOr (m, _, _) -> involves role m
  | Ast.ProtoStop _ | Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ -> false

(** How many rows the whole protocol would take drawn out: a two-step
    conversation needs no diagram. *)
let rec size (steps : Ast.protocol_step list) =
  List.fold_left (fun n s -> n + match s with
      | Ast.ProtoLoop (body, _) -> 1 + size body
      | Ast.ProtoChoice (_, brs) -> 1 + List.fold_left (fun n (_, ss) -> n + size ss) 0 brs
      | _ -> 1) 0 (visible steps)

type row = {
  indent : int;
  label  : string;           (** a labelled message's label, else "" *)
  text   : string;
  mark   : string;           (** the right-hand column, "" for none *)
  rpos   : pos;
  header : bool;             (** an opened `loop` or `choose`: not a step *)
  mine   : bool;             (** the role takes part in it *)
  is_end : bool;             (** `stop` or the end of the conversation *)
  is_msg : bool;             (** a message: its text sits in the label column *)
}

let ticks l = "`" ^ l ^ "`"

let others_mark = function
  | [] -> ""
  | [ l ] -> "other branch: " ^ ticks l
  | ls -> "other branches: " ^ String.concat ", " (List.map ticks ls)

(** The rows of the conversation along the path to [here], and on to
    [tried] when that lies on the same path (a step after it, or inside a
    `loop` or `choose` the path goes through).  [here] and [tried] are what
    remains of each position below [prefix]: [None] when it does not
    descend here. *)
let rec rows ~role ~indent ~(prefix : int list) (steps : Ast.protocol_step list)
    ~(here : int list option) ~(tried : int list option) : row list =
  let vs = visible steps in
  let n = List.length vs in
  let head = function Some (i :: _) -> Some i | _ -> None in
  let last = match head here, head tried with
    | Some h, Some t -> max h t
    | Some h, None | None, Some h -> h
    | None, None -> -1 in
  let descends p i = match p with Some (j :: _ :: _) -> j = i | _ -> false in
  (* A choice the role is AT is drawn closed: what lies inside is a branch
     it has not taken yet, so a step tried there is not on the path. *)
  let at_here i = here = Some [ i ] in
  let drop k = function Some l when List.length l > k -> Some (List.drop k l) | _ -> None in
  let row ?(label = "") ?(mark = "") ?(header = false) ?(is_end = false) ?(is_msg = false) ~mine i text =
    { indent; label; text; mark; rpos = prefix @ [ i ]; header; mine; is_end; is_msg } in
  let msg_row i (s : Ast.protocol_step) = match s with
    | Ast.ProtoMsg (a, b, t, lbl) | Ast.ProtoCrashOr (Ast.ProtoMsg (a, b, t, lbl), _, _) ->
      [ row ~label:(match lbl with Some l -> l.Ast.txt ^ ":" | None -> "") ~is_msg:true
          ~mine:(a.Ast.txt = role || b.Ast.txt = role) i
          (Printf.sprintf "%s -> %s : %s" a.Ast.txt b.Ast.txt (Ast.show_ty t)) ]
    | _ -> [] in
  List.concat (List.init (last + 1) (fun i ->
      if i >= n then
        (if prefix = [] then [ row ~mine:true ~is_end:true i "(end of conversation)" ] else [])
      else
        let s = List.nth vs i in
        let h = descends here i and t = descends tried i && not (at_here i) in
        match s with
        | Ast.ProtoLoop (body, _) when h || t ->
          row ~header:true ~mark:"(repeats)" ~mine:false i "loop do"
          :: rows ~role ~indent:(indent + 2) ~prefix:(prefix @ [ i ]) body
               ~here:(drop 1 here) ~tried:(drop 1 tried)
        | Ast.ProtoChoice (c, brs) when h || t ->
          let branch = match (if h then here else tried) with
            | Some (_ :: b :: _) -> b | _ -> 0 in
          let same p = descends p i && (match p with Some (_ :: b :: _) -> b = branch | _ -> false) in
          (match List.nth_opt brs branch with
           | None -> []
           | Some (lbl, body) ->
             let others = List.filter_map (fun ((l : Ast.name), _) ->
                 if l.Ast.txt = lbl.Ast.txt then None else Some l.Ast.txt) brs in
             row ~header:true ~mark:(others_mark others) ~mine:(c.Ast.txt = role) i
               (Printf.sprintf "choose by %s: %s" c.Ast.txt lbl.Ast.txt)
             :: rows ~role ~indent:(indent + 2) ~prefix:(prefix @ [ i; branch ]) body
                  ~here:(if same here then drop 2 here else None)
                  ~tried:(if same tried then drop 2 tried else None))
        | Ast.ProtoLoop _ -> [ row ~mine:(involves role s) i "loop ... end" ]
        | Ast.ProtoChoice (c, brs) ->
          [ row ~mine:(involves role s) i
              (Printf.sprintf "choose by %s: %s" c.Ast.txt
                 (String.concat " | " (List.map (fun ((l : Ast.name), _) -> l.Ast.txt) brs))) ]
        | Ast.ProtoStop _ -> [ row ~mine:true ~is_end:true i "stop" ]
        | Ast.ProtoMsg _ | Ast.ProtoCrashOr _ -> msg_row i s
        | Ast.ProtoMayCrash _ | Ast.ProtoRoleNeeds _ -> []))

(** Replace every run of plain rows in [rs] by one `… N earlier steps` row.
    Headers stay, they open what the kept rows are inside, and so does a
    row [keep] names (the step tried). *)
let elide_runs ~word ~keep (rs : row list) : row list =
  let flush acc run =
    match run with
    | [] -> acc
    | [ r ] -> r :: acc
    | _ ->
      let k = List.length run in
      let first = List.nth run (k - 1) in
      { first with label = ""; text = Printf.sprintf "… %d %s steps" k word; mark = "";
                   header = false; mine = false; is_end = false; is_msg = false } :: acc in
  let rec go acc run = function
    | [] -> List.rev (flush acc run)
    | r :: rest when r.header || keep r -> go (r :: flush acc run) [] rest
    | r :: rest -> go acc (r :: run) rest in
  go [] [] rs

(** The conversation of protocol [proto] up to the step the role is at,
    as a note: each step on one line with what [subject] (the role, or
    "the channel") has done, must do next, and tried instead.  [None]
    when the protocol is not recorded, is too short to need it, or the
    positions do not point into it. *)
let diagram ~proto ~role ~subject ~(here : pos) ?(tried : (pos * string) option) () : string option =
  match Hashtbl.find_opt protocols proto with
  | None -> None
  | Some steps when size steps <= 2 -> None
  | Some steps ->
    let tried_pos = Option.map fst tried in
    let all = rows ~role ~indent:0 ~prefix:[] steps ~here:(Some here) ~tried:tried_pos in
    let here_row = List.find_opt (fun r -> r.rpos = here && not r.header) all in
    (* The step tried may be a `choose` the path goes through (the chooser,
       inside a branch, choosing again): then its row is the opened header. *)
    let tried_row = match tried with
      | Some (p, _) -> List.find_opt (fun r -> r.rpos = p) all
      | None -> None in
    (match here_row with
     | None -> None
     | Some hr ->
       let is_here r = r == hr in
       let is_tried r = match tried_row with Some tr -> r == tr | None -> false in
       let mark r =
         let done_ = r.mine && not r.header && pos_before r.rpos here in
         let arrow =
           if is_here r then
             Some (if hr.is_end then subject ^ " can only close here"
                   else subject ^ " must do this next")
           else if is_tried r then Option.map snd tried
           else None in
         String.concat "   " (List.filter (( <> ) "")
           [ (if done_ then "done" else "");
             (match arrow with Some a -> "<- " ^ a | None -> r.mark) ]) in
       (* Context: three steps before `here`, and three after it on the way
          to `tried`; the rest elided, headers kept. *)
       let keep = 3 in
       let idx p = let rec f i = function [] -> i | x :: xs -> if p x then i else f (i + 1) xs in f 0 all in
       let hi = idx is_here in
       let before = List.filteri (fun i _ -> i < hi) all in
       let before =
         let n = List.length before in
         let far = List.filteri (fun i _ -> i < n - keep) before in
         let near = List.filteri (fun i _ -> i >= n - keep) before in
         elide_runs ~word:"earlier" ~keep:is_tried far @ near in
       let after = match tried_row with
         | Some tr when pos_before here tr.rpos ->
           let ti = idx is_tried in
           let between = List.filteri (fun i _ -> i > hi && i < ti) all in
           let n = List.length between in
           let near = List.filteri (fun i _ -> i < keep) between in
           let far = List.filteri (fun i _ -> i >= keep) between in
           if n <= keep then between @ [ tr ]
           else near @ elide_runs ~word:"more" ~keep:is_tried far @ [ tr ]
         | _ -> [] in
       let shown = List.map (fun r -> { r with mark = mark r }) (before @ [ hr ] @ after) in
       (* Columns are aligned by code points: the elision row's `…` is one. *)
       let width s = String.fold_left (fun n c -> if Char.code c land 0xC0 = 0x80 then n else n + 1) 0 s in
       let lw = List.fold_left (fun w r -> max w (width r.label)) 0 shown in
       let left r =
         let lbl = if lw = 0 || not r.is_msg then "" else r.label ^ String.make (lw - width r.label + 1) ' ' in
         String.make r.indent ' ' ^ lbl ^ r.text in
       let tw = List.fold_left (fun w r -> max w (width (left r))) 0 shown in
       let line r =
         let l = left r in
         if r.mark = "" then "  " ^ l
         else Printf.sprintf "  %s%s   %s" l (String.make (tw - width l) ' ') r.mark in
       Some (Printf.sprintf "The conversation so far, in protocol `%s`:\n\n%s" proto
               (String.concat "\n" (List.map line shown))))
