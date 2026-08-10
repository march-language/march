# forge audit/licenses/tree: resolve git/registry deps under $HOME, not project root

`forge/lib/cmd_audit.ml`, `forge/lib/cmd_licenses.ml`, and `forge/lib/cmd_tree.ml` each
had their own `cas_deps_dir root` / `dep_dir` helper that computed a git/registry
dependency's install location as `<project_root>/.march/cas/deps/<name>`.

The actual installer (`forge/lib/cmd_deps.ml`'s `cas_deps_dir ()`, and
`Project.dep_root_dir`) installs git and registry dependencies under
`$HOME/.march/cas/deps/<name>` — a global, cross-project location — never under the
project root. So `forge audit`, `forge licenses`, and `forge tree` could never find an
actually-installed git/registry dependency's source tree: the computed directory never
existed, `Sys.file_exists`/`Project.load_from_dir` failed, and the dependency was
reported as "not installed" (audit), with empty version/license metadata (licenses), or
as a childless leaf (tree) — even immediately after a successful `forge deps`. `PathDep`
was unaffected since it resolves relative to the declaring project regardless.

Fixed by replacing all three local reimplementations with `Project.dep_root_dir
~project_root:base (name, dep)`, the same resolver the installer and `forge deps`'
transitive-dependency BFS already use.

Existing tests for these three commands (`test_forge.ml`'s `Cmd_licenses` cases,
`test_audit.ml`) only exercised pure helpers or `PathDep`, which never touches the
buggy branch — so none of them caught this. Added `forge/test/test_dep_dir.ml`, which
fakes `$HOME` with a pre-populated `.march/cas/deps/<name>` fixture and exercises each
command's `dep_dir` directly against `GitTagDep`, `RegistryDep`, and `PathDep`.
