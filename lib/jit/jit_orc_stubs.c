/* lib/jit/jit_orc_stubs.c
 *
 * LLVM ORCv2 LLJIT bindings for March's REPL JIT.
 *
 * Strategy — runtime dlopen of libLLVM.dylib:
 *   • This library is NOT link-time dependent on libLLVM (that would add
 *     >100MB to every march startup via dyld, even for AOT compilation).
 *   • Instead we dlopen libLLVM with RTLD_GLOBAL on first LLJIT creation,
 *     making the LLVM C-API symbols resolvable by subsequent calls in
 *     this translation unit.
 *   • Linker is told to leave these symbols unresolved via
 *     `-Wl,-undefined,dynamic_lookup` in lib/jit/dune.
 *
 * Scope — Phase 2.3 MVP behind MARCH_JIT_BACKEND=orc:
 *   • create/dispose a single process-wide LLJIT instance
 *   • add an IR module (string → parsed → TSModule → LLJIT)
 *   • look up a symbol by name
 *   • process-wide symbol resolution via DynamicLibrarySearchGenerator,
 *     so the already-dlopen'd runtime.so / stdlib.so are visible.
 */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/Error.h>
#include <llvm-c/LLJIT.h>
#include <llvm-c/Orc.h>

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── libLLVM loader ───────────────────────────────────────────────────── */

static int llvm_loaded = 0;

static const char *default_llvm_paths[] = {
    "/opt/homebrew/opt/llvm/lib/libLLVM.dylib",
    "/opt/homebrew/lib/libLLVM.dylib",
    "/usr/local/opt/llvm/lib/libLLVM.dylib",
    "libLLVM.dylib",
    NULL,
};

static void load_libllvm_once(void) {
    if (llvm_loaded) return;
    const char *override = getenv("MARCH_LLVM_LIB");
    void *h = NULL;
    if (override && override[0]) {
        h = dlopen(override, RTLD_NOW | RTLD_GLOBAL);
        if (!h) {
            char buf[512];
            snprintf(buf, sizeof buf, "MARCH_LLVM_LIB=%s dlopen: %s",
                     override, dlerror());
            caml_failwith(buf);
        }
    } else {
        for (int i = 0; default_llvm_paths[i]; ++i) {
            h = dlopen(default_llvm_paths[i], RTLD_NOW | RTLD_GLOBAL);
            if (h) break;
        }
        if (!h) {
            caml_failwith(
                "libLLVM.dylib not found — install via `brew install llvm`, "
                "or set MARCH_LLVM_LIB to the .dylib path.");
        }
    }
    llvm_loaded = 1;
}

/* ── error helper ─────────────────────────────────────────────────────── */

static void fail_with_llvm_err(const char *prefix, LLVMErrorRef err) {
    char *msg = LLVMGetErrorMessage(err);
    char buf[1024];
    snprintf(buf, sizeof buf, "%s: %s", prefix, msg ? msg : "(no message)");
    if (msg) LLVMDisposeErrorMessage(msg);
    caml_failwith(buf);
}

/* ── OCaml-visible entry points ───────────────────────────────────────── */

/* Create a new LLJIT instance with a process-wide symbol search generator.
   Returns the LLJITRef as a nativeint. */
CAMLprim value march_orc_create(value v_unit) {
    CAMLparam1(v_unit);
    load_libllvm_once();

    /* One-shot native-target init. Idempotent in LLVM's implementation. */
    if (LLVMInitializeNativeTarget())
        caml_failwith("LLVMInitializeNativeTarget failed");
    if (LLVMInitializeNativeAsmPrinter())
        caml_failwith("LLVMInitializeNativeAsmPrinter failed");
    if (LLVMInitializeNativeAsmParser())
        caml_failwith("LLVMInitializeNativeAsmParser failed");

    LLVMOrcLLJITBuilderRef builder = LLVMOrcCreateLLJITBuilder();
    LLVMOrcLLJITRef J = NULL;
    LLVMErrorRef err = LLVMOrcCreateLLJIT(&J, builder);
    /* builder ownership: consumed by LLJIT on success, disposed on error. */
    if (err) fail_with_llvm_err("LLVMOrcCreateLLJIT", err);

    /* Add a process-search generator to the main dylib so symbols already
       present in the host process (runtime.so, stdlib.so dlopen'd at
       startup) are resolvable by JIT'd code. */
    LLVMOrcJITDylibRef MainJD = LLVMOrcLLJITGetMainJITDylib(J);
    LLVMOrcDefinitionGeneratorRef gen = NULL;
    char prefix = LLVMOrcLLJITGetGlobalPrefix(J);
    err = LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(
        &gen, prefix, /*Filter*/NULL, /*FilterCtx*/NULL);
    if (err) {
        LLVMOrcDisposeLLJIT(J);
        fail_with_llvm_err("CreateDynamicLibrarySearchGeneratorForProcess",
                           err);
    }
    LLVMOrcJITDylibAddGenerator(MainJD, gen);

    CAMLreturn(caml_copy_nativeint((intnat)J));
}

/* Parse an IR string and add it to the LLJIT's main dylib. */
CAMLprim value march_orc_add_ir(value v_J, value v_ir, value v_name) {
    CAMLparam3(v_J, v_ir, v_name);
    LLVMOrcLLJITRef J = (LLVMOrcLLJITRef)Nativeint_val(v_J);
    const char *ir_str = String_val(v_ir);
    mlsize_t ir_len = caml_string_length(v_ir);
    const char *name = String_val(v_name);

    /* Create a plain LLVMContext, parse IR into it, then wrap it in a
       ThreadSafeContext. This is the canonical pattern in newer LLVM
       versions where the TSContext no longer exposes its inner context
       directly via a getter. */
    LLVMContextRef Ctx = LLVMContextCreate();

    /* Copy the IR bytes — LLVMParseIRInContext consumes the MemoryBuffer. */
    LLVMMemoryBufferRef MemBuf = LLVMCreateMemoryBufferWithMemoryRangeCopy(
        ir_str, (size_t)ir_len, name);

    LLVMModuleRef Mod = NULL;
    char *errmsg = NULL;
    if (LLVMParseIRInContext(Ctx, MemBuf, &Mod, &errmsg) != 0) {
        char buf[2048];
        snprintf(buf, sizeof buf, "LLVMParseIRInContext: %s",
                 errmsg ? errmsg : "(no message)");
        if (errmsg) LLVMDisposeMessage(errmsg);
        LLVMContextDispose(Ctx);
        caml_failwith(buf);
    }
    /* MemBuf consumed by LLVMParseIRInContext; Mod is now owned by Ctx. */

    LLVMOrcThreadSafeContextRef TSCtx =
        LLVMOrcCreateNewThreadSafeContextFromLLVMContext(Ctx);
    /* TSCtx now owns Ctx; do not call LLVMContextDispose on it. */

    LLVMOrcThreadSafeModuleRef TSM =
        LLVMOrcCreateNewThreadSafeModule(Mod, TSCtx);
    /* TSM now owns Mod; TSCtx refcount is incremented. */

    /* We can drop our reference to TSCtx — TSM keeps it alive. */
    LLVMOrcDisposeThreadSafeContext(TSCtx);

    LLVMOrcJITDylibRef MainJD = LLVMOrcLLJITGetMainJITDylib(J);
    LLVMErrorRef err = LLVMOrcLLJITAddLLVMIRModule(J, MainJD, TSM);
    /* On success TSM is consumed; on failure the caller still owns it. */
    if (err) {
        LLVMOrcDisposeThreadSafeModule(TSM);
        fail_with_llvm_err("LLVMOrcLLJITAddLLVMIRModule", err);
    }

    CAMLreturn(Val_unit);
}

/* Look up a symbol in the LLJIT's main dylib. Returns the address as
   a nativeint (suitable for passing to Jit.call_void_to_*). */
CAMLprim value march_orc_lookup(value v_J, value v_sym) {
    CAMLparam2(v_J, v_sym);
    LLVMOrcLLJITRef J = (LLVMOrcLLJITRef)Nativeint_val(v_J);
    const char *sym = String_val(v_sym);

    LLVMOrcJITTargetAddress addr = 0;
    LLVMErrorRef err = LLVMOrcLLJITLookup(J, &addr, sym);
    if (err) {
        char buf[512];
        snprintf(buf, sizeof buf, "LLVMOrcLLJITLookup('%s')", sym);
        fail_with_llvm_err(buf, err);
    }
    CAMLreturn(caml_copy_nativeint((intnat)addr));
}

/* Dispose of the LLJIT instance. Frees all JIT'd code. */
CAMLprim value march_orc_dispose(value v_J) {
    CAMLparam1(v_J);
    LLVMOrcLLJITRef J = (LLVMOrcLLJITRef)Nativeint_val(v_J);
    LLVMErrorRef err = LLVMOrcDisposeLLJIT(J);
    /* On dispose, errors are reported but not fatal — we're tearing down. */
    if (err) {
        char *msg = LLVMGetErrorMessage(err);
        if (msg) {
            fprintf(stderr, "[march] LLJIT dispose warning: %s\n", msg);
            LLVMDisposeErrorMessage(msg);
        }
    }
    CAMLreturn(Val_unit);
}
