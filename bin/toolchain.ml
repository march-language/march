(** Toolchain plumbing for the March compiler driver.

    Three bands lifted verbatim out of [bin/main.ml] (Target A, task A1 of
    [specs/plans/2026-08-27-remaining-decomposition-targets.md]):

    - diagnostic rendering and the prelude-collision check;
    - executable / stdlib / runtime directory discovery and the stdlib
      AST cache ([load_stdlib]);
    - clang link flags, cross-compile sysroots and [ensure_runtime_so].

    None of it references a [main.ml] local, so it hoists as a block with no
    reordering.  [main.ml] reaches all of it through [open Toolchain]. *)

(* Decode URL-safe base64 (with or without padding) to bytes.
 * Returns Some bytes_string on success, None on invalid input. *)
(* Label a desugar diagnostic by its ACTUAL severity. Both desugar printers
   hardcoded "error:", which was harmless only while desugar emitted nothing but
   errors. It now also emits a warning (the redundant-CSRF-token one), and a
   warning printed as "error:" misleads people and any tooling that greps the
   output. The exit decision is unchanged -- it still keys off has_errors. *)
let severity_word (sev : March_errors.Errors.severity) : string =
  match sev with
  | March_errors.Errors.Error -> "error"
  | March_errors.Errors.Warning -> "warning"
  | March_errors.Errors.Hint -> "hint"

(* Reject a bare top-level function name shared between prelude.march and the
   entry module BEFORE the two decl lists are concatenated below (or, at the
   two other call sites, wherever the equivalent concatenation happens for
   that pipeline). Both are unwrapped into bare, unqualified declarations
   (see [load_stdlib_file] and [desugar_module]'s [~is_entry] default), and
   Prelude's own functions call each other unqualified, so an entry-module
   function sharing one of those names silently replaces it program-wide —
   confirmed to produce, depending on how the two definitions' types happen
   to line up: a misattributed runtime arity error, a compiled SIGBUS with no
   diagnostic, or a fully silent no-op. See
   specs/plans/2026-08-13-prelude-entry-fn-name-collision.md.

   [stdlib_decls] is the FULL concatenated stdlib list, not just prelude's —
   passing the whole thing is correct and not just convenient: every stdlib
   file other than prelude.march keeps its wrapping [DMod], so only
   prelude's members ever appear as a bare top-level [DFn] in this list; the
   checker is blind to everything else in it. *)
(* The compiler's own builtin-name tables — [print] and friends have NO
   corresponding March-source [DFn] anywhere (eval.ml injects them directly
   as [VBuiltin] values), so [Prelude_collision]'s DFn-vs-DFn check cannot
   see a collision with them on its own; it needs this list. Sourced from
   the SAME table the typechecker itself resolves ordinary builtin calls
   against, so this can never drift from what the compiler actually treats
   as a builtin. Sourced from [Typecheck.prelude_collision_builtin_names]/
   [Typecheck.prelude_collision_iface_arities] — the SAME shared values the
   LSP's own [lsp/lib/analysis.ml] uses, so the two can never independently
   drift from each other or from what the typechecker treats as a builtin. *)
let check_no_prelude_collision_decls ~(stdlib_decls : March_ast.Ast.decl list)
    (entry_decls : March_ast.Ast.decl list) : unit =
  let errors = March_errors.Errors.create () in
  March_modules.Prelude_collision.check ~prelude_decls:stdlib_decls
    ~ordinary_builtin_names:March_typecheck.Typecheck.prelude_collision_builtin_names
    ~iface_method_arities:March_typecheck.Typecheck.prelude_collision_iface_arities
    ~entry_decls errors;
  if March_errors.Errors.has_errors errors then begin
    List.iter (fun (d : March_errors.Errors.diagnostic) ->
        Printf.eprintf "%s:%d:%d: %s: %s\n"
          d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
          d.span.March_ast.Ast.start_col (severity_word d.severity) d.message
      ) (March_errors.Errors.sorted errors);
    exit 1
  end

let check_no_prelude_collision ~(stdlib_decls : March_ast.Ast.decl list)
    (entry : March_ast.Ast.module_) : unit =
  check_no_prelude_collision_decls ~stdlib_decls entry.March_ast.Ast.mod_decls

(* [find_substring ~needle haystack] returns the index of the first
   occurrence of [needle] in [haystack], or [None]. Small local helper so
   [dedupe_cap_hints] below doesn't reach for a regex library over one fixed
   marker string. *)
let find_substring ~needle haystack =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i =
    if i + nl > hl then None
    else if String.sub haystack i nl = needle then Some i
    else go (i + 1)
  in
  if nl = 0 then Some 0 else go 0

(* Presentation-only de-duplication of the capability diagnostics: the
   typechecker's Check 1b (lib/typecheck/typecheck.ml, an Error) and
   Cap_infer's call-site hint (lib/refinecheck/cap_infer.ml, a Hint) both
   name the same missing capability once Cap_infer's call-chain work landed
   — see specs/progress/2026-08-10-capability-diagnostic-duplication.md.
   Their "add `needs X`" clauses are now byte-for-byte redundant, but the
   hint's trailing "reached from `main`: …" chain is genuinely new
   information the error doesn't carry. So: when a Hint tagged
   `cap_needs:<cap>` names a capability already covered by an Error/Warning
   in the SAME module, trim the hint down to just the chain (dropping the
   now-redundant prefix); when there is no chain to show, drop the hint
   entirely rather than print a sentence that says nothing the error hasn't
   already said.

   Matching used to be exact-span-plus-exact-code equality, which relied on
   Check 1b emitting one error per (cap, call-site span) — an exact mirror
   of Cap_infer's own per-call hint. Task 5
   (specs/progress/2026-08-13-aggregate-missing-needs-diagnostics.md)
   collapsed Check 1b to ONE error per module, carrying every missing
   capability in a comma-joined `cap_needs:<c1>,<c2>,...` code and reporting
   only the FIRST offending span — so a hint for the SECOND (or later)
   offending capability no longer shares a span, or an exact code, with the
   error that already covers it, and survived as an orphan duplicate. Fixed
   by matching on capability-SET membership (parsed out of the comma-joined
   code, not re-derived) plus the owning module (parsed out of each
   message via a fixed marker, the same technique already used for the
   chain suffix below) rather than requiring the span or the whole code
   string to match exactly.

   Both passes are tagged via the `code` field (not by re-parsing each
   other's prose for the CAPABILITY) specifically so cap matching stays
   robust to independent wording changes on either side; the chain suffix is
   split off via [Cap_infer.chain_marker], the one constant Cap_infer
   exports for this purpose. The MODULE name still has to come from the
   message text (neither diagnostic carries a structured module field), via
   fixed markers scoped to each emitter's own known phrasing — the same
   "parse via anchor, not by guessing" discipline the chain marker already
   established, just applied to a second anchor.

   This is deliberately scoped to THIS file: it changes only what the
   combined single-file compiler pipeline renders. [Cap_infer.check_module]
   itself is untouched and keeps emitting the hint's full text
   unconditionally — its direct-call unit tests in test/test_compiler.ml
   pin exactly that standalone contract for any caller (e.g. tooling that
   runs Cap_infer without this file's Check 1b) that invokes it without
   going through this pipeline. *)
let dedupe_cap_hints (diags : March_errors.Errors.diagnostic list)
    : March_errors.Errors.diagnostic list =
  let module E = March_errors.Errors in
  let cap_needs_code (d : E.diagnostic) =
    match d.E.code with
    | Some c when String.length c > 10 && String.sub c 0 10 = "cap_needs:" -> Some c
    | _ -> None
  in
  let caps_of_code code =
    let rest = String.sub code 10 (String.length code - 10) in
    String.split_on_char ',' rest
  in
  (* The text right after [marker] up to the next backtick, e.g.
     [name_after ~marker:"bodies in `" "function bodies in `M` call ..."]
     is ["M"]. Returns [None] if [marker] isn't found or isn't followed by a
     closing backtick — deliberately conservative: a missed match just means
     the hint isn't suppressed, never a wrong suppression. *)
  let name_after ~marker message =
    match find_substring ~needle:marker message with
    | None -> None
    | Some i ->
      let start = i + String.length marker in
      let rest = String.sub message start (String.length message - start) in
      (match find_substring ~needle:"`" rest with
       | Some j -> Some (String.sub rest 0 j)
       | None -> None)
  in
  (* Check 1b's aggregated error: "function bodies in `M` call builtins
     that require ...". Check 1's per-Cap(X)-parameter error: "`Cap(X)` used
     in module `M` but ...". Both anchors are tried in turn — a diagnostic's
     message matches at most one of them. *)
  let error_module (d : E.diagnostic) =
    match name_after ~marker:"bodies in `" d.E.message with
    | Some m -> Some m
    | None -> name_after ~marker:"used in module `" d.E.message
  in
  (* Cap_infer's hint: "call to `f` requires `needs X` — add `needs X` to
     module `M`...". *)
  let hint_module (d : E.diagnostic) = name_after ~marker:"to module `" d.E.message in
  (* Every (module, capability) pair already covered by some Error/Warning
     in the diagnostic list. *)
  let strong_caps : (string * string) list =
    List.concat_map (fun (d : E.diagnostic) ->
        match d.E.severity, cap_needs_code d with
        | (E.Error | E.Warning), Some code ->
          (match error_module d with
           | Some m -> List.map (fun c -> (m, c)) (caps_of_code code)
           | None -> [])
        | _ -> [])
      diags
  in
  List.filter_map
    (fun (d : E.diagnostic) ->
       match d.E.severity, cap_needs_code d with
       | E.Hint, Some code ->
         let covered =
           (* [cap_subsumes parent child]: the ERROR's capability is the
              parent (it's the broader `needs` a fix would add), the HINT's
              capability is the child (the narrower one the call actually
              triggers) — e.g. an error covering `IO` subsumes a hint for
              `IO.FileWrite`. Getting this backwards would suppress hints
              for capabilities the error does NOT actually cover. *)
           match caps_of_code code, hint_module d with
           | [ hint_cap ], Some m ->
             List.exists
               (fun (em, error_cap) ->
                  em = m && March_caps.Cap_lattice.cap_subsumes error_cap hint_cap)
               strong_caps
           | _ -> false
         in
         if not covered then Some d
         else begin
           let marker = March_refinecheck.Cap_infer.chain_marker in
           match find_substring ~needle:marker d.E.message with
           | Some i ->
             let chain_start = i + String.length marker in
             let chain =
               String.sub d.E.message chain_start
                 (String.length d.E.message - chain_start)
             in
             Some { d with E.message = "reached from `main`: " ^ chain }
           | None -> None
         end
       | _ -> Some d)
    diags

let b64_decode_pubkey b64 =
  let tbl = Array.make 256 (-1) in
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=" in
  String.iteri (fun i c -> tbl.(Char.code c) <- i) chars;
  let s = String.map (function '-' -> '+' | '_' -> '/' | c -> c) b64 in
  let s = match String.length s mod 4 with
    | 2 -> s ^ "=="
    | 3 -> s ^ "="
    | _ -> s in
  let n = String.length s in
  if n = 0 || n mod 4 <> 0 then None
  else begin
    let buf = Buffer.create (n / 4 * 3) in
    let ok = ref true in
    let i = ref 0 in
    while !i < n && !ok do
      let v0 = tbl.(Char.code s.[!i]) in
      let v1 = tbl.(Char.code s.[!i+1]) in
      let v2 = tbl.(Char.code s.[!i+2]) in
      let v3 = tbl.(Char.code s.[!i+3]) in
      if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0 then ok := false
      else begin
        Buffer.add_char buf (Char.chr ((v0 lsl 2) lor (v1 lsr 4)));
        if s.[!i+2] <> '=' then
          Buffer.add_char buf (Char.chr (((v1 land 0xf) lsl 4) lor (v2 lsr 2)));
        if s.[!i+3] <> '=' then
          Buffer.add_char buf (Char.chr (((v2 land 0x3) lsl 6) lor v3))
      end;
      i := !i + 4
    done;
    if not !ok then None
    else begin
      let bytes = Buffer.contents buf in
      if String.length bytes <> 32 then None
      else begin
        let hex = String.concat "" (List.init 32 (fun j ->
          Printf.sprintf "%02x" (Char.code bytes.[j]))) in
        Some hex
      end
    end
  end

(** Create [dir] and every missing parent, ignoring races.

    [Unix.mkdir] is NOT recursive, and every cache-writing site here catches
    only [EEXIST].  So on a machine — or under a HOME override — where
    [~/.cache] does not already exist, [ENOENT] on the missing parent escaped
    to the enclosing handler and SILENTLY DISABLED the cache: a
    "could not save the stdlib typecheck cache" warning ahead of the program's
    own output (which also corrupted [--emit-core-ast]'s one-document contract)
    and a full stdlib re-parse and re-typecheck on every single invocation.
    See specs/progress/2026-08-27-stdlib-cache-mkdir-not-recursive.md.

    [EEXIST] is ignored rather than pre-checked because the cache directory is
    shared across concurrent sessions: two racing processes must both succeed.
    Any other error is left to the caller's handler — a cache that genuinely
    cannot be created should still degrade to "no cache", not crash. *)
let rec mkdir_p (dir : string) : unit =
  if dir <> "" && dir <> "/" && dir <> Filename.current_dir_name
     && not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(* ------------------------------------------------------------------ *)
(* Stdlib loader                                                       *)
(* ------------------------------------------------------------------ *)

(** Resolve an executable name to an absolute path.
    If the name already contains a slash it is used as-is (after resolving
    relative to CWD).  Otherwise PATH is searched.  Falls back to the raw
    name if nothing is found. *)
let resolve_exe_path name =
  if String.contains name '/' then
    (* relative or absolute path — resolve against CWD *)
    if String.length name > 0 && name.[0] = '/' then name
    else Filename.concat (Sys.getcwd ()) name
  else begin
    let path_dirs =
      match Sys.getenv_opt "PATH" with
      | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
      | Some p -> String.split_on_char ':' p
    in
    match List.find_opt (fun d ->
        let p = Filename.concat d name in
        Sys.file_exists p && not (Sys.is_directory p)
      ) path_dirs with
    | Some d -> Filename.concat d name
    | None   -> name
  end

(** A real stdlib directory always contains [prelude.march] (every
    [stdlib_file_list] below starts with it). Gating on that, rather than
    just "a directory with this name exists", avoids a false match on an
    unrelated same-named directory — e.g. `test/stdlib/` holds the stdlib
    test suite's `test_*.march` fixtures, not the real stdlib, and a bare
    [Sys.file_exists] can't tell them apart when the compiler is invoked
    with CWD = `test/`. *)
let looks_like_stdlib_dir d =
  Sys.file_exists d && Sys.is_directory d
  && Sys.file_exists (Filename.concat d "prelude.march")

(** Locate the stdlib directory.
    Resolution order:
    1. MARCH_STDLIB environment variable (explicit override)
    2. Paths relative to the resolved march executable:
       - bin/../stdlib          (source-tree / opam switch layout)
       - bin/../../stdlib       (nested build layout)
       - bin/../../../stdlib    (dune's _build/default/bin/ layout, exe invoked
                                  with a CWD other than the project root)
       - bin/../share/march/stdlib  (installed share layout)
    3. "stdlib" relative to CWD (works when running from the March repo root) *)
let find_stdlib_dir () =
  match Sys.getenv_opt "MARCH_STDLIB" with
  | Some p when Sys.file_exists p -> Some p
  | _ ->
    let exe_path = resolve_exe_path Sys.executable_name in
    let exe_dir  = Filename.dirname exe_path in
    let candidates = [
      (* Exe-relative candidates — work regardless of CWD *)
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
      Filename.concat exe_dir "../../../stdlib";
      (* Installed share layout: bin/../share/march/stdlib or bin/../share/march *)
      Filename.concat exe_dir "../share/march/stdlib";
      Filename.concat exe_dir "../share/march";
      (* CWD-relative fallback — works when invoked from the March repo root *)
      "stdlib";
    ] in
    List.find_opt looks_like_stdlib_dir candidates

(** A file that is itself part of the compiler's OWN shipped standard
    library (e.g. `stdlib/list.march`) legitimately defines top-level names
    -- `reverse`, `to_string`, and others -- that match Prelude's
    internally-called set. That's only a real collision when the file is
    loaded as a NAMESPACED dependency (`List.reverse`, never flattened) is
    NOT what's happening -- and the one case where it isn't is invoking the
    compiler directly on a stdlib source file's own path, which flattens it
    as the entry (see [check_no_prelude_collision] below) purely as an
    artifact of the single-file CLI contract. No real user's own entry file
    ever lives under the compiler's own stdlib directory, so skipping the
    check exactly there costs no real coverage. (Concretely: CI's
    `--refine-report` obligation-count ratchet runs `--check
    stdlib/list.march` directly to measure the stdlib's own contract
    surface, and `List`'s real `reverse`/`fold_left` would otherwise trip
    the same collision this file's own internal calls rely on being
    intentional, not a bug.) *)
(* Matched by BASENAME against the stdlib manifest, not by resolving
   [filename]'s directory against [find_stdlib_dir]'s result: the compiler
   binary resolves its OWN stdlib exe-relative (typically a staged
   `_build/default/stdlib` copy), which does not share a physical directory
   with a source-tree-relative CLI argument like `stdlib/list.march` even
   though both name the same module — confirmed live, the path-comparison
   version of this check never fired for exactly that reason. The manifest
   (`Stdlib_manifest.all_known`) is the authoritative "is this a real
   shipped stdlib module" answer regardless of which copy's directory it
   was actually read from. *)
let is_shipped_stdlib_file filename =
  List.mem (Filename.basename filename) March_modules.Stdlib_manifest.all_known

(** Locate a file under the project's `runtime/` directory (e.g.
    "march_runtime.c"), independent of CWD.
    Mirrors [find_stdlib_dir]'s exe-relative resolution order:
      1. bin/../runtime/<name>        (source-tree / opam switch layout)
      2. bin/../../runtime/<name>     (nested build layout)
      3. bin/../../../runtime/<name>  (dune's _build/default/bin/ layout,
                                        exe invoked with a CWD other than
                                        the project root)
      4. runtime/<name> relative to CWD (works when running from the repo root)
    Every call site previously tried only (2)+(3)+CWD-relative, which meant
    the exe-relative candidates never covered the actual `_build/default/bin/
    main.exe` layout dune produces — resolvable only via the CWD-relative
    fallback, so a `march --compile` invoked from any other directory failed
    with "cannot find runtime/march_runtime.c" even though the sources were
    right there, three levels up from the exe.

    [runtime_dir] resolves the directory ONCE (anchored on march_runtime.c) and
    hands it to the CAS via [Cas.set_runtime_dir], so the cache key digests the
    very sources this process compiles.  Before that, cas.ml resolved its own
    candidate list cwd-FIRST: with cwd at the repo root and the exe under
    _build/default/bin/, the key digested ./runtime/*.c while clang compiled
    _build/default/runtime/*.c, and editing a runtime source could print
    `compiled <out> (cached)` for a binary containing none of the new code.
    MARCH_RUNTIME_DIR overrides the search, mirroring MARCH_STDLIB. *)
let runtime_dir : string option Lazy.t = lazy (
  let candidates =
    match Sys.getenv_opt "MARCH_RUNTIME_DIR" with
    | Some d when d <> "" -> [d]
    | _ ->
      let exe_dir = Filename.dirname (resolve_exe_path Sys.executable_name) in
      [ Filename.concat exe_dir "../runtime";
        Filename.concat exe_dir "../../runtime";
        Filename.concat exe_dir "../../../runtime";
        "runtime" ]
  in
  let dir =
    List.find_opt
      (fun d -> Sys.file_exists (Filename.concat d "march_runtime.c"))
      candidates
  in
  (match dir with
   | Some d -> March_cas.Cas.set_runtime_dir d
   | None -> ());
  dir)

let find_runtime_file name =
  let in_runtime_dir =
    match Lazy.force runtime_dir with
    | Some d ->
      let p = Filename.concat d name in
      if Sys.file_exists p then Some p else None
    | None -> None
  in
  match in_runtime_dir with
  | Some _ as found -> found
  | None ->
    (* The resolved directory does not hold this particular file (e.g. a JS
       runtime .mjs shipped in a different layout) — fall back to the original
       per-name scan rather than failing. *)
    let exe_dir = Filename.dirname (resolve_exe_path Sys.executable_name) in
    List.find_opt Sys.file_exists [
      Filename.concat exe_dir (Filename.concat "../runtime" name);
      Filename.concat exe_dir (Filename.concat "../../runtime" name);
      Filename.concat exe_dir (Filename.concat "../../../runtime" name);
      Filename.concat "runtime" name;
    ]

(** Parse a stdlib source file and return its top-level declarations.
    Each stdlib file is a single [mod Name do ... end] wrapper.
    - For "prelude.march": the inner declarations are returned directly,
      so they land in the user module's top-level scope.
    - For all other files: the whole [DMod] is returned, so the module
      is accessible as e.g. [Option.is_some]. *)
let load_stdlib_file path =
  let src =
    try
      let ic = open_in path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    with Sys_error _ -> ""
  in
  if src = "" then []
  else
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    (try
       let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let basename = Filename.basename path in
       (* prelude.march's own members are unwrapped into global scope below
          (matching TIR's entry-module unwrapping), so its bare intra-module
          calls must NOT be qualified with "Prelude." — is_entry:true (the
          default) keeps them bare, consistent with every other file. Every
          other stdlib file keeps its own top-level mod name as part of every
          member's qualified name (Module.member), so is_entry:false here. *)
       let m = March_desugar.Desugar.desugar_module
                 ~is_entry:(basename = "prelude.march") m in
       if basename = "prelude.march" then
         (* Unwrap the outer mod so prelude functions are in global scope *)
         (match m.March_ast.Ast.mod_decls with
          | [March_ast.Ast.DMod (_, _, inner_decls, _)] -> inner_decls
          | decls -> decls)
       else
         (* Wrap in a DMod so names are accessible as Module.name *)
         [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                              March_ast.Ast.Public,
                              m.March_ast.Ast.mod_decls,
                              March_ast.Ast.dummy_span)]
     with
     | March_parser.Parser.Error ->
       let pos = Lexing.lexeme_start_p lexbuf in
       Printf.eprintf "[stdlib] parse error in %s at line %d col %d\n%!"
         path pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
       []
     | exn ->
       Printf.eprintf "[stdlib] error in %s: %s\n%!" path (Printexc.to_string exn); [])

(* The manifest moved to lib/modules/stdlib_manifest.ml so a test can assert it
   is exhaustive over stdlib/ — a file missing from it miscompiles silently at a
   concrete niche-eligible type.  See that module's header. *)
let stdlib_file_list = March_modules.Stdlib_manifest.stdlib_file_list

(** Stdlib modules only loaded for --target js builds.
    These have externs with no native C symbols, so including them in native/JIT
    builds would cause dlopen(RTLD_NOW) to fail at link time. *)
let js_only_stdlib_file_list = March_modules.Stdlib_manifest.js_only_stdlib_file_list

(** Read all stdlib source files and compute a hash of their contents.
    Returns (stdlib_dir, source_hash, file_paths). *)
let stdlib_source_hash ?(for_js=false) () =
  match find_stdlib_dir () with
  | None -> None
  | Some stdlib_dir ->
    let file_list =
      if for_js then stdlib_file_list @ js_only_stdlib_file_list
      else stdlib_file_list
    in
    let paths = List.map (Filename.concat stdlib_dir) file_list in
    let buf = Buffer.create (256 * 1024) in
    List.iter (fun path ->
      try
        let ic = open_in path in
        let n = in_channel_length ic in
        let bytes = Bytes.create n in
        really_input ic bytes 0 n;
        close_in ic;
        Buffer.add_bytes buf bytes
      with Sys_error _ -> ()
    ) paths;
    let hash = Digest.to_hex (Digest.string (Buffer.contents buf)) in
    Some (stdlib_dir, hash, paths)

(** Load all stdlib modules and return their declarations, to be
    prepended to the user module before evaluation.
    Uses a content-hash-keyed cache of parsed+desugared ASTs. *)
let load_stdlib ?(for_js=false) () =
  let file_list =
    if for_js then stdlib_file_list @ js_only_stdlib_file_list
    else stdlib_file_list
  in
  match stdlib_source_hash ~for_js () with
  | None -> []
  | Some (stdlib_dir, source_hash, _) ->
    let home = (try Sys.getenv "HOME" with Not_found -> ".") in
    let cache_dir = Filename.concat home ".cache/march" in
    let short_hash = String.sub source_hash 0 16 in
    (* The compiler's own identity is part of the key.  This blob is a
       Marshal of March_ast.Ast.decl list: if the AST type changes shape while
       the stdlib SOURCE does not, a content-only key still hits, and
       unmarshalling a stale blob into the new type is undefined behaviour —
       observed as a SIGSEGV on every input, with no diagnostic. *)
    let build_id = String.sub (Lazy.force March_cas.Cas.compiler_identity) 0 12 in
    let cache_path = Filename.concat cache_dir
      ("stdlib_ast_" ^ build_id ^ "_" ^ short_hash ^ ".bin") in
    (* Cache hit: unmarshal parsed ASTs *)
    match (try
      if Sys.file_exists cache_path then begin
        let ic = open_in_bin cache_path in
        let data : March_ast.Ast.decl list = Marshal.from_channel ic in
        close_in ic;
        Some data
      end else None
    with _ -> None) with
    | Some decls -> decls
    | None ->
      (* Cache miss: parse all files, then cache *)
      let decls = List.concat_map (fun name ->
          load_stdlib_file (Filename.concat stdlib_dir name)
        ) file_list in
      (try
        mkdir_p cache_dir;
        (* Write-to-temp + rename: the cache dir is shared across concurrent
           sessions; a reader must never see a half-written Marshal blob. *)
        let tmp = Printf.sprintf "%s.%d.tmp" cache_path (Unix.getpid ()) in
        let oc = open_out_bin tmp in
        Marshal.to_channel oc decls [];
        close_out oc;
        Sys.rename tmp cache_path
      with _ -> ());
      decls

(* clang cflags/libs to make libblake3 linkable into the runtime. These come
   from March_cas.Blake3_flags, generated by lib/cas/discover.ml's dune
   configurator probe — the SAME probe the OCaml FFI stubs in lib/cas use
   (pkg-config tier, static-archive-on-macOS preference, toolchain-based
   macOS detection, bare -lblake3 fallback). Sharing one generated module
   makes it impossible for this link path and the lib/cas link path to
   silently diverge. Used to compile+link runtime/march_blake3.c (see
   march_blake3.h) so march_reload.c can recompute cap_root with the same
   BLAKE3 algorithm the compiler uses (March_cas.Blake3, Phase5C-A). Only
   needed on the paths that link march_reload.c (i.e. not --compile-so
   patches). *)
let blake3_link_flags () =
  let flags = March_cas.Blake3_flags.cflags @ March_cas.Blake3_flags.libs in
  match flags with
  | [] -> ""
  | _ -> " " ^ String.concat " " flags

(* ── Cross-compile target sysroot (OpenSSL/TLS + zlib/gzip) ─────────────────
   A cross Linux main binary CANNOT defer undefined symbols the way a .so can,
   so the cross-linker needs TARGET copies of libssl/libcrypto/libz (+ headers)
   at link time — not just at runtime.  These live in a per-arch cache populated
   by scripts/fetch-cross-sysroot.sh, extracted from Debian bookworm packages so
   the soname/ABI matches the deploy image (debian:bookworm-slim).  See
   specs/2026-07-04-cross-compile-linux-hot-deploy-design.md §5. *)

(** The cache/override directory that holds a target sysroot for [arch]
    ("amd64" | "arm64").  Resolution order:
      1. MARCH_CROSS_SYSROOT_<ARCH>  (arch-specific override)
      2. MARCH_CROSS_SYSROOT         (single dir — used as-is for the built arch)
      3. ~/.cache/march/cross-sysroot/linux-<arch>  (fetch-script cache)
    Returns the first directory that both exists and contains lib/libssl.so.3
    (a well-formed sysroot), else None. *)
let cross_sysroot_dir (arch : string) : string option =
  let well_formed d =
    Sys.file_exists (Filename.concat d "lib/libssl.so.3")
    && Sys.file_exists (Filename.concat d "lib/libcrypto.so.3")
    && Sys.file_exists (Filename.concat d "lib/libz.so.1")
    && Sys.file_exists (Filename.concat d "include/openssl/ssl.h")
  in
  let candidates =
    let upper = String.uppercase_ascii arch in
    (match Sys.getenv_opt ("MARCH_CROSS_SYSROOT_" ^ upper) with
     | Some d -> [d] | None -> [])
    @ (match Sys.getenv_opt "MARCH_CROSS_SYSROOT" with
       | Some d -> [d] | None -> [])
    @ (let home = (try Sys.getenv "HOME" with Not_found -> ".") in
       [Filename.concat home
          (Printf.sprintf ".cache/march/cross-sysroot/linux-%s" arch)])
  in
  List.find_opt well_formed candidates

(** Short digest of a sysroot's three .so files (by content), folded into the CAS
    key so re-fetching a different OpenSSL/zlib version invalidates cached cross
    binaries.  Empty string if the sysroot is missing (the build errors out
    before caching anyway). *)
let cross_sysroot_digest (dir : string) : string =
  let buf = Buffer.create 64 in
  List.iter (fun so ->
      let p = Filename.concat dir ("lib/" ^ so) in
      (try Buffer.add_string buf (Digest.to_hex (Digest.file p))
       with _ -> ()))
    ["libssl.so.3"; "libcrypto.so.3"; "libz.so.1"];
  String.sub (Digest.to_hex (Digest.string (Buffer.contents buf))) 0 12

(** arch string ("amd64"/"arm64") for a LinuxGnu target, for sysroot lookup. *)
let linux_arch_str = function
  | March_tir.Llvm_emit.(LinuxGnu { arch = X86_64; _ }) -> Some "amd64"
  | March_tir.Llvm_emit.(LinuxGnu { arch = Arm64; _ })  -> Some "arm64"
  | _ -> None

(* Every cached .so in ~/.cache/march is compiled to a pid-suffixed temp and
   renamed into place.  On macOS the linker stamps LC_ID_DYLIB with the path
   the file was BUILT at, i.e. the now-deleted "<name>.<pid>.tmp" — and every
   later dylib linked against it records that dead path as its dependency, so
   a fresh process can no longer dlopen the dependent (the JIT stdlib prelude
   silently fell back to a full recompile on every REPL/--jit start).  Stamp
   the ID with the path the file actually lands at instead.  Linux ld records
   the link-line path (or DT_SONAME) and needs nothing here.

   -Xlinker rather than -Wl,: clang splits a -Wl, argument on COMMAS, so a
   cache path containing one (a home directory named "Doe, J", say) would be
   torn into two bogus linker arguments and fail the link outright. *)
let install_name_flag (final_path : string) : string =
  if Sys.file_exists "/System/Library/CoreServices"
  then Printf.sprintf " -Xlinker -install_name -Xlinker %s"
         (Filename.quote final_path)
  else ""

(** Pre-compile the C runtime to a shared library.
    Cached at ~/.cache/march/libmarch_runtime_<hash>.so, where <hash> covers
    every C source/header that goes into the build plus the clang flags.

    The cache directory is SHARED across worktrees and concurrent sessions,
    so the artifact name must be a pure function of its inputs and the write
    must be atomic (compile to a pid-suffixed temp, then rename).  The old
    scheme — one fixed "libmarch_runtime.so" invalidated by the mtime of
    march_runtime.c alone — let two worktrees with diverged runtimes
    ping-pong overwrite each other's binary (ABI mismatch → wrong symbols →
    hangs/crashes in whichever session dlopen'd the other's build), and a
    reader could dlopen a half-written .so mid-compile.
    Returns the path to the .so. *)
let ensure_runtime_so () =
  let home = Sys.getenv "HOME" in
  let dot_cache = Filename.concat home ".cache" in
  let cache_dir = Filename.concat dot_cache "march" in
  (* Create parent directories recursively *)
  mkdir_p cache_dir;
  (* Find runtime source *)
  let runtime_c_opt = find_runtime_file "march_runtime.c" in
  match runtime_c_opt with
  | None ->
    (* No sources (e.g. installed binary without a source tree): fall back
       to the newest cached runtime .so from a previous run, if any. *)
    let cached =
      (try Sys.readdir cache_dir with Sys_error _ -> [||])
      |> Array.to_list
      |> List.filter (fun f ->
          String.length f > 16
          && String.sub f 0 16 = "libmarch_runtime"
          && Filename.check_suffix f ".so")
      |> List.map (Filename.concat cache_dir)
      |> List.sort (fun a b ->
          compare (Unix.stat b).Unix.st_mtime (Unix.stat a).Unix.st_mtime)
    in
    (match cached with
     | newest :: _ -> newest
     | [] -> failwith "march: cannot find runtime/march_runtime.c")
  | Some runtime_c ->
    let runtime_dir = Filename.dirname runtime_c in
    (* Note: -lpthread not needed on macOS (pthreads are in libSystem). *)
    let http_c     = Filename.concat runtime_dir "march_http.c" in
    let extras_c   = Filename.concat runtime_dir "march_extras.c" in
    let compress_c = Filename.concat runtime_dir "march_compress.c" in
    let opt_file f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
    let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
    let ffi_c     = Filename.concat runtime_dir "march_ffi.c" in
    let sha1_c    = Filename.concat runtime_dir "sha1.c" in
    let base64_c  = Filename.concat runtime_dir "base64.c" in
    let extra_files =
      (if Sys.file_exists http_c then
        let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
        let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
        let io_c      = Filename.concat runtime_dir "march_http_io.c" in
        let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
        let tls_c     = Filename.concat runtime_dir "march_tls.c" in
        Printf.sprintf " %s %s %s%s%s%s%s%s%s%s%s" http_c sha1_c base64_c
          (opt_file simd_c) (opt_file sched_c) (opt_file resp_c)
          (opt_file io_c) (opt_file evloop_c) (opt_file tls_c) (opt_file extras_c)
          (opt_file compress_c)
      else
        (* march_extras.c unconditionally references base64_encode (base64.c) and
           sha1 (sha1.c), so they must be linked whenever march_extras.c is —
           independent of the HTTP stack. Without this, a build tree that has
           march_extras.c but not march_http.c (e.g. a native test rule that
           lists extras as a dep but not http) fails to link with undefined
           _base64_encode / _sha1. opt_file-guarded so absent files are skipped. *)
        Printf.sprintf "%s%s%s%s%s" (opt_file sched_c) (opt_file extras_c)
          (opt_file compress_c) (opt_file base64_c) (opt_file sha1_c))
      ^ (opt_file ffi_c)
      ^ (opt_file (Filename.concat runtime_dir "march_dispatch.c"))  (* HCR dispatch table *)
      ^ (opt_file (Filename.concat runtime_dir "march_reload.c"))    (* HCR reload server *)
      ^ (opt_file (Filename.concat runtime_dir "march_blake3.c"))    (* BLAKE3 for server-side cap_root recompute *)
      ^ (opt_file (Filename.concat runtime_dir "march_cap_lattice.c")) (* cap subsumption/normalize for ACTIVATE4 admission *)
      ^ (opt_file (Filename.concat runtime_dir "march_ctx_escape.c"))  (* ~H contextual escapers; referenced by march_extras.c *)
      ^ (opt_file (Filename.concat runtime_dir "march_remote_registry.c"))  (* L4 remote registry *)
      ^ (opt_file (Filename.concat runtime_dir "march_monitor_registry.c")) (* dist monitor registry *)
    in
    (* OpenSSL flags: needed when march_tls.c is included. *)
    let tls_c = Filename.concat runtime_dir "march_tls.c" in
    let openssl_flags =
      if not (Sys.file_exists tls_c) then ""
      else
        let dirs = [
          "/opt/homebrew/opt/openssl@3";
          "/opt/homebrew/opt/openssl";
          "/usr/local/opt/openssl@3";
          "/usr/local/opt/openssl";
          "/usr/include/openssl";
        ] in
        let found = List.fold_left (fun acc d ->
          match acc with
          | Some _ -> acc
          | None ->
            let hdr = Filename.concat d "include/openssl/ssl.h" in
            if Sys.file_exists hdr then Some d else None
        ) None dirs in
        match found with
        | Some d ->
          Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
        | None ->
          (* Try pkg-config *)
          if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0 then
            " -lssl -lcrypto"
          else ""
    in
    let evloop_flag =
      let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
      (* Event-loop HTTP server is opt-in: it runs handlers on non-blocking
         loop threads that cannot perform blocking I/O (e.g. a synchronous DB
         connect), which hangs DB-backed apps. Default to thread-per-connection
         (blocking sockets, works on any worker thread); set MARCH_HTTP_EVLOOP=1
         to opt back into the event-loop server. *)
      if Sys.file_exists evloop_c
         && (try Sys.getenv "MARCH_HTTP_EVLOOP" = "1" with Not_found -> false)
      then " -DMARCH_HTTP_USE_EVLOOP" else ""
    in
    (* Compression flags: always link -lz (system zlib), optionally zstd/brotli *)
    let compress_flags =
      if not (Sys.file_exists compress_c) then ""
      else begin
        let zstd_flags =
          if Sys.file_exists "/opt/homebrew/include/zstd.h" then
            " -DMARCH_HAVE_ZSTD -I/opt/homebrew/include -L/opt/homebrew/lib -lzstd"
          else if Sys.file_exists "/usr/include/zstd.h" then
            " -DMARCH_HAVE_ZSTD -lzstd"
          else ""
        in
        let brotli_flags =
          if Sys.file_exists "/opt/homebrew/include/brotli/encode.h" then
            " -DMARCH_HAVE_BROTLI -I/opt/homebrew/include -L/opt/homebrew/lib -lbrotlienc -lbrotlidec"
          else if Sys.file_exists "/usr/include/brotli/encode.h" then
            " -DMARCH_HAVE_BROTLI -lbrotlienc -lbrotlidec"
          else ""
        in
        Printf.sprintf " -lz%s%s" zstd_flags brotli_flags
      end
    in
    let so_dbg_flag = if Sys.getenv_opt "MARCH_DEBUG_RUNTIME" <> None then " -g" else "" in
    let so_san_flag =
      if Sys.getenv_opt "MARCH_SANITIZE" <> None then " -fsanitize=address,undefined" else ""
    in
    (* BLAKE3 flags: needed when march_blake3.c is included (links alongside
       march_reload.c so the reload server can recompute cap_root). *)
    let blake3_c = Filename.concat runtime_dir "march_blake3.c" in
    let blake3_flags = if Sys.file_exists blake3_c then blake3_link_flags () else "" in
    (* Content key: digests of every C input (the .c files named in the
       command plus every header in runtime/) and the full flag string.
       Identical inputs across worktrees share one artifact; any divergence
       gets its own filename instead of overwriting a shared one. *)
    let flags_sig = Printf.sprintf
      "clang -shared -O2 -fno-strict-aliasing -fwrapv -fPIC -msse4.2 -Wno-unused-command-line-argument%s%s%s -I%s %s%s%s%s%s"
      evloop_flag so_dbg_flag so_san_flag runtime_dir runtime_c extra_files openssl_flags compress_flags blake3_flags in
    let key_buf = Buffer.create 256 in
    Buffer.add_string key_buf flags_sig;
    (* Not part of [flags_sig] itself: the -install_name argument is the .so
       path, which is derived from this very key.  Version-stamp it instead so
       caches built before the fix (whose LC_ID_DYLIB is a dead .tmp path) get
       a new key and are rebuilt rather than silently reused. *)
    Buffer.add_string key_buf "|install_name=v1";
    let c_inputs =
      runtime_c ::
      (String.split_on_char ' ' extra_files
       |> List.filter (fun s -> s <> "" && Filename.check_suffix s ".c")) in
    let h_inputs =
      (try Sys.readdir runtime_dir with Sys_error _ -> [||])
      |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".h")
      |> List.sort String.compare
      |> List.map (Filename.concat runtime_dir) in
    List.iter (fun p ->
        Buffer.add_string key_buf p;
        try Buffer.add_string key_buf (Digest.to_hex (Digest.file p))
        with Sys_error _ -> ())
      (c_inputs @ h_inputs);
    let key = String.sub (Digest.to_hex (Digest.string (Buffer.contents key_buf))) 0 16 in
    let so_path = Filename.concat cache_dir ("libmarch_runtime_" ^ key ^ ".so") in
    if not (Sys.file_exists so_path) then begin
      (* Compile to a pid-suffixed temp and rename into place: rename(2) is
         atomic on the same filesystem, so a concurrent session can never
         dlopen a half-written .so, and same-key racers converge on
         identical bytes regardless of who wins the rename. *)
      let tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
      let cmd = Printf.sprintf "%s%s -o %s 2>&1"
        flags_sig (install_name_flag so_path) tmp in
      let rc = Sys.command cmd in
      if rc <> 0 then begin
        (try Sys.remove tmp with Sys_error _ -> ());
        failwith (Printf.sprintf "march: failed to compile runtime .so (clang exit %d)" rc)
      end;
      (try Sys.rename tmp so_path
       with Sys_error _ -> (try Sys.remove tmp with Sys_error _ -> ()))
    end;
    so_path