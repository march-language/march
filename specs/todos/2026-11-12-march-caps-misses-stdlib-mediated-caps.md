# `march caps` does not count capabilities reached through the stdlib (2026-11-12)

Found by ocap phase 2b, Task 10. `march caps <files...>` reports the union of each own
function's capability closure (`Typecheck.fn_own_capability_closures`), which counts
capability BUILTINS called from the package's own code and does not follow a call into a
stdlib wrapper. A package whose helper calls `Socket.connect(host, 80)` or `File.read(p)`
reports neither `IO.NetConnect` nor `IO.FileRead`:

    mod PkgHelper do
      needs IO.NetConnect, IO.FileRead
      fn fetch(host : String) : Bool do ... Socket.connect(host, 80) ... end
      fn rd(p : String) do File.read(p) end
    end
    -- march caps pkg_helper.march pkg_entry.march  =>  {"caps":["IO.Console"]}

This predates Task 10 for every phase-1 wrapper (`File.read`, `Process.run`, ...); Task 10
makes it bite for sockets too, since a user package can no longer call `tcp_connect` directly
(`test/test_cap_package.ml` switched its fixture to `file_read`, still a callable builtin).
`march caps` is the extractor behind the dependency capability audit (`forge audit`), so it
under-reports, the dangerous direction for a capability record.

What to do: charge the stdlib-mediated route in `march caps` the way the source-level ceiling
does (`check_stdlib_mediated_ceiling`, `cap_strict_ceiling`), or read the TIR-side ceiling's
attribution (`Cap_attrib`) for the package's own modules; then point the `test_cap_package`
fixture back at `Socket.connect`.
