# `[P3]` Choreography: an alias for a role's entry state

Filed 2026-09-20 by the choreography UX pass ([[2026-09-20-choreography-ux-hardening]]).

Every role body's signature has to spell the role's first state, and the only way to learn
it is to work out `S_` + the first step (`Fan_C.S_recv_Msg_A_C_1`). The generator already
knows it (`role_module` returns the entry state name for `<P>_Run`), so it could also emit
`type Entry = S_recv_Msg_A_C_1` in each role module and the guide could show
`st : Fan_C.Entry`. The state is `always_linear`; check that a type alias to one keeps the
linearity (it should: aliases are transparent), and that the name `Entry` cannot collide
with a generated state name (states all start with `S_`).
