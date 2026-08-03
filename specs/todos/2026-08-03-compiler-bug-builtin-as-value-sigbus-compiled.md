# Compiler bug: builtin passed directly as a first-class value SIGBUSes compiled

- [ ] Passing a capability builtin directly as a function value — `apply1(file_read, path)`
  where `fn apply1(f : (String) -> a, p : String) : a` — typechecks, works INTERPRETED
  (prints the file), and dies with SIGBUS (exit 138) compiled. Wrapping in a lambda
  (`apply1(fn p -> file_read(p), p)`) works both ways, so the miscompile is specific to
  the builtin-as-value closure-conversion path, same family as past compiled-only bugs
  in `specs/progress/`.

  Found 2026-08-03 while measuring call-site visibility for the cap-audit design
  (`specs/2026-08-03-forge-cap-audit-design.md` §3). Repro (compile + run, compare
  against interpreter):

  ```march
  mod HofApp do
    needs IO.FileRead

    fn apply1(f : (String) -> a, p : String) : a do
      f(p)
    end

    fn main() : () do
      match apply1(file_read, "/etc/hosts") do
        Ok(s)  -> println(string_slice(s, 0, 5))
        Err(_) -> println("err")
      end
    end
  end
  ```

  Also relevant to the cap audit: a direct-passed builtin emits no direct `bl` in the
  binary, so when this is fixed, confirm the marker-emission path (`mangle_extern`
  recording) still catches it — add a marker test for the direct-pass form alongside
  the lambda-wrapped one in `test/test_cap_markers.ml`.
