(** forge.toml lookup for the LSP: finds the project a file belongs to and the
    library directories its imports resolve against. Dependency resolution is
    forge's own ([March_forge.Cmd_build.lib_paths]), so the editor sees
    exactly the modules [forge build] compiles against. *)

(** Walk up from [start_dir] looking for a directory that contains
    [forge.toml].  Returns the directory path (the project root), or [None]
    if none is found before reaching the filesystem root. *)
let find_forge_root start_dir =
  let rec search d =
    let candidate = Filename.concat d "forge.toml" in
    if Sys.file_exists candidate then Some d
    else
      let parent = Filename.dirname d in
      if parent = d then None
      else search parent
  in
  search start_dir

(** All lib paths for a project root: the transitive dependency lib dirs
    (dev scope), the project's own [lib/] (and its subdirectories),
    [.forge/generated/] and [config/] -- the [MARCH_LIB_PATH] that
    [forge build] compiles under.

    This used to be a second, hand-written resolver that had drifted from
    forge's: it ignored forge.lock, so a git dep resolved to the whole
    version-keyed container [~/.march/cas/deps/<name>] (which has no [lib/]
    since 2026-09-12), and EVERY cached version of the dep, with its [test/]
    and [priv/] trees, landed on the path. Registry and transitive deps were
    missing altogether
    (specs/progress/2026-10-02-forge-lib-path-includes-dep-test-and-priv-dirs.md).

    A forge.toml that does not load (mid-edit) contributes the project's own
    directories only. *)
let project_lib_paths root =
  match March_forge.Project.load_from_dir root with
  | Ok proj -> March_forge.Cmd_build.lib_paths proj
  | Error _ ->
    March_forge.Cmd_build.collect_lib_dirs (Filename.concat root "lib")
    @ List.filter Sys.file_exists
        [Filename.concat root ".forge/generated"; Filename.concat root "config"]
