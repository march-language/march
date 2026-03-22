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

@.str1 = private unnamed_addr constant [26 x i8] c"[Worker] processed work #\00"
@.str2 = private unnamed_addr constant [32 x i8] c"[Watcher] down_count in state: \00"
@.str3 = private unnamed_addr constant [21 x i8] c"=== Monitor Demo ===\00"
@.str4 = private unnamed_addr constant [1 x i8] c"\00"
@.str5 = private unnamed_addr constant [14 x i8] c"worker  pid: \00"
@.str6 = private unnamed_addr constant [14 x i8] c"watcher pid: \00"
@.str7 = private unnamed_addr constant [1 x i8] c"\00"
@.str8 = private unnamed_addr constant [28 x i8] c"monitor established, ref = \00"
@.str9 = private unnamed_addr constant [37 x i8] c"watcher mailbox size (before kill): \00"
@.str10 = private unnamed_addr constant [1 x i8] c"\00"
@.str11 = private unnamed_addr constant [1 x i8] c"\00"
@.str12 = private unnamed_addr constant [18 x i8] c"Killing worker...\00"
@.str13 = private unnamed_addr constant [15 x i8] c"worker alive: \00"
@.str14 = private unnamed_addr constant [37 x i8] c"watcher mailbox size (after kill):  \00"
@.str15 = private unnamed_addr constant [39 x i8] c"  (expect 1 \E2\80\94 one Down notification)\00"
@.str16 = private unnamed_addr constant [1 x i8] c"\00"
@.str17 = private unnamed_addr constant [24 x i8] c"monitor cancelled (ref \00"
@.str18 = private unnamed_addr constant [2 x i8] c")\00"
@.str19 = private unnamed_addr constant [1 x i8] c"\00"
@.str20 = private unnamed_addr constant [32 x i8] c"--- Monitoring a dead actor ---\00"
@.str21 = private unnamed_addr constant [27 x i8] c"monitor dead actor, ref = \00"
@.str22 = private unnamed_addr constant [23 x i8] c"watcher mailbox size: \00"
@.str23 = private unnamed_addr constant [64 x i8] c"  (expect 2 \E2\80\94 second Down arrives immediately for dead actor)\00"
@.str24 = private unnamed_addr constant [1 x i8] c"\00"
@.str25 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"

define void @Worker_Work(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
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
  %$sf_count.addr = alloca i64
  store i64 %fv9, ptr %$sf_count.addr
  %hp10 = call ptr @march_alloc(i64 24)
  %tgp11 = getelementptr i8, ptr %hp10, i64 8
  store i32 0, ptr %tgp11, align 4
  %ld12 = load i64, ptr %$sf_count.addr
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
  %ar18 = add i64 %ld17, 1
  %n.addr = alloca i64
  store i64 %ar18, ptr %n.addr
  %ld19 = load i64, ptr %n.addr
  %cr20 = call ptr @march_int_to_string(i64 %ld19)
  %$t2010.addr = alloca ptr
  store ptr %cr20, ptr %$t2010.addr
  %sl21 = call ptr @march_string_lit(ptr @.str1, i64 25)
  %ld22 = load ptr, ptr %$t2010.addr
  %cr23 = call ptr @march_string_concat(ptr %sl21, ptr %ld22)
  %$t2011.addr = alloca ptr
  store ptr %cr23, ptr %$t2011.addr
  %ld24 = load ptr, ptr %$t2011.addr
  call void @march_println(ptr %ld24)
  %hp25 = call ptr @march_alloc(i64 24)
  %tgp26 = getelementptr i8, ptr %hp25, i64 8
  store i32 0, ptr %tgp26, align 4
  %ld27 = load i64, ptr %n.addr
  %fp28 = getelementptr i8, ptr %hp25, i64 16
  store i64 %ld27, ptr %fp28, align 8
  %$result.addr = alloca ptr
  store ptr %hp25, ptr %$result.addr
  %ld29 = load ptr, ptr %$result.addr
  %fp30 = getelementptr i8, ptr %ld29, i64 16
  %fv31 = load i64, ptr %fp30, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv31, ptr %$nf_count.addr
  %ld32 = load ptr, ptr %$actor.addr
  %ld33 = load ptr, ptr %$dispatch_v.addr
  %ld34 = load i64, ptr %$alive_v.addr
  %ld35 = load i64, ptr %$nf_count.addr
  %rc36 = load i64, ptr %ld32, align 8
  %uniq37 = icmp eq i64 %rc36, 1
  %fbip_slot38 = alloca ptr
  br i1 %uniq37, label %fbip_reuse1, label %fbip_fresh2
fbip_reuse1:
  %tgp39 = getelementptr i8, ptr %ld32, i64 8
  store i32 0, ptr %tgp39, align 4
  %fp40 = getelementptr i8, ptr %ld32, i64 16
  store ptr %ld33, ptr %fp40, align 8
  %fp41 = getelementptr i8, ptr %ld32, i64 24
  store i64 %ld34, ptr %fp41, align 8
  %fp42 = getelementptr i8, ptr %ld32, i64 32
  store i64 %ld35, ptr %fp42, align 8
  store ptr %ld32, ptr %fbip_slot38
  br label %fbip_merge3
fbip_fresh2:
  call void @march_decrc(ptr %ld32)
  %hp43 = call ptr @march_alloc(i64 40)
  %tgp44 = getelementptr i8, ptr %hp43, i64 8
  store i32 0, ptr %tgp44, align 4
  %fp45 = getelementptr i8, ptr %hp43, i64 16
  store ptr %ld33, ptr %fp45, align 8
  %fp46 = getelementptr i8, ptr %hp43, i64 24
  store i64 %ld34, ptr %fp46, align 8
  %fp47 = getelementptr i8, ptr %hp43, i64 32
  store i64 %ld35, ptr %fp47, align 8
  store ptr %hp43, ptr %fbip_slot38
  br label %fbip_merge3
fbip_merge3:
  %fbip_r48 = load ptr, ptr %fbip_slot38
  ret void
}

define void @Worker_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld49 = load ptr, ptr %$msg.addr
  %res_slot50 = alloca ptr
  %tgp51 = getelementptr i8, ptr %ld49, i64 8
  %tag52 = load i32, ptr %tgp51, align 4
  switch i32 %tag52, label %case_default5 [
      i32 0, label %case_br6
  ]
case_br6:
  %ld53 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld53)
  %ld54 = load ptr, ptr %$actor.addr
  call void @Worker_Work(ptr %ld54)
  %cv55 = inttoptr i64 0 to ptr
  store ptr %cv55, ptr %res_slot50
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r56 = load ptr, ptr %res_slot50
  ret void
}

define void @Watcher_Report(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %ld57 = load ptr, ptr %$actor.addr
  %fp58 = getelementptr i8, ptr %ld57, i64 16
  %fv59 = load ptr, ptr %fp58, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv59, ptr %$dispatch_v.addr
  %ld60 = load ptr, ptr %$actor.addr
  %fp61 = getelementptr i8, ptr %ld60, i64 24
  %fv62 = load i64, ptr %fp61, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv62, ptr %$alive_v.addr
  %ld63 = load ptr, ptr %$actor.addr
  %fp64 = getelementptr i8, ptr %ld63, i64 32
  %fv65 = load i64, ptr %fp64, align 8
  %$sf_down_count.addr = alloca i64
  store i64 %fv65, ptr %$sf_down_count.addr
  %hp66 = call ptr @march_alloc(i64 24)
  %tgp67 = getelementptr i8, ptr %hp66, i64 8
  store i32 0, ptr %tgp67, align 4
  %ld68 = load i64, ptr %$sf_down_count.addr
  %fp69 = getelementptr i8, ptr %hp66, i64 16
  store i64 %ld68, ptr %fp69, align 8
  %state.addr = alloca ptr
  store ptr %hp66, ptr %state.addr
  %ld70 = load ptr, ptr %state.addr
  %fp71 = getelementptr i8, ptr %ld70, i64 16
  %fv72 = load i64, ptr %fp71, align 8
  %$t2012.addr = alloca i64
  store i64 %fv72, ptr %$t2012.addr
  %ld73 = load i64, ptr %$t2012.addr
  %cr74 = call ptr @march_int_to_string(i64 %ld73)
  %$t2013.addr = alloca ptr
  store ptr %cr74, ptr %$t2013.addr
  %sl75 = call ptr @march_string_lit(ptr @.str2, i64 31)
  %ld76 = load ptr, ptr %$t2013.addr
  %cr77 = call ptr @march_string_concat(ptr %sl75, ptr %ld76)
  %$t2014.addr = alloca ptr
  store ptr %cr77, ptr %$t2014.addr
  %ld78 = load ptr, ptr %$t2014.addr
  call void @march_println(ptr %ld78)
  %ld79 = load ptr, ptr %state.addr
  %$result.addr = alloca ptr
  store ptr %ld79, ptr %$result.addr
  %ld80 = load ptr, ptr %$result.addr
  %fp81 = getelementptr i8, ptr %ld80, i64 16
  %fv82 = load i64, ptr %fp81, align 8
  %$nf_down_count.addr = alloca i64
  store i64 %fv82, ptr %$nf_down_count.addr
  %ld83 = load ptr, ptr %$actor.addr
  %ld84 = load ptr, ptr %$dispatch_v.addr
  %ld85 = load i64, ptr %$alive_v.addr
  %ld86 = load i64, ptr %$nf_down_count.addr
  %rc87 = load i64, ptr %ld83, align 8
  %uniq88 = icmp eq i64 %rc87, 1
  %fbip_slot89 = alloca ptr
  br i1 %uniq88, label %fbip_reuse7, label %fbip_fresh8
fbip_reuse7:
  %tgp90 = getelementptr i8, ptr %ld83, i64 8
  store i32 0, ptr %tgp90, align 4
  %fp91 = getelementptr i8, ptr %ld83, i64 16
  store ptr %ld84, ptr %fp91, align 8
  %fp92 = getelementptr i8, ptr %ld83, i64 24
  store i64 %ld85, ptr %fp92, align 8
  %fp93 = getelementptr i8, ptr %ld83, i64 32
  store i64 %ld86, ptr %fp93, align 8
  store ptr %ld83, ptr %fbip_slot89
  br label %fbip_merge9
fbip_fresh8:
  call void @march_decrc(ptr %ld83)
  %hp94 = call ptr @march_alloc(i64 40)
  %tgp95 = getelementptr i8, ptr %hp94, i64 8
  store i32 0, ptr %tgp95, align 4
  %fp96 = getelementptr i8, ptr %hp94, i64 16
  store ptr %ld84, ptr %fp96, align 8
  %fp97 = getelementptr i8, ptr %hp94, i64 24
  store i64 %ld85, ptr %fp97, align 8
  %fp98 = getelementptr i8, ptr %hp94, i64 32
  store i64 %ld86, ptr %fp98, align 8
  store ptr %hp94, ptr %fbip_slot89
  br label %fbip_merge9
fbip_merge9:
  %fbip_r99 = load ptr, ptr %fbip_slot89
  ret void
}

define void @Watcher_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld100 = load ptr, ptr %$msg.addr
  %res_slot101 = alloca ptr
  %tgp102 = getelementptr i8, ptr %ld100, i64 8
  %tag103 = load i32, ptr %tgp102, align 4
  switch i32 %tag103, label %case_default11 [
      i32 0, label %case_br12
  ]
case_br12:
  %ld104 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld104)
  %ld105 = load ptr, ptr %$actor.addr
  call void @Watcher_Report(ptr %ld105)
  %cv106 = inttoptr i64 0 to ptr
  store ptr %cv106, ptr %res_slot101
  br label %case_merge10
case_default11:
  unreachable
case_merge10:
  %case_r107 = load ptr, ptr %res_slot101
  ret void
}

define ptr @march_main() {
entry:
  %sl108 = call ptr @march_string_lit(ptr @.str3, i64 20)
  call void @march_println(ptr %sl108)
  %sl109 = call ptr @march_string_lit(ptr @.str4, i64 0)
  call void @march_println(ptr %sl109)
  %hp110 = call ptr @march_alloc(i64 24)
  %tgp111 = getelementptr i8, ptr %hp110, i64 8
  store i32 0, ptr %tgp111, align 4
  %fp112 = getelementptr i8, ptr %hp110, i64 16
  store i64 0, ptr %fp112, align 8
  %$init_state_i26.addr = alloca ptr
  store ptr %hp110, ptr %$init_state_i26.addr
  %ld113 = load ptr, ptr %$init_state_i26.addr
  %fp114 = getelementptr i8, ptr %ld113, i64 16
  %fv115 = load i64, ptr %fp114, align 8
  %$init_count_i27.addr = alloca i64
  store i64 %fv115, ptr %$init_count_i27.addr
  %hp116 = call ptr @march_alloc(i64 40)
  %tgp117 = getelementptr i8, ptr %hp116, i64 8
  store i32 0, ptr %tgp117, align 4
  %cwrap118 = call ptr @march_alloc(i64 24)
  %cwt119 = getelementptr i8, ptr %cwrap118, i64 8
  store i32 0, ptr %cwt119, align 4
  %cwf120 = getelementptr i8, ptr %cwrap118, i64 16
  store ptr @Worker_dispatch$clo_wrap, ptr %cwf120, align 8
  %fp121 = getelementptr i8, ptr %hp116, i64 16
  store ptr %cwrap118, ptr %fp121, align 8
  %fp122 = getelementptr i8, ptr %hp116, i64 24
  store i64 1, ptr %fp122, align 8
  %ld123 = load i64, ptr %$init_count_i27.addr
  %fp124 = getelementptr i8, ptr %hp116, i64 32
  store i64 %ld123, ptr %fp124, align 8
  %$spawned_i28.addr = alloca ptr
  store ptr %hp116, ptr %$spawned_i28.addr
  %ld125 = load ptr, ptr %$spawned_i28.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld125, ptr %$raw_actor.addr
  %ld126 = load ptr, ptr %$raw_actor.addr
  %cr127 = call ptr @march_spawn(ptr %ld126)
  %worker.addr = alloca ptr
  store ptr %cr127, ptr %worker.addr
  %hp128 = call ptr @march_alloc(i64 24)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  %fp130 = getelementptr i8, ptr %hp128, i64 16
  store i64 0, ptr %fp130, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp128, ptr %$init_state_i23.addr
  %ld131 = load ptr, ptr %$init_state_i23.addr
  %fp132 = getelementptr i8, ptr %ld131, i64 16
  %fv133 = load i64, ptr %fp132, align 8
  %$init_down_count_i24.addr = alloca i64
  store i64 %fv133, ptr %$init_down_count_i24.addr
  %hp134 = call ptr @march_alloc(i64 40)
  %tgp135 = getelementptr i8, ptr %hp134, i64 8
  store i32 0, ptr %tgp135, align 4
  %cwrap136 = call ptr @march_alloc(i64 24)
  %cwt137 = getelementptr i8, ptr %cwrap136, i64 8
  store i32 0, ptr %cwt137, align 4
  %cwf138 = getelementptr i8, ptr %cwrap136, i64 16
  store ptr @Watcher_dispatch$clo_wrap, ptr %cwf138, align 8
  %fp139 = getelementptr i8, ptr %hp134, i64 16
  store ptr %cwrap136, ptr %fp139, align 8
  %fp140 = getelementptr i8, ptr %hp134, i64 24
  store i64 1, ptr %fp140, align 8
  %ld141 = load i64, ptr %$init_down_count_i24.addr
  %fp142 = getelementptr i8, ptr %hp134, i64 32
  store i64 %ld141, ptr %fp142, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp134, ptr %$spawned_i25.addr
  %ld143 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor_1.addr = alloca ptr
  store ptr %ld143, ptr %$raw_actor_1.addr
  %ld144 = load ptr, ptr %$raw_actor_1.addr
  %cr145 = call ptr @march_spawn(ptr %ld144)
  %watcher.addr = alloca ptr
  store ptr %cr145, ptr %watcher.addr
  %ld146 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld146)
  %ld147 = load ptr, ptr %worker.addr
  %cr148 = call ptr @march_value_to_string(ptr %ld147)
  %$t2015.addr = alloca ptr
  store ptr %cr148, ptr %$t2015.addr
  %sl149 = call ptr @march_string_lit(ptr @.str5, i64 13)
  %ld150 = load ptr, ptr %$t2015.addr
  %cr151 = call ptr @march_string_concat(ptr %sl149, ptr %ld150)
  %$t2016.addr = alloca ptr
  store ptr %cr151, ptr %$t2016.addr
  %ld152 = load ptr, ptr %$t2016.addr
  call void @march_println(ptr %ld152)
  %ld153 = load ptr, ptr %watcher.addr
  call void @march_incrc(ptr %ld153)
  %ld154 = load ptr, ptr %watcher.addr
  %cr155 = call ptr @march_value_to_string(ptr %ld154)
  %$t2017.addr = alloca ptr
  store ptr %cr155, ptr %$t2017.addr
  %sl156 = call ptr @march_string_lit(ptr @.str6, i64 13)
  %ld157 = load ptr, ptr %$t2017.addr
  %cr158 = call ptr @march_string_concat(ptr %sl156, ptr %ld157)
  %$t2018.addr = alloca ptr
  store ptr %cr158, ptr %$t2018.addr
  %ld159 = load ptr, ptr %$t2018.addr
  call void @march_println(ptr %ld159)
  %sl160 = call ptr @march_string_lit(ptr @.str7, i64 0)
  call void @march_println(ptr %sl160)
  %ld161 = load ptr, ptr %watcher.addr
  call void @march_incrc(ptr %ld161)
  %ld162 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld162)
  %ld163 = load ptr, ptr %watcher.addr
  %ld164 = load ptr, ptr %worker.addr
  %cr165 = call i64 @march_monitor(ptr %ld163, ptr %ld164)
  %ref1.addr = alloca i64
  store i64 %cr165, ptr %ref1.addr
  %ld166 = load i64, ptr %ref1.addr
  %cr167 = call ptr @march_int_to_string(i64 %ld166)
  %$t2019.addr = alloca ptr
  store ptr %cr167, ptr %$t2019.addr
  %sl168 = call ptr @march_string_lit(ptr @.str8, i64 27)
  %ld169 = load ptr, ptr %$t2019.addr
  %cr170 = call ptr @march_string_concat(ptr %sl168, ptr %ld169)
  %$t2020.addr = alloca ptr
  store ptr %cr170, ptr %$t2020.addr
  %ld171 = load ptr, ptr %$t2020.addr
  call void @march_println(ptr %ld171)
  %ld172 = load ptr, ptr %watcher.addr
  call void @march_incrc(ptr %ld172)
  %ld173 = load ptr, ptr %watcher.addr
  %cr174 = call i64 @march_mailbox_size(ptr %ld173)
  %$t2021.addr = alloca i64
  store i64 %cr174, ptr %$t2021.addr
  %ld175 = load i64, ptr %$t2021.addr
  %cr176 = call ptr @march_int_to_string(i64 %ld175)
  %$t2022.addr = alloca ptr
  store ptr %cr176, ptr %$t2022.addr
  %sl177 = call ptr @march_string_lit(ptr @.str9, i64 36)
  %ld178 = load ptr, ptr %$t2022.addr
  %cr179 = call ptr @march_string_concat(ptr %sl177, ptr %ld178)
  %$t2023.addr = alloca ptr
  store ptr %cr179, ptr %$t2023.addr
  %ld180 = load ptr, ptr %$t2023.addr
  call void @march_println(ptr %ld180)
  %sl181 = call ptr @march_string_lit(ptr @.str10, i64 0)
  call void @march_println(ptr %sl181)
  %hp182 = call ptr @march_alloc(i64 16)
  %tgp183 = getelementptr i8, ptr %hp182, i64 8
  store i32 0, ptr %tgp183, align 4
  %$t2024.addr = alloca ptr
  store ptr %hp182, ptr %$t2024.addr
  %ld184 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld184)
  %ld185 = load ptr, ptr %worker.addr
  %ld186 = load ptr, ptr %$t2024.addr
  %cr187 = call ptr @march_send(ptr %ld185, ptr %ld186)
  %hp188 = call ptr @march_alloc(i64 16)
  %tgp189 = getelementptr i8, ptr %hp188, i64 8
  store i32 0, ptr %tgp189, align 4
  %$t2025.addr = alloca ptr
  store ptr %hp188, ptr %$t2025.addr
  %ld190 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld190)
  %ld191 = load ptr, ptr %worker.addr
  %ld192 = load ptr, ptr %$t2025.addr
  %cr193 = call ptr @march_send(ptr %ld191, ptr %ld192)
  %sl194 = call ptr @march_string_lit(ptr @.str11, i64 0)
  call void @march_println(ptr %sl194)
  %sl195 = call ptr @march_string_lit(ptr @.str12, i64 17)
  call void @march_println(ptr %sl195)
  %ld196 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld196)
  %ld197 = load ptr, ptr %worker.addr
  call void @march_kill(ptr %ld197)
  %ld198 = load ptr, ptr %worker.addr
  call void @march_incrc(ptr %ld198)
  %ld199 = load ptr, ptr %worker.addr
  %cr200 = call i64 @march_is_alive(ptr %ld199)
  %$t2026.addr = alloca i64
  store i64 %cr200, ptr %$t2026.addr
  %ld201 = load i64, ptr %$t2026.addr
  %cr202 = call ptr @march_bool_to_string(i64 %ld201)
  %$t2027.addr = alloca ptr
  store ptr %cr202, ptr %$t2027.addr
  %sl203 = call ptr @march_string_lit(ptr @.str13, i64 14)
  %ld204 = load ptr, ptr %$t2027.addr
  %cr205 = call ptr @march_string_concat(ptr %sl203, ptr %ld204)
  %$t2028.addr = alloca ptr
  store ptr %cr205, ptr %$t2028.addr
  %ld206 = load ptr, ptr %$t2028.addr
  call void @march_println(ptr %ld206)
  %ld207 = load ptr, ptr %watcher.addr
  call void @march_incrc(ptr %ld207)
  %ld208 = load ptr, ptr %watcher.addr
  %cr209 = call i64 @march_mailbox_size(ptr %ld208)
  %mbox1.addr = alloca i64
  store i64 %cr209, ptr %mbox1.addr
  %ld210 = load i64, ptr %mbox1.addr
  %cr211 = call ptr @march_int_to_string(i64 %ld210)
  %$t2029.addr = alloca ptr
  store ptr %cr211, ptr %$t2029.addr
  %sl212 = call ptr @march_string_lit(ptr @.str14, i64 36)
  %ld213 = load ptr, ptr %$t2029.addr
  %cr214 = call ptr @march_string_concat(ptr %sl212, ptr %ld213)
  %$t2030.addr = alloca ptr
  store ptr %cr214, ptr %$t2030.addr
  %ld215 = load ptr, ptr %$t2030.addr
  call void @march_println(ptr %ld215)
  %sl216 = call ptr @march_string_lit(ptr @.str15, i64 38)
  call void @march_println(ptr %sl216)
  %sl217 = call ptr @march_string_lit(ptr @.str16, i64 0)
  call void @march_println(ptr %sl217)
  %ld218 = load i64, ptr %ref1.addr
  call void @march_demonitor(i64 %ld218)
  %ld219 = load i64, ptr %ref1.addr
  %cr220 = call ptr @march_int_to_string(i64 %ld219)
  %$t2031.addr = alloca ptr
  store ptr %cr220, ptr %$t2031.addr
  %sl221 = call ptr @march_string_lit(ptr @.str17, i64 23)
  %ld222 = load ptr, ptr %$t2031.addr
  %cr223 = call ptr @march_string_concat(ptr %sl221, ptr %ld222)
  %$t2032.addr = alloca ptr
  store ptr %cr223, ptr %$t2032.addr
  %ld224 = load ptr, ptr %$t2032.addr
  %sl225 = call ptr @march_string_lit(ptr @.str18, i64 1)
  %cr226 = call ptr @march_string_concat(ptr %ld224, ptr %sl225)
  %$t2033.addr = alloca ptr
  store ptr %cr226, ptr %$t2033.addr
  %ld227 = load ptr, ptr %$t2033.addr
  call void @march_println(ptr %ld227)
  %sl228 = call ptr @march_string_lit(ptr @.str19, i64 0)
  call void @march_println(ptr %sl228)
  %sl229 = call ptr @march_string_lit(ptr @.str20, i64 31)
  call void @march_println(ptr %sl229)
  %ld230 = load ptr, ptr %watcher.addr
  call void @march_incrc(ptr %ld230)
  %ld231 = load ptr, ptr %watcher.addr
  %ld232 = load ptr, ptr %worker.addr
  %cr233 = call i64 @march_monitor(ptr %ld231, ptr %ld232)
  %ref2.addr = alloca i64
  store i64 %cr233, ptr %ref2.addr
  %ld234 = load ptr, ptr %watcher.addr
  %cr235 = call i64 @march_mailbox_size(ptr %ld234)
  %mbox2.addr = alloca i64
  store i64 %cr235, ptr %mbox2.addr
  %ld236 = load i64, ptr %ref2.addr
  %cr237 = call ptr @march_int_to_string(i64 %ld236)
  %$t2034.addr = alloca ptr
  store ptr %cr237, ptr %$t2034.addr
  %sl238 = call ptr @march_string_lit(ptr @.str21, i64 26)
  %ld239 = load ptr, ptr %$t2034.addr
  %cr240 = call ptr @march_string_concat(ptr %sl238, ptr %ld239)
  %$t2035.addr = alloca ptr
  store ptr %cr240, ptr %$t2035.addr
  %ld241 = load ptr, ptr %$t2035.addr
  call void @march_println(ptr %ld241)
  %ld242 = load i64, ptr %mbox2.addr
  %cr243 = call ptr @march_int_to_string(i64 %ld242)
  %$t2036.addr = alloca ptr
  store ptr %cr243, ptr %$t2036.addr
  %sl244 = call ptr @march_string_lit(ptr @.str22, i64 22)
  %ld245 = load ptr, ptr %$t2036.addr
  %cr246 = call ptr @march_string_concat(ptr %sl244, ptr %ld245)
  %$t2037.addr = alloca ptr
  store ptr %cr246, ptr %$t2037.addr
  %ld247 = load ptr, ptr %$t2037.addr
  call void @march_println(ptr %ld247)
  %sl248 = call ptr @march_string_lit(ptr @.str23, i64 63)
  call void @march_println(ptr %sl248)
  %ld249 = load i64, ptr %ref2.addr
  call void @march_demonitor(i64 %ld249)
  %sl250 = call ptr @march_string_lit(ptr @.str24, i64 0)
  call void @march_println(ptr %sl250)
  %sl251 = call ptr @march_string_lit(ptr @.str25, i64 12)
  call void @march_println(ptr %sl251)
  %cv252 = inttoptr i64 0 to ptr
  ret ptr %cv252
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @Worker_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Worker_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

define ptr @Watcher_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Watcher_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

