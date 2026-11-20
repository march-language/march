# JS `try_finally` around a promise does not restore the authority slot (2026-11-19)

Found by the ocap phase 4 Task 10b review. On `--target js`, a `try_finally`
whose body returns a promise restores the authority slot when the synchronous
part returns, not when the promise settles, so a rejection after an `await`
runs its handler under whatever authority is current then. Async thunks are not
supported in `try_finally` today, so no program reaches it yet.

What to do: when async thunks are supported, restore in the promise's
`finally`, and add a `test/cap_conformance` JS fixture.
