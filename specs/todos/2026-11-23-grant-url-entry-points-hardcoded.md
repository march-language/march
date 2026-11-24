# ocap p6: the grant literal-target check hard-codes its URL entry points

Logged 2026-11-23 by ocap phase 6, Task 3.

`Scoped_literal_check.url_entry_points` (`lib/typecheck/scoped_literal_check.ml`) lists the
stdlib functions whose argument is a URL, with the argument's index, by hand: `HttpClient.get`,
`post`, `put_request`, `delete`, `with_connection`, `stream_get` and
`HttpTransport.simple_get`. It already misses `HttpTransport.simple_get_scoped(url, scope)`,
so a literal URL outside a scoped grant passed to it is refused at run time but not reported
at compile time (`dep_grant_scope`). Any new `@[net_dest(url)]` entry point is missed the same
way.

What to do: derive the list from the `@[net_dest]` attribute (the same source
`Net_dest.method_of` reads), so an annotated function is covered without a line here, and add
an error-corpus case through `simple_get_scoped`.
