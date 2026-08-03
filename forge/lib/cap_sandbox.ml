(* Derive an OS sandbox profile from a capability set.  See cap_sandbox.mli.

   The enforceable/advisory split below was MEASURED on macOS 26 (arm64) by
   running real March binaries under each blanket deny, not assumed:

     deny file-write*    -> program runs, writes blocked      ENFORCEABLE
     deny network*       -> program runs, bind fails cleanly  ENFORCEABLE
     deny process-fork   -> program runs                      ENFORCEABLE
     deny file-read*     -> SIGABRT (dyld cannot map libs)    NOT enforceable
     deny process-exec   -> exit 71 (target cannot launch)    NOT enforceable

   The two failures are structural, not tuning: the loader must read
   /usr/lib and the shared cache before any user code exists, and
   sandbox-exec must exec the target.  Scoped allow-lists for those paths
   were tried and still aborted.  Rather than ship a file-read denial with
   holes in it -- which would read as enforcement while not enforcing --
   IO.FileRead is reported Advisory on macOS.  Linux Landlock can scope
   filesystem reads properly and is the path to fixing that; see
   specs/todos for the follow-up.

   IO.Clock and IO.Spawn are advisory everywhere: their syscalls
   (clock_gettime, thread creation) are indistinguishable from the GC and
   scheduler's own baseline traffic, so denying them kills the runtime. *)

type enforcement =
  | Enforced
  | Advisory of string

(* Backend selection.  macOS: sandbox-exec (SBPL).  Linux: bubblewrap, whose
   primitives were measured in a 6.12 container:
     --ro-bind / /     -> writes DENIED                    ENFORCEABLE
     --tmpfs <path>    -> reads of that path DENIED        ENFORCEABLE
     --unshare-net     -> outbound connect DENIED, but
                          bind() still SUCCEEDS locally
   That last asymmetry is real and is not smoothed over: a netns isolates
   rather than refuses, so a server can still bind a port nothing can reach.
   Exfiltration -- the case that matters -- is blocked. *)
type backend = Sbpl | Bwrap | Unavailable

let backend =
  if Sys.file_exists "/usr/bin/sandbox-exec" then Sbpl
  else if Sys.file_exists "/usr/bin/bwrap" || Sys.file_exists "/bin/bwrap" then
    Bwrap
  else Unavailable

let supported = backend <> Unavailable

let enforceability_bwrap cap = (
      match cap with
      | "IO.FileWrite" | "IO.FileSystem" -> Enforced
      | "IO.Network" | "IO.NetConnect" | "IO.NetConnect.TLS" | "IO.WebSocket"
      | "IO.Database" ->
          Enforced
      | "IO.NetListen" ->
          (* A netns isolates rather than refuses: bind() still succeeds, it
             is simply unreachable.  Containment for reachability, not a
             refusal at the syscall. *)
          Advisory
            "a network namespace isolates rather than refuses; bind() still \
             succeeds but is unreachable"
      | "IO.FileRead" ->
          (* Linux CAN scope reads, unlike macOS -- this is the gap Landlock
             closes properly.  Reported Enforced only once path scoping is
             wired; today the profile does not restrict reads. *)
          Advisory
            "read scoping is available on Linux (tmpfs/Landlock) but not yet \
             wired into the profile"
      | "IO.Process" -> Enforced
      | "IO.Clock" ->
          Advisory "clock_gettime is indistinguishable from the scheduler's own use"
      | "IO.Spawn" ->
          Advisory "thread creation is indistinguishable from the runtime's own use"
      | "IO.Console" -> Advisory "stdout/stderr are required to report violations"
      | "IO.Random" -> Advisory "/dev/urandom is read by the runtime at startup"
      | "IO.Foreign" | "IO.Foreign.Blocking" ->
          Advisory "foreign C code is outside the capability model entirely"
      | _ -> Advisory "no mapping from this capability to an OS restriction")

let enforceability_sbpl cap =
  match cap with
  | "IO.FileWrite" | "IO.FileSystem" -> Enforced
  | "IO.Network" | "IO.NetConnect" | "IO.NetListen" | "IO.NetConnect.TLS"
  | "IO.WebSocket" | "IO.Database" ->
    Enforced
  | "IO.Process" ->
    (* fork is deniable; exec of the target itself cannot be, so a program
       that only spawns children is contained, but "no exec at all" is not
       expressible here. *)
    Enforced
  | "IO.FileRead" ->
    Advisory "the dynamic loader must read system libraries before user code runs"
  | "IO.Clock" ->
    Advisory "clock_gettime is indistinguishable from the scheduler's own use"
  | "IO.Spawn" ->
    Advisory "thread creation is indistinguishable from the runtime's own use"
  | "IO.Console" -> Advisory "stdout/stderr are required to report violations"
  | "IO.Random" -> Advisory "/dev/urandom is read by the runtime at startup"
  | "IO.Foreign" | "IO.Foreign.Blocking" ->
    Advisory "foreign C code is outside the capability model entirely"
  | _ -> Advisory "no mapping from this capability to an OS restriction"

let enforceability cap =
  match backend with
  | Unavailable -> Advisory "no sandbox backend on this platform"
  | Bwrap -> enforceability_bwrap cap
  | Sbpl -> enforceability_sbpl cap

let advisory_caps =
  List.filter
    (fun c -> match enforceability c with Advisory _ -> true | Enforced -> false)
    March_caps.Cap_symbols.all_caps

(* [holds_under caps klass] — must the OS class [klass] stay open?

   BOTH lattice directions matter, and each was a bug caught by a test:
   - held cap is an ANCESTOR of the class (granting IO, or IO.Network)
     -> the grant covers the class;
   - held cap is a DESCENDANT of the class (granting IO.NetListen, a child
     of IO.Network) -> the program still needs the class open to work.
   Requiring only one direction silently denies a capability that was
   granted, which is indistinguishable from correct containment. *)
let holds_under caps klass =
  List.exists
    (fun c ->
       March_caps.Cap_lattice.cap_subsumes klass c
       || March_caps.Cap_lattice.cap_subsumes c klass)
    caps

let profile_for ~caps ~binary =
  let b = Buffer.create 512 in
  Buffer.add_string b "(version 1)\n";
  (* Allow-by-default, then deny each enforceable class the caps do not
     grant.  A deny-default profile was measured to abort the runtime even
     with a hand-built allow-list for system paths; an allow-list that does
     not work is worth nothing, so this denies the capability classes
     instead.  That is weaker than a true allow-list -- it constrains the
     categories the capability lattice models, not novel resources -- and
     cap_sandbox.mli says so rather than implying otherwise. *)
  Buffer.add_string b "(allow default)\n";
  (* The target must be exec'able and readable or it cannot start. *)
  Buffer.add_string b
    (Printf.sprintf "(allow process-exec (literal %S))\n" binary);
  Buffer.add_string b (Printf.sprintf "(allow file-read* (literal %S))\n" binary);
  if not (holds_under caps "IO.FileWrite") then
    Buffer.add_string b "(deny file-write*)\n";
  if not (holds_under caps "IO.Network") then
    Buffer.add_string b "(deny network*)\n";
  if not (holds_under caps "IO.Process") then
    Buffer.add_string b "(deny process-fork)\n";
  Buffer.contents b

(* Linux: bubblewrap flags for the same capability set.  --dev-bind / / keeps
   the filesystem visible (the loader needs it), then each withheld class is
   removed:  --ro-bind makes the whole tree read-only, --unshare-net drops
   external reachability, --unshare-pid contains process spawning. *)
let bwrap_args ~caps =
  let a = ref [] in
  let add x = a := x :: !a in
  if holds_under caps "IO.FileWrite" then add "--dev-bind / /"
  else begin
    (* read-only root, with a writable /tmp so the runtime can still use
       scratch space; without this many programs fail for reasons unrelated
       to the capability being withheld. *)
    add "--ro-bind / /";
    add "--tmpfs /tmp";
    add "--dev /dev";
    add "--proc /proc"
  end;
  if not (holds_under caps "IO.Network") then add "--unshare-net";
  if not (holds_under caps "IO.Process") then add "--unshare-pid";
  List.rev !a

let run ~caps ~binary ~args =
  let quoted_args = String.concat " " (List.map Filename.quote args) in
  match backend with
  | Unavailable ->
    Error
      "capability enforcement is not available on this platform (no \
       sandbox-exec or bwrap); refusing to run unsandboxed"
  | Sbpl ->
    let profile = profile_for ~caps ~binary in
    let path = Filename.temp_file "march_cap" ".sb" in
    let oc = open_out path in
    output_string oc profile;
    close_out oc;
    let cmd =
      Printf.sprintf "/usr/bin/sandbox-exec -f %s %s %s" (Filename.quote path)
        (Filename.quote binary) quoted_args
    in
    let rc = Sys.command cmd in
    (try Sys.remove path with Sys_error _ -> ());
    Ok rc
  | Bwrap ->
    let cmd =
      Printf.sprintf "bwrap %s %s %s"
        (String.concat " " (bwrap_args ~caps))
        (Filename.quote binary) quoted_args
    in
    Ok (Sys.command cmd)
