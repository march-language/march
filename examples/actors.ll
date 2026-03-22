; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_panic(ptr %s)
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
; Ord / Hash builtins
declare i64    @march_compare_int(i64 %x, i64 %y)
declare i64    @march_compare_float(double %x, double %y)
declare i64    @march_compare_string(ptr %x, ptr %y)
declare i64    @march_hash_int(i64 %x)
declare i64    @march_hash_float(double %x)
declare i64    @march_hash_string(ptr %x)
declare i64    @march_hash_bool(i64 %x)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)
declare ptr  @march_spawn(ptr %actor)
declare i64  @march_actor_get_int(ptr %actor, i64 %index)
declare void @march_run_scheduler()
declare i64  @march_tcp_listen(i64 %port)
declare i64  @march_tcp_accept(i64 %fd)
declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)
declare void @march_tcp_send_all(i64 %fd, ptr %data)
declare void @march_tcp_close(i64 %fd)
declare ptr  @march_http_parse_request(ptr %raw)
declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)
declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)
declare void @march_ws_handshake(i64 %fd, ptr %key)
declare ptr  @march_ws_recv(i64 %fd)
declare void @march_ws_send(i64 %fd, ptr %frame)
declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)
; Float builtins
declare double @march_float_abs(double %f)
declare i64    @march_float_ceil(double %f)
declare i64    @march_float_floor(double %f)
declare i64    @march_float_round(double %f)
declare i64    @march_float_truncate(double %f)
declare double @march_int_to_float(i64 %n)
; Math builtins
declare double @march_math_sin(double %f)
declare double @march_math_cos(double %f)
declare double @march_math_tan(double %f)
declare double @march_math_asin(double %f)
declare double @march_math_acos(double %f)
declare double @march_math_atan(double %f)
declare double @march_math_atan2(double %y, double %x)
declare double @march_math_sinh(double %f)
declare double @march_math_cosh(double %f)
declare double @march_math_tanh(double %f)
declare double @march_math_sqrt(double %f)
declare double @march_math_cbrt(double %f)
declare double @march_math_exp(double %f)
declare double @march_math_exp2(double %f)
declare double @march_math_log(double %f)
declare double @march_math_log2(double %f)
declare double @march_math_log10(double %f)
declare double @march_math_pow(double %b, double %e)
; Extended string builtins
declare i64  @march_string_contains(ptr %s, ptr %sub)
declare i64  @march_string_starts_with(ptr %s, ptr %prefix)
declare i64  @march_string_ends_with(ptr %s, ptr %suffix)
declare ptr  @march_string_slice(ptr %s, i64 %start, i64 %len)
declare ptr  @march_string_split(ptr %s, ptr %sep)
declare ptr  @march_string_split_first(ptr %s, ptr %sep)
declare ptr  @march_string_replace(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_replace_all(ptr %s, ptr %old, ptr %new)
declare ptr  @march_string_to_lowercase(ptr %s)
declare ptr  @march_string_to_uppercase(ptr %s)
declare ptr  @march_string_trim(ptr %s)
declare ptr  @march_string_trim_start(ptr %s)
declare ptr  @march_string_trim_end(ptr %s)
declare ptr  @march_string_repeat(ptr %s, i64 %n)
declare ptr  @march_string_reverse(ptr %s)
declare ptr  @march_string_pad_left(ptr %s, i64 %width, ptr %fill)
declare ptr  @march_string_pad_right(ptr %s, i64 %width, ptr %fill)
declare i64  @march_string_grapheme_count(ptr %s)
declare ptr  @march_string_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_last_index_of(ptr %s, ptr %sub)
declare ptr  @march_string_to_float(ptr %s)
; List builtins
declare ptr  @march_list_append(ptr %a, ptr %b)
declare ptr  @march_list_concat(ptr %lists)
; File/Dir builtins
declare i64  @march_file_exists(ptr %s)
declare i64  @march_dir_exists(ptr %s)
; Capability builtins
declare ptr  @march_cap_narrow(ptr %cap)
; Monitor/supervision builtins
declare void @march_demonitor(i64 %ref)
declare i64  @march_monitor(ptr %watcher, ptr %target)
declare i64  @march_mailbox_size(ptr %pid)
declare void @march_run_until_idle()
declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)
declare ptr  @march_get_cap(ptr %pid)
declare void @march_send_checked(ptr %cap, ptr %msg)
declare ptr  @march_pid_of_int(i64 %n)
declare ptr  @march_get_actor_field(ptr %pid, ptr %name)
declare ptr  @march_value_to_string(ptr %v)

@.str1 = private unnamed_addr constant [21 x i8] c"[Counter] ping from \00"
@.str2 = private unnamed_addr constant [11 x i8] c", value = \00"
@.str3 = private unnamed_addr constant [7 x i8] c"[LOG #\00"
@.str4 = private unnamed_addr constant [3 x i8] c"] \00"
@.str5 = private unnamed_addr constant [33 x i8] c"[Logger] total messages logged: \00"
@.str6 = private unnamed_addr constant [24 x i8] c"=== Spawning actors ===\00"
@.str7 = private unnamed_addr constant [16 x i8] c"counter alive: \00"
@.str8 = private unnamed_addr constant [16 x i8] c"logger  alive: \00"
@.str9 = private unnamed_addr constant [1 x i8] c"\00"
@.str10 = private unnamed_addr constant [45 x i8] c"=== Normal operation: counter \E2\86\94 logger ===\00"
@.str11 = private unnamed_addr constant [14 x i8] c"Increment(10)\00"
@.str12 = private unnamed_addr constant [26 x i8] c"counter incremented by 10\00"
@.str13 = private unnamed_addr constant [4 x i8] c"Log\00"
@.str14 = private unnamed_addr constant [13 x i8] c"Increment(5)\00"
@.str15 = private unnamed_addr constant [25 x i8] c"counter incremented by 5\00"
@.str16 = private unnamed_addr constant [4 x i8] c"Log\00"
@.str17 = private unnamed_addr constant [7 x i8] c"logger\00"
@.str18 = private unnamed_addr constant [5 x i8] c"Ping\00"
@.str19 = private unnamed_addr constant [6 x i8] c"Stats\00"
@.str20 = private unnamed_addr constant [1 x i8] c"\00"
@.str21 = private unnamed_addr constant [27 x i8] c"=== Killing the logger ===\00"
@.str22 = private unnamed_addr constant [16 x i8] c"logger  alive: \00"
@.str23 = private unnamed_addr constant [1 x i8] c"\00"
@.str24 = private unnamed_addr constant [48 x i8] c"=== Drop semantics: messages to dead logger ===\00"
@.str25 = private unnamed_addr constant [21 x i8] c"this will be dropped\00"
@.str26 = private unnamed_addr constant [15 x i8] c"Log after kill\00"
@.str27 = private unnamed_addr constant [17 x i8] c"so will this one\00"
@.str28 = private unnamed_addr constant [15 x i8] c"Log after kill\00"
@.str29 = private unnamed_addr constant [17 x i8] c"Stats after kill\00"
@.str30 = private unnamed_addr constant [1 x i8] c"\00"
@.str31 = private unnamed_addr constant [31 x i8] c"=== Counter is still alive ===\00"
@.str32 = private unnamed_addr constant [13 x i8] c"Decrement(3)\00"
@.str33 = private unnamed_addr constant [11 x i8] c"supervisor\00"
@.str34 = private unnamed_addr constant [5 x i8] c"Ping\00"
@.str35 = private unnamed_addr constant [6 x i8] c"Reset\00"
@.str36 = private unnamed_addr constant [11 x i8] c"supervisor\00"
@.str37 = private unnamed_addr constant [17 x i8] c"Ping after reset\00"
@.str38 = private unnamed_addr constant [1 x i8] c"\00"
@.str39 = private unnamed_addr constant [50 x i8] c"=== Restarting the logger (spawn a fresh one) ===\00"
@.str40 = private unnamed_addr constant [16 x i8] c"logger2 alive: \00"
@.str41 = private unnamed_addr constant [19 x i8] c"fresh logger is up\00"
@.str42 = private unnamed_addr constant [15 x i8] c"Log to logger2\00"
@.str43 = private unnamed_addr constant [43 x i8] c"drop semantics apply only to killed actors\00"
@.str44 = private unnamed_addr constant [15 x i8] c"Log to logger2\00"
@.str45 = private unnamed_addr constant [19 x i8] c"Stats from logger2\00"
@.str46 = private unnamed_addr constant [1 x i8] c"\00"
@.str47 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"
@.str48 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str49 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str50 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str51 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str52 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str53 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str54 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str55 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str56 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str57 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str58 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str59 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str60 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str61 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str62 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str63 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str64 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str65 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str66 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str67 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str68 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str69 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str70 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str71 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str72 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str73 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str74 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str75 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str76 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str77 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"
@.str78 = private unnamed_addr constant [12 x i8] c"  !! DROP: \00"
@.str79 = private unnamed_addr constant [19 x i8] c" \E2\80\94 actor is dead\00"

define void @Counter_Increment(ptr %$actor.arg, i64 %n.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld1 = load ptr, ptr %$actor.addr
  %fp2 = getelementptr i8, ptr %ld1, i64 16
  %fv3 = load ptr, ptr %fp2, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv3, ptr %$dispatch_v.addr
  %ld4 = load ptr, ptr %$actor.addr
  %fp5 = getelementptr i8, ptr %ld4, i64 24
  %fv6 = load i64, ptr %fp5, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv6, ptr %$alive_v.addr
  %ld7 = load ptr, ptr %$actor.addr
  %fp8 = getelementptr i8, ptr %ld7, i64 32
  %fv9 = load i64, ptr %fp8, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv9, ptr %$sf_value.addr
  %hp10 = call ptr @march_alloc(i64 24)
  %tgp11 = getelementptr i8, ptr %hp10, i64 8
  store i32 0, ptr %tgp11, align 4
  %ld12 = load i64, ptr %$sf_value.addr
  %fp13 = getelementptr i8, ptr %hp10, i64 16
  store i64 %ld12, ptr %fp13, align 8
  %state.addr = alloca ptr
  store ptr %hp10, ptr %state.addr
  %ld14 = load ptr, ptr %state.addr
  %fp15 = getelementptr i8, ptr %ld14, i64 16
  %fv16 = load i64, ptr %fp15, align 8
  %$t2009.addr = alloca i64
  store i64 %fv16, ptr %$t2009.addr
  %ld17 = load i64, ptr %$t2009.addr
  %ld18 = load i64, ptr %n.addr
  %ar19 = add i64 %ld17, %ld18
  %$t2010.addr = alloca i64
  store i64 %ar19, ptr %$t2010.addr
  %ld20 = load ptr, ptr %state.addr
  %hp21 = call ptr @march_alloc(i64 24)
  %tgp22 = getelementptr i8, ptr %hp21, i64 8
  store i32 0, ptr %tgp22, align 4
  %fp23 = getelementptr i8, ptr %ld20, i64 16
  %fv24 = load i64, ptr %fp23, align 8
  %fp25 = getelementptr i8, ptr %hp21, i64 16
  store i64 %fv24, ptr %fp25, align 8
  %ld26 = load i64, ptr %$t2010.addr
  %fp27 = getelementptr i8, ptr %hp21, i64 16
  store i64 %ld26, ptr %fp27, align 8
  %$result.addr = alloca ptr
  store ptr %hp21, ptr %$result.addr
  %ld28 = load ptr, ptr %$result.addr
  %fp29 = getelementptr i8, ptr %ld28, i64 16
  %fv30 = load i64, ptr %fp29, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv30, ptr %$nf_value.addr
  %ld31 = load ptr, ptr %$actor.addr
  %ld32 = load ptr, ptr %$dispatch_v.addr
  %ld33 = load i64, ptr %$alive_v.addr
  %ld34 = load i64, ptr %$nf_value.addr
  %rc35 = load i64, ptr %ld31, align 8
  %uniq36 = icmp eq i64 %rc35, 1
  %fbip_slot37 = alloca ptr
  br i1 %uniq36, label %fbip_reuse1, label %fbip_fresh2
fbip_reuse1:
  %tgp38 = getelementptr i8, ptr %ld31, i64 8
  store i32 0, ptr %tgp38, align 4
  %fp39 = getelementptr i8, ptr %ld31, i64 16
  store ptr %ld32, ptr %fp39, align 8
  %fp40 = getelementptr i8, ptr %ld31, i64 24
  store i64 %ld33, ptr %fp40, align 8
  %fp41 = getelementptr i8, ptr %ld31, i64 32
  store i64 %ld34, ptr %fp41, align 8
  store ptr %ld31, ptr %fbip_slot37
  br label %fbip_merge3
fbip_fresh2:
  call void @march_decrc(ptr %ld31)
  %hp42 = call ptr @march_alloc(i64 40)
  %tgp43 = getelementptr i8, ptr %hp42, i64 8
  store i32 0, ptr %tgp43, align 4
  %fp44 = getelementptr i8, ptr %hp42, i64 16
  store ptr %ld32, ptr %fp44, align 8
  %fp45 = getelementptr i8, ptr %hp42, i64 24
  store i64 %ld33, ptr %fp45, align 8
  %fp46 = getelementptr i8, ptr %hp42, i64 32
  store i64 %ld34, ptr %fp46, align 8
  store ptr %hp42, ptr %fbip_slot37
  br label %fbip_merge3
fbip_merge3:
  %fbip_r47 = load ptr, ptr %fbip_slot37
  ret void
}

define void @Counter_Decrement(ptr %$actor.arg, i64 %n.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld48 = load ptr, ptr %$actor.addr
  %fp49 = getelementptr i8, ptr %ld48, i64 16
  %fv50 = load ptr, ptr %fp49, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv50, ptr %$dispatch_v.addr
  %ld51 = load ptr, ptr %$actor.addr
  %fp52 = getelementptr i8, ptr %ld51, i64 24
  %fv53 = load i64, ptr %fp52, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv53, ptr %$alive_v.addr
  %ld54 = load ptr, ptr %$actor.addr
  %fp55 = getelementptr i8, ptr %ld54, i64 32
  %fv56 = load i64, ptr %fp55, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv56, ptr %$sf_value.addr
  %hp57 = call ptr @march_alloc(i64 24)
  %tgp58 = getelementptr i8, ptr %hp57, i64 8
  store i32 0, ptr %tgp58, align 4
  %ld59 = load i64, ptr %$sf_value.addr
  %fp60 = getelementptr i8, ptr %hp57, i64 16
  store i64 %ld59, ptr %fp60, align 8
  %state.addr = alloca ptr
  store ptr %hp57, ptr %state.addr
  %ld61 = load ptr, ptr %state.addr
  %fp62 = getelementptr i8, ptr %ld61, i64 16
  %fv63 = load i64, ptr %fp62, align 8
  %$t2011.addr = alloca i64
  store i64 %fv63, ptr %$t2011.addr
  %ld64 = load i64, ptr %$t2011.addr
  %ld65 = load i64, ptr %n.addr
  %ar66 = sub i64 %ld64, %ld65
  %$t2012.addr = alloca i64
  store i64 %ar66, ptr %$t2012.addr
  %ld67 = load ptr, ptr %state.addr
  %hp68 = call ptr @march_alloc(i64 24)
  %tgp69 = getelementptr i8, ptr %hp68, i64 8
  store i32 0, ptr %tgp69, align 4
  %fp70 = getelementptr i8, ptr %ld67, i64 16
  %fv71 = load i64, ptr %fp70, align 8
  %fp72 = getelementptr i8, ptr %hp68, i64 16
  store i64 %fv71, ptr %fp72, align 8
  %ld73 = load i64, ptr %$t2012.addr
  %fp74 = getelementptr i8, ptr %hp68, i64 16
  store i64 %ld73, ptr %fp74, align 8
  %$result.addr = alloca ptr
  store ptr %hp68, ptr %$result.addr
  %ld75 = load ptr, ptr %$result.addr
  %fp76 = getelementptr i8, ptr %ld75, i64 16
  %fv77 = load i64, ptr %fp76, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv77, ptr %$nf_value.addr
  %ld78 = load ptr, ptr %$actor.addr
  %ld79 = load ptr, ptr %$dispatch_v.addr
  %ld80 = load i64, ptr %$alive_v.addr
  %ld81 = load i64, ptr %$nf_value.addr
  %rc82 = load i64, ptr %ld78, align 8
  %uniq83 = icmp eq i64 %rc82, 1
  %fbip_slot84 = alloca ptr
  br i1 %uniq83, label %fbip_reuse4, label %fbip_fresh5
fbip_reuse4:
  %tgp85 = getelementptr i8, ptr %ld78, i64 8
  store i32 0, ptr %tgp85, align 4
  %fp86 = getelementptr i8, ptr %ld78, i64 16
  store ptr %ld79, ptr %fp86, align 8
  %fp87 = getelementptr i8, ptr %ld78, i64 24
  store i64 %ld80, ptr %fp87, align 8
  %fp88 = getelementptr i8, ptr %ld78, i64 32
  store i64 %ld81, ptr %fp88, align 8
  store ptr %ld78, ptr %fbip_slot84
  br label %fbip_merge6
fbip_fresh5:
  call void @march_decrc(ptr %ld78)
  %hp89 = call ptr @march_alloc(i64 40)
  %tgp90 = getelementptr i8, ptr %hp89, i64 8
  store i32 0, ptr %tgp90, align 4
  %fp91 = getelementptr i8, ptr %hp89, i64 16
  store ptr %ld79, ptr %fp91, align 8
  %fp92 = getelementptr i8, ptr %hp89, i64 24
  store i64 %ld80, ptr %fp92, align 8
  %fp93 = getelementptr i8, ptr %hp89, i64 32
  store i64 %ld81, ptr %fp93, align 8
  store ptr %hp89, ptr %fbip_slot84
  br label %fbip_merge6
fbip_merge6:
  %fbip_r94 = load ptr, ptr %fbip_slot84
  ret void
}

define void @Counter_Reset(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %ld95 = load ptr, ptr %$actor.addr
  %fp96 = getelementptr i8, ptr %ld95, i64 16
  %fv97 = load ptr, ptr %fp96, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv97, ptr %$dispatch_v.addr
  %ld98 = load ptr, ptr %$actor.addr
  %fp99 = getelementptr i8, ptr %ld98, i64 24
  %fv100 = load i64, ptr %fp99, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv100, ptr %$alive_v.addr
  %ld101 = load ptr, ptr %$actor.addr
  %fp102 = getelementptr i8, ptr %ld101, i64 32
  %fv103 = load i64, ptr %fp102, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv103, ptr %$sf_value.addr
  %hp104 = call ptr @march_alloc(i64 24)
  %tgp105 = getelementptr i8, ptr %hp104, i64 8
  store i32 0, ptr %tgp105, align 4
  %ld106 = load i64, ptr %$sf_value.addr
  %fp107 = getelementptr i8, ptr %hp104, i64 16
  store i64 %ld106, ptr %fp107, align 8
  %state.addr = alloca ptr
  store ptr %hp104, ptr %state.addr
  %ld108 = load ptr, ptr %state.addr
  %hp109 = call ptr @march_alloc(i64 24)
  %tgp110 = getelementptr i8, ptr %hp109, i64 8
  store i32 0, ptr %tgp110, align 4
  %fp111 = getelementptr i8, ptr %ld108, i64 16
  %fv112 = load i64, ptr %fp111, align 8
  %fp113 = getelementptr i8, ptr %hp109, i64 16
  store i64 %fv112, ptr %fp113, align 8
  %fp114 = getelementptr i8, ptr %hp109, i64 16
  store i64 0, ptr %fp114, align 8
  %$result.addr = alloca ptr
  store ptr %hp109, ptr %$result.addr
  %ld115 = load ptr, ptr %$result.addr
  %fp116 = getelementptr i8, ptr %ld115, i64 16
  %fv117 = load i64, ptr %fp116, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv117, ptr %$nf_value.addr
  %ld118 = load ptr, ptr %$actor.addr
  %ld119 = load ptr, ptr %$dispatch_v.addr
  %ld120 = load i64, ptr %$alive_v.addr
  %ld121 = load i64, ptr %$nf_value.addr
  %rc122 = load i64, ptr %ld118, align 8
  %uniq123 = icmp eq i64 %rc122, 1
  %fbip_slot124 = alloca ptr
  br i1 %uniq123, label %fbip_reuse7, label %fbip_fresh8
fbip_reuse7:
  %tgp125 = getelementptr i8, ptr %ld118, i64 8
  store i32 0, ptr %tgp125, align 4
  %fp126 = getelementptr i8, ptr %ld118, i64 16
  store ptr %ld119, ptr %fp126, align 8
  %fp127 = getelementptr i8, ptr %ld118, i64 24
  store i64 %ld120, ptr %fp127, align 8
  %fp128 = getelementptr i8, ptr %ld118, i64 32
  store i64 %ld121, ptr %fp128, align 8
  store ptr %ld118, ptr %fbip_slot124
  br label %fbip_merge9
fbip_fresh8:
  call void @march_decrc(ptr %ld118)
  %hp129 = call ptr @march_alloc(i64 40)
  %tgp130 = getelementptr i8, ptr %hp129, i64 8
  store i32 0, ptr %tgp130, align 4
  %fp131 = getelementptr i8, ptr %hp129, i64 16
  store ptr %ld119, ptr %fp131, align 8
  %fp132 = getelementptr i8, ptr %hp129, i64 24
  store i64 %ld120, ptr %fp132, align 8
  %fp133 = getelementptr i8, ptr %hp129, i64 32
  store i64 %ld121, ptr %fp133, align 8
  store ptr %hp129, ptr %fbip_slot124
  br label %fbip_merge9
fbip_merge9:
  %fbip_r134 = load ptr, ptr %fbip_slot124
  ret void
}

define void @Counter_Ping(ptr %$actor.arg, ptr %label.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %label.addr = alloca ptr
  store ptr %label.arg, ptr %label.addr
  %ld135 = load ptr, ptr %$actor.addr
  %fp136 = getelementptr i8, ptr %ld135, i64 16
  %fv137 = load ptr, ptr %fp136, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv137, ptr %$dispatch_v.addr
  %ld138 = load ptr, ptr %$actor.addr
  %fp139 = getelementptr i8, ptr %ld138, i64 24
  %fv140 = load i64, ptr %fp139, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv140, ptr %$alive_v.addr
  %ld141 = load ptr, ptr %$actor.addr
  %fp142 = getelementptr i8, ptr %ld141, i64 32
  %fv143 = load i64, ptr %fp142, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv143, ptr %$sf_value.addr
  %hp144 = call ptr @march_alloc(i64 24)
  %tgp145 = getelementptr i8, ptr %hp144, i64 8
  store i32 0, ptr %tgp145, align 4
  %ld146 = load i64, ptr %$sf_value.addr
  %fp147 = getelementptr i8, ptr %hp144, i64 16
  store i64 %ld146, ptr %fp147, align 8
  %state.addr = alloca ptr
  store ptr %hp144, ptr %state.addr
  %sl148 = call ptr @march_string_lit(ptr @.str1, i64 20)
  %ld149 = load ptr, ptr %label.addr
  %cr150 = call ptr @march_string_concat(ptr %sl148, ptr %ld149)
  %$t2013.addr = alloca ptr
  store ptr %cr150, ptr %$t2013.addr
  %ld151 = load ptr, ptr %$t2013.addr
  %sl152 = call ptr @march_string_lit(ptr @.str2, i64 10)
  %cr153 = call ptr @march_string_concat(ptr %ld151, ptr %sl152)
  %$t2014.addr = alloca ptr
  store ptr %cr153, ptr %$t2014.addr
  %ld154 = load ptr, ptr %state.addr
  %fp155 = getelementptr i8, ptr %ld154, i64 16
  %fv156 = load i64, ptr %fp155, align 8
  %$t2015.addr = alloca i64
  store i64 %fv156, ptr %$t2015.addr
  %ld157 = load i64, ptr %$t2015.addr
  %cr158 = call ptr @march_int_to_string(i64 %ld157)
  %$t2016.addr = alloca ptr
  store ptr %cr158, ptr %$t2016.addr
  %ld159 = load ptr, ptr %$t2014.addr
  %ld160 = load ptr, ptr %$t2016.addr
  %cr161 = call ptr @march_string_concat(ptr %ld159, ptr %ld160)
  %$t2017.addr = alloca ptr
  store ptr %cr161, ptr %$t2017.addr
  %ld162 = load ptr, ptr %$t2017.addr
  call void @march_println(ptr %ld162)
  %ld163 = load ptr, ptr %state.addr
  %$result.addr = alloca ptr
  store ptr %ld163, ptr %$result.addr
  %ld164 = load ptr, ptr %$result.addr
  %fp165 = getelementptr i8, ptr %ld164, i64 16
  %fv166 = load i64, ptr %fp165, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv166, ptr %$nf_value.addr
  %ld167 = load ptr, ptr %$actor.addr
  %ld168 = load ptr, ptr %$dispatch_v.addr
  %ld169 = load i64, ptr %$alive_v.addr
  %ld170 = load i64, ptr %$nf_value.addr
  %rc171 = load i64, ptr %ld167, align 8
  %uniq172 = icmp eq i64 %rc171, 1
  %fbip_slot173 = alloca ptr
  br i1 %uniq172, label %fbip_reuse10, label %fbip_fresh11
fbip_reuse10:
  %tgp174 = getelementptr i8, ptr %ld167, i64 8
  store i32 0, ptr %tgp174, align 4
  %fp175 = getelementptr i8, ptr %ld167, i64 16
  store ptr %ld168, ptr %fp175, align 8
  %fp176 = getelementptr i8, ptr %ld167, i64 24
  store i64 %ld169, ptr %fp176, align 8
  %fp177 = getelementptr i8, ptr %ld167, i64 32
  store i64 %ld170, ptr %fp177, align 8
  store ptr %ld167, ptr %fbip_slot173
  br label %fbip_merge12
fbip_fresh11:
  call void @march_decrc(ptr %ld167)
  %hp178 = call ptr @march_alloc(i64 40)
  %tgp179 = getelementptr i8, ptr %hp178, i64 8
  store i32 0, ptr %tgp179, align 4
  %fp180 = getelementptr i8, ptr %hp178, i64 16
  store ptr %ld168, ptr %fp180, align 8
  %fp181 = getelementptr i8, ptr %hp178, i64 24
  store i64 %ld169, ptr %fp181, align 8
  %fp182 = getelementptr i8, ptr %hp178, i64 32
  store i64 %ld170, ptr %fp182, align 8
  store ptr %hp178, ptr %fbip_slot173
  br label %fbip_merge12
fbip_merge12:
  %fbip_r183 = load ptr, ptr %fbip_slot173
  ret void
}

define void @Counter_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld184 = load ptr, ptr %$msg.addr
  %res_slot185 = alloca ptr
  %tgp186 = getelementptr i8, ptr %ld184, i64 8
  %tag187 = load i32, ptr %tgp186, align 4
  switch i32 %tag187, label %case_default14 [
      i32 0, label %case_br15
      i32 1, label %case_br16
      i32 2, label %case_br17
      i32 3, label %case_br18
  ]
case_br15:
  %fp188 = getelementptr i8, ptr %ld184, i64 16
  %fv189 = load i64, ptr %fp188, align 8
  %$Increment_n.addr = alloca i64
  store i64 %fv189, ptr %$Increment_n.addr
  %ld190 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld190)
  %ld191 = load ptr, ptr %$actor.addr
  %ld192 = load i64, ptr %$Increment_n.addr
  call void @Counter_Increment(ptr %ld191, i64 %ld192)
  %cv193 = inttoptr i64 0 to ptr
  store ptr %cv193, ptr %res_slot185
  br label %case_merge13
case_br16:
  %fp194 = getelementptr i8, ptr %ld184, i64 16
  %fv195 = load i64, ptr %fp194, align 8
  %$Decrement_n.addr = alloca i64
  store i64 %fv195, ptr %$Decrement_n.addr
  %ld196 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld196)
  %ld197 = load ptr, ptr %$actor.addr
  %ld198 = load i64, ptr %$Decrement_n.addr
  call void @Counter_Decrement(ptr %ld197, i64 %ld198)
  %cv199 = inttoptr i64 0 to ptr
  store ptr %cv199, ptr %res_slot185
  br label %case_merge13
case_br17:
  %ld200 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld200)
  %ld201 = load ptr, ptr %$actor.addr
  call void @Counter_Reset(ptr %ld201)
  %cv202 = inttoptr i64 0 to ptr
  store ptr %cv202, ptr %res_slot185
  br label %case_merge13
case_br18:
  %fp203 = getelementptr i8, ptr %ld184, i64 16
  %fv204 = load ptr, ptr %fp203, align 8
  %$Ping_label.addr = alloca ptr
  store ptr %fv204, ptr %$Ping_label.addr
  %freed205 = call i64 @march_decrc_freed(ptr %ld184)
  %freed_b206 = icmp ne i64 %freed205, 0
  br i1 %freed_b206, label %br_unique19, label %br_shared20
br_shared20:
  call void @march_incrc(ptr %fv204)
  br label %br_body21
br_unique19:
  br label %br_body21
br_body21:
  %ld207 = load ptr, ptr %$actor.addr
  %ld208 = load ptr, ptr %$Ping_label.addr
  call void @Counter_Ping(ptr %ld207, ptr %ld208)
  %cv209 = inttoptr i64 0 to ptr
  store ptr %cv209, ptr %res_slot185
  br label %case_merge13
case_default14:
  unreachable
case_merge13:
  %case_r210 = load ptr, ptr %res_slot185
  ret void
}

define void @Logger_Log(ptr %$actor.arg, ptr %msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %ld211 = load ptr, ptr %$actor.addr
  %fp212 = getelementptr i8, ptr %ld211, i64 16
  %fv213 = load ptr, ptr %fp212, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv213, ptr %$dispatch_v.addr
  %ld214 = load ptr, ptr %$actor.addr
  %fp215 = getelementptr i8, ptr %ld214, i64 24
  %fv216 = load i64, ptr %fp215, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv216, ptr %$alive_v.addr
  %ld217 = load ptr, ptr %$actor.addr
  %fp218 = getelementptr i8, ptr %ld217, i64 32
  %fv219 = load i64, ptr %fp218, align 8
  %$sf_count.addr = alloca i64
  store i64 %fv219, ptr %$sf_count.addr
  %hp220 = call ptr @march_alloc(i64 24)
  %tgp221 = getelementptr i8, ptr %hp220, i64 8
  store i32 0, ptr %tgp221, align 4
  %ld222 = load i64, ptr %$sf_count.addr
  %fp223 = getelementptr i8, ptr %hp220, i64 16
  store i64 %ld222, ptr %fp223, align 8
  %state.addr = alloca ptr
  store ptr %hp220, ptr %state.addr
  %ld224 = load ptr, ptr %state.addr
  %fp225 = getelementptr i8, ptr %ld224, i64 16
  %fv226 = load i64, ptr %fp225, align 8
  %$t2018.addr = alloca i64
  store i64 %fv226, ptr %$t2018.addr
  %ld227 = load i64, ptr %$t2018.addr
  %ar228 = add i64 %ld227, 1
  %n.addr = alloca i64
  store i64 %ar228, ptr %n.addr
  %ld229 = load i64, ptr %n.addr
  %cr230 = call ptr @march_int_to_string(i64 %ld229)
  %$t2019.addr = alloca ptr
  store ptr %cr230, ptr %$t2019.addr
  %sl231 = call ptr @march_string_lit(ptr @.str3, i64 6)
  %ld232 = load ptr, ptr %$t2019.addr
  %cr233 = call ptr @march_string_concat(ptr %sl231, ptr %ld232)
  %$t2020.addr = alloca ptr
  store ptr %cr233, ptr %$t2020.addr
  %ld234 = load ptr, ptr %$t2020.addr
  %sl235 = call ptr @march_string_lit(ptr @.str4, i64 2)
  %cr236 = call ptr @march_string_concat(ptr %ld234, ptr %sl235)
  %$t2021.addr = alloca ptr
  store ptr %cr236, ptr %$t2021.addr
  %ld237 = load ptr, ptr %$t2021.addr
  %ld238 = load ptr, ptr %msg.addr
  %cr239 = call ptr @march_string_concat(ptr %ld237, ptr %ld238)
  %$t2022.addr = alloca ptr
  store ptr %cr239, ptr %$t2022.addr
  %ld240 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld240)
  %ld241 = load ptr, ptr %state.addr
  %hp242 = call ptr @march_alloc(i64 24)
  %tgp243 = getelementptr i8, ptr %hp242, i64 8
  store i32 0, ptr %tgp243, align 4
  %fp244 = getelementptr i8, ptr %ld241, i64 16
  %fv245 = load i64, ptr %fp244, align 8
  %fp246 = getelementptr i8, ptr %hp242, i64 16
  store i64 %fv245, ptr %fp246, align 8
  %ld247 = load i64, ptr %n.addr
  %fp248 = getelementptr i8, ptr %hp242, i64 16
  store i64 %ld247, ptr %fp248, align 8
  %$result.addr = alloca ptr
  store ptr %hp242, ptr %$result.addr
  %ld249 = load ptr, ptr %$result.addr
  %fp250 = getelementptr i8, ptr %ld249, i64 16
  %fv251 = load i64, ptr %fp250, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv251, ptr %$nf_count.addr
  %ld252 = load ptr, ptr %$actor.addr
  %ld253 = load ptr, ptr %$dispatch_v.addr
  %ld254 = load i64, ptr %$alive_v.addr
  %ld255 = load i64, ptr %$nf_count.addr
  %rc256 = load i64, ptr %ld252, align 8
  %uniq257 = icmp eq i64 %rc256, 1
  %fbip_slot258 = alloca ptr
  br i1 %uniq257, label %fbip_reuse22, label %fbip_fresh23
fbip_reuse22:
  %tgp259 = getelementptr i8, ptr %ld252, i64 8
  store i32 0, ptr %tgp259, align 4
  %fp260 = getelementptr i8, ptr %ld252, i64 16
  store ptr %ld253, ptr %fp260, align 8
  %fp261 = getelementptr i8, ptr %ld252, i64 24
  store i64 %ld254, ptr %fp261, align 8
  %fp262 = getelementptr i8, ptr %ld252, i64 32
  store i64 %ld255, ptr %fp262, align 8
  store ptr %ld252, ptr %fbip_slot258
  br label %fbip_merge24
fbip_fresh23:
  call void @march_decrc(ptr %ld252)
  %hp263 = call ptr @march_alloc(i64 40)
  %tgp264 = getelementptr i8, ptr %hp263, i64 8
  store i32 0, ptr %tgp264, align 4
  %fp265 = getelementptr i8, ptr %hp263, i64 16
  store ptr %ld253, ptr %fp265, align 8
  %fp266 = getelementptr i8, ptr %hp263, i64 24
  store i64 %ld254, ptr %fp266, align 8
  %fp267 = getelementptr i8, ptr %hp263, i64 32
  store i64 %ld255, ptr %fp267, align 8
  store ptr %hp263, ptr %fbip_slot258
  br label %fbip_merge24
fbip_merge24:
  %fbip_r268 = load ptr, ptr %fbip_slot258
  ret void
}

define void @Logger_Stats(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %ld269 = load ptr, ptr %$actor.addr
  %fp270 = getelementptr i8, ptr %ld269, i64 16
  %fv271 = load ptr, ptr %fp270, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv271, ptr %$dispatch_v.addr
  %ld272 = load ptr, ptr %$actor.addr
  %fp273 = getelementptr i8, ptr %ld272, i64 24
  %fv274 = load i64, ptr %fp273, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv274, ptr %$alive_v.addr
  %ld275 = load ptr, ptr %$actor.addr
  %fp276 = getelementptr i8, ptr %ld275, i64 32
  %fv277 = load i64, ptr %fp276, align 8
  %$sf_count.addr = alloca i64
  store i64 %fv277, ptr %$sf_count.addr
  %hp278 = call ptr @march_alloc(i64 24)
  %tgp279 = getelementptr i8, ptr %hp278, i64 8
  store i32 0, ptr %tgp279, align 4
  %ld280 = load i64, ptr %$sf_count.addr
  %fp281 = getelementptr i8, ptr %hp278, i64 16
  store i64 %ld280, ptr %fp281, align 8
  %state.addr = alloca ptr
  store ptr %hp278, ptr %state.addr
  %ld282 = load ptr, ptr %state.addr
  %fp283 = getelementptr i8, ptr %ld282, i64 16
  %fv284 = load i64, ptr %fp283, align 8
  %$t2023.addr = alloca i64
  store i64 %fv284, ptr %$t2023.addr
  %ld285 = load i64, ptr %$t2023.addr
  %cr286 = call ptr @march_int_to_string(i64 %ld285)
  %$t2024.addr = alloca ptr
  store ptr %cr286, ptr %$t2024.addr
  %sl287 = call ptr @march_string_lit(ptr @.str5, i64 32)
  %ld288 = load ptr, ptr %$t2024.addr
  %cr289 = call ptr @march_string_concat(ptr %sl287, ptr %ld288)
  %$t2025.addr = alloca ptr
  store ptr %cr289, ptr %$t2025.addr
  %ld290 = load ptr, ptr %$t2025.addr
  call void @march_println(ptr %ld290)
  %ld291 = load ptr, ptr %state.addr
  %$result.addr = alloca ptr
  store ptr %ld291, ptr %$result.addr
  %ld292 = load ptr, ptr %$result.addr
  %fp293 = getelementptr i8, ptr %ld292, i64 16
  %fv294 = load i64, ptr %fp293, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv294, ptr %$nf_count.addr
  %ld295 = load ptr, ptr %$actor.addr
  %ld296 = load ptr, ptr %$dispatch_v.addr
  %ld297 = load i64, ptr %$alive_v.addr
  %ld298 = load i64, ptr %$nf_count.addr
  %rc299 = load i64, ptr %ld295, align 8
  %uniq300 = icmp eq i64 %rc299, 1
  %fbip_slot301 = alloca ptr
  br i1 %uniq300, label %fbip_reuse25, label %fbip_fresh26
fbip_reuse25:
  %tgp302 = getelementptr i8, ptr %ld295, i64 8
  store i32 0, ptr %tgp302, align 4
  %fp303 = getelementptr i8, ptr %ld295, i64 16
  store ptr %ld296, ptr %fp303, align 8
  %fp304 = getelementptr i8, ptr %ld295, i64 24
  store i64 %ld297, ptr %fp304, align 8
  %fp305 = getelementptr i8, ptr %ld295, i64 32
  store i64 %ld298, ptr %fp305, align 8
  store ptr %ld295, ptr %fbip_slot301
  br label %fbip_merge27
fbip_fresh26:
  call void @march_decrc(ptr %ld295)
  %hp306 = call ptr @march_alloc(i64 40)
  %tgp307 = getelementptr i8, ptr %hp306, i64 8
  store i32 0, ptr %tgp307, align 4
  %fp308 = getelementptr i8, ptr %hp306, i64 16
  store ptr %ld296, ptr %fp308, align 8
  %fp309 = getelementptr i8, ptr %hp306, i64 24
  store i64 %ld297, ptr %fp309, align 8
  %fp310 = getelementptr i8, ptr %hp306, i64 32
  store i64 %ld298, ptr %fp310, align 8
  store ptr %hp306, ptr %fbip_slot301
  br label %fbip_merge27
fbip_merge27:
  %fbip_r311 = load ptr, ptr %fbip_slot301
  ret void
}

define void @Logger_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld312 = load ptr, ptr %$msg.addr
  %res_slot313 = alloca ptr
  %tgp314 = getelementptr i8, ptr %ld312, i64 8
  %tag315 = load i32, ptr %tgp314, align 4
  switch i32 %tag315, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %fp316 = getelementptr i8, ptr %ld312, i64 16
  %fv317 = load ptr, ptr %fp316, align 8
  %$Log_msg.addr = alloca ptr
  store ptr %fv317, ptr %$Log_msg.addr
  %freed318 = call i64 @march_decrc_freed(ptr %ld312)
  %freed_b319 = icmp ne i64 %freed318, 0
  br i1 %freed_b319, label %br_unique32, label %br_shared33
br_shared33:
  call void @march_incrc(ptr %fv317)
  br label %br_body34
br_unique32:
  br label %br_body34
br_body34:
  %ld320 = load ptr, ptr %$actor.addr
  %ld321 = load ptr, ptr %$Log_msg.addr
  call void @Logger_Log(ptr %ld320, ptr %ld321)
  %cv322 = inttoptr i64 0 to ptr
  store ptr %cv322, ptr %res_slot313
  br label %case_merge28
case_br31:
  %ld323 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld323)
  %ld324 = load ptr, ptr %$actor.addr
  call void @Logger_Stats(ptr %ld324)
  %cv325 = inttoptr i64 0 to ptr
  store ptr %cv325, ptr %res_slot313
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r326 = load ptr, ptr %res_slot313
  ret void
}

define ptr @Logger_spawn() {
entry:
  %hp327 = call ptr @march_alloc(i64 24)
  %tgp328 = getelementptr i8, ptr %hp327, i64 8
  store i32 0, ptr %tgp328, align 4
  %fp329 = getelementptr i8, ptr %hp327, i64 16
  store i64 0, ptr %fp329, align 8
  %$init_state.addr = alloca ptr
  store ptr %hp327, ptr %$init_state.addr
  %ld330 = load ptr, ptr %$init_state.addr
  %fp331 = getelementptr i8, ptr %ld330, i64 16
  %fv332 = load i64, ptr %fp331, align 8
  %$init_count.addr = alloca i64
  store i64 %fv332, ptr %$init_count.addr
  %hp333 = call ptr @march_alloc(i64 40)
  %tgp334 = getelementptr i8, ptr %hp333, i64 8
  store i32 0, ptr %tgp334, align 4
  %cwrap335 = call ptr @march_alloc(i64 24)
  %cwt336 = getelementptr i8, ptr %cwrap335, i64 8
  store i32 0, ptr %cwt336, align 4
  %cwf337 = getelementptr i8, ptr %cwrap335, i64 16
  store ptr @Logger_dispatch$clo_wrap, ptr %cwf337, align 8
  %fp338 = getelementptr i8, ptr %hp333, i64 16
  store ptr %cwrap335, ptr %fp338, align 8
  %fp339 = getelementptr i8, ptr %hp333, i64 24
  store i64 1, ptr %fp339, align 8
  %ld340 = load i64, ptr %$init_count.addr
  %fp341 = getelementptr i8, ptr %hp333, i64 32
  store i64 %ld340, ptr %fp341, align 8
  %$spawned.addr = alloca ptr
  store ptr %hp333, ptr %$spawned.addr
  %ld342 = load ptr, ptr %$spawned.addr
  ret ptr %ld342
}

define void @march_main() {
entry:
  %sl343 = call ptr @march_string_lit(ptr @.str6, i64 23)
  call void @march_println(ptr %sl343)
  %hp344 = call ptr @march_alloc(i64 24)
  %tgp345 = getelementptr i8, ptr %hp344, i64 8
  store i32 0, ptr %tgp345, align 4
  %fp346 = getelementptr i8, ptr %hp344, i64 16
  store i64 0, ptr %fp346, align 8
  %$init_state_i29.addr = alloca ptr
  store ptr %hp344, ptr %$init_state_i29.addr
  %ld347 = load ptr, ptr %$init_state_i29.addr
  %fp348 = getelementptr i8, ptr %ld347, i64 16
  %fv349 = load i64, ptr %fp348, align 8
  %$init_value_i30.addr = alloca i64
  store i64 %fv349, ptr %$init_value_i30.addr
  %hp350 = call ptr @march_alloc(i64 40)
  %tgp351 = getelementptr i8, ptr %hp350, i64 8
  store i32 0, ptr %tgp351, align 4
  %cwrap352 = call ptr @march_alloc(i64 24)
  %cwt353 = getelementptr i8, ptr %cwrap352, i64 8
  store i32 0, ptr %cwt353, align 4
  %cwf354 = getelementptr i8, ptr %cwrap352, i64 16
  store ptr @Counter_dispatch$clo_wrap, ptr %cwf354, align 8
  %fp355 = getelementptr i8, ptr %hp350, i64 16
  store ptr %cwrap352, ptr %fp355, align 8
  %fp356 = getelementptr i8, ptr %hp350, i64 24
  store i64 1, ptr %fp356, align 8
  %ld357 = load i64, ptr %$init_value_i30.addr
  %fp358 = getelementptr i8, ptr %hp350, i64 32
  store i64 %ld357, ptr %fp358, align 8
  %$spawned_i31.addr = alloca ptr
  store ptr %hp350, ptr %$spawned_i31.addr
  %ld359 = load ptr, ptr %$spawned_i31.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld359, ptr %$raw_actor.addr
  %ld360 = load ptr, ptr %$raw_actor.addr
  %cr361 = call ptr @march_spawn(ptr %ld360)
  %counter.addr = alloca ptr
  store ptr %cr361, ptr %counter.addr
  %hp362 = call ptr @march_alloc(i64 24)
  %tgp363 = getelementptr i8, ptr %hp362, i64 8
  store i32 0, ptr %tgp363, align 4
  %fp364 = getelementptr i8, ptr %hp362, i64 16
  store i64 0, ptr %fp364, align 8
  %$init_state_i26.addr = alloca ptr
  store ptr %hp362, ptr %$init_state_i26.addr
  %ld365 = load ptr, ptr %$init_state_i26.addr
  %fp366 = getelementptr i8, ptr %ld365, i64 16
  %fv367 = load i64, ptr %fp366, align 8
  %$init_count_i27.addr = alloca i64
  store i64 %fv367, ptr %$init_count_i27.addr
  %hp368 = call ptr @march_alloc(i64 40)
  %tgp369 = getelementptr i8, ptr %hp368, i64 8
  store i32 0, ptr %tgp369, align 4
  %cwrap370 = call ptr @march_alloc(i64 24)
  %cwt371 = getelementptr i8, ptr %cwrap370, i64 8
  store i32 0, ptr %cwt371, align 4
  %cwf372 = getelementptr i8, ptr %cwrap370, i64 16
  store ptr @Logger_dispatch$clo_wrap, ptr %cwf372, align 8
  %fp373 = getelementptr i8, ptr %hp368, i64 16
  store ptr %cwrap370, ptr %fp373, align 8
  %fp374 = getelementptr i8, ptr %hp368, i64 24
  store i64 1, ptr %fp374, align 8
  %ld375 = load i64, ptr %$init_count_i27.addr
  %fp376 = getelementptr i8, ptr %hp368, i64 32
  store i64 %ld375, ptr %fp376, align 8
  %$spawned_i28.addr = alloca ptr
  store ptr %hp368, ptr %$spawned_i28.addr
  %ld377 = load ptr, ptr %$spawned_i28.addr
  %$raw_actor_1.addr = alloca ptr
  store ptr %ld377, ptr %$raw_actor_1.addr
  %ld378 = load ptr, ptr %$raw_actor_1.addr
  %cr379 = call ptr @march_spawn(ptr %ld378)
  %logger.addr = alloca ptr
  store ptr %cr379, ptr %logger.addr
  %ld380 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld380)
  %ld381 = load ptr, ptr %counter.addr
  %cr382 = call i64 @march_is_alive(ptr %ld381)
  %$t2029.addr = alloca i64
  store i64 %cr382, ptr %$t2029.addr
  %ld383 = load i64, ptr %$t2029.addr
  %cr384 = call ptr @march_bool_to_string(i64 %ld383)
  %$t2030.addr = alloca ptr
  store ptr %cr384, ptr %$t2030.addr
  %sl385 = call ptr @march_string_lit(ptr @.str7, i64 15)
  %ld386 = load ptr, ptr %$t2030.addr
  %cr387 = call ptr @march_string_concat(ptr %sl385, ptr %ld386)
  %$t2031.addr = alloca ptr
  store ptr %cr387, ptr %$t2031.addr
  %ld388 = load ptr, ptr %$t2031.addr
  call void @march_println(ptr %ld388)
  %ld389 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld389)
  %ld390 = load ptr, ptr %logger.addr
  %cr391 = call i64 @march_is_alive(ptr %ld390)
  %$t2032.addr = alloca i64
  store i64 %cr391, ptr %$t2032.addr
  %ld392 = load i64, ptr %$t2032.addr
  %cr393 = call ptr @march_bool_to_string(i64 %ld392)
  %$t2033.addr = alloca ptr
  store ptr %cr393, ptr %$t2033.addr
  %sl394 = call ptr @march_string_lit(ptr @.str8, i64 15)
  %ld395 = load ptr, ptr %$t2033.addr
  %cr396 = call ptr @march_string_concat(ptr %sl394, ptr %ld395)
  %$t2034.addr = alloca ptr
  store ptr %cr396, ptr %$t2034.addr
  %ld397 = load ptr, ptr %$t2034.addr
  call void @march_println(ptr %ld397)
  %sl398 = call ptr @march_string_lit(ptr @.str9, i64 0)
  call void @march_println(ptr %sl398)
  %sl399 = call ptr @march_string_lit(ptr @.str10, i64 44)
  call void @march_println(ptr %sl399)
  %hp400 = call ptr @march_alloc(i64 24)
  %tgp401 = getelementptr i8, ptr %hp400, i64 8
  store i32 0, ptr %tgp401, align 4
  %fp402 = getelementptr i8, ptr %hp400, i64 16
  store i64 10, ptr %fp402, align 8
  %$t2035.addr = alloca ptr
  store ptr %hp400, ptr %$t2035.addr
  %ld403 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld403)
  %ld404 = load ptr, ptr %counter.addr
  %ld405 = load ptr, ptr %$t2035.addr
  %sl406 = call ptr @march_string_lit(ptr @.str11, i64 13)
  %cr407 = call ptr @safe_send$Pid_V__6051$Counter_Msg$String(ptr %ld404, ptr %ld405, ptr %sl406)
  %hp408 = call ptr @march_alloc(i64 24)
  %tgp409 = getelementptr i8, ptr %hp408, i64 8
  store i32 0, ptr %tgp409, align 4
  %sl410 = call ptr @march_string_lit(ptr @.str12, i64 25)
  %fp411 = getelementptr i8, ptr %hp408, i64 16
  store ptr %sl410, ptr %fp411, align 8
  %$t2036.addr = alloca ptr
  store ptr %hp408, ptr %$t2036.addr
  %ld412 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld412)
  %ld413 = load ptr, ptr %logger.addr
  %ld414 = load ptr, ptr %$t2036.addr
  %sl415 = call ptr @march_string_lit(ptr @.str13, i64 3)
  %cr416 = call ptr @safe_send$Pid_V__6054$Logger_Msg$String(ptr %ld413, ptr %ld414, ptr %sl415)
  %hp417 = call ptr @march_alloc(i64 24)
  %tgp418 = getelementptr i8, ptr %hp417, i64 8
  store i32 0, ptr %tgp418, align 4
  %fp419 = getelementptr i8, ptr %hp417, i64 16
  store i64 5, ptr %fp419, align 8
  %$t2037.addr = alloca ptr
  store ptr %hp417, ptr %$t2037.addr
  %ld420 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld420)
  %ld421 = load ptr, ptr %counter.addr
  %ld422 = load ptr, ptr %$t2037.addr
  %sl423 = call ptr @march_string_lit(ptr @.str14, i64 12)
  %cr424 = call ptr @safe_send$Pid_V__6057$Counter_Msg$String(ptr %ld421, ptr %ld422, ptr %sl423)
  %hp425 = call ptr @march_alloc(i64 24)
  %tgp426 = getelementptr i8, ptr %hp425, i64 8
  store i32 0, ptr %tgp426, align 4
  %sl427 = call ptr @march_string_lit(ptr @.str15, i64 24)
  %fp428 = getelementptr i8, ptr %hp425, i64 16
  store ptr %sl427, ptr %fp428, align 8
  %$t2038.addr = alloca ptr
  store ptr %hp425, ptr %$t2038.addr
  %ld429 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld429)
  %ld430 = load ptr, ptr %logger.addr
  %ld431 = load ptr, ptr %$t2038.addr
  %sl432 = call ptr @march_string_lit(ptr @.str16, i64 3)
  %cr433 = call ptr @safe_send$Pid_V__6060$Logger_Msg$String(ptr %ld430, ptr %ld431, ptr %sl432)
  %hp434 = call ptr @march_alloc(i64 24)
  %tgp435 = getelementptr i8, ptr %hp434, i64 8
  store i32 3, ptr %tgp435, align 4
  %sl436 = call ptr @march_string_lit(ptr @.str17, i64 6)
  %fp437 = getelementptr i8, ptr %hp434, i64 16
  store ptr %sl436, ptr %fp437, align 8
  %$t2039.addr = alloca ptr
  store ptr %hp434, ptr %$t2039.addr
  %ld438 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld438)
  %ld439 = load ptr, ptr %counter.addr
  %ld440 = load ptr, ptr %$t2039.addr
  %sl441 = call ptr @march_string_lit(ptr @.str18, i64 4)
  %cr442 = call ptr @safe_send$Pid_V__6063$Counter_Msg$String(ptr %ld439, ptr %ld440, ptr %sl441)
  %hp443 = call ptr @march_alloc(i64 16)
  %tgp444 = getelementptr i8, ptr %hp443, i64 8
  store i32 1, ptr %tgp444, align 4
  %$t2040.addr = alloca ptr
  store ptr %hp443, ptr %$t2040.addr
  %ld445 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld445)
  %ld446 = load ptr, ptr %logger.addr
  %ld447 = load ptr, ptr %$t2040.addr
  %sl448 = call ptr @march_string_lit(ptr @.str19, i64 5)
  %cr449 = call ptr @safe_send$Pid_V__6066$Logger_Msg$String(ptr %ld446, ptr %ld447, ptr %sl448)
  %sl450 = call ptr @march_string_lit(ptr @.str20, i64 0)
  call void @march_println(ptr %sl450)
  %sl451 = call ptr @march_string_lit(ptr @.str21, i64 26)
  call void @march_println(ptr %sl451)
  %ld452 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld452)
  %ld453 = load ptr, ptr %logger.addr
  call void @march_kill(ptr %ld453)
  %ld454 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld454)
  %ld455 = load ptr, ptr %logger.addr
  %cr456 = call i64 @march_is_alive(ptr %ld455)
  %$t2041.addr = alloca i64
  store i64 %cr456, ptr %$t2041.addr
  %ld457 = load i64, ptr %$t2041.addr
  %cr458 = call ptr @march_bool_to_string(i64 %ld457)
  %$t2042.addr = alloca ptr
  store ptr %cr458, ptr %$t2042.addr
  %sl459 = call ptr @march_string_lit(ptr @.str22, i64 15)
  %ld460 = load ptr, ptr %$t2042.addr
  %cr461 = call ptr @march_string_concat(ptr %sl459, ptr %ld460)
  %$t2043.addr = alloca ptr
  store ptr %cr461, ptr %$t2043.addr
  %ld462 = load ptr, ptr %$t2043.addr
  call void @march_println(ptr %ld462)
  %sl463 = call ptr @march_string_lit(ptr @.str23, i64 0)
  call void @march_println(ptr %sl463)
  %sl464 = call ptr @march_string_lit(ptr @.str24, i64 47)
  call void @march_println(ptr %sl464)
  %hp465 = call ptr @march_alloc(i64 24)
  %tgp466 = getelementptr i8, ptr %hp465, i64 8
  store i32 0, ptr %tgp466, align 4
  %sl467 = call ptr @march_string_lit(ptr @.str25, i64 20)
  %fp468 = getelementptr i8, ptr %hp465, i64 16
  store ptr %sl467, ptr %fp468, align 8
  %$t2044.addr = alloca ptr
  store ptr %hp465, ptr %$t2044.addr
  %ld469 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld469)
  %ld470 = load ptr, ptr %logger.addr
  %ld471 = load ptr, ptr %$t2044.addr
  %sl472 = call ptr @march_string_lit(ptr @.str26, i64 14)
  %cr473 = call ptr @safe_send$Pid_V__6073$Logger_Msg$String(ptr %ld470, ptr %ld471, ptr %sl472)
  %hp474 = call ptr @march_alloc(i64 24)
  %tgp475 = getelementptr i8, ptr %hp474, i64 8
  store i32 0, ptr %tgp475, align 4
  %sl476 = call ptr @march_string_lit(ptr @.str27, i64 16)
  %fp477 = getelementptr i8, ptr %hp474, i64 16
  store ptr %sl476, ptr %fp477, align 8
  %$t2045.addr = alloca ptr
  store ptr %hp474, ptr %$t2045.addr
  %ld478 = load ptr, ptr %logger.addr
  call void @march_incrc(ptr %ld478)
  %ld479 = load ptr, ptr %logger.addr
  %ld480 = load ptr, ptr %$t2045.addr
  %sl481 = call ptr @march_string_lit(ptr @.str28, i64 14)
  %cr482 = call ptr @safe_send$Pid_V__6076$Logger_Msg$String(ptr %ld479, ptr %ld480, ptr %sl481)
  %hp483 = call ptr @march_alloc(i64 16)
  %tgp484 = getelementptr i8, ptr %hp483, i64 8
  store i32 1, ptr %tgp484, align 4
  %$t2046.addr = alloca ptr
  store ptr %hp483, ptr %$t2046.addr
  %ld485 = load ptr, ptr %logger.addr
  %ld486 = load ptr, ptr %$t2046.addr
  %sl487 = call ptr @march_string_lit(ptr @.str29, i64 16)
  %cr488 = call ptr @safe_send$Pid_V__6079$Logger_Msg$String(ptr %ld485, ptr %ld486, ptr %sl487)
  %sl489 = call ptr @march_string_lit(ptr @.str30, i64 0)
  call void @march_println(ptr %sl489)
  %sl490 = call ptr @march_string_lit(ptr @.str31, i64 30)
  call void @march_println(ptr %sl490)
  %hp491 = call ptr @march_alloc(i64 24)
  %tgp492 = getelementptr i8, ptr %hp491, i64 8
  store i32 1, ptr %tgp492, align 4
  %fp493 = getelementptr i8, ptr %hp491, i64 16
  store i64 3, ptr %fp493, align 8
  %$t2047.addr = alloca ptr
  store ptr %hp491, ptr %$t2047.addr
  %ld494 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld494)
  %ld495 = load ptr, ptr %counter.addr
  %ld496 = load ptr, ptr %$t2047.addr
  %sl497 = call ptr @march_string_lit(ptr @.str32, i64 12)
  %cr498 = call ptr @safe_send$Pid_V__6082$Counter_Msg$String(ptr %ld495, ptr %ld496, ptr %sl497)
  %hp499 = call ptr @march_alloc(i64 24)
  %tgp500 = getelementptr i8, ptr %hp499, i64 8
  store i32 3, ptr %tgp500, align 4
  %sl501 = call ptr @march_string_lit(ptr @.str33, i64 10)
  %fp502 = getelementptr i8, ptr %hp499, i64 16
  store ptr %sl501, ptr %fp502, align 8
  %$t2048.addr = alloca ptr
  store ptr %hp499, ptr %$t2048.addr
  %ld503 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld503)
  %ld504 = load ptr, ptr %counter.addr
  %ld505 = load ptr, ptr %$t2048.addr
  %sl506 = call ptr @march_string_lit(ptr @.str34, i64 4)
  %cr507 = call ptr @safe_send$Pid_V__6085$Counter_Msg$String(ptr %ld504, ptr %ld505, ptr %sl506)
  %hp508 = call ptr @march_alloc(i64 16)
  %tgp509 = getelementptr i8, ptr %hp508, i64 8
  store i32 2, ptr %tgp509, align 4
  %$t2049.addr = alloca ptr
  store ptr %hp508, ptr %$t2049.addr
  %ld510 = load ptr, ptr %counter.addr
  call void @march_incrc(ptr %ld510)
  %ld511 = load ptr, ptr %counter.addr
  %ld512 = load ptr, ptr %$t2049.addr
  %sl513 = call ptr @march_string_lit(ptr @.str35, i64 5)
  %cr514 = call ptr @safe_send$Pid_V__6088$Counter_Msg$String(ptr %ld511, ptr %ld512, ptr %sl513)
  %hp515 = call ptr @march_alloc(i64 24)
  %tgp516 = getelementptr i8, ptr %hp515, i64 8
  store i32 3, ptr %tgp516, align 4
  %sl517 = call ptr @march_string_lit(ptr @.str36, i64 10)
  %fp518 = getelementptr i8, ptr %hp515, i64 16
  store ptr %sl517, ptr %fp518, align 8
  %$t2050.addr = alloca ptr
  store ptr %hp515, ptr %$t2050.addr
  %ld519 = load ptr, ptr %counter.addr
  %ld520 = load ptr, ptr %$t2050.addr
  %sl521 = call ptr @march_string_lit(ptr @.str37, i64 16)
  %cr522 = call ptr @safe_send$Pid_V__6091$Counter_Msg$String(ptr %ld519, ptr %ld520, ptr %sl521)
  %sl523 = call ptr @march_string_lit(ptr @.str38, i64 0)
  call void @march_println(ptr %sl523)
  %sl524 = call ptr @march_string_lit(ptr @.str39, i64 49)
  call void @march_println(ptr %sl524)
  %hp525 = call ptr @march_alloc(i64 24)
  %tgp526 = getelementptr i8, ptr %hp525, i64 8
  store i32 0, ptr %tgp526, align 4
  %fp527 = getelementptr i8, ptr %hp525, i64 16
  store i64 0, ptr %fp527, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp525, ptr %$init_state_i23.addr
  %ld528 = load ptr, ptr %$init_state_i23.addr
  %fp529 = getelementptr i8, ptr %ld528, i64 16
  %fv530 = load i64, ptr %fp529, align 8
  %$init_count_i24.addr = alloca i64
  store i64 %fv530, ptr %$init_count_i24.addr
  %hp531 = call ptr @march_alloc(i64 40)
  %tgp532 = getelementptr i8, ptr %hp531, i64 8
  store i32 0, ptr %tgp532, align 4
  %cwrap533 = call ptr @march_alloc(i64 24)
  %cwt534 = getelementptr i8, ptr %cwrap533, i64 8
  store i32 0, ptr %cwt534, align 4
  %cwf535 = getelementptr i8, ptr %cwrap533, i64 16
  store ptr @Logger_dispatch$clo_wrap, ptr %cwf535, align 8
  %fp536 = getelementptr i8, ptr %hp531, i64 16
  store ptr %cwrap533, ptr %fp536, align 8
  %fp537 = getelementptr i8, ptr %hp531, i64 24
  store i64 1, ptr %fp537, align 8
  %ld538 = load i64, ptr %$init_count_i24.addr
  %fp539 = getelementptr i8, ptr %hp531, i64 32
  store i64 %ld538, ptr %fp539, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp531, ptr %$spawned_i25.addr
  %ld540 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor_2.addr = alloca ptr
  store ptr %ld540, ptr %$raw_actor_2.addr
  %ld541 = load ptr, ptr %$raw_actor_2.addr
  %cr542 = call ptr @march_spawn(ptr %ld541)
  %logger2.addr = alloca ptr
  store ptr %cr542, ptr %logger2.addr
  %ld543 = load ptr, ptr %logger2.addr
  call void @march_incrc(ptr %ld543)
  %ld544 = load ptr, ptr %logger2.addr
  %cr545 = call i64 @march_is_alive(ptr %ld544)
  %$t2051.addr = alloca i64
  store i64 %cr545, ptr %$t2051.addr
  %ld546 = load i64, ptr %$t2051.addr
  %cr547 = call ptr @march_bool_to_string(i64 %ld546)
  %$t2052.addr = alloca ptr
  store ptr %cr547, ptr %$t2052.addr
  %sl548 = call ptr @march_string_lit(ptr @.str40, i64 15)
  %ld549 = load ptr, ptr %$t2052.addr
  %cr550 = call ptr @march_string_concat(ptr %sl548, ptr %ld549)
  %$t2053.addr = alloca ptr
  store ptr %cr550, ptr %$t2053.addr
  %ld551 = load ptr, ptr %$t2053.addr
  call void @march_println(ptr %ld551)
  %hp552 = call ptr @march_alloc(i64 24)
  %tgp553 = getelementptr i8, ptr %hp552, i64 8
  store i32 0, ptr %tgp553, align 4
  %sl554 = call ptr @march_string_lit(ptr @.str41, i64 18)
  %fp555 = getelementptr i8, ptr %hp552, i64 16
  store ptr %sl554, ptr %fp555, align 8
  %$t2054.addr = alloca ptr
  store ptr %hp552, ptr %$t2054.addr
  %ld556 = load ptr, ptr %logger2.addr
  call void @march_incrc(ptr %ld556)
  %ld557 = load ptr, ptr %logger2.addr
  %ld558 = load ptr, ptr %$t2054.addr
  %sl559 = call ptr @march_string_lit(ptr @.str42, i64 14)
  %cr560 = call ptr @safe_send$Pid_V__6098$Logger_Msg$String(ptr %ld557, ptr %ld558, ptr %sl559)
  %hp561 = call ptr @march_alloc(i64 24)
  %tgp562 = getelementptr i8, ptr %hp561, i64 8
  store i32 0, ptr %tgp562, align 4
  %sl563 = call ptr @march_string_lit(ptr @.str43, i64 42)
  %fp564 = getelementptr i8, ptr %hp561, i64 16
  store ptr %sl563, ptr %fp564, align 8
  %$t2055.addr = alloca ptr
  store ptr %hp561, ptr %$t2055.addr
  %ld565 = load ptr, ptr %logger2.addr
  call void @march_incrc(ptr %ld565)
  %ld566 = load ptr, ptr %logger2.addr
  %ld567 = load ptr, ptr %$t2055.addr
  %sl568 = call ptr @march_string_lit(ptr @.str44, i64 14)
  %cr569 = call ptr @safe_send$Pid_V__6101$Logger_Msg$String(ptr %ld566, ptr %ld567, ptr %sl568)
  %hp570 = call ptr @march_alloc(i64 16)
  %tgp571 = getelementptr i8, ptr %hp570, i64 8
  store i32 1, ptr %tgp571, align 4
  %$t2056.addr = alloca ptr
  store ptr %hp570, ptr %$t2056.addr
  %ld572 = load ptr, ptr %logger2.addr
  %ld573 = load ptr, ptr %$t2056.addr
  %sl574 = call ptr @march_string_lit(ptr @.str45, i64 18)
  %cr575 = call ptr @safe_send$Pid_V__6104$Logger_Msg$String(ptr %ld572, ptr %ld573, ptr %sl574)
  %sl576 = call ptr @march_string_lit(ptr @.str46, i64 0)
  call void @march_println(ptr %sl576)
  %sl577 = call ptr @march_string_lit(ptr @.str47, i64 12)
  call void @march_println(ptr %sl577)
  ret void
}

define void @safe_send$Pid_V__6104$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld578 = load ptr, ptr %pid.addr
  %ld579 = load ptr, ptr %msg.addr
  %cr580 = call ptr @march_send(ptr %ld578, ptr %ld579)
  %result.addr = alloca ptr
  store ptr %cr580, ptr %result.addr
  %ld581 = load ptr, ptr %result.addr
  %res_slot582 = alloca ptr
  %tgp583 = getelementptr i8, ptr %ld581, i64 8
  %tag584 = load i32, ptr %tgp583, align 4
  switch i32 %tag584, label %case_default36 [
      i32 0, label %case_br37
      i32 1, label %case_br38
  ]
case_br37:
  %ld585 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld585)
  %sl586 = call ptr @march_string_lit(ptr @.str48, i64 11)
  %ld587 = load ptr, ptr %desc.addr
  %cr588 = call ptr @march_string_concat(ptr %sl586, ptr %ld587)
  %$t2026.addr = alloca ptr
  store ptr %cr588, ptr %$t2026.addr
  %ld589 = load ptr, ptr %$t2026.addr
  %sl590 = call ptr @march_string_lit(ptr @.str49, i64 18)
  %cr591 = call ptr @march_string_concat(ptr %ld589, ptr %sl590)
  %$t2027.addr = alloca ptr
  store ptr %cr591, ptr %$t2027.addr
  %ld592 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld592)
  %cv593 = inttoptr i64 0 to ptr
  store ptr %cv593, ptr %res_slot582
  br label %case_merge35
case_br38:
  %fp594 = getelementptr i8, ptr %ld581, i64 16
  %fv595 = load ptr, ptr %fp594, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv595, ptr %$f2028.addr
  %freed596 = call i64 @march_decrc_freed(ptr %ld581)
  %freed_b597 = icmp ne i64 %freed596, 0
  br i1 %freed_b597, label %br_unique39, label %br_shared40
br_shared40:
  call void @march_incrc(ptr %fv595)
  br label %br_body41
br_unique39:
  br label %br_body41
br_body41:
  %cv598 = inttoptr i64 0 to ptr
  store ptr %cv598, ptr %res_slot582
  br label %case_merge35
case_default36:
  unreachable
case_merge35:
  %case_r599 = load ptr, ptr %res_slot582
  ret void
}

define void @safe_send$Pid_V__6101$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld600 = load ptr, ptr %pid.addr
  %ld601 = load ptr, ptr %msg.addr
  %cr602 = call ptr @march_send(ptr %ld600, ptr %ld601)
  %result.addr = alloca ptr
  store ptr %cr602, ptr %result.addr
  %ld603 = load ptr, ptr %result.addr
  %res_slot604 = alloca ptr
  %tgp605 = getelementptr i8, ptr %ld603, i64 8
  %tag606 = load i32, ptr %tgp605, align 4
  switch i32 %tag606, label %case_default43 [
      i32 0, label %case_br44
      i32 1, label %case_br45
  ]
case_br44:
  %ld607 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld607)
  %sl608 = call ptr @march_string_lit(ptr @.str50, i64 11)
  %ld609 = load ptr, ptr %desc.addr
  %cr610 = call ptr @march_string_concat(ptr %sl608, ptr %ld609)
  %$t2026.addr = alloca ptr
  store ptr %cr610, ptr %$t2026.addr
  %ld611 = load ptr, ptr %$t2026.addr
  %sl612 = call ptr @march_string_lit(ptr @.str51, i64 18)
  %cr613 = call ptr @march_string_concat(ptr %ld611, ptr %sl612)
  %$t2027.addr = alloca ptr
  store ptr %cr613, ptr %$t2027.addr
  %ld614 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld614)
  %cv615 = inttoptr i64 0 to ptr
  store ptr %cv615, ptr %res_slot604
  br label %case_merge42
case_br45:
  %fp616 = getelementptr i8, ptr %ld603, i64 16
  %fv617 = load ptr, ptr %fp616, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv617, ptr %$f2028.addr
  %freed618 = call i64 @march_decrc_freed(ptr %ld603)
  %freed_b619 = icmp ne i64 %freed618, 0
  br i1 %freed_b619, label %br_unique46, label %br_shared47
br_shared47:
  call void @march_incrc(ptr %fv617)
  br label %br_body48
br_unique46:
  br label %br_body48
br_body48:
  %cv620 = inttoptr i64 0 to ptr
  store ptr %cv620, ptr %res_slot604
  br label %case_merge42
case_default43:
  unreachable
case_merge42:
  %case_r621 = load ptr, ptr %res_slot604
  ret void
}

define void @safe_send$Pid_V__6098$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld622 = load ptr, ptr %pid.addr
  %ld623 = load ptr, ptr %msg.addr
  %cr624 = call ptr @march_send(ptr %ld622, ptr %ld623)
  %result.addr = alloca ptr
  store ptr %cr624, ptr %result.addr
  %ld625 = load ptr, ptr %result.addr
  %res_slot626 = alloca ptr
  %tgp627 = getelementptr i8, ptr %ld625, i64 8
  %tag628 = load i32, ptr %tgp627, align 4
  switch i32 %tag628, label %case_default50 [
      i32 0, label %case_br51
      i32 1, label %case_br52
  ]
case_br51:
  %ld629 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld629)
  %sl630 = call ptr @march_string_lit(ptr @.str52, i64 11)
  %ld631 = load ptr, ptr %desc.addr
  %cr632 = call ptr @march_string_concat(ptr %sl630, ptr %ld631)
  %$t2026.addr = alloca ptr
  store ptr %cr632, ptr %$t2026.addr
  %ld633 = load ptr, ptr %$t2026.addr
  %sl634 = call ptr @march_string_lit(ptr @.str53, i64 18)
  %cr635 = call ptr @march_string_concat(ptr %ld633, ptr %sl634)
  %$t2027.addr = alloca ptr
  store ptr %cr635, ptr %$t2027.addr
  %ld636 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld636)
  %cv637 = inttoptr i64 0 to ptr
  store ptr %cv637, ptr %res_slot626
  br label %case_merge49
case_br52:
  %fp638 = getelementptr i8, ptr %ld625, i64 16
  %fv639 = load ptr, ptr %fp638, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv639, ptr %$f2028.addr
  %freed640 = call i64 @march_decrc_freed(ptr %ld625)
  %freed_b641 = icmp ne i64 %freed640, 0
  br i1 %freed_b641, label %br_unique53, label %br_shared54
br_shared54:
  call void @march_incrc(ptr %fv639)
  br label %br_body55
br_unique53:
  br label %br_body55
br_body55:
  %cv642 = inttoptr i64 0 to ptr
  store ptr %cv642, ptr %res_slot626
  br label %case_merge49
case_default50:
  unreachable
case_merge49:
  %case_r643 = load ptr, ptr %res_slot626
  ret void
}

define void @safe_send$Pid_V__6091$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld644 = load ptr, ptr %pid.addr
  %ld645 = load ptr, ptr %msg.addr
  %cr646 = call ptr @march_send(ptr %ld644, ptr %ld645)
  %result.addr = alloca ptr
  store ptr %cr646, ptr %result.addr
  %ld647 = load ptr, ptr %result.addr
  %res_slot648 = alloca ptr
  %tgp649 = getelementptr i8, ptr %ld647, i64 8
  %tag650 = load i32, ptr %tgp649, align 4
  switch i32 %tag650, label %case_default57 [
      i32 0, label %case_br58
      i32 1, label %case_br59
  ]
case_br58:
  %ld651 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld651)
  %sl652 = call ptr @march_string_lit(ptr @.str54, i64 11)
  %ld653 = load ptr, ptr %desc.addr
  %cr654 = call ptr @march_string_concat(ptr %sl652, ptr %ld653)
  %$t2026.addr = alloca ptr
  store ptr %cr654, ptr %$t2026.addr
  %ld655 = load ptr, ptr %$t2026.addr
  %sl656 = call ptr @march_string_lit(ptr @.str55, i64 18)
  %cr657 = call ptr @march_string_concat(ptr %ld655, ptr %sl656)
  %$t2027.addr = alloca ptr
  store ptr %cr657, ptr %$t2027.addr
  %ld658 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld658)
  %cv659 = inttoptr i64 0 to ptr
  store ptr %cv659, ptr %res_slot648
  br label %case_merge56
case_br59:
  %fp660 = getelementptr i8, ptr %ld647, i64 16
  %fv661 = load ptr, ptr %fp660, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv661, ptr %$f2028.addr
  %freed662 = call i64 @march_decrc_freed(ptr %ld647)
  %freed_b663 = icmp ne i64 %freed662, 0
  br i1 %freed_b663, label %br_unique60, label %br_shared61
br_shared61:
  call void @march_incrc(ptr %fv661)
  br label %br_body62
br_unique60:
  br label %br_body62
br_body62:
  %cv664 = inttoptr i64 0 to ptr
  store ptr %cv664, ptr %res_slot648
  br label %case_merge56
case_default57:
  unreachable
case_merge56:
  %case_r665 = load ptr, ptr %res_slot648
  ret void
}

define void @safe_send$Pid_V__6088$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld666 = load ptr, ptr %pid.addr
  %ld667 = load ptr, ptr %msg.addr
  %cr668 = call ptr @march_send(ptr %ld666, ptr %ld667)
  %result.addr = alloca ptr
  store ptr %cr668, ptr %result.addr
  %ld669 = load ptr, ptr %result.addr
  %res_slot670 = alloca ptr
  %tgp671 = getelementptr i8, ptr %ld669, i64 8
  %tag672 = load i32, ptr %tgp671, align 4
  switch i32 %tag672, label %case_default64 [
      i32 0, label %case_br65
      i32 1, label %case_br66
  ]
case_br65:
  %ld673 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld673)
  %sl674 = call ptr @march_string_lit(ptr @.str56, i64 11)
  %ld675 = load ptr, ptr %desc.addr
  %cr676 = call ptr @march_string_concat(ptr %sl674, ptr %ld675)
  %$t2026.addr = alloca ptr
  store ptr %cr676, ptr %$t2026.addr
  %ld677 = load ptr, ptr %$t2026.addr
  %sl678 = call ptr @march_string_lit(ptr @.str57, i64 18)
  %cr679 = call ptr @march_string_concat(ptr %ld677, ptr %sl678)
  %$t2027.addr = alloca ptr
  store ptr %cr679, ptr %$t2027.addr
  %ld680 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld680)
  %cv681 = inttoptr i64 0 to ptr
  store ptr %cv681, ptr %res_slot670
  br label %case_merge63
case_br66:
  %fp682 = getelementptr i8, ptr %ld669, i64 16
  %fv683 = load ptr, ptr %fp682, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv683, ptr %$f2028.addr
  %freed684 = call i64 @march_decrc_freed(ptr %ld669)
  %freed_b685 = icmp ne i64 %freed684, 0
  br i1 %freed_b685, label %br_unique67, label %br_shared68
br_shared68:
  call void @march_incrc(ptr %fv683)
  br label %br_body69
br_unique67:
  br label %br_body69
br_body69:
  %cv686 = inttoptr i64 0 to ptr
  store ptr %cv686, ptr %res_slot670
  br label %case_merge63
case_default64:
  unreachable
case_merge63:
  %case_r687 = load ptr, ptr %res_slot670
  ret void
}

define void @safe_send$Pid_V__6085$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld688 = load ptr, ptr %pid.addr
  %ld689 = load ptr, ptr %msg.addr
  %cr690 = call ptr @march_send(ptr %ld688, ptr %ld689)
  %result.addr = alloca ptr
  store ptr %cr690, ptr %result.addr
  %ld691 = load ptr, ptr %result.addr
  %res_slot692 = alloca ptr
  %tgp693 = getelementptr i8, ptr %ld691, i64 8
  %tag694 = load i32, ptr %tgp693, align 4
  switch i32 %tag694, label %case_default71 [
      i32 0, label %case_br72
      i32 1, label %case_br73
  ]
case_br72:
  %ld695 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld695)
  %sl696 = call ptr @march_string_lit(ptr @.str58, i64 11)
  %ld697 = load ptr, ptr %desc.addr
  %cr698 = call ptr @march_string_concat(ptr %sl696, ptr %ld697)
  %$t2026.addr = alloca ptr
  store ptr %cr698, ptr %$t2026.addr
  %ld699 = load ptr, ptr %$t2026.addr
  %sl700 = call ptr @march_string_lit(ptr @.str59, i64 18)
  %cr701 = call ptr @march_string_concat(ptr %ld699, ptr %sl700)
  %$t2027.addr = alloca ptr
  store ptr %cr701, ptr %$t2027.addr
  %ld702 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld702)
  %cv703 = inttoptr i64 0 to ptr
  store ptr %cv703, ptr %res_slot692
  br label %case_merge70
case_br73:
  %fp704 = getelementptr i8, ptr %ld691, i64 16
  %fv705 = load ptr, ptr %fp704, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv705, ptr %$f2028.addr
  %freed706 = call i64 @march_decrc_freed(ptr %ld691)
  %freed_b707 = icmp ne i64 %freed706, 0
  br i1 %freed_b707, label %br_unique74, label %br_shared75
br_shared75:
  call void @march_incrc(ptr %fv705)
  br label %br_body76
br_unique74:
  br label %br_body76
br_body76:
  %cv708 = inttoptr i64 0 to ptr
  store ptr %cv708, ptr %res_slot692
  br label %case_merge70
case_default71:
  unreachable
case_merge70:
  %case_r709 = load ptr, ptr %res_slot692
  ret void
}

define void @safe_send$Pid_V__6082$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld710 = load ptr, ptr %pid.addr
  %ld711 = load ptr, ptr %msg.addr
  %cr712 = call ptr @march_send(ptr %ld710, ptr %ld711)
  %result.addr = alloca ptr
  store ptr %cr712, ptr %result.addr
  %ld713 = load ptr, ptr %result.addr
  %res_slot714 = alloca ptr
  %tgp715 = getelementptr i8, ptr %ld713, i64 8
  %tag716 = load i32, ptr %tgp715, align 4
  switch i32 %tag716, label %case_default78 [
      i32 0, label %case_br79
      i32 1, label %case_br80
  ]
case_br79:
  %ld717 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld717)
  %sl718 = call ptr @march_string_lit(ptr @.str60, i64 11)
  %ld719 = load ptr, ptr %desc.addr
  %cr720 = call ptr @march_string_concat(ptr %sl718, ptr %ld719)
  %$t2026.addr = alloca ptr
  store ptr %cr720, ptr %$t2026.addr
  %ld721 = load ptr, ptr %$t2026.addr
  %sl722 = call ptr @march_string_lit(ptr @.str61, i64 18)
  %cr723 = call ptr @march_string_concat(ptr %ld721, ptr %sl722)
  %$t2027.addr = alloca ptr
  store ptr %cr723, ptr %$t2027.addr
  %ld724 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld724)
  %cv725 = inttoptr i64 0 to ptr
  store ptr %cv725, ptr %res_slot714
  br label %case_merge77
case_br80:
  %fp726 = getelementptr i8, ptr %ld713, i64 16
  %fv727 = load ptr, ptr %fp726, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv727, ptr %$f2028.addr
  %freed728 = call i64 @march_decrc_freed(ptr %ld713)
  %freed_b729 = icmp ne i64 %freed728, 0
  br i1 %freed_b729, label %br_unique81, label %br_shared82
br_shared82:
  call void @march_incrc(ptr %fv727)
  br label %br_body83
br_unique81:
  br label %br_body83
br_body83:
  %cv730 = inttoptr i64 0 to ptr
  store ptr %cv730, ptr %res_slot714
  br label %case_merge77
case_default78:
  unreachable
case_merge77:
  %case_r731 = load ptr, ptr %res_slot714
  ret void
}

define void @safe_send$Pid_V__6079$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld732 = load ptr, ptr %pid.addr
  %ld733 = load ptr, ptr %msg.addr
  %cr734 = call ptr @march_send(ptr %ld732, ptr %ld733)
  %result.addr = alloca ptr
  store ptr %cr734, ptr %result.addr
  %ld735 = load ptr, ptr %result.addr
  %res_slot736 = alloca ptr
  %tgp737 = getelementptr i8, ptr %ld735, i64 8
  %tag738 = load i32, ptr %tgp737, align 4
  switch i32 %tag738, label %case_default85 [
      i32 0, label %case_br86
      i32 1, label %case_br87
  ]
case_br86:
  %ld739 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld739)
  %sl740 = call ptr @march_string_lit(ptr @.str62, i64 11)
  %ld741 = load ptr, ptr %desc.addr
  %cr742 = call ptr @march_string_concat(ptr %sl740, ptr %ld741)
  %$t2026.addr = alloca ptr
  store ptr %cr742, ptr %$t2026.addr
  %ld743 = load ptr, ptr %$t2026.addr
  %sl744 = call ptr @march_string_lit(ptr @.str63, i64 18)
  %cr745 = call ptr @march_string_concat(ptr %ld743, ptr %sl744)
  %$t2027.addr = alloca ptr
  store ptr %cr745, ptr %$t2027.addr
  %ld746 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld746)
  %cv747 = inttoptr i64 0 to ptr
  store ptr %cv747, ptr %res_slot736
  br label %case_merge84
case_br87:
  %fp748 = getelementptr i8, ptr %ld735, i64 16
  %fv749 = load ptr, ptr %fp748, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv749, ptr %$f2028.addr
  %freed750 = call i64 @march_decrc_freed(ptr %ld735)
  %freed_b751 = icmp ne i64 %freed750, 0
  br i1 %freed_b751, label %br_unique88, label %br_shared89
br_shared89:
  call void @march_incrc(ptr %fv749)
  br label %br_body90
br_unique88:
  br label %br_body90
br_body90:
  %cv752 = inttoptr i64 0 to ptr
  store ptr %cv752, ptr %res_slot736
  br label %case_merge84
case_default85:
  unreachable
case_merge84:
  %case_r753 = load ptr, ptr %res_slot736
  ret void
}

define void @safe_send$Pid_V__6076$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld754 = load ptr, ptr %pid.addr
  %ld755 = load ptr, ptr %msg.addr
  %cr756 = call ptr @march_send(ptr %ld754, ptr %ld755)
  %result.addr = alloca ptr
  store ptr %cr756, ptr %result.addr
  %ld757 = load ptr, ptr %result.addr
  %res_slot758 = alloca ptr
  %tgp759 = getelementptr i8, ptr %ld757, i64 8
  %tag760 = load i32, ptr %tgp759, align 4
  switch i32 %tag760, label %case_default92 [
      i32 0, label %case_br93
      i32 1, label %case_br94
  ]
case_br93:
  %ld761 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld761)
  %sl762 = call ptr @march_string_lit(ptr @.str64, i64 11)
  %ld763 = load ptr, ptr %desc.addr
  %cr764 = call ptr @march_string_concat(ptr %sl762, ptr %ld763)
  %$t2026.addr = alloca ptr
  store ptr %cr764, ptr %$t2026.addr
  %ld765 = load ptr, ptr %$t2026.addr
  %sl766 = call ptr @march_string_lit(ptr @.str65, i64 18)
  %cr767 = call ptr @march_string_concat(ptr %ld765, ptr %sl766)
  %$t2027.addr = alloca ptr
  store ptr %cr767, ptr %$t2027.addr
  %ld768 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld768)
  %cv769 = inttoptr i64 0 to ptr
  store ptr %cv769, ptr %res_slot758
  br label %case_merge91
case_br94:
  %fp770 = getelementptr i8, ptr %ld757, i64 16
  %fv771 = load ptr, ptr %fp770, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv771, ptr %$f2028.addr
  %freed772 = call i64 @march_decrc_freed(ptr %ld757)
  %freed_b773 = icmp ne i64 %freed772, 0
  br i1 %freed_b773, label %br_unique95, label %br_shared96
br_shared96:
  call void @march_incrc(ptr %fv771)
  br label %br_body97
br_unique95:
  br label %br_body97
br_body97:
  %cv774 = inttoptr i64 0 to ptr
  store ptr %cv774, ptr %res_slot758
  br label %case_merge91
case_default92:
  unreachable
case_merge91:
  %case_r775 = load ptr, ptr %res_slot758
  ret void
}

define void @safe_send$Pid_V__6073$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld776 = load ptr, ptr %pid.addr
  %ld777 = load ptr, ptr %msg.addr
  %cr778 = call ptr @march_send(ptr %ld776, ptr %ld777)
  %result.addr = alloca ptr
  store ptr %cr778, ptr %result.addr
  %ld779 = load ptr, ptr %result.addr
  %res_slot780 = alloca ptr
  %tgp781 = getelementptr i8, ptr %ld779, i64 8
  %tag782 = load i32, ptr %tgp781, align 4
  switch i32 %tag782, label %case_default99 [
      i32 0, label %case_br100
      i32 1, label %case_br101
  ]
case_br100:
  %ld783 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld783)
  %sl784 = call ptr @march_string_lit(ptr @.str66, i64 11)
  %ld785 = load ptr, ptr %desc.addr
  %cr786 = call ptr @march_string_concat(ptr %sl784, ptr %ld785)
  %$t2026.addr = alloca ptr
  store ptr %cr786, ptr %$t2026.addr
  %ld787 = load ptr, ptr %$t2026.addr
  %sl788 = call ptr @march_string_lit(ptr @.str67, i64 18)
  %cr789 = call ptr @march_string_concat(ptr %ld787, ptr %sl788)
  %$t2027.addr = alloca ptr
  store ptr %cr789, ptr %$t2027.addr
  %ld790 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld790)
  %cv791 = inttoptr i64 0 to ptr
  store ptr %cv791, ptr %res_slot780
  br label %case_merge98
case_br101:
  %fp792 = getelementptr i8, ptr %ld779, i64 16
  %fv793 = load ptr, ptr %fp792, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv793, ptr %$f2028.addr
  %freed794 = call i64 @march_decrc_freed(ptr %ld779)
  %freed_b795 = icmp ne i64 %freed794, 0
  br i1 %freed_b795, label %br_unique102, label %br_shared103
br_shared103:
  call void @march_incrc(ptr %fv793)
  br label %br_body104
br_unique102:
  br label %br_body104
br_body104:
  %cv796 = inttoptr i64 0 to ptr
  store ptr %cv796, ptr %res_slot780
  br label %case_merge98
case_default99:
  unreachable
case_merge98:
  %case_r797 = load ptr, ptr %res_slot780
  ret void
}

define void @safe_send$Pid_V__6066$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld798 = load ptr, ptr %pid.addr
  %ld799 = load ptr, ptr %msg.addr
  %cr800 = call ptr @march_send(ptr %ld798, ptr %ld799)
  %result.addr = alloca ptr
  store ptr %cr800, ptr %result.addr
  %ld801 = load ptr, ptr %result.addr
  %res_slot802 = alloca ptr
  %tgp803 = getelementptr i8, ptr %ld801, i64 8
  %tag804 = load i32, ptr %tgp803, align 4
  switch i32 %tag804, label %case_default106 [
      i32 0, label %case_br107
      i32 1, label %case_br108
  ]
case_br107:
  %ld805 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld805)
  %sl806 = call ptr @march_string_lit(ptr @.str68, i64 11)
  %ld807 = load ptr, ptr %desc.addr
  %cr808 = call ptr @march_string_concat(ptr %sl806, ptr %ld807)
  %$t2026.addr = alloca ptr
  store ptr %cr808, ptr %$t2026.addr
  %ld809 = load ptr, ptr %$t2026.addr
  %sl810 = call ptr @march_string_lit(ptr @.str69, i64 18)
  %cr811 = call ptr @march_string_concat(ptr %ld809, ptr %sl810)
  %$t2027.addr = alloca ptr
  store ptr %cr811, ptr %$t2027.addr
  %ld812 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld812)
  %cv813 = inttoptr i64 0 to ptr
  store ptr %cv813, ptr %res_slot802
  br label %case_merge105
case_br108:
  %fp814 = getelementptr i8, ptr %ld801, i64 16
  %fv815 = load ptr, ptr %fp814, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv815, ptr %$f2028.addr
  %freed816 = call i64 @march_decrc_freed(ptr %ld801)
  %freed_b817 = icmp ne i64 %freed816, 0
  br i1 %freed_b817, label %br_unique109, label %br_shared110
br_shared110:
  call void @march_incrc(ptr %fv815)
  br label %br_body111
br_unique109:
  br label %br_body111
br_body111:
  %cv818 = inttoptr i64 0 to ptr
  store ptr %cv818, ptr %res_slot802
  br label %case_merge105
case_default106:
  unreachable
case_merge105:
  %case_r819 = load ptr, ptr %res_slot802
  ret void
}

define void @safe_send$Pid_V__6063$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld820 = load ptr, ptr %pid.addr
  %ld821 = load ptr, ptr %msg.addr
  %cr822 = call ptr @march_send(ptr %ld820, ptr %ld821)
  %result.addr = alloca ptr
  store ptr %cr822, ptr %result.addr
  %ld823 = load ptr, ptr %result.addr
  %res_slot824 = alloca ptr
  %tgp825 = getelementptr i8, ptr %ld823, i64 8
  %tag826 = load i32, ptr %tgp825, align 4
  switch i32 %tag826, label %case_default113 [
      i32 0, label %case_br114
      i32 1, label %case_br115
  ]
case_br114:
  %ld827 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld827)
  %sl828 = call ptr @march_string_lit(ptr @.str70, i64 11)
  %ld829 = load ptr, ptr %desc.addr
  %cr830 = call ptr @march_string_concat(ptr %sl828, ptr %ld829)
  %$t2026.addr = alloca ptr
  store ptr %cr830, ptr %$t2026.addr
  %ld831 = load ptr, ptr %$t2026.addr
  %sl832 = call ptr @march_string_lit(ptr @.str71, i64 18)
  %cr833 = call ptr @march_string_concat(ptr %ld831, ptr %sl832)
  %$t2027.addr = alloca ptr
  store ptr %cr833, ptr %$t2027.addr
  %ld834 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld834)
  %cv835 = inttoptr i64 0 to ptr
  store ptr %cv835, ptr %res_slot824
  br label %case_merge112
case_br115:
  %fp836 = getelementptr i8, ptr %ld823, i64 16
  %fv837 = load ptr, ptr %fp836, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv837, ptr %$f2028.addr
  %freed838 = call i64 @march_decrc_freed(ptr %ld823)
  %freed_b839 = icmp ne i64 %freed838, 0
  br i1 %freed_b839, label %br_unique116, label %br_shared117
br_shared117:
  call void @march_incrc(ptr %fv837)
  br label %br_body118
br_unique116:
  br label %br_body118
br_body118:
  %cv840 = inttoptr i64 0 to ptr
  store ptr %cv840, ptr %res_slot824
  br label %case_merge112
case_default113:
  unreachable
case_merge112:
  %case_r841 = load ptr, ptr %res_slot824
  ret void
}

define void @safe_send$Pid_V__6060$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld842 = load ptr, ptr %pid.addr
  %ld843 = load ptr, ptr %msg.addr
  %cr844 = call ptr @march_send(ptr %ld842, ptr %ld843)
  %result.addr = alloca ptr
  store ptr %cr844, ptr %result.addr
  %ld845 = load ptr, ptr %result.addr
  %res_slot846 = alloca ptr
  %tgp847 = getelementptr i8, ptr %ld845, i64 8
  %tag848 = load i32, ptr %tgp847, align 4
  switch i32 %tag848, label %case_default120 [
      i32 0, label %case_br121
      i32 1, label %case_br122
  ]
case_br121:
  %ld849 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld849)
  %sl850 = call ptr @march_string_lit(ptr @.str72, i64 11)
  %ld851 = load ptr, ptr %desc.addr
  %cr852 = call ptr @march_string_concat(ptr %sl850, ptr %ld851)
  %$t2026.addr = alloca ptr
  store ptr %cr852, ptr %$t2026.addr
  %ld853 = load ptr, ptr %$t2026.addr
  %sl854 = call ptr @march_string_lit(ptr @.str73, i64 18)
  %cr855 = call ptr @march_string_concat(ptr %ld853, ptr %sl854)
  %$t2027.addr = alloca ptr
  store ptr %cr855, ptr %$t2027.addr
  %ld856 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld856)
  %cv857 = inttoptr i64 0 to ptr
  store ptr %cv857, ptr %res_slot846
  br label %case_merge119
case_br122:
  %fp858 = getelementptr i8, ptr %ld845, i64 16
  %fv859 = load ptr, ptr %fp858, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv859, ptr %$f2028.addr
  %freed860 = call i64 @march_decrc_freed(ptr %ld845)
  %freed_b861 = icmp ne i64 %freed860, 0
  br i1 %freed_b861, label %br_unique123, label %br_shared124
br_shared124:
  call void @march_incrc(ptr %fv859)
  br label %br_body125
br_unique123:
  br label %br_body125
br_body125:
  %cv862 = inttoptr i64 0 to ptr
  store ptr %cv862, ptr %res_slot846
  br label %case_merge119
case_default120:
  unreachable
case_merge119:
  %case_r863 = load ptr, ptr %res_slot846
  ret void
}

define void @safe_send$Pid_V__6057$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld864 = load ptr, ptr %pid.addr
  %ld865 = load ptr, ptr %msg.addr
  %cr866 = call ptr @march_send(ptr %ld864, ptr %ld865)
  %result.addr = alloca ptr
  store ptr %cr866, ptr %result.addr
  %ld867 = load ptr, ptr %result.addr
  %res_slot868 = alloca ptr
  %tgp869 = getelementptr i8, ptr %ld867, i64 8
  %tag870 = load i32, ptr %tgp869, align 4
  switch i32 %tag870, label %case_default127 [
      i32 0, label %case_br128
      i32 1, label %case_br129
  ]
case_br128:
  %ld871 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld871)
  %sl872 = call ptr @march_string_lit(ptr @.str74, i64 11)
  %ld873 = load ptr, ptr %desc.addr
  %cr874 = call ptr @march_string_concat(ptr %sl872, ptr %ld873)
  %$t2026.addr = alloca ptr
  store ptr %cr874, ptr %$t2026.addr
  %ld875 = load ptr, ptr %$t2026.addr
  %sl876 = call ptr @march_string_lit(ptr @.str75, i64 18)
  %cr877 = call ptr @march_string_concat(ptr %ld875, ptr %sl876)
  %$t2027.addr = alloca ptr
  store ptr %cr877, ptr %$t2027.addr
  %ld878 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld878)
  %cv879 = inttoptr i64 0 to ptr
  store ptr %cv879, ptr %res_slot868
  br label %case_merge126
case_br129:
  %fp880 = getelementptr i8, ptr %ld867, i64 16
  %fv881 = load ptr, ptr %fp880, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv881, ptr %$f2028.addr
  %freed882 = call i64 @march_decrc_freed(ptr %ld867)
  %freed_b883 = icmp ne i64 %freed882, 0
  br i1 %freed_b883, label %br_unique130, label %br_shared131
br_shared131:
  call void @march_incrc(ptr %fv881)
  br label %br_body132
br_unique130:
  br label %br_body132
br_body132:
  %cv884 = inttoptr i64 0 to ptr
  store ptr %cv884, ptr %res_slot868
  br label %case_merge126
case_default127:
  unreachable
case_merge126:
  %case_r885 = load ptr, ptr %res_slot868
  ret void
}

define void @safe_send$Pid_V__6054$Logger_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld886 = load ptr, ptr %pid.addr
  %ld887 = load ptr, ptr %msg.addr
  %cr888 = call ptr @march_send(ptr %ld886, ptr %ld887)
  %result.addr = alloca ptr
  store ptr %cr888, ptr %result.addr
  %ld889 = load ptr, ptr %result.addr
  %res_slot890 = alloca ptr
  %tgp891 = getelementptr i8, ptr %ld889, i64 8
  %tag892 = load i32, ptr %tgp891, align 4
  switch i32 %tag892, label %case_default134 [
      i32 0, label %case_br135
      i32 1, label %case_br136
  ]
case_br135:
  %ld893 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld893)
  %sl894 = call ptr @march_string_lit(ptr @.str76, i64 11)
  %ld895 = load ptr, ptr %desc.addr
  %cr896 = call ptr @march_string_concat(ptr %sl894, ptr %ld895)
  %$t2026.addr = alloca ptr
  store ptr %cr896, ptr %$t2026.addr
  %ld897 = load ptr, ptr %$t2026.addr
  %sl898 = call ptr @march_string_lit(ptr @.str77, i64 18)
  %cr899 = call ptr @march_string_concat(ptr %ld897, ptr %sl898)
  %$t2027.addr = alloca ptr
  store ptr %cr899, ptr %$t2027.addr
  %ld900 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld900)
  %cv901 = inttoptr i64 0 to ptr
  store ptr %cv901, ptr %res_slot890
  br label %case_merge133
case_br136:
  %fp902 = getelementptr i8, ptr %ld889, i64 16
  %fv903 = load ptr, ptr %fp902, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv903, ptr %$f2028.addr
  %freed904 = call i64 @march_decrc_freed(ptr %ld889)
  %freed_b905 = icmp ne i64 %freed904, 0
  br i1 %freed_b905, label %br_unique137, label %br_shared138
br_shared138:
  call void @march_incrc(ptr %fv903)
  br label %br_body139
br_unique137:
  br label %br_body139
br_body139:
  %cv906 = inttoptr i64 0 to ptr
  store ptr %cv906, ptr %res_slot890
  br label %case_merge133
case_default134:
  unreachable
case_merge133:
  %case_r907 = load ptr, ptr %res_slot890
  ret void
}

define void @safe_send$Pid_V__6051$Counter_Msg$String(ptr %pid.arg, ptr %msg.arg, ptr %desc.arg) {
entry:
  %pid.addr = alloca ptr
  store ptr %pid.arg, ptr %pid.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %desc.addr = alloca ptr
  store ptr %desc.arg, ptr %desc.addr
  %ld908 = load ptr, ptr %pid.addr
  %ld909 = load ptr, ptr %msg.addr
  %cr910 = call ptr @march_send(ptr %ld908, ptr %ld909)
  %result.addr = alloca ptr
  store ptr %cr910, ptr %result.addr
  %ld911 = load ptr, ptr %result.addr
  %res_slot912 = alloca ptr
  %tgp913 = getelementptr i8, ptr %ld911, i64 8
  %tag914 = load i32, ptr %tgp913, align 4
  switch i32 %tag914, label %case_default141 [
      i32 0, label %case_br142
      i32 1, label %case_br143
  ]
case_br142:
  %ld915 = load ptr, ptr %result.addr
  call void @march_decrc(ptr %ld915)
  %sl916 = call ptr @march_string_lit(ptr @.str78, i64 11)
  %ld917 = load ptr, ptr %desc.addr
  %cr918 = call ptr @march_string_concat(ptr %sl916, ptr %ld917)
  %$t2026.addr = alloca ptr
  store ptr %cr918, ptr %$t2026.addr
  %ld919 = load ptr, ptr %$t2026.addr
  %sl920 = call ptr @march_string_lit(ptr @.str79, i64 18)
  %cr921 = call ptr @march_string_concat(ptr %ld919, ptr %sl920)
  %$t2027.addr = alloca ptr
  store ptr %cr921, ptr %$t2027.addr
  %ld922 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld922)
  %cv923 = inttoptr i64 0 to ptr
  store ptr %cv923, ptr %res_slot912
  br label %case_merge140
case_br143:
  %fp924 = getelementptr i8, ptr %ld911, i64 16
  %fv925 = load ptr, ptr %fp924, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv925, ptr %$f2028.addr
  %freed926 = call i64 @march_decrc_freed(ptr %ld911)
  %freed_b927 = icmp ne i64 %freed926, 0
  br i1 %freed_b927, label %br_unique144, label %br_shared145
br_shared145:
  call void @march_incrc(ptr %fv925)
  br label %br_body146
br_unique144:
  br label %br_body146
br_body146:
  %cv928 = inttoptr i64 0 to ptr
  store ptr %cv928, ptr %res_slot912
  br label %case_merge140
case_default141:
  unreachable
case_merge140:
  %case_r929 = load ptr, ptr %res_slot912
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @Logger_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Logger_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

define ptr @Counter_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Counter_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

