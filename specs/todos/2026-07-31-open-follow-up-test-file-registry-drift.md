# Open follow-up: test-file registry drift


A test `.march` file can silently drop out of the build (nothing checks that
every `test/stdlib/test_*.march` is registered in `test_stdlib_march.ml` — this
is how `test/stdlib/test_json.march` went dead for a while, wired into no
runner). A directory-vs-registry assertion would catch it.

---
