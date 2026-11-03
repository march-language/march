/* lib/jit/jit_emit_stubs.c
 *
 * In-process object emission for shell fragments (Repl_jit.shell_compile):
 * parse LLVM IR text, run the O1 pipeline, and write a PIC object file for
 * an arbitrary target triple — what `clang -O1 -fPIC -c -x ir` does, minus
 * the process start and the driver (~60 ms per input on macOS).
 *
 * Every LLVM entry point is looked up with dlsym at first use rather than
 * referenced directly.  That keeps this file link-independent of libLLVM's
 * component set: a static-LLVM build (MARCH_STATIC_LLVM=1, which links only
 * the `orcjit native` components and exports no symbols) or a host whose
 * libLLVM lacks a target simply reports "unavailable", and the caller falls
 * back to clang.  Target initialisation is per target, also by name
 * (LLVMInitialize<Arch>TargetInfo, ...), for the same reason: an LLVM built
 * without, say, the X86 backend has no such symbol.
 */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Error.h>
#include <llvm-c/Transforms/PassBuilder.h>

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

/* From jit_orc_stubs.c: dlopen libLLVM (RTLD_GLOBAL) if it is not already
   in the process.  Returns nonzero when it is loaded. */
extern int march_llvm_try_load(void);

#define EMIT_FN(name) static __typeof__(&name) p_##name
EMIT_FN(LLVMContextCreate);
EMIT_FN(LLVMContextDispose);
EMIT_FN(LLVMCreateMemoryBufferWithMemoryRangeCopy);
EMIT_FN(LLVMParseIRInContext);
EMIT_FN(LLVMDisposeMessage);
EMIT_FN(LLVMGetTargetFromTriple);
EMIT_FN(LLVMCreateTargetMachine);
EMIT_FN(LLVMDisposeTargetMachine);
EMIT_FN(LLVMCreateTargetDataLayout);
EMIT_FN(LLVMSetModuleDataLayout);
EMIT_FN(LLVMDisposeTargetData);
EMIT_FN(LLVMSetTarget);
EMIT_FN(LLVMCreatePassBuilderOptions);
EMIT_FN(LLVMDisposePassBuilderOptions);
EMIT_FN(LLVMRunPasses);
EMIT_FN(LLVMGetErrorMessage);
EMIT_FN(LLVMDisposeErrorMessage);
EMIT_FN(LLVMTargetMachineEmitToFile);
EMIT_FN(LLVMDisposeModule);

/* 0 = not probed, 1 = all entry points found, -1 = unavailable. */
static int emit_state = 0;

static int resolve_all(void) {
#define R(name) do { \
        p_##name = (__typeof__(&name))dlsym(RTLD_DEFAULT, #name); \
        if (!p_##name) return 0; \
    } while (0)
    R(LLVMContextCreate);
    R(LLVMContextDispose);
    R(LLVMCreateMemoryBufferWithMemoryRangeCopy);
    R(LLVMParseIRInContext);
    R(LLVMDisposeMessage);
    R(LLVMGetTargetFromTriple);
    R(LLVMCreateTargetMachine);
    R(LLVMDisposeTargetMachine);
    R(LLVMCreateTargetDataLayout);
    R(LLVMSetModuleDataLayout);
    R(LLVMDisposeTargetData);
    R(LLVMSetTarget);
    R(LLVMCreatePassBuilderOptions);
    R(LLVMDisposePassBuilderOptions);
    R(LLVMRunPasses);
    R(LLVMGetErrorMessage);
    R(LLVMDisposeErrorMessage);
    R(LLVMTargetMachineEmitToFile);
    R(LLVMDisposeModule);
#undef R
    return 1;
}

static int emit_ready(void) {
    if (emit_state == 0) {
        march_llvm_try_load();
        emit_state = resolve_all() ? 1 : -1;
    }
    return emit_state == 1;
}

/* Initialise one backend (TargetInfo, Target, TargetMC, AsmPrinter) by its
   LLVM name, e.g. "AArch64" or "X86".  Idempotent in LLVM.  Returns 0 when
   this libLLVM was built without it. */
static int init_target(const char *arch) {
    static const char *parts[] = { "TargetInfo", "Target", "TargetMC", "AsmPrinter" };
    void (*fns[4])(void);
    char sym[96];
    for (int i = 0; i < 4; i++) {
        snprintf(sym, sizeof sym, "LLVMInitialize%s%s", arch, parts[i]);
        fns[i] = (void (*)(void))dlsym(RTLD_DEFAULT, sym);
        if (!fns[i]) return 0;
    }
    for (int i = 0; i < 4; i++) fns[i]();
    return 1;
}

/* march_emit_available : string -> bool
   [arch] is the LLVM backend name ("AArch64", "X86").  True when libLLVM is
   loaded, every entry point this file uses resolves, and that backend is
   compiled in.  Never raises. */
CAMLprim value march_emit_available(value v_arch) {
    CAMLparam1(v_arch);
    int ok = emit_ready() && init_target(String_val(v_arch));
    CAMLreturn(Val_bool(ok));
}

/* march_emit_object : ir -> triple -> cpu -> out_path -> string
   Parse [ir], retarget it to [triple], run `default<O1>` (clang -O1's
   pipeline) and write a PIC object to [out_path].  Returns "" on success,
   else an error message (the caller falls back to clang, whose diagnostic
   is then the one the user sees).  Call only after [march_emit_available]
   returned true for the triple's backend. */
CAMLprim value march_emit_object(value v_ir, value v_triple, value v_cpu,
                                 value v_out) {
    CAMLparam4(v_ir, v_triple, v_cpu, v_out);
    char err[2048];
    err[0] = '\0';
    if (!emit_ready()) CAMLreturn(caml_copy_string("libLLVM not available"));

    const char *triple = String_val(v_triple);
    LLVMContextRef ctx = p_LLVMContextCreate();
    LLVMMemoryBufferRef buf = p_LLVMCreateMemoryBufferWithMemoryRangeCopy(
        String_val(v_ir), caml_string_length(v_ir), "shell_fragment");
    LLVMModuleRef mod = NULL;
    LLVMTargetMachineRef tm = NULL;
    char *msg = NULL;

    /* LLVMParseIRInContext consumes [buf] on every path. */
    if (p_LLVMParseIRInContext(ctx, buf, &mod, &msg)) {
        snprintf(err, sizeof err, "parse IR: %s", msg ? msg : "(no message)");
        goto out;
    }
    LLVMTargetRef target = NULL;
    if (p_LLVMGetTargetFromTriple(triple, &target, &msg)) {
        snprintf(err, sizeof err, "target %s: %s", triple, msg ? msg : "(no message)");
        goto out;
    }
    /* CodeGenOptLevel Less is what clang -O1 hands the backend. */
    tm = p_LLVMCreateTargetMachine(target, triple, String_val(v_cpu), "",
                                   LLVMCodeGenLevelLess, LLVMRelocPIC,
                                   LLVMCodeModelDefault);
    if (!tm) { snprintf(err, sizeof err, "no target machine for %s", triple); goto out; }
    p_LLVMSetTarget(mod, triple);
    LLVMTargetDataRef dl = p_LLVMCreateTargetDataLayout(tm);
    p_LLVMSetModuleDataLayout(mod, dl);
    p_LLVMDisposeTargetData(dl);

    LLVMPassBuilderOptionsRef opts = p_LLVMCreatePassBuilderOptions();
    LLVMErrorRef e = p_LLVMRunPasses(mod, "default<O1>", tm, opts);
    p_LLVMDisposePassBuilderOptions(opts);
    if (e) {
        char *em = p_LLVMGetErrorMessage(e);
        snprintf(err, sizeof err, "O1 pipeline: %s", em ? em : "(no message)");
        if (em) p_LLVMDisposeErrorMessage(em);
        goto out;
    }
    /* The C API takes a non-const char * for the path. */
    char path[4096];
    snprintf(path, sizeof path, "%s", String_val(v_out));
    if (p_LLVMTargetMachineEmitToFile(tm, mod, path, LLVMObjectFile, &msg)) {
        snprintf(err, sizeof err, "emit object: %s", msg ? msg : "(no message)");
        goto out;
    }
out:
    if (msg) p_LLVMDisposeMessage(msg);
    if (tm) p_LLVMDisposeTargetMachine(tm);
    if (mod) p_LLVMDisposeModule(mod);
    p_LLVMContextDispose(ctx);
    CAMLreturn(caml_copy_string(err));
}
