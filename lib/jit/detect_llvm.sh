#!/bin/sh
# Emit dune sexp flag lists for LLVM compilation on the current platform.
# Usage: sh detect_llvm.sh c_flags
#        sh detect_llvm.sh link_flags
#
# Emits LLVM_MAJOR_VERSION=N as a compile-time define so jit_orc_stubs.c
# can switch between the LLVM 18 and LLVM 19+ ThreadSafeContext APIs.
WHAT="${1:-c_flags}"
if uname | grep -q Darwin; then
    PREFIX=$(brew --prefix llvm 2>/dev/null || echo /opt/homebrew/opt/llvm)
    LLVM_VER=$("${PREFIX}/bin/llvm-config" --version 2>/dev/null | cut -d. -f1)
    LLVM_VER=${LLVM_VER:-22}
    case "$WHAT" in
        c_flags)    printf '(-I%s/include -DLLVM_MAJOR_VERSION=%s)\n' "$PREFIX" "$LLVM_VER" ;;
        link_flags) printf '(-Wl,-undefined,dynamic_lookup)\n' ;;
    esac
else
    LLVM_CFG=$(command -v llvm-config 2>/dev/null \
            || command -v llvm-config-18 2>/dev/null \
            || command -v llvm-config-17 2>/dev/null)
    if [ -n "$LLVM_CFG" ]; then
        INC=$("$LLVM_CFG" --includedir)
        LIB=$("$LLVM_CFG" --libdir)
        LLVM_VER=$("$LLVM_CFG" --version | cut -d. -f1)
    else
        INC=/usr/lib/llvm-18/include
        LIB=/usr/lib/llvm-18/lib
        LLVM_VER=18
    fi
    case "$WHAT" in
        c_flags)    printf '(-I%s -DLLVM_MAJOR_VERSION=%s)\n' "$INC" "$LLVM_VER" ;;
        link_flags) printf '(-ldl -L%s -lLLVM)\n' "$LIB" ;;
    esac
fi
