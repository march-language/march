(** A lemma's parts as written in its source text: the parameter list and
    the theorem [P] of `fn name(params) : {Unit | P}`, and the functions [P]
    calls.  Text-level, so a tool reports a law exactly as its author wrote
    it ([Lemma_test]'s compiled harness, `forge search`). *)

(* The byte offset of a span position (1-based lines, 0-based columns). *)
let offset (text : string) ~line ~col : int option =
  let rec go i l =
    if l >= line then Some (i + col)
    else match String.index_from_opt text i '\n' with Some j -> go (j + 1) (l + 1) | None -> None
  in
  go 0 1

(* The text between [open_] at [i] and its matching [close], and the offset
   after [close]. *)
let balanced (text : string) (i : int) ~(open_ : char) ~(close : char) : (string * int) option =
  if i >= String.length text || text.[i] <> open_ then None
  else
    let rec go j depth =
      if j >= String.length text then None
      else
        let c = text.[j] in
        if c = open_ then go (j + 1) (depth + 1)
        else if c = close then
          if depth = 1 then Some (String.sub text (i + 1) (j - i - 1), j + 1) else go (j + 1) (depth - 1)
        else go (j + 1) depth
    in
    go i 0

let rec skip_ws text i =
  if i < String.length text && (text.[i] = ' ' || text.[i] = '\n' || text.[i] = '\t' || text.[i] = '\r') then
    skip_ws text (i + 1)
  else i

(** [Some (params, theorem)] for `fn name(params) : {Unit | theorem}` in
    [text], the source of the file that declares [fd]; [None] for any other
    shape. *)
let parts (text : string) (fd : Ast.fn_def) : (string * string) option =
  let sp = fd.Ast.fn_name.Ast.span in
  match offset text ~line:sp.Ast.end_line ~col:sp.Ast.end_col with
  | None -> None
  | Some i -> (
    match balanced text (skip_ws text i) ~open_:'(' ~close:')' with
    | None -> None
    | Some (params, j) ->
      let j = skip_ws text j in
      if j >= String.length text || text.[j] <> ':' then None
      else (
        match balanced text (skip_ws text (j + 1)) ~open_:'{' ~close:'}' with
        | None -> None
        | Some (ret, _) ->
          let n = String.length ret in
          (* The first `|` that is not part of `||`. *)
          let rec bar k =
            if k >= n then None
            else if ret.[k] = '|' && (k + 1 >= n || ret.[k + 1] <> '|') && (k = 0 || ret.[k - 1] <> '|') then Some k
            else bar (k + 1)
          in
          Option.map (fun k -> (String.trim params, String.trim (String.sub ret (k + 1) (n - k - 1)))) (bar 0)))

(** The functions [theorem] calls, in order of first call: each `name(` (or
    `Mod.name(`) whose last segment starts with a lowercase letter. *)
let calls (theorem : string) : string list =
  let n = String.length theorem in
  let ident c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c = '.' in
  let rec go i acc =
    if i >= n then List.rev acc
    else if ident theorem.[i] && (i = 0 || not (ident theorem.[i - 1])) then begin
      let j = ref i in
      while !j < n && ident theorem.[!j] do incr j done;
      let word = String.sub theorem i (!j - i) in
      let last = match String.rindex_opt word '.' with Some k -> String.sub word (k + 1) (String.length word - k - 1) | None -> word in
      let acc =
        if !j < n && theorem.[!j] = '(' && last <> "" && last.[0] >= 'a' && last.[0] <= 'z' && not (List.mem word acc)
        then word :: acc
        else acc
      in
      go !j acc
    end
    else go (i + 1) acc
  in
  go 0 []
