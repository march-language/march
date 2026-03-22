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


define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t2009.addr = alloca i64
  store i64 %ar3, ptr %$t2009.addr
  %ld4 = load i64, ptr %$t2009.addr
  %res_slot5 = alloca ptr
  %bi6 = trunc i64 %ld4 to i1
  br i1 %bi6, label %case_br3, label %case_default2
case_br3:
  %ld7 = load ptr, ptr %acc.addr
  store ptr %ld7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %seed.addr
  %ar9 = mul i64 %ld8, 1664525
  %$t2010.addr = alloca i64
  store i64 %ar9, ptr %$t2010.addr
  %ld10 = load i64, ptr %$t2010.addr
  %ar11 = add i64 %ld10, 1013904223
  %$t2011.addr = alloca i64
  store i64 %ar11, ptr %$t2011.addr
  %ld12 = load i64, ptr %$t2011.addr
  %ar13 = srem i64 %ld12, 1000000
  %next.addr = alloca i64
  store i64 %ar13, ptr %next.addr
  %ld14 = load i64, ptr %n.addr
  %ar15 = sub i64 %ld14, 1
  %$t2012.addr = alloca i64
  store i64 %ar15, ptr %$t2012.addr
  %ld16 = load i64, ptr %next.addr
  %ar17 = srem i64 %ld16, 100000
  %$t2013.addr = alloca i64
  store i64 %ar17, ptr %$t2013.addr
  %hp18 = call ptr @march_alloc(i64 32)
  %tgp19 = getelementptr i8, ptr %hp18, i64 8
  store i32 1, ptr %tgp19, align 4
  %ld20 = load i64, ptr %$t2013.addr
  %cv21 = inttoptr i64 %ld20 to ptr
  %fp22 = getelementptr i8, ptr %hp18, i64 16
  store ptr %cv21, ptr %fp22, align 8
  %ld23 = load ptr, ptr %acc.addr
  %fp24 = getelementptr i8, ptr %hp18, i64 24
  store ptr %ld23, ptr %fp24, align 8
  %$t2014.addr = alloca ptr
  store ptr %hp18, ptr %$t2014.addr
  %ld25 = load i64, ptr %$t2012.addr
  %ld26 = load i64, ptr %next.addr
  %ld27 = load ptr, ptr %$t2014.addr
  %cr28 = call ptr @gen_list(i64 %ld25, i64 %ld26, ptr %ld27)
  store ptr %cr28, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r29 = load ptr, ptr %res_slot5
  ret ptr %case_r29
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld30 = load ptr, ptr %xs.addr
  %res_slot31 = alloca ptr
  %tgp32 = getelementptr i8, ptr %ld30, i64 8
  %tag33 = load i32, ptr %tgp32, align 4
  switch i32 %tag33, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld34 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld34)
  %cv35 = inttoptr i64 0 to ptr
  store ptr %cv35, ptr %res_slot31
  br label %case_merge4
case_br7:
  %fp36 = getelementptr i8, ptr %ld30, i64 16
  %fv37 = load ptr, ptr %fp36, align 8
  %$f2015.addr = alloca ptr
  store ptr %fv37, ptr %$f2015.addr
  %fp38 = getelementptr i8, ptr %ld30, i64 24
  %fv39 = load ptr, ptr %fp38, align 8
  %$f2016.addr = alloca ptr
  store ptr %fv39, ptr %$f2016.addr
  %freed40 = call i64 @march_decrc_freed(ptr %ld30)
  %freed_b41 = icmp ne i64 %freed40, 0
  br i1 %freed_b41, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv39)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld42 = load ptr, ptr %$f2015.addr
  %h.addr = alloca ptr
  store ptr %ld42, ptr %h.addr
  %ld43 = load ptr, ptr %h.addr
  store ptr %ld43, ptr %res_slot31
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r44 = load ptr, ptr %res_slot31
  %cv45 = ptrtoint ptr %case_r44 to i64
  ret i64 %cv45
}

define void @march_main() {
entry:
  %hp46 = call ptr @march_alloc(i64 16)
  %tgp47 = getelementptr i8, ptr %hp46, i64 8
  store i32 0, ptr %tgp47, align 4
  %$t2017.addr = alloca ptr
  store ptr %hp46, ptr %$t2017.addr
  %ld48 = load ptr, ptr %$t2017.addr
  %cr49 = call ptr @gen_list(i64 2000, i64 42, ptr %ld48)
  %xs.addr = alloca ptr
  store ptr %cr49, ptr %xs.addr
  %hp50 = call ptr @march_alloc(i64 24)
  %tgp51 = getelementptr i8, ptr %hp50, i64 8
  store i32 0, ptr %tgp51, align 4
  %fp52 = getelementptr i8, ptr %hp50, i64 16
  store ptr @$lam2018$apply$21, ptr %fp52, align 8
  %cmp.addr = alloca ptr
  store ptr %hp50, ptr %cmp.addr
  %ld53 = load ptr, ptr %xs.addr
  %ld54 = load ptr, ptr %cmp.addr
  %cr55 = call ptr @Sort.insertion_sort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %ld53, ptr %ld54)
  %sorted.addr = alloca ptr
  store ptr %cr55, ptr %sorted.addr
  %ld56 = load ptr, ptr %sorted.addr
  %cr57 = call i64 @head(ptr %ld56)
  %$t2020.addr = alloca i64
  store i64 %cr57, ptr %$t2020.addr
  %ld58 = load i64, ptr %$t2020.addr
  %cr59 = call ptr @march_int_to_string(i64 %ld58)
  %$t2021.addr = alloca ptr
  store ptr %cr59, ptr %$t2021.addr
  %ld60 = load ptr, ptr %$t2021.addr
  call void @march_println(ptr %ld60)
  ret void
}

define ptr @Sort.insertion_sort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp61 = call ptr @march_alloc(i64 32)
  %tgp62 = getelementptr i8, ptr %hp61, i64 8
  store i32 0, ptr %tgp62, align 4
  %fp63 = getelementptr i8, ptr %hp61, i64 16
  store ptr @go$apply$25, ptr %fp63, align 8
  %ld64 = load ptr, ptr %cmp.addr
  %fp65 = getelementptr i8, ptr %hp61, i64 24
  store ptr %ld64, ptr %fp65, align 8
  %go.addr = alloca ptr
  store ptr %hp61, ptr %go.addr
  %hp66 = call ptr @march_alloc(i64 16)
  %tgp67 = getelementptr i8, ptr %hp66, i64 8
  store i32 0, ptr %tgp67, align 4
  %$t1555.addr = alloca ptr
  store ptr %hp66, ptr %$t1555.addr
  %ld68 = load ptr, ptr %go.addr
  %fp69 = getelementptr i8, ptr %ld68, i64 16
  %fv70 = load ptr, ptr %fp69, align 8
  %ld71 = load ptr, ptr %xs.addr
  %ld72 = load ptr, ptr %$t1555.addr
  %cr73 = call ptr (ptr, ptr, ptr) %fv70(ptr %ld68, ptr %ld71, ptr %ld72)
  ret ptr %cr73
}

define ptr @Sort.insert_sorted$V__4903$List_V__4903$Fn_V__4903_Fn_V__4903_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld74 = load ptr, ptr %sorted.addr
  %res_slot75 = alloca ptr
  %tgp76 = getelementptr i8, ptr %ld74, i64 8
  %tag77 = load i32, ptr %tgp76, align 4
  switch i32 %tag77, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld78 = load ptr, ptr %sorted.addr
  %rc79 = load i64, ptr %ld78, align 8
  %uniq80 = icmp eq i64 %rc79, 1
  %fbip_slot81 = alloca ptr
  br i1 %uniq80, label %fbip_reuse15, label %fbip_fresh16
fbip_reuse15:
  %tgp82 = getelementptr i8, ptr %ld78, i64 8
  store i32 0, ptr %tgp82, align 4
  store ptr %ld78, ptr %fbip_slot81
  br label %fbip_merge17
fbip_fresh16:
  call void @march_decrc(ptr %ld78)
  %hp83 = call ptr @march_alloc(i64 16)
  %tgp84 = getelementptr i8, ptr %hp83, i64 8
  store i32 0, ptr %tgp84, align 4
  store ptr %hp83, ptr %fbip_slot81
  br label %fbip_merge17
fbip_merge17:
  %fbip_r85 = load ptr, ptr %fbip_slot81
  %$t1547.addr = alloca ptr
  store ptr %fbip_r85, ptr %$t1547.addr
  %hp86 = call ptr @march_alloc(i64 32)
  %tgp87 = getelementptr i8, ptr %hp86, i64 8
  store i32 1, ptr %tgp87, align 4
  %ld88 = load ptr, ptr %x.addr
  %fp89 = getelementptr i8, ptr %hp86, i64 16
  store ptr %ld88, ptr %fp89, align 8
  %ld90 = load ptr, ptr %$t1547.addr
  %fp91 = getelementptr i8, ptr %hp86, i64 24
  store ptr %ld90, ptr %fp91, align 8
  store ptr %hp86, ptr %res_slot75
  br label %case_merge11
case_br14:
  %fp92 = getelementptr i8, ptr %ld74, i64 16
  %fv93 = load ptr, ptr %fp92, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv93, ptr %$f1550.addr
  %fp94 = getelementptr i8, ptr %ld74, i64 24
  %fv95 = load ptr, ptr %fp94, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv95, ptr %$f1551.addr
  %ld96 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld96, ptr %t.addr
  %ld97 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld97, ptr %h.addr
  %ld98 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld98)
  %ld99 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld99)
  %ld100 = load ptr, ptr %cmp.addr
  %ld101 = load ptr, ptr %x.addr
  %ld102 = load ptr, ptr %h.addr
  %cr103 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld100, ptr %ld101, ptr %ld102)
  %$t1548.addr = alloca i64
  store i64 %cr103, ptr %$t1548.addr
  %ld104 = load i64, ptr %$t1548.addr
  %res_slot105 = alloca ptr
  %bi106 = trunc i64 %ld104 to i1
  br i1 %bi106, label %case_br20, label %case_default19
case_br20:
  %hp107 = call ptr @march_alloc(i64 32)
  %tgp108 = getelementptr i8, ptr %hp107, i64 8
  store i32 1, ptr %tgp108, align 4
  %ld109 = load ptr, ptr %x.addr
  %fp110 = getelementptr i8, ptr %hp107, i64 16
  store ptr %ld109, ptr %fp110, align 8
  %ld111 = load ptr, ptr %sorted.addr
  %fp112 = getelementptr i8, ptr %hp107, i64 24
  store ptr %ld111, ptr %fp112, align 8
  store ptr %hp107, ptr %res_slot105
  br label %case_merge18
case_default19:
  %ld113 = load ptr, ptr %x.addr
  %ld114 = load ptr, ptr %t.addr
  %ld115 = load ptr, ptr %cmp.addr
  %cr116 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld113, ptr %ld114, ptr %ld115)
  %$t1549.addr = alloca ptr
  store ptr %cr116, ptr %$t1549.addr
  %hp117 = call ptr @march_alloc(i64 32)
  %tgp118 = getelementptr i8, ptr %hp117, i64 8
  store i32 1, ptr %tgp118, align 4
  %ld119 = load ptr, ptr %h.addr
  %fp120 = getelementptr i8, ptr %hp117, i64 16
  store ptr %ld119, ptr %fp120, align 8
  %ld121 = load ptr, ptr %$t1549.addr
  %fp122 = getelementptr i8, ptr %hp117, i64 24
  store ptr %ld121, ptr %fp122, align 8
  store ptr %hp117, ptr %res_slot105
  br label %case_merge18
case_merge18:
  %case_r123 = load ptr, ptr %res_slot105
  store ptr %case_r123, ptr %res_slot75
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r124 = load ptr, ptr %res_slot75
  ret ptr %case_r124
}

define ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld125 = load ptr, ptr %sorted.addr
  %res_slot126 = alloca ptr
  %tgp127 = getelementptr i8, ptr %ld125, i64 8
  %tag128 = load i32, ptr %tgp127, align 4
  switch i32 %tag128, label %case_default22 [
      i32 0, label %case_br23
      i32 1, label %case_br24
  ]
case_br23:
  %ld129 = load ptr, ptr %sorted.addr
  %rc130 = load i64, ptr %ld129, align 8
  %uniq131 = icmp eq i64 %rc130, 1
  %fbip_slot132 = alloca ptr
  br i1 %uniq131, label %fbip_reuse25, label %fbip_fresh26
fbip_reuse25:
  %tgp133 = getelementptr i8, ptr %ld129, i64 8
  store i32 0, ptr %tgp133, align 4
  store ptr %ld129, ptr %fbip_slot132
  br label %fbip_merge27
fbip_fresh26:
  call void @march_decrc(ptr %ld129)
  %hp134 = call ptr @march_alloc(i64 16)
  %tgp135 = getelementptr i8, ptr %hp134, i64 8
  store i32 0, ptr %tgp135, align 4
  store ptr %hp134, ptr %fbip_slot132
  br label %fbip_merge27
fbip_merge27:
  %fbip_r136 = load ptr, ptr %fbip_slot132
  %$t1547.addr = alloca ptr
  store ptr %fbip_r136, ptr %$t1547.addr
  %hp137 = call ptr @march_alloc(i64 32)
  %tgp138 = getelementptr i8, ptr %hp137, i64 8
  store i32 1, ptr %tgp138, align 4
  %ld139 = load ptr, ptr %x.addr
  %fp140 = getelementptr i8, ptr %hp137, i64 16
  store ptr %ld139, ptr %fp140, align 8
  %ld141 = load ptr, ptr %$t1547.addr
  %fp142 = getelementptr i8, ptr %hp137, i64 24
  store ptr %ld141, ptr %fp142, align 8
  store ptr %hp137, ptr %res_slot126
  br label %case_merge21
case_br24:
  %fp143 = getelementptr i8, ptr %ld125, i64 16
  %fv144 = load ptr, ptr %fp143, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv144, ptr %$f1550.addr
  %fp145 = getelementptr i8, ptr %ld125, i64 24
  %fv146 = load ptr, ptr %fp145, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv146, ptr %$f1551.addr
  %ld147 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld147, ptr %t.addr
  %ld148 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld148, ptr %h.addr
  %ld149 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld149)
  %ld150 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld150)
  %ld151 = load ptr, ptr %cmp.addr
  %ld152 = load ptr, ptr %x.addr
  %ld153 = load ptr, ptr %h.addr
  %cr154 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld151, ptr %ld152, ptr %ld153)
  %$t1548.addr = alloca i64
  store i64 %cr154, ptr %$t1548.addr
  %ld155 = load i64, ptr %$t1548.addr
  %res_slot156 = alloca ptr
  %bi157 = trunc i64 %ld155 to i1
  br i1 %bi157, label %case_br30, label %case_default29
case_br30:
  %hp158 = call ptr @march_alloc(i64 32)
  %tgp159 = getelementptr i8, ptr %hp158, i64 8
  store i32 1, ptr %tgp159, align 4
  %ld160 = load ptr, ptr %x.addr
  %fp161 = getelementptr i8, ptr %hp158, i64 16
  store ptr %ld160, ptr %fp161, align 8
  %ld162 = load ptr, ptr %sorted.addr
  %fp163 = getelementptr i8, ptr %hp158, i64 24
  store ptr %ld162, ptr %fp163, align 8
  store ptr %hp158, ptr %res_slot156
  br label %case_merge28
case_default29:
  %ld164 = load ptr, ptr %x.addr
  %ld165 = load ptr, ptr %t.addr
  %ld166 = load ptr, ptr %cmp.addr
  %cr167 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld164, ptr %ld165, ptr %ld166)
  %$t1549.addr = alloca ptr
  store ptr %cr167, ptr %$t1549.addr
  %hp168 = call ptr @march_alloc(i64 32)
  %tgp169 = getelementptr i8, ptr %hp168, i64 8
  store i32 1, ptr %tgp169, align 4
  %ld170 = load ptr, ptr %h.addr
  %fp171 = getelementptr i8, ptr %hp168, i64 16
  store ptr %ld170, ptr %fp171, align 8
  %ld172 = load ptr, ptr %$t1549.addr
  %fp173 = getelementptr i8, ptr %hp168, i64 24
  store ptr %ld172, ptr %fp173, align 8
  store ptr %hp168, ptr %res_slot156
  br label %case_merge28
case_merge28:
  %case_r174 = load ptr, ptr %res_slot156
  store ptr %case_r174, ptr %res_slot126
  br label %case_merge21
case_default22:
  unreachable
case_merge21:
  %case_r175 = load ptr, ptr %res_slot126
  ret ptr %case_r175
}

define i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld176 = load ptr, ptr %cmp.addr
  %fp177 = getelementptr i8, ptr %ld176, i64 16
  %fv178 = load ptr, ptr %fp177, align 8
  %ld179 = load ptr, ptr %x.addr
  %cr180 = call ptr (ptr, ptr) %fv178(ptr %ld176, ptr %ld179)
  %f.addr = alloca ptr
  store ptr %cr180, ptr %f.addr
  %ld181 = load ptr, ptr %f.addr
  %fp182 = getelementptr i8, ptr %ld181, i64 16
  %fv183 = load ptr, ptr %fp182, align 8
  %ld184 = load ptr, ptr %y.addr
  %cr185 = call i64 (ptr, ptr) %fv183(ptr %ld181, ptr %ld184)
  ret i64 %cr185
}

define ptr @$lam2018$apply$21(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp186 = call ptr @march_alloc(i64 32)
  %tgp187 = getelementptr i8, ptr %hp186, i64 8
  store i32 0, ptr %tgp187, align 4
  %fp188 = getelementptr i8, ptr %hp186, i64 16
  store ptr @$lam2019$apply$22, ptr %fp188, align 8
  %ld189 = load ptr, ptr %x.addr
  %fp190 = getelementptr i8, ptr %hp186, i64 24
  store ptr %ld189, ptr %fp190, align 8
  ret ptr %hp186
}

define i64 @$lam2019$apply$22(ptr %$clo.arg, ptr %y.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld191 = load ptr, ptr %$clo.addr
  %fp192 = getelementptr i8, ptr %ld191, i64 24
  %fv193 = load ptr, ptr %fp192, align 8
  %x.addr = alloca ptr
  store ptr %fv193, ptr %x.addr
  %ld194 = load ptr, ptr %x.addr
  %ld195 = load ptr, ptr %y.addr
  %cv198 = ptrtoint ptr %ld194 to i64
  %cv199 = ptrtoint ptr %ld195 to i64
  %cmp196 = icmp sle i64 %cv198, %cv199
  %ar197 = zext i1 %cmp196 to i64
  ret i64 %ar197
}

define ptr @go$apply$25(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld200 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld200)
  %ld201 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld201, ptr %go.addr
  %ld202 = load ptr, ptr %$clo.addr
  %fp203 = getelementptr i8, ptr %ld202, i64 24
  %fv204 = load ptr, ptr %fp203, align 8
  %cmp.addr = alloca ptr
  store ptr %fv204, ptr %cmp.addr
  %ld205 = load ptr, ptr %lst.addr
  %res_slot206 = alloca ptr
  %tgp207 = getelementptr i8, ptr %ld205, i64 8
  %tag208 = load i32, ptr %tgp207, align 4
  switch i32 %tag208, label %case_default32 [
      i32 0, label %case_br33
      i32 1, label %case_br34
  ]
case_br33:
  %ld209 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld209)
  %ld210 = load ptr, ptr %acc.addr
  store ptr %ld210, ptr %res_slot206
  br label %case_merge31
case_br34:
  %fp211 = getelementptr i8, ptr %ld205, i64 16
  %fv212 = load ptr, ptr %fp211, align 8
  %$f1553.addr = alloca ptr
  store ptr %fv212, ptr %$f1553.addr
  %fp213 = getelementptr i8, ptr %ld205, i64 24
  %fv214 = load ptr, ptr %fp213, align 8
  %$f1554.addr = alloca ptr
  store ptr %fv214, ptr %$f1554.addr
  %freed215 = call i64 @march_decrc_freed(ptr %ld205)
  %freed_b216 = icmp ne i64 %freed215, 0
  br i1 %freed_b216, label %br_unique35, label %br_shared36
br_shared36:
  call void @march_incrc(ptr %fv214)
  call void @march_incrc(ptr %fv212)
  br label %br_body37
br_unique35:
  br label %br_body37
br_body37:
  %ld217 = load ptr, ptr %$f1554.addr
  %t.addr = alloca ptr
  store ptr %ld217, ptr %t.addr
  %ld218 = load ptr, ptr %$f1553.addr
  %h.addr = alloca ptr
  store ptr %ld218, ptr %h.addr
  %ld219 = load ptr, ptr %h.addr
  %ld220 = load ptr, ptr %acc.addr
  %ld221 = load ptr, ptr %cmp.addr
  %cr222 = call ptr @Sort.insert_sorted$V__4903$List_V__4903$Fn_V__4903_Fn_V__4903_Bool(ptr %ld219, ptr %ld220, ptr %ld221)
  %$t1552.addr = alloca ptr
  store ptr %cr222, ptr %$t1552.addr
  %ld223 = load ptr, ptr %go.addr
  %fp224 = getelementptr i8, ptr %ld223, i64 16
  %fv225 = load ptr, ptr %fp224, align 8
  %ld226 = load ptr, ptr %t.addr
  %ld227 = load ptr, ptr %$t1552.addr
  %cr228 = call ptr (ptr, ptr, ptr) %fv225(ptr %ld223, ptr %ld226, ptr %ld227)
  store ptr %cr228, ptr %res_slot206
  br label %case_merge31
case_default32:
  unreachable
case_merge31:
  %case_r229 = load ptr, ptr %res_slot206
  ret ptr %case_r229
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
