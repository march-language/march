# Unscoped launch requests in freestanding WebAssembly

The freestanding browser target has no process environment supplying
`MARCH_GRANT`. With an empty environment grant, `Authority.launch_init`
returns immediately for an unscoped request, including `needs IO.Foreign`.
The browser compiler now omits that no-op for any unscoped request. Static
capability checks and scoped launch requests still run.

The codegen regression checks an unscoped entry that calls a statically
linked extern. The same guest links with the freestanding runtime and
invokes its host function from the exported `_start`.
