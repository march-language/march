(** Process supervision for commands that run several long-lived processes
    together: start them, watch them, stop them as a group.

    forge otherwise runs one foreground process per command through
    [Sys.command]. This module is for the rest: [forge run --processes], the
    local reconciler backend and [forge test --upgrade-from]
    (specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md, II.3,
    II.6, II.8). It knows nothing about topologies; the caller decides what
    to run.

    Every child runs in its own session and process group, so a terminal
    Ctrl-C reaches forge only, and forge stops the children in order. [stop]
    signals the whole group, so a child's own children go with it. *)

(** Where a process's output goes. stdout and stderr are both written to
    [<dir>/<name>.log]. With [follow], each line is also passed to the
    function prefixed with ["[<name>] "] (the terminal, for [--follow]). *)
type log_sink = {
  dir : string;
  follow : (string -> unit) option;
}

(** [.forge/run] under [root], not following. *)
val default_log_sink : root:string -> log_sink

type proc

val name : proc -> string
val pid : proc -> int
val log_path : proc -> string

(** [None] while running; the exit status once reaped. *)
val status : proc -> Unix.process_status option

(** Start [argv] (resolved on PATH, no shell) with the current environment
    plus [env], which overrides any variable of the same name. stdin is
    /dev/null. An [argv.(0)] that cannot be executed gives a process that
    exits 127 with the reason in its log. *)
val spawn :
  name:string -> env:(string * string) list -> argv:string array -> log:log_sink -> proc

(** Block until one of the running [procs] exits, and return it with its
    status; [None] if none of them is running. *)
val wait_any : proc list -> (proc * Unix.process_status) option

(** Block until every proc has exited or [timeout] seconds pass; [true] if
    they all exited. *)
val wait_all : timeout:float -> proc list -> bool

(** SIGTERM the proc's process group, wait up to [grace_ms] for it to exit,
    then SIGKILL the group. Returns once the proc is reaped. A no-op on a
    proc that has already exited. *)
val stop : proc -> grace_ms:int -> unit

(** [stop] every proc, in reverse start order ([procs] is in start order). *)
val stop_all : proc list -> grace_ms:int -> unit

(** Watch [procs] until they have all exited, then return each one's name and
    status, in start order.

    forge's own SIGINT or SIGTERM stops them all ([stop_all]). With
    [fail_fast], so does any proc exiting that [stop] did not ask to exit.
    The previous SIGINT/SIGTERM handlers are restored on return. *)
val supervise :
  ?fail_fast:bool -> grace_ms:int -> proc list -> (string * Unix.process_status) list

(** A TCP port on 127.0.0.1 that was free a moment ago (bind port 0, read it
    back, close). For assigning cluster ports per process; racy by nature,
    like every such helper. *)
val free_port : unit -> int

(** [n] distinct ports, each free a moment ago. Use this, not [n] calls to
    [free_port], when several processes need ports at once: the sockets are all
    held until every port is read, so the list has no duplicates. *)
val free_ports : int -> int list

val string_of_status : Unix.process_status -> string
