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
   sandbox-exec must exec the target.  Rather than ship a file-read denial
   with holes in it -- which would read as enforcement while not enforcing
   -- IO.FileRead is Advisory on this backend.  Linux scopes reads properly
   via a mount-namespace allow-list; see [bwrap_args].

   The profile itself is DENY-DEFAULT (see [profile_for]).  An earlier
   attempt concluded deny-default was infeasible because the runtime
   SIGABRTed; the real cause was a baseline missing mach*, sysctl-read and
   ipc-posix-shm, not the approach.  With those present a March binary runs
   clean under (deny default), so the profile is a true allow-list rather
   than a list of denied classes.

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
          (* Enforced via an allow-list mount namespace: only the loader's
             paths and the binary are bound in, so anything else is absent
             rather than merely forbidden.  Measured on Linux 6.12 --
             /etc/hosts DENIED, an explicitly bound path OK, program runs.
             macOS cannot do this because dyld maps system libraries before
             user code exists. *)
          Enforced
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

(* Runtime baseline: the minimum a March process needs to reach main under
   (deny default).  Characterized empirically -- an earlier attempt failed
   because it lacked mach*, sysctl-read and ipc-posix-shm, not because
   deny-default was infeasible.  file-read* is unconditional here: dyld maps
   system libraries before user code exists, which is why IO.FileRead is
   Advisory on this backend (Linux scopes reads properly; see bwrap_args).
   Writes are limited to the standard streams so the process can report. *)
let sbpl_baseline =
  "(allow process-exec)\n\
   (allow file-read* file-read-metadata)\n\
   (allow file-write-data (literal \"/dev/null\") (literal \"/dev/stdout\") \
   (literal \"/dev/stderr\") (literal \"/dev/tty\"))\n\
   (allow sysctl-read)\n\
   (allow mach*)\n\
   (allow signal)\n\
   (allow ipc-posix-shm)\n\
   (allow iokit-open)\n"

let profile_for ~caps ~binary =
  let b = Buffer.create 512 in
  Buffer.add_string b "(version 1)\n";
  (* DENY-DEFAULT allow-list: anything the capability set does not grant, and
     that the runtime baseline does not require, is refused -- including
     resources the capability lattice never modelled (IPC, IOKit, novel
     services).  This replaced an allow-default profile that could only deny
     the classes it knew to name. *)
  Buffer.add_string b "(deny default)\n";
  Buffer.add_string b sbpl_baseline;
  (* The target must be readable to be mapped; covered by the baseline's
     file-read*, but stated explicitly so tightening reads later cannot
     silently make the binary unlaunchable. *)
  Buffer.add_string b (Printf.sprintf "(allow file-read* (literal %S))\n" binary);
  if holds_under caps "IO.FileWrite" then
    Buffer.add_string b "(allow file-write*)\n";
  if holds_under caps "IO.Network" then Buffer.add_string b "(allow network*)\n";
  if holds_under caps "IO.Process" then
    Buffer.add_string b "(allow process-fork)\n";
  Buffer.contents b

(* Linux: bubblewrap flags for the same capability set.  --dev-bind / / keeps
   the filesystem visible (the loader needs it), then each withheld class is
   removed:  --ro-bind makes the whole tree read-only, --unshare-net drops
   external reachability, --unshare-pid contains process spawning. *)
(* Paths a dynamically-linked binary needs before any user code runs.  Bound
   read-only into the allow-list namespace; everything not listed is simply
   not present in the mount namespace, so a read of it fails with ENOENT
   rather than being denied by a policy that could have holes. *)
let loader_paths = [ "/usr"; "/lib"; "/lib64"; "/bin"; "/sbin"; "/etc/ld.so.cache" ]

let bwrap_args ?(binary = "") ~caps () =
  let a = ref [] in
  let add x = a := x :: !a in
  let reads = holds_under caps "IO.FileRead" in
  let writes = holds_under caps "IO.FileWrite" in
  let uses_tmpfs = ref false in
  (match (reads, writes) with
   | true, true -> add "--dev-bind / /"
   | true, false ->
     (* Whole filesystem visible but read-only; a writable /tmp keeps the
        runtime's scratch space working, so a failure means the withheld
        capability and not incidental breakage. *)
     add "--ro-bind / /";
     add "--tmpfs /tmp";
     add "--dev /dev";
     add "--proc /proc";
     uses_tmpfs := true
   | false, _ ->
     (* Read NOT granted: build an ALLOW-LIST namespace containing only the
        loader's paths and the binary itself.  Verified on Linux 6.12 —
        /etc/hosts reads DENIED while an explicitly bound path still reads
        OK.  This is the scoping macOS cannot do, because dyld must map
        /usr/lib before any user code exists. *)
     List.iter
       (fun p -> add (Printf.sprintf "--ro-bind-try %s %s" p p))
       loader_paths;
     add "--dev /dev";
     add "--proc /proc";
     add "--tmpfs /tmp";
     uses_tmpfs := true);
  (* Bind the target AFTER any tmpfs.  A tmpfs mounted over /tmp masks
     everything beneath it — including the binary itself when it lives
     there — so binding earlier makes the program unlaunchable
     ("execvp: No such file or directory").  Caught by testing the GRANTED
     direction; the denied direction passes either way, which is exactly
     why a sandbox needs both tests. *)
  if binary <> "" && !uses_tmpfs then
    add
      (Printf.sprintf "--ro-bind-try %s %s" (Filename.quote binary)
         (Filename.quote binary));
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
        (String.concat " " (bwrap_args ~binary ~caps ()))
        (Filename.quote binary) quoted_args
    in
    Ok (Sys.command cmd)
