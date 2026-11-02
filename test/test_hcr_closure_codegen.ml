(* An old escaping closure called by newer C work must route its nested boundary
   call through the creation epoch, including a top-level function-as-value. *)
let source = {|mod ClosureEpoch do
  needs IO.Console
  needs IO.Foreign
  extern "raw" : Cap(IO.Foreign) do
    fn probe(f : Int -> Int) : Int = "closure_epoch_probe"
    fn probe_panic(f : Int -> Int) : Int = "closure_epoch_probe_panic"
  end
  fn callee(x : Int) : Int do x + 10 end
  fn forward(x : Int) : Int do callee(x) end
  fn main(c : Cap(IO.Console), f : Cap(IO.Foreign)) : Unit do
    let offset = 1
    println(int_to_string(probe(fn x -> callee(x) + offset)))
    println(int_to_string(probe(forward)))
    fn recursive(n : Int) : Int do
      if n == 0 do panic("recursive closure panic")
      else recursive(n - 1) + offset end
    end
    println("panic=" ++ int_to_string(probe_panic(recursive)))
    let mapped = native_int_arr_map(native_int_arr_make(4, 1), fn x -> x + 1)
    println("map=" ++ int_to_string(native_int_arr_get(mapped, 0)))
    let paired = native_int_arr_map2(native_int_arr_make(4, 1), native_int_arr_make(4, 2), fn (x, y) -> x + y)
    println("map2=" ++ int_to_string(native_int_arr_get(paired, 0)))
    println("fold=" ++ int_to_string(native_int_arr_fold(0, native_int_arr_make(4, 1), fn (acc, x) -> acc + x)))
    fn deep(n : Int, acc : Int) : Int do
      if n == 0 do acc else deep(n - 1, acc + offset) end
    end
    println("deep=" ++ int_to_string(deep(200000, 0)))
    fn plain(n : Int, acc : Int) : Int do
      if n == 0 do acc else plain(n - 1, acc + 1) end
    end
    println("plain=" ++ int_to_string(plain(200000, 0)))
  end
end
|}

let shim = {|
#include "march_runtime.h"
#include "march_dispatch.h"
#include "march_scheduler.h"
#include <assert.h>
#include <stdint.h>
static int64_t replacement(int64_t a, int64_t b) { (void)a; (void)b; return 999; }
int64_t closure_epoch_probe(void *clo) {
    static uint32_t epoch = 1;
    uint32_t id = 0;
    assert(march_dispatch_name_to_id("callee", &id) == 1);
    assert(id);
    ++epoch;
    assert(march_epoch_reserve(epoch) == 0);
    assert(march_dispatch_publish_epoch(id, (void *)replacement, "new", "changed ABI", 0, epoch) >= 0);
    march_epoch_advance(epoch);
    march_frame_enter(epoch);
    march_incrc(clo); /* apply consumes the call's own reference */
    void *(*apply)(void *, void *) = *(void *(**)(void *, void *))((char *)clo + 16);
    void *result = apply(clo, (void *)(uintptr_t)3); /* tagged Int 1 */
    assert(march_sched_current_epoch() == epoch);
    march_frame_leave();
    return (int64_t)(intptr_t)result >> 1;
}
/* The trampoline supplies an Int argument of 3 to exercise non-tail recursive
 * self-aliases, inside the real runtime catch boundary. */
static int64_t panic_bridge(void *thunk, int64_t ignored) {
    (void)ignored;
    void *clo = ((void **)thunk)[3];
    march_incrc(clo);
    void *(*apply)(void *, void *) = *(void *(**)(void *, void *))((char *)clo + 16);
    return (int64_t)(intptr_t)apply(clo, (void *)(uintptr_t)7);
}
int64_t closure_epoch_probe_panic(void *clo) {
    int64_t refs = march_rc_peek(clo);
    uint32_t old_epoch = (uint32_t)((march_hdr *)clo)->pad;
    int64_t pins = march_epoch_pins(old_epoch);
    march_frame_enter(march_epoch_current());
    void *mark = march_frame_mark();
    int64_t thunk[] = {INT64_MAX, 0, (int64_t)(uintptr_t)panic_bridge, (int64_t)(uintptr_t)clo};
    void *result = march_try_call_val(thunk);
    assert(((march_hdr *)result)->tag == 1);
    assert(march_frame_mark() == mark);
    assert(march_rc_peek(clo) == refs);
    assert(march_epoch_pins(old_epoch) == pins);
    march_frame_leave();
    return 1;
}
|}

let test_compiled_escape ~opt () =
  let compiler = Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe" in
  let dir = Filename.temp_dir "hcr_closure_epoch" "" in
  let socket = Printf.sprintf "/tmp/clo-epoch-%d.sock" (Unix.getpid ()) in
  let write name contents =
    let path = Filename.concat dir name in
    Out_channel.with_open_bin path (fun oc -> output_string oc contents);
    path
  in
  Fun.protect ~finally:(fun () ->
      ignore (Sys.command ("rm -rf " ^ Filename.quote dir));
      List.iter (fun suffix -> try Sys.remove (socket ^ suffix) with Sys_error _ -> ())
        [""; ".observe"; ".shell"])
    (fun () ->
      let src = write "closure.march" source and ffi = write "shim.c" shim in
      let bin = Filename.concat dir "app" and log = Filename.concat dir "output" in
      let cmd = Printf.sprintf
        "%s --compile --opt %d --hot-reload ClosureEpoch --ffi-c %s -o %s %s > %s 2>&1"
        (Filename.quote compiler) opt (Filename.quote ffi)
        (Filename.quote bin) (Filename.quote src) (Filename.quote log) in
      let rc = Sys.command cmd in
      let read () = In_channel.with_open_bin log In_channel.input_all in
      if rc <> 0 then Alcotest.failf "closure fixture compile (%d):\n%s" rc (read ());
      let rc = Sys.command (Printf.sprintf "HOME=%s MARCH_HOT_RELOAD_SOCKET=%s %s > %s 2>&1"
        (Filename.quote dir) (Filename.quote socket)
        (Filename.quote bin) (Filename.quote log)) in
      let output = read () in
      if rc <> 0 then Alcotest.failf "closure fixture exit (%d):\n%s" rc output;
      let lines = String.split_on_char '\n' output in
      Alcotest.(check bool) "capturing closure keeps old callee" true (List.mem "12" lines);
      Alcotest.(check bool) "function-value wrapper keeps old nested callee" true (List.mem "11" lines);
      Alcotest.(check bool) "recursive panic releases apply env aliases" true (List.mem "panic=1" lines);
      Alcotest.(check bool) "specialized apply accepts null environment" true (List.mem "map=2" lines);
      Alcotest.(check bool) "specialized map2 accepts null environment" true (List.mem "map2=3" lines);
      Alcotest.(check bool) "specialized fold accepts null environment" true (List.mem "fold=4" lines);
      Alcotest.(check bool) "capturing recursive apply stays tail recursive" true (List.mem "deep=200000" lines);
      Alcotest.(check bool) "capture-free recursive apply stays tail recursive" true (List.mem "plain=200000" lines))

let tests =
  [ Alcotest.test_case "escaping closures, panic cleanup and deep tail recursion (opt 2)"
      `Slow (test_compiled_escape ~opt:2);
    Alcotest.test_case "escaping closures, panic cleanup and deep tail recursion (opt 0)"
      `Slow (test_compiled_escape ~opt:0) ]
