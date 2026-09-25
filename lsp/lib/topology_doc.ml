(** Editor support for the topology file: `topology.toml` and its
    `topology.<env>.toml` overlays (build step 7 of the distributed-deploys
    plan, specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md,
    section 4 and II.6).

    {1 One implementation}

    Everything that decides what the file MEANS is forge's
    [March_forge.Topology] (and its [Toml]), linked as a library: the parse
    and overlay merge ([of_strings], the same path [load] takes), the checks
    ([check]), the project index ([index_project_with], the walk
    [forge topology check] does) and the protocol facts ([proto_roles],
    [find_protocol]). This module adds only what an editor needs on top:

    - buffers: an open topology document or `.march` file is read from the
      editor instead of the disk ([index_project_with ~parse]);
    - positions: forge reports [file:line]; a diagnostic here covers the text
      of that line, with forge's message verbatim;
    - the cursor: which string or key the cursor is in ([context_at]), a
      small lexical scan that tolerates the half-typed text completion sees;
    - navigation: the declaration spans the index records ([Topology.site]).

    {1 Which diagnostics a document shows}

    - An overlay shows [forge topology check --env <env>]'s diagnostics that
      point into the overlay.
    - The base file shows [forge topology check]'s, plus those that
      [--env <env>] adds in the base file for each overlay next to it (on disk
      or open): a `place.count` above the host count only exists once an
      overlay supplies hosts, and its line is the role's, in the base. Those
      carry the source ["forge topology --env <env>"] so the editor says
      which environment raised them; the message is forge's. A diagnostic
      forge places in no topology file (a `.march` file that does not parse)
      is shown on the base file's first line. *)

module Lsp = Linol_lsp.Lsp
module Ast = March_ast.Ast
module T = March_forge.Topology
module Toml = March_forge.Toml

(* ── Recognising the documents ──────────────────────────────────────────── *)

type kind = Base | Overlay of string

let kind_of_path (path : string) : kind option =
  let b = Filename.basename path in
  if b = "topology.toml" then Some Base
  else begin
    let pre = "topology." and suf = ".toml" in
    let lb = String.length b and lp = String.length pre and ls = String.length suf in
    if lb > lp + ls && String.sub b 0 lp = pre && String.sub b (lb - ls) ls = suf then
      Some (Overlay (String.sub b lp (lb - lp - ls)))
    else None
  end

let is_topology_path path = kind_of_path path <> None

(* ── Buffers ────────────────────────────────────────────────────────────── *)

(** Open topology documents, by path. *)
let open_docs : (string, string) Hashtbl.t = Hashtbl.create 4

(** Open `.march` buffers, by path: what the index reads instead of the disk.
    Kept here rather than read from the analysis cache because an analysis
    of a buffer that does not parse keeps the last good source, and forge
    would see the broken file. *)
let march_buffers : (string, string) Hashtbl.t = Hashtbl.create 16

let set_open path text = Hashtbl.replace open_docs path text
let close path = Hashtbl.remove open_docs path
let set_march_buffer path text = Hashtbl.replace march_buffers path text
let close_march_buffer path = Hashtbl.remove march_buffers path

let open_paths () =
  Hashtbl.fold (fun p _ acc -> p :: acc) open_docs [] |> List.sort String.compare

let read_file path =
  try Some (In_channel.with_open_bin path In_channel.input_all) with _ -> None

(** A topology file's text: the open buffer, else the disk. *)
let text_of path =
  match Hashtbl.find_opt open_docs path with Some t -> Some t | None -> read_file path

(* ── The index, from buffers and disk ───────────────────────────────────── *)

(** path -> (digest of the text parsed, result): a keystroke in the topology
    file re-reads the project but reparses only what changed. *)
let parse_cache : (string, Digest.t * (Ast.module_, string) result) Hashtbl.t =
  Hashtbl.create 32

let cached_parse path src =
  let d = Digest.string src in
  match Hashtbl.find_opt parse_cache path with
  | Some (d', r) when d' = d -> r
  | _ ->
    let r = T.parse_source ~path src in
    Hashtbl.replace parse_cache path (d, r);
    r

let parse_path path =
  match Hashtbl.find_opt march_buffers path with
  | Some src -> cached_parse path src
  | None ->
    (match read_file path with
     | Some src -> cached_parse path src
     | None -> T.parse_module path  (* forge's own message for an unreadable file *))

let index ~root : T.index = T.index_project_with ~parse:parse_path ~root

(* ── Diagnostics ────────────────────────────────────────────────────────── *)

let base_of path = Filename.concat (Filename.dirname path) "topology.toml"

(** The overlays next to [root]'s base: on disk, or open in the editor. *)
let overlay_envs root : string list =
  let on_disk = try Array.to_list (Sys.readdir root) with Sys_error _ -> [] in
  let opened =
    List.filter_map (fun p -> if Filename.dirname p = root then Some (Filename.basename p) else None)
      (open_paths ())
  in
  List.filter_map (fun b -> match kind_of_path b with Some (Overlay e) -> Some e | _ -> None)
    (on_disk @ opened)
  |> List.sort_uniq String.compare

(** [forge topology check] over [files] (base first): the parse and merge,
    then, when that succeeds, the checks. *)
let run ~(index : T.index Lazy.t) (files : (string * string) list) : T.diag list =
  match T.of_strings files with
  | Error ds -> ds
  | Ok t -> T.check ~index:(Lazy.force index) t

(** The base file's own read error ([load]'s message) when it is neither
    open nor on disk. *)
let missing_base base =
  match T.parse_file base with Error ds -> ds | Ok _ -> []

(** The forge diagnostics a document shows, each with the environment whose
    overlay raised it ([None]: the base alone). See the module comment. *)
let topology_diags (path : string) : (T.diag * string option) list =
  let root = Filename.dirname path in
  let base = base_of path in
  let idx = lazy (index ~root) in
  match kind_of_path path with
  | None -> []
  | Some (Overlay _) ->
    (match text_of base, text_of path with
     | None, _ -> List.map (fun d -> (d, None)) (missing_base base)
     | _, None -> []
     | Some bt, Some ot ->
       run ~index:idx [ (base, bt); (path, ot) ]
       |> List.filter (fun (d : T.diag) -> d.T.loc.T.file = path)
       |> List.map (fun d -> (d, None)))
  | Some Base ->
    (match text_of path with
     | None -> []
     | Some bt ->
       let here (d : T.diag) =
         (* Not an overlay's: this file's, or a file forge reports that is not
            a topology file at all (an unparseable `.march`). *)
         d.T.loc.T.file = path || not (is_topology_path d.T.loc.T.file)
       in
       let ctx env =
         let files =
           (path, bt)
           :: (match env with
               | None -> []
               | Some e ->
                 let o = T.overlay_file ~root e in
                 (match text_of o with Some ot -> [ (o, ot) ] | None -> []))
         in
         run ~index:idx files |> List.filter here |> List.map (fun d -> (d, env))
       in
       let all = ctx None @ List.concat_map (fun e -> ctx (Some e)) (overlay_envs root) in
       let seen = Hashtbl.create 16 in
       List.filter (fun ((d : T.diag), _) ->
           let k = (d.T.loc.T.file, d.T.loc.T.line, d.T.severity, d.T.msg) in
           if Hashtbl.mem seen k then false else (Hashtbl.replace seen k (); true))
         all)

(* ── Positions ──────────────────────────────────────────────────────────── *)

let doc_of text = Utf16.build text

(** 0-indexed line of byte offset [off]. *)
let line_of_offset (d : Utf16.doc) off =
  let n = Array.length d.Utf16.line_starts in
  let rec go lo hi =
    (* last line whose start <= off *)
    if lo >= hi then lo
    else
      let mid = (lo + hi + 1) / 2 in
      if d.Utf16.line_starts.(mid) <= off then go mid hi else go lo (mid - 1)
  in
  go 0 (n - 1)

let lsp_pos_of_offset (d : Utf16.doc) off : Lsp.Types.Position.t =
  let line = line_of_offset d off in
  let byte_col = off - Utf16.line_start d line in
  Lsp.Types.Position.create ~line ~character:(Utf16.byte_col_to_lsp_char d ~line ~byte_col)

let lsp_range (d : Utf16.doc) a b : Lsp.Types.Range.t =
  Lsp.Types.Range.create ~start:(lsp_pos_of_offset d a) ~end_:(lsp_pos_of_offset d b)

(** Byte offset of an LSP (line, UTF-16 character) position. *)
let offset_of_lsp (d : Utf16.doc) ~line ~utf16_char =
  let line = max 0 (min line (Utf16.line_count d - 1)) in
  Utf16.line_start d line + Utf16.lsp_char_to_byte_col d ~line ~utf16_char

(** The written text of 0-indexed [line]: first non-blank byte to the last
    one before a comment. forge names a line; this is what it covers. *)
let line_extent (d : Utf16.doc) line =
  let ls = Utf16.line_start d line and le = Utf16.line_end d line in
  let s = d.Utf16.src in
  let body_end =
    match Toml.comment_start (String.sub s ls (le - ls)) with
    | Some i -> ls + i
    | None -> le
  in
  let a = ref ls in
  while !a < body_end && (s.[!a] = ' ' || s.[!a] = '\t') do incr a done;
  let b = ref body_end in
  while !b > !a && (s.[!b - 1] = ' ' || s.[!b - 1] = '\t' || s.[!b - 1] = '\r') do decr b done;
  if !a >= !b then (ls, le) else (!a, !b)

let source_name = function
  | None -> "forge topology"
  | Some env -> "forge topology --env " ^ env

(** The LSP form of forge's diagnostics for the document at [path] with
    text [text]. *)
let diagnostics ~path ~text : Lsp.Types.Diagnostic.t list =
  let d = doc_of text in
  List.map (fun ((dg : T.diag), env) ->
      let line =
        if dg.T.loc.T.file = path then max 0 (min (dg.T.loc.T.line - 1) (Utf16.line_count d - 1))
        else 0
      in
      let (a, b) = line_extent d line in
      Lsp.Types.Diagnostic.create
        ~range:(lsp_range d a b)
        ~severity:(match dg.T.severity with
            | T.Error -> Lsp.Types.DiagnosticSeverity.Error
            | T.Warning -> Lsp.Types.DiagnosticSeverity.Warning)
        ~source:(source_name env)
        ~message:(`String dg.T.msg) ())
    (topology_diags path)

(** Diagnostics for an open (or on-disk) topology document. *)
let diagnostics_for path : Lsp.Types.Diagnostic.t list =
  match text_of path with
  | None -> []
  | Some text -> diagnostics ~path ~text

(** The open topology documents whose diagnostics depend on [path]: every
    one in the same project when [path] is a topology file, every one whose
    directory contains [path] when it is a `.march` file. *)
let dependents_of path : string list =
  let dir = Filename.dirname path in
  List.filter (fun p ->
      let root = Filename.dirname p in
      if is_topology_path path then root = dir
      else
        let rl = String.length root in
        String.length path > rl && String.sub path 0 rl = root && path.[rl] = '/')
    (open_paths ())

(* ── The cursor ─────────────────────────────────────────────────────────── *)

type ctx =
  | Str of {
      section : string;
      path : string list;   (** enclosing keys, outermost first, ending in the key this string is the value of *)
      is_key : bool;        (** the string is itself a key (`"Checkout.Ledger" = ...`) *)
      in_array : bool;
      content : string;
      cstart : int;         (** byte offset of the first content byte *)
      cend : int;           (** byte offset of the closing quote (or end of line) *)
    }
  | Key of { section : string; path : string list; kstart : int; prefix : string }
  (** A bare key being typed; [path] is the enclosing tables' keys. *)
  | Header of { hstart : int; prefix : string }
  (** Inside a `[section]` header; [hstart] is just after the bracket(s). *)
  | Other

type frame = { fkey : string option; is_array : bool }

let is_word c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '-' || c = '.'

(** What the cursor at byte offset [cur] is in. A lexical scan, not the
    parser: it has to make sense of the half-typed text completion runs on
    (an unclosed string, a key with no `=` yet), which [Toml] rightly
    rejects. *)
let context_at (text : string) (cur : int) : ctx =
  let n = String.length text in
  let result = ref Other in
  let section = ref "" in
  let stack : frame list ref = ref [] in
  let cur_key = ref None in
  let expect_key = ref true in
  let line_start = ref true in
  let keys () = List.rev (List.filter_map (fun f -> f.fkey) !stack) in
  let in_array () = match !stack with f :: _ -> f.is_array | [] -> false in
  let i = ref 0 in
  let stop = ref false in
  while not !stop && !i <= n do
    let at_gap =
      !i = n || (match text.[!i] with ' ' | '\t' | '\r' | '\n' | ',' | '}' | '#' -> true | _ -> false)
    in
    if !i = cur && !expect_key && at_gap then begin
      result := Key { section = !section; path = keys (); kstart = cur; prefix = "" };
      stop := true
    end
    else if !i = n then stop := true
    else begin
      let c = text.[!i] in
      match c with
      | '\n' ->
        if !stack = [] then (expect_key := true; cur_key := None);
        line_start := true;
        incr i
      | ' ' | '\t' | '\r' -> incr i
      | '#' ->
        while !i < n && text.[!i] <> '\n' do incr i done
      | '[' when !stack = [] && !line_start ->
        let aot = !i + 1 < n && text.[!i + 1] = '[' in
        let hstart = !i + if aot then 2 else 1 in
        let j = ref hstart in
        while !j < n && text.[!j] <> ']' && text.[!j] <> '\n' do incr j done;
        if cur >= hstart && cur <= !j then begin
          result := Header { hstart; prefix = String.sub text hstart (cur - hstart) };
          stop := true
        end else begin
          section := String.trim (String.sub text hstart (!j - hstart));
          while !j < n && text.[!j] <> '\n' do incr j done;
          i := !j;
          cur_key := None;
          expect_key := true;
          line_start := false
        end
      | '"' ->
        line_start := false;
        let cstart = !i + 1 in
        let j = ref cstart in
        let closed = ref false in
        while !j < n && not !closed && text.[!j] <> '\n' do
          if text.[!j] = '\\' && !j + 1 < n && text.[!j + 1] <> '\n' then j := !j + 2
          else if text.[!j] = '"' then closed := true
          else incr j
        done;
        let cend = !j in
        let content = String.sub text cstart (cend - cstart) in
        if cur >= cstart && cur <= cend then begin
          let path, is_key, arr =
            if !expect_key then (keys () @ [ content ], true, false)
            else if in_array () then (keys (), false, true)
            else (keys () @ [ Option.value ~default:"" !cur_key ], false, false)
          in
          result := Str { section = !section; path; is_key; in_array = arr; content; cstart; cend };
          stop := true
        end else begin
          if !expect_key then (cur_key := Some content; expect_key := false);
          i := if !closed then cend + 1 else cend
        end
      | '=' -> line_start := false; incr i
      | '{' ->
        line_start := false;
        stack := { fkey = (if in_array () then None else !cur_key); is_array = false } :: !stack;
        expect_key := true;
        cur_key := None;
        incr i
      | '[' ->
        line_start := false;
        stack := { fkey = (if in_array () then None else !cur_key); is_array = true } :: !stack;
        expect_key := false;
        incr i
      | '}' | ']' ->
        line_start := false;
        (match !stack with _ :: rest -> stack := rest | [] -> ());
        expect_key := false;
        incr i
      | ',' ->
        line_start := false;
        (match !stack with
         | { is_array = false; _ } :: _ -> expect_key := true; cur_key := None
         | _ -> ());
        incr i
      | c when is_word c ->
        line_start := false;
        let j = ref !i in
        while !j < n && is_word text.[!j] do incr j done;
        if !expect_key then begin
          if cur >= !i && cur <= !j then begin
            result := Key { section = !section; path = keys (); kstart = !i;
                            prefix = String.sub text !i (cur - !i) };
            stop := true
          end else begin
            cur_key := Some (String.sub text !i (!j - !i));
            expect_key := false
          end
        end;
        i := !j
      | _ -> line_start := false; incr i
    end
  done;
  !result

(* ── What the strings name ──────────────────────────────────────────────── *)

type section_kind = Roles | Pool | Drain | Backend | Unknown

let section_kind s =
  if s = "roles" then Roles
  else if String.length s > 5 && String.sub s 0 5 = "pool." then Pool
  else if s = "drain" then Drain
  else if s = "backend" then Backend
  else Unknown

type target =
  | Fn_name
  | Actor_name
  | Role_name  (** "Protocol.Role" *)
  | Label
  | Nothing

(** What the string in [ctx] names. *)
let target_of = function
  | Str { section; path; is_key; in_array; _ } ->
    (match section_kind section, path, is_key, in_array with
     | Roles, [ _ ], true, _ -> Role_name
     | Roles, [ _; "body" ], false, _ -> Fn_name
     | Roles, [ _; "actor" ], false, _ -> Actor_name
     | Roles, [ _; "place"; "on" ], false, _ -> Label
     | Pool, [ "start" ], false, false -> Fn_name
     | Pool, ([ "serves" ] | [ "initiates" ]), false, true -> Role_name
     | Pool, [ "hosts"; "labels" ], false, true -> Label
     | _ -> Nothing)
  | _ -> Nothing

(** [Some (protocol, role)] for ["Protocol.Role"] (the role after the last
    dot, as forge splits it). *)
let split_role s =
  match String.rindex_opt s '.' with
  | Some i when i > 0 && i < String.length s - 1 ->
    Some (String.sub s 0 i, String.sub s (i + 1) (String.length s - i - 1))
  | _ -> None

(** The first place [role] is named in a protocol: its `role R needs` line,
    else the first message it sends or receives. *)
let role_site (def : Ast.protocol_def) (role : string) : Ast.span option =
  let needs =
    List.find_map (function
        | Ast.ProtoRoleNeeds (r, _, _) when r.Ast.txt = role -> Some r.Ast.span
        | _ -> None)
      def.Ast.proto_steps
  in
  let rec in_steps steps =
    List.find_map (function
        | Ast.ProtoMsg (s, r, _, _) ->
          if s.Ast.txt = role then Some s.Ast.span
          else if r.Ast.txt = role then Some r.Ast.span
          else None
        | Ast.ProtoLoop (inner, _) -> in_steps inner
        | Ast.ProtoChoice (by, branches) ->
          if by.Ast.txt = role then Some by.Ast.span
          else List.find_map (fun (_, steps) -> in_steps steps) branches
        | Ast.ProtoCrashOr (inner, crash, _) ->
          (match in_steps [ inner ] with Some sp -> Some sp | None -> in_steps crash)
        | _ -> None)
      steps
  in
  match needs with Some sp -> Some sp | None -> in_steps def.Ast.proto_steps

let location_of_span (sp : Ast.span) : Lsp.Types.Location.t =
  let range = Position.span_to_lsp_range sp in
  let range =
    let src =
      match Hashtbl.find_opt march_buffers sp.Ast.file with
      | Some s -> Some s
      | None -> read_file sp.Ast.file
    in
    match src with Some s -> Position.remap_range (Utf16.build s) range | None -> range
  in
  Lsp.Types.Location.create ~uri:(Lsp.Types.DocumentUri.of_path sp.Ast.file) ~range

(** Context at an LSP position of the document at [path]. *)
let ctx_at ~path ~line ~utf16_char =
  match text_of path with
  | None -> None
  | Some text ->
    let d = doc_of text in
    let off = offset_of_lsp d ~line ~utf16_char in
    Some (text, d, off, context_at text off)

(* ── Go-to-definition ───────────────────────────────────────────────────── *)

let definition_at ~path ~line ~utf16_char : Lsp.Types.Location.t option =
  match ctx_at ~path ~line ~utf16_char with
  | None -> None
  | Some (_, _, off, ctx) ->
    let idx = lazy (index ~root:(Filename.dirname path)) in
    (match ctx, target_of ctx with
     | Str { content; _ }, Fn_name ->
       Option.map location_of_span (T.site (Lazy.force idx) `Fn content)
     | Str { content; _ }, Actor_name ->
       Option.map location_of_span (T.site (Lazy.force idx) `Actor content)
     | Str { content; cstart; _ }, Role_name ->
       (match split_role content with
        | None -> None
        | Some (proto, role) ->
          let idx = Lazy.force idx in
          (match T.find_protocol idx proto with
           | None -> None
           | Some (q, _, def) ->
             (* On the protocol part: the declaration; on the role: the role. *)
             if off - cstart <= String.length proto then
               Option.map location_of_span (T.site idx `Protocol q)
             else
               (match role_site def role with
                | Some sp -> Some (location_of_span sp)
                | None -> Option.map location_of_span (T.site idx `Protocol q))))
     | _ -> None)

(* ── Hover ──────────────────────────────────────────────────────────────── *)

(** The type a role's body has, as the `@[endpoints]` runner front
    ([<P>_Run.run_<R>]) declares it (build step 4, D34): the session
    capability, one [Cap(P)] per grant path in declaration order, then the
    role's entry state, returning the role module's [Yield]. Spelled with
    the [Entry] alias, the name a body's signature uses. *)
let body_type ~proto ~role ~(grants : string list) =
  let m = proto ^ "_" ^ role in
  Printf.sprintf "(%s) -> %s.Yield"
    (String.concat ", "
       (("Cap(Session.Live)" :: List.map (fun p -> "Cap(" ^ p ^ ")") grants) @ [ m ^ ".Entry" ]))
    m

let role_hover idx (name : string) : string option =
  match split_role name with
  | None -> None
  | Some (proto, role) ->
    (match T.find_protocol idx proto with
     | None -> None
     | Some (q, short, def) ->
       if not (List.mem role (T.proto_roles def)) then None
       else begin
         let grants =
           List.assoc_opt role (March_desugar.Desugar_endpoints.grants_of def.Ast.proto_steps)
         in
         let grant =
           match grants with
           | Some paths ->
             Printf.sprintf "```march\nrole %s needs %s\n```" role (String.concat ", " paths)
           | None ->
             Printf.sprintf "No `role %s needs ...` grant in protocol `%s`." role short
         in
         let grants = Option.value ~default:[] grants in
         (* step 3: the generated main passes `fn (s, c1..ck, st) ->
            f(env, s, c1..ck, st)`, so a topology-bound body is the runner's
            body with the pool's environment in front. *)
         let bound_params =
           String.concat "" (List.mapi (fun i _ -> Printf.sprintf ", c%d" (i + 1)) grants)
         in
         Some (Printf.sprintf
                 "**`%s`**: role `%s` of protocol `%s`\n\n%s\n\n\
                  Body type (`%s_Run.run_%s`):\n\n```march\n%s\n```\n\n\
                  A `body` bound here takes the pool's environment first \
                  (the hook's return type, `()` without a hook): \
                  `f(env, s%s, st)`."
                 name role q grant short role
                 (body_type ~proto:short ~role ~grants) bound_params)
       end)

let hover_at ~path ~line ~utf16_char : Lsp.Types.Hover.t option =
  match ctx_at ~path ~line ~utf16_char with
  | None -> None
  | Some (_, d, _, ctx) ->
    (match ctx, target_of ctx with
     | Str { content; cstart; cend; _ }, Role_name ->
       (match role_hover (index ~root:(Filename.dirname path)) content with
        | None -> None
        | Some md ->
          Some (Lsp.Types.Hover.create
                  ~contents:(`MarkupContent (Lsp.Types.MarkupContent.create
                                               ~kind:Lsp.Types.MarkupKind.Markdown ~value:md))
                  ~range:(lsp_range d cstart cend) ()))
     | _ -> None)

(* ── Completion ─────────────────────────────────────────────────────────── *)

let sorted_keys h = Hashtbl.fold (fun k () acc -> k :: acc) h [] |> List.sort String.compare

let role_names idx =
  List.concat_map (fun (_, short, def) -> List.map (fun r -> short ^ "." ^ r) (T.proto_roles def))
    idx.T.protocols
  |> List.sort_uniq String.compare

(** The topology files of [root] that parse: the base and every overlay. *)
let toml_docs root : Toml.document list =
  let base = Filename.concat root "topology.toml" in
  List.filter_map (fun p ->
      match text_of p with
      | None -> None
      | Some t -> (match Toml.parse_located t with Ok d -> Some d | Error _ -> None))
    (base :: List.map (fun e -> T.overlay_file ~root e) (overlay_envs root))

let pool_names root =
  List.concat_map (fun (doc : Toml.document) ->
      List.filter_map (fun (ls : Toml.located_section) ->
          let s = ls.Toml.sec_name in
          if section_kind s = Pool then Some (String.sub s 5 (String.length s - 5)) else None)
        doc.Toml.located)
    (toml_docs root)
  |> List.sort_uniq String.compare

let labels root =
  List.concat_map (fun (doc : Toml.document) ->
      List.concat_map (fun (ls : Toml.located_section) ->
          match Toml.find_at ls "hosts" with
          | Some (Toml.Array items, _) ->
            List.concat_map (function
                | Toml.InlineTable t -> Toml.get_string_list t "labels"
                | _ -> [])
              items
          | _ -> [])
        doc.Toml.located)
    (toml_docs root)
  |> List.sort_uniq String.compare

let keys_for section (path : string list) : string list =
  match section_kind section, path with
  | Roles, [ _ ] -> T.known_role_keys
  | Roles, [ _; "place" ] -> T.known_place_keys
  | Pool, [] -> T.known_pool_keys
  | Pool, [ "hosts" ] -> T.known_host_keys
  | Drain, [] -> T.known_drain_keys
  | Backend, [] -> T.known_backend_keys
  | _ -> []

let item (d : Utf16.doc) ~a ~b ~kind ?detail ~sort ~label ~insert () =
  Lsp.Types.CompletionItem.create ~label ~kind ?detail
    ~sortText:(Printf.sprintf "%04d" sort) ~filterText:label
    ~textEdit:(`TextEdit (Lsp.Types.TextEdit.create ~range:(lsp_range d a b) ~newText:insert))
    ()

let completions_at ~path ~line ~utf16_char : Lsp.Types.CompletionItem.t list =
  match ctx_at ~path ~line ~utf16_char with
  | None -> []
  | Some (_, d, off, ctx) ->
    let root = Filename.dirname path in
    let idx = lazy (index ~root) in
    let many ~a ~b ~kind ?detail ?(quote = false) names =
      List.mapi (fun i nm ->
          item d ~a ~b ~kind ?detail ~sort:i ~label:nm
            ~insert:(if quote then "\"" ^ nm ^ "\"" else nm) ())
        names
    in
    let open Lsp.Types.CompletionItemKind in
    (match ctx with
     | Str { section; path = kpath; is_key; cstart; cend; _ } ->
       let a = cstart and b = max off cend in
       (match target_of ctx with
        | Fn_name -> many ~a ~b ~kind:Function ~detail:"fn" (sorted_keys (Lazy.force idx).T.fns)
        | Actor_name -> many ~a ~b ~kind:Class ~detail:"actor" (sorted_keys (Lazy.force idx).T.actors)
        | Role_name -> many ~a ~b ~kind:EnumMember ~detail:"Protocol.Role" (role_names (Lazy.force idx))
        | Label -> many ~a ~b ~kind:Value ~detail:"host label" (labels root)
        | Nothing ->
          if is_key then
            let parent = List.filteri (fun i _ -> i < List.length kpath - 1) kpath in
            many ~a ~b ~kind:Property ~detail:section (keys_for section parent)
          else [])
     | Key { section; path = kpath; kstart; _ } ->
       let a = kstart and b = off in
       (match section_kind section, kpath with
        | Roles, [] ->
          many ~a ~b ~kind:EnumMember ~detail:"Protocol.Role" ~quote:true (role_names (Lazy.force idx))
        | _ -> many ~a ~b ~kind:Property ~detail:("[" ^ section ^ "]") (keys_for section kpath))
     | Header { hstart; _ } ->
       let pools = List.map (fun p -> "pool." ^ p) (pool_names root) in
       let names = pools @ List.filter (fun s -> not (List.mem s pools)) [ "roles"; "drain"; "backend"; "pool." ] in
       many ~a:hstart ~b:off ~kind:Module ~detail:"section" names
     | Other -> [])
