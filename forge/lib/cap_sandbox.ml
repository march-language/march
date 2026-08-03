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

let supported = Sys.file_exists "/usr/bin/sandbox-exec"

let enforceability cap =
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

let run ~caps ~binary ~args =
  if not supported then
    Error
      "capability enforcement is not available on this platform (no \
       /usr/bin/sandbox-exec); refusing to run unsandboxed"
  else begin
    let profile = profile_for ~caps ~binary in
    let path = Filename.temp_file "march_cap" ".sb" in
    let oc = open_out path in
    output_string oc profile;
    close_out oc;
    let cmd =
      Printf.sprintf "/usr/bin/sandbox-exec -f %s %s %s" (Filename.quote path)
        (Filename.quote binary)
        (String.concat " " (List.map Filename.quote args))
    in
    let rc = Sys.command cmd in
    (try Sys.remove path with Sys_error _ -> ());
    Ok rc
  end
