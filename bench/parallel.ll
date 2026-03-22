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
  store i64 1, ptr %fp9, align 8
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

define i64 @sum(ptr %t.arg) {
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
  %$f2016.addr = alloca i64
  store i64 %fv30, ptr %$f2016.addr
  %ld31 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld31)
  %ld32 = load i64, ptr %$f2016.addr
  %n.addr = alloca i64
  store i64 %ld32, ptr %n.addr
  %ld33 = load i64, ptr %n.addr
  %cv34 = inttoptr i64 %ld33 to ptr
  store ptr %cv34, ptr %res_slot26
  br label %case_merge4
case_br7:
  %fp35 = getelementptr i8, ptr %ld25, i64 16
  %fv36 = load ptr, ptr %fp35, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv36, ptr %$f2017.addr
  %fp37 = getelementptr i8, ptr %ld25, i64 24
  %fv38 = load ptr, ptr %fp37, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv38, ptr %$f2018.addr
  %freed39 = call i64 @march_decrc_freed(ptr %ld25)
  %freed_b40 = icmp ne i64 %freed39, 0
  br i1 %freed_b40, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv38)
  call void @march_incrc(ptr %fv36)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld41 = load ptr, ptr %$f2018.addr
  %r.addr = alloca ptr
  store ptr %ld41, ptr %r.addr
  %ld42 = load ptr, ptr %$f2017.addr
  %l.addr = alloca ptr
  store ptr %ld42, ptr %l.addr
  %ld43 = load ptr, ptr %l.addr
  %cr44 = call i64 @sum(ptr %ld43)
  %$t2014.addr = alloca i64
  store i64 %cr44, ptr %$t2014.addr
  %ld45 = load ptr, ptr %r.addr
  %cr46 = call i64 @sum(ptr %ld45)
  %$t2015.addr = alloca i64
  store i64 %cr46, ptr %$t2015.addr
  %ld47 = load i64, ptr %$t2014.addr
  %ld48 = load i64, ptr %$t2015.addr
  %ar49 = add i64 %ld47, %ld48
  %cv50 = inttoptr i64 %ar49 to ptr
  store ptr %cv50, ptr %res_slot26
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r51 = load ptr, ptr %res_slot26
  %cv52 = ptrtoint ptr %case_r51 to i64
  ret i64 %cv52
}

define i64 @par_sum(ptr %t.arg, i64 %depth.arg, i64 %threshold.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %depth.addr = alloca i64
  store i64 %depth.arg, ptr %depth.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld53 = load ptr, ptr %t.addr
  %res_slot54 = alloca ptr
  %tgp55 = getelementptr i8, ptr %ld53, i64 8
  %tag56 = load i32, ptr %tgp55, align 4
  switch i32 %tag56, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %fp57 = getelementptr i8, ptr %ld53, i64 16
  %fv58 = load i64, ptr %fp57, align 8
  %$f2028.addr = alloca i64
  store i64 %fv58, ptr %$f2028.addr
  %ld59 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld59)
  %ld60 = load i64, ptr %$f2028.addr
  %n.addr = alloca i64
  store i64 %ld60, ptr %n.addr
  %ld61 = load i64, ptr %n.addr
  %cv62 = inttoptr i64 %ld61 to ptr
  store ptr %cv62, ptr %res_slot54
  br label %case_merge11
case_br14:
  %fp63 = getelementptr i8, ptr %ld53, i64 16
  %fv64 = load ptr, ptr %fp63, align 8
  %$f2029.addr = alloca ptr
  store ptr %fv64, ptr %$f2029.addr
  %fp65 = getelementptr i8, ptr %ld53, i64 24
  %fv66 = load ptr, ptr %fp65, align 8
  %$f2030.addr = alloca ptr
  store ptr %fv66, ptr %$f2030.addr
  %freed67 = call i64 @march_decrc_freed(ptr %ld53)
  %freed_b68 = icmp ne i64 %freed67, 0
  br i1 %freed_b68, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv66)
  call void @march_incrc(ptr %fv64)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %ld69 = load ptr, ptr %$f2030.addr
  %r.addr = alloca ptr
  store ptr %ld69, ptr %r.addr
  %ld70 = load ptr, ptr %$f2029.addr
  %l.addr = alloca ptr
  store ptr %ld70, ptr %l.addr
  %ld71 = load i64, ptr %depth.addr
  %ld72 = load i64, ptr %threshold.addr
  %cmp73 = icmp sge i64 %ld71, %ld72
  %ar74 = zext i1 %cmp73 to i64
  %$t2019.addr = alloca i64
  store i64 %ar74, ptr %$t2019.addr
  %ld75 = load i64, ptr %$t2019.addr
  %res_slot76 = alloca ptr
  %bi77 = trunc i64 %ld75 to i1
  br i1 %bi77, label %case_br20, label %case_default19
case_br20:
  %ld78 = load ptr, ptr %l.addr
  %cr79 = call i64 @sum(ptr %ld78)
  %$t2020.addr = alloca i64
  store i64 %cr79, ptr %$t2020.addr
  %ld80 = load ptr, ptr %r.addr
  %cr81 = call i64 @sum(ptr %ld80)
  %$t2021.addr = alloca i64
  store i64 %cr81, ptr %$t2021.addr
  %ld82 = load i64, ptr %$t2020.addr
  %ld83 = load i64, ptr %$t2021.addr
  %ar84 = add i64 %ld82, %ld83
  %cv85 = inttoptr i64 %ar84 to ptr
  store ptr %cv85, ptr %res_slot76
  br label %case_merge18
case_default19:
  %hp86 = call ptr @march_alloc(i64 48)
  %tgp87 = getelementptr i8, ptr %hp86, i64 8
  store i32 0, ptr %tgp87, align 4
  %fp88 = getelementptr i8, ptr %hp86, i64 16
  store ptr @$lam2022$apply$21, ptr %fp88, align 8
  %ld89 = load i64, ptr %depth.addr
  %fp90 = getelementptr i8, ptr %hp86, i64 24
  store i64 %ld89, ptr %fp90, align 8
  %ld91 = load ptr, ptr %l.addr
  %fp92 = getelementptr i8, ptr %hp86, i64 32
  store ptr %ld91, ptr %fp92, align 8
  %ld93 = load i64, ptr %threshold.addr
  %fp94 = getelementptr i8, ptr %hp86, i64 40
  store i64 %ld93, ptr %fp94, align 8
  %$t2024.addr = alloca ptr
  store ptr %hp86, ptr %$t2024.addr
  %ld95 = load ptr, ptr %$t2024.addr
  %fp96 = getelementptr i8, ptr %ld95, i64 16
  %fv97 = load ptr, ptr %fp96, align 8
  %tsres98 = call i64 %fv97(ptr %ld95, i64 0)
  %hp99 = call ptr @march_alloc(i64 24)
  %tgp100 = getelementptr i8, ptr %hp99, i64 8
  store i32 0, ptr %tgp100, align 4
  %fp101 = getelementptr i8, ptr %hp99, i64 16
  store i64 %tsres98, ptr %fp101, align 8
  %tl.addr = alloca ptr
  store ptr %hp99, ptr %tl.addr
  %hp102 = call ptr @march_alloc(i64 48)
  %tgp103 = getelementptr i8, ptr %hp102, i64 8
  store i32 0, ptr %tgp103, align 4
  %fp104 = getelementptr i8, ptr %hp102, i64 16
  store ptr @$lam2025$apply$22, ptr %fp104, align 8
  %ld105 = load i64, ptr %depth.addr
  %fp106 = getelementptr i8, ptr %hp102, i64 24
  store i64 %ld105, ptr %fp106, align 8
  %ld107 = load ptr, ptr %r.addr
  %fp108 = getelementptr i8, ptr %hp102, i64 32
  store ptr %ld107, ptr %fp108, align 8
  %ld109 = load i64, ptr %threshold.addr
  %fp110 = getelementptr i8, ptr %hp102, i64 40
  store i64 %ld109, ptr %fp110, align 8
  %$t2027.addr = alloca ptr
  store ptr %hp102, ptr %$t2027.addr
  %ld111 = load ptr, ptr %$t2027.addr
  %fp112 = getelementptr i8, ptr %ld111, i64 16
  %fv113 = load ptr, ptr %fp112, align 8
  %tsres114 = call i64 %fv113(ptr %ld111, i64 0)
  %hp115 = call ptr @march_alloc(i64 24)
  %tgp116 = getelementptr i8, ptr %hp115, i64 8
  store i32 0, ptr %tgp116, align 4
  %fp117 = getelementptr i8, ptr %hp115, i64 16
  store i64 %tsres114, ptr %fp117, align 8
  %tr.addr = alloca ptr
  store ptr %hp115, ptr %tr.addr
  %ld118 = load ptr, ptr %tl.addr
  %fp119 = getelementptr i8, ptr %ld118, i64 16
  %fv120 = load i64, ptr %fp119, align 8
  %rl.addr = alloca i64
  store i64 %fv120, ptr %rl.addr
  %ld121 = load ptr, ptr %tr.addr
  %fp122 = getelementptr i8, ptr %ld121, i64 16
  %fv123 = load i64, ptr %fp122, align 8
  %rr.addr = alloca i64
  store i64 %fv123, ptr %rr.addr
  %ld124 = load i64, ptr %rl.addr
  %ld125 = load i64, ptr %rr.addr
  %ar126 = add i64 %ld124, %ld125
  %cv127 = inttoptr i64 %ar126 to ptr
  store ptr %cv127, ptr %res_slot76
  br label %case_merge18
case_merge18:
  %case_r128 = load ptr, ptr %res_slot76
  store ptr %case_r128, ptr %res_slot54
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r129 = load ptr, ptr %res_slot54
  %cv130 = ptrtoint ptr %case_r129 to i64
  ret i64 %cv130
}

define void @march_main() {
entry:
  %cr131 = call ptr @make(i64 24)
  %t.addr = alloca ptr
  store ptr %cr131, ptr %t.addr
  %ld132 = load ptr, ptr %t.addr
  %cr133 = call i64 @par_sum(ptr %ld132, i64 0, i64 10)
  %total.addr = alloca i64
  store i64 %cr133, ptr %total.addr
  %ld134 = load i64, ptr %total.addr
  %cr135 = call ptr @march_int_to_string(i64 %ld134)
  %$t2031.addr = alloca ptr
  store ptr %cr135, ptr %$t2031.addr
  %ld136 = load ptr, ptr %$t2031.addr
  call void @march_println(ptr %ld136)
  ret void
}

define i64 @$lam2022$apply$21(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld137 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld137)
  %ld138 = load ptr, ptr %$clo.addr
  %fp139 = getelementptr i8, ptr %ld138, i64 24
  %fv140 = load ptr, ptr %fp139, align 8
  %cv141 = ptrtoint ptr %fv140 to i64
  %depth.addr = alloca i64
  store i64 %cv141, ptr %depth.addr
  %ld142 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld142)
  %ld143 = load ptr, ptr %$clo.addr
  %fp144 = getelementptr i8, ptr %ld143, i64 32
  %fv145 = load ptr, ptr %fp144, align 8
  %l.addr = alloca ptr
  store ptr %fv145, ptr %l.addr
  %ld146 = load ptr, ptr %$clo.addr
  %fp147 = getelementptr i8, ptr %ld146, i64 40
  %fv148 = load i64, ptr %fp147, align 8
  %threshold.addr = alloca i64
  store i64 %fv148, ptr %threshold.addr
  %ld149 = load i64, ptr %depth.addr
  %ar150 = add i64 %ld149, 1
  %$t2023.addr = alloca i64
  store i64 %ar150, ptr %$t2023.addr
  %ld151 = load ptr, ptr %l.addr
  %ld152 = load i64, ptr %$t2023.addr
  %ld153 = load i64, ptr %threshold.addr
  %cr154 = call i64 @par_sum(ptr %ld151, i64 %ld152, i64 %ld153)
  ret i64 %cr154
}

define i64 @$lam2025$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld155 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld155)
  %ld156 = load ptr, ptr %$clo.addr
  %fp157 = getelementptr i8, ptr %ld156, i64 24
  %fv158 = load ptr, ptr %fp157, align 8
  %cv159 = ptrtoint ptr %fv158 to i64
  %depth.addr = alloca i64
  store i64 %cv159, ptr %depth.addr
  %ld160 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld160)
  %ld161 = load ptr, ptr %$clo.addr
  %fp162 = getelementptr i8, ptr %ld161, i64 32
  %fv163 = load ptr, ptr %fp162, align 8
  %r.addr = alloca ptr
  store ptr %fv163, ptr %r.addr
  %ld164 = load ptr, ptr %$clo.addr
  %fp165 = getelementptr i8, ptr %ld164, i64 40
  %fv166 = load i64, ptr %fp165, align 8
  %threshold.addr = alloca i64
  store i64 %fv166, ptr %threshold.addr
  %ld167 = load i64, ptr %depth.addr
  %ar168 = add i64 %ld167, 1
  %$t2026.addr = alloca i64
  store i64 %ar168, ptr %$t2026.addr
  %ld169 = load ptr, ptr %r.addr
  %ld170 = load i64, ptr %$t2026.addr
  %ld171 = load i64, ptr %threshold.addr
  %cr172 = call i64 @par_sum(ptr %ld169, i64 %ld170, i64 %ld171)
  ret i64 %cr172
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
