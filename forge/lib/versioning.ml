(** Version bumping for `forge version` / `forge release`. Pure — unit-tested. *)

type kind = Patch | Minor | Major

let kind_of_string = function
  | "patch" -> Some Patch
  | "minor" -> Some Minor
  | "major" -> Some Major
  | _ -> None

(* Bump a semver; a bump always clears any pre-release identifiers. *)
let bump kind (v : Resolver_version.t) : Resolver_version.t =
  match kind with
  | Patch -> { v with patch = v.patch + 1; pre = [] }
  | Minor -> { v with minor = v.minor + 1; patch = 0; pre = [] }
  | Major -> { major = v.major + 1; minor = 0; patch = 0; pre = [] }

(* Rewrite the `version = "..."` key inside the [package] (or [project]) section
   of a forge.toml, leaving every other `version` (e.g. a dependency's) intact.
   Only the first such key in that section is changed. *)
let rewrite_version_line ~toml ~new_version =
  let lines = String.split_on_char '\n' toml in
  let in_pkg = ref false and done_ = ref false in
  let rewrite line =
    let t = String.trim line in
    if String.length t >= 1 && t.[0] = '[' then begin
      in_pkg := (t = "[package]" || t = "[project]");
      line
    end
    else if !in_pkg && (not !done_)
            && String.length t >= 7 && String.sub t 0 7 = "version"
            && String.contains t '=' then begin
      done_ := true;
      let indent = String.sub line 0 (String.length line - String.length (String.trim line)) in
      Printf.sprintf "%sversion = %S" indent new_version
    end
    else line
  in
  String.concat "\n" (List.map rewrite lines)
