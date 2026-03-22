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

@.str1 = private unnamed_addr constant [34 x i8] c"=== Supervisor Demo (Phase 2) ===\00"
@.str2 = private unnamed_addr constant [1 x i8] c"\00"
@.str3 = private unnamed_addr constant [50 x i8] c"AppSupervisor spawned (auto-started Worker child)\00"
@.str4 = private unnamed_addr constant [19 x i8] c"supervisor alive: \00"
@.str5 = private unnamed_addr constant [1 x i8] c"\00"
@.str6 = private unnamed_addr constant [23 x i8] c"initial worker pid:   \00"
@.str7 = private unnamed_addr constant [23 x i8] c"initial worker alive: \00"
@.str8 = private unnamed_addr constant [1 x i8] c"\00"
@.str9 = private unnamed_addr constant [31 x i8] c"--- Sending work to worker ---\00"
@.str10 = private unnamed_addr constant [1 x i8] c"\00"
@.str11 = private unnamed_addr constant [30 x i8] c"--- Crashing the worker (pid \00"
@.str12 = private unnamed_addr constant [6 x i8] c") ---\00"
@.str13 = private unnamed_addr constant [30 x i8] c"old worker alive after kill: \00"
@.str14 = private unnamed_addr constant [1 x i8] c"\00"
@.str15 = private unnamed_addr constant [31 x i8] c"new worker pid after restart: \00"
@.str16 = private unnamed_addr constant [31 x i8] c"new worker alive:             \00"
@.str17 = private unnamed_addr constant [14 x i8] c"(old pid was \00"
@.str18 = private unnamed_addr constant [14 x i8] c", new pid is \00"
@.str19 = private unnamed_addr constant [17 x i8] c" \E2\80\94 different!)\00"
@.str20 = private unnamed_addr constant [1 x i8] c"\00"
@.str21 = private unnamed_addr constant [65 x i8] c"--- New worker responds with fresh state (count starts at 0) ---\00"
@.str22 = private unnamed_addr constant [1 x i8] c"\00"
@.str23 = private unnamed_addr constant [19 x i8] c"supervisor alive: \00"
@.str24 = private unnamed_addr constant [1 x i8] c"\00"
@.str25 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"
@.str26 = private unnamed_addr constant [7 x i8] c"worker\00"
@.str27 = private unnamed_addr constant [7 x i8] c"worker\00"

define void @AppSupervisor_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld1 = load ptr, ptr %$msg.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      
  ]
case_default2:
  unreachable
case_merge1:
  %case_r5 = load ptr, ptr %res_slot2
  ret void
}

define ptr @march_main() {
entry:
  %sl6 = call ptr @march_string_lit(ptr @.str1, i64 33)
  call void @march_println(ptr %sl6)
  %sl7 = call ptr @march_string_lit(ptr @.str2, i64 0)
  call void @march_println(ptr %sl7)
  %hp8 = call ptr @march_alloc(i64 24)
  %tgp9 = getelementptr i8, ptr %hp8, i64 8
  store i32 0, ptr %tgp9, align 4
  %fp10 = getelementptr i8, ptr %hp8, i64 16
  store i64 0, ptr %fp10, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp8, ptr %$init_state_i23.addr
  %ld11 = load ptr, ptr %$init_state_i23.addr
  %fp12 = getelementptr i8, ptr %ld11, i64 16
  %fv13 = load i64, ptr %fp12, align 8
  %$init_worker_i24.addr = alloca i64
  store i64 %fv13, ptr %$init_worker_i24.addr
  %hp14 = call ptr @march_alloc(i64 40)
  %tgp15 = getelementptr i8, ptr %hp14, i64 8
  store i32 0, ptr %tgp15, align 4
  %cwrap16 = call ptr @march_alloc(i64 24)
  %cwt17 = getelementptr i8, ptr %cwrap16, i64 8
  store i32 0, ptr %cwt17, align 4
  %cwf18 = getelementptr i8, ptr %cwrap16, i64 16
  store ptr @AppSupervisor_dispatch$clo_wrap, ptr %cwf18, align 8
  %fp19 = getelementptr i8, ptr %hp14, i64 16
  store ptr %cwrap16, ptr %fp19, align 8
  %fp20 = getelementptr i8, ptr %hp14, i64 24
  store i64 1, ptr %fp20, align 8
  %ld21 = load i64, ptr %$init_worker_i24.addr
  %fp22 = getelementptr i8, ptr %hp14, i64 32
  store i64 %ld21, ptr %fp22, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp14, ptr %$spawned_i25.addr
  %ld23 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld23, ptr %$raw_actor.addr
  %ld24 = load ptr, ptr %$raw_actor.addr
  %cr25 = call ptr @march_spawn(ptr %ld24)
  %sup.addr = alloca ptr
  store ptr %cr25, ptr %sup.addr
  %sl26 = call ptr @march_string_lit(ptr @.str3, i64 49)
  call void @march_println(ptr %sl26)
  %ld27 = load ptr, ptr %sup.addr
  call void @march_incrc(ptr %ld27)
  %ld28 = load ptr, ptr %sup.addr
  %cr29 = call i64 @march_is_alive(ptr %ld28)
  %$t2018.addr = alloca i64
  store i64 %cr29, ptr %$t2018.addr
  %ld30 = load i64, ptr %$t2018.addr
  %cr31 = call ptr @march_bool_to_string(i64 %ld30)
  %$t2019.addr = alloca ptr
  store ptr %cr31, ptr %$t2019.addr
  %sl32 = call ptr @march_string_lit(ptr @.str4, i64 18)
  %ld33 = load ptr, ptr %$t2019.addr
  %cr34 = call ptr @march_string_concat(ptr %sl32, ptr %ld33)
  %$t2020.addr = alloca ptr
  store ptr %cr34, ptr %$t2020.addr
  %ld35 = load ptr, ptr %$t2020.addr
  call void @march_println(ptr %ld35)
  %sl36 = call ptr @march_string_lit(ptr @.str5, i64 0)
  call void @march_println(ptr %sl36)
  %ld37 = load ptr, ptr %sup.addr
  call void @march_incrc(ptr %ld37)
  %ld38 = load ptr, ptr %sup.addr
  %cr39 = call ptr @get_worker_pid$Pid_V__6045(ptr %ld38)
  %w1.addr = alloca ptr
  store ptr %cr39, ptr %w1.addr
  %ld40 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld40)
  %ld41 = load ptr, ptr %w1.addr
  %cr42 = call ptr @march_value_to_string(ptr %ld41)
  %$t2021.addr = alloca ptr
  store ptr %cr42, ptr %$t2021.addr
  %sl43 = call ptr @march_string_lit(ptr @.str6, i64 22)
  %ld44 = load ptr, ptr %$t2021.addr
  %cr45 = call ptr @march_string_concat(ptr %sl43, ptr %ld44)
  %$t2022.addr = alloca ptr
  store ptr %cr45, ptr %$t2022.addr
  %ld46 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld46)
  %ld47 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld47)
  %ld48 = load ptr, ptr %w1.addr
  %cr49 = call i64 @march_is_alive(ptr %ld48)
  %$t2023.addr = alloca i64
  store i64 %cr49, ptr %$t2023.addr
  %ld50 = load i64, ptr %$t2023.addr
  %cr51 = call ptr @march_bool_to_string(i64 %ld50)
  %$t2024.addr = alloca ptr
  store ptr %cr51, ptr %$t2024.addr
  %sl52 = call ptr @march_string_lit(ptr @.str7, i64 22)
  %ld53 = load ptr, ptr %$t2024.addr
  %cr54 = call ptr @march_string_concat(ptr %sl52, ptr %ld53)
  %$t2025.addr = alloca ptr
  store ptr %cr54, ptr %$t2025.addr
  %ld55 = load ptr, ptr %$t2025.addr
  call void @march_println(ptr %ld55)
  %sl56 = call ptr @march_string_lit(ptr @.str8, i64 0)
  call void @march_println(ptr %sl56)
  %sl57 = call ptr @march_string_lit(ptr @.str9, i64 30)
  call void @march_println(ptr %sl57)
  %hp58 = call ptr @march_alloc(i64 16)
  %tgp59 = getelementptr i8, ptr %hp58, i64 8
  store i32 0, ptr %tgp59, align 4
  %$t2026.addr = alloca ptr
  store ptr %hp58, ptr %$t2026.addr
  %ld60 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld60)
  %ld61 = load ptr, ptr %w1.addr
  %ld62 = load ptr, ptr %$t2026.addr
  %cr63 = call ptr @march_send(ptr %ld61, ptr %ld62)
  %hp64 = call ptr @march_alloc(i64 16)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 0, ptr %tgp65, align 4
  %$t2027.addr = alloca ptr
  store ptr %hp64, ptr %$t2027.addr
  %ld66 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld66)
  %ld67 = load ptr, ptr %w1.addr
  %ld68 = load ptr, ptr %$t2027.addr
  %cr69 = call ptr @march_send(ptr %ld67, ptr %ld68)
  %hp70 = call ptr @march_alloc(i64 16)
  %tgp71 = getelementptr i8, ptr %hp70, i64 8
  store i32 0, ptr %tgp71, align 4
  %$t2028.addr = alloca ptr
  store ptr %hp70, ptr %$t2028.addr
  %ld72 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld72)
  %ld73 = load ptr, ptr %w1.addr
  %ld74 = load ptr, ptr %$t2028.addr
  %cr75 = call ptr @march_send(ptr %ld73, ptr %ld74)
  %hp76 = call ptr @march_alloc(i64 16)
  %tgp77 = getelementptr i8, ptr %hp76, i64 8
  store i32 1, ptr %tgp77, align 4
  %$t2029.addr = alloca ptr
  store ptr %hp76, ptr %$t2029.addr
  %ld78 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld78)
  %ld79 = load ptr, ptr %w1.addr
  %ld80 = load ptr, ptr %$t2029.addr
  %cr81 = call ptr @march_send(ptr %ld79, ptr %ld80)
  call void @march_run_until_idle()
  %sl82 = call ptr @march_string_lit(ptr @.str10, i64 0)
  call void @march_println(ptr %sl82)
  %ld83 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld83)
  %ld84 = load ptr, ptr %w1.addr
  %cr85 = call ptr @march_value_to_string(ptr %ld84)
  %$t2030.addr = alloca ptr
  store ptr %cr85, ptr %$t2030.addr
  %sl86 = call ptr @march_string_lit(ptr @.str11, i64 29)
  %ld87 = load ptr, ptr %$t2030.addr
  %cr88 = call ptr @march_string_concat(ptr %sl86, ptr %ld87)
  %$t2031.addr = alloca ptr
  store ptr %cr88, ptr %$t2031.addr
  %ld89 = load ptr, ptr %$t2031.addr
  %sl90 = call ptr @march_string_lit(ptr @.str12, i64 5)
  %cr91 = call ptr @march_string_concat(ptr %ld89, ptr %sl90)
  %$t2032.addr = alloca ptr
  store ptr %cr91, ptr %$t2032.addr
  %ld92 = load ptr, ptr %$t2032.addr
  call void @march_println(ptr %ld92)
  %ld93 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld93)
  %ld94 = load ptr, ptr %w1.addr
  call void @march_kill(ptr %ld94)
  %ld95 = load ptr, ptr %w1.addr
  call void @march_incrc(ptr %ld95)
  %ld96 = load ptr, ptr %w1.addr
  %cr97 = call i64 @march_is_alive(ptr %ld96)
  %$t2033.addr = alloca i64
  store i64 %cr97, ptr %$t2033.addr
  %ld98 = load i64, ptr %$t2033.addr
  %cr99 = call ptr @march_bool_to_string(i64 %ld98)
  %$t2034.addr = alloca ptr
  store ptr %cr99, ptr %$t2034.addr
  %sl100 = call ptr @march_string_lit(ptr @.str13, i64 29)
  %ld101 = load ptr, ptr %$t2034.addr
  %cr102 = call ptr @march_string_concat(ptr %sl100, ptr %ld101)
  %$t2035.addr = alloca ptr
  store ptr %cr102, ptr %$t2035.addr
  %ld103 = load ptr, ptr %$t2035.addr
  call void @march_println(ptr %ld103)
  %sl104 = call ptr @march_string_lit(ptr @.str14, i64 0)
  call void @march_println(ptr %sl104)
  %ld105 = load ptr, ptr %sup.addr
  call void @march_incrc(ptr %ld105)
  %ld106 = load ptr, ptr %sup.addr
  %cr107 = call ptr @get_worker_pid$Pid_V__6067(ptr %ld106)
  %w2.addr = alloca ptr
  store ptr %cr107, ptr %w2.addr
  %ld108 = load ptr, ptr %w2.addr
  call void @march_incrc(ptr %ld108)
  %ld109 = load ptr, ptr %w2.addr
  %cr110 = call ptr @march_value_to_string(ptr %ld109)
  %$t2036.addr = alloca ptr
  store ptr %cr110, ptr %$t2036.addr
  %sl111 = call ptr @march_string_lit(ptr @.str15, i64 30)
  %ld112 = load ptr, ptr %$t2036.addr
  %cr113 = call ptr @march_string_concat(ptr %sl111, ptr %ld112)
  %$t2037.addr = alloca ptr
  store ptr %cr113, ptr %$t2037.addr
  %ld114 = load ptr, ptr %$t2037.addr
  call void @march_println(ptr %ld114)
  %ld115 = load ptr, ptr %w2.addr
  call void @march_incrc(ptr %ld115)
  %ld116 = load ptr, ptr %w2.addr
  %cr117 = call i64 @march_is_alive(ptr %ld116)
  %$t2038.addr = alloca i64
  store i64 %cr117, ptr %$t2038.addr
  %ld118 = load i64, ptr %$t2038.addr
  %cr119 = call ptr @march_bool_to_string(i64 %ld118)
  %$t2039.addr = alloca ptr
  store ptr %cr119, ptr %$t2039.addr
  %sl120 = call ptr @march_string_lit(ptr @.str16, i64 30)
  %ld121 = load ptr, ptr %$t2039.addr
  %cr122 = call ptr @march_string_concat(ptr %sl120, ptr %ld121)
  %$t2040.addr = alloca ptr
  store ptr %cr122, ptr %$t2040.addr
  %ld123 = load ptr, ptr %$t2040.addr
  call void @march_println(ptr %ld123)
  %ld124 = load ptr, ptr %w1.addr
  %cr125 = call ptr @march_value_to_string(ptr %ld124)
  %$t2041.addr = alloca ptr
  store ptr %cr125, ptr %$t2041.addr
  %sl126 = call ptr @march_string_lit(ptr @.str17, i64 13)
  %ld127 = load ptr, ptr %$t2041.addr
  %cr128 = call ptr @march_string_concat(ptr %sl126, ptr %ld127)
  %$t2042.addr = alloca ptr
  store ptr %cr128, ptr %$t2042.addr
  %ld129 = load ptr, ptr %$t2042.addr
  %sl130 = call ptr @march_string_lit(ptr @.str18, i64 13)
  %cr131 = call ptr @march_string_concat(ptr %ld129, ptr %sl130)
  %$t2043.addr = alloca ptr
  store ptr %cr131, ptr %$t2043.addr
  %ld132 = load ptr, ptr %w2.addr
  call void @march_incrc(ptr %ld132)
  %ld133 = load ptr, ptr %w2.addr
  %cr134 = call ptr @march_value_to_string(ptr %ld133)
  %$t2044.addr = alloca ptr
  store ptr %cr134, ptr %$t2044.addr
  %ld135 = load ptr, ptr %$t2043.addr
  %ld136 = load ptr, ptr %$t2044.addr
  %cr137 = call ptr @march_string_concat(ptr %ld135, ptr %ld136)
  %$t2045.addr = alloca ptr
  store ptr %cr137, ptr %$t2045.addr
  %ld138 = load ptr, ptr %$t2045.addr
  %sl139 = call ptr @march_string_lit(ptr @.str19, i64 16)
  %cr140 = call ptr @march_string_concat(ptr %ld138, ptr %sl139)
  %$t2046.addr = alloca ptr
  store ptr %cr140, ptr %$t2046.addr
  %ld141 = load ptr, ptr %$t2046.addr
  call void @march_println(ptr %ld141)
  %sl142 = call ptr @march_string_lit(ptr @.str20, i64 0)
  call void @march_println(ptr %sl142)
  %sl143 = call ptr @march_string_lit(ptr @.str21, i64 64)
  call void @march_println(ptr %sl143)
  %hp144 = call ptr @march_alloc(i64 16)
  %tgp145 = getelementptr i8, ptr %hp144, i64 8
  store i32 0, ptr %tgp145, align 4
  %$t2047.addr = alloca ptr
  store ptr %hp144, ptr %$t2047.addr
  %ld146 = load ptr, ptr %w2.addr
  call void @march_incrc(ptr %ld146)
  %ld147 = load ptr, ptr %w2.addr
  %ld148 = load ptr, ptr %$t2047.addr
  %cr149 = call ptr @march_send(ptr %ld147, ptr %ld148)
  %hp150 = call ptr @march_alloc(i64 16)
  %tgp151 = getelementptr i8, ptr %hp150, i64 8
  store i32 1, ptr %tgp151, align 4
  %$t2048.addr = alloca ptr
  store ptr %hp150, ptr %$t2048.addr
  %ld152 = load ptr, ptr %w2.addr
  %ld153 = load ptr, ptr %$t2048.addr
  %cr154 = call ptr @march_send(ptr %ld152, ptr %ld153)
  call void @march_run_until_idle()
  %sl155 = call ptr @march_string_lit(ptr @.str22, i64 0)
  call void @march_println(ptr %sl155)
  %ld156 = load ptr, ptr %sup.addr
  %cr157 = call i64 @march_is_alive(ptr %ld156)
  %$t2049.addr = alloca i64
  store i64 %cr157, ptr %$t2049.addr
  %ld158 = load i64, ptr %$t2049.addr
  %cr159 = call ptr @march_bool_to_string(i64 %ld158)
  %$t2050.addr = alloca ptr
  store ptr %cr159, ptr %$t2050.addr
  %sl160 = call ptr @march_string_lit(ptr @.str23, i64 18)
  %ld161 = load ptr, ptr %$t2050.addr
  %cr162 = call ptr @march_string_concat(ptr %sl160, ptr %ld161)
  %$t2051.addr = alloca ptr
  store ptr %cr162, ptr %$t2051.addr
  %ld163 = load ptr, ptr %$t2051.addr
  call void @march_println(ptr %ld163)
  %sl164 = call ptr @march_string_lit(ptr @.str24, i64 0)
  call void @march_println(ptr %sl164)
  %sl165 = call ptr @march_string_lit(ptr @.str25, i64 12)
  call void @march_println(ptr %sl165)
  %cv166 = inttoptr i64 0 to ptr
  ret ptr %cv166
}

define ptr @get_worker_pid$Pid_V__6067(ptr %sup.arg) {
entry:
  %sup.addr = alloca ptr
  store ptr %sup.arg, ptr %sup.addr
  %ld167 = load ptr, ptr %sup.addr
  %sl168 = call ptr @march_string_lit(ptr @.str26, i64 6)
  %cr169 = call ptr @march_get_actor_field(ptr %ld167, ptr %sl168)
  %$t2015.addr = alloca ptr
  store ptr %cr169, ptr %$t2015.addr
  %ld170 = load ptr, ptr %$t2015.addr
  %res_slot171 = alloca ptr
  %tgp172 = getelementptr i8, ptr %ld170, i64 8
  %tag173 = load i32, ptr %tgp172, align 4
  switch i32 %tag173, label %case_default4 [
      i32 0, label %case_br5
      i32 1, label %case_br6
  ]
case_br5:
  %ld174 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld174)
  %ar175 = sub i64 0, 1
  %$t2016.addr = alloca i64
  store i64 %ar175, ptr %$t2016.addr
  %ld176 = load i64, ptr %$t2016.addr
  %cr177 = call ptr @march_pid_of_int(i64 %ld176)
  store ptr %cr177, ptr %res_slot171
  br label %case_merge3
case_br6:
  %fp178 = getelementptr i8, ptr %ld170, i64 16
  %fv179 = load ptr, ptr %fp178, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv179, ptr %$f2017.addr
  %ld180 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld180)
  %ld181 = load ptr, ptr %$f2017.addr
  %n.addr = alloca ptr
  store ptr %ld181, ptr %n.addr
  %ld182 = load ptr, ptr %n.addr
  %cr183 = call ptr @march_pid_of_int(ptr %ld182)
  store ptr %cr183, ptr %res_slot171
  br label %case_merge3
case_default4:
  unreachable
case_merge3:
  %case_r184 = load ptr, ptr %res_slot171
  ret ptr %case_r184
}

define ptr @get_worker_pid$Pid_V__6045(ptr %sup.arg) {
entry:
  %sup.addr = alloca ptr
  store ptr %sup.arg, ptr %sup.addr
  %ld185 = load ptr, ptr %sup.addr
  %sl186 = call ptr @march_string_lit(ptr @.str27, i64 6)
  %cr187 = call ptr @march_get_actor_field(ptr %ld185, ptr %sl186)
  %$t2015.addr = alloca ptr
  store ptr %cr187, ptr %$t2015.addr
  %ld188 = load ptr, ptr %$t2015.addr
  %res_slot189 = alloca ptr
  %tgp190 = getelementptr i8, ptr %ld188, i64 8
  %tag191 = load i32, ptr %tgp190, align 4
  switch i32 %tag191, label %case_default8 [
      i32 0, label %case_br9
      i32 1, label %case_br10
  ]
case_br9:
  %ld192 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld192)
  %ar193 = sub i64 0, 1
  %$t2016.addr = alloca i64
  store i64 %ar193, ptr %$t2016.addr
  %ld194 = load i64, ptr %$t2016.addr
  %cr195 = call ptr @march_pid_of_int(i64 %ld194)
  store ptr %cr195, ptr %res_slot189
  br label %case_merge7
case_br10:
  %fp196 = getelementptr i8, ptr %ld188, i64 16
  %fv197 = load ptr, ptr %fp196, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv197, ptr %$f2017.addr
  %ld198 = load ptr, ptr %$t2015.addr
  call void @march_decrc(ptr %ld198)
  %ld199 = load ptr, ptr %$f2017.addr
  %n.addr = alloca ptr
  store ptr %ld199, ptr %n.addr
  %ld200 = load ptr, ptr %n.addr
  %cr201 = call ptr @march_pid_of_int(ptr %ld200)
  store ptr %cr201, ptr %res_slot189
  br label %case_merge7
case_default8:
  unreachable
case_merge7:
  %case_r202 = load ptr, ptr %res_slot189
  ret ptr %case_r202
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @AppSupervisor_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @AppSupervisor_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

