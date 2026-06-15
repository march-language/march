(** Debug Adapter Protocol session for the March interpreter.

    A session runs a March program on a worker thread under the interpreter's
    debug context, and answers DAP requests on the protocol thread. The two
    rendezvous through a mutex + condition: when the program hits a breakpoint
    or finishes a step, the [dc_on_pause] callback (worker thread) publishes the
    paused frame and blocks; the protocol thread answers stackTrace / scopes /
    variables against that frame, then assigns the next step mode and resumes
    the worker.

    The session is engine-only: it does not parse or load the stdlib. The caller
    supplies a [make_program : path -> (unit -> unit)] factory that builds a
    runnable for a source path (parse → desugar → run_module). This keeps the
    session library free of the front-end and trivially testable. *)

module Eval = March_eval.Eval
module Debug = March_debug.Debug
module Ast = March_ast.Ast

(* ------------------------------------------------------------------ *)
(* JSON helpers                                                        *)
(* ------------------------------------------------------------------ *)

let jstr s : Yojson.Safe.t = `String s
let jint i : Yojson.Safe.t = `Int i
let jbool b : Yojson.Safe.t = `Bool b
let obj kvs : Yojson.Safe.t = `Assoc kvs

let member key (j : Yojson.Safe.t) : Yojson.Safe.t =
  match j with `Assoc kvs -> (try List.assoc key kvs with Not_found -> `Null) | _ -> `Null

let to_int_opt = function `Int i -> Some i | `Float f -> Some (int_of_float f) | _ -> None
let to_str_opt = function `String s -> Some s | _ -> None
let to_bool = function `Bool b -> b | _ -> false
let to_list = function `List l -> l | _ -> []

(* ------------------------------------------------------------------ *)
(* Session state                                                       *)
(* ------------------------------------------------------------------ *)

type runstate = RNotStarted | RRunning | RPaused | RDone

type t = {
  ic : in_channel;
  oc : out_channel;
  out_mtx : Mutex.t;                  (* serialises writes to [oc] *)
  m : Mutex.t;                        (* guards state + pause fields *)
  cond : Condition.t;
  ctx : Eval.debug_ctx;
  make_program : string -> (unit -> unit);
  baseline : (string, unit) Hashtbl.t; (* builtin names hidden from Locals *)

  mutable seq : int;
  mutable state : runstate;
  mutable pause_env : Eval.env option;
  mutable pause_loc : (string * int) option;  (* file, line at pause *)
  mutable program_path : string option;
  mutable stop_on_entry : bool;
  mutable launch_seen : bool;
  mutable config_done : bool;
  mutable entry_reported : bool;
  mutable worker : Thread.t option;
  mutable finished : bool;            (* serve loop should exit *)
}

(* ------------------------------------------------------------------ *)
(* Outgoing messages                                                   *)
(* ------------------------------------------------------------------ *)

let next_seq t = t.seq <- t.seq + 1; t.seq

let send t (j : Yojson.Safe.t) = Dap_json.write_message t.out_mtx t.oc j

let send_response t ~request_seq ~command ?(success = true) ?body () =
  let base = [
    "seq", jint (next_seq t);
    "type", jstr "response";
    "request_seq", jint request_seq;
    "success", jbool success;
    "command", jstr command;
  ] in
  let base = match body with Some b -> base @ ["body", b] | None -> base in
  send t (obj base)

let send_event t ~event ?body () =
  let base = [
    "seq", jint (next_seq t);
    "type", jstr "event";
    "event", jstr event;
  ] in
  let base = match body with Some b -> base @ ["body", b] | None -> base in
  send t (obj base)

let send_output t ~category text =
  send_event t ~event:"output"
    ~body:(obj ["category", jstr category; "output", jstr text]) ()

(* ------------------------------------------------------------------ *)
(* Inspection: call stack and locals                                   *)
(* ------------------------------------------------------------------ *)

(** Reconstruct the live call stack from the interpreter's named march-stack
    plus the current pause location. Innermost frame first.

    The march-stack records, for each active call, the callee's name and the
    *call-site* line (a line in the caller). So a frame's current line is the
    call-site recorded by the frame one level deeper; the innermost frame's
    current line is the pause location. *)
let build_stack_frames pause_file pause_line : Yojson.Safe.t list =
  let mk id name file line =
    obj [
      "id", jint id;
      "name", jstr name;
      "line", jint line;
      "column", jint 1;
      "source", obj ["name", jstr (Filename.basename file); "path", jstr file];
    ]
  in
  let stack = Array.of_list (Eval.get_march_stack ()) in
  let n = Array.length stack in
  if n = 0 then [ mk 0 "<main>" pause_file pause_line ]
  else begin
    let frames = ref [] in
    frames := [ mk 0 stack.(0).Eval.mf_name pause_file pause_line ];
    for k = 1 to n - 1 do
      frames := mk k stack.(k).Eval.mf_name
                  stack.(k - 1).Eval.mf_file stack.(k - 1).Eval.mf_line :: !frames
    done;
    frames := mk n "<main>"
                stack.(n - 1).Eval.mf_file stack.(n - 1).Eval.mf_line :: !frames;
    List.rev !frames
  end

(** Local bindings for the variables pane: the paused frame's env, deduplicated
    (innermost binding wins), with interpreter builtins and internal names hidden,
    capped to keep the pane readable. *)
let build_locals t : Yojson.Safe.t list =
  match t.pause_env with
  | None -> []
  | Some env ->
    let seen = Hashtbl.create 64 in
    let acc = ref [] in
    let count = ref 0 in
    (try
       List.iter (fun (name, v) ->
           if !count >= 200 then raise Exit;
           if Hashtbl.mem seen name then ()
           else begin
             Hashtbl.add seen name ();
             let hidden =
               Hashtbl.mem t.baseline name
               || (String.length name >= 2 && name.[0] = '_' && name.[1] = '_')
             in
             if not hidden then begin
               incr count;
               acc := obj [
                   "name", jstr name;
                   "value", jstr (Eval.value_to_string v);
                   "variablesReference", jint 0;
                 ] :: !acc
             end
           end) env
     with Exit -> ());
    List.rev !acc

(* ------------------------------------------------------------------ *)
(* Rendezvous: pause / resume                                          *)
(* ------------------------------------------------------------------ *)

(** Worker-thread callback installed as [dc_on_pause]. Publishes the paused
    frame, emits a `stopped` event, and blocks until the protocol thread sets a
    new step mode and resumes. *)
let on_pause t (env : Eval.env) (sp : Ast.span) : unit =
  Mutex.lock t.m;
  t.pause_env <- Some env;
  t.pause_loc <- Some (sp.Ast.file, sp.Ast.start_line);
  t.state <- RPaused;
  let reason =
    if not t.entry_reported && t.stop_on_entry then (t.entry_reported <- true; "entry")
    else if Hashtbl.mem t.ctx.Eval.dc_breakpoints (sp.Ast.file, sp.Ast.start_line)
    then "breakpoint"
    else "step"
  in
  Mutex.unlock t.m;
  send_event t ~event:"stopped"
    ~body:(obj [
        "reason", jstr reason;
        "threadId", jint 1;
        "allThreadsStopped", jbool true;
      ]) ();
  Mutex.lock t.m;
  while t.state = RPaused do Condition.wait t.cond t.m done;
  Mutex.unlock t.m

(** Resume the worker with [step] (called on the protocol thread while the
    worker is parked). *)
let resume t (step : Eval.step_mode) =
  Mutex.lock t.m;
  t.ctx.Eval.dc_step <- step;
  t.pause_env <- None;
  t.pause_loc <- None;
  t.state <- RRunning;
  Condition.signal t.cond;
  Mutex.unlock t.m

(* ------------------------------------------------------------------ *)
(* Worker thread                                                       *)
(* ------------------------------------------------------------------ *)

let start_worker t =
  match t.program_path with
  | None -> ()
  | Some path ->
    Mutex.lock t.m; t.state <- RRunning; Mutex.unlock t.m;
    t.ctx.Eval.dc_step <- (if t.stop_on_entry then Eval.Pause else Eval.Run);
    let prog = t.make_program path in
    let body () =
      (try prog ()
       with e -> send_output t ~category:"stderr" (Printexc.to_string e ^ "\n"));
      (* The program writes to the (block-buffered, non-TTY) process stdout/stderr,
         which the entry point redirects to a pipe drained into `output` events.
         Flush here so buffered program output reaches that pipe before we report
         termination. *)
      (try flush stdout with _ -> ());
      (try flush stderr with _ -> ());
      Mutex.lock t.m; t.state <- RDone; Mutex.unlock t.m;
      send_event t ~event:"exited" ~body:(obj ["exitCode", jint 0]) ();
      send_event t ~event:"terminated" ()
    in
    t.worker <- Some (Thread.create body ())

let maybe_start t =
  if t.launch_seen && t.config_done && t.worker = None then start_worker t

(* ------------------------------------------------------------------ *)
(* Request handlers                                                    *)
(* ------------------------------------------------------------------ *)

let cur_depth t = t.ctx.Eval.dc_depth

let handle_request t (msg : Yojson.Safe.t) =
  let request_seq = match to_int_opt (member "seq" msg) with Some i -> i | None -> 0 in
  let command = match to_str_opt (member "command" msg) with Some s -> s | None -> "" in
  let args = member "arguments" msg in
  let respond ?(success = true) ?body () =
    send_response t ~request_seq ~command ~success ?body () in
  match command with
  | "initialize" ->
    respond ~body:(obj [
        "supportsConfigurationDoneRequest", jbool true;
        "supportsTerminateRequest", jbool true;
        "supportsEvaluateForHovers", jbool true;
      ]) ();
    send_event t ~event:"initialized" ()

  | "launch" ->
    let path = to_str_opt (member "program" args) in
    t.program_path <- path;
    t.stop_on_entry <- to_bool (member "stopOnEntry" args);
    t.launch_seen <- true;
    respond ();
    maybe_start t

  | "setBreakpoints" ->
    let source = member "source" args in
    let path = match to_str_opt (member "path" source) with Some p -> p | None -> "" in
    (* Clear existing breakpoints for this file, then install the new set. *)
    Hashtbl.iter (fun (f, l) () ->
        if f = path then Hashtbl.remove t.ctx.Eval.dc_breakpoints (f, l))
      (Hashtbl.copy t.ctx.Eval.dc_breakpoints);
    let bps = to_list (member "breakpoints" args) in
    let verified =
      List.map (fun bp ->
          match to_int_opt (member "line" bp) with
          | Some line ->
            Hashtbl.replace t.ctx.Eval.dc_breakpoints (path, line) ();
            obj ["verified", jbool true; "line", jint line]
          | None -> obj ["verified", jbool false]) bps
    in
    respond ~body:(obj ["breakpoints", `List verified]) ()

  | "setExceptionBreakpoints" | "setFunctionBreakpoints" ->
    respond ~body:(obj ["breakpoints", `List []]) ()

  | "configurationDone" ->
    t.config_done <- true;
    respond ();
    maybe_start t

  | "threads" ->
    respond ~body:(obj [
        "threads", `List [ obj ["id", jint 1; "name", jstr "main"] ]
      ]) ()

  | "stackTrace" ->
    Mutex.lock t.m;
    let frames = match t.pause_loc with
      | Some (file, line) -> build_stack_frames file line
      | None -> [] in
    Mutex.unlock t.m;
    respond ~body:(obj [
        "stackFrames", `List frames;
        "totalFrames", jint (List.length frames);
      ]) ()

  | "scopes" ->
    respond ~body:(obj [
        "scopes", `List [
          obj [
            "name", jstr "Locals";
            "variablesReference", jint 1;
            "expensive", jbool false;
          ]
        ]
      ]) ()

  | "variables" ->
    Mutex.lock t.m;
    let vars = build_locals t in
    Mutex.unlock t.m;
    respond ~body:(obj ["variables", `List vars]) ()

  | "continue" ->
    resume t Eval.Run;
    respond ~body:(obj ["allThreadsContinued", jbool true]) ();
    send_event t ~event:"continued"
      ~body:(obj ["threadId", jint 1; "allThreadsContinued", jbool true]) ()

  | "next" ->
    resume t (Eval.StepOver (cur_depth t));
    respond ()

  | "stepIn" ->
    resume t Eval.StepInto;
    respond ()

  | "stepOut" ->
    resume t (Eval.StepOut (cur_depth t));
    respond ()

  | "pause" ->
    t.ctx.Eval.dc_step <- Eval.Pause;
    respond ();
    send_event t ~event:"stopped"
      ~body:(obj ["reason", jstr "pause"; "threadId", jint 1]) ()

  | "evaluate" ->
    (* v1: resolve a bare variable name in the paused frame (hover / watch). *)
    let expr = match to_str_opt (member "expression" args) with Some s -> String.trim s | None -> "" in
    Mutex.lock t.m;
    let result =
      match t.pause_env with
      | Some env -> (match List.assoc_opt expr env with
          | Some v -> Some (Eval.value_to_string v)
          | None -> None)
      | None -> None in
    Mutex.unlock t.m;
    (match result with
     | Some v -> respond ~body:(obj ["result", jstr v; "variablesReference", jint 0]) ()
     | None -> respond ~success:false ~body:(obj ["result", jstr "not available"; "variablesReference", jint 0]) ())

  | "disconnect" | "terminate" ->
    (* Unblock the worker if it is parked, then end the protocol loop. *)
    (match t.state with RPaused -> resume t Eval.Run | _ -> ());
    t.finished <- true;
    respond ()

  | _ ->
    (* Be lenient with requests we do not implement. *)
    respond ()

(* ------------------------------------------------------------------ *)
(* Public API                                                          *)
(* ------------------------------------------------------------------ *)

(** Create a session. Installs a fresh debug context wired to this session's
    pause rendezvous (replacing any previously installed context). *)
let create ~ic ~oc ~make_program : t =
  let ctx = Debug.make_debug_ctx ~on_dbg:(fun _ -> ()) in
  let baseline = Hashtbl.create 512 in
  List.iter (fun (name, _) -> Hashtbl.replace baseline name ()) Eval.base_env;
  let t = {
    ic; oc;
    out_mtx = Mutex.create ();
    m = Mutex.create ();
    cond = Condition.create ();
    ctx;
    make_program;
    baseline;
    seq = 0;
    state = RNotStarted;
    pause_env = None;
    pause_loc = None;
    program_path = None;
    stop_on_entry = false;
    launch_seen = false;
    config_done = false;
    entry_reported = false;
    worker = None;
    finished = false;
  } in
  ctx.Eval.dc_on_pause <- Some (on_pause t);
  Debug.install ctx;
  t

(** Run the protocol loop until a disconnect/terminate request (or EOF). *)
let serve (t : t) : unit =
  let rec loop () =
    if t.finished then ()
    else match Dap_json.read_message t.ic with
      | None -> ()
      | Some msg ->
        (match to_str_opt (member "type" msg) with
         | Some "request" -> handle_request t msg
         | _ -> ());
        loop ()
  in
  loop ();
  Debug.uninstall ()
