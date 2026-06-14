(** forge release [--bump patch|minor|major]

    A guarded release pipeline: require a clean working tree, then build (release)
    and test, then bump the version and commit + tag it. Each step gates the
    next; any failure aborts before the tag is created. (Pushing to a registry
    is future work — see forge_version_manager.md.) *)

let run ?(bump = "patch") () =
  let ( let* ) = Result.bind in
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let root = proj.Project.root in
    if not (Cmd_version.git_tree_clean root) then
      Error "working tree is dirty; commit or stash changes before `forge release`"
    else begin
      Printf.printf "release: building (release) ...\n%!";
      let* _ = Cmd_build.build ~release:true () in
      Printf.printf "release: running tests ...\n%!";
      let* () = Cmd_test.run () in
      Printf.printf "release: bumping version (%s) + tagging ...\n%!" bump;
      Cmd_version.run ~spec:bump ~tag:true ()
    end
