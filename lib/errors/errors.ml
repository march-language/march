exception ParseError of string * string option * Lexing.position
(** ParseError (message, hint, position) *)

(** March error reporting.

    Errors carry provenance (source spans) and are designed
    to produce clear, non-cascading diagnostics with
    expected-vs-found framing. *)

module Code = Code

type severity = Error | Warning | Hint

type fix_kind =
  | FInsert of { after_line : int; text : string }
  (** Insert [text] as a new line immediately after line [after_line] (1-indexed).
      [text] must NOT include a trailing newline; the applier adds one. *)
  | FDelete of { start_line : int; end_line : int }
  (** Delete full source lines [start_line]..[end_line] inclusive (1-indexed). *)
  | FReplace of { span : March_ast.Ast.span; text : string }
  (** Replace the text covered by [span] with [text] in-place. *)
  | FMulti of fix_kind list
  (** Several edits that make ONE fix (one root cause, one report:
      specs/plans/2026-11-02-diagnostics-depth-plan.md §X3 / §F1), e.g. the
      `needs` line and the grant edit for a missing authority.  Every edit's
      positions are relative to the ORIGINAL source, as for separate fixes;
      an applier sorts them bottom-up by (line, column).  Flat: build one
      with {!multi_fix}, which never nests. *)

type diagnostic = {
  severity : severity;
  span : March_ast.Ast.span;
  message : string;
  labels : label list;     (** Additional labeled source spans *)
  notes : string list;      (** Extra context / suggestions *)
  code : string;           (** Machine-readable code from {!Code}, e.g. [Code.unused_binding].
                               Required: every diagnostic has one. *)
  fix : fix_kind option;   (** Mechanically-determined fix, if one exists *)
}

and label = {
  lbl_span : March_ast.Ast.span;
  lbl_message : string;
}

(** A positioned rejection raised from a pass that has no diagnostic
    accumulator to report into (lowering, for one).  The driver catches it
    once and prints it with the standard renderer, so it gets the same
    header, caret, code and explain pointer as every other diagnostic;
    nothing prints a raw `file:line:col: error: …` line (plan §X5). *)
exception Diagnostic_exn of diagnostic

(** A diagnostic record with no labels, notes or fix. *)
let make ?(severity = Error) ?(notes = []) ~code ~span message =
  { severity; span; message; labels = []; notes; code; fix = None }

(** Hint exclusivity (specs/plans/2026-11-02-diagnostics-depth-plan.md §X4):
    a diagnostic gives at most one "likely cause".  [first_cause groups] is
    the first non-empty group, so a caller lists its candidate explanations
    most specific first and the rest are dropped, never stacked:
    [first_cause [ occurs_note; session_hint; generic_hint ]]. *)
let first_cause (groups : string list list) : string list =
  match List.find_opt (fun g -> g <> []) groups with
  | Some g -> g
  | None -> []

(** One line, [file:line:col: error: message [slug]], for the generic
    catch-alls that only have [Printexc.to_string] (the REPL, a test). *)
let () =
  Printexc.register_printer (function
    | Diagnostic_exn d ->
      Some (Printf.sprintf "%s:%d:%d: %s: %s [%s]" d.span.March_ast.Ast.file
              d.span.March_ast.Ast.start_line d.span.March_ast.Ast.start_col
              (match d.severity with Error -> "error" | Warning -> "warning" | Hint -> "hint")
              d.message (Code.slug_of d.code))
    | _ -> None)

(** Accumulator for diagnostics — allows error recovery. *)
type ctx = { mutable diagnostics : diagnostic list }

(** What a grammar `error` production knows beyond [ParseError]'s
    (message, hint, position): its own code and a mechanical fix (D4,
    specs/plans/diagnostics-and-triage-plan.md §8). [ParseError] is matched
    as a 3-tuple at ~40 sites, so the extra fields ride a side channel:
    the grammar's [error_raise] sets this right before raising, every
    time (to [None, None] when it has nothing to add), and [Parse.run]
    reads and clears it when it catches the exception. A direct [raise
    ParseError] that bypasses [error_raise] would leave a stale value, so
    parser.mly has none. *)
let parse_error_extra : (string option * fix_kind option) ref = ref (None, None)

let take_parse_error_extra () =
  let v = !parse_error_extra in
  parse_error_extra := (None, None);
  v

let create () = { diagnostics = [] }

(** The edits of a fix, flattened. *)
let rec fix_edits = function
  | FMulti fs -> List.concat_map fix_edits fs
  | f -> [ f ]

(** One fix made of every edit in [fixes] (flattened, exact duplicates
    dropped); [None] when there are none, the edit itself when only one. *)
let multi_fix (fixes : fix_kind option list) : fix_kind option =
  let edits =
    List.fold_left (fun acc f -> if List.mem f acc then acc else acc @ [ f ]) []
      (List.concat_map (function None -> [] | Some f -> fix_edits f) fixes) in
  match edits with
  | [] -> None
  | [ f ] -> Some f
  | fs -> Some (FMulti fs)

(* Some diagnostics get re-derived at every use of a declaration whose own
   definition is broken (e.g. instantiating a constructor re-resolves its
   stored surface argument types on each use, needed for fresh per-use type
   variables) — a name that fails to resolve there gets reported once per
   instantiation instead of once.  A diagnostic identical in severity, span,
   AND message can only be the same fact re-derived, never two independent
   issues that coincide byte-for-byte at the same source location, so
   suppress an exact repeat rather than showing the user the same error
   three times. *)
let report ctx diag =
  let is_dup (d : diagnostic) =
    d.severity = diag.severity && d.span = diag.span && d.message = diag.message
  in
  if not (List.exists is_dup ctx.diagnostics) then
    ctx.diagnostics <- diag :: ctx.diagnostics

let error ctx ~code ~span message =
  report ctx
    { severity = Error; span; message; labels = []; notes = []; code; fix = None }

let warning ctx ~code ~span message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code; fix = None }

let hint ctx ~code ~span message =
  report ctx
    { severity = Hint; span; message; labels = []; notes = []; code; fix = None }

(* Kept as an alias of [warning] now that every helper takes [~code]. *)
let warning_with_code = warning

let error_with_fix ctx ~code ~span ~fix message =
  report ctx
    { severity = Error; span; message; labels = []; notes = []; code; fix = Some fix }

let warning_with_fix ctx ~code ~span ~fix message =
  report ctx
    { severity = Warning; span; message; labels = []; notes = []; code; fix = Some fix }

let warning_with_code_and_fix = warning_with_fix

let use_color : bool ref = ref false

let ansi_reset        = "\027[0m"
let ansi_bold         = "\027[1m"
let ansi_dim          = "\027[2m"
let ansi_cyan         = "\027[36m"
let ansi_magenta      = "\027[35m"
let ansi_bold_magenta = "\027[1;35m"

let sev_bold_code  = function Error -> "\027[1;31m" | Warning -> "\027[1;33m" | Hint -> "\027[1;34m"
let sev_plain_code = function Error -> "\027[31m"   | Warning -> "\027[33m"   | Hint -> "\027[34m"

(** Wrap [s] in an ANSI [code]…reset pair when colour is on. *)
let paint code s =
  if !use_color then code ^ s ^ ansi_reset else s

(** Colour backtick-quoted spans within [s].
    Each matched `` `…` `` is wrapped in [inner_code]; [parent_code] is
    restored afterwards so surrounding styling is not lost. *)
let colorize_backticks ~parent_code ~inner_code s =
  if not !use_color then s
  else begin
    let parts = String.split_on_char '`' s in
    let n = List.length parts in
    List.mapi (fun i part ->
      if i mod 2 = 1 && i + 1 < n then
        inner_code ^ "`" ^ part ^ "`" ^ ansi_reset ^ parent_code
      else part
    ) parts |> String.concat ""
  end

(** Bold primary message with bold-magenta backtick terms. *)
let fmt_message s =
  paint ansi_bold
    (colorize_backticks ~parent_code:ansi_bold ~inner_code:ansi_bold_magenta s)

(** Dim note with plain-magenta backtick terms. *)
let fmt_note s =
  paint ansi_dim
    (colorize_backticks ~parent_code:ansi_dim ~inner_code:ansi_magenta s)

(* ─────────────────────────────────────────────────────────────────────── *)

let has_errors ctx =
  List.exists (fun d -> d.severity = Error) ctx.diagnostics

let has_diagnostics ctx = ctx.diagnostics <> []

(** A mark for [error_since]: the diagnostics reported so far. *)
let mark ctx = ctx.diagnostics

(** Whether an error was reported after [mark] was taken.  [report] only
    prepends, so the diagnostics since the mark are the prefix of the list
    ending at the (physically) marked list. *)
let error_since ctx mark =
  let rec go = function
    | l when l == mark -> false
    | [] -> false
    | d :: rest -> d.severity = Error || go rest
  in
  go ctx.diagnostics

let has_hints ctx =
  List.exists (fun d -> d.severity = Hint) ctx.diagnostics

let sorted ctx =
  (* [stable_sort] plus a total tiebreaker so diagnostics that SHARE a span
     (e.g. a Cap-narrowing HINT emitted at the same span as another
     diagnostic) render in a deterministic order run-to-run. Without a
     deterministic tiebreaker a non-stable sort could reorder equal-span
     diagnostics, producing display nondeterminism. *)
  let sev_rank = function Error -> 0 | Warning -> 1 | Hint -> 2 in
  (* A [cap_grant] beside another error renders last: the other error is
     the mistake to fix first, and the grant is what is left after it, so
     the reader meets them in that order (one-turn metric, §M1). *)
  let is_grant d = Code.slug_of d.code = Code.cap_grant in
  let other_error =
    List.exists (fun d -> d.severity = Error && not (is_grant d)) ctx.diagnostics in
  let late d = if other_error && is_grant d then 1 else 0 in
  List.stable_sort
    (fun a b ->
      let c = compare (late a) (late b) in
      if c <> 0 then c else
      let c = compare a.span.start_line b.span.start_line in
      if c <> 0 then c
      else
        let c = compare a.span.start_col b.span.start_col in
        if c <> 0 then c
        else
          let c = compare (sev_rank a.severity) (sev_rank b.severity) in
          if c <> 0 then c
          else
            (* Two reports starting at the same place: the narrower one
               first.  In `x ++ "no"`, the operand `x` is the cause, and the
               whole expression's mismatch reads as its consequence (§X1). *)
            let c = compare (a.span.end_line, a.span.end_col)
                (b.span.end_line, b.span.end_col) in
            if c <> 0 then c else compare a.message b.message)
    ctx.diagnostics

(* ── Cascade suppression ──────────────────────────────────────────────

   One root cause, one report (specs/plans/2026-11-02-diagnostics-depth-plan.md
   §X3).  Each rule drops a diagnostic that only restates, or follows from,
   another one in the same set:

   - a [type_mismatch] on the exact span of a [callback_arity_mismatch]: the
     arity error already says what is wrong with that argument;
   - an [unused_binding] for `x` when an [unbound_variable] error suggests
     `x`: the binder is unused because its use is misspelled;
   - an [unused_binding] for `x` when [linear_never_used] reports `x`: the
     linearity error says the same thing, and its `_x` fix does not satisfy
     linearity;
   - an [unbound_variable] for `y` on the arm of an [or_pattern_binding]
     error naming `y`: the name is unbound because only some alternatives
     bind it;
   - [cap_root_broad] while any error outside the capability checks exists:
     it is advice on a program that does not typecheck yet. [cap_grant] is
     kept (and sorted after the other errors): hiding it cost a second turn
     on every program that also forgot the grant (one-turn metric, §M1);
   - a [cap_ceiling:X] when a [cap_needs:X] error reports the same missing
     `needs` (it points at the use, the ceiling at the module header, and
     the two carry the same fix), or when [import_cap_missing] reports the
     same `X` for an import;
   - an exact duplicate (same code, span and message), and a second
     [type_mismatch] on the very span of an earlier one;
   - a [session_state_mismatch] "expected a channel endpoint but got `a`"
     while another session error exists: the channel's type was lost by the
     earlier error, not by this call;
   - a [mint_cap_invalid] inside the span of a [proof_cap_mint_private] /
     [proof_cap_return]: the specific rule already reports that mint;
   - while a protocol definition is invalid ([role_needs_invalid],
     [protocol_invalid], [endpoints_label_invalid]), the type, step-order,
     constructor, linearity and session errors: the generated role modules everything
     else is checked against are built from the invalid protocol, so those
     errors are its consequences (fix the protocol first);
   - an error with no source position (line 0) beside a positioned one;
   - an [overlapping_impl] for `impl I(T)` when [json_derive_name_collision]
     reports `T`: the two codecs overlap because the two types share a name,
     which that error already says (with both sites);
   - an [ambiguous_constructor] hint inside a [send_wrong_actor] error: that
     error already says which actor the bare message resolves to;
   - any advisory HINT on the exact span of an error (§X4): the error is what
     to fix there, and an advisory stacked on it can contradict its fix (a
     `cap_root_broad` "narrow `Cap(IO)`" under a `cap_needs` "add `needs IO`");
   - a [refinement_unverified] hint on the span of a [lemma_unproved_call]
     warning, which already says the precondition is not proved there; the
     warning takes over the precondition and the reason as one note.

   Last, within each diagnostic that stays, a note that repeats an earlier
   note or a line of the message is dropped (§X4: one hint, said once). *)
let slug_of_code = Code.slug_of

let first_backticked s =
  match String.index_opt s '`' with
  | None -> None
  | Some a ->
    (match String.index_from_opt s (a + 1) '`' with
     | Some b -> Some (String.sub s (a + 1) (b - a - 1))
     | None -> None)

let contains_sub hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

(* A note that repeats an earlier note, or a line of the message, says the
   same thing twice: drop it (whitespace-insensitive). *)
let tidy_notes (d : diagnostic) : diagnostic =
  let norm s =
    String.split_on_char '\n' s |> List.map String.trim
    |> List.filter (( <> ) "") |> String.concat " " in
  let msg_lines = List.map String.trim (String.split_on_char '\n' d.message) in
  let rec go seen = function
    | [] -> []
    | n :: rest ->
      let k = norm n in
      if k = "" || List.mem k seen || List.mem k msg_lines then go seen rest
      else n :: go (k :: seen) rest in
  { d with notes = go [] d.notes }

let suppress_cascades ?(visible = fun (_ : diagnostic) -> true)
    (ds : diagnostic list) : diagnostic list =
  (* Only a diagnostic the user is shown may suppress another: the driver
     hides errors in stdlib files, and a hidden error suppressing the only
     visible one would turn a rejected program into an accepted one. *)
  let is_err d = d.severity = Error && visible d in
  let has_slug sl d = slug_of_code d.code = sl in
  (* The capability checks' codes: every code naming `cap` (`cap_needs`,
     `import_cap_missing`, `root_cap_reference`, …) except
     `linear_captured`, plus the grant and `needs` codes that don't. *)
  let capability_slug sl =
    (contains_sub sl "cap" && not (contains_sub sl "captured"))
    || contains_sub sl "role_grant"
    || List.mem sl [ Code.extern_needs_foreign; Code.io_not_allowed; Code.unused_needs ] in
  let non_cap_error =
    List.exists (fun d -> is_err d && not (capability_slug (slug_of_code d.code))) ds in
  let arity_spans =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.callback_arity_mismatch d then Some d.span else None) ds in
  let unbound_msgs =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.unbound_variable d then Some d.message else None) ds in
  let or_pattern_msgs =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.or_pattern_binding d then Some d else None) ds in
  let never_used =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.linear_never_used d then first_backticked d.message
        else None) ds in
  let import_missing_msgs =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.import_cap_missing d then Some d.message else None) ds in
  let proof_cap_spans =
    List.filter_map (fun d ->
        if is_err d && (has_slug Code.proof_cap_mint_private d || has_slug Code.proof_cap_return d)
        then Some d.span else None) ds in
  let protocol_invalid =
    List.exists (fun d ->
        is_err d
        && List.mem (slug_of_code d.code)
             [ Code.role_needs_invalid; Code.protocol_invalid; Code.endpoints_label_invalid;
               Code.endpoints_name_clash ]) ds in
  let protocol_follow_on sl =
    List.mem sl [ Code.type_mismatch; Code.protocol_step_order; Code.protocol_wrong_role;
                  Code.unknown_constructor;
                  Code.unknown_qualified_name ]
    || (String.length sl > 7 && String.sub sl 0 7 = "linear_")
    || (String.length sl > 8 && String.sub sl 0 8 = "session_") in
  let session_errors =
    List.length (List.filter (fun d ->
        is_err d && (let sl = slug_of_code d.code in
                     String.length sl > 8 && String.sub sl 0 8 = "session_")) ds) in
  let json_collisions =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.json_derive_name_collision d then first_backticked d.message
        else None) ds in
  (* A protocol state used a second time: the step the second use takes is
     out of order only because the first already took this one, so the
     reuse is the error (§F3: `close(s, st)` then a step on `st`). *)
  let used_twice_spans =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.linear_used_twice d then Some d.span else None) ds in
  let wrong_actor_spans =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.send_wrong_actor d then Some d.span else None) ds in
  let positioned_error = List.exists (fun d -> is_err d && d.span.start_line > 0) ds in
  let error_spans = List.filter_map (fun d -> if is_err d then Some d.span else None) ds in
  let lemma_call_spans =
    List.filter_map (fun d ->
        if d.severity <> Hint && visible d && has_slug Code.lemma_unproved_call d
        then Some d.span else None) ds in
  let within (inner : March_ast.Ast.span) (outer : March_ast.Ast.span) =
    inner.file = outer.file
    && (inner.start_line, inner.start_col) >= (outer.start_line, outer.start_col)
    && (inner.end_line, inner.end_col) <= (outer.end_line, outer.end_col) in
  let needs_codes =
    List.filter_map (fun d ->
        if is_err d && has_slug Code.cap_needs d then Some d.code else None) ds in
  (* Exact duplicates go; [type_mismatch]es on one span merge into the first,
     which takes the others' notes and labels: for `let? x = f()` one says
     "the declared return type of `bad`" and the other states the `let?`
     rule, and the reader needs both, once. *)
  let ds =
    let key d =
      if slug_of_code d.code = Code.type_mismatch then (d.code, d.span, "")
      else (d.code, d.span, d.message) in
    let merged = Hashtbl.create 16 in
    let order = ref [] in
    List.iter (fun d ->
        match Hashtbl.find_opt merged (key d) with
        | None -> Hashtbl.replace merged (key d) d; order := key d :: !order
        | Some b ->
          let add xs ys = xs @ List.filter (fun y -> not (List.mem y xs)) ys in
          Hashtbl.replace merged (key d)
            { b with notes = add b.notes d.notes; labels = add b.labels d.labels;
                     fix = (match b.fix with None -> d.fix | f -> f) }) ds;
    List.rev_map (fun k -> Hashtbl.find merged k) !order in
  let kept = List.filter (fun d ->
      let sl = slug_of_code d.code in
      not (
        (sl = Code.type_mismatch && List.mem d.span arity_spans)
        || (sl = Code.unused_binding
            && (match first_backticked d.message with
                | Some x ->
                  let dym = "Did you mean `" ^ x ^ "`?" in
                  List.exists (fun m -> contains_sub m dym) unbound_msgs
                  || List.mem x never_used
                | None -> false))
        || (sl = Code.unbound_variable
            && (match first_backticked d.message with
                | Some y ->
                  List.exists (fun (o : diagnostic) ->
                      o.span.start_line <= d.span.start_line
                      && d.span.start_line <= o.span.end_line + 1
                      && List.exists (fun n -> contains_sub n ("`" ^ y ^ "`"))
                           (o.message :: o.notes))
                    or_pattern_msgs
                | None -> false))
        || (sl = Code.cap_root_broad && non_cap_error)
        || (sl = Code.session_state_mismatch && session_errors > 1
            && contains_sub d.message "expected a channel endpoint but got `")
        || (sl = Code.mint_cap_invalid
            && List.exists (fun o -> within d.span o) proof_cap_spans)
        || (protocol_invalid && is_err d && protocol_follow_on sl)
        || ((sl = Code.protocol_step_order || sl = Code.protocol_wrong_role)
            && List.mem d.span used_twice_spans)
        || (is_err d && d.span.start_line = 0 && positioned_error)
        || (sl = Code.ambiguous_constructor
            && List.exists (fun o -> within d.span o) wrong_actor_spans)
        || (d.severity = Hint && List.mem d.span error_spans)
        || (sl = Code.refinement_unverified && d.severity = Hint
            && List.mem d.span lemma_call_spans)
        || (sl = Code.overlapping_impl
            && List.exists (fun t -> contains_sub d.message ("(" ^ t ^ ")`")) json_collisions)
        || (sl = Code.cap_ceiling
            && (match String.index_opt d.code ':' with
                | Some i ->
                  let cap = String.sub d.code (i + 1) (String.length d.code - i - 1) in
                  List.exists (fun m -> contains_sub m ("`" ^ cap ^ "` is not declared"))
                    import_missing_msgs
                | None -> false))
        || (sl = Code.cap_ceiling
            && (match String.index_opt d.code ':' with
                | Some i ->
                  let arg = String.sub d.code i (String.length d.code - i) in
                  List.mem (Code.cap_needs ^ arg) needs_codes
                | None -> false))))
    ds in
  (* A dropped diagnostic's fix must not be lost: a [cap_ceiling:X] dropped
     for an [import_cap_missing] about `X` hands its `needs X` insert to that
     error when it has none. *)
  let kept =
    List.map (fun k ->
        if is_err k && has_slug Code.import_cap_missing k && k.fix = None then
          match List.find_opt (fun d ->
              has_slug Code.cap_ceiling d && d.fix <> None
              && not (List.memq d kept)
              && (match String.index_opt d.code ':' with
                  | Some i ->
                    let cap = String.sub d.code (i + 1) (String.length d.code - i - 1) in
                    contains_sub k.message ("`" ^ cap ^ "` is not declared")
                  | None -> false)) ds with
          | Some d -> { k with fix = d.fix }
          | None -> k
        else k) kept in
  (* The reuse report takes over what the dropped step-order error knew: a
     protocol state takes exactly one step, and `close` takes the last. *)
  let kept =
    List.map (fun k ->
        if is_err k && has_slug Code.linear_used_twice k then
          match List.find_opt (fun d ->
              (has_slug Code.protocol_step_order d || has_slug Code.protocol_wrong_role d)
              && d.span = k.span && not (List.memq d kept)) ds with
          | Some d ->
            let note =
              if contains_sub d.message "must close the conversation" then
                "This is a protocol state, and the first use closed the conversation: \
                 no step can follow `close`."
              else
                "This is a protocol state, so it takes exactly one step: take the next \
                 step with the state the first one returned." in
            (* ... and its diagram, which marks the step taken again. *)
            let diagram = List.filter (fun n ->
                String.starts_with ~prefix:"The conversation so far" n) d.notes in
            { k with notes = k.notes @ [ note ] @ diagram }
          | None -> k
        else k) kept in
  (* The lemma warning takes over what the dropped [refinement_unverified]
     hint knew: which precondition, and why it is not proved. *)
  let kept =
    List.map (fun k ->
        if has_slug Code.lemma_unproved_call k && k.severity <> Hint then
          match List.find_opt (fun d ->
              has_slug Code.refinement_unverified d && d.severity = Hint
              && d.span = k.span && not (List.memq d kept)) ds with
          | Some d ->
            let why = match String.split_on_char '\n' d.message with
              | _ :: rest -> List.filter_map (fun l ->
                  match String.trim l with "" -> None | l -> Some l) rest
              | [] -> [] in
            (match first_backticked d.message with
             | Some p ->
               let note = Printf.sprintf "Its precondition is `%s`%s." p
                   (match why with [] -> "" | ws -> "; " ^ String.concat "; " ws) in
               { k with notes = k.notes @ [ note ] }
             | None -> k)
          | None -> k
        else k) kept in
  let kept = List.map tidy_notes kept in
  (* Every rule names a visible error that stays, so this cannot fire; it
     guards the exit code against a future rule that forgets to. *)
  if List.exists is_err ds && not (List.exists is_err kept) then ds else kept

(** Render a diagnostic with source context.
    Shows the relevant source line with a caret underline pointing at the span.

    Format (Elm-inspired):
      -- TYPE MISMATCH ---------- filename    (the title: [header_title])
      <blank>
      message
      <blank>
      N | source line
        | ^^^^^^^^^^^^
      [notes]
*)
(* ── Codes in rendered output ────────────────────────────────────────

   Every rendered diagnostic ends its headline (the message's first line)
   with ` [slug]`. It is APPENDED to the line, never inserted, so a test or a
   corpus `EXPECT-ERROR` that greps for a fragment of the headline still
   matches. The first time a run renders a code that has a
   `march --explain` page, the diagnostic also says so; later diagnostics
   with the same code don't repeat it. *)

let explain_hints_shown : (string, unit) Hashtbl.t = Hashtbl.create 8


let headline_with_code (d : diagnostic) =
  let suffix = " [" ^ Code.slug_of d.code ^ "]" in
  match String.index_opt d.message '\n' with
  | None -> d.message ^ suffix
  | Some i ->
    String.sub d.message 0 i ^ suffix
    ^ String.sub d.message i (String.length d.message - i)

let explain_hint (d : diagnostic) =
  let slug = Code.slug_of d.code in
  if not (Explain.has_page slug)
     || Hashtbl.mem explain_hints_shown slug then ""
  else begin
    Hashtbl.replace explain_hints_shown slug ();
    "\n" ^ fmt_note (Printf.sprintf "    run `march --explain %s`" slug)
  end

(** The title of a diagnostic's header: its code's category for an error
    (`TYPE MISMATCH`), the severity and the category for a warning or hint
    (`WARNING: UNUSED`), so the severity of a non-error is never lost. *)
let header_title (d : diagnostic) =
  let cat = Code.category d.code in
  match d.severity with
  | Error -> cat
  | Warning -> if cat = "ERROR" then "WARNING" else "WARNING: " ^ cat
  | Hint -> if cat = "ERROR" then "HINT" else "HINT: " ^ cat

(** Whether [line] (ANSI colour already stripped) is a rendered header, and
    of which severity: `-- <TITLE> --…`, the title upper-case letters,
    spaces and colons.  For tools that count diagnostics in rendered output
    (forge's build summary keeps its own copy of this rule). *)
let header_severity (line : string) : severity option =
  let n = String.length line in
  let rec title_end i =
    if i < n && (match line.[i] with 'A' .. 'Z' | ' ' | ':' -> true | _ -> false)
    then title_end (i + 1) else i in
  if n < 6 || String.sub line 0 3 <> "-- " then None
  else
    let e = title_end 3 in
    if e > 4 && e + 1 < n && line.[e] = '-' && line.[e + 1] = '-' && line.[e - 1] = ' ' then
      let title = String.sub line 3 (e - 4) in
      if String.starts_with ~prefix:"WARNING" title then Some Warning
      else if String.starts_with ~prefix:"HINT" title then Some Hint
      else Some Error
    else None

let render_diagnostic ~src ?(filename = "") (d : diagnostic) : string =
  let sev_str = header_title d in
  let line  = d.span.March_ast.Ast.start_line in
  let col   = d.span.March_ast.Ast.start_col in
  let eline = d.span.March_ast.Ast.end_line in
  let ecol  = d.span.March_ast.Ast.end_col in
  (* Header bar *)
  let loc_str = if filename = "" then "" else " " ^ filename in
  (* As wide as the old `-- ERROR ---- file` header whatever the title, down
     to a minimum of two dashes. *)
  let dashes  = String.make (max 2 (53 - String.length sev_str - String.length loc_str)) '-' in
  let header =
    if not !use_color then "-- " ^ sev_str ^ " " ^ dashes ^ loc_str
    else
      paint ansi_dim "--" ^ " " ^
      paint (sev_bold_code d.severity) sev_str ^
      paint ansi_dim (" " ^ dashes) ^
      paint ansi_cyan loc_str
  in
  (* Notes block — each note gets 4-space indent on every line *)
  let notes_block =
    if d.notes = [] then ""
    else
      "\n" ^ String.concat "\n"
        (List.map (fun n ->
           let colored = fmt_note n in
           let note_lines = String.split_on_char '\n' colored in
           String.concat "\n" (List.map (fun l -> if l = "" then l else "    " ^ l) note_lines)
         ) d.notes)
  in
  (* When no span info, just show the header and message. *)
  if line <= 0 || src = "" then
    String.concat "\n" [ header; ""; fmt_message (headline_with_code d); notes_block ]
    ^ explain_hint d
  else begin
    (* Extract the source line(s) *)
    let src_lines = String.split_on_char '\n' src in
    let get_line n = try List.nth src_lines (n - 1) with _ -> "" in
    (* Gutter: "N | " — left-pad line number to consistent width *)
    let max_line_no = if eline > line then eline else line in
    let gutter_width = String.length (string_of_int max_line_no) + 3 in (* "N | " *)
    let gutter n =
      let ns = string_of_int n in
      let pad_n = String.make (gutter_width - String.length ns - 3) ' ' in
      pad_n ^ ns ^ " | "
    in
    let pad = String.make gutter_width ' ' in
    (* Build underline: ^^^^^ under the span *)
    let src_line = get_line line in
    let underline =
      let start = col in
      (* If single-line span, underline to end_col; else to end of line *)
      let stop = if eline = line && ecol > col then ecol else String.length src_line in
      let len  = max 1 (stop - start) in
      String.make start ' ' ^ String.make len '^'
    in
    let label_blocks =
      List.filter_map (fun (lbl : label) ->
        let ll  = lbl.lbl_span.March_ast.Ast.start_line in
        let lc  = lbl.lbl_span.March_ast.Ast.start_col in
        let ell = lbl.lbl_span.March_ast.Ast.end_line in
        let elc = lbl.lbl_span.March_ast.Ast.end_col in
        if ll <= 0 || lbl.lbl_span = d.span then None
        else begin
          let lbl_src = get_line ll in
          let max_lno = max ll ell in
          let lw = String.length (string_of_int max_lno) + 3 in
          let lg n =
            let ns = string_of_int n in
            String.make (lw - String.length ns - 3) ' ' ^ ns ^ " | "
          in
          let lp = String.make lw ' ' in
          let lu =
            let stop = if ell = ll && elc > lc then elc else String.length lbl_src in
            String.make lc ' ' ^ String.make (max 1 (stop - lc)) '^'
          in
          Some (Printf.sprintf "\n    %s:\n\n%s%s\n%s%s"
            (paint ansi_dim lbl.lbl_message)
            (paint ansi_dim (lg ll)) lbl_src lp
            (paint ansi_dim lu))
        end
      ) d.labels
    in
    String.concat "\n"
      ([ header; ""; fmt_message (headline_with_code d); "";
         paint ansi_dim (gutter line) ^ src_line;
         pad ^ paint (sev_plain_code d.severity) underline;
         notes_block ]
       @ label_blocks)
    ^ explain_hint d
  end

let parse_error_diagnostic ?(filename = "") ?hint ?(code = Code.syntax_error) ~msg lexbuf =
  let pos     = Lexing.lexeme_start_p lexbuf in
  let line    = pos.Lexing.pos_lnum in
  let col     = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let tok     = Lexing.lexeme lexbuf in
  let tok_len = max 1 (String.length tok) in
  let span    = { March_ast.Ast.file = filename;
                  start_line = line; start_col = col;
                  end_line = line; end_col = col + tok_len } in
  let notes   = match hint with None -> [] | Some h -> [h] in
  { severity = Error; span; message = msg; labels = []; notes; code; fix = None }

let render_parse_error ~src ?(filename = "") ?hint ~msg lexbuf =
  render_diagnostic ~src ~filename (parse_error_diagnostic ~filename ?hint ~msg lexbuf)

(** Width of the token starting at ([line], [col]) in [src], for sizing a
    caret under a position that carries no lexeme: an identifier/keyword/number
    run, else one character.  [line] is 1-based, [col] 0-based (the
    [Lexing.position] convention).  Located by line/column rather than
    [pos_cnum], because some [ParseError] positions are rebuilt from spans and
    carry no absolute offset. *)
let token_len_at ~src ~line ~col =
  let n = String.length src in
  let rec line_start l i =
    if l <= 1 then Some i
    else match String.index_from_opt src i '\n' with
      | Some j -> line_start (l - 1) (j + 1)
      | None -> None
  in
  match line_start line 0 with
  | None -> 1
  | Some bol ->
    let i = bol + col in
    let is_word c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '_' in
    if i < 0 || i >= n || not (is_word src.[i]) then 1
    else begin
      let j = ref i in
      while !j < n && is_word src.[!j] do incr j done;
      !j - i
    end

(** Diagnostic for a [ParseError (msg, hint, pos)]: the span starts at [pos],
    the position the grammar's error production chose.  Use this, not the
    lexbuf form above, whenever the exception carries a position: the lexbuf
    only knows menhir's lookahead token, which is the token AFTER the one the
    message is about.  [src], when given, sizes the caret to the token at
    [pos]; [len] overrides it. *)
let parse_error_diagnostic_at ?(filename = "") ?hint ?src ?len
    ?(code = Code.parse_error) ~msg
    (pos : Lexing.position) =
  let line = pos.Lexing.pos_lnum in
  let col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
  let len  = match len, src with
    | Some l, _ -> max 1 l
    | None, Some src -> token_len_at ~src ~line ~col
    | None, None -> 1 in
  let file = if filename <> "" then filename else pos.Lexing.pos_fname in
  let span = { March_ast.Ast.file;
               start_line = line; start_col = col;
               end_line = line; end_col = col + len } in
  let notes = match hint with None -> [] | Some h -> [h] in
  { severity = Error; span; message = msg; labels = []; notes; code; fix = None }

let render_parse_error_at ~src ?(filename = "") ?hint ~msg pos =
  render_diagnostic ~src ~filename
    (parse_error_diagnostic_at ~filename ?hint ~src ~msg pos)

(* ── JSON output (--check-json) ───────────────────────────────────────── *)

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function
    | '"'  -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c    -> Buffer.add_char b c
  ) s;
  Buffer.add_char b '"';
  Buffer.contents b

(** One NDJSON object per diagnostic.  [related] (default true) adds the
    [labels] (secondary spans, each with its message) and [notes] arrays;
    [--emit-core-ast] passes [~related:false] to keep its versioned document
    byte-stable. *)
let render_diagnostic_json ?(related = true) (d : diagnostic) : string =
  let sev = match d.severity with Error -> "error" | Warning -> "warning" | Hint -> "hint" in
  let sp  = d.span in
  let file    = json_string sp.March_ast.Ast.file in
  let msg     = json_string d.message in
  let code    = json_string d.code in
  let rec edit_json = function
    | FInsert { after_line; text } ->
      Printf.sprintf {|{"kind":"insert","after_line":%d,"text":%s}|}
        after_line (json_string text)
    | FDelete { start_line; end_line } ->
      Printf.sprintf {|{"kind":"delete","start_line":%d,"end_line":%d}|}
        start_line end_line
    | FReplace { span = rs; text } ->
      Printf.sprintf {|{"kind":"replace","start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"text":%s}|}
        rs.March_ast.Ast.start_line rs.March_ast.Ast.start_col
        rs.March_ast.Ast.end_line   rs.March_ast.Ast.end_col
        (json_string text)
    (* A multi-edit fix: {"kind":"multi","edits":[<insert|delete|replace>…]},
       each edit's positions relative to the original source. *)
    | FMulti fs ->
      Printf.sprintf {|{"kind":"multi","edits":[%s]}|}
        (String.concat "," (List.map edit_json (List.concat_map fix_edits fs)))
  in
  let fix_json = match d.fix with
    | None -> "null"
    | Some f -> edit_json f
  in
  let related_json =
    if not related then ""
    else
      let label (l : label) =
        let ls = l.lbl_span in
        Printf.sprintf
          {|{"file":%s,"start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"message":%s}|}
          (json_string ls.March_ast.Ast.file)
          ls.March_ast.Ast.start_line ls.March_ast.Ast.start_col
          ls.March_ast.Ast.end_line   ls.March_ast.Ast.end_col
          (json_string l.lbl_message)
      in
      Printf.sprintf {|,"labels":[%s],"notes":[%s]|}
        (String.concat "," (List.map label d.labels))
        (String.concat "," (List.map json_string d.notes))
  in
  (* [category] (plan §X5) is appended, so every existing field keeps its
     place, and rides with [labels]/[notes]: [~related:false]'s versioned
     --emit-core-ast document stays byte-stable. *)
  let category_json =
    if not related then ""
    else Printf.sprintf {|,"category":%s|} (json_string (Code.category d.code)) in
  Printf.sprintf
    {|{"severity":%s,"file":%s,"start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"message":%s,"code":%s,"fix":%s%s%s}|}
    (json_string sev) file
    sp.March_ast.Ast.start_line sp.March_ast.Ast.start_col
    sp.March_ast.Ast.end_line   sp.March_ast.Ast.end_col
    msg code fix_json related_json category_json
