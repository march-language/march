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
  %cr49 = call ptr @gen_list(i64 10000, i64 42, ptr %ld48)
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
  %cr55 = call ptr @Sort.mergesort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %ld53, ptr %ld54)
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

define ptr @Sort.mergesort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp61 = call ptr @march_alloc(i64 24)
  %tgp62 = getelementptr i8, ptr %hp61, i64 8
  store i32 0, ptr %tgp62, align 4
  %fp63 = getelementptr i8, ptr %hp61, i64 16
  store ptr @take_k$apply$25, ptr %fp63, align 8
  %take_k.addr = alloca ptr
  store ptr %hp61, ptr %take_k.addr
  %hp64 = call ptr @march_alloc(i64 40)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 0, ptr %tgp65, align 4
  %fp66 = getelementptr i8, ptr %hp64, i64 16
  store ptr @go$apply$26, ptr %fp66, align 8
  %ld67 = load ptr, ptr %cmp.addr
  %fp68 = getelementptr i8, ptr %hp64, i64 24
  store ptr %ld67, ptr %fp68, align 8
  %ld69 = load ptr, ptr %take_k.addr
  %fp70 = getelementptr i8, ptr %hp64, i64 32
  store ptr %ld69, ptr %fp70, align 8
  %go.addr = alloca ptr
  store ptr %hp64, ptr %go.addr
  %ld71 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld71)
  %ld72 = load ptr, ptr %xs.addr
  %cr73 = call i64 @Sort.list_len$List_V__4528(ptr %ld72)
  %$t1388.addr = alloca i64
  store i64 %cr73, ptr %$t1388.addr
  %ld74 = load ptr, ptr %go.addr
  %fp75 = getelementptr i8, ptr %ld74, i64 16
  %fv76 = load ptr, ptr %fp75, align 8
  %ld77 = load ptr, ptr %xs.addr
  %ld78 = load i64, ptr %$t1388.addr
  %cr79 = call ptr (ptr, ptr, i64) %fv76(ptr %ld74, ptr %ld77, i64 %ld78)
  ret ptr %cr79
}

define i64 @Sort.list_len$List_V__4528(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp80 = call ptr @march_alloc(i64 24)
  %tgp81 = getelementptr i8, ptr %hp80, i64 8
  store i32 0, ptr %tgp81, align 4
  %fp82 = getelementptr i8, ptr %hp80, i64 16
  store ptr @go$apply$28, ptr %fp82, align 8
  %go.addr = alloca ptr
  store ptr %hp80, ptr %go.addr
  %ld83 = load ptr, ptr %go.addr
  %fp84 = getelementptr i8, ptr %ld83, i64 16
  %fv85 = load ptr, ptr %fp84, align 8
  %ld86 = load ptr, ptr %xs.addr
  %cr87 = call i64 (ptr, ptr, i64) %fv85(ptr %ld83, ptr %ld86, i64 0)
  ret i64 %cr87
}

define ptr @Sort.merge_sorted$List_V__4528$List_V__4528$Fn_V__4528_Fn_V__4528_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld88 = load ptr, ptr %xs.addr
  %res_slot89 = alloca ptr
  %tgp90 = getelementptr i8, ptr %ld88, i64 8
  %tag91 = load i32, ptr %tgp90, align 4
  switch i32 %tag91, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld92 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld92)
  %ld93 = load ptr, ptr %ys.addr
  store ptr %ld93, ptr %res_slot89
  br label %case_merge11
case_br14:
  %fp94 = getelementptr i8, ptr %ld88, i64 16
  %fv95 = load ptr, ptr %fp94, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv95, ptr %$f1372.addr
  %fp96 = getelementptr i8, ptr %ld88, i64 24
  %fv97 = load ptr, ptr %fp96, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv97, ptr %$f1373.addr
  %ld98 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld98, ptr %xt.addr
  %ld99 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld99, ptr %x.addr
  %ld100 = load ptr, ptr %ys.addr
  %res_slot101 = alloca ptr
  %tgp102 = getelementptr i8, ptr %ld100, i64 8
  %tag103 = load i32, ptr %tgp102, align 4
  switch i32 %tag103, label %case_default16 [
      i32 0, label %case_br17
      i32 1, label %case_br18
  ]
case_br17:
  %ld104 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld104)
  %ld105 = load ptr, ptr %xs.addr
  store ptr %ld105, ptr %res_slot101
  br label %case_merge15
case_br18:
  %fp106 = getelementptr i8, ptr %ld100, i64 16
  %fv107 = load ptr, ptr %fp106, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv107, ptr %$f1370.addr
  %fp108 = getelementptr i8, ptr %ld100, i64 24
  %fv109 = load ptr, ptr %fp108, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv109, ptr %$f1371.addr
  %ld110 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld110, ptr %yt.addr
  %ld111 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld111, ptr %y.addr
  %ld112 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld112)
  %ld113 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld113)
  %ld114 = load ptr, ptr %cmp.addr
  %ld115 = load ptr, ptr %x.addr
  %ld116 = load ptr, ptr %y.addr
  %cr117 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld114, ptr %ld115, ptr %ld116)
  %$t1367.addr = alloca i64
  store i64 %cr117, ptr %$t1367.addr
  %ld118 = load i64, ptr %$t1367.addr
  %res_slot119 = alloca ptr
  %bi120 = trunc i64 %ld118 to i1
  br i1 %bi120, label %case_br21, label %case_default20
case_br21:
  %ld121 = load ptr, ptr %xt.addr
  %ld122 = load ptr, ptr %ys.addr
  %ld123 = load ptr, ptr %cmp.addr
  %cr124 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld121, ptr %ld122, ptr %ld123)
  %$t1368.addr = alloca ptr
  store ptr %cr124, ptr %$t1368.addr
  %hp125 = call ptr @march_alloc(i64 32)
  %tgp126 = getelementptr i8, ptr %hp125, i64 8
  store i32 1, ptr %tgp126, align 4
  %ld127 = load ptr, ptr %x.addr
  %fp128 = getelementptr i8, ptr %hp125, i64 16
  store ptr %ld127, ptr %fp128, align 8
  %ld129 = load ptr, ptr %$t1368.addr
  %fp130 = getelementptr i8, ptr %hp125, i64 24
  store ptr %ld129, ptr %fp130, align 8
  store ptr %hp125, ptr %res_slot119
  br label %case_merge19
case_default20:
  %ld131 = load ptr, ptr %xs.addr
  %ld132 = load ptr, ptr %yt.addr
  %ld133 = load ptr, ptr %cmp.addr
  %cr134 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld131, ptr %ld132, ptr %ld133)
  %$t1369.addr = alloca ptr
  store ptr %cr134, ptr %$t1369.addr
  %hp135 = call ptr @march_alloc(i64 32)
  %tgp136 = getelementptr i8, ptr %hp135, i64 8
  store i32 1, ptr %tgp136, align 4
  %ld137 = load ptr, ptr %y.addr
  %fp138 = getelementptr i8, ptr %hp135, i64 16
  store ptr %ld137, ptr %fp138, align 8
  %ld139 = load ptr, ptr %$t1369.addr
  %fp140 = getelementptr i8, ptr %hp135, i64 24
  store ptr %ld139, ptr %fp140, align 8
  store ptr %hp135, ptr %res_slot119
  br label %case_merge19
case_merge19:
  %case_r141 = load ptr, ptr %res_slot119
  store ptr %case_r141, ptr %res_slot101
  br label %case_merge15
case_default16:
  unreachable
case_merge15:
  %case_r142 = load ptr, ptr %res_slot101
  store ptr %case_r142, ptr %res_slot89
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r143 = load ptr, ptr %res_slot89
  ret ptr %case_r143
}

define ptr @Sort.reverse_list$List_V__4510(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp144 = call ptr @march_alloc(i64 24)
  %tgp145 = getelementptr i8, ptr %hp144, i64 8
  store i32 0, ptr %tgp145, align 4
  %fp146 = getelementptr i8, ptr %hp144, i64 16
  store ptr @go$apply$29, ptr %fp146, align 8
  %go.addr = alloca ptr
  store ptr %hp144, ptr %go.addr
  %hp147 = call ptr @march_alloc(i64 16)
  %tgp148 = getelementptr i8, ptr %hp147, i64 8
  store i32 0, ptr %tgp148, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp147, ptr %$t1355.addr
  %ld149 = load ptr, ptr %go.addr
  %fp150 = getelementptr i8, ptr %ld149, i64 16
  %fv151 = load ptr, ptr %fp150, align 8
  %ld152 = load ptr, ptr %xs.addr
  %ld153 = load ptr, ptr %$t1355.addr
  %cr154 = call ptr (ptr, ptr, ptr) %fv151(ptr %ld149, ptr %ld152, ptr %ld153)
  ret ptr %cr154
}

define ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld155 = load ptr, ptr %xs.addr
  %res_slot156 = alloca ptr
  %tgp157 = getelementptr i8, ptr %ld155, i64 8
  %tag158 = load i32, ptr %tgp157, align 4
  switch i32 %tag158, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld159 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld159)
  %ld160 = load ptr, ptr %ys.addr
  store ptr %ld160, ptr %res_slot156
  br label %case_merge22
case_br25:
  %fp161 = getelementptr i8, ptr %ld155, i64 16
  %fv162 = load ptr, ptr %fp161, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv162, ptr %$f1372.addr
  %fp163 = getelementptr i8, ptr %ld155, i64 24
  %fv164 = load ptr, ptr %fp163, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv164, ptr %$f1373.addr
  %ld165 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld165, ptr %xt.addr
  %ld166 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld166, ptr %x.addr
  %ld167 = load ptr, ptr %ys.addr
  %res_slot168 = alloca ptr
  %tgp169 = getelementptr i8, ptr %ld167, i64 8
  %tag170 = load i32, ptr %tgp169, align 4
  switch i32 %tag170, label %case_default27 [
      i32 0, label %case_br28
      i32 1, label %case_br29
  ]
case_br28:
  %ld171 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld171)
  %ld172 = load ptr, ptr %xs.addr
  store ptr %ld172, ptr %res_slot168
  br label %case_merge26
case_br29:
  %fp173 = getelementptr i8, ptr %ld167, i64 16
  %fv174 = load ptr, ptr %fp173, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv174, ptr %$f1370.addr
  %fp175 = getelementptr i8, ptr %ld167, i64 24
  %fv176 = load ptr, ptr %fp175, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv176, ptr %$f1371.addr
  %ld177 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld177, ptr %yt.addr
  %ld178 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld178, ptr %y.addr
  %ld179 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld179)
  %ld180 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld180)
  %ld181 = load ptr, ptr %cmp.addr
  %ld182 = load ptr, ptr %x.addr
  %ld183 = load ptr, ptr %y.addr
  %cr184 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld181, ptr %ld182, ptr %ld183)
  %$t1367.addr = alloca i64
  store i64 %cr184, ptr %$t1367.addr
  %ld185 = load i64, ptr %$t1367.addr
  %res_slot186 = alloca ptr
  %bi187 = trunc i64 %ld185 to i1
  br i1 %bi187, label %case_br32, label %case_default31
case_br32:
  %ld188 = load ptr, ptr %xt.addr
  %ld189 = load ptr, ptr %ys.addr
  %ld190 = load ptr, ptr %cmp.addr
  %cr191 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld188, ptr %ld189, ptr %ld190)
  %$t1368.addr = alloca ptr
  store ptr %cr191, ptr %$t1368.addr
  %hp192 = call ptr @march_alloc(i64 32)
  %tgp193 = getelementptr i8, ptr %hp192, i64 8
  store i32 1, ptr %tgp193, align 4
  %ld194 = load ptr, ptr %x.addr
  %fp195 = getelementptr i8, ptr %hp192, i64 16
  store ptr %ld194, ptr %fp195, align 8
  %ld196 = load ptr, ptr %$t1368.addr
  %fp197 = getelementptr i8, ptr %hp192, i64 24
  store ptr %ld196, ptr %fp197, align 8
  store ptr %hp192, ptr %res_slot186
  br label %case_merge30
case_default31:
  %ld198 = load ptr, ptr %xs.addr
  %ld199 = load ptr, ptr %yt.addr
  %ld200 = load ptr, ptr %cmp.addr
  %cr201 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld198, ptr %ld199, ptr %ld200)
  %$t1369.addr = alloca ptr
  store ptr %cr201, ptr %$t1369.addr
  %hp202 = call ptr @march_alloc(i64 32)
  %tgp203 = getelementptr i8, ptr %hp202, i64 8
  store i32 1, ptr %tgp203, align 4
  %ld204 = load ptr, ptr %y.addr
  %fp205 = getelementptr i8, ptr %hp202, i64 16
  store ptr %ld204, ptr %fp205, align 8
  %ld206 = load ptr, ptr %$t1369.addr
  %fp207 = getelementptr i8, ptr %hp202, i64 24
  store ptr %ld206, ptr %fp207, align 8
  store ptr %hp202, ptr %res_slot186
  br label %case_merge30
case_merge30:
  %case_r208 = load ptr, ptr %res_slot186
  store ptr %case_r208, ptr %res_slot168
  br label %case_merge26
case_default27:
  unreachable
case_merge26:
  %case_r209 = load ptr, ptr %res_slot168
  store ptr %case_r209, ptr %res_slot156
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r210 = load ptr, ptr %res_slot156
  ret ptr %case_r210
}

define i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld211 = load ptr, ptr %cmp.addr
  %fp212 = getelementptr i8, ptr %ld211, i64 16
  %fv213 = load ptr, ptr %fp212, align 8
  %ld214 = load ptr, ptr %x.addr
  %cr215 = call ptr (ptr, ptr) %fv213(ptr %ld211, ptr %ld214)
  %f.addr = alloca ptr
  store ptr %cr215, ptr %f.addr
  %ld216 = load ptr, ptr %f.addr
  %fp217 = getelementptr i8, ptr %ld216, i64 16
  %fv218 = load ptr, ptr %fp217, align 8
  %ld219 = load ptr, ptr %y.addr
  %cr220 = call i64 (ptr, ptr) %fv218(ptr %ld216, ptr %ld219)
  ret i64 %cr220
}

define ptr @$lam2018$apply$21(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp221 = call ptr @march_alloc(i64 32)
  %tgp222 = getelementptr i8, ptr %hp221, i64 8
  store i32 0, ptr %tgp222, align 4
  %fp223 = getelementptr i8, ptr %hp221, i64 16
  store ptr @$lam2019$apply$22, ptr %fp223, align 8
  %ld224 = load ptr, ptr %x.addr
  %fp225 = getelementptr i8, ptr %hp221, i64 24
  store ptr %ld224, ptr %fp225, align 8
  ret ptr %hp221
}

define i64 @$lam2019$apply$22(ptr %$clo.arg, ptr %y.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld226 = load ptr, ptr %$clo.addr
  %fp227 = getelementptr i8, ptr %ld226, i64 24
  %fv228 = load ptr, ptr %fp227, align 8
  %x.addr = alloca ptr
  store ptr %fv228, ptr %x.addr
  %ld229 = load ptr, ptr %x.addr
  %ld230 = load ptr, ptr %y.addr
  %cv233 = ptrtoint ptr %ld229 to i64
  %cv234 = ptrtoint ptr %ld230 to i64
  %cmp231 = icmp sle i64 %cv233, %cv234
  %ar232 = zext i1 %cmp231 to i64
  ret i64 %ar232
}

define ptr @take_k$apply$25(ptr %$clo.arg, ptr %lst.arg, i64 %k.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %k.addr = alloca i64
  store i64 %k.arg, ptr %k.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld235 = load ptr, ptr %$clo.addr
  %take_k.addr = alloca ptr
  store ptr %ld235, ptr %take_k.addr
  %ld236 = load i64, ptr %k.addr
  %cmp237 = icmp eq i64 %ld236, 0
  %ar238 = zext i1 %cmp237 to i64
  %$t1374.addr = alloca i64
  store i64 %ar238, ptr %$t1374.addr
  %ld239 = load i64, ptr %$t1374.addr
  %res_slot240 = alloca ptr
  %bi241 = trunc i64 %ld239 to i1
  br i1 %bi241, label %case_br35, label %case_default34
case_br35:
  %ld242 = load ptr, ptr %acc.addr
  %cr243 = call ptr @Sort.reverse_list$List_V__4510(ptr %ld242)
  %$t1375.addr = alloca ptr
  store ptr %cr243, ptr %$t1375.addr
  %hp244 = call ptr @march_alloc(i64 32)
  %tgp245 = getelementptr i8, ptr %hp244, i64 8
  store i32 0, ptr %tgp245, align 4
  %ld246 = load ptr, ptr %$t1375.addr
  %fp247 = getelementptr i8, ptr %hp244, i64 16
  store ptr %ld246, ptr %fp247, align 8
  %ld248 = load ptr, ptr %lst.addr
  %fp249 = getelementptr i8, ptr %hp244, i64 24
  store ptr %ld248, ptr %fp249, align 8
  store ptr %hp244, ptr %res_slot240
  br label %case_merge33
case_default34:
  %ld250 = load ptr, ptr %lst.addr
  %res_slot251 = alloca ptr
  %tgp252 = getelementptr i8, ptr %ld250, i64 8
  %tag253 = load i32, ptr %tgp252, align 4
  switch i32 %tag253, label %case_default37 [
      i32 0, label %case_br38
      i32 1, label %case_br39
  ]
case_br38:
  %ld254 = load ptr, ptr %acc.addr
  %cr255 = call ptr @Sort.reverse_list$List_V__4510(ptr %ld254)
  %$t1376.addr = alloca ptr
  store ptr %cr255, ptr %$t1376.addr
  %ld256 = load ptr, ptr %lst.addr
  %rc257 = load i64, ptr %ld256, align 8
  %uniq258 = icmp eq i64 %rc257, 1
  %fbip_slot259 = alloca ptr
  br i1 %uniq258, label %fbip_reuse40, label %fbip_fresh41
fbip_reuse40:
  %tgp260 = getelementptr i8, ptr %ld256, i64 8
  store i32 0, ptr %tgp260, align 4
  store ptr %ld256, ptr %fbip_slot259
  br label %fbip_merge42
fbip_fresh41:
  call void @march_decrc(ptr %ld256)
  %hp261 = call ptr @march_alloc(i64 16)
  %tgp262 = getelementptr i8, ptr %hp261, i64 8
  store i32 0, ptr %tgp262, align 4
  store ptr %hp261, ptr %fbip_slot259
  br label %fbip_merge42
fbip_merge42:
  %fbip_r263 = load ptr, ptr %fbip_slot259
  %$t1377.addr = alloca ptr
  store ptr %fbip_r263, ptr %$t1377.addr
  %hp264 = call ptr @march_alloc(i64 32)
  %tgp265 = getelementptr i8, ptr %hp264, i64 8
  store i32 0, ptr %tgp265, align 4
  %ld266 = load ptr, ptr %$t1376.addr
  %fp267 = getelementptr i8, ptr %hp264, i64 16
  store ptr %ld266, ptr %fp267, align 8
  %ld268 = load ptr, ptr %$t1377.addr
  %fp269 = getelementptr i8, ptr %hp264, i64 24
  store ptr %ld268, ptr %fp269, align 8
  store ptr %hp264, ptr %res_slot251
  br label %case_merge36
case_br39:
  %fp270 = getelementptr i8, ptr %ld250, i64 16
  %fv271 = load ptr, ptr %fp270, align 8
  %$f1380.addr = alloca ptr
  store ptr %fv271, ptr %$f1380.addr
  %fp272 = getelementptr i8, ptr %ld250, i64 24
  %fv273 = load ptr, ptr %fp272, align 8
  %$f1381.addr = alloca ptr
  store ptr %fv273, ptr %$f1381.addr
  %ld274 = load ptr, ptr %$f1381.addr
  %t.addr = alloca ptr
  store ptr %ld274, ptr %t.addr
  %ld275 = load ptr, ptr %$f1380.addr
  %h.addr = alloca ptr
  store ptr %ld275, ptr %h.addr
  %ld276 = load i64, ptr %k.addr
  %ar277 = sub i64 %ld276, 1
  %$t1378.addr = alloca i64
  store i64 %ar277, ptr %$t1378.addr
  %ld278 = load ptr, ptr %lst.addr
  %ld279 = load ptr, ptr %h.addr
  %ld280 = load ptr, ptr %acc.addr
  %rc281 = load i64, ptr %ld278, align 8
  %uniq282 = icmp eq i64 %rc281, 1
  %fbip_slot283 = alloca ptr
  br i1 %uniq282, label %fbip_reuse43, label %fbip_fresh44
fbip_reuse43:
  %tgp284 = getelementptr i8, ptr %ld278, i64 8
  store i32 1, ptr %tgp284, align 4
  %fp285 = getelementptr i8, ptr %ld278, i64 16
  store ptr %ld279, ptr %fp285, align 8
  %fp286 = getelementptr i8, ptr %ld278, i64 24
  store ptr %ld280, ptr %fp286, align 8
  store ptr %ld278, ptr %fbip_slot283
  br label %fbip_merge45
fbip_fresh44:
  call void @march_decrc(ptr %ld278)
  %hp287 = call ptr @march_alloc(i64 32)
  %tgp288 = getelementptr i8, ptr %hp287, i64 8
  store i32 1, ptr %tgp288, align 4
  %fp289 = getelementptr i8, ptr %hp287, i64 16
  store ptr %ld279, ptr %fp289, align 8
  %fp290 = getelementptr i8, ptr %hp287, i64 24
  store ptr %ld280, ptr %fp290, align 8
  store ptr %hp287, ptr %fbip_slot283
  br label %fbip_merge45
fbip_merge45:
  %fbip_r291 = load ptr, ptr %fbip_slot283
  %$t1379.addr = alloca ptr
  store ptr %fbip_r291, ptr %$t1379.addr
  %ld292 = load ptr, ptr %take_k.addr
  %fp293 = getelementptr i8, ptr %ld292, i64 16
  %fv294 = load ptr, ptr %fp293, align 8
  %ld295 = load ptr, ptr %t.addr
  %ld296 = load i64, ptr %$t1378.addr
  %ld297 = load ptr, ptr %$t1379.addr
  %cr298 = call ptr (ptr, ptr, i64, ptr) %fv294(ptr %ld292, ptr %ld295, i64 %ld296, ptr %ld297)
  store ptr %cr298, ptr %res_slot251
  br label %case_merge36
case_default37:
  unreachable
case_merge36:
  %case_r299 = load ptr, ptr %res_slot251
  store ptr %case_r299, ptr %res_slot240
  br label %case_merge33
case_merge33:
  %case_r300 = load ptr, ptr %res_slot240
  ret ptr %case_r300
}

define ptr @go$apply$26(ptr %$clo.arg, ptr %lst.arg, i64 %n.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld301 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld301)
  %ld302 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld302, ptr %go.addr
  %ld303 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld303)
  %ld304 = load ptr, ptr %$clo.addr
  %fp305 = getelementptr i8, ptr %ld304, i64 24
  %fv306 = load ptr, ptr %fp305, align 8
  %cmp.addr = alloca ptr
  store ptr %fv306, ptr %cmp.addr
  %ld307 = load ptr, ptr %$clo.addr
  %fp308 = getelementptr i8, ptr %ld307, i64 32
  %fv309 = load ptr, ptr %fp308, align 8
  %take_k.addr = alloca ptr
  store ptr %fv309, ptr %take_k.addr
  %ld310 = load i64, ptr %n.addr
  %cmp311 = icmp sle i64 %ld310, 1
  %ar312 = zext i1 %cmp311 to i64
  %$t1382.addr = alloca i64
  store i64 %ar312, ptr %$t1382.addr
  %ld313 = load i64, ptr %$t1382.addr
  %res_slot314 = alloca ptr
  %bi315 = trunc i64 %ld313 to i1
  br i1 %bi315, label %case_br48, label %case_default47
case_br48:
  %ld316 = load ptr, ptr %lst.addr
  store ptr %ld316, ptr %res_slot314
  br label %case_merge46
case_default47:
  %ld317 = load i64, ptr %n.addr
  %ar318 = sdiv i64 %ld317, 2
  %half.addr = alloca i64
  store i64 %ar318, ptr %half.addr
  %hp319 = call ptr @march_alloc(i64 16)
  %tgp320 = getelementptr i8, ptr %hp319, i64 8
  store i32 0, ptr %tgp320, align 4
  %$t1383.addr = alloca ptr
  store ptr %hp319, ptr %$t1383.addr
  %ld321 = load ptr, ptr %take_k.addr
  %fp322 = getelementptr i8, ptr %ld321, i64 16
  %fv323 = load ptr, ptr %fp322, align 8
  %ld324 = load ptr, ptr %lst.addr
  %ld325 = load i64, ptr %half.addr
  %ld326 = load ptr, ptr %$t1383.addr
  %cr327 = call ptr (ptr, ptr, i64, ptr) %fv323(ptr %ld321, ptr %ld324, i64 %ld325, ptr %ld326)
  %$p1387.addr = alloca ptr
  store ptr %cr327, ptr %$p1387.addr
  %ld328 = load ptr, ptr %$p1387.addr
  %fp329 = getelementptr i8, ptr %ld328, i64 16
  %fv330 = load ptr, ptr %fp329, align 8
  %l.addr = alloca ptr
  store ptr %fv330, ptr %l.addr
  %ld331 = load ptr, ptr %$p1387.addr
  %fp332 = getelementptr i8, ptr %ld331, i64 24
  %fv333 = load ptr, ptr %fp332, align 8
  %r.addr = alloca ptr
  store ptr %fv333, ptr %r.addr
  %ld334 = load ptr, ptr %go.addr
  %fp335 = getelementptr i8, ptr %ld334, i64 16
  %fv336 = load ptr, ptr %fp335, align 8
  %ld337 = load ptr, ptr %l.addr
  %ld338 = load i64, ptr %half.addr
  %cr339 = call ptr (ptr, ptr, i64) %fv336(ptr %ld334, ptr %ld337, i64 %ld338)
  %$t1384.addr = alloca ptr
  store ptr %cr339, ptr %$t1384.addr
  %ld340 = load i64, ptr %n.addr
  %ld341 = load i64, ptr %half.addr
  %ar342 = sub i64 %ld340, %ld341
  %$t1385.addr = alloca i64
  store i64 %ar342, ptr %$t1385.addr
  %ld343 = load ptr, ptr %go.addr
  %fp344 = getelementptr i8, ptr %ld343, i64 16
  %fv345 = load ptr, ptr %fp344, align 8
  %ld346 = load ptr, ptr %r.addr
  %ld347 = load i64, ptr %$t1385.addr
  %cr348 = call ptr (ptr, ptr, i64) %fv345(ptr %ld343, ptr %ld346, i64 %ld347)
  %$t1386.addr = alloca ptr
  store ptr %cr348, ptr %$t1386.addr
  %ld349 = load ptr, ptr %$t1384.addr
  %ld350 = load ptr, ptr %$t1386.addr
  %ld351 = load ptr, ptr %cmp.addr
  %cr352 = call ptr @Sort.merge_sorted$List_V__4528$List_V__4528$Fn_V__4528_Fn_V__4528_Bool(ptr %ld349, ptr %ld350, ptr %ld351)
  store ptr %cr352, ptr %res_slot314
  br label %case_merge46
case_merge46:
  %case_r353 = load ptr, ptr %res_slot314
  ret ptr %case_r353
}

define i64 @go$apply$28(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld354 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld354, ptr %go.addr
  %ld355 = load ptr, ptr %lst.addr
  %res_slot356 = alloca ptr
  %tgp357 = getelementptr i8, ptr %ld355, i64 8
  %tag358 = load i32, ptr %tgp357, align 4
  switch i32 %tag358, label %case_default50 [
      i32 0, label %case_br51
      i32 1, label %case_br52
  ]
case_br51:
  %ld359 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld359)
  %ld360 = load i64, ptr %acc.addr
  %cv361 = inttoptr i64 %ld360 to ptr
  store ptr %cv361, ptr %res_slot356
  br label %case_merge49
case_br52:
  %fp362 = getelementptr i8, ptr %ld355, i64 16
  %fv363 = load ptr, ptr %fp362, align 8
  %$f1360.addr = alloca ptr
  store ptr %fv363, ptr %$f1360.addr
  %fp364 = getelementptr i8, ptr %ld355, i64 24
  %fv365 = load ptr, ptr %fp364, align 8
  %$f1361.addr = alloca ptr
  store ptr %fv365, ptr %$f1361.addr
  %freed366 = call i64 @march_decrc_freed(ptr %ld355)
  %freed_b367 = icmp ne i64 %freed366, 0
  br i1 %freed_b367, label %br_unique53, label %br_shared54
br_shared54:
  call void @march_incrc(ptr %fv365)
  call void @march_incrc(ptr %fv363)
  br label %br_body55
br_unique53:
  br label %br_body55
br_body55:
  %ld368 = load ptr, ptr %$f1361.addr
  %t.addr = alloca ptr
  store ptr %ld368, ptr %t.addr
  %ld369 = load i64, ptr %acc.addr
  %ar370 = add i64 %ld369, 1
  %$t1359.addr = alloca i64
  store i64 %ar370, ptr %$t1359.addr
  %ld371 = load ptr, ptr %go.addr
  %fp372 = getelementptr i8, ptr %ld371, i64 16
  %fv373 = load ptr, ptr %fp372, align 8
  %ld374 = load ptr, ptr %t.addr
  %ld375 = load i64, ptr %$t1359.addr
  %cr376 = call i64 (ptr, ptr, i64) %fv373(ptr %ld371, ptr %ld374, i64 %ld375)
  %cv377 = inttoptr i64 %cr376 to ptr
  store ptr %cv377, ptr %res_slot356
  br label %case_merge49
case_default50:
  unreachable
case_merge49:
  %case_r378 = load ptr, ptr %res_slot356
  %cv379 = ptrtoint ptr %case_r378 to i64
  ret i64 %cv379
}

define ptr @go$apply$29(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld380 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld380, ptr %go.addr
  %ld381 = load ptr, ptr %lst.addr
  %res_slot382 = alloca ptr
  %tgp383 = getelementptr i8, ptr %ld381, i64 8
  %tag384 = load i32, ptr %tgp383, align 4
  switch i32 %tag384, label %case_default57 [
      i32 0, label %case_br58
      i32 1, label %case_br59
  ]
case_br58:
  %ld385 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld385)
  %ld386 = load ptr, ptr %acc.addr
  store ptr %ld386, ptr %res_slot382
  br label %case_merge56
case_br59:
  %fp387 = getelementptr i8, ptr %ld381, i64 16
  %fv388 = load ptr, ptr %fp387, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv388, ptr %$f1353.addr
  %fp389 = getelementptr i8, ptr %ld381, i64 24
  %fv390 = load ptr, ptr %fp389, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv390, ptr %$f1354.addr
  %ld391 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld391, ptr %t.addr
  %ld392 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld392, ptr %h.addr
  %ld393 = load ptr, ptr %lst.addr
  %ld394 = load ptr, ptr %h.addr
  %ld395 = load ptr, ptr %acc.addr
  %rc396 = load i64, ptr %ld393, align 8
  %uniq397 = icmp eq i64 %rc396, 1
  %fbip_slot398 = alloca ptr
  br i1 %uniq397, label %fbip_reuse60, label %fbip_fresh61
fbip_reuse60:
  %tgp399 = getelementptr i8, ptr %ld393, i64 8
  store i32 1, ptr %tgp399, align 4
  %fp400 = getelementptr i8, ptr %ld393, i64 16
  store ptr %ld394, ptr %fp400, align 8
  %fp401 = getelementptr i8, ptr %ld393, i64 24
  store ptr %ld395, ptr %fp401, align 8
  store ptr %ld393, ptr %fbip_slot398
  br label %fbip_merge62
fbip_fresh61:
  call void @march_decrc(ptr %ld393)
  %hp402 = call ptr @march_alloc(i64 32)
  %tgp403 = getelementptr i8, ptr %hp402, i64 8
  store i32 1, ptr %tgp403, align 4
  %fp404 = getelementptr i8, ptr %hp402, i64 16
  store ptr %ld394, ptr %fp404, align 8
  %fp405 = getelementptr i8, ptr %hp402, i64 24
  store ptr %ld395, ptr %fp405, align 8
  store ptr %hp402, ptr %fbip_slot398
  br label %fbip_merge62
fbip_merge62:
  %fbip_r406 = load ptr, ptr %fbip_slot398
  %$t1352.addr = alloca ptr
  store ptr %fbip_r406, ptr %$t1352.addr
  %ld407 = load ptr, ptr %go.addr
  %fp408 = getelementptr i8, ptr %ld407, i64 16
  %fv409 = load ptr, ptr %fp408, align 8
  %ld410 = load ptr, ptr %t.addr
  %ld411 = load ptr, ptr %$t1352.addr
  %cr412 = call ptr (ptr, ptr, ptr) %fv409(ptr %ld407, ptr %ld410, ptr %ld411)
  store ptr %cr412, ptr %res_slot382
  br label %case_merge56
case_default57:
  unreachable
case_merge56:
  %case_r413 = load ptr, ptr %res_slot382
  ret ptr %case_r413
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
