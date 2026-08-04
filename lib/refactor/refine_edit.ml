(** Splice a refinement annotation onto a function parameter.

    Shared by [forge refine --apply] and the LSP's `march.suggestRefinement`
    command, which must produce byte-identical edits: a user who accepts the
    editor's quick-fix and a user who runs the CLI are applying the same
    suggestion, and two implementations of "find the annotation" would diverge
    on exactly the parameter lists nobody tested.

    The edit is textual rather than a re-print of the AST for two reasons: a
    [ty] carries no span of its own, so there is nothing to overwrite
    precisely; and re-printing the signature would reformat code the user did
    not ask to have reformatted.  The scanner tracks bracket depth so a type
    such as [Map(String, Int)] is not split at its inner comma.

    Every failure returns [None].  A wrong splice here silently changes a
    contract — the caller is expected to fall back to telling the user to edit
    by hand, and to re-parse the result before writing it. *)

let is_word c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  || c = '_' || c = '\''

(** [byte_range_of_param ~src ~line ~fn ~param] locates [param]'s type
    annotation inside [fn]'s parameter list, searching from 1-based [line].
    Returns the half-open byte range of the annotation TEXT (everything after
    the colon, up to but excluding the separating `,` or the closing `)`).

    The range excludes the colon, so replacing it never disturbs the parameter
    name or the separator. *)
let byte_range_of_param ~(src : string) ~(line : int) ~(fn : string)
    ~(param : string) : (int * int) option =
  let n = String.length src in
  let rec line_start i cur =
    if cur >= line || i >= n then i
    else line_start (i + 1) (if src.[i] = '\n' then cur + 1 else cur)
  in
  let start = line_start 0 1 in
  let flen = String.length fn in
  let rec find_fn i =
    if i + flen > n then None
    else if
      String.sub src i flen = fn
      && (i = 0 || not (is_word src.[i - 1]))
      && (i + flen >= n || not (is_word src.[i + flen]))
    then Some i
    else find_fn (i + 1)
  in
  match find_fn start with
  | None -> None
  | Some fn_ofs ->
    let rec find_lparen i =
      if i >= n then None
      else
        match src.[i] with
        | '(' -> Some i
        | ' ' | '\t' -> find_lparen (i + 1)
        | _ -> None
    in
    (match find_lparen (fn_ofs + flen) with
     | None -> None
     | Some lp ->
       let plen = String.length param in
       (* Walk the parameter list at depth 1, splitting on top-level commas. *)
       let rec scan i depth seg_start =
         if i >= n then None
         else
           let close seg_end k =
             let seg = String.sub src seg_start (seg_end - seg_start) in
             let trimmed = String.trim seg in
             let name_ok =
               String.length trimmed >= plen
               && String.sub trimmed 0 plen = param
               && (String.length trimmed = plen || not (is_word trimmed.[plen]))
             in
             (* An UNANNOTATED parameter has no base type to put on the left of
                the bar, so it is not spliceable — not a failure, just not this
                parameter. *)
             match String.index_opt seg ':' with
             | Some ci when name_ok -> Some (seg_start + ci + 1, seg_end)
             | _ -> k ()
           in
           match src.[i] with
           | '(' | '[' | '{' -> scan (i + 1) (depth + 1) seg_start
           | ')' when depth = 1 -> close i (fun () -> None)
           | ')' | ']' | '}' -> scan (i + 1) (depth - 1) seg_start
           | ',' when depth = 1 -> close i (fun () -> scan (i + 1) depth (i + 1))
           | _ -> scan (i + 1) depth seg_start
       in
       scan (lp + 1) 1 (lp + 1))

(** Replace [param]'s annotation with [annotation] (e.g. ["{Int | _ > 0}"]),
    returning the whole new source. *)
let splice ~(src : string) ~(line : int) ~(fn : string) ~(param : string)
    ~(annotation : string) : string option =
  match byte_range_of_param ~src ~line ~fn ~param with
  | None -> None
  | Some (a, b) ->
    Some
      (String.sub src 0 a ^ " " ^ annotation
       ^ String.sub src b (String.length src - b))

(** [byte_range_of_return ~src ~line ~fn] locates [fn]'s RETURN type annotation,
    searching from 1-based [line].  Returns the half-open byte range of the
    annotation text — everything after the `:` that follows the parameter list,
    up to but excluding the `do` that opens the body.

    Separate from [byte_range_of_param] because it is a different scan, not a
    variation of one: the parameter version splits a comma-separated list inside
    brackets, while this must first find the paren that CLOSES the parameter
    list (tracking depth, so `Map(String, Int)` does not end it early) and then
    stop at a `do` keyword rather than a separator.

    [None] when the function declares no return type (`fn f(x) do …`), which is
    not a failure — there is simply nothing to annotate. *)
let byte_range_of_return ~(src : string) ~(line : int) ~(fn : string) :
    (int * int) option =
  let n = String.length src in
  let rec line_start i cur =
    if cur >= line || i >= n then i
    else line_start (i + 1) (if src.[i] = '\n' then cur + 1 else cur)
  in
  let start = line_start 0 1 in
  let flen = String.length fn in
  let rec find_fn i =
    if i + flen > n then None
    else if
      String.sub src i flen = fn
      && (i = 0 || not (is_word src.[i - 1]))
      && (i + flen >= n || not (is_word src.[i + flen]))
    then Some i
    else find_fn (i + 1)
  in
  match find_fn start with
  | None -> None
  | Some fn_ofs ->
    let rec find_lparen i =
      if i >= n then None
      else
        match src.[i] with
        | '(' -> Some i
        | ' ' | '\t' -> find_lparen (i + 1)
        | _ -> None
    in
    (match find_lparen (fn_ofs + flen) with
     | None -> None
     | Some lp ->
       (* Closing paren of the PARAMETER LIST, tracking depth so a parenthesised
          parameter type does not terminate the scan early. *)
       let rec close i depth =
         if i >= n then None
         else
           match src.[i] with
           | '(' | '[' | '{' -> close (i + 1) (depth + 1)
           | ')' when depth = 1 -> Some i
           | ')' | ']' | '}' -> close (i + 1) (depth - 1)
           | _ -> close (i + 1) depth
       in
       (match close (lp + 1) 1 with
        | None -> None
        | Some rp ->
          (* `: <ty> do`.  Anything else between the parameter list and the body
             (including no annotation at all) yields None rather than a guess. *)
          let rec skip_ws i = if i < n && (src.[i] = ' ' || src.[i] = '\t') then skip_ws (i + 1) else i in
          let i = skip_ws (rp + 1) in
          if i >= n || src.[i] <> ':' then None
          else
            let ty_start = i + 1 in
            let rec find_do j depth =
              if j + 2 > n then None
              else
                match src.[j] with
                | '(' | '[' | '{' -> find_do (j + 1) (depth + 1)
                | ')' | ']' | '}' -> find_do (j + 1) (depth - 1)
                | 'd' when depth = 0
                           && j + 2 <= n && String.sub src j 2 = "do"
                           && (j = 0 || not (is_word src.[j - 1]))
                           && (j + 2 >= n || not (is_word src.[j + 2])) -> Some j
                | '\n' -> None   (* the body opener must be on the signature line *)
                | _ -> find_do (j + 1) depth
            in
            (match find_do ty_start 0 with
             | None -> None
             | Some do_ofs -> Some (ty_start, do_ofs))))

(** Replace [fn]'s return annotation with [annotation]. *)
let splice_return ~(src : string) ~(line : int) ~(fn : string)
    ~(annotation : string) : string option =
  match byte_range_of_return ~src ~line ~fn with
  | None -> None
  | Some (a, b) ->
    Some
      (String.sub src 0 a ^ " " ^ annotation ^ " "
       ^ String.sub src b (String.length src - b))

(** 0-based (line, column) of a byte offset — what an LSP [Position] needs. *)
let position_of_offset (src : string) (ofs : int) : int * int =
  let line = ref 0 and col = ref 0 in
  (try
     String.iteri
       (fun i c ->
         if i >= ofs then raise Exit;
         if c = '\n' then begin incr line; col := 0 end else incr col)
       src
   with Exit -> ());
  (!line, !col)
