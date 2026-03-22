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


define ptr @make(i64 %d.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld1 = load i64, ptr %d.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %hp7 = call ptr @march_alloc(i64 24)
  %tgp8 = getelementptr i8, ptr %hp7, i64 8
  store i32 0, ptr %tgp8, align 4
  %fp9 = getelementptr i8, ptr %hp7, i64 16
  store i64 0, ptr %fp9, align 8
  store ptr %hp7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld10 = load i64, ptr %d.addr
  %ar11 = sub i64 %ld10, 1
  %$t2010.addr = alloca i64
  store i64 %ar11, ptr %$t2010.addr
  %ld12 = load i64, ptr %$t2010.addr
  %cr13 = call ptr @make(i64 %ld12)
  %$t2011.addr = alloca ptr
  store ptr %cr13, ptr %$t2011.addr
  %ld14 = load i64, ptr %d.addr
  %ar15 = sub i64 %ld14, 1
  %$t2012.addr = alloca i64
  store i64 %ar15, ptr %$t2012.addr
  %ld16 = load i64, ptr %$t2012.addr
  %cr17 = call ptr @make(i64 %ld16)
  %$t2013.addr = alloca ptr
  store ptr %cr17, ptr %$t2013.addr
  %hp18 = call ptr @march_alloc(i64 32)
  %tgp19 = getelementptr i8, ptr %hp18, i64 8
  store i32 1, ptr %tgp19, align 4
  %ld20 = load ptr, ptr %$t2011.addr
  %fp21 = getelementptr i8, ptr %hp18, i64 16
  store ptr %ld20, ptr %fp21, align 8
  %ld22 = load ptr, ptr %$t2013.addr
  %fp23 = getelementptr i8, ptr %hp18, i64 24
  store ptr %ld22, ptr %fp23, align 8
  store ptr %hp18, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r24 = load ptr, ptr %res_slot5
  ret ptr %case_r24
}

define ptr @inc_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld25 = load ptr, ptr %t.addr
  %res_slot26 = alloca ptr
  %tgp27 = getelementptr i8, ptr %ld25, i64 8
  %tag28 = load i32, ptr %tgp27, align 4
  switch i32 %tag28, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %fp29 = getelementptr i8, ptr %ld25, i64 16
  %fv30 = load i64, ptr %fp29, align 8
  %$f2017.addr = alloca i64
  store i64 %fv30, ptr %$f2017.addr
  %ld31 = load i64, ptr %$f2017.addr
  %n.addr = alloca i64
  store i64 %ld31, ptr %n.addr
  %ld32 = load i64, ptr %n.addr
  %ar33 = add i64 %ld32, 1
  %$t2014.addr = alloca i64
  store i64 %ar33, ptr %$t2014.addr
  %ld34 = load ptr, ptr %t.addr
  %ld35 = load i64, ptr %$t2014.addr
  %rc36 = load i64, ptr %ld34, align 8
  %uniq37 = icmp eq i64 %rc36, 1
  %fbip_slot38 = alloca ptr
  br i1 %uniq37, label %fbip_reuse8, label %fbip_fresh9
fbip_reuse8:
  %tgp39 = getelementptr i8, ptr %ld34, i64 8
  store i32 0, ptr %tgp39, align 4
  %fp40 = getelementptr i8, ptr %ld34, i64 16
  store i64 %ld35, ptr %fp40, align 8
  store ptr %ld34, ptr %fbip_slot38
  br label %fbip_merge10
fbip_fresh9:
  call void @march_decrc(ptr %ld34)
  %hp41 = call ptr @march_alloc(i64 24)
  %tgp42 = getelementptr i8, ptr %hp41, i64 8
  store i32 0, ptr %tgp42, align 4
  %fp43 = getelementptr i8, ptr %hp41, i64 16
  store i64 %ld35, ptr %fp43, align 8
  store ptr %hp41, ptr %fbip_slot38
  br label %fbip_merge10
fbip_merge10:
  %fbip_r44 = load ptr, ptr %fbip_slot38
  store ptr %fbip_r44, ptr %res_slot26
  br label %case_merge4
case_br7:
  %fp45 = getelementptr i8, ptr %ld25, i64 16
  %fv46 = load ptr, ptr %fp45, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv46, ptr %$f2018.addr
  %fp47 = getelementptr i8, ptr %ld25, i64 24
  %fv48 = load ptr, ptr %fp47, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv48, ptr %$f2019.addr
  %ld49 = load ptr, ptr %$f2019.addr
  %r.addr = alloca ptr
  store ptr %ld49, ptr %r.addr
  %ld50 = load ptr, ptr %$f2018.addr
  %l.addr = alloca ptr
  store ptr %ld50, ptr %l.addr
  %ld51 = load ptr, ptr %l.addr
  %cr52 = call ptr @inc_leaves(ptr %ld51)
  %$t2015.addr = alloca ptr
  store ptr %cr52, ptr %$t2015.addr
  %ld53 = load ptr, ptr %r.addr
  %cr54 = call ptr @inc_leaves(ptr %ld53)
  %$t2016.addr = alloca ptr
  store ptr %cr54, ptr %$t2016.addr
  %ld55 = load ptr, ptr %t.addr
  %ld56 = load ptr, ptr %$t2015.addr
  %ld57 = load ptr, ptr %$t2016.addr
  %rc58 = load i64, ptr %ld55, align 8
  %uniq59 = icmp eq i64 %rc58, 1
  %fbip_slot60 = alloca ptr
  br i1 %uniq59, label %fbip_reuse11, label %fbip_fresh12
fbip_reuse11:
  %tgp61 = getelementptr i8, ptr %ld55, i64 8
  store i32 1, ptr %tgp61, align 4
  %fp62 = getelementptr i8, ptr %ld55, i64 16
  store ptr %ld56, ptr %fp62, align 8
  %fp63 = getelementptr i8, ptr %ld55, i64 24
  store ptr %ld57, ptr %fp63, align 8
  store ptr %ld55, ptr %fbip_slot60
  br label %fbip_merge13
fbip_fresh12:
  call void @march_decrc(ptr %ld55)
  %hp64 = call ptr @march_alloc(i64 32)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 1, ptr %tgp65, align 4
  %fp66 = getelementptr i8, ptr %hp64, i64 16
  store ptr %ld56, ptr %fp66, align 8
  %fp67 = getelementptr i8, ptr %hp64, i64 24
  store ptr %ld57, ptr %fp67, align 8
  store ptr %hp64, ptr %fbip_slot60
  br label %fbip_merge13
fbip_merge13:
  %fbip_r68 = load ptr, ptr %fbip_slot60
  store ptr %fbip_r68, ptr %res_slot26
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r69 = load ptr, ptr %res_slot26
  ret ptr %case_r69
}

define i64 @sum_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld70 = load ptr, ptr %t.addr
  %res_slot71 = alloca ptr
  %tgp72 = getelementptr i8, ptr %ld70, i64 8
  %tag73 = load i32, ptr %tgp72, align 4
  switch i32 %tag73, label %case_default15 [
      i32 0, label %case_br16
      i32 1, label %case_br17
  ]
case_br16:
  %fp74 = getelementptr i8, ptr %ld70, i64 16
  %fv75 = load i64, ptr %fp74, align 8
  %$f2022.addr = alloca i64
  store i64 %fv75, ptr %$f2022.addr
  %ld76 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld76)
  %ld77 = load i64, ptr %$f2022.addr
  %n.addr = alloca i64
  store i64 %ld77, ptr %n.addr
  %ld78 = load i64, ptr %n.addr
  %cv79 = inttoptr i64 %ld78 to ptr
  store ptr %cv79, ptr %res_slot71
  br label %case_merge14
case_br17:
  %fp80 = getelementptr i8, ptr %ld70, i64 16
  %fv81 = load ptr, ptr %fp80, align 8
  %$f2023.addr = alloca ptr
  store ptr %fv81, ptr %$f2023.addr
  %fp82 = getelementptr i8, ptr %ld70, i64 24
  %fv83 = load ptr, ptr %fp82, align 8
  %$f2024.addr = alloca ptr
  store ptr %fv83, ptr %$f2024.addr
  %freed84 = call i64 @march_decrc_freed(ptr %ld70)
  %freed_b85 = icmp ne i64 %freed84, 0
  br i1 %freed_b85, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv83)
  call void @march_incrc(ptr %fv81)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld86 = load ptr, ptr %$f2024.addr
  %r.addr = alloca ptr
  store ptr %ld86, ptr %r.addr
  %ld87 = load ptr, ptr %$f2023.addr
  %l.addr = alloca ptr
  store ptr %ld87, ptr %l.addr
  %ld88 = load ptr, ptr %l.addr
  %cr89 = call i64 @sum_leaves(ptr %ld88)
  %$t2020.addr = alloca i64
  store i64 %cr89, ptr %$t2020.addr
  %ld90 = load ptr, ptr %r.addr
  %cr91 = call i64 @sum_leaves(ptr %ld90)
  %$t2021.addr = alloca i64
  store i64 %cr91, ptr %$t2021.addr
  %ld92 = load i64, ptr %$t2020.addr
  %ld93 = load i64, ptr %$t2021.addr
  %ar94 = add i64 %ld92, %ld93
  %cv95 = inttoptr i64 %ar94 to ptr
  store ptr %cv95, ptr %res_slot71
  br label %case_merge14
case_default15:
  unreachable
case_merge14:
  %case_r96 = load ptr, ptr %res_slot71
  %cv97 = ptrtoint ptr %case_r96 to i64
  ret i64 %cv97
}

define ptr @repeat(ptr %t.arg, i64 %n.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld98 = load i64, ptr %n.addr
  %cmp99 = icmp eq i64 %ld98, 0
  %ar100 = zext i1 %cmp99 to i64
  %$t2025.addr = alloca i64
  store i64 %ar100, ptr %$t2025.addr
  %ld101 = load i64, ptr %$t2025.addr
  %res_slot102 = alloca ptr
  %bi103 = trunc i64 %ld101 to i1
  br i1 %bi103, label %case_br23, label %case_default22
case_br23:
  %ld104 = load ptr, ptr %t.addr
  store ptr %ld104, ptr %res_slot102
  br label %case_merge21
case_default22:
  %ld105 = load ptr, ptr %t.addr
  %cr106 = call ptr @inc_leaves(ptr %ld105)
  %$t2026.addr = alloca ptr
  store ptr %cr106, ptr %$t2026.addr
  %ld107 = load i64, ptr %n.addr
  %ar108 = sub i64 %ld107, 1
  %$t2027.addr = alloca i64
  store i64 %ar108, ptr %$t2027.addr
  %ld109 = load ptr, ptr %$t2026.addr
  %ld110 = load i64, ptr %$t2027.addr
  %cr111 = call ptr @repeat(ptr %ld109, i64 %ld110)
  store ptr %cr111, ptr %res_slot102
  br label %case_merge21
case_merge21:
  %case_r112 = load ptr, ptr %res_slot102
  ret ptr %case_r112
}

define void @march_main() {
entry:
  %depth.addr = alloca i64
  store i64 20, ptr %depth.addr
  %passes.addr = alloca i64
  store i64 100, ptr %passes.addr
  %ld113 = load i64, ptr %depth.addr
  %cr114 = call ptr @make(i64 %ld113)
  %t.addr = alloca ptr
  store ptr %cr114, ptr %t.addr
  %ld115 = load ptr, ptr %t.addr
  %ld116 = load i64, ptr %passes.addr
  %cr117 = call ptr @repeat(ptr %ld115, i64 %ld116)
  %t2.addr = alloca ptr
  store ptr %cr117, ptr %t2.addr
  %ld118 = load ptr, ptr %t2.addr
  %cr119 = call i64 @sum_leaves(ptr %ld118)
  %$t2028.addr = alloca i64
  store i64 %cr119, ptr %$t2028.addr
  %ld120 = load i64, ptr %$t2028.addr
  %cr121 = call ptr @march_int_to_string(i64 %ld120)
  %$t2029.addr = alloca ptr
  store ptr %cr121, ptr %$t2029.addr
  %ld122 = load ptr, ptr %$t2029.addr
  call void @march_println(ptr %ld122)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
