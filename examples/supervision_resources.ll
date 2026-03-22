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

@.str1 = private unnamed_addr constant [27 x i8] c"[Worker] doing work, id = \00"
@.str2 = private unnamed_addr constant [41 x i8] c"=== OS Resource Drop Demo (Phase 6a) ===\00"
@.str3 = private unnamed_addr constant [23 x i8] c"Worker spawned, pid = \00"
@.str4 = private unnamed_addr constant [54 x i8] c"Registering cleanup resources (reverse-order demo)...\00"
@.str5 = private unnamed_addr constant [18 x i8] c"worker_connection\00"
@.str6 = private unnamed_addr constant [11 x i8] c"worker_log\00"
@.str7 = private unnamed_addr constant [19 x i8] c"Crashing worker...\00"
@.str8 = private unnamed_addr constant [15 x i8] c"Worker alive: \00"
@.str9 = private unnamed_addr constant [63 x i8] c"(Cleanup 2 ran before Cleanup 1 \E2\80\94 reverse acquisition order)\00"
@.str10 = private unnamed_addr constant [13 x i8] c"=== Done ===\00"
@.str11 = private unnamed_addr constant [72 x i8] c"[Cleanup 1] worker_connection released (registered first, cleaned last)\00"
@.str12 = private unnamed_addr constant [66 x i8] c"[Cleanup 2] worker_log flushed (registered second, cleaned first)\00"

define void @Worker_SetId(ptr %$actor.arg, i64 %n.arg) {
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
  %$sf_id.addr = alloca i64
  store i64 %fv9, ptr %$sf_id.addr
  %hp10 = call ptr @march_alloc(i64 24)
  %tgp11 = getelementptr i8, ptr %hp10, i64 8
  store i32 0, ptr %tgp11, align 4
  %ld12 = load i64, ptr %$sf_id.addr
  %fp13 = getelementptr i8, ptr %hp10, i64 16
  store i64 %ld12, ptr %fp13, align 8
  %state.addr = alloca ptr
  store ptr %hp10, ptr %state.addr
  %ld14 = load ptr, ptr %state.addr
  call void @march_decrc(ptr %ld14)
  %hp15 = call ptr @march_alloc(i64 24)
  %tgp16 = getelementptr i8, ptr %hp15, i64 8
  store i32 0, ptr %tgp16, align 4
  %ld17 = load i64, ptr %n.addr
  %fp18 = getelementptr i8, ptr %hp15, i64 16
  store i64 %ld17, ptr %fp18, align 8
  %$result.addr = alloca ptr
  store ptr %hp15, ptr %$result.addr
  %ld19 = load ptr, ptr %$result.addr
  %fp20 = getelementptr i8, ptr %ld19, i64 16
  %fv21 = load i64, ptr %fp20, align 8
  %$nf_id.addr = alloca i64
  store i64 %fv21, ptr %$nf_id.addr
  %ld22 = load ptr, ptr %$actor.addr
  %ld23 = load ptr, ptr %$dispatch_v.addr
  %ld24 = load i64, ptr %$alive_v.addr
  %ld25 = load i64, ptr %$nf_id.addr
  %rc26 = load i64, ptr %ld22, align 8
  %uniq27 = icmp eq i64 %rc26, 1
  %fbip_slot28 = alloca ptr
  br i1 %uniq27, label %fbip_reuse1, label %fbip_fresh2
fbip_reuse1:
  %tgp29 = getelementptr i8, ptr %ld22, i64 8
  store i32 0, ptr %tgp29, align 4
  %fp30 = getelementptr i8, ptr %ld22, i64 16
  store ptr %ld23, ptr %fp30, align 8
  %fp31 = getelementptr i8, ptr %ld22, i64 24
  store i64 %ld24, ptr %fp31, align 8
  %fp32 = getelementptr i8, ptr %ld22, i64 32
  store i64 %ld25, ptr %fp32, align 8
  store ptr %ld22, ptr %fbip_slot28
  br label %fbip_merge3
fbip_fresh2:
  call void @march_decrc(ptr %ld22)
  %hp33 = call ptr @march_alloc(i64 40)
  %tgp34 = getelementptr i8, ptr %hp33, i64 8
  store i32 0, ptr %tgp34, align 4
  %fp35 = getelementptr i8, ptr %hp33, i64 16
  store ptr %ld23, ptr %fp35, align 8
  %fp36 = getelementptr i8, ptr %hp33, i64 24
  store i64 %ld24, ptr %fp36, align 8
  %fp37 = getelementptr i8, ptr %hp33, i64 32
  store i64 %ld25, ptr %fp37, align 8
  store ptr %hp33, ptr %fbip_slot28
  br label %fbip_merge3
fbip_merge3:
  %fbip_r38 = load ptr, ptr %fbip_slot28
  ret void
}

define void @Worker_Work(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %ld39 = load ptr, ptr %$actor.addr
  %fp40 = getelementptr i8, ptr %ld39, i64 16
  %fv41 = load ptr, ptr %fp40, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv41, ptr %$dispatch_v.addr
  %ld42 = load ptr, ptr %$actor.addr
  %fp43 = getelementptr i8, ptr %ld42, i64 24
  %fv44 = load i64, ptr %fp43, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv44, ptr %$alive_v.addr
  %ld45 = load ptr, ptr %$actor.addr
  %fp46 = getelementptr i8, ptr %ld45, i64 32
  %fv47 = load i64, ptr %fp46, align 8
  %$sf_id.addr = alloca i64
  store i64 %fv47, ptr %$sf_id.addr
  %hp48 = call ptr @march_alloc(i64 24)
  %tgp49 = getelementptr i8, ptr %hp48, i64 8
  store i32 0, ptr %tgp49, align 4
  %ld50 = load i64, ptr %$sf_id.addr
  %fp51 = getelementptr i8, ptr %hp48, i64 16
  store i64 %ld50, ptr %fp51, align 8
  %state.addr = alloca ptr
  store ptr %hp48, ptr %state.addr
  %ld52 = load ptr, ptr %state.addr
  %fp53 = getelementptr i8, ptr %ld52, i64 16
  %fv54 = load i64, ptr %fp53, align 8
  %$t2009.addr = alloca i64
  store i64 %fv54, ptr %$t2009.addr
  %ld55 = load i64, ptr %$t2009.addr
  %cr56 = call ptr @march_value_to_string(i64 %ld55)
  %$t2010.addr = alloca ptr
  store ptr %cr56, ptr %$t2010.addr
  %sl57 = call ptr @march_string_lit(ptr @.str1, i64 26)
  %ld58 = load ptr, ptr %$t2010.addr
  %cr59 = call ptr @march_string_concat(ptr %sl57, ptr %ld58)
  %$t2011.addr = alloca ptr
  store ptr %cr59, ptr %$t2011.addr
  %ld60 = load ptr, ptr %$t2011.addr
  call void @march_println(ptr %ld60)
  %ld61 = load ptr, ptr %state.addr
  %$result.addr = alloca ptr
  store ptr %ld61, ptr %$result.addr
  %ld62 = load ptr, ptr %$result.addr
  %fp63 = getelementptr i8, ptr %ld62, i64 16
  %fv64 = load i64, ptr %fp63, align 8
  %$nf_id.addr = alloca i64
  store i64 %fv64, ptr %$nf_id.addr
  %ld65 = load ptr, ptr %$actor.addr
  %ld66 = load ptr, ptr %$dispatch_v.addr
  %ld67 = load i64, ptr %$alive_v.addr
  %ld68 = load i64, ptr %$nf_id.addr
  %rc69 = load i64, ptr %ld65, align 8
  %uniq70 = icmp eq i64 %rc69, 1
  %fbip_slot71 = alloca ptr
  br i1 %uniq70, label %fbip_reuse4, label %fbip_fresh5
fbip_reuse4:
  %tgp72 = getelementptr i8, ptr %ld65, i64 8
  store i32 0, ptr %tgp72, align 4
  %fp73 = getelementptr i8, ptr %ld65, i64 16
  store ptr %ld66, ptr %fp73, align 8
  %fp74 = getelementptr i8, ptr %ld65, i64 24
  store i64 %ld67, ptr %fp74, align 8
  %fp75 = getelementptr i8, ptr %ld65, i64 32
  store i64 %ld68, ptr %fp75, align 8
  store ptr %ld65, ptr %fbip_slot71
  br label %fbip_merge6
fbip_fresh5:
  call void @march_decrc(ptr %ld65)
  %hp76 = call ptr @march_alloc(i64 40)
  %tgp77 = getelementptr i8, ptr %hp76, i64 8
  store i32 0, ptr %tgp77, align 4
  %fp78 = getelementptr i8, ptr %hp76, i64 16
  store ptr %ld66, ptr %fp78, align 8
  %fp79 = getelementptr i8, ptr %hp76, i64 24
  store i64 %ld67, ptr %fp79, align 8
  %fp80 = getelementptr i8, ptr %hp76, i64 32
  store i64 %ld68, ptr %fp80, align 8
  store ptr %hp76, ptr %fbip_slot71
  br label %fbip_merge6
fbip_merge6:
  %fbip_r81 = load ptr, ptr %fbip_slot71
  ret void
}

define void @Worker_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld82 = load ptr, ptr %$msg.addr
  %res_slot83 = alloca ptr
  %tgp84 = getelementptr i8, ptr %ld82, i64 8
  %tag85 = load i32, ptr %tgp84, align 4
  switch i32 %tag85, label %case_default8 [
      i32 0, label %case_br9
      i32 1, label %case_br10
  ]
case_br9:
  %fp86 = getelementptr i8, ptr %ld82, i64 16
  %fv87 = load i64, ptr %fp86, align 8
  %$SetId_n.addr = alloca i64
  store i64 %fv87, ptr %$SetId_n.addr
  %ld88 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld88)
  %ld89 = load ptr, ptr %$actor.addr
  %ld90 = load i64, ptr %$SetId_n.addr
  call void @Worker_SetId(ptr %ld89, i64 %ld90)
  %cv91 = inttoptr i64 0 to ptr
  store ptr %cv91, ptr %res_slot83
  br label %case_merge7
case_br10:
  %ld92 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld92)
  %ld93 = load ptr, ptr %$actor.addr
  call void @Worker_Work(ptr %ld93)
  %cv94 = inttoptr i64 0 to ptr
  store ptr %cv94, ptr %res_slot83
  br label %case_merge7
case_default8:
  unreachable
case_merge7:
  %case_r95 = load ptr, ptr %res_slot83
  ret void
}

define ptr @march_main() {
entry:
  %sl96 = call ptr @march_string_lit(ptr @.str2, i64 40)
  call void @march_println(ptr %sl96)
  %hp97 = call ptr @march_alloc(i64 24)
  %tgp98 = getelementptr i8, ptr %hp97, i64 8
  store i32 0, ptr %tgp98, align 4
  %fp99 = getelementptr i8, ptr %hp97, i64 16
  store i64 0, ptr %fp99, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp97, ptr %$init_state_i23.addr
  %ld100 = load ptr, ptr %$init_state_i23.addr
  %fp101 = getelementptr i8, ptr %ld100, i64 16
  %fv102 = load i64, ptr %fp101, align 8
  %$init_id_i24.addr = alloca i64
  store i64 %fv102, ptr %$init_id_i24.addr
  %hp103 = call ptr @march_alloc(i64 40)
  %tgp104 = getelementptr i8, ptr %hp103, i64 8
  store i32 0, ptr %tgp104, align 4
  %cwrap105 = call ptr @march_alloc(i64 24)
  %cwt106 = getelementptr i8, ptr %cwrap105, i64 8
  store i32 0, ptr %cwt106, align 4
  %cwf107 = getelementptr i8, ptr %cwrap105, i64 16
  store ptr @Worker_dispatch$clo_wrap, ptr %cwf107, align 8
  %fp108 = getelementptr i8, ptr %hp103, i64 16
  store ptr %cwrap105, ptr %fp108, align 8
  %fp109 = getelementptr i8, ptr %hp103, i64 24
  store i64 1, ptr %fp109, align 8
  %ld110 = load i64, ptr %$init_id_i24.addr
  %fp111 = getelementptr i8, ptr %hp103, i64 32
  store i64 %ld110, ptr %fp111, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp103, ptr %$spawned_i25.addr
  %ld112 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld112, ptr %$raw_actor.addr
  %ld113 = load ptr, ptr %$raw_actor.addr
  %cr114 = call ptr @march_spawn(ptr %ld113)
  %pid.addr = alloca ptr
  store ptr %cr114, ptr %pid.addr
  %hp115 = call ptr @march_alloc(i64 24)
  %tgp116 = getelementptr i8, ptr %hp115, i64 8
  store i32 0, ptr %tgp116, align 4
  %fp117 = getelementptr i8, ptr %hp115, i64 16
  store i64 42, ptr %fp117, align 8
  %$t2012.addr = alloca ptr
  store ptr %hp115, ptr %$t2012.addr
  %ld118 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld118)
  %ld119 = load ptr, ptr %pid.addr
  %ld120 = load ptr, ptr %$t2012.addr
  %cr121 = call ptr @march_send(ptr %ld119, ptr %ld120)
  call void @march_run_until_idle()
  %ld122 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld122)
  %ld123 = load ptr, ptr %pid.addr
  %cr124 = call ptr @march_value_to_string(ptr %ld123)
  %$t2013.addr = alloca ptr
  store ptr %cr124, ptr %$t2013.addr
  %sl125 = call ptr @march_string_lit(ptr @.str3, i64 22)
  %ld126 = load ptr, ptr %$t2013.addr
  %cr127 = call ptr @march_string_concat(ptr %sl125, ptr %ld126)
  %$t2014.addr = alloca ptr
  store ptr %cr127, ptr %$t2014.addr
  %ld128 = load ptr, ptr %$t2014.addr
  call void @march_println(ptr %ld128)
  %hp129 = call ptr @march_alloc(i64 16)
  %tgp130 = getelementptr i8, ptr %hp129, i64 8
  store i32 1, ptr %tgp130, align 4
  %$t2015.addr = alloca ptr
  store ptr %hp129, ptr %$t2015.addr
  %ld131 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld131)
  %ld132 = load ptr, ptr %pid.addr
  %ld133 = load ptr, ptr %$t2015.addr
  %cr134 = call ptr @march_send(ptr %ld132, ptr %ld133)
  call void @march_run_until_idle()
  %sl135 = call ptr @march_string_lit(ptr @.str4, i64 53)
  call void @march_println(ptr %sl135)
  %hp136 = call ptr @march_alloc(i64 24)
  %tgp137 = getelementptr i8, ptr %hp136, i64 8
  store i32 0, ptr %tgp137, align 4
  %fp138 = getelementptr i8, ptr %hp136, i64 16
  store ptr @$lam2016$apply$22, ptr %fp138, align 8
  %$t2017.addr = alloca ptr
  store ptr %hp136, ptr %$t2017.addr
  %ld139 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld139)
  %ld140 = load ptr, ptr %pid.addr
  %sl141 = call ptr @march_string_lit(ptr @.str5, i64 17)
  %ld142 = load ptr, ptr %$t2017.addr
  call void @march_register_resource(ptr %ld140, ptr %sl141, ptr %ld142)
  %hp143 = call ptr @march_alloc(i64 24)
  %tgp144 = getelementptr i8, ptr %hp143, i64 8
  store i32 0, ptr %tgp144, align 4
  %fp145 = getelementptr i8, ptr %hp143, i64 16
  store ptr @$lam2018$apply$23, ptr %fp145, align 8
  %$t2019.addr = alloca ptr
  store ptr %hp143, ptr %$t2019.addr
  %ld146 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld146)
  %ld147 = load ptr, ptr %pid.addr
  %sl148 = call ptr @march_string_lit(ptr @.str6, i64 10)
  %ld149 = load ptr, ptr %$t2019.addr
  call void @march_register_resource(ptr %ld147, ptr %sl148, ptr %ld149)
  %sl150 = call ptr @march_string_lit(ptr @.str7, i64 18)
  call void @march_println(ptr %sl150)
  %ld151 = load ptr, ptr %pid.addr
  call void @march_incrc(ptr %ld151)
  %ld152 = load ptr, ptr %pid.addr
  call void @march_kill(ptr %ld152)
  %ld153 = load ptr, ptr %pid.addr
  %cr154 = call i64 @march_is_alive(ptr %ld153)
  %$t2020.addr = alloca i64
  store i64 %cr154, ptr %$t2020.addr
  %ld155 = load i64, ptr %$t2020.addr
  %cr156 = call ptr @march_value_to_string(i64 %ld155)
  %$t2021.addr = alloca ptr
  store ptr %cr156, ptr %$t2021.addr
  %sl157 = call ptr @march_string_lit(ptr @.str8, i64 14)
  %ld158 = load ptr, ptr %$t2021.addr
  %cr159 = call ptr @march_string_concat(ptr %sl157, ptr %ld158)
  %$t2022.addr = alloca ptr
  store ptr %cr159, ptr %$t2022.addr
  %ld160 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld160)
  %sl161 = call ptr @march_string_lit(ptr @.str9, i64 62)
  call void @march_println(ptr %sl161)
  %sl162 = call ptr @march_string_lit(ptr @.str10, i64 12)
  call void @march_println(ptr %sl162)
  %cv163 = inttoptr i64 0 to ptr
  ret ptr %cv163
}

define ptr @$lam2016$apply$22(ptr %$clo.arg, ptr %_.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %_.addr = alloca ptr
  store ptr %_.arg, ptr %_.addr
  %sl164 = call ptr @march_string_lit(ptr @.str11, i64 71)
  call void @march_println(ptr %sl164)
  %cv165 = inttoptr i64 0 to ptr
  ret ptr %cv165
}

define ptr @$lam2018$apply$23(ptr %$clo.arg, ptr %_.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %_.addr = alloca ptr
  store ptr %_.arg, ptr %_.addr
  %sl166 = call ptr @march_string_lit(ptr @.str12, i64 65)
  call void @march_println(ptr %sl166)
  %cv167 = inttoptr i64 0 to ptr
  ret ptr %cv167
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

