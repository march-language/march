# Compiled calls prefer lexical module aliases

Two modules could each declare `alias … as Local` and pass typechecking, but
TIR lowering resolved both uses of `Local.member` through the first alias
registered across the program. When both targets exported the member, the
compiled program could silently call the wrong one. When only the intended
target exported it, compilation could fail on a reference to the other target.

Lowering now records module prefixes alongside exact imports in the lexical
scope. A nested module inherits the enclosing scope and may replace an
inherited alias. Deferred lowering can recover the prior binding when it
revisits a function declared before a replacement.

The codegen regression uses a library and entry point with different aliases
for the same member and checks both inheritance and rebinding in nested modules.
