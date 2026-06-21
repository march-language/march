(* Parses Z3's `(get-model)` output into a (symbol -> value-string) assoc list,
   for rendering counterexamples.  Pure; no solver dependency.

   Handles both shapes Z3 emits:
     ( (define-fun d () Int 0) ... )        -- SMT-LIB 2.6 default
     (model (define-fun d () Int 0) ... )   -- legacy / :model-style
   by recursively collecting every (define-fun NAME () SORT VALUE) form. *)

type sexp = Atom of string | List of sexp list

let parse_sexps (s : string) : sexp list =
  let n = String.length s in
  let pos = ref 0 in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let is_delim c = c = '(' || c = ')' || is_ws c in
  let skip_ws () = while !pos < n && is_ws s.[!pos] do incr pos done in
  let rec parse_one () : sexp =
    skip_ws ();
    if !pos >= n then failwith "model: unexpected eof"
    else if s.[!pos] = '(' then begin
      incr pos;
      let items = ref [] in
      let rec loop () =
        skip_ws ();
        if !pos < n && s.[!pos] = ')' then incr pos
        else begin
          items := parse_one () :: !items;
          loop ()
        end
      in
      loop ();
      List (List.rev !items)
    end
    else begin
      let start = !pos in
      while !pos < n && not (is_delim s.[!pos]) do incr pos done;
      Atom (String.sub s start (!pos - start))
    end
  in
  let items = ref [] in
  (try
     while true do
       skip_ws ();
       if !pos >= n then raise Exit;
       items := parse_one () :: !items
     done
   with Exit -> ());
  List.rev !items

let rec render_sexp = function
  | Atom a -> a
  | List xs -> "(" ^ String.concat " " (List.map render_sexp xs) ^ ")"

let of_string (s : string) : (string * string) list =
  let defs = ref [] in
  let rec collect = function
    | List [ Atom "define-fun"; Atom name; List []; _sort; value ] ->
        defs := (name, render_sexp value) :: !defs
    | List xs -> List.iter collect xs
    | Atom _ -> ()
  in
  List.iter collect (parse_sexps s);
  List.rev !defs
