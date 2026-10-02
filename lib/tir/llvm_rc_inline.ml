(** Inline refcount fast path (specs/plans/2026-09-30-inline-rc-fast-path.md).

    Every refcount operation in compiled code used to be an out-of-line call
    into the separately compiled runtime, which LLVM can neither inline nor
    elide. This pass rewrites a finished LLVM module so that each call to one
    of the six runtime refcount entry points goes to an [internal alwaysinline]
    twin defined in the same module:

    {v
    march_incrc              -> __march_rc_incrc
    march_incrc_local        -> __march_rc_incrc_local
    march_decrc              -> __march_rc_decrc
    march_decrc_local        -> __march_rc_decrc_local
    march_decrc_freed        -> __march_rc_decrc_freed
    march_decrc_local_freed  -> __march_rc_decrc_local_freed
    v}

    It works on the module TEXT, after emission, because these calls are
    printed by more than a dozen emitter files; one rewrite at the end catches
    every site, including future ones, without touching any of them.

    Each twin reproduces its original's semantics exactly
    (runtime/march_runtime.c), and hands every unusual case to the original:

    - a value that is not a heap pointer ([IS_HEAP_PTR]) is left alone, with
      the original's return value for the [_freed] forms (1 for
      [march_decrc_freed], 0 for [march_decrc_local_freed]);
    - while GC tracing is on or not yet resolved ([march_gc_trace_state] is not
      -1) the original is called, so trace events are unchanged;
    - a decrement of an immortal object ([rc >= MARCH_RC_IMMORTAL]) is skipped,
      as the originals skip it;
    - a decrement that reaches the last reference (or underflows) calls
      [march_rc_last_atomic] / [march_rc_last_local], which run exactly the
      original's tail at that point (destructor, string stats, free counters,
      underflow abort) without decrementing again. An earlier version restored
      the count and called the original instead, which cost one more atomic and
      a second decrement per free: binary_trees, which frees heavily, measured
      about 6% slower that way.

    The fast path is always atomic. The [_local] originals are atomic whenever
    they run on a scheduler worker, which includes compiled [main]; an atomic
    increment is never less safe than a plain one, and measured no slower on
    arm64.

    Not applied to wasm targets (the wasm runtime's refcount entry points are
    no-ops, so a fast path would start freeing memory), to sanitizer builds
    (they keep the runtime's own accesses visible), or with
    [MARCH_NO_INLINE_RC=1]. The driver decides; see [bin/main.ml]. *)

(** Escape hatch for A/B runs and bisection. Read once per process. *)
let env_disabled : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_NO_INLINE_RC" with
      | Some ("1" | "true" | "yes") -> true
      | _ -> false)

(** [MARCH_RC_IMMORTAL] in runtime/march_runtime.h is [1 << 40]. The twins test
    [rc >= 1 << 40] as [(rc asr 40) > 0]: the same answer for every count
    (a negative, underflowed count is not immortal either way), but with no
    40-bit constant, which LLVM otherwise pins in a callee-saved register in
    every function that refcounts, growing each frame. *)
let immortal = "40"

type kind =
  | Inc
  | Dec of string                (* last-reference helper *)
  | DecFreed of string * string  (* value returned for a non-heap ptr, helper *)

(* (runtime name, twin name, kind). The DecFreed literal is each original's
   non-heap return: march_decrc_freed returns 1, march_decrc_local_freed 0. *)
let entries = [
  "march_incrc",             "__march_rc_incrc",             Inc;
  "march_incrc_local",       "__march_rc_incrc_local",       Inc;
  "march_decrc",             "__march_rc_decrc",             Dec "march_rc_last_atomic";
  "march_decrc_local",       "__march_rc_decrc_local",       Dec "march_rc_last_local";
  "march_decrc_freed",       "__march_rc_decrc_freed",       DecFreed ("1", "march_rc_last_atomic");
  "march_decrc_local_freed", "__march_rc_decrc_local_freed", DecFreed ("0", "march_rc_last_local");
]

let heap_check = {|  %i = ptrtoint ptr %p to i64
  %lo = and i64 %i, 1
  %even = icmp eq i64 %lo, 0
  %big = icmp uge i64 %i, 4096
  %pos = icmp sgt i64 %i, 0
  %a = and i1 %even, %big
  %heap = and i1 %a, %pos
  br i1 %heap, label %chk, label %nonheap
chk:
  %ts = load i32, ptr @march_gc_trace_state, align 4
  %off = icmp eq i32 %ts, -1
  br i1 %off, label %fast, label %slow
|}

let definition (orig, twin, kind) =
  match kind with
  | Inc ->
    Printf.sprintf {|define internal void @%s(ptr %%p) alwaysinline nounwind {
entry:
%sfast:
  %%old = atomicrmw add ptr %%p, i64 1 monotonic, align 8
  ret void
slow:
  call void @%s(ptr %%p)
  ret void
nonheap:
  ret void
}
|} twin heap_check orig
  | Dec helper ->
    Printf.sprintf {|define internal void @%s(ptr %%p) alwaysinline nounwind {
entry:
%sfast:
  %%rc = load atomic i64, ptr %%p monotonic, align 8
  %%hi = ashr i64 %%rc, %s
  %%imm = icmp sgt i64 %%hi, 0
  br i1 %%imm, label %%nonheap, label %%dec
dec:
  %%prev = atomicrmw sub ptr %%p, i64 1 acq_rel, align 8
  %%live = icmp sgt i64 %%prev, 1
  br i1 %%live, label %%nonheap, label %%last
last:
  call void @%s(ptr %%p, i64 %%prev)
  ret void
slow:
  call void @%s(ptr %%p)
  ret void
nonheap:
  ret void
}
|} twin heap_check immortal helper orig
  | DecFreed (nonheap_val, helper) ->
    Printf.sprintf {|define internal i64 @%s(ptr %%p) alwaysinline nounwind {
entry:
%sfast:
  %%rc = load atomic i64, ptr %%p monotonic, align 8
  %%hi = ashr i64 %%rc, %s
  %%imm = icmp sgt i64 %%hi, 0
  br i1 %%imm, label %%kept, label %%dec
dec:
  %%prev = atomicrmw sub ptr %%p, i64 1 acq_rel, align 8
  %%live = icmp sgt i64 %%prev, 1
  br i1 %%live, label %%kept, label %%last
last:
  call void @%s(ptr %%p, i64 %%prev)
  ret i64 1
slow:
  %%r2 = call i64 @%s(ptr %%p)
  ret i64 %%r2
kept:
  ret i64 0
nonheap:
  ret i64 %s
}
|} twin heap_check immortal helper orig nonheap_val

let declaration (orig, _, kind) =
  match kind with
  | Inc | Dec _ -> Printf.sprintf "declare void @%s(ptr)" orig
  | DecFreed _ -> Printf.sprintf "declare i64 @%s(ptr)" orig

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

(** Replace every [@orig(] in [line] with [@twin(]. *)
let rewrite_line (line : string) : string * string list =
  if starts_with "declare " line || starts_with "define " line then (line, [])
  else
    List.fold_left (fun (l, used) (orig, twin, _) ->
        let pat = "@" ^ orig ^ "(" in
        if not (String.length l >= String.length pat) then (l, used)
        else begin
          let buf = Buffer.create (String.length l) in
          let n = String.length l and m = String.length pat in
          let hit = ref false in
          let i = ref 0 in
          while !i < n do
            if !i + m <= n && String.sub l !i m = pat then begin
              Buffer.add_string buf ("@" ^ twin ^ "("); i := !i + m; hit := true
            end else begin
              Buffer.add_char buf l.[!i]; incr i
            end
          done;
          (Buffer.contents buf, if !hit then orig :: used else used)
        end) (line, []) entries

(* ── entry-block alloca hoisting ─────────────────────────────────────

   The emitter gives every let binding a stack slot ([%x.addr = alloca ptr]) at
   the point it is bound, inside case-arm and loop blocks. LLVM promotes a slot
   to a register only when it is in the function's ENTRY block; one anywhere
   else is a dynamic alloca that stays on the stack unless later passes happen
   to clean it up. Inlining the refcount twins splits blocks, so fewer of those
   cleanups fired, and frames grew: test/native/array_sort_by.march, whose
   ordered_and_stable recurses through a join-point closure (not a self tail
   call), went from 208 to 256 bytes per level and overflowed its 1 MiB green
   thread stack at 4,500 elements instead of ~6,000.

   Moving every fixed-size scalar slot to the entry block is the standard
   frontend rule, and sound here: such an alloca has no operand, its name is
   unique in the function, and every slot is stored before it is read. Only
   single scalar and pointer slots move. An aggregate or array alloca may be a
   stack-promoted object (Escape), where a fresh slot per loop iteration could
   matter, so those stay where they are. With hoisting the same recursion takes
   160 bytes per level. *)

let hoistable_alloca (line : string) : bool =
  let t = String.trim line in
  match String.index_opt t '=' with
  | None -> false
  | Some i ->
    String.length t > 0 && t.[0] = '%'
    && (let rhs = String.trim (String.sub t (i + 1) (String.length t - i - 1)) in
        List.exists (fun ty -> rhs = "alloca " ^ ty || starts_with ("alloca " ^ ty ^ ", align") rhs)
          [ "ptr"; "i64"; "i32"; "i16"; "i8"; "i1"; "double"; "float" ])

let is_label (line : string) : bool =
  String.length line > 1 && line.[String.length line - 1] = ':'
  && line.[0] <> ' ' && line.[0] <> ';'

(** Move each function's hoistable allocas to just after its entry label. *)
let hoist_allocas (lines : string list) : string list =
  let rec go acc = function
    | [] -> List.rev acc
    | l :: rest when starts_with "define " l ->
      (* Split off the body up to the closing brace. *)
      let rec take body = function
        | [] -> (List.rev body, [])
        | "}" :: tl -> (List.rev ("}" :: body), tl)
        | x :: tl -> take (x :: body) tl
      in
      let (body, after) = take [] rest in
      let hoisted = List.filter hoistable_alloca body in
      (* Only when EVERY alloca in the function is hoistable: hoisting the
         scalar slots of test/native/simd_mutual_tco.march's mutual-TCO
         dispatcher, which also allocates <4 x float> slots inside its loop,
         made it crash (SIGSEGV at 0x10), although no slot is type-punned and
         each slot class hoisted alone was fine. Until that is understood, a
         function with any dynamic aggregate/vector slot keeps its layout. *)
      let any_alloca = List.exists (fun b ->
          let t = String.trim b in
          match String.index_opt t '=' with
          | Some i -> starts_with "alloca " (String.trim (String.sub t (i + 1) (String.length t - i - 1)))
          | None -> false) body in
      let all_hoistable = List.for_all (fun b ->
          let t = String.trim b in
          match String.index_opt t '=' with
          | Some i when starts_with "alloca " (String.trim (String.sub t (i + 1) (String.length t - i - 1))) ->
            hoistable_alloca b
          | _ -> true) body in
      if hoisted = [] || not any_alloca || not all_hoistable then go (List.rev_append body (l :: acc)) after
      else begin
        let others = List.filter (fun b -> not (hoistable_alloca b)) body in
        (* The entry block is the body's first block: after its label when it
           opens with one, otherwise (an unnamed entry block) at the very top.
           Never after a LATER label, or uses in the entry block would precede
           the definition. *)
        let placed = match others with
          | first :: tl when is_label first -> first :: hoisted @ tl
          | _ -> hoisted @ others
        in
        go (List.rev_append placed (l :: acc)) after
      end
    | l :: rest -> go (l :: acc) rest
  in
  go [] lines

(** Rewrite a finished module. Returns it unchanged when it has no refcount
    calls at all. *)
let rewrite (ir : string) : string =
  let lines = hoist_allocas (String.split_on_char '\n' ir) in
  let used = Hashtbl.create 8 in
  let declared = Hashtbl.create 8 in
  let lines' = List.map (fun line ->
      List.iter (fun (orig, _, _) ->
          if starts_with ("declare void @" ^ orig ^ "(") line
          || starts_with ("declare i64 @" ^ orig ^ "(") line
          || starts_with ("declare i64  @" ^ orig ^ "(") line
          then Hashtbl.replace declared orig ()) entries;
      let (l, u) = rewrite_line line in
      List.iter (fun o -> Hashtbl.replace used o ()) u;
      l) lines in
  if Hashtbl.length used = 0 then String.concat "\n" lines'
  else begin
    let buf = Buffer.create (String.length ir + 4096) in
    Buffer.add_string buf (String.concat "\n" lines');
    Buffer.add_string buf "\n\n; ── inline refcount fast path (lib/tir/llvm_rc_inline.ml) ──\n";
    Buffer.add_string buf "@march_gc_trace_state = external global i32, align 4\n";
    Buffer.add_string buf "declare void @march_rc_last_atomic(ptr, i64)\n";
    Buffer.add_string buf "declare void @march_rc_last_local(ptr, i64)\n";
    List.iter (fun ((orig, _, _) as e) ->
        if Hashtbl.mem used orig then begin
          if not (Hashtbl.mem declared orig) then begin
            Buffer.add_string buf (declaration e); Buffer.add_char buf '\n'
          end;
          Buffer.add_string buf (definition e)
        end) entries;
    Buffer.contents buf
  end
