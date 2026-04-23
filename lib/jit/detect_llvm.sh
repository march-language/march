#!/bin/sh
# Emit a dune sexp list of LLVM flags for the current platform.
# Usage: sh detect_llvm.sh c_flags
#        sh detect_llvm.sh link_flags
WHAT="${1:-c_flags}"
if uname | grep -q Darwin; then
    PREFIX=$(brew --prefix llvm 2>/dev/null || echo /opt/homebrew/opt/llvm)
    case "$WHAT" in
        c_flags)    printf '(-I%s/include)\n' "$PREFIX" ;;
        link_flags) printf '(-Wl,-undefined,dynamic_lookup)\n' ;;
    esac
else
    INC=$(llvm-config --includedir 2>/dev/null \
       || llvm-config-18 --includedir 2>/dev/null \
       || echo /usr/lib/llvm-18/include)
    LIB=$(llvm-config --libdir 2>/dev/null \
       || llvm-config-18 --libdir 2>/dev/null \
       || echo /usr/lib/llvm-18/lib)
    case "$WHAT" in
        c_flags)    printf '(-I%s)\n' "$INC" ;;
        link_flags) printf '(-ldl -L%s -lLLVM)\n' "$LIB" ;;
    esac
fi
