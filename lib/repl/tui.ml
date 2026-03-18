open Notty
open Notty.A

type t = {
  term    : Notty_unix.Term.t;
  mutable w : int;
  mutable h : int;
}

type scope_entry = {
  name     : string;
  type_str : string;
  val_str  : string;
}

type pane_content = {
  history       : I.t list;
  input_line    : I.t;
  prompt        : string;
  scope         : scope_entry list;
  result_latest : (string * string) option;
  status        : string;
}

let create () =
  let term = Notty_unix.Term.create () in
  let (w, h) = Notty_unix.Term.size term in
  { term; w; h }

let close tui = Notty_unix.Term.release tui.term

let size tui = (tui.w, tui.h)

(** Crop or pad an image to exactly [w] columns wide. *)
let fit_width w img =
  let iw = I.width img in
  if iw > w then I.hcrop 0 (iw - w) img
  else if iw < w then I.(img <|> char A.empty ' ' (w - iw) 1)
  else img

let render tui content =
  let w = tui.w and h = tui.h in
  let status_h  = 1 in
  let pane_h    = max 1 (h - status_h) in
  let right_w   = w / 3 in
  let sep_w     = 1 in
  let left_w    = max 1 (w - right_w - sep_w) in

  (* Build right pane *)
  let right_header = fit_width right_w (I.string (st bold) "Variables in Scope") in
  let right_sep    = I.string A.empty (String.make right_w '-') in
  let v_rows = match content.result_latest with
    | None -> []
    | Some (ty, vs) ->
      [fit_width right_w (I.string (fg green) (Printf.sprintf "v : %s = %s" ty vs))]
  in
  let scope_rows = List.map (fun e ->
    let s = Printf.sprintf "%s : %s = %s" e.name e.type_str e.val_str in
    fit_width right_w (I.string A.empty s)
  ) content.scope in
  let right_rows = [right_header; right_sep] @ v_rows @ scope_rows in
  let right_visible =
    if List.length right_rows <= pane_h then right_rows
    else List.filteri (fun i _ -> i < pane_h) right_rows
  in
  let right_fill = max 0 (pane_h - List.length right_visible) in
  let right_pane =
    I.vcat (right_visible @ [I.char A.empty ' ' right_w right_fill])
  in

  (* Build left pane *)
  let prompt_img  = I.string (st bold ++ fg blue) content.prompt in
  let input_row   = I.(prompt_img <|> content.input_line) in
  let all_rows    = content.history @ [input_row] in
  let all_rows_n  = List.length all_rows in
  let left_visible =
    if all_rows_n <= pane_h then all_rows
    else List.filteri (fun i _ -> i >= all_rows_n - pane_h) all_rows
  in
  let left_rows_fitted = List.map (fit_width left_w) left_visible in
  let left_fill = max 0 (pane_h - List.length left_rows_fitted) in
  let left_pane =
    I.vcat (left_rows_fitted @ [I.char A.empty ' ' left_w left_fill])
  in

  (* Separator column *)
  let sep_col = I.char A.empty '|' sep_w pane_h in

  (* Compose panes + status *)
  let panes      = I.hcat [left_pane; sep_col; right_pane] in
  let status_img = fit_width w (I.string A.empty (" " ^ content.status)) in
  let screen     = I.(panes <-> status_img) in
  Notty_unix.Term.image tui.term screen

let rec next_event tui =
  match Notty_unix.Term.event tui.term with
  | `Key key         -> `Key key
  | `Resize (w, h)   -> tui.w <- w; tui.h <- h; `Resize (w, h)
  | `Mouse _         -> next_event tui
  | `Paste _         -> next_event tui
  | `End             -> `End
