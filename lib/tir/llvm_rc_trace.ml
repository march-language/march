(** RC trace site ids (`march --rc-trace`;
    specs/plans/incremental-codegen-cas-plan.md §8, A3).

    The runtime's `MARCH_TRACE_GC=1` trace (runtime/march_runtime.c, gc_emit)
    records every alloc / inc_ref / dec_ref / free with the object's address,
    count and tag, but not WHO performed it. This pass makes a finished LLVM
    module say who: it brackets every call into the runtime as

    {v
      call void @march_rc_site_set(i32 N)
      call ... @march_xxx(...)
      call void @march_rc_site_set(i32 -1)
    v}

    where [N] is a dense site id, and it appends a table naming each id
    ["<function symbol>#<ordinal>:<callee>"] (ordinal = the call's position
    among the runtime calls of its function, in emission order) that a module
    constructor hands to [march_rc_sites_register]. The runtime copies the
    active id into each event's ["site"] field, so every event a runtime call
    makes, including a builtin's internal allocations and the recursive drop
    of a freed cell's children, names the compiled call site; an event with
    no compiled call active on its thread reads -1. The table is also written
    to [trace/gc/sites.json] at run time, so scripts/gc-trace-report.py needs
    no compiler.

    Like [Llvm_rc_inline] this works on the module TEXT, after emission:
    the traced calls are printed by more than a dozen emitter files, and one
    rewrite at the end catches every site, including the ones a future
    emitter adds. It runs BEFORE the inline refcount rewrite, which replaces
    [@march_incrc(] and friends with inline twins; the twins take their
    out-of-line branch whenever tracing is on, so the site stored here still
    reaches the runtime. The site id is passed out-of-band (a thread-local
    the runtime reads) rather than as a new parameter, because the inline
    rewrite matches these calls by their text and a changed signature would
    break it.

    With `--rc-trace` off this pass is not run, so release emission is
    byte-identical (scripts/ir-oracle.sh pins that). *)

(** Calls that get a site: every call into the runtime, i.e. to a symbol
    whose name starts with [march_], except this pass's own setter. Not just
    the refcount entry points: a builtin that allocates internally (string
    concatenation, a list map) produces events too, and bracketing its call
    attributes them to the compiled site that made it. *)
let traced_prefix = "@march_"
let untraced = [ "march_rc_site_set"; "march_rc_sites_register" ]

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

(** The symbol a [define] line defines: the text after the first [@], either
    a quoted name or a run of symbol characters. *)
let define_name (line : string) : string =
  match String.index_opt line '@' with
  | None -> "?"
  | Some i ->
    let n = String.length line in
    if i + 1 < n && line.[i + 1] = '"' then begin
      let j = ref (i + 2) in
      while !j < n && line.[!j] <> '"' do incr j done;
      String.sub line (i + 2) (!j - i - 2)
    end else begin
      let j = ref (i + 1) in
      let ok c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                 || (c >= '0' && c <= '9') || c = '_' || c = '.' || c = '$' || c = '-' in
      while !j < n && ok line.[!j] do incr j done;
      String.sub line (i + 1) (!j - i - 1)
    end

(** The runtime callee of an instruction line ([call ... @march_xxx(] on a
    line that is not a [declare]/[define]), or [None]. *)
let traced_callee (line : string) : string option =
  if starts_with "declare " line || starts_with "define " line
  || not (contains line "call ") then None
  else
    let n = String.length line and m = String.length traced_prefix in
    let rec find i =
      if i + m > n then None
      else if String.sub line i m = traced_prefix then begin
        let j = ref (i + 1) in
        let ok c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                   || (c >= '0' && c <= '9') || c = '_' || c = '.' || c = '$' in
        while !j < n && ok line.[!j] do incr j done;
        let name = String.sub line (i + 1) (!j - i - 1) in
        if !j < n && line.[!j] = '(' && not (List.mem name untraced) then Some name
        else find (i + 1)
      end else find (i + 1)
    in
    find 0

(** LLVM [c"..."] escaping of a byte string. *)
let llvm_cstring (s : string) : string =
  let b = Buffer.create (String.length s + 8) in
  String.iter (fun c ->
      let code = Char.code c in
      if c = '"' || c = '\\' || code < 0x20 || code > 0x7e
      then Buffer.add_string b (Printf.sprintf "\\%02X" code)
      else Buffer.add_char b c) s;
  Buffer.contents b

(** Rewrite a finished module. Returns it unchanged when it makes no traced
    call at all. *)
let rewrite (ir : string) : string =
  let lines = String.split_on_char '\n' ir in
  let sites = ref [] in          (* reversed list of names *)
  let next_id = ref 0 in
  let cur_fn = ref "" in
  let ordinal = ref 0 in
  let out = ref [] in
  List.iter (fun line ->
      if starts_with "define " line then begin
        cur_fn := define_name line; ordinal := 0
      end;
      (match (if !cur_fn <> "" then traced_callee line else None) with
       | Some callee ->
         sites := Printf.sprintf "%s#%d:%s" !cur_fn !ordinal callee :: !sites;
         out := Printf.sprintf "  call void @march_rc_site_set(i32 %d)" !next_id :: !out;
         out := line :: !out;
         out := "  call void @march_rc_site_set(i32 -1)" :: !out;
         incr next_id; incr ordinal
       | None ->
         if line = "}" then cur_fn := "";
         out := line :: !out)) lines;
  let n = !next_id in
  if n = 0 then ir
  else begin
    let names = Array.of_list (List.rev !sites) in
    let buf = Buffer.create (String.length ir + 64 * n + 1024) in
    (* The module constructor table is [appending]: one definition per
       module, so an existing one (Llvm_toplevel's atom-namer registration)
       is extended rather than duplicated. *)
    let ctor_entry = "{ i32, ptr, ptr } { i32 65535, ptr @__march_rc_sites_register, ptr null }" in
    let merged = ref false in
    let pre = "@llvm.global_ctors = appending global [" in
    List.iter (fun line ->
        if (not !merged) && starts_with pre line then begin
          merged := true;
          let rest = String.sub line (String.length pre) (String.length line - String.length pre) in
          let k = Scanf.sscanf rest "%d x" (fun k -> k) in
          match String.index_opt rest '[' with
          | None -> Buffer.add_string buf line
          | Some i ->
            let elems = String.sub rest (i + 1) (String.length rest - i - 1) in
            Buffer.add_string buf
              (Printf.sprintf "%s%d x { i32, ptr, ptr }] [%s, %s" pre (k + 1) ctor_entry elems)
        end else Buffer.add_string buf line;
        Buffer.add_char buf '\n') (List.rev !out);
    Buffer.add_string buf "\n; ── RC trace site table (lib/tir/llvm_rc_trace.ml, --rc-trace) ──\n";
    Array.iteri (fun i name ->
        Buffer.add_string buf
          (Printf.sprintf "@__march_rc_site_%d = private unnamed_addr constant [%d x i8] c\"%s\\00\"\n"
             i (String.length name + 1) (llvm_cstring name))) names;
    Buffer.add_string buf
      (Printf.sprintf "@__march_rc_site_names = private constant [%d x ptr] [%s]\n" n
         (String.concat ", " (List.init n (fun i -> Printf.sprintf "ptr @__march_rc_site_%d" i))));
    Buffer.add_string buf
      "declare void @march_rc_site_set(i32)\n\
       declare void @march_rc_sites_register(ptr, i32)\n\
       define internal void @__march_rc_sites_register() {\n\
       entry:\n";
    Buffer.add_string buf
      (Printf.sprintf "  call void @march_rc_sites_register(ptr @__march_rc_site_names, i32 %d)\n" n);
    Buffer.add_string buf "  ret void\n}\n";
    if not !merged then
      Buffer.add_string buf
        (Printf.sprintf "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [%s]\n" ctor_entry);
    Buffer.contents buf
  end
