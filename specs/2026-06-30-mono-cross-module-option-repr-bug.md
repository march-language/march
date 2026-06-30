# Residual Boxed-vs-Niche `Option` repr mismatch across module boundaries

**Status:** OPEN, root-caused to a hypothesis with decisive crash evidence. This is the
*residual* of the bug `373932d3` (mono `refine_field_types`) fixed: that commit fixed the
**single-compilation-unit** case; forgepm's real publish path still crashes identically
because the same generic helper (`get_req_header`) lives in a **separately-compiled**
module (stdlib `HttpServer` → bastion `Conn`). forgepm currently works only via the
`force_copy` workaround (`forgepm e840b63`).

**Owner needed:** the `lib/tir/mono.ml` author (who wrote `373932d3`) — this extends that
exact fix.

---

## 1. Symptom

The natively-compiled forgepm binary, built with the mono-fixed compiler but **without**
the `force_copy` workaround, **crashes (SIGSEGV) on the multipart publish POST**. Other
routes are fine. With `force_copy` (copying every String projected out of a tuple/Option
in the publish path) it passes 29/0. The interpreter is always fine.

It can also manifest as a *hang* (sequential server, the crashed green thread leaves the
connection wedged → `/` returns `000`) rather than a clean process exit — same root cause.

## 2. Decisive evidence — crash report

`~/Library/Logs/DiagnosticReports/forgepm-2026-06-30-100914.ips`:

```
EXC_BAD_ACCESS (SIGSEGV)  KERN_INVALID_ADDRESS at 0x0000000000000036   ← corrupt near-zero ptr
  frame 0  march_string_concat                       +48
  frame 1  Forgepm.Api.Upload.get_file               +104    ← "--" ++ boundary
  frame 2  Forgepm.Api.PackagesHandler.run_publish    +1388
  frame 3  Forgepm.Api.PackagesHandler.publish        +520
  frame 4  Forgepm.Api.Router.dispatch / route
  ...      handle → HttpServer.run_pipeline → connection_thread → march_http_server_listen
```

This is the **exact** original bug: `boundary` (the `b` param of `get_file`) is a corrupt
`0x36` pointer at `"--" ++ boundary`. `0x36` = 54 — a small integer/box field read as a
pointer, the classic Boxed-vs-Niche `Option` misread the mono fix's own comment describes
("reads the Some-box pointer as the payload (SIGSEGV)").

## 3. Why the minimal repro passes but forgepm crashes

- `specs/repros/perceus_tuple_proj_rc_min.march` defines `get_req_header`/`lookup`/`boundary`
  all in **one module** (`mod T`), compiled in one unit. The mono fix's `refine_field_types`
  runs over that unit, retypes the `conn.hdrs` projection to the concrete field type, and the
  callee `lookup` monomorphizes with `Option(String)` as **Niche** on both sides. → passes,
  stable across 100 runs.
- forgepm's real path crosses module/compilation boundaries:
  `Forgepm…run_publish` → **`HttpServer.get_req_header`** (stdlib `http_server.march`) →
  **`Conn.get_req_header`** (bastion `lib/http/conn.march`) → a `lookup` over the bastion
  `Conn`'s header storage. `HttpServer`/bastion are **separately compiled** deps (forge.toml
  registry/path deps), so the generic `get_req_header`'s `Option(String)` representation is
  decided in *its* compilation, and `refine_field_types` (which runs within forgepm's unit)
  does not reach across to make the two units agree. One side emits **Boxed**, the other
  reads **Niche** → the unwrapped boundary `b` is a box pointer misread as the String → `0x36`.

So: `373932d3` closed the intra-unit gap; the **inter-unit (separate-compilation) gap**
remains for any generic helper returning `Option`/a projected field across a dep boundary.
`get_req_header`/`Upload.boundary` is just the first one forgepm exercises.

## 4. The mono fix's scope (what to extend)

`373932d3` added to `lib/tir/mono.ml`:
- a `TRecord, TRecord` arm in `match_ty` (binds row-var fields when a concrete record is
  passed for a row-polymorphic param), and
- `refine_field_types`: for every `let v = a.fld` where `a` resolves to a concrete record,
  retype `v` to the field type and propagate to `v`'s uses — run after `subst_fn_def`,
  before `rewrite_calls`.

Both operate **within the monomorphized unit**. The residual bug is that the representation
(`Boxed` vs `Niche`, decided by `Repr.is_niche_shaped` / the mono'd `Option`'s type args)
must **agree across a dep boundary**, and a separately-compiled generic `Option`-returning
function can be emitted with the abstract (`Boxed`) layout while the concrete caller's
call-site reads `Niche`.

## 5. Reproduction (isolated, set up and working)

A dedicated environment is already in place — does **not** touch the shared `local-main`
toolchain or other agents' work:

- **Toolchain** `~/.march/versions/clean-test` = `local-main` (body-fixed runtime + clean
  stdlib) with `bin/march` replaced by the clean-HEAD compiler
  (`/Users/80197052/code/march/_build/default/bin/main.exe`, which has `373932d3` + the
  niche fix `d7e920b0`).
- **Worktree** `<scratch>/fp-investigate` = forgepm at HEAD with `force_copy` removed
  (`git checkout e840b63~1 -- lib/forgepm/api/upload.march lib/forgepm/api/packages_handler.march`)
  and `.march-version` pinned to `clean-test`.

Reproduce:
```bash
cd <scratch>/fp-investigate
export TMPDIR=<writable>
forge build                                   # clean compiler, no workaround
KEY=$(MARCH_ENV=dev forge test test/zz_seed_test.march | grep -oE 'fpm_[A-Za-z0-9]+' | head -1)
MARCH_ENV=dev MARCH_HTTP_SEQUENTIAL=1 MARCH_NUM_SCHEDULERS=1 ./.march/build/debug/forgepm &
# from the MAIN repo's test/browser (has node_modules):
FORGEPM_API_KEY=$KEY npx playwright test publish.spec.ts:98 --workers=1
# → server SIGSEGVs; new forgepm-*.ips with the frames in §2.
```
Build with `MARCH_SANITIZE=1` for an ASAN report pinning `march_string_concat` reading the
freed/misread boundary.

## 6. Investigation plan (next steps, in order)

1. **Localize the mismatched `Option`.** Dump mono/TIR for `run_publish` + the
   `get_req_header`/`boundary` chain built in the worktree, and find the `Option(_)` whose
   type args are abstract (`'_NNNN`/`TVar`) on one side of a call and concrete on the other.
   Candidate flags: a `MARCH_DEBUG` for mono/repr if one exists; else `--dump-phases` and
   inspect `tir-mono` for `Forgepm.Api.Upload.boundary` and `HttpServer.get_req_header`.
   Confirm whether the abstract `Option` is `get_req_header`'s return, `boundary`'s return,
   or `get_file`'s `Some(b)` scrutinee.
2. **Build a separately-compiled minimal repro.** A single-file `march --compile` likely
   whole-program-monomorphizes and will NOT reproduce (that's why the min repro passes).
   Reproduce the *separate compilation* with two forge packages (or a `lib/` dep): a generic
   `get_opt(pairs, key) : Option('a)` in package B, called from package A with a concrete
   `List((String,String))`, unwrap + use the String. Expect SIGSEGV on use. This isolates
   the bug from forgepm and gives a fast fix-validation harness.
3. **Decide the fix surface.** Options, by preference:
   - Make `Repr` representation of `Option`/niche-shaped types **deterministic regardless of
     whether the type arg is abstract** at the point of emission (so Boxed/Niche never
     disagrees across units), OR
   - Force monomorphic specialization of generic `Option`-returning functions per concrete
     instantiation across dep boundaries (so no abstract `Option` is ever emitted), OR
   - Extend `refine_field_types`/`match_ty` propagation so the concrete type reaches the
     separately-compiled callee's instantiation (mirrors `373932d3` but inter-unit).
4. **Validate:** the §5 repro crashes → passes; the §2 frames gone; `dune runtest` green;
   forgepm cold-build **without** `force_copy` passes the full Playwright suite (29/0) and a
   100× publish stress with no crash; then remove `force_copy` (`forgepm`) and the
   `force_copy` helper.

## 7. Constraints / hazards

- Do the work against `clean-test` + the `fp-investigate` worktree; do NOT install into the
  shared `local-main` (other agents' forgepm WIP — un-`conn`-threaded `pages.march`, `totp`
  needing an unwired `sha1_bytes` — does not typecheck against HEAD, so a `forge check` gate
  on the main tree is confounded; gate on the worktree build + Playwright instead).
- The mono fix `373932d3` is committed+pushed on `fix/h-sigil-compiled`; build from a clean
  checkout of that (the `tweetnacl` vendored stub means a fresh `git worktree` needs the
  tracked `runtime/tweetnacl.*`, present at HEAD).
- The `force_copy` workaround in forgepm is **load-bearing** until this lands — do not remove
  it. It works by copying every String projected out of a tuple/`Option` in the publish path,
  so the owned copy has a correct (concrete) representation.

## 8. One-line summary

`373932d3` fixed intra-unit Boxed-vs-Niche `Option` repr; the **inter-unit** case
(`HttpServer.get_req_header` in separately-compiled stdlib/bastion, consumed by forgepm)
still emits a mismatched `Option(String)` layout, corrupting the unwrapped multipart
boundary → SIGSEGV in `Upload.get_file`'s `"--" ++ boundary`. forgepm's `force_copy`
workaround masks it.
