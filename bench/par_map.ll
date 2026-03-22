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


define i64 @collatz_steps(i64 %n.arg, i64 %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp eq i64 %ld1, 1
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %ld7 = load i64, ptr %acc.addr
  %cv8 = inttoptr i64 %ld7 to ptr
  store ptr %cv8, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %n.addr
  %ar10 = srem i64 %ld9, 2
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %$t2010.addr
  %cmp12 = icmp eq i64 %ld11, 0
  %ar13 = zext i1 %cmp12 to i64
  %$t2011.addr = alloca i64
  store i64 %ar13, ptr %$t2011.addr
  %ld14 = load i64, ptr %$t2011.addr
  %res_slot15 = alloca ptr
  %bi16 = trunc i64 %ld14 to i1
  br i1 %bi16, label %case_br6, label %case_default5
case_br6:
  %ld17 = load i64, ptr %n.addr
  %ar18 = sdiv i64 %ld17, 2
  %$t2012.addr = alloca i64
  store i64 %ar18, ptr %$t2012.addr
  %ld19 = load i64, ptr %acc.addr
  %ar20 = add i64 %ld19, 1
  %$t2013.addr = alloca i64
  store i64 %ar20, ptr %$t2013.addr
  %ld21 = load i64, ptr %$t2012.addr
  %ld22 = load i64, ptr %$t2013.addr
  %cr23 = call i64 @collatz_steps(i64 %ld21, i64 %ld22)
  %cv24 = inttoptr i64 %cr23 to ptr
  store ptr %cv24, ptr %res_slot15
  br label %case_merge4
case_default5:
  %ld25 = load i64, ptr %n.addr
  %ar26 = mul i64 3, %ld25
  %$t2014.addr = alloca i64
  store i64 %ar26, ptr %$t2014.addr
  %ld27 = load i64, ptr %$t2014.addr
  %ar28 = add i64 %ld27, 1
  %$t2015.addr = alloca i64
  store i64 %ar28, ptr %$t2015.addr
  %ld29 = load i64, ptr %acc.addr
  %ar30 = add i64 %ld29, 1
  %$t2016.addr = alloca i64
  store i64 %ar30, ptr %$t2016.addr
  %ld31 = load i64, ptr %$t2015.addr
  %ld32 = load i64, ptr %$t2016.addr
  %cr33 = call i64 @collatz_steps(i64 %ld31, i64 %ld32)
  %cv34 = inttoptr i64 %cr33 to ptr
  store ptr %cv34, ptr %res_slot15
  br label %case_merge4
case_merge4:
  %case_r35 = load ptr, ptr %res_slot15
  store ptr %case_r35, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r36 = load ptr, ptr %res_slot5
  %cv37 = ptrtoint ptr %case_r36 to i64
  ret i64 %cv37
}

define ptr @range_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld38 = load i64, ptr %lo.addr
  %ld39 = load i64, ptr %hi.addr
  %cmp40 = icmp sgt i64 %ld38, %ld39
  %ar41 = zext i1 %cmp40 to i64
  %$t2017.addr = alloca i64
  store i64 %ar41, ptr %$t2017.addr
  %ld42 = load i64, ptr %$t2017.addr
  %res_slot43 = alloca ptr
  %bi44 = trunc i64 %ld42 to i1
  br i1 %bi44, label %case_br9, label %case_default8
case_br9:
  %ld45 = load ptr, ptr %acc.addr
  store ptr %ld45, ptr %res_slot43
  br label %case_merge7
case_default8:
  %ld46 = load i64, ptr %hi.addr
  %ar47 = sub i64 %ld46, 1
  %$t2018.addr = alloca i64
  store i64 %ar47, ptr %$t2018.addr
  %hp48 = call ptr @march_alloc(i64 32)
  %tgp49 = getelementptr i8, ptr %hp48, i64 8
  store i32 1, ptr %tgp49, align 4
  %ld50 = load i64, ptr %hi.addr
  %cv51 = inttoptr i64 %ld50 to ptr
  %fp52 = getelementptr i8, ptr %hp48, i64 16
  store ptr %cv51, ptr %fp52, align 8
  %ld53 = load ptr, ptr %acc.addr
  %fp54 = getelementptr i8, ptr %hp48, i64 24
  store ptr %ld53, ptr %fp54, align 8
  %$t2019.addr = alloca ptr
  store ptr %hp48, ptr %$t2019.addr
  %ld55 = load i64, ptr %lo.addr
  %ld56 = load i64, ptr %$t2018.addr
  %ld57 = load ptr, ptr %$t2019.addr
  %cr58 = call ptr @range_acc(i64 %ld55, i64 %ld56, ptr %ld57)
  store ptr %cr58, ptr %res_slot43
  br label %case_merge7
case_merge7:
  %case_r59 = load ptr, ptr %res_slot43
  ret ptr %case_r59
}

define i64 @sum(ptr %xs.arg, i64 %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld60 = load ptr, ptr %xs.addr
  %res_slot61 = alloca ptr
  %tgp62 = getelementptr i8, ptr %ld60, i64 8
  %tag63 = load i32, ptr %tgp62, align 4
  switch i32 %tag63, label %case_default11 [
      i32 0, label %case_br12
      i32 1, label %case_br13
  ]
case_br12:
  %ld64 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld64)
  %ld65 = load i64, ptr %acc.addr
  %cv66 = inttoptr i64 %ld65 to ptr
  store ptr %cv66, ptr %res_slot61
  br label %case_merge10
case_br13:
  %fp67 = getelementptr i8, ptr %ld60, i64 16
  %fv68 = load ptr, ptr %fp67, align 8
  %$f2022.addr = alloca ptr
  store ptr %fv68, ptr %$f2022.addr
  %fp69 = getelementptr i8, ptr %ld60, i64 24
  %fv70 = load ptr, ptr %fp69, align 8
  %$f2023.addr = alloca ptr
  store ptr %fv70, ptr %$f2023.addr
  %freed71 = call i64 @march_decrc_freed(ptr %ld60)
  %freed_b72 = icmp ne i64 %freed71, 0
  br i1 %freed_b72, label %br_unique14, label %br_shared15
br_shared15:
  call void @march_incrc(ptr %fv70)
  br label %br_body16
br_unique14:
  br label %br_body16
br_body16:
  %ld73 = load ptr, ptr %$f2023.addr
  %rest.addr = alloca ptr
  store ptr %ld73, ptr %rest.addr
  %ld74 = load ptr, ptr %$f2022.addr
  %x.addr = alloca ptr
  store ptr %ld74, ptr %x.addr
  %ld75 = load i64, ptr %acc.addr
  %ld76 = load ptr, ptr %x.addr
  %cv77 = ptrtoint ptr %ld76 to i64
  %ar78 = add i64 %ld75, %cv77
  %$t2021.addr = alloca i64
  store i64 %ar78, ptr %$t2021.addr
  %ld79 = load ptr, ptr %rest.addr
  %ld80 = load i64, ptr %$t2021.addr
  %cr81 = call i64 @sum(ptr %ld79, i64 %ld80)
  %cv82 = inttoptr i64 %cr81 to ptr
  store ptr %cv82, ptr %res_slot61
  br label %case_merge10
case_default11:
  unreachable
case_merge10:
  %case_r83 = load ptr, ptr %res_slot61
  %cv84 = ptrtoint ptr %case_r83 to i64
  ret i64 %cv84
}

define ptr @map_collatz(ptr %xs.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld85 = load ptr, ptr %xs.addr
  %res_slot86 = alloca ptr
  %tgp87 = getelementptr i8, ptr %ld85, i64 8
  %tag88 = load i32, ptr %tgp87, align 4
  switch i32 %tag88, label %case_default18 [
      i32 0, label %case_br19
      i32 1, label %case_br20
  ]
case_br19:
  %ld89 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld89)
  %ld90 = load ptr, ptr %acc.addr
  store ptr %ld90, ptr %res_slot86
  br label %case_merge17
case_br20:
  %fp91 = getelementptr i8, ptr %ld85, i64 16
  %fv92 = load ptr, ptr %fp91, align 8
  %$f2026.addr = alloca ptr
  store ptr %fv92, ptr %$f2026.addr
  %fp93 = getelementptr i8, ptr %ld85, i64 24
  %fv94 = load ptr, ptr %fp93, align 8
  %$f2027.addr = alloca ptr
  store ptr %fv94, ptr %$f2027.addr
  %freed95 = call i64 @march_decrc_freed(ptr %ld85)
  %freed_b96 = icmp ne i64 %freed95, 0
  br i1 %freed_b96, label %br_unique21, label %br_shared22
br_shared22:
  call void @march_incrc(ptr %fv94)
  br label %br_body23
br_unique21:
  br label %br_body23
br_body23:
  %ld97 = load ptr, ptr %$f2027.addr
  %rest.addr = alloca ptr
  store ptr %ld97, ptr %rest.addr
  %ld98 = load ptr, ptr %$f2026.addr
  %x.addr = alloca ptr
  store ptr %ld98, ptr %x.addr
  %ld99 = load ptr, ptr %x.addr
  %cr100 = call i64 @collatz_steps(ptr %ld99, i64 0)
  %$t2024.addr = alloca i64
  store i64 %cr100, ptr %$t2024.addr
  %hp101 = call ptr @march_alloc(i64 32)
  %tgp102 = getelementptr i8, ptr %hp101, i64 8
  store i32 1, ptr %tgp102, align 4
  %ld103 = load i64, ptr %$t2024.addr
  %cv104 = inttoptr i64 %ld103 to ptr
  %fp105 = getelementptr i8, ptr %hp101, i64 16
  store ptr %cv104, ptr %fp105, align 8
  %ld106 = load ptr, ptr %acc.addr
  %fp107 = getelementptr i8, ptr %hp101, i64 24
  store ptr %ld106, ptr %fp107, align 8
  %$t2025.addr = alloca ptr
  store ptr %hp101, ptr %$t2025.addr
  %ld108 = load ptr, ptr %rest.addr
  %ld109 = load ptr, ptr %$t2025.addr
  %cr110 = call ptr @map_collatz(ptr %ld108, ptr %ld109)
  store ptr %cr110, ptr %res_slot86
  br label %case_merge17
case_default18:
  unreachable
case_merge17:
  %case_r111 = load ptr, ptr %res_slot86
  ret ptr %case_r111
}

define i64 @par_map_inner(ptr %xs.arg, i64 %chunk_size.arg, ptr %chunk_acc.arg, i64 %chunk_left.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %chunk_size.addr = alloca i64
  store i64 %chunk_size.arg, ptr %chunk_size.addr
  %chunk_acc.addr = alloca ptr
  store ptr %chunk_acc.arg, ptr %chunk_acc.addr
  %chunk_left.addr = alloca i64
  store i64 %chunk_left.arg, ptr %chunk_left.addr
  %ld112 = load ptr, ptr %xs.addr
  %res_slot113 = alloca ptr
  %tgp114 = getelementptr i8, ptr %ld112, i64 8
  %tag115 = load i32, ptr %tgp114, align 4
  switch i32 %tag115, label %case_default25 [
      i32 0, label %case_br26
      i32 1, label %case_br27
  ]
case_br26:
  %ld116 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld116)
  %ld117 = load i64, ptr %chunk_left.addr
  %ld118 = load i64, ptr %chunk_size.addr
  %cmp119 = icmp eq i64 %ld117, %ld118
  %ar120 = zext i1 %cmp119 to i64
  %$t2028.addr = alloca i64
  store i64 %ar120, ptr %$t2028.addr
  %ld121 = load i64, ptr %$t2028.addr
  %res_slot122 = alloca ptr
  %bi123 = trunc i64 %ld121 to i1
  br i1 %bi123, label %case_br30, label %case_default29
case_br30:
  %cv124 = inttoptr i64 0 to ptr
  store ptr %cv124, ptr %res_slot122
  br label %case_merge28
case_default29:
  %hp125 = call ptr @march_alloc(i64 32)
  %tgp126 = getelementptr i8, ptr %hp125, i64 8
  store i32 0, ptr %tgp126, align 4
  %fp127 = getelementptr i8, ptr %hp125, i64 16
  store ptr @$lam2029$apply$21, ptr %fp127, align 8
  %ld128 = load ptr, ptr %chunk_acc.addr
  %fp129 = getelementptr i8, ptr %hp125, i64 24
  store ptr %ld128, ptr %fp129, align 8
  %$t2032.addr = alloca ptr
  store ptr %hp125, ptr %$t2032.addr
  %ld130 = load ptr, ptr %$t2032.addr
  %fp131 = getelementptr i8, ptr %ld130, i64 16
  %fv132 = load ptr, ptr %fp131, align 8
  %tsres133 = call i64 %fv132(ptr %ld130, i64 0)
  %hp134 = call ptr @march_alloc(i64 24)
  %tgp135 = getelementptr i8, ptr %hp134, i64 8
  store i32 0, ptr %tgp135, align 4
  %fp136 = getelementptr i8, ptr %hp134, i64 16
  store i64 %tsres133, ptr %fp136, align 8
  %t.addr = alloca ptr
  store ptr %hp134, ptr %t.addr
  %ld137 = load ptr, ptr %t.addr
  %fp138 = getelementptr i8, ptr %ld137, i64 16
  %fv139 = load i64, ptr %fp138, align 8
  %cv140 = inttoptr i64 %fv139 to ptr
  store ptr %cv140, ptr %res_slot122
  br label %case_merge28
case_merge28:
  %case_r141 = load ptr, ptr %res_slot122
  store ptr %case_r141, ptr %res_slot113
  br label %case_merge24
case_br27:
  %fp142 = getelementptr i8, ptr %ld112, i64 16
  %fv143 = load ptr, ptr %fp142, align 8
  %$f2043.addr = alloca ptr
  store ptr %fv143, ptr %$f2043.addr
  %fp144 = getelementptr i8, ptr %ld112, i64 24
  %fv145 = load ptr, ptr %fp144, align 8
  %$f2044.addr = alloca ptr
  store ptr %fv145, ptr %$f2044.addr
  %freed146 = call i64 @march_decrc_freed(ptr %ld112)
  %freed_b147 = icmp ne i64 %freed146, 0
  br i1 %freed_b147, label %br_unique31, label %br_shared32
br_shared32:
  call void @march_incrc(ptr %fv145)
  br label %br_body33
br_unique31:
  br label %br_body33
br_body33:
  %ld148 = load ptr, ptr %$f2044.addr
  %tl.addr = alloca ptr
  store ptr %ld148, ptr %tl.addr
  %ld149 = load ptr, ptr %$f2043.addr
  %h.addr = alloca ptr
  store ptr %ld149, ptr %h.addr
  %ld150 = load i64, ptr %chunk_left.addr
  %cmp151 = icmp eq i64 %ld150, 0
  %ar152 = zext i1 %cmp151 to i64
  %$t2033.addr = alloca i64
  store i64 %ar152, ptr %$t2033.addr
  %ld153 = load i64, ptr %$t2033.addr
  %res_slot154 = alloca ptr
  %bi155 = trunc i64 %ld153 to i1
  br i1 %bi155, label %case_br36, label %case_default35
case_br36:
  %hp156 = call ptr @march_alloc(i64 32)
  %tgp157 = getelementptr i8, ptr %hp156, i64 8
  store i32 0, ptr %tgp157, align 4
  %fp158 = getelementptr i8, ptr %hp156, i64 16
  store ptr @$lam2034$apply$22, ptr %fp158, align 8
  %ld159 = load ptr, ptr %chunk_acc.addr
  %fp160 = getelementptr i8, ptr %hp156, i64 24
  store ptr %ld159, ptr %fp160, align 8
  %$t2037.addr = alloca ptr
  store ptr %hp156, ptr %$t2037.addr
  %ld161 = load ptr, ptr %$t2037.addr
  %fp162 = getelementptr i8, ptr %ld161, i64 16
  %fv163 = load ptr, ptr %fp162, align 8
  %tsres164 = call i64 %fv163(ptr %ld161, i64 0)
  %hp165 = call ptr @march_alloc(i64 24)
  %tgp166 = getelementptr i8, ptr %hp165, i64 8
  store i32 0, ptr %tgp166, align 4
  %fp167 = getelementptr i8, ptr %hp165, i64 16
  store i64 %tsres164, ptr %fp167, align 8
  %t_1.addr = alloca ptr
  store ptr %hp165, ptr %t_1.addr
  %hp168 = call ptr @march_alloc(i64 16)
  %tgp169 = getelementptr i8, ptr %hp168, i64 8
  store i32 0, ptr %tgp169, align 4
  %$t2038.addr = alloca ptr
  store ptr %hp168, ptr %$t2038.addr
  %hp170 = call ptr @march_alloc(i64 32)
  %tgp171 = getelementptr i8, ptr %hp170, i64 8
  store i32 1, ptr %tgp171, align 4
  %ld172 = load ptr, ptr %h.addr
  %fp173 = getelementptr i8, ptr %hp170, i64 16
  store ptr %ld172, ptr %fp173, align 8
  %ld174 = load ptr, ptr %$t2038.addr
  %fp175 = getelementptr i8, ptr %hp170, i64 24
  store ptr %ld174, ptr %fp175, align 8
  %$t2039.addr = alloca ptr
  store ptr %hp170, ptr %$t2039.addr
  %ld176 = load i64, ptr %chunk_size.addr
  %ar177 = sub i64 %ld176, 1
  %$t2040.addr = alloca i64
  store i64 %ar177, ptr %$t2040.addr
  %ld178 = load ptr, ptr %tl.addr
  %ld179 = load i64, ptr %chunk_size.addr
  %ld180 = load ptr, ptr %$t2039.addr
  %ld181 = load i64, ptr %$t2040.addr
  %cr182 = call i64 @par_map_inner(ptr %ld178, i64 %ld179, ptr %ld180, i64 %ld181)
  %rest_sum.addr = alloca i64
  store i64 %cr182, ptr %rest_sum.addr
  %ld183 = load ptr, ptr %t_1.addr
  %fp184 = getelementptr i8, ptr %ld183, i64 16
  %fv185 = load i64, ptr %fp184, align 8
  %chunk_sum.addr = alloca i64
  store i64 %fv185, ptr %chunk_sum.addr
  %ld186 = load i64, ptr %chunk_sum.addr
  %ld187 = load i64, ptr %rest_sum.addr
  %ar188 = add i64 %ld186, %ld187
  %cv189 = inttoptr i64 %ar188 to ptr
  store ptr %cv189, ptr %res_slot154
  br label %case_merge34
case_default35:
  %hp190 = call ptr @march_alloc(i64 32)
  %tgp191 = getelementptr i8, ptr %hp190, i64 8
  store i32 1, ptr %tgp191, align 4
  %ld192 = load ptr, ptr %h.addr
  %fp193 = getelementptr i8, ptr %hp190, i64 16
  store ptr %ld192, ptr %fp193, align 8
  %ld194 = load ptr, ptr %chunk_acc.addr
  %fp195 = getelementptr i8, ptr %hp190, i64 24
  store ptr %ld194, ptr %fp195, align 8
  %$t2041.addr = alloca ptr
  store ptr %hp190, ptr %$t2041.addr
  %ld196 = load i64, ptr %chunk_left.addr
  %ar197 = sub i64 %ld196, 1
  %$t2042.addr = alloca i64
  store i64 %ar197, ptr %$t2042.addr
  %ld198 = load ptr, ptr %tl.addr
  %ld199 = load i64, ptr %chunk_size.addr
  %ld200 = load ptr, ptr %$t2041.addr
  %ld201 = load i64, ptr %$t2042.addr
  %cr202 = call i64 @par_map_inner(ptr %ld198, i64 %ld199, ptr %ld200, i64 %ld201)
  %cv203 = inttoptr i64 %cr202 to ptr
  store ptr %cv203, ptr %res_slot154
  br label %case_merge34
case_merge34:
  %case_r204 = load ptr, ptr %res_slot154
  store ptr %case_r204, ptr %res_slot113
  br label %case_merge24
case_default25:
  unreachable
case_merge24:
  %case_r205 = load ptr, ptr %res_slot113
  %cv206 = ptrtoint ptr %case_r205 to i64
  ret i64 %cv206
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 10000, ptr %n.addr
  %chunk_size.addr = alloca i64
  store i64 1000, ptr %chunk_size.addr
  %lo_i26.addr = alloca i64
  store i64 1, ptr %lo_i26.addr
  %ld207 = load i64, ptr %n.addr
  %hi_i27.addr = alloca i64
  store i64 %ld207, ptr %hi_i27.addr
  %hp208 = call ptr @march_alloc(i64 16)
  %tgp209 = getelementptr i8, ptr %hp208, i64 8
  store i32 0, ptr %tgp209, align 4
  %$t2020_i28.addr = alloca ptr
  store ptr %hp208, ptr %$t2020_i28.addr
  %ld210 = load i64, ptr %lo_i26.addr
  %ld211 = load i64, ptr %hi_i27.addr
  %ld212 = load ptr, ptr %$t2020_i28.addr
  %cr213 = call ptr @range_acc(i64 %ld210, i64 %ld211, ptr %ld212)
  %xs.addr = alloca ptr
  store ptr %cr213, ptr %xs.addr
  %ld214 = load ptr, ptr %xs.addr
  %xs_i23.addr = alloca ptr
  store ptr %ld214, ptr %xs_i23.addr
  %ld215 = load i64, ptr %chunk_size.addr
  %chunk_size_i24.addr = alloca i64
  store i64 %ld215, ptr %chunk_size_i24.addr
  %hp216 = call ptr @march_alloc(i64 16)
  %tgp217 = getelementptr i8, ptr %hp216, i64 8
  store i32 0, ptr %tgp217, align 4
  %$t2045_i25.addr = alloca ptr
  store ptr %hp216, ptr %$t2045_i25.addr
  %ld218 = load ptr, ptr %xs_i23.addr
  %ld219 = load i64, ptr %chunk_size_i24.addr
  %ld220 = load ptr, ptr %$t2045_i25.addr
  %ld221 = load i64, ptr %chunk_size_i24.addr
  %cr222 = call i64 @par_map_inner(ptr %ld218, i64 %ld219, ptr %ld220, i64 %ld221)
  %total.addr = alloca i64
  store i64 %cr222, ptr %total.addr
  %ld223 = load i64, ptr %total.addr
  %cr224 = call ptr @march_int_to_string(i64 %ld223)
  %$t2046.addr = alloca ptr
  store ptr %cr224, ptr %$t2046.addr
  %ld225 = load ptr, ptr %$t2046.addr
  call void @march_println(ptr %ld225)
  ret void
}

define i64 @$lam2029$apply$21(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld226 = load ptr, ptr %$clo.addr
  %fp227 = getelementptr i8, ptr %ld226, i64 24
  %fv228 = load ptr, ptr %fp227, align 8
  %chunk_acc.addr = alloca ptr
  store ptr %fv228, ptr %chunk_acc.addr
  %hp229 = call ptr @march_alloc(i64 16)
  %tgp230 = getelementptr i8, ptr %hp229, i64 8
  store i32 0, ptr %tgp230, align 4
  %$t2030.addr = alloca ptr
  store ptr %hp229, ptr %$t2030.addr
  %ld231 = load ptr, ptr %chunk_acc.addr
  %ld232 = load ptr, ptr %$t2030.addr
  %cr233 = call ptr @map_collatz(ptr %ld231, ptr %ld232)
  %$t2031.addr = alloca ptr
  store ptr %cr233, ptr %$t2031.addr
  %ld234 = load ptr, ptr %$t2031.addr
  %cr235 = call i64 @sum(ptr %ld234, i64 0)
  ret i64 %cr235
}

define i64 @$lam2034$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld236 = load ptr, ptr %$clo.addr
  %fp237 = getelementptr i8, ptr %ld236, i64 24
  %fv238 = load ptr, ptr %fp237, align 8
  %chunk_acc.addr = alloca ptr
  store ptr %fv238, ptr %chunk_acc.addr
  %hp239 = call ptr @march_alloc(i64 16)
  %tgp240 = getelementptr i8, ptr %hp239, i64 8
  store i32 0, ptr %tgp240, align 4
  %$t2035.addr = alloca ptr
  store ptr %hp239, ptr %$t2035.addr
  %ld241 = load ptr, ptr %chunk_acc.addr
  %ld242 = load ptr, ptr %$t2035.addr
  %cr243 = call ptr @map_collatz(ptr %ld241, ptr %ld242)
  %$t2036.addr = alloca ptr
  store ptr %cr243, ptr %$t2036.addr
  %ld244 = load ptr, ptr %$t2036.addr
  %cr245 = call i64 @sum(ptr %ld244, i64 0)
  ret i64 %cr245
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
