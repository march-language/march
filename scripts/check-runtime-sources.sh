#!/usr/bin/env bash
# Police the hand-maintained runtime C source lists against runtime/sources.list.
#
# Adding a runtime .c file used to mean editing several lists by hand, and a
# miss failed at link time (or not at all: a dune rule that omits a dep simply
# never rebuilds when that file changes). This turns "undefined symbol
# _march_ctx_escape" into "rule X omits core file march_ctx_escape.c", in
# seconds, with no build. Design: specs/2026-09-11-ci-tooling-fixes-design.md §4.
#
#   1. every runtime/*.c is in the manifest exactly once, and vice versa;
#   2. bin/main.ml and bin/toolchain.ml name every core/http/hcr file and no
#      unit-test-only file (toolchain.ml is the cross-compile copy of main.ml's
#      list; main.ml may also name the wasm runtime, for --target wasm32);
#   3. test/test_helpers.ml's JIT .so list names every `jit`-tagged file;
#   4. every test/dune / demo/dune rule that compiles with %{cc} names the same
#      runtime .c set in its (deps) as in its action; every rule that runs
#      `march --compile` either globs ../runtime/*.c or names every core, http
#      and hcr file (those are what the driver links, so they are what the
#      rule's output depends on).
#
# Usage: scripts/check-runtime-sources.sh     # exit 1 on any problem
set -euo pipefail
cd "$(dirname "$0")/.."

manifest=runtime/sources.list
fail=0
problem() { echo "  $*"; fail=1; }

# ── manifest accessors (plain awk; macOS ships bash 3.2, which has no
#    associative arrays) ──
entries() { awk '!/^#/ && NF>=3 {print $1, $2, $3}' "$manifest"; }
role_of() { entries | awk -v f="$1" '$1==f {print $2; exit}'; }
jit_of()  { entries | awk -v f="$1" '$1==f {print $3; exit}'; }
files_with_role() { entries | awk -v r="$1" '$2==r {print $1}'; }
all_files() { entries | awk '{print $1}'; }
dups=$(all_files | sort | uniq -d)
[[ -n "$dups" ]] && problem "MANIFEST: listed twice: $dups"
nfiles=$(all_files | wc -l | tr -d ' ')

echo "== Check 1: runtime/*.c <-> $manifest =="
for p in runtime/*.c; do
  f=$(basename "$p")
  [[ -n "$(role_of "$f")" ]] || problem "UNLISTED: runtime/$f is not in $manifest (add it with a role)"
done
for f in $(all_files); do
  [[ -e "runtime/$f" ]] || problem "STALE: $manifest lists $f but runtime/$f does not exist"
  case "$(role_of "$f")" in core|http|hcr|unit-test-only|wasm) ;; *) problem "MANIFEST: $f has unknown role '$(role_of "$f")'";; esac
done
[[ $fail -eq 0 ]] && echo "  ok — $nfiles files classified"

driver_files() { grep -oE '"[a-z_0-9]+\.c"' "$1" | tr -d '"' | sort -u; }

echo "== Check 2: driver link lists (bin/main.ml, bin/toolchain.ml) =="
c2=0
for drv in bin/main.ml bin/toolchain.ml; do
  named=$(driver_files "$drv")
  for f in $(all_files); do
    r=$(role_of "$f")
    case "$r" in
      core|http|hcr)
        grep -qx "$f" <<<"$named" || { problem "$drv does not name $r file $f"; c2=1; } ;;
      unit-test-only)
        grep -qx "$f" <<<"$named" && { problem "$drv names unit-test-only file $f (the driver must not link the arena)"; c2=1; } ;;
      wasm)
        if [[ $drv == bin/toolchain.ml ]] && grep -qx "$f" <<<"$named"; then problem "$drv names wasm file $f"; c2=1; fi ;;
    esac
  done
done
[[ $c2 -eq 0 ]] && echo "  ok — both drivers name every core/http/hcr file and no arena file"

echo "== Check 3: test/test_helpers.ml JIT .so link list =="
c3=0
helpers=$(sed -n '/extra_src_list = List.filter_map opt_path \[/,/\]/p' test/test_helpers.ml | grep -oE '"[a-z_0-9]+\.c"' | tr -d '"')
for f in $(all_files); do
  if [[ "$(jit_of "$f")" == jit && "$f" != march_runtime.c ]]; then
    grep -qx "$f" <<<"$helpers" || { problem "test/test_helpers.ml extra_src_list omits jit file $f"; c3=1; }
  fi
done
[[ $c3 -eq 0 ]] && echo "  ok — JIT link list covers every jit-tagged file"

echo "== Check 4: test/dune and demo/dune rule blocks =="
required=$( { files_with_role core; files_with_role http; files_with_role hcr; } )
c4=0; nrules=0
for dunefile in test/dune demo/dune; do
  # Emit one line per (rule ...) block: "<target>|<kind>|<glob>|<deps files>|<action files>".
  while IFS='|' read -r target kind glob deps acts; do
    nrules=$((nrules+1))
    case "$kind" in
      cc)
        [[ $glob == 1 ]] && continue   # deps glob the whole runtime: nothing to omit
        for f in $acts; do grep -qw "$f" <<<"$deps" || { problem "$dunefile rule $target: action compiles $f but (deps) omits it"; c4=1; }; done
        for f in $deps; do grep -qw "$f" <<<"$acts" || { problem "$dunefile rule $target: (deps) lists $f but the action does not compile it"; c4=1; }; done ;;
      compile)
        if [[ $glob != 1 ]]; then
          while read -r f; do [[ -z "$f" ]] && continue
            grep -qw "$f" <<<"$deps" || { problem "$dunefile rule $target: --compile rule omits $(role_of "$f") file $f from (deps) (or glob ../runtime/*.c)"; c4=1; }
          done <<<"$required"
        fi ;;
    esac
  done < <(python3 - "$dunefile" <<'PY'
import re,sys
s=open(sys.argv[1]).read(); i=0
while True:
    j=s.find('(rule',i)
    if j<0: break
    d=0;k=j
    while k<len(s):
        if s[k]=='(': d+=1
        elif s[k]==')':
            d-=1
            if d==0: break
        k+=1
    b=s[j:k+1]; i=k+1
    files=re.findall(r'\.\./runtime/([a-z_0-9]+\.c)',b)
    glob='glob_files ../runtime/*.c' in b
    if not files and not glob: continue
    kind='cc' if '%{cc}' in b else ('compile' if '--compile' in b else 'other')
    m=re.search(r'\(targets?\s+([^\s)]+)',b); target=m.group(1) if m else '?'
    ai=b.find('(action'); deps_part=b[:ai] if ai>=0 else b; act_part=b[ai:] if ai>=0 else ''
    dep_files=sorted(set(re.findall(r'\.\./runtime/([a-z_0-9]+\.c)',deps_part)))
    act_files=sorted(set(re.findall(r'\.\./runtime/([a-z_0-9]+\.c)',act_part)))
    print('|'.join([target,kind,'1' if glob else '0',' '.join(dep_files),' '.join(act_files)]))
PY
)
done
[[ $c4 -eq 0 ]] && echo "  ok — $nrules rule blocks consistent" || echo "  ($nrules rule blocks checked)"

echo
if [[ $fail -ne 0 ]]; then echo "check-runtime-sources FAILED"; exit 1; fi
echo "check-runtime-sources passed"
