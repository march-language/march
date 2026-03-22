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


define ptr @build_pairs(i64 %n.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp slt i64 %ld1, 0
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
  %ld8 = load i64, ptr %n.addr
  %ld9 = load i64, ptr %n.addr
  %ar10 = add i64 %ld8, %ld9
  %sr_s2.addr = alloca i64
  store i64 %ar10, ptr %sr_s2.addr
  %ld11 = load i64, ptr %sr_s2.addr
  %even.addr = alloca i64
  store i64 %ld11, ptr %even.addr
  %ld12 = load i64, ptr %n.addr
  %ld13 = load i64, ptr %n.addr
  %ar14 = add i64 %ld12, %ld13
  %sr_s1.addr = alloca i64
  store i64 %ar14, ptr %sr_s1.addr
  %ld15 = load i64, ptr %sr_s1.addr
  %$t2010.addr = alloca i64
  store i64 %ld15, ptr %$t2010.addr
  %ld16 = load i64, ptr %$t2010.addr
  %ar17 = add i64 %ld16, 1
  %odd.addr = alloca i64
  store i64 %ar17, ptr %odd.addr
  %ld18 = load i64, ptr %n.addr
  %ar19 = sub i64 %ld18, 1
  %$t2011.addr = alloca i64
  store i64 %ar19, ptr %$t2011.addr
  %hp20 = call ptr @march_alloc(i64 32)
  %tgp21 = getelementptr i8, ptr %hp20, i64 8
  store i32 1, ptr %tgp21, align 4
  %ld22 = load i64, ptr %odd.addr
  %cv23 = inttoptr i64 %ld22 to ptr
  %fp24 = getelementptr i8, ptr %hp20, i64 16
  store ptr %cv23, ptr %fp24, align 8
  %ld25 = load ptr, ptr %acc.addr
  %fp26 = getelementptr i8, ptr %hp20, i64 24
  store ptr %ld25, ptr %fp26, align 8
  %$t2012.addr = alloca ptr
  store ptr %hp20, ptr %$t2012.addr
  %hp27 = call ptr @march_alloc(i64 32)
  %tgp28 = getelementptr i8, ptr %hp27, i64 8
  store i32 1, ptr %tgp28, align 4
  %ld29 = load i64, ptr %even.addr
  %cv30 = inttoptr i64 %ld29 to ptr
  %fp31 = getelementptr i8, ptr %hp27, i64 16
  store ptr %cv30, ptr %fp31, align 8
  %ld32 = load ptr, ptr %$t2012.addr
  %fp33 = getelementptr i8, ptr %hp27, i64 24
  store ptr %ld32, ptr %fp33, align 8
  %$t2013.addr = alloca ptr
  store ptr %hp27, ptr %$t2013.addr
  %ld34 = load i64, ptr %$t2011.addr
  %ld35 = load ptr, ptr %$t2013.addr
  %cr36 = call ptr @build_pairs(i64 %ld34, ptr %ld35)
  store ptr %cr36, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r37 = load ptr, ptr %res_slot5
  ret ptr %case_r37
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld38 = load ptr, ptr %xs.addr
  %res_slot39 = alloca ptr
  %tgp40 = getelementptr i8, ptr %ld38, i64 8
  %tag41 = load i32, ptr %tgp40, align 4
  switch i32 %tag41, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld42 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld42)
  %cv43 = inttoptr i64 0 to ptr
  store ptr %cv43, ptr %res_slot39
  br label %case_merge4
case_br7:
  %fp44 = getelementptr i8, ptr %ld38, i64 16
  %fv45 = load ptr, ptr %fp44, align 8
  %$f2014.addr = alloca ptr
  store ptr %fv45, ptr %$f2014.addr
  %fp46 = getelementptr i8, ptr %ld38, i64 24
  %fv47 = load ptr, ptr %fp46, align 8
  %$f2015.addr = alloca ptr
  store ptr %fv47, ptr %$f2015.addr
  %freed48 = call i64 @march_decrc_freed(ptr %ld38)
  %freed_b49 = icmp ne i64 %freed48, 0
  br i1 %freed_b49, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv47)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld50 = load ptr, ptr %$f2014.addr
  %h.addr = alloca ptr
  store ptr %ld50, ptr %h.addr
  %ld51 = load ptr, ptr %h.addr
  store ptr %ld51, ptr %res_slot39
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r52 = load ptr, ptr %res_slot39
  %cv53 = ptrtoint ptr %case_r52 to i64
  ret i64 %cv53
}

define void @march_main() {
entry:
  %hp54 = call ptr @march_alloc(i64 24)
  %tgp55 = getelementptr i8, ptr %hp54, i64 8
  store i32 0, ptr %tgp55, align 4
  %fp56 = getelementptr i8, ptr %hp54, i64 16
  store ptr @$lam2016$apply$21, ptr %fp56, align 8
  %cmp.addr = alloca ptr
  store ptr %hp54, ptr %cmp.addr
  %hp57 = call ptr @march_alloc(i64 16)
  %tgp58 = getelementptr i8, ptr %hp57, i64 8
  store i32 0, ptr %tgp58, align 4
  %$t2018.addr = alloca ptr
  store ptr %hp57, ptr %$t2018.addr
  %ld59 = load ptr, ptr %$t2018.addr
  %cr60 = call ptr @build_pairs(i64 4999, ptr %ld59)
  %$t2019.addr = alloca ptr
  store ptr %cr60, ptr %$t2019.addr
  %ld61 = load ptr, ptr %$t2019.addr
  %ld62 = load ptr, ptr %cmp.addr
  %cr63 = call ptr @Sort.timsort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %ld61, ptr %ld62)
  %ts.addr = alloca ptr
  store ptr %cr63, ptr %ts.addr
  %hp64 = call ptr @march_alloc(i64 16)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 0, ptr %tgp65, align 4
  %$t2020.addr = alloca ptr
  store ptr %hp64, ptr %$t2020.addr
  %ld66 = load ptr, ptr %$t2020.addr
  %cr67 = call ptr @build_pairs(i64 4999, ptr %ld66)
  %$t2021.addr = alloca ptr
  store ptr %cr67, ptr %$t2021.addr
  %ld68 = load ptr, ptr %$t2021.addr
  %ld69 = load ptr, ptr %cmp.addr
  %cr70 = call ptr @Sort.mergesort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %ld68, ptr %ld69)
  %ms.addr = alloca ptr
  store ptr %cr70, ptr %ms.addr
  %ld71 = load ptr, ptr %ts.addr
  %cr72 = call i64 @head(ptr %ld71)
  %$t2022.addr = alloca i64
  store i64 %cr72, ptr %$t2022.addr
  %ld73 = load i64, ptr %$t2022.addr
  %cr74 = call ptr @march_int_to_string(i64 %ld73)
  %$t2023.addr = alloca ptr
  store ptr %cr74, ptr %$t2023.addr
  %ld75 = load ptr, ptr %$t2023.addr
  call void @march_println(ptr %ld75)
  %ld76 = load ptr, ptr %ms.addr
  %cr77 = call i64 @head(ptr %ld76)
  %$t2024.addr = alloca i64
  store i64 %cr77, ptr %$t2024.addr
  %ld78 = load i64, ptr %$t2024.addr
  %cr79 = call ptr @march_int_to_string(i64 %ld78)
  %$t2025.addr = alloca ptr
  store ptr %cr79, ptr %$t2025.addr
  %ld80 = load ptr, ptr %$t2025.addr
  call void @march_println(ptr %ld80)
  ret void
}

define ptr @Sort.mergesort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp81 = call ptr @march_alloc(i64 24)
  %tgp82 = getelementptr i8, ptr %hp81, i64 8
  store i32 0, ptr %tgp82, align 4
  %fp83 = getelementptr i8, ptr %hp81, i64 16
  store ptr @take_k$apply$25, ptr %fp83, align 8
  %take_k.addr = alloca ptr
  store ptr %hp81, ptr %take_k.addr
  %hp84 = call ptr @march_alloc(i64 40)
  %tgp85 = getelementptr i8, ptr %hp84, i64 8
  store i32 0, ptr %tgp85, align 4
  %fp86 = getelementptr i8, ptr %hp84, i64 16
  store ptr @go$apply$26, ptr %fp86, align 8
  %ld87 = load ptr, ptr %cmp.addr
  %fp88 = getelementptr i8, ptr %hp84, i64 24
  store ptr %ld87, ptr %fp88, align 8
  %ld89 = load ptr, ptr %take_k.addr
  %fp90 = getelementptr i8, ptr %hp84, i64 32
  store ptr %ld89, ptr %fp90, align 8
  %go.addr = alloca ptr
  store ptr %hp84, ptr %go.addr
  %ld91 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld91)
  %ld92 = load ptr, ptr %xs.addr
  %cr93 = call i64 @Sort.list_len$List_V__4528(ptr %ld92)
  %$t1388.addr = alloca i64
  store i64 %cr93, ptr %$t1388.addr
  %ld94 = load ptr, ptr %go.addr
  %fp95 = getelementptr i8, ptr %ld94, i64 16
  %fv96 = load ptr, ptr %fp95, align 8
  %ld97 = load ptr, ptr %xs.addr
  %ld98 = load i64, ptr %$t1388.addr
  %cr99 = call ptr (ptr, ptr, i64) %fv96(ptr %ld94, ptr %ld97, i64 %ld98)
  ret ptr %cr99
}

define ptr @Sort.timsort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld100 = load ptr, ptr %xs.addr
  %ld101 = load ptr, ptr %cmp.addr
  %cr102 = call ptr @Sort.detect_runs$List_V__5074$Fn_V__5074_Fn_V__5074_Bool(ptr %ld100, ptr %ld101)
  %runs.addr = alloca ptr
  store ptr %cr102, ptr %runs.addr
  %hp103 = call ptr @march_alloc(i64 32)
  %tgp104 = getelementptr i8, ptr %hp103, i64 8
  store i32 0, ptr %tgp104, align 4
  %fp105 = getelementptr i8, ptr %hp103, i64 16
  store ptr @process$apply$27, ptr %fp105, align 8
  %ld106 = load ptr, ptr %cmp.addr
  %fp107 = getelementptr i8, ptr %hp103, i64 24
  store ptr %ld106, ptr %fp107, align 8
  %process.addr = alloca ptr
  store ptr %hp103, ptr %process.addr
  %hp108 = call ptr @march_alloc(i64 16)
  %tgp109 = getelementptr i8, ptr %hp108, i64 8
  store i32 0, ptr %tgp109, align 4
  %$t1625.addr = alloca ptr
  store ptr %hp108, ptr %$t1625.addr
  %ld110 = load ptr, ptr %process.addr
  %fp111 = getelementptr i8, ptr %ld110, i64 16
  %fv112 = load ptr, ptr %fp111, align 8
  %ld113 = load ptr, ptr %runs.addr
  %ld114 = load ptr, ptr %$t1625.addr
  %cr115 = call ptr (ptr, ptr, ptr) %fv112(ptr %ld110, ptr %ld113, ptr %ld114)
  %final_stack.addr = alloca ptr
  store ptr %cr115, ptr %final_stack.addr
  %ld116 = load ptr, ptr %final_stack.addr
  %ld117 = load ptr, ptr %cmp.addr
  %cr118 = call ptr @Sort.drain_stack$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %ld116, ptr %ld117)
  ret ptr %cr118
}

define i64 @Sort.list_len$List_V__4528(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp119 = call ptr @march_alloc(i64 24)
  %tgp120 = getelementptr i8, ptr %hp119, i64 8
  store i32 0, ptr %tgp120, align 4
  %fp121 = getelementptr i8, ptr %hp119, i64 16
  store ptr @go$apply$29, ptr %fp121, align 8
  %go.addr = alloca ptr
  store ptr %hp119, ptr %go.addr
  %ld122 = load ptr, ptr %go.addr
  %fp123 = getelementptr i8, ptr %ld122, i64 16
  %fv124 = load ptr, ptr %fp123, align 8
  %ld125 = load ptr, ptr %xs.addr
  %cr126 = call i64 (ptr, ptr, i64) %fv124(ptr %ld122, ptr %ld125, i64 0)
  ret i64 %cr126
}

define ptr @Sort.merge_sorted$List_V__4528$List_V__4528$Fn_V__4528_Fn_V__4528_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld127 = load ptr, ptr %xs.addr
  %res_slot128 = alloca ptr
  %tgp129 = getelementptr i8, ptr %ld127, i64 8
  %tag130 = load i32, ptr %tgp129, align 4
  switch i32 %tag130, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld131 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld131)
  %ld132 = load ptr, ptr %ys.addr
  store ptr %ld132, ptr %res_slot128
  br label %case_merge11
case_br14:
  %fp133 = getelementptr i8, ptr %ld127, i64 16
  %fv134 = load ptr, ptr %fp133, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv134, ptr %$f1372.addr
  %fp135 = getelementptr i8, ptr %ld127, i64 24
  %fv136 = load ptr, ptr %fp135, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv136, ptr %$f1373.addr
  %ld137 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld137, ptr %xt.addr
  %ld138 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld138, ptr %x.addr
  %ld139 = load ptr, ptr %ys.addr
  %res_slot140 = alloca ptr
  %tgp141 = getelementptr i8, ptr %ld139, i64 8
  %tag142 = load i32, ptr %tgp141, align 4
  switch i32 %tag142, label %case_default16 [
      i32 0, label %case_br17
      i32 1, label %case_br18
  ]
case_br17:
  %ld143 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld143)
  %ld144 = load ptr, ptr %xs.addr
  store ptr %ld144, ptr %res_slot140
  br label %case_merge15
case_br18:
  %fp145 = getelementptr i8, ptr %ld139, i64 16
  %fv146 = load ptr, ptr %fp145, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv146, ptr %$f1370.addr
  %fp147 = getelementptr i8, ptr %ld139, i64 24
  %fv148 = load ptr, ptr %fp147, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv148, ptr %$f1371.addr
  %ld149 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld149, ptr %yt.addr
  %ld150 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld150, ptr %y.addr
  %ld151 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld151)
  %ld152 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld152)
  %ld153 = load ptr, ptr %cmp.addr
  %ld154 = load ptr, ptr %x.addr
  %ld155 = load ptr, ptr %y.addr
  %cr156 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld153, ptr %ld154, ptr %ld155)
  %$t1367.addr = alloca i64
  store i64 %cr156, ptr %$t1367.addr
  %ld157 = load i64, ptr %$t1367.addr
  %res_slot158 = alloca ptr
  %bi159 = trunc i64 %ld157 to i1
  br i1 %bi159, label %case_br21, label %case_default20
case_br21:
  %ld160 = load ptr, ptr %xt.addr
  %ld161 = load ptr, ptr %ys.addr
  %ld162 = load ptr, ptr %cmp.addr
  %cr163 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld160, ptr %ld161, ptr %ld162)
  %$t1368.addr = alloca ptr
  store ptr %cr163, ptr %$t1368.addr
  %hp164 = call ptr @march_alloc(i64 32)
  %tgp165 = getelementptr i8, ptr %hp164, i64 8
  store i32 1, ptr %tgp165, align 4
  %ld166 = load ptr, ptr %x.addr
  %fp167 = getelementptr i8, ptr %hp164, i64 16
  store ptr %ld166, ptr %fp167, align 8
  %ld168 = load ptr, ptr %$t1368.addr
  %fp169 = getelementptr i8, ptr %hp164, i64 24
  store ptr %ld168, ptr %fp169, align 8
  store ptr %hp164, ptr %res_slot158
  br label %case_merge19
case_default20:
  %ld170 = load ptr, ptr %xs.addr
  %ld171 = load ptr, ptr %yt.addr
  %ld172 = load ptr, ptr %cmp.addr
  %cr173 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld170, ptr %ld171, ptr %ld172)
  %$t1369.addr = alloca ptr
  store ptr %cr173, ptr %$t1369.addr
  %hp174 = call ptr @march_alloc(i64 32)
  %tgp175 = getelementptr i8, ptr %hp174, i64 8
  store i32 1, ptr %tgp175, align 4
  %ld176 = load ptr, ptr %y.addr
  %fp177 = getelementptr i8, ptr %hp174, i64 16
  store ptr %ld176, ptr %fp177, align 8
  %ld178 = load ptr, ptr %$t1369.addr
  %fp179 = getelementptr i8, ptr %hp174, i64 24
  store ptr %ld178, ptr %fp179, align 8
  store ptr %hp174, ptr %res_slot158
  br label %case_merge19
case_merge19:
  %case_r180 = load ptr, ptr %res_slot158
  store ptr %case_r180, ptr %res_slot140
  br label %case_merge15
case_default16:
  unreachable
case_merge15:
  %case_r181 = load ptr, ptr %res_slot140
  store ptr %case_r181, ptr %res_slot128
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r182 = load ptr, ptr %res_slot128
  ret ptr %case_r182
}

define ptr @Sort.reverse_list$List_V__4510(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp183 = call ptr @march_alloc(i64 24)
  %tgp184 = getelementptr i8, ptr %hp183, i64 8
  store i32 0, ptr %tgp184, align 4
  %fp185 = getelementptr i8, ptr %hp183, i64 16
  store ptr @go$apply$30, ptr %fp185, align 8
  %go.addr = alloca ptr
  store ptr %hp183, ptr %go.addr
  %hp186 = call ptr @march_alloc(i64 16)
  %tgp187 = getelementptr i8, ptr %hp186, i64 8
  store i32 0, ptr %tgp187, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp186, ptr %$t1355.addr
  %ld188 = load ptr, ptr %go.addr
  %fp189 = getelementptr i8, ptr %ld188, i64 16
  %fv190 = load ptr, ptr %fp189, align 8
  %ld191 = load ptr, ptr %xs.addr
  %ld192 = load ptr, ptr %$t1355.addr
  %cr193 = call ptr (ptr, ptr, ptr) %fv190(ptr %ld188, ptr %ld191, ptr %ld192)
  ret ptr %cr193
}

define ptr @Sort.drain_stack$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld194 = load ptr, ptr %stack.addr
  %cr195 = call ptr @Sort.reverse_list$List_T_List_V__5042_Int(ptr %ld194)
  %rev.addr = alloca ptr
  store ptr %cr195, ptr %rev.addr
  %hp196 = call ptr @march_alloc(i64 32)
  %tgp197 = getelementptr i8, ptr %hp196, i64 8
  store i32 0, ptr %tgp197, align 4
  %fp198 = getelementptr i8, ptr %hp196, i64 16
  store ptr @go$apply$31, ptr %fp198, align 8
  %ld199 = load ptr, ptr %cmp.addr
  %fp200 = getelementptr i8, ptr %hp196, i64 24
  store ptr %ld199, ptr %fp200, align 8
  %go.addr = alloca ptr
  store ptr %hp196, ptr %go.addr
  %ld201 = load ptr, ptr %rev.addr
  %res_slot202 = alloca ptr
  %tgp203 = getelementptr i8, ptr %ld201, i64 8
  %tag204 = load i32, ptr %tgp203, align 4
  switch i32 %tag204, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld205 = load ptr, ptr %rev.addr
  %rc206 = load i64, ptr %ld205, align 8
  %uniq207 = icmp eq i64 %rc206, 1
  %fbip_slot208 = alloca ptr
  br i1 %uniq207, label %fbip_reuse26, label %fbip_fresh27
fbip_reuse26:
  %tgp209 = getelementptr i8, ptr %ld205, i64 8
  store i32 0, ptr %tgp209, align 4
  store ptr %ld205, ptr %fbip_slot208
  br label %fbip_merge28
fbip_fresh27:
  call void @march_decrc(ptr %ld205)
  %hp210 = call ptr @march_alloc(i64 16)
  %tgp211 = getelementptr i8, ptr %hp210, i64 8
  store i32 0, ptr %tgp211, align 4
  store ptr %hp210, ptr %fbip_slot208
  br label %fbip_merge28
fbip_merge28:
  %fbip_r212 = load ptr, ptr %fbip_slot208
  store ptr %fbip_r212, ptr %res_slot202
  br label %case_merge22
case_br25:
  %fp213 = getelementptr i8, ptr %ld201, i64 16
  %fv214 = load ptr, ptr %fp213, align 8
  %$f1618.addr = alloca ptr
  store ptr %fv214, ptr %$f1618.addr
  %fp215 = getelementptr i8, ptr %ld201, i64 24
  %fv216 = load ptr, ptr %fp215, align 8
  %$f1619.addr = alloca ptr
  store ptr %fv216, ptr %$f1619.addr
  %freed217 = call i64 @march_decrc_freed(ptr %ld201)
  %freed_b218 = icmp ne i64 %freed217, 0
  br i1 %freed_b218, label %br_unique29, label %br_shared30
br_shared30:
  call void @march_incrc(ptr %fv216)
  call void @march_incrc(ptr %fv214)
  br label %br_body31
br_unique29:
  br label %br_body31
br_body31:
  %ld219 = load ptr, ptr %$f1618.addr
  %res_slot220 = alloca ptr
  %tgp221 = getelementptr i8, ptr %ld219, i64 8
  %tag222 = load i32, ptr %tgp221, align 4
  switch i32 %tag222, label %case_default33 [
      i32 0, label %case_br34
  ]
case_br34:
  %fp223 = getelementptr i8, ptr %ld219, i64 16
  %fv224 = load ptr, ptr %fp223, align 8
  %$f1620.addr = alloca ptr
  store ptr %fv224, ptr %$f1620.addr
  %fp225 = getelementptr i8, ptr %ld219, i64 24
  %fv226 = load ptr, ptr %fp225, align 8
  %$f1621.addr = alloca ptr
  store ptr %fv226, ptr %$f1621.addr
  %freed227 = call i64 @march_decrc_freed(ptr %ld219)
  %freed_b228 = icmp ne i64 %freed227, 0
  br i1 %freed_b228, label %br_unique35, label %br_shared36
br_shared36:
  call void @march_incrc(ptr %fv226)
  call void @march_incrc(ptr %fv224)
  br label %br_body37
br_unique35:
  br label %br_body37
br_body37:
  %ld229 = load ptr, ptr %$f1619.addr
  %rest.addr = alloca ptr
  store ptr %ld229, ptr %rest.addr
  %ld230 = load ptr, ptr %$f1620.addr
  %first.addr = alloca ptr
  store ptr %ld230, ptr %first.addr
  %ld231 = load ptr, ptr %go.addr
  %fp232 = getelementptr i8, ptr %ld231, i64 16
  %fv233 = load ptr, ptr %fp232, align 8
  %ld234 = load ptr, ptr %rest.addr
  %ld235 = load ptr, ptr %first.addr
  %cr236 = call ptr (ptr, ptr, ptr) %fv233(ptr %ld231, ptr %ld234, ptr %ld235)
  store ptr %cr236, ptr %res_slot220
  br label %case_merge32
case_default33:
  unreachable
case_merge32:
  %case_r237 = load ptr, ptr %res_slot220
  store ptr %case_r237, ptr %res_slot202
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r238 = load ptr, ptr %res_slot202
  ret ptr %case_r238
}

define ptr @Sort.enforce_invariants$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld239 = load ptr, ptr %stack.addr
  %res_slot240 = alloca ptr
  %tgp241 = getelementptr i8, ptr %ld239, i64 8
  %tag242 = load i32, ptr %tgp241, align 4
  switch i32 %tag242, label %case_default39 [
      i32 1, label %case_br40
  ]
case_br40:
  %fp243 = getelementptr i8, ptr %ld239, i64 16
  %fv244 = load ptr, ptr %fp243, align 8
  %$f1597.addr = alloca ptr
  store ptr %fv244, ptr %$f1597.addr
  %fp245 = getelementptr i8, ptr %ld239, i64 24
  %fv246 = load ptr, ptr %fp245, align 8
  %$f1598.addr = alloca ptr
  store ptr %fv246, ptr %$f1598.addr
  %ld247 = load ptr, ptr %$f1597.addr
  %res_slot248 = alloca ptr
  %tgp249 = getelementptr i8, ptr %ld247, i64 8
  %tag250 = load i32, ptr %tgp249, align 4
  switch i32 %tag250, label %case_default42 [
      i32 0, label %case_br43
  ]
case_br43:
  %fp251 = getelementptr i8, ptr %ld247, i64 16
  %fv252 = load ptr, ptr %fp251, align 8
  %$f1599.addr = alloca ptr
  store ptr %fv252, ptr %$f1599.addr
  %fp253 = getelementptr i8, ptr %ld247, i64 24
  %fv254 = load ptr, ptr %fp253, align 8
  %$f1600.addr = alloca ptr
  store ptr %fv254, ptr %$f1600.addr
  %freed255 = call i64 @march_decrc_freed(ptr %ld247)
  %freed_b256 = icmp ne i64 %freed255, 0
  br i1 %freed_b256, label %br_unique44, label %br_shared45
br_shared45:
  call void @march_incrc(ptr %fv254)
  call void @march_incrc(ptr %fv252)
  br label %br_body46
br_unique44:
  br label %br_body46
br_body46:
  %ld257 = load ptr, ptr %$f1598.addr
  %res_slot258 = alloca ptr
  %tgp259 = getelementptr i8, ptr %ld257, i64 8
  %tag260 = load i32, ptr %tgp259, align 4
  switch i32 %tag260, label %case_default48 [
      i32 0, label %case_br49
  ]
case_br49:
  %fp261 = getelementptr i8, ptr %ld257, i64 16
  %fv262 = load ptr, ptr %fp261, align 8
  %$f1605.addr = alloca ptr
  store ptr %fv262, ptr %$f1605.addr
  %fp263 = getelementptr i8, ptr %ld257, i64 24
  %fv264 = load ptr, ptr %fp263, align 8
  %$f1606.addr = alloca ptr
  store ptr %fv264, ptr %$f1606.addr
  %ld265 = load ptr, ptr %$f1605.addr
  %res_slot266 = alloca ptr
  %tgp267 = getelementptr i8, ptr %ld265, i64 8
  %tag268 = load i32, ptr %tgp267, align 4
  switch i32 %tag268, label %case_default51 [
      i32 0, label %case_br52
  ]
case_br52:
  %fp269 = getelementptr i8, ptr %ld265, i64 16
  %fv270 = load ptr, ptr %fp269, align 8
  %$f1607.addr = alloca ptr
  store ptr %fv270, ptr %$f1607.addr
  %fp271 = getelementptr i8, ptr %ld265, i64 24
  %fv272 = load ptr, ptr %fp271, align 8
  %$f1608.addr = alloca ptr
  store ptr %fv272, ptr %$f1608.addr
  %freed273 = call i64 @march_decrc_freed(ptr %ld265)
  %freed_b274 = icmp ne i64 %freed273, 0
  br i1 %freed_b274, label %br_unique53, label %br_shared54
br_shared54:
  call void @march_incrc(ptr %fv272)
  call void @march_incrc(ptr %fv270)
  br label %br_body55
br_unique53:
  br label %br_body55
br_body55:
  %ld275 = load ptr, ptr %$f1606.addr
  %res_slot276 = alloca ptr
  %tgp277 = getelementptr i8, ptr %ld275, i64 8
  %tag278 = load i32, ptr %tgp277, align 4
  switch i32 %tag278, label %case_default57 [
      i32 0, label %case_br58
  ]
case_br58:
  %fp279 = getelementptr i8, ptr %ld275, i64 16
  %fv280 = load ptr, ptr %fp279, align 8
  %$f1609.addr = alloca ptr
  store ptr %fv280, ptr %$f1609.addr
  %fp281 = getelementptr i8, ptr %ld275, i64 24
  %fv282 = load ptr, ptr %fp281, align 8
  %$f1610.addr = alloca ptr
  store ptr %fv282, ptr %$f1610.addr
  %freed283 = call i64 @march_decrc_freed(ptr %ld275)
  %freed_b284 = icmp ne i64 %freed283, 0
  br i1 %freed_b284, label %br_unique59, label %br_shared60
br_shared60:
  call void @march_incrc(ptr %fv282)
  call void @march_incrc(ptr %fv280)
  br label %br_body61
br_unique59:
  br label %br_body61
br_body61:
  %ld285 = load ptr, ptr %$f1609.addr
  %res_slot286 = alloca ptr
  %tgp287 = getelementptr i8, ptr %ld285, i64 8
  %tag288 = load i32, ptr %tgp287, align 4
  switch i32 %tag288, label %case_default63 [
      i32 0, label %case_br64
  ]
case_br64:
  %fp289 = getelementptr i8, ptr %ld285, i64 16
  %fv290 = load ptr, ptr %fp289, align 8
  %$f1611.addr = alloca ptr
  store ptr %fv290, ptr %$f1611.addr
  %fp291 = getelementptr i8, ptr %ld285, i64 24
  %fv292 = load ptr, ptr %fp291, align 8
  %$f1612.addr = alloca ptr
  store ptr %fv292, ptr %$f1612.addr
  %freed293 = call i64 @march_decrc_freed(ptr %ld285)
  %freed_b294 = icmp ne i64 %freed293, 0
  br i1 %freed_b294, label %br_unique65, label %br_shared66
br_shared66:
  call void @march_incrc(ptr %fv292)
  call void @march_incrc(ptr %fv290)
  br label %br_body67
br_unique65:
  br label %br_body67
br_body67:
  %ld295 = load ptr, ptr %$f1610.addr
  %rest.addr = alloca ptr
  store ptr %ld295, ptr %rest.addr
  %ld296 = load ptr, ptr %$f1612.addr
  %zn.addr = alloca ptr
  store ptr %ld296, ptr %zn.addr
  %ld297 = load ptr, ptr %$f1611.addr
  %z.addr = alloca ptr
  store ptr %ld297, ptr %z.addr
  %ld298 = load ptr, ptr %$f1608.addr
  %yn.addr = alloca ptr
  store ptr %ld298, ptr %yn.addr
  %ld299 = load ptr, ptr %$f1607.addr
  %y.addr = alloca ptr
  store ptr %ld299, ptr %y.addr
  %ld300 = load ptr, ptr %$f1600.addr
  %xn.addr = alloca ptr
  store ptr %ld300, ptr %xn.addr
  %ld301 = load ptr, ptr %$f1599.addr
  %x.addr = alloca ptr
  store ptr %ld301, ptr %x.addr
  %ld302 = load ptr, ptr %yn.addr
  %ld303 = load ptr, ptr %xn.addr
  %cv306 = ptrtoint ptr %ld302 to i64
  %cv307 = ptrtoint ptr %ld303 to i64
  %cmp304 = icmp sle i64 %cv306, %cv307
  %ar305 = zext i1 %cmp304 to i64
  %$t1580.addr = alloca i64
  store i64 %ar305, ptr %$t1580.addr
  %ld308 = load i64, ptr %$t1580.addr
  %res_slot309 = alloca ptr
  %bi310 = trunc i64 %ld308 to i1
  br i1 %bi310, label %case_br70, label %case_default69
case_br70:
  %ld311 = load ptr, ptr %y.addr
  %a_i38.addr = alloca ptr
  store ptr %ld311, ptr %a_i38.addr
  %ld312 = load ptr, ptr %x.addr
  %b_i39.addr = alloca ptr
  store ptr %ld312, ptr %b_i39.addr
  %ld313 = load ptr, ptr %cmp.addr
  %cmp_i40.addr = alloca ptr
  store ptr %ld313, ptr %cmp_i40.addr
  %ld314 = load ptr, ptr %a_i38.addr
  %ld315 = load ptr, ptr %b_i39.addr
  %ld316 = load ptr, ptr %cmp_i40.addr
  %cr317 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld314, ptr %ld315, ptr %ld316)
  %merged.addr = alloca ptr
  store ptr %cr317, ptr %merged.addr
  %ld318 = load ptr, ptr %xn.addr
  %cv319 = ptrtoint ptr %ld318 to i64
  %ld320 = load ptr, ptr %yn.addr
  %cv321 = ptrtoint ptr %ld320 to i64
  %ar322 = add i64 %cv319, %cv321
  %$t1581.addr = alloca i64
  store i64 %ar322, ptr %$t1581.addr
  %hp323 = call ptr @march_alloc(i64 32)
  %tgp324 = getelementptr i8, ptr %hp323, i64 8
  store i32 0, ptr %tgp324, align 4
  %ld325 = load ptr, ptr %merged.addr
  %fp326 = getelementptr i8, ptr %hp323, i64 16
  store ptr %ld325, ptr %fp326, align 8
  %ld327 = load i64, ptr %$t1581.addr
  %fp328 = getelementptr i8, ptr %hp323, i64 24
  store i64 %ld327, ptr %fp328, align 8
  %$t1582.addr = alloca ptr
  store ptr %hp323, ptr %$t1582.addr
  %hp329 = call ptr @march_alloc(i64 32)
  %tgp330 = getelementptr i8, ptr %hp329, i64 8
  store i32 0, ptr %tgp330, align 4
  %ld331 = load ptr, ptr %z.addr
  %fp332 = getelementptr i8, ptr %hp329, i64 16
  store ptr %ld331, ptr %fp332, align 8
  %ld333 = load ptr, ptr %zn.addr
  %fp334 = getelementptr i8, ptr %hp329, i64 24
  store ptr %ld333, ptr %fp334, align 8
  %$t1583.addr = alloca ptr
  store ptr %hp329, ptr %$t1583.addr
  %hp335 = call ptr @march_alloc(i64 32)
  %tgp336 = getelementptr i8, ptr %hp335, i64 8
  store i32 1, ptr %tgp336, align 4
  %ld337 = load ptr, ptr %$t1583.addr
  %fp338 = getelementptr i8, ptr %hp335, i64 16
  store ptr %ld337, ptr %fp338, align 8
  %ld339 = load ptr, ptr %rest.addr
  %fp340 = getelementptr i8, ptr %hp335, i64 24
  store ptr %ld339, ptr %fp340, align 8
  %$t1584.addr = alloca ptr
  store ptr %hp335, ptr %$t1584.addr
  %hp341 = call ptr @march_alloc(i64 32)
  %tgp342 = getelementptr i8, ptr %hp341, i64 8
  store i32 1, ptr %tgp342, align 4
  %ld343 = load ptr, ptr %$t1582.addr
  %fp344 = getelementptr i8, ptr %hp341, i64 16
  store ptr %ld343, ptr %fp344, align 8
  %ld345 = load ptr, ptr %$t1584.addr
  %fp346 = getelementptr i8, ptr %hp341, i64 24
  store ptr %ld345, ptr %fp346, align 8
  %$t1585.addr = alloca ptr
  store ptr %hp341, ptr %$t1585.addr
  %ld347 = load ptr, ptr %$t1585.addr
  %ld348 = load ptr, ptr %cmp.addr
  %cr349 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld347, ptr %ld348)
  store ptr %cr349, ptr %res_slot309
  br label %case_merge68
case_default69:
  %ld350 = load ptr, ptr %yn.addr
  %cv351 = ptrtoint ptr %ld350 to i64
  %ld352 = load ptr, ptr %xn.addr
  %cv353 = ptrtoint ptr %ld352 to i64
  %ar354 = add i64 %cv351, %cv353
  %$t1586.addr = alloca i64
  store i64 %ar354, ptr %$t1586.addr
  %ld355 = load ptr, ptr %zn.addr
  %ld356 = load i64, ptr %$t1586.addr
  %cv359 = ptrtoint ptr %ld355 to i64
  %cmp357 = icmp sle i64 %cv359, %ld356
  %ar358 = zext i1 %cmp357 to i64
  %$t1587.addr = alloca i64
  store i64 %ar358, ptr %$t1587.addr
  %ld360 = load i64, ptr %$t1587.addr
  %res_slot361 = alloca ptr
  %bi362 = trunc i64 %ld360 to i1
  br i1 %bi362, label %case_br73, label %case_default72
case_br73:
  %ld363 = load ptr, ptr %z.addr
  %a_i35.addr = alloca ptr
  store ptr %ld363, ptr %a_i35.addr
  %ld364 = load ptr, ptr %y.addr
  %b_i36.addr = alloca ptr
  store ptr %ld364, ptr %b_i36.addr
  %ld365 = load ptr, ptr %cmp.addr
  %cmp_i37.addr = alloca ptr
  store ptr %ld365, ptr %cmp_i37.addr
  %ld366 = load ptr, ptr %a_i35.addr
  %ld367 = load ptr, ptr %b_i36.addr
  %ld368 = load ptr, ptr %cmp_i37.addr
  %cr369 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld366, ptr %ld367, ptr %ld368)
  %merged_1.addr = alloca ptr
  store ptr %cr369, ptr %merged_1.addr
  %hp370 = call ptr @march_alloc(i64 32)
  %tgp371 = getelementptr i8, ptr %hp370, i64 8
  store i32 0, ptr %tgp371, align 4
  %ld372 = load ptr, ptr %x.addr
  %fp373 = getelementptr i8, ptr %hp370, i64 16
  store ptr %ld372, ptr %fp373, align 8
  %ld374 = load ptr, ptr %xn.addr
  %fp375 = getelementptr i8, ptr %hp370, i64 24
  store ptr %ld374, ptr %fp375, align 8
  %$t1588.addr = alloca ptr
  store ptr %hp370, ptr %$t1588.addr
  %ld376 = load ptr, ptr %yn.addr
  %cv377 = ptrtoint ptr %ld376 to i64
  %ld378 = load ptr, ptr %zn.addr
  %cv379 = ptrtoint ptr %ld378 to i64
  %ar380 = add i64 %cv377, %cv379
  %$t1589.addr = alloca i64
  store i64 %ar380, ptr %$t1589.addr
  %hp381 = call ptr @march_alloc(i64 32)
  %tgp382 = getelementptr i8, ptr %hp381, i64 8
  store i32 0, ptr %tgp382, align 4
  %ld383 = load ptr, ptr %merged_1.addr
  %fp384 = getelementptr i8, ptr %hp381, i64 16
  store ptr %ld383, ptr %fp384, align 8
  %ld385 = load i64, ptr %$t1589.addr
  %fp386 = getelementptr i8, ptr %hp381, i64 24
  store i64 %ld385, ptr %fp386, align 8
  %$t1590.addr = alloca ptr
  store ptr %hp381, ptr %$t1590.addr
  %hp387 = call ptr @march_alloc(i64 32)
  %tgp388 = getelementptr i8, ptr %hp387, i64 8
  store i32 1, ptr %tgp388, align 4
  %ld389 = load ptr, ptr %$t1590.addr
  %fp390 = getelementptr i8, ptr %hp387, i64 16
  store ptr %ld389, ptr %fp390, align 8
  %ld391 = load ptr, ptr %rest.addr
  %fp392 = getelementptr i8, ptr %hp387, i64 24
  store ptr %ld391, ptr %fp392, align 8
  %$t1591.addr = alloca ptr
  store ptr %hp387, ptr %$t1591.addr
  %hp393 = call ptr @march_alloc(i64 32)
  %tgp394 = getelementptr i8, ptr %hp393, i64 8
  store i32 1, ptr %tgp394, align 4
  %ld395 = load ptr, ptr %$t1588.addr
  %fp396 = getelementptr i8, ptr %hp393, i64 16
  store ptr %ld395, ptr %fp396, align 8
  %ld397 = load ptr, ptr %$t1591.addr
  %fp398 = getelementptr i8, ptr %hp393, i64 24
  store ptr %ld397, ptr %fp398, align 8
  %$t1592.addr = alloca ptr
  store ptr %hp393, ptr %$t1592.addr
  %ld399 = load ptr, ptr %$t1592.addr
  %ld400 = load ptr, ptr %cmp.addr
  %cr401 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld399, ptr %ld400)
  store ptr %cr401, ptr %res_slot361
  br label %case_merge71
case_default72:
  %ld402 = load ptr, ptr %stack.addr
  store ptr %ld402, ptr %res_slot361
  br label %case_merge71
case_merge71:
  %case_r403 = load ptr, ptr %res_slot361
  store ptr %case_r403, ptr %res_slot309
  br label %case_merge68
case_merge68:
  %case_r404 = load ptr, ptr %res_slot309
  store ptr %case_r404, ptr %res_slot286
  br label %case_merge62
case_default63:
  %ld405 = load ptr, ptr %$f1609.addr
  call void @march_decrc(ptr %ld405)
  %ld406 = load ptr, ptr %$f1598.addr
  %res_slot407 = alloca ptr
  %tgp408 = getelementptr i8, ptr %ld406, i64 8
  %tag409 = load i32, ptr %tgp408, align 4
  switch i32 %tag409, label %case_default75 [
      i32 0, label %case_br76
  ]
case_br76:
  %fp410 = getelementptr i8, ptr %ld406, i64 16
  %fv411 = load ptr, ptr %fp410, align 8
  %$f1601.addr = alloca ptr
  store ptr %fv411, ptr %$f1601.addr
  %fp412 = getelementptr i8, ptr %ld406, i64 24
  %fv413 = load ptr, ptr %fp412, align 8
  %$f1602.addr = alloca ptr
  store ptr %fv413, ptr %$f1602.addr
  %freed414 = call i64 @march_decrc_freed(ptr %ld406)
  %freed_b415 = icmp ne i64 %freed414, 0
  br i1 %freed_b415, label %br_unique77, label %br_shared78
br_shared78:
  call void @march_incrc(ptr %fv413)
  call void @march_incrc(ptr %fv411)
  br label %br_body79
br_unique77:
  br label %br_body79
br_body79:
  %ld416 = load ptr, ptr %$f1601.addr
  %res_slot417 = alloca ptr
  %tgp418 = getelementptr i8, ptr %ld416, i64 8
  %tag419 = load i32, ptr %tgp418, align 4
  switch i32 %tag419, label %case_default81 [
      i32 0, label %case_br82
  ]
case_br82:
  %fp420 = getelementptr i8, ptr %ld416, i64 16
  %fv421 = load ptr, ptr %fp420, align 8
  %$f1603.addr = alloca ptr
  store ptr %fv421, ptr %$f1603.addr
  %fp422 = getelementptr i8, ptr %ld416, i64 24
  %fv423 = load ptr, ptr %fp422, align 8
  %$f1604.addr = alloca ptr
  store ptr %fv423, ptr %$f1604.addr
  %freed424 = call i64 @march_decrc_freed(ptr %ld416)
  %freed_b425 = icmp ne i64 %freed424, 0
  br i1 %freed_b425, label %br_unique83, label %br_shared84
br_shared84:
  call void @march_incrc(ptr %fv423)
  call void @march_incrc(ptr %fv421)
  br label %br_body85
br_unique83:
  br label %br_body85
br_body85:
  %ld426 = load ptr, ptr %$f1602.addr
  %res_slot427 = alloca ptr
  %tgp428 = getelementptr i8, ptr %ld426, i64 8
  %tag429 = load i32, ptr %tgp428, align 4
  switch i32 %tag429, label %case_default87 [
      i32 0, label %case_br88
  ]
case_br88:
  %ld430 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld430)
  %ld431 = load ptr, ptr %$f1604.addr
  %yn_1.addr = alloca ptr
  store ptr %ld431, ptr %yn_1.addr
  %ld432 = load ptr, ptr %$f1603.addr
  %y_1.addr = alloca ptr
  store ptr %ld432, ptr %y_1.addr
  %ld433 = load ptr, ptr %$f1600.addr
  %xn_1.addr = alloca ptr
  store ptr %ld433, ptr %xn_1.addr
  %ld434 = load ptr, ptr %$f1599.addr
  %x_1.addr = alloca ptr
  store ptr %ld434, ptr %x_1.addr
  %ld435 = load ptr, ptr %yn_1.addr
  %ld436 = load ptr, ptr %xn_1.addr
  %cv439 = ptrtoint ptr %ld435 to i64
  %cv440 = ptrtoint ptr %ld436 to i64
  %cmp437 = icmp sle i64 %cv439, %cv440
  %ar438 = zext i1 %cmp437 to i64
  %$t1593.addr = alloca i64
  store i64 %ar438, ptr %$t1593.addr
  %ld441 = load i64, ptr %$t1593.addr
  %res_slot442 = alloca ptr
  %bi443 = trunc i64 %ld441 to i1
  br i1 %bi443, label %case_br91, label %case_default90
case_br91:
  %ld444 = load ptr, ptr %y_1.addr
  %a_i32.addr = alloca ptr
  store ptr %ld444, ptr %a_i32.addr
  %ld445 = load ptr, ptr %x_1.addr
  %b_i33.addr = alloca ptr
  store ptr %ld445, ptr %b_i33.addr
  %ld446 = load ptr, ptr %cmp.addr
  %cmp_i34.addr = alloca ptr
  store ptr %ld446, ptr %cmp_i34.addr
  %ld447 = load ptr, ptr %a_i32.addr
  %ld448 = load ptr, ptr %b_i33.addr
  %ld449 = load ptr, ptr %cmp_i34.addr
  %cr450 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld447, ptr %ld448, ptr %ld449)
  %merged_2.addr = alloca ptr
  store ptr %cr450, ptr %merged_2.addr
  %ld451 = load ptr, ptr %xn_1.addr
  %cv452 = ptrtoint ptr %ld451 to i64
  %ld453 = load ptr, ptr %yn_1.addr
  %cv454 = ptrtoint ptr %ld453 to i64
  %ar455 = add i64 %cv452, %cv454
  %$t1594.addr = alloca i64
  store i64 %ar455, ptr %$t1594.addr
  %hp456 = call ptr @march_alloc(i64 32)
  %tgp457 = getelementptr i8, ptr %hp456, i64 8
  store i32 0, ptr %tgp457, align 4
  %ld458 = load ptr, ptr %merged_2.addr
  %fp459 = getelementptr i8, ptr %hp456, i64 16
  store ptr %ld458, ptr %fp459, align 8
  %ld460 = load i64, ptr %$t1594.addr
  %fp461 = getelementptr i8, ptr %hp456, i64 24
  store i64 %ld460, ptr %fp461, align 8
  %$t1595.addr = alloca ptr
  store ptr %hp456, ptr %$t1595.addr
  %hp462 = call ptr @march_alloc(i64 16)
  %tgp463 = getelementptr i8, ptr %hp462, i64 8
  store i32 0, ptr %tgp463, align 4
  %$t1596.addr = alloca ptr
  store ptr %hp462, ptr %$t1596.addr
  %hp464 = call ptr @march_alloc(i64 32)
  %tgp465 = getelementptr i8, ptr %hp464, i64 8
  store i32 1, ptr %tgp465, align 4
  %ld466 = load ptr, ptr %$t1595.addr
  %fp467 = getelementptr i8, ptr %hp464, i64 16
  store ptr %ld466, ptr %fp467, align 8
  %ld468 = load ptr, ptr %$t1596.addr
  %fp469 = getelementptr i8, ptr %hp464, i64 24
  store ptr %ld468, ptr %fp469, align 8
  store ptr %hp464, ptr %res_slot442
  br label %case_merge89
case_default90:
  %ld470 = load ptr, ptr %stack.addr
  store ptr %ld470, ptr %res_slot442
  br label %case_merge89
case_merge89:
  %case_r471 = load ptr, ptr %res_slot442
  store ptr %case_r471, ptr %res_slot427
  br label %case_merge86
case_default87:
  %ld472 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld472)
  %ld473 = load ptr, ptr %stack.addr
  store ptr %ld473, ptr %res_slot427
  br label %case_merge86
case_merge86:
  %case_r474 = load ptr, ptr %res_slot427
  store ptr %case_r474, ptr %res_slot417
  br label %case_merge80
case_default81:
  %ld475 = load ptr, ptr %$f1601.addr
  call void @march_decrc(ptr %ld475)
  %ld476 = load ptr, ptr %stack.addr
  store ptr %ld476, ptr %res_slot417
  br label %case_merge80
case_merge80:
  %case_r477 = load ptr, ptr %res_slot417
  store ptr %case_r477, ptr %res_slot407
  br label %case_merge74
case_default75:
  %ld478 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld478)
  %ld479 = load ptr, ptr %stack.addr
  store ptr %ld479, ptr %res_slot407
  br label %case_merge74
case_merge74:
  %case_r480 = load ptr, ptr %res_slot407
  store ptr %case_r480, ptr %res_slot286
  br label %case_merge62
case_merge62:
  %case_r481 = load ptr, ptr %res_slot286
  store ptr %case_r481, ptr %res_slot276
  br label %case_merge56
case_default57:
  %ld482 = load ptr, ptr %$f1606.addr
  call void @march_decrc(ptr %ld482)
  %ld483 = load ptr, ptr %$f1598.addr
  %res_slot484 = alloca ptr
  %tgp485 = getelementptr i8, ptr %ld483, i64 8
  %tag486 = load i32, ptr %tgp485, align 4
  switch i32 %tag486, label %case_default93 [
      i32 0, label %case_br94
  ]
case_br94:
  %fp487 = getelementptr i8, ptr %ld483, i64 16
  %fv488 = load ptr, ptr %fp487, align 8
  %$f1601_1.addr = alloca ptr
  store ptr %fv488, ptr %$f1601_1.addr
  %fp489 = getelementptr i8, ptr %ld483, i64 24
  %fv490 = load ptr, ptr %fp489, align 8
  %$f1602_1.addr = alloca ptr
  store ptr %fv490, ptr %$f1602_1.addr
  %freed491 = call i64 @march_decrc_freed(ptr %ld483)
  %freed_b492 = icmp ne i64 %freed491, 0
  br i1 %freed_b492, label %br_unique95, label %br_shared96
br_shared96:
  call void @march_incrc(ptr %fv490)
  call void @march_incrc(ptr %fv488)
  br label %br_body97
br_unique95:
  br label %br_body97
br_body97:
  %ld493 = load ptr, ptr %$f1601_1.addr
  %res_slot494 = alloca ptr
  %tgp495 = getelementptr i8, ptr %ld493, i64 8
  %tag496 = load i32, ptr %tgp495, align 4
  switch i32 %tag496, label %case_default99 [
      i32 0, label %case_br100
  ]
case_br100:
  %fp497 = getelementptr i8, ptr %ld493, i64 16
  %fv498 = load ptr, ptr %fp497, align 8
  %$f1603_1.addr = alloca ptr
  store ptr %fv498, ptr %$f1603_1.addr
  %fp499 = getelementptr i8, ptr %ld493, i64 24
  %fv500 = load ptr, ptr %fp499, align 8
  %$f1604_1.addr = alloca ptr
  store ptr %fv500, ptr %$f1604_1.addr
  %freed501 = call i64 @march_decrc_freed(ptr %ld493)
  %freed_b502 = icmp ne i64 %freed501, 0
  br i1 %freed_b502, label %br_unique101, label %br_shared102
br_shared102:
  call void @march_incrc(ptr %fv500)
  call void @march_incrc(ptr %fv498)
  br label %br_body103
br_unique101:
  br label %br_body103
br_body103:
  %ld503 = load ptr, ptr %$f1602_1.addr
  %res_slot504 = alloca ptr
  %tgp505 = getelementptr i8, ptr %ld503, i64 8
  %tag506 = load i32, ptr %tgp505, align 4
  switch i32 %tag506, label %case_default105 [
      i32 0, label %case_br106
  ]
case_br106:
  %ld507 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld507)
  %ld508 = load ptr, ptr %$f1604_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld508, ptr %yn_2.addr
  %ld509 = load ptr, ptr %$f1603_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld509, ptr %y_2.addr
  %ld510 = load ptr, ptr %$f1600.addr
  %xn_2.addr = alloca ptr
  store ptr %ld510, ptr %xn_2.addr
  %ld511 = load ptr, ptr %$f1599.addr
  %x_2.addr = alloca ptr
  store ptr %ld511, ptr %x_2.addr
  %ld512 = load ptr, ptr %yn_2.addr
  %ld513 = load ptr, ptr %xn_2.addr
  %cv516 = ptrtoint ptr %ld512 to i64
  %cv517 = ptrtoint ptr %ld513 to i64
  %cmp514 = icmp sle i64 %cv516, %cv517
  %ar515 = zext i1 %cmp514 to i64
  %$t1593_1.addr = alloca i64
  store i64 %ar515, ptr %$t1593_1.addr
  %ld518 = load i64, ptr %$t1593_1.addr
  %res_slot519 = alloca ptr
  %bi520 = trunc i64 %ld518 to i1
  br i1 %bi520, label %case_br109, label %case_default108
case_br109:
  %ld521 = load ptr, ptr %y_2.addr
  %a_i29.addr = alloca ptr
  store ptr %ld521, ptr %a_i29.addr
  %ld522 = load ptr, ptr %x_2.addr
  %b_i30.addr = alloca ptr
  store ptr %ld522, ptr %b_i30.addr
  %ld523 = load ptr, ptr %cmp.addr
  %cmp_i31.addr = alloca ptr
  store ptr %ld523, ptr %cmp_i31.addr
  %ld524 = load ptr, ptr %a_i29.addr
  %ld525 = load ptr, ptr %b_i30.addr
  %ld526 = load ptr, ptr %cmp_i31.addr
  %cr527 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld524, ptr %ld525, ptr %ld526)
  %merged_3.addr = alloca ptr
  store ptr %cr527, ptr %merged_3.addr
  %ld528 = load ptr, ptr %xn_2.addr
  %cv529 = ptrtoint ptr %ld528 to i64
  %ld530 = load ptr, ptr %yn_2.addr
  %cv531 = ptrtoint ptr %ld530 to i64
  %ar532 = add i64 %cv529, %cv531
  %$t1594_1.addr = alloca i64
  store i64 %ar532, ptr %$t1594_1.addr
  %hp533 = call ptr @march_alloc(i64 32)
  %tgp534 = getelementptr i8, ptr %hp533, i64 8
  store i32 0, ptr %tgp534, align 4
  %ld535 = load ptr, ptr %merged_3.addr
  %fp536 = getelementptr i8, ptr %hp533, i64 16
  store ptr %ld535, ptr %fp536, align 8
  %ld537 = load i64, ptr %$t1594_1.addr
  %fp538 = getelementptr i8, ptr %hp533, i64 24
  store i64 %ld537, ptr %fp538, align 8
  %$t1595_1.addr = alloca ptr
  store ptr %hp533, ptr %$t1595_1.addr
  %hp539 = call ptr @march_alloc(i64 16)
  %tgp540 = getelementptr i8, ptr %hp539, i64 8
  store i32 0, ptr %tgp540, align 4
  %$t1596_1.addr = alloca ptr
  store ptr %hp539, ptr %$t1596_1.addr
  %hp541 = call ptr @march_alloc(i64 32)
  %tgp542 = getelementptr i8, ptr %hp541, i64 8
  store i32 1, ptr %tgp542, align 4
  %ld543 = load ptr, ptr %$t1595_1.addr
  %fp544 = getelementptr i8, ptr %hp541, i64 16
  store ptr %ld543, ptr %fp544, align 8
  %ld545 = load ptr, ptr %$t1596_1.addr
  %fp546 = getelementptr i8, ptr %hp541, i64 24
  store ptr %ld545, ptr %fp546, align 8
  store ptr %hp541, ptr %res_slot519
  br label %case_merge107
case_default108:
  %ld547 = load ptr, ptr %stack.addr
  store ptr %ld547, ptr %res_slot519
  br label %case_merge107
case_merge107:
  %case_r548 = load ptr, ptr %res_slot519
  store ptr %case_r548, ptr %res_slot504
  br label %case_merge104
case_default105:
  %ld549 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld549)
  %ld550 = load ptr, ptr %stack.addr
  store ptr %ld550, ptr %res_slot504
  br label %case_merge104
case_merge104:
  %case_r551 = load ptr, ptr %res_slot504
  store ptr %case_r551, ptr %res_slot494
  br label %case_merge98
case_default99:
  %ld552 = load ptr, ptr %$f1601_1.addr
  call void @march_decrc(ptr %ld552)
  %ld553 = load ptr, ptr %stack.addr
  store ptr %ld553, ptr %res_slot494
  br label %case_merge98
case_merge98:
  %case_r554 = load ptr, ptr %res_slot494
  store ptr %case_r554, ptr %res_slot484
  br label %case_merge92
case_default93:
  %ld555 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld555)
  %ld556 = load ptr, ptr %stack.addr
  store ptr %ld556, ptr %res_slot484
  br label %case_merge92
case_merge92:
  %case_r557 = load ptr, ptr %res_slot484
  store ptr %case_r557, ptr %res_slot276
  br label %case_merge56
case_merge56:
  %case_r558 = load ptr, ptr %res_slot276
  store ptr %case_r558, ptr %res_slot266
  br label %case_merge50
case_default51:
  %ld559 = load ptr, ptr %$f1605.addr
  call void @march_decrc(ptr %ld559)
  %ld560 = load ptr, ptr %$f1598.addr
  %res_slot561 = alloca ptr
  %tgp562 = getelementptr i8, ptr %ld560, i64 8
  %tag563 = load i32, ptr %tgp562, align 4
  switch i32 %tag563, label %case_default111 [
      i32 0, label %case_br112
  ]
case_br112:
  %fp564 = getelementptr i8, ptr %ld560, i64 16
  %fv565 = load ptr, ptr %fp564, align 8
  %$f1601_2.addr = alloca ptr
  store ptr %fv565, ptr %$f1601_2.addr
  %fp566 = getelementptr i8, ptr %ld560, i64 24
  %fv567 = load ptr, ptr %fp566, align 8
  %$f1602_2.addr = alloca ptr
  store ptr %fv567, ptr %$f1602_2.addr
  %freed568 = call i64 @march_decrc_freed(ptr %ld560)
  %freed_b569 = icmp ne i64 %freed568, 0
  br i1 %freed_b569, label %br_unique113, label %br_shared114
br_shared114:
  call void @march_incrc(ptr %fv567)
  call void @march_incrc(ptr %fv565)
  br label %br_body115
br_unique113:
  br label %br_body115
br_body115:
  %ld570 = load ptr, ptr %$f1601_2.addr
  %res_slot571 = alloca ptr
  %tgp572 = getelementptr i8, ptr %ld570, i64 8
  %tag573 = load i32, ptr %tgp572, align 4
  switch i32 %tag573, label %case_default117 [
      i32 0, label %case_br118
  ]
case_br118:
  %fp574 = getelementptr i8, ptr %ld570, i64 16
  %fv575 = load ptr, ptr %fp574, align 8
  %$f1603_2.addr = alloca ptr
  store ptr %fv575, ptr %$f1603_2.addr
  %fp576 = getelementptr i8, ptr %ld570, i64 24
  %fv577 = load ptr, ptr %fp576, align 8
  %$f1604_2.addr = alloca ptr
  store ptr %fv577, ptr %$f1604_2.addr
  %freed578 = call i64 @march_decrc_freed(ptr %ld570)
  %freed_b579 = icmp ne i64 %freed578, 0
  br i1 %freed_b579, label %br_unique119, label %br_shared120
br_shared120:
  call void @march_incrc(ptr %fv577)
  call void @march_incrc(ptr %fv575)
  br label %br_body121
br_unique119:
  br label %br_body121
br_body121:
  %ld580 = load ptr, ptr %$f1602_2.addr
  %res_slot581 = alloca ptr
  %tgp582 = getelementptr i8, ptr %ld580, i64 8
  %tag583 = load i32, ptr %tgp582, align 4
  switch i32 %tag583, label %case_default123 [
      i32 0, label %case_br124
  ]
case_br124:
  %ld584 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld584)
  %ld585 = load ptr, ptr %$f1604_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld585, ptr %yn_3.addr
  %ld586 = load ptr, ptr %$f1603_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld586, ptr %y_3.addr
  %ld587 = load ptr, ptr %$f1600.addr
  %xn_3.addr = alloca ptr
  store ptr %ld587, ptr %xn_3.addr
  %ld588 = load ptr, ptr %$f1599.addr
  %x_3.addr = alloca ptr
  store ptr %ld588, ptr %x_3.addr
  %ld589 = load ptr, ptr %yn_3.addr
  %ld590 = load ptr, ptr %xn_3.addr
  %cv593 = ptrtoint ptr %ld589 to i64
  %cv594 = ptrtoint ptr %ld590 to i64
  %cmp591 = icmp sle i64 %cv593, %cv594
  %ar592 = zext i1 %cmp591 to i64
  %$t1593_2.addr = alloca i64
  store i64 %ar592, ptr %$t1593_2.addr
  %ld595 = load i64, ptr %$t1593_2.addr
  %res_slot596 = alloca ptr
  %bi597 = trunc i64 %ld595 to i1
  br i1 %bi597, label %case_br127, label %case_default126
case_br127:
  %ld598 = load ptr, ptr %y_3.addr
  %a_i26.addr = alloca ptr
  store ptr %ld598, ptr %a_i26.addr
  %ld599 = load ptr, ptr %x_3.addr
  %b_i27.addr = alloca ptr
  store ptr %ld599, ptr %b_i27.addr
  %ld600 = load ptr, ptr %cmp.addr
  %cmp_i28.addr = alloca ptr
  store ptr %ld600, ptr %cmp_i28.addr
  %ld601 = load ptr, ptr %a_i26.addr
  %ld602 = load ptr, ptr %b_i27.addr
  %ld603 = load ptr, ptr %cmp_i28.addr
  %cr604 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld601, ptr %ld602, ptr %ld603)
  %merged_4.addr = alloca ptr
  store ptr %cr604, ptr %merged_4.addr
  %ld605 = load ptr, ptr %xn_3.addr
  %cv606 = ptrtoint ptr %ld605 to i64
  %ld607 = load ptr, ptr %yn_3.addr
  %cv608 = ptrtoint ptr %ld607 to i64
  %ar609 = add i64 %cv606, %cv608
  %$t1594_2.addr = alloca i64
  store i64 %ar609, ptr %$t1594_2.addr
  %hp610 = call ptr @march_alloc(i64 32)
  %tgp611 = getelementptr i8, ptr %hp610, i64 8
  store i32 0, ptr %tgp611, align 4
  %ld612 = load ptr, ptr %merged_4.addr
  %fp613 = getelementptr i8, ptr %hp610, i64 16
  store ptr %ld612, ptr %fp613, align 8
  %ld614 = load i64, ptr %$t1594_2.addr
  %fp615 = getelementptr i8, ptr %hp610, i64 24
  store i64 %ld614, ptr %fp615, align 8
  %$t1595_2.addr = alloca ptr
  store ptr %hp610, ptr %$t1595_2.addr
  %hp616 = call ptr @march_alloc(i64 16)
  %tgp617 = getelementptr i8, ptr %hp616, i64 8
  store i32 0, ptr %tgp617, align 4
  %$t1596_2.addr = alloca ptr
  store ptr %hp616, ptr %$t1596_2.addr
  %hp618 = call ptr @march_alloc(i64 32)
  %tgp619 = getelementptr i8, ptr %hp618, i64 8
  store i32 1, ptr %tgp619, align 4
  %ld620 = load ptr, ptr %$t1595_2.addr
  %fp621 = getelementptr i8, ptr %hp618, i64 16
  store ptr %ld620, ptr %fp621, align 8
  %ld622 = load ptr, ptr %$t1596_2.addr
  %fp623 = getelementptr i8, ptr %hp618, i64 24
  store ptr %ld622, ptr %fp623, align 8
  store ptr %hp618, ptr %res_slot596
  br label %case_merge125
case_default126:
  %ld624 = load ptr, ptr %stack.addr
  store ptr %ld624, ptr %res_slot596
  br label %case_merge125
case_merge125:
  %case_r625 = load ptr, ptr %res_slot596
  store ptr %case_r625, ptr %res_slot581
  br label %case_merge122
case_default123:
  %ld626 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld626)
  %ld627 = load ptr, ptr %stack.addr
  store ptr %ld627, ptr %res_slot581
  br label %case_merge122
case_merge122:
  %case_r628 = load ptr, ptr %res_slot581
  store ptr %case_r628, ptr %res_slot571
  br label %case_merge116
case_default117:
  %ld629 = load ptr, ptr %$f1601_2.addr
  call void @march_decrc(ptr %ld629)
  %ld630 = load ptr, ptr %stack.addr
  store ptr %ld630, ptr %res_slot571
  br label %case_merge116
case_merge116:
  %case_r631 = load ptr, ptr %res_slot571
  store ptr %case_r631, ptr %res_slot561
  br label %case_merge110
case_default111:
  %ld632 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld632)
  %ld633 = load ptr, ptr %stack.addr
  store ptr %ld633, ptr %res_slot561
  br label %case_merge110
case_merge110:
  %case_r634 = load ptr, ptr %res_slot561
  store ptr %case_r634, ptr %res_slot266
  br label %case_merge50
case_merge50:
  %case_r635 = load ptr, ptr %res_slot266
  store ptr %case_r635, ptr %res_slot258
  br label %case_merge47
case_default48:
  %ld636 = load ptr, ptr %$f1598.addr
  %res_slot637 = alloca ptr
  %tgp638 = getelementptr i8, ptr %ld636, i64 8
  %tag639 = load i32, ptr %tgp638, align 4
  switch i32 %tag639, label %case_default129 [
      i32 0, label %case_br130
  ]
case_br130:
  %fp640 = getelementptr i8, ptr %ld636, i64 16
  %fv641 = load ptr, ptr %fp640, align 8
  %$f1601_3.addr = alloca ptr
  store ptr %fv641, ptr %$f1601_3.addr
  %fp642 = getelementptr i8, ptr %ld636, i64 24
  %fv643 = load ptr, ptr %fp642, align 8
  %$f1602_3.addr = alloca ptr
  store ptr %fv643, ptr %$f1602_3.addr
  %freed644 = call i64 @march_decrc_freed(ptr %ld636)
  %freed_b645 = icmp ne i64 %freed644, 0
  br i1 %freed_b645, label %br_unique131, label %br_shared132
br_shared132:
  call void @march_incrc(ptr %fv643)
  call void @march_incrc(ptr %fv641)
  br label %br_body133
br_unique131:
  br label %br_body133
br_body133:
  %ld646 = load ptr, ptr %$f1601_3.addr
  %res_slot647 = alloca ptr
  %tgp648 = getelementptr i8, ptr %ld646, i64 8
  %tag649 = load i32, ptr %tgp648, align 4
  switch i32 %tag649, label %case_default135 [
      i32 0, label %case_br136
  ]
case_br136:
  %fp650 = getelementptr i8, ptr %ld646, i64 16
  %fv651 = load ptr, ptr %fp650, align 8
  %$f1603_3.addr = alloca ptr
  store ptr %fv651, ptr %$f1603_3.addr
  %fp652 = getelementptr i8, ptr %ld646, i64 24
  %fv653 = load ptr, ptr %fp652, align 8
  %$f1604_3.addr = alloca ptr
  store ptr %fv653, ptr %$f1604_3.addr
  %freed654 = call i64 @march_decrc_freed(ptr %ld646)
  %freed_b655 = icmp ne i64 %freed654, 0
  br i1 %freed_b655, label %br_unique137, label %br_shared138
br_shared138:
  call void @march_incrc(ptr %fv653)
  call void @march_incrc(ptr %fv651)
  br label %br_body139
br_unique137:
  br label %br_body139
br_body139:
  %ld656 = load ptr, ptr %$f1602_3.addr
  %res_slot657 = alloca ptr
  %tgp658 = getelementptr i8, ptr %ld656, i64 8
  %tag659 = load i32, ptr %tgp658, align 4
  switch i32 %tag659, label %case_default141 [
      i32 0, label %case_br142
  ]
case_br142:
  %ld660 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld660)
  %ld661 = load ptr, ptr %$f1604_3.addr
  %yn_4.addr = alloca ptr
  store ptr %ld661, ptr %yn_4.addr
  %ld662 = load ptr, ptr %$f1603_3.addr
  %y_4.addr = alloca ptr
  store ptr %ld662, ptr %y_4.addr
  %ld663 = load ptr, ptr %$f1600.addr
  %xn_4.addr = alloca ptr
  store ptr %ld663, ptr %xn_4.addr
  %ld664 = load ptr, ptr %$f1599.addr
  %x_4.addr = alloca ptr
  store ptr %ld664, ptr %x_4.addr
  %ld665 = load ptr, ptr %yn_4.addr
  %ld666 = load ptr, ptr %xn_4.addr
  %cv669 = ptrtoint ptr %ld665 to i64
  %cv670 = ptrtoint ptr %ld666 to i64
  %cmp667 = icmp sle i64 %cv669, %cv670
  %ar668 = zext i1 %cmp667 to i64
  %$t1593_3.addr = alloca i64
  store i64 %ar668, ptr %$t1593_3.addr
  %ld671 = load i64, ptr %$t1593_3.addr
  %res_slot672 = alloca ptr
  %bi673 = trunc i64 %ld671 to i1
  br i1 %bi673, label %case_br145, label %case_default144
case_br145:
  %ld674 = load ptr, ptr %y_4.addr
  %a_i23.addr = alloca ptr
  store ptr %ld674, ptr %a_i23.addr
  %ld675 = load ptr, ptr %x_4.addr
  %b_i24.addr = alloca ptr
  store ptr %ld675, ptr %b_i24.addr
  %ld676 = load ptr, ptr %cmp.addr
  %cmp_i25.addr = alloca ptr
  store ptr %ld676, ptr %cmp_i25.addr
  %ld677 = load ptr, ptr %a_i23.addr
  %ld678 = load ptr, ptr %b_i24.addr
  %ld679 = load ptr, ptr %cmp_i25.addr
  %cr680 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld677, ptr %ld678, ptr %ld679)
  %merged_5.addr = alloca ptr
  store ptr %cr680, ptr %merged_5.addr
  %ld681 = load ptr, ptr %xn_4.addr
  %cv682 = ptrtoint ptr %ld681 to i64
  %ld683 = load ptr, ptr %yn_4.addr
  %cv684 = ptrtoint ptr %ld683 to i64
  %ar685 = add i64 %cv682, %cv684
  %$t1594_3.addr = alloca i64
  store i64 %ar685, ptr %$t1594_3.addr
  %hp686 = call ptr @march_alloc(i64 32)
  %tgp687 = getelementptr i8, ptr %hp686, i64 8
  store i32 0, ptr %tgp687, align 4
  %ld688 = load ptr, ptr %merged_5.addr
  %fp689 = getelementptr i8, ptr %hp686, i64 16
  store ptr %ld688, ptr %fp689, align 8
  %ld690 = load i64, ptr %$t1594_3.addr
  %fp691 = getelementptr i8, ptr %hp686, i64 24
  store i64 %ld690, ptr %fp691, align 8
  %$t1595_3.addr = alloca ptr
  store ptr %hp686, ptr %$t1595_3.addr
  %hp692 = call ptr @march_alloc(i64 16)
  %tgp693 = getelementptr i8, ptr %hp692, i64 8
  store i32 0, ptr %tgp693, align 4
  %$t1596_3.addr = alloca ptr
  store ptr %hp692, ptr %$t1596_3.addr
  %hp694 = call ptr @march_alloc(i64 32)
  %tgp695 = getelementptr i8, ptr %hp694, i64 8
  store i32 1, ptr %tgp695, align 4
  %ld696 = load ptr, ptr %$t1595_3.addr
  %fp697 = getelementptr i8, ptr %hp694, i64 16
  store ptr %ld696, ptr %fp697, align 8
  %ld698 = load ptr, ptr %$t1596_3.addr
  %fp699 = getelementptr i8, ptr %hp694, i64 24
  store ptr %ld698, ptr %fp699, align 8
  store ptr %hp694, ptr %res_slot672
  br label %case_merge143
case_default144:
  %ld700 = load ptr, ptr %stack.addr
  store ptr %ld700, ptr %res_slot672
  br label %case_merge143
case_merge143:
  %case_r701 = load ptr, ptr %res_slot672
  store ptr %case_r701, ptr %res_slot657
  br label %case_merge140
case_default141:
  %ld702 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld702)
  %ld703 = load ptr, ptr %stack.addr
  store ptr %ld703, ptr %res_slot657
  br label %case_merge140
case_merge140:
  %case_r704 = load ptr, ptr %res_slot657
  store ptr %case_r704, ptr %res_slot647
  br label %case_merge134
case_default135:
  %ld705 = load ptr, ptr %$f1601_3.addr
  call void @march_decrc(ptr %ld705)
  %ld706 = load ptr, ptr %stack.addr
  store ptr %ld706, ptr %res_slot647
  br label %case_merge134
case_merge134:
  %case_r707 = load ptr, ptr %res_slot647
  store ptr %case_r707, ptr %res_slot637
  br label %case_merge128
case_default129:
  %ld708 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld708)
  %ld709 = load ptr, ptr %stack.addr
  store ptr %ld709, ptr %res_slot637
  br label %case_merge128
case_merge128:
  %case_r710 = load ptr, ptr %res_slot637
  store ptr %case_r710, ptr %res_slot258
  br label %case_merge47
case_merge47:
  %case_r711 = load ptr, ptr %res_slot258
  store ptr %case_r711, ptr %res_slot248
  br label %case_merge41
case_default42:
  %ld712 = load ptr, ptr %$f1597.addr
  call void @march_decrc(ptr %ld712)
  %ld713 = load ptr, ptr %stack.addr
  store ptr %ld713, ptr %res_slot248
  br label %case_merge41
case_merge41:
  %case_r714 = load ptr, ptr %res_slot248
  store ptr %case_r714, ptr %res_slot240
  br label %case_merge38
case_default39:
  %ld715 = load ptr, ptr %stack.addr
  store ptr %ld715, ptr %res_slot240
  br label %case_merge38
case_merge38:
  %case_r716 = load ptr, ptr %res_slot240
  ret ptr %case_r716
}

define ptr @Sort.detect_runs$List_V__5074$Fn_V__5074_Fn_V__5074_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp717 = call ptr @march_alloc(i64 32)
  %tgp718 = getelementptr i8, ptr %hp717, i64 8
  store i32 0, ptr %tgp718, align 4
  %fp719 = getelementptr i8, ptr %hp717, i64 16
  store ptr @scan_run$apply$32, ptr %fp719, align 8
  %ld720 = load ptr, ptr %cmp.addr
  %fp721 = getelementptr i8, ptr %hp717, i64 24
  store ptr %ld720, ptr %fp721, align 8
  %scan_run.addr = alloca ptr
  store ptr %hp717, ptr %scan_run.addr
  %hp722 = call ptr @march_alloc(i64 40)
  %tgp723 = getelementptr i8, ptr %hp722, i64 8
  store i32 0, ptr %tgp723, align 4
  %fp724 = getelementptr i8, ptr %hp722, i64 16
  store ptr @collect$apply$33, ptr %fp724, align 8
  %ld725 = load ptr, ptr %cmp.addr
  %fp726 = getelementptr i8, ptr %hp722, i64 24
  store ptr %ld725, ptr %fp726, align 8
  %ld727 = load ptr, ptr %scan_run.addr
  %fp728 = getelementptr i8, ptr %hp722, i64 32
  store ptr %ld727, ptr %fp728, align 8
  %collect.addr = alloca ptr
  store ptr %hp722, ptr %collect.addr
  %hp729 = call ptr @march_alloc(i64 16)
  %tgp730 = getelementptr i8, ptr %hp729, i64 8
  store i32 0, ptr %tgp730, align 4
  %$t1579.addr = alloca ptr
  store ptr %hp729, ptr %$t1579.addr
  %ld731 = load ptr, ptr %collect.addr
  %fp732 = getelementptr i8, ptr %ld731, i64 16
  %fv733 = load ptr, ptr %fp732, align 8
  %ld734 = load ptr, ptr %xs.addr
  %ld735 = load ptr, ptr %$t1579.addr
  %cr736 = call ptr (ptr, ptr, ptr) %fv733(ptr %ld731, ptr %ld734, ptr %ld735)
  ret ptr %cr736
}

define ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld737 = load ptr, ptr %xs.addr
  %res_slot738 = alloca ptr
  %tgp739 = getelementptr i8, ptr %ld737, i64 8
  %tag740 = load i32, ptr %tgp739, align 4
  switch i32 %tag740, label %case_default147 [
      i32 0, label %case_br148
      i32 1, label %case_br149
  ]
case_br148:
  %ld741 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld741)
  %ld742 = load ptr, ptr %ys.addr
  store ptr %ld742, ptr %res_slot738
  br label %case_merge146
case_br149:
  %fp743 = getelementptr i8, ptr %ld737, i64 16
  %fv744 = load ptr, ptr %fp743, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv744, ptr %$f1372.addr
  %fp745 = getelementptr i8, ptr %ld737, i64 24
  %fv746 = load ptr, ptr %fp745, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv746, ptr %$f1373.addr
  %ld747 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld747, ptr %xt.addr
  %ld748 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld748, ptr %x.addr
  %ld749 = load ptr, ptr %ys.addr
  %res_slot750 = alloca ptr
  %tgp751 = getelementptr i8, ptr %ld749, i64 8
  %tag752 = load i32, ptr %tgp751, align 4
  switch i32 %tag752, label %case_default151 [
      i32 0, label %case_br152
      i32 1, label %case_br153
  ]
case_br152:
  %ld753 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld753)
  %ld754 = load ptr, ptr %xs.addr
  store ptr %ld754, ptr %res_slot750
  br label %case_merge150
case_br153:
  %fp755 = getelementptr i8, ptr %ld749, i64 16
  %fv756 = load ptr, ptr %fp755, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv756, ptr %$f1370.addr
  %fp757 = getelementptr i8, ptr %ld749, i64 24
  %fv758 = load ptr, ptr %fp757, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv758, ptr %$f1371.addr
  %ld759 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld759, ptr %yt.addr
  %ld760 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld760, ptr %y.addr
  %ld761 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld761)
  %ld762 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld762)
  %ld763 = load ptr, ptr %cmp.addr
  %ld764 = load ptr, ptr %x.addr
  %ld765 = load ptr, ptr %y.addr
  %cr766 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld763, ptr %ld764, ptr %ld765)
  %$t1367.addr = alloca i64
  store i64 %cr766, ptr %$t1367.addr
  %ld767 = load i64, ptr %$t1367.addr
  %res_slot768 = alloca ptr
  %bi769 = trunc i64 %ld767 to i1
  br i1 %bi769, label %case_br156, label %case_default155
case_br156:
  %ld770 = load ptr, ptr %xt.addr
  %ld771 = load ptr, ptr %ys.addr
  %ld772 = load ptr, ptr %cmp.addr
  %cr773 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld770, ptr %ld771, ptr %ld772)
  %$t1368.addr = alloca ptr
  store ptr %cr773, ptr %$t1368.addr
  %hp774 = call ptr @march_alloc(i64 32)
  %tgp775 = getelementptr i8, ptr %hp774, i64 8
  store i32 1, ptr %tgp775, align 4
  %ld776 = load ptr, ptr %x.addr
  %fp777 = getelementptr i8, ptr %hp774, i64 16
  store ptr %ld776, ptr %fp777, align 8
  %ld778 = load ptr, ptr %$t1368.addr
  %fp779 = getelementptr i8, ptr %hp774, i64 24
  store ptr %ld778, ptr %fp779, align 8
  store ptr %hp774, ptr %res_slot768
  br label %case_merge154
case_default155:
  %ld780 = load ptr, ptr %xs.addr
  %ld781 = load ptr, ptr %yt.addr
  %ld782 = load ptr, ptr %cmp.addr
  %cr783 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld780, ptr %ld781, ptr %ld782)
  %$t1369.addr = alloca ptr
  store ptr %cr783, ptr %$t1369.addr
  %hp784 = call ptr @march_alloc(i64 32)
  %tgp785 = getelementptr i8, ptr %hp784, i64 8
  store i32 1, ptr %tgp785, align 4
  %ld786 = load ptr, ptr %y.addr
  %fp787 = getelementptr i8, ptr %hp784, i64 16
  store ptr %ld786, ptr %fp787, align 8
  %ld788 = load ptr, ptr %$t1369.addr
  %fp789 = getelementptr i8, ptr %hp784, i64 24
  store ptr %ld788, ptr %fp789, align 8
  store ptr %hp784, ptr %res_slot768
  br label %case_merge154
case_merge154:
  %case_r790 = load ptr, ptr %res_slot768
  store ptr %case_r790, ptr %res_slot750
  br label %case_merge150
case_default151:
  unreachable
case_merge150:
  %case_r791 = load ptr, ptr %res_slot750
  store ptr %case_r791, ptr %res_slot738
  br label %case_merge146
case_default147:
  unreachable
case_merge146:
  %case_r792 = load ptr, ptr %res_slot738
  ret ptr %case_r792
}

define i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld793 = load ptr, ptr %cmp.addr
  %fp794 = getelementptr i8, ptr %ld793, i64 16
  %fv795 = load ptr, ptr %fp794, align 8
  %ld796 = load ptr, ptr %x.addr
  %cr797 = call ptr (ptr, ptr) %fv795(ptr %ld793, ptr %ld796)
  %f.addr = alloca ptr
  store ptr %cr797, ptr %f.addr
  %ld798 = load ptr, ptr %f.addr
  %fp799 = getelementptr i8, ptr %ld798, i64 16
  %fv800 = load ptr, ptr %fp799, align 8
  %ld801 = load ptr, ptr %y.addr
  %cr802 = call i64 (ptr, ptr) %fv800(ptr %ld798, ptr %ld801)
  ret i64 %cr802
}

define ptr @Sort.reverse_list$List_T_List_V__5042_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp803 = call ptr @march_alloc(i64 24)
  %tgp804 = getelementptr i8, ptr %hp803, i64 8
  store i32 0, ptr %tgp804, align 4
  %fp805 = getelementptr i8, ptr %hp803, i64 16
  store ptr @go$apply$34, ptr %fp805, align 8
  %go.addr = alloca ptr
  store ptr %hp803, ptr %go.addr
  %hp806 = call ptr @march_alloc(i64 16)
  %tgp807 = getelementptr i8, ptr %hp806, i64 8
  store i32 0, ptr %tgp807, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp806, ptr %$t1355.addr
  %ld808 = load ptr, ptr %go.addr
  %fp809 = getelementptr i8, ptr %ld808, i64 16
  %fv810 = load ptr, ptr %fp809, align 8
  %ld811 = load ptr, ptr %xs.addr
  %ld812 = load ptr, ptr %$t1355.addr
  %cr813 = call ptr (ptr, ptr, ptr) %fv810(ptr %ld808, ptr %ld811, ptr %ld812)
  ret ptr %cr813
}

define ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld814 = load ptr, ptr %stack.addr
  %res_slot815 = alloca ptr
  %tgp816 = getelementptr i8, ptr %ld814, i64 8
  %tag817 = load i32, ptr %tgp816, align 4
  switch i32 %tag817, label %case_default158 [
      i32 1, label %case_br159
  ]
case_br159:
  %fp818 = getelementptr i8, ptr %ld814, i64 16
  %fv819 = load ptr, ptr %fp818, align 8
  %$f1597.addr = alloca ptr
  store ptr %fv819, ptr %$f1597.addr
  %fp820 = getelementptr i8, ptr %ld814, i64 24
  %fv821 = load ptr, ptr %fp820, align 8
  %$f1598.addr = alloca ptr
  store ptr %fv821, ptr %$f1598.addr
  %ld822 = load ptr, ptr %$f1597.addr
  %res_slot823 = alloca ptr
  %tgp824 = getelementptr i8, ptr %ld822, i64 8
  %tag825 = load i32, ptr %tgp824, align 4
  switch i32 %tag825, label %case_default161 [
      i32 0, label %case_br162
  ]
case_br162:
  %fp826 = getelementptr i8, ptr %ld822, i64 16
  %fv827 = load ptr, ptr %fp826, align 8
  %$f1599.addr = alloca ptr
  store ptr %fv827, ptr %$f1599.addr
  %fp828 = getelementptr i8, ptr %ld822, i64 24
  %fv829 = load ptr, ptr %fp828, align 8
  %$f1600.addr = alloca ptr
  store ptr %fv829, ptr %$f1600.addr
  %freed830 = call i64 @march_decrc_freed(ptr %ld822)
  %freed_b831 = icmp ne i64 %freed830, 0
  br i1 %freed_b831, label %br_unique163, label %br_shared164
br_shared164:
  call void @march_incrc(ptr %fv829)
  call void @march_incrc(ptr %fv827)
  br label %br_body165
br_unique163:
  br label %br_body165
br_body165:
  %ld832 = load ptr, ptr %$f1598.addr
  %res_slot833 = alloca ptr
  %tgp834 = getelementptr i8, ptr %ld832, i64 8
  %tag835 = load i32, ptr %tgp834, align 4
  switch i32 %tag835, label %case_default167 [
      i32 0, label %case_br168
  ]
case_br168:
  %fp836 = getelementptr i8, ptr %ld832, i64 16
  %fv837 = load ptr, ptr %fp836, align 8
  %$f1605.addr = alloca ptr
  store ptr %fv837, ptr %$f1605.addr
  %fp838 = getelementptr i8, ptr %ld832, i64 24
  %fv839 = load ptr, ptr %fp838, align 8
  %$f1606.addr = alloca ptr
  store ptr %fv839, ptr %$f1606.addr
  %ld840 = load ptr, ptr %$f1605.addr
  %res_slot841 = alloca ptr
  %tgp842 = getelementptr i8, ptr %ld840, i64 8
  %tag843 = load i32, ptr %tgp842, align 4
  switch i32 %tag843, label %case_default170 [
      i32 0, label %case_br171
  ]
case_br171:
  %fp844 = getelementptr i8, ptr %ld840, i64 16
  %fv845 = load ptr, ptr %fp844, align 8
  %$f1607.addr = alloca ptr
  store ptr %fv845, ptr %$f1607.addr
  %fp846 = getelementptr i8, ptr %ld840, i64 24
  %fv847 = load ptr, ptr %fp846, align 8
  %$f1608.addr = alloca ptr
  store ptr %fv847, ptr %$f1608.addr
  %freed848 = call i64 @march_decrc_freed(ptr %ld840)
  %freed_b849 = icmp ne i64 %freed848, 0
  br i1 %freed_b849, label %br_unique172, label %br_shared173
br_shared173:
  call void @march_incrc(ptr %fv847)
  call void @march_incrc(ptr %fv845)
  br label %br_body174
br_unique172:
  br label %br_body174
br_body174:
  %ld850 = load ptr, ptr %$f1606.addr
  %res_slot851 = alloca ptr
  %tgp852 = getelementptr i8, ptr %ld850, i64 8
  %tag853 = load i32, ptr %tgp852, align 4
  switch i32 %tag853, label %case_default176 [
      i32 0, label %case_br177
  ]
case_br177:
  %fp854 = getelementptr i8, ptr %ld850, i64 16
  %fv855 = load ptr, ptr %fp854, align 8
  %$f1609.addr = alloca ptr
  store ptr %fv855, ptr %$f1609.addr
  %fp856 = getelementptr i8, ptr %ld850, i64 24
  %fv857 = load ptr, ptr %fp856, align 8
  %$f1610.addr = alloca ptr
  store ptr %fv857, ptr %$f1610.addr
  %freed858 = call i64 @march_decrc_freed(ptr %ld850)
  %freed_b859 = icmp ne i64 %freed858, 0
  br i1 %freed_b859, label %br_unique178, label %br_shared179
br_shared179:
  call void @march_incrc(ptr %fv857)
  call void @march_incrc(ptr %fv855)
  br label %br_body180
br_unique178:
  br label %br_body180
br_body180:
  %ld860 = load ptr, ptr %$f1609.addr
  %res_slot861 = alloca ptr
  %tgp862 = getelementptr i8, ptr %ld860, i64 8
  %tag863 = load i32, ptr %tgp862, align 4
  switch i32 %tag863, label %case_default182 [
      i32 0, label %case_br183
  ]
case_br183:
  %fp864 = getelementptr i8, ptr %ld860, i64 16
  %fv865 = load ptr, ptr %fp864, align 8
  %$f1611.addr = alloca ptr
  store ptr %fv865, ptr %$f1611.addr
  %fp866 = getelementptr i8, ptr %ld860, i64 24
  %fv867 = load ptr, ptr %fp866, align 8
  %$f1612.addr = alloca ptr
  store ptr %fv867, ptr %$f1612.addr
  %freed868 = call i64 @march_decrc_freed(ptr %ld860)
  %freed_b869 = icmp ne i64 %freed868, 0
  br i1 %freed_b869, label %br_unique184, label %br_shared185
br_shared185:
  call void @march_incrc(ptr %fv867)
  call void @march_incrc(ptr %fv865)
  br label %br_body186
br_unique184:
  br label %br_body186
br_body186:
  %ld870 = load ptr, ptr %$f1610.addr
  %rest.addr = alloca ptr
  store ptr %ld870, ptr %rest.addr
  %ld871 = load ptr, ptr %$f1612.addr
  %zn.addr = alloca ptr
  store ptr %ld871, ptr %zn.addr
  %ld872 = load ptr, ptr %$f1611.addr
  %z.addr = alloca ptr
  store ptr %ld872, ptr %z.addr
  %ld873 = load ptr, ptr %$f1608.addr
  %yn.addr = alloca ptr
  store ptr %ld873, ptr %yn.addr
  %ld874 = load ptr, ptr %$f1607.addr
  %y.addr = alloca ptr
  store ptr %ld874, ptr %y.addr
  %ld875 = load ptr, ptr %$f1600.addr
  %xn.addr = alloca ptr
  store ptr %ld875, ptr %xn.addr
  %ld876 = load ptr, ptr %$f1599.addr
  %x.addr = alloca ptr
  store ptr %ld876, ptr %x.addr
  %ld877 = load ptr, ptr %yn.addr
  %ld878 = load ptr, ptr %xn.addr
  %cv881 = ptrtoint ptr %ld877 to i64
  %cv882 = ptrtoint ptr %ld878 to i64
  %cmp879 = icmp sle i64 %cv881, %cv882
  %ar880 = zext i1 %cmp879 to i64
  %$t1580.addr = alloca i64
  store i64 %ar880, ptr %$t1580.addr
  %ld883 = load i64, ptr %$t1580.addr
  %res_slot884 = alloca ptr
  %bi885 = trunc i64 %ld883 to i1
  br i1 %bi885, label %case_br189, label %case_default188
case_br189:
  %ld886 = load ptr, ptr %y.addr
  %a_i56.addr = alloca ptr
  store ptr %ld886, ptr %a_i56.addr
  %ld887 = load ptr, ptr %x.addr
  %b_i57.addr = alloca ptr
  store ptr %ld887, ptr %b_i57.addr
  %ld888 = load ptr, ptr %cmp.addr
  %cmp_i58.addr = alloca ptr
  store ptr %ld888, ptr %cmp_i58.addr
  %ld889 = load ptr, ptr %a_i56.addr
  %ld890 = load ptr, ptr %b_i57.addr
  %ld891 = load ptr, ptr %cmp_i58.addr
  %cr892 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld889, ptr %ld890, ptr %ld891)
  %merged.addr = alloca ptr
  store ptr %cr892, ptr %merged.addr
  %ld893 = load ptr, ptr %xn.addr
  %cv894 = ptrtoint ptr %ld893 to i64
  %ld895 = load ptr, ptr %yn.addr
  %cv896 = ptrtoint ptr %ld895 to i64
  %ar897 = add i64 %cv894, %cv896
  %$t1581.addr = alloca i64
  store i64 %ar897, ptr %$t1581.addr
  %hp898 = call ptr @march_alloc(i64 32)
  %tgp899 = getelementptr i8, ptr %hp898, i64 8
  store i32 0, ptr %tgp899, align 4
  %ld900 = load ptr, ptr %merged.addr
  %fp901 = getelementptr i8, ptr %hp898, i64 16
  store ptr %ld900, ptr %fp901, align 8
  %ld902 = load i64, ptr %$t1581.addr
  %fp903 = getelementptr i8, ptr %hp898, i64 24
  store i64 %ld902, ptr %fp903, align 8
  %$t1582.addr = alloca ptr
  store ptr %hp898, ptr %$t1582.addr
  %hp904 = call ptr @march_alloc(i64 32)
  %tgp905 = getelementptr i8, ptr %hp904, i64 8
  store i32 0, ptr %tgp905, align 4
  %ld906 = load ptr, ptr %z.addr
  %fp907 = getelementptr i8, ptr %hp904, i64 16
  store ptr %ld906, ptr %fp907, align 8
  %ld908 = load ptr, ptr %zn.addr
  %fp909 = getelementptr i8, ptr %hp904, i64 24
  store ptr %ld908, ptr %fp909, align 8
  %$t1583.addr = alloca ptr
  store ptr %hp904, ptr %$t1583.addr
  %hp910 = call ptr @march_alloc(i64 32)
  %tgp911 = getelementptr i8, ptr %hp910, i64 8
  store i32 1, ptr %tgp911, align 4
  %ld912 = load ptr, ptr %$t1583.addr
  %fp913 = getelementptr i8, ptr %hp910, i64 16
  store ptr %ld912, ptr %fp913, align 8
  %ld914 = load ptr, ptr %rest.addr
  %fp915 = getelementptr i8, ptr %hp910, i64 24
  store ptr %ld914, ptr %fp915, align 8
  %$t1584.addr = alloca ptr
  store ptr %hp910, ptr %$t1584.addr
  %hp916 = call ptr @march_alloc(i64 32)
  %tgp917 = getelementptr i8, ptr %hp916, i64 8
  store i32 1, ptr %tgp917, align 4
  %ld918 = load ptr, ptr %$t1582.addr
  %fp919 = getelementptr i8, ptr %hp916, i64 16
  store ptr %ld918, ptr %fp919, align 8
  %ld920 = load ptr, ptr %$t1584.addr
  %fp921 = getelementptr i8, ptr %hp916, i64 24
  store ptr %ld920, ptr %fp921, align 8
  %$t1585.addr = alloca ptr
  store ptr %hp916, ptr %$t1585.addr
  %ld922 = load ptr, ptr %$t1585.addr
  %ld923 = load ptr, ptr %cmp.addr
  %cr924 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld922, ptr %ld923)
  store ptr %cr924, ptr %res_slot884
  br label %case_merge187
case_default188:
  %ld925 = load ptr, ptr %yn.addr
  %cv926 = ptrtoint ptr %ld925 to i64
  %ld927 = load ptr, ptr %xn.addr
  %cv928 = ptrtoint ptr %ld927 to i64
  %ar929 = add i64 %cv926, %cv928
  %$t1586.addr = alloca i64
  store i64 %ar929, ptr %$t1586.addr
  %ld930 = load ptr, ptr %zn.addr
  %ld931 = load i64, ptr %$t1586.addr
  %cv934 = ptrtoint ptr %ld930 to i64
  %cmp932 = icmp sle i64 %cv934, %ld931
  %ar933 = zext i1 %cmp932 to i64
  %$t1587.addr = alloca i64
  store i64 %ar933, ptr %$t1587.addr
  %ld935 = load i64, ptr %$t1587.addr
  %res_slot936 = alloca ptr
  %bi937 = trunc i64 %ld935 to i1
  br i1 %bi937, label %case_br192, label %case_default191
case_br192:
  %ld938 = load ptr, ptr %z.addr
  %a_i53.addr = alloca ptr
  store ptr %ld938, ptr %a_i53.addr
  %ld939 = load ptr, ptr %y.addr
  %b_i54.addr = alloca ptr
  store ptr %ld939, ptr %b_i54.addr
  %ld940 = load ptr, ptr %cmp.addr
  %cmp_i55.addr = alloca ptr
  store ptr %ld940, ptr %cmp_i55.addr
  %ld941 = load ptr, ptr %a_i53.addr
  %ld942 = load ptr, ptr %b_i54.addr
  %ld943 = load ptr, ptr %cmp_i55.addr
  %cr944 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld941, ptr %ld942, ptr %ld943)
  %merged_1.addr = alloca ptr
  store ptr %cr944, ptr %merged_1.addr
  %hp945 = call ptr @march_alloc(i64 32)
  %tgp946 = getelementptr i8, ptr %hp945, i64 8
  store i32 0, ptr %tgp946, align 4
  %ld947 = load ptr, ptr %x.addr
  %fp948 = getelementptr i8, ptr %hp945, i64 16
  store ptr %ld947, ptr %fp948, align 8
  %ld949 = load ptr, ptr %xn.addr
  %fp950 = getelementptr i8, ptr %hp945, i64 24
  store ptr %ld949, ptr %fp950, align 8
  %$t1588.addr = alloca ptr
  store ptr %hp945, ptr %$t1588.addr
  %ld951 = load ptr, ptr %yn.addr
  %cv952 = ptrtoint ptr %ld951 to i64
  %ld953 = load ptr, ptr %zn.addr
  %cv954 = ptrtoint ptr %ld953 to i64
  %ar955 = add i64 %cv952, %cv954
  %$t1589.addr = alloca i64
  store i64 %ar955, ptr %$t1589.addr
  %hp956 = call ptr @march_alloc(i64 32)
  %tgp957 = getelementptr i8, ptr %hp956, i64 8
  store i32 0, ptr %tgp957, align 4
  %ld958 = load ptr, ptr %merged_1.addr
  %fp959 = getelementptr i8, ptr %hp956, i64 16
  store ptr %ld958, ptr %fp959, align 8
  %ld960 = load i64, ptr %$t1589.addr
  %fp961 = getelementptr i8, ptr %hp956, i64 24
  store i64 %ld960, ptr %fp961, align 8
  %$t1590.addr = alloca ptr
  store ptr %hp956, ptr %$t1590.addr
  %hp962 = call ptr @march_alloc(i64 32)
  %tgp963 = getelementptr i8, ptr %hp962, i64 8
  store i32 1, ptr %tgp963, align 4
  %ld964 = load ptr, ptr %$t1590.addr
  %fp965 = getelementptr i8, ptr %hp962, i64 16
  store ptr %ld964, ptr %fp965, align 8
  %ld966 = load ptr, ptr %rest.addr
  %fp967 = getelementptr i8, ptr %hp962, i64 24
  store ptr %ld966, ptr %fp967, align 8
  %$t1591.addr = alloca ptr
  store ptr %hp962, ptr %$t1591.addr
  %hp968 = call ptr @march_alloc(i64 32)
  %tgp969 = getelementptr i8, ptr %hp968, i64 8
  store i32 1, ptr %tgp969, align 4
  %ld970 = load ptr, ptr %$t1588.addr
  %fp971 = getelementptr i8, ptr %hp968, i64 16
  store ptr %ld970, ptr %fp971, align 8
  %ld972 = load ptr, ptr %$t1591.addr
  %fp973 = getelementptr i8, ptr %hp968, i64 24
  store ptr %ld972, ptr %fp973, align 8
  %$t1592.addr = alloca ptr
  store ptr %hp968, ptr %$t1592.addr
  %ld974 = load ptr, ptr %$t1592.addr
  %ld975 = load ptr, ptr %cmp.addr
  %cr976 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld974, ptr %ld975)
  store ptr %cr976, ptr %res_slot936
  br label %case_merge190
case_default191:
  %ld977 = load ptr, ptr %stack.addr
  store ptr %ld977, ptr %res_slot936
  br label %case_merge190
case_merge190:
  %case_r978 = load ptr, ptr %res_slot936
  store ptr %case_r978, ptr %res_slot884
  br label %case_merge187
case_merge187:
  %case_r979 = load ptr, ptr %res_slot884
  store ptr %case_r979, ptr %res_slot861
  br label %case_merge181
case_default182:
  %ld980 = load ptr, ptr %$f1609.addr
  call void @march_decrc(ptr %ld980)
  %ld981 = load ptr, ptr %$f1598.addr
  %res_slot982 = alloca ptr
  %tgp983 = getelementptr i8, ptr %ld981, i64 8
  %tag984 = load i32, ptr %tgp983, align 4
  switch i32 %tag984, label %case_default194 [
      i32 0, label %case_br195
  ]
case_br195:
  %fp985 = getelementptr i8, ptr %ld981, i64 16
  %fv986 = load ptr, ptr %fp985, align 8
  %$f1601.addr = alloca ptr
  store ptr %fv986, ptr %$f1601.addr
  %fp987 = getelementptr i8, ptr %ld981, i64 24
  %fv988 = load ptr, ptr %fp987, align 8
  %$f1602.addr = alloca ptr
  store ptr %fv988, ptr %$f1602.addr
  %freed989 = call i64 @march_decrc_freed(ptr %ld981)
  %freed_b990 = icmp ne i64 %freed989, 0
  br i1 %freed_b990, label %br_unique196, label %br_shared197
br_shared197:
  call void @march_incrc(ptr %fv988)
  call void @march_incrc(ptr %fv986)
  br label %br_body198
br_unique196:
  br label %br_body198
br_body198:
  %ld991 = load ptr, ptr %$f1601.addr
  %res_slot992 = alloca ptr
  %tgp993 = getelementptr i8, ptr %ld991, i64 8
  %tag994 = load i32, ptr %tgp993, align 4
  switch i32 %tag994, label %case_default200 [
      i32 0, label %case_br201
  ]
case_br201:
  %fp995 = getelementptr i8, ptr %ld991, i64 16
  %fv996 = load ptr, ptr %fp995, align 8
  %$f1603.addr = alloca ptr
  store ptr %fv996, ptr %$f1603.addr
  %fp997 = getelementptr i8, ptr %ld991, i64 24
  %fv998 = load ptr, ptr %fp997, align 8
  %$f1604.addr = alloca ptr
  store ptr %fv998, ptr %$f1604.addr
  %freed999 = call i64 @march_decrc_freed(ptr %ld991)
  %freed_b1000 = icmp ne i64 %freed999, 0
  br i1 %freed_b1000, label %br_unique202, label %br_shared203
br_shared203:
  call void @march_incrc(ptr %fv998)
  call void @march_incrc(ptr %fv996)
  br label %br_body204
br_unique202:
  br label %br_body204
br_body204:
  %ld1001 = load ptr, ptr %$f1602.addr
  %res_slot1002 = alloca ptr
  %tgp1003 = getelementptr i8, ptr %ld1001, i64 8
  %tag1004 = load i32, ptr %tgp1003, align 4
  switch i32 %tag1004, label %case_default206 [
      i32 0, label %case_br207
  ]
case_br207:
  %ld1005 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld1005)
  %ld1006 = load ptr, ptr %$f1604.addr
  %yn_1.addr = alloca ptr
  store ptr %ld1006, ptr %yn_1.addr
  %ld1007 = load ptr, ptr %$f1603.addr
  %y_1.addr = alloca ptr
  store ptr %ld1007, ptr %y_1.addr
  %ld1008 = load ptr, ptr %$f1600.addr
  %xn_1.addr = alloca ptr
  store ptr %ld1008, ptr %xn_1.addr
  %ld1009 = load ptr, ptr %$f1599.addr
  %x_1.addr = alloca ptr
  store ptr %ld1009, ptr %x_1.addr
  %ld1010 = load ptr, ptr %yn_1.addr
  %ld1011 = load ptr, ptr %xn_1.addr
  %cv1014 = ptrtoint ptr %ld1010 to i64
  %cv1015 = ptrtoint ptr %ld1011 to i64
  %cmp1012 = icmp sle i64 %cv1014, %cv1015
  %ar1013 = zext i1 %cmp1012 to i64
  %$t1593.addr = alloca i64
  store i64 %ar1013, ptr %$t1593.addr
  %ld1016 = load i64, ptr %$t1593.addr
  %res_slot1017 = alloca ptr
  %bi1018 = trunc i64 %ld1016 to i1
  br i1 %bi1018, label %case_br210, label %case_default209
case_br210:
  %ld1019 = load ptr, ptr %y_1.addr
  %a_i50.addr = alloca ptr
  store ptr %ld1019, ptr %a_i50.addr
  %ld1020 = load ptr, ptr %x_1.addr
  %b_i51.addr = alloca ptr
  store ptr %ld1020, ptr %b_i51.addr
  %ld1021 = load ptr, ptr %cmp.addr
  %cmp_i52.addr = alloca ptr
  store ptr %ld1021, ptr %cmp_i52.addr
  %ld1022 = load ptr, ptr %a_i50.addr
  %ld1023 = load ptr, ptr %b_i51.addr
  %ld1024 = load ptr, ptr %cmp_i52.addr
  %cr1025 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1022, ptr %ld1023, ptr %ld1024)
  %merged_2.addr = alloca ptr
  store ptr %cr1025, ptr %merged_2.addr
  %ld1026 = load ptr, ptr %xn_1.addr
  %cv1027 = ptrtoint ptr %ld1026 to i64
  %ld1028 = load ptr, ptr %yn_1.addr
  %cv1029 = ptrtoint ptr %ld1028 to i64
  %ar1030 = add i64 %cv1027, %cv1029
  %$t1594.addr = alloca i64
  store i64 %ar1030, ptr %$t1594.addr
  %hp1031 = call ptr @march_alloc(i64 32)
  %tgp1032 = getelementptr i8, ptr %hp1031, i64 8
  store i32 0, ptr %tgp1032, align 4
  %ld1033 = load ptr, ptr %merged_2.addr
  %fp1034 = getelementptr i8, ptr %hp1031, i64 16
  store ptr %ld1033, ptr %fp1034, align 8
  %ld1035 = load i64, ptr %$t1594.addr
  %fp1036 = getelementptr i8, ptr %hp1031, i64 24
  store i64 %ld1035, ptr %fp1036, align 8
  %$t1595.addr = alloca ptr
  store ptr %hp1031, ptr %$t1595.addr
  %hp1037 = call ptr @march_alloc(i64 16)
  %tgp1038 = getelementptr i8, ptr %hp1037, i64 8
  store i32 0, ptr %tgp1038, align 4
  %$t1596.addr = alloca ptr
  store ptr %hp1037, ptr %$t1596.addr
  %hp1039 = call ptr @march_alloc(i64 32)
  %tgp1040 = getelementptr i8, ptr %hp1039, i64 8
  store i32 1, ptr %tgp1040, align 4
  %ld1041 = load ptr, ptr %$t1595.addr
  %fp1042 = getelementptr i8, ptr %hp1039, i64 16
  store ptr %ld1041, ptr %fp1042, align 8
  %ld1043 = load ptr, ptr %$t1596.addr
  %fp1044 = getelementptr i8, ptr %hp1039, i64 24
  store ptr %ld1043, ptr %fp1044, align 8
  store ptr %hp1039, ptr %res_slot1017
  br label %case_merge208
case_default209:
  %ld1045 = load ptr, ptr %stack.addr
  store ptr %ld1045, ptr %res_slot1017
  br label %case_merge208
case_merge208:
  %case_r1046 = load ptr, ptr %res_slot1017
  store ptr %case_r1046, ptr %res_slot1002
  br label %case_merge205
case_default206:
  %ld1047 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld1047)
  %ld1048 = load ptr, ptr %stack.addr
  store ptr %ld1048, ptr %res_slot1002
  br label %case_merge205
case_merge205:
  %case_r1049 = load ptr, ptr %res_slot1002
  store ptr %case_r1049, ptr %res_slot992
  br label %case_merge199
case_default200:
  %ld1050 = load ptr, ptr %$f1601.addr
  call void @march_decrc(ptr %ld1050)
  %ld1051 = load ptr, ptr %stack.addr
  store ptr %ld1051, ptr %res_slot992
  br label %case_merge199
case_merge199:
  %case_r1052 = load ptr, ptr %res_slot992
  store ptr %case_r1052, ptr %res_slot982
  br label %case_merge193
case_default194:
  %ld1053 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1053)
  %ld1054 = load ptr, ptr %stack.addr
  store ptr %ld1054, ptr %res_slot982
  br label %case_merge193
case_merge193:
  %case_r1055 = load ptr, ptr %res_slot982
  store ptr %case_r1055, ptr %res_slot861
  br label %case_merge181
case_merge181:
  %case_r1056 = load ptr, ptr %res_slot861
  store ptr %case_r1056, ptr %res_slot851
  br label %case_merge175
case_default176:
  %ld1057 = load ptr, ptr %$f1606.addr
  call void @march_decrc(ptr %ld1057)
  %ld1058 = load ptr, ptr %$f1598.addr
  %res_slot1059 = alloca ptr
  %tgp1060 = getelementptr i8, ptr %ld1058, i64 8
  %tag1061 = load i32, ptr %tgp1060, align 4
  switch i32 %tag1061, label %case_default212 [
      i32 0, label %case_br213
  ]
case_br213:
  %fp1062 = getelementptr i8, ptr %ld1058, i64 16
  %fv1063 = load ptr, ptr %fp1062, align 8
  %$f1601_1.addr = alloca ptr
  store ptr %fv1063, ptr %$f1601_1.addr
  %fp1064 = getelementptr i8, ptr %ld1058, i64 24
  %fv1065 = load ptr, ptr %fp1064, align 8
  %$f1602_1.addr = alloca ptr
  store ptr %fv1065, ptr %$f1602_1.addr
  %freed1066 = call i64 @march_decrc_freed(ptr %ld1058)
  %freed_b1067 = icmp ne i64 %freed1066, 0
  br i1 %freed_b1067, label %br_unique214, label %br_shared215
br_shared215:
  call void @march_incrc(ptr %fv1065)
  call void @march_incrc(ptr %fv1063)
  br label %br_body216
br_unique214:
  br label %br_body216
br_body216:
  %ld1068 = load ptr, ptr %$f1601_1.addr
  %res_slot1069 = alloca ptr
  %tgp1070 = getelementptr i8, ptr %ld1068, i64 8
  %tag1071 = load i32, ptr %tgp1070, align 4
  switch i32 %tag1071, label %case_default218 [
      i32 0, label %case_br219
  ]
case_br219:
  %fp1072 = getelementptr i8, ptr %ld1068, i64 16
  %fv1073 = load ptr, ptr %fp1072, align 8
  %$f1603_1.addr = alloca ptr
  store ptr %fv1073, ptr %$f1603_1.addr
  %fp1074 = getelementptr i8, ptr %ld1068, i64 24
  %fv1075 = load ptr, ptr %fp1074, align 8
  %$f1604_1.addr = alloca ptr
  store ptr %fv1075, ptr %$f1604_1.addr
  %freed1076 = call i64 @march_decrc_freed(ptr %ld1068)
  %freed_b1077 = icmp ne i64 %freed1076, 0
  br i1 %freed_b1077, label %br_unique220, label %br_shared221
br_shared221:
  call void @march_incrc(ptr %fv1075)
  call void @march_incrc(ptr %fv1073)
  br label %br_body222
br_unique220:
  br label %br_body222
br_body222:
  %ld1078 = load ptr, ptr %$f1602_1.addr
  %res_slot1079 = alloca ptr
  %tgp1080 = getelementptr i8, ptr %ld1078, i64 8
  %tag1081 = load i32, ptr %tgp1080, align 4
  switch i32 %tag1081, label %case_default224 [
      i32 0, label %case_br225
  ]
case_br225:
  %ld1082 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld1082)
  %ld1083 = load ptr, ptr %$f1604_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld1083, ptr %yn_2.addr
  %ld1084 = load ptr, ptr %$f1603_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld1084, ptr %y_2.addr
  %ld1085 = load ptr, ptr %$f1600.addr
  %xn_2.addr = alloca ptr
  store ptr %ld1085, ptr %xn_2.addr
  %ld1086 = load ptr, ptr %$f1599.addr
  %x_2.addr = alloca ptr
  store ptr %ld1086, ptr %x_2.addr
  %ld1087 = load ptr, ptr %yn_2.addr
  %ld1088 = load ptr, ptr %xn_2.addr
  %cv1091 = ptrtoint ptr %ld1087 to i64
  %cv1092 = ptrtoint ptr %ld1088 to i64
  %cmp1089 = icmp sle i64 %cv1091, %cv1092
  %ar1090 = zext i1 %cmp1089 to i64
  %$t1593_1.addr = alloca i64
  store i64 %ar1090, ptr %$t1593_1.addr
  %ld1093 = load i64, ptr %$t1593_1.addr
  %res_slot1094 = alloca ptr
  %bi1095 = trunc i64 %ld1093 to i1
  br i1 %bi1095, label %case_br228, label %case_default227
case_br228:
  %ld1096 = load ptr, ptr %y_2.addr
  %a_i47.addr = alloca ptr
  store ptr %ld1096, ptr %a_i47.addr
  %ld1097 = load ptr, ptr %x_2.addr
  %b_i48.addr = alloca ptr
  store ptr %ld1097, ptr %b_i48.addr
  %ld1098 = load ptr, ptr %cmp.addr
  %cmp_i49.addr = alloca ptr
  store ptr %ld1098, ptr %cmp_i49.addr
  %ld1099 = load ptr, ptr %a_i47.addr
  %ld1100 = load ptr, ptr %b_i48.addr
  %ld1101 = load ptr, ptr %cmp_i49.addr
  %cr1102 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1099, ptr %ld1100, ptr %ld1101)
  %merged_3.addr = alloca ptr
  store ptr %cr1102, ptr %merged_3.addr
  %ld1103 = load ptr, ptr %xn_2.addr
  %cv1104 = ptrtoint ptr %ld1103 to i64
  %ld1105 = load ptr, ptr %yn_2.addr
  %cv1106 = ptrtoint ptr %ld1105 to i64
  %ar1107 = add i64 %cv1104, %cv1106
  %$t1594_1.addr = alloca i64
  store i64 %ar1107, ptr %$t1594_1.addr
  %hp1108 = call ptr @march_alloc(i64 32)
  %tgp1109 = getelementptr i8, ptr %hp1108, i64 8
  store i32 0, ptr %tgp1109, align 4
  %ld1110 = load ptr, ptr %merged_3.addr
  %fp1111 = getelementptr i8, ptr %hp1108, i64 16
  store ptr %ld1110, ptr %fp1111, align 8
  %ld1112 = load i64, ptr %$t1594_1.addr
  %fp1113 = getelementptr i8, ptr %hp1108, i64 24
  store i64 %ld1112, ptr %fp1113, align 8
  %$t1595_1.addr = alloca ptr
  store ptr %hp1108, ptr %$t1595_1.addr
  %hp1114 = call ptr @march_alloc(i64 16)
  %tgp1115 = getelementptr i8, ptr %hp1114, i64 8
  store i32 0, ptr %tgp1115, align 4
  %$t1596_1.addr = alloca ptr
  store ptr %hp1114, ptr %$t1596_1.addr
  %hp1116 = call ptr @march_alloc(i64 32)
  %tgp1117 = getelementptr i8, ptr %hp1116, i64 8
  store i32 1, ptr %tgp1117, align 4
  %ld1118 = load ptr, ptr %$t1595_1.addr
  %fp1119 = getelementptr i8, ptr %hp1116, i64 16
  store ptr %ld1118, ptr %fp1119, align 8
  %ld1120 = load ptr, ptr %$t1596_1.addr
  %fp1121 = getelementptr i8, ptr %hp1116, i64 24
  store ptr %ld1120, ptr %fp1121, align 8
  store ptr %hp1116, ptr %res_slot1094
  br label %case_merge226
case_default227:
  %ld1122 = load ptr, ptr %stack.addr
  store ptr %ld1122, ptr %res_slot1094
  br label %case_merge226
case_merge226:
  %case_r1123 = load ptr, ptr %res_slot1094
  store ptr %case_r1123, ptr %res_slot1079
  br label %case_merge223
case_default224:
  %ld1124 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld1124)
  %ld1125 = load ptr, ptr %stack.addr
  store ptr %ld1125, ptr %res_slot1079
  br label %case_merge223
case_merge223:
  %case_r1126 = load ptr, ptr %res_slot1079
  store ptr %case_r1126, ptr %res_slot1069
  br label %case_merge217
case_default218:
  %ld1127 = load ptr, ptr %$f1601_1.addr
  call void @march_decrc(ptr %ld1127)
  %ld1128 = load ptr, ptr %stack.addr
  store ptr %ld1128, ptr %res_slot1069
  br label %case_merge217
case_merge217:
  %case_r1129 = load ptr, ptr %res_slot1069
  store ptr %case_r1129, ptr %res_slot1059
  br label %case_merge211
case_default212:
  %ld1130 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1130)
  %ld1131 = load ptr, ptr %stack.addr
  store ptr %ld1131, ptr %res_slot1059
  br label %case_merge211
case_merge211:
  %case_r1132 = load ptr, ptr %res_slot1059
  store ptr %case_r1132, ptr %res_slot851
  br label %case_merge175
case_merge175:
  %case_r1133 = load ptr, ptr %res_slot851
  store ptr %case_r1133, ptr %res_slot841
  br label %case_merge169
case_default170:
  %ld1134 = load ptr, ptr %$f1605.addr
  call void @march_decrc(ptr %ld1134)
  %ld1135 = load ptr, ptr %$f1598.addr
  %res_slot1136 = alloca ptr
  %tgp1137 = getelementptr i8, ptr %ld1135, i64 8
  %tag1138 = load i32, ptr %tgp1137, align 4
  switch i32 %tag1138, label %case_default230 [
      i32 0, label %case_br231
  ]
case_br231:
  %fp1139 = getelementptr i8, ptr %ld1135, i64 16
  %fv1140 = load ptr, ptr %fp1139, align 8
  %$f1601_2.addr = alloca ptr
  store ptr %fv1140, ptr %$f1601_2.addr
  %fp1141 = getelementptr i8, ptr %ld1135, i64 24
  %fv1142 = load ptr, ptr %fp1141, align 8
  %$f1602_2.addr = alloca ptr
  store ptr %fv1142, ptr %$f1602_2.addr
  %freed1143 = call i64 @march_decrc_freed(ptr %ld1135)
  %freed_b1144 = icmp ne i64 %freed1143, 0
  br i1 %freed_b1144, label %br_unique232, label %br_shared233
br_shared233:
  call void @march_incrc(ptr %fv1142)
  call void @march_incrc(ptr %fv1140)
  br label %br_body234
br_unique232:
  br label %br_body234
br_body234:
  %ld1145 = load ptr, ptr %$f1601_2.addr
  %res_slot1146 = alloca ptr
  %tgp1147 = getelementptr i8, ptr %ld1145, i64 8
  %tag1148 = load i32, ptr %tgp1147, align 4
  switch i32 %tag1148, label %case_default236 [
      i32 0, label %case_br237
  ]
case_br237:
  %fp1149 = getelementptr i8, ptr %ld1145, i64 16
  %fv1150 = load ptr, ptr %fp1149, align 8
  %$f1603_2.addr = alloca ptr
  store ptr %fv1150, ptr %$f1603_2.addr
  %fp1151 = getelementptr i8, ptr %ld1145, i64 24
  %fv1152 = load ptr, ptr %fp1151, align 8
  %$f1604_2.addr = alloca ptr
  store ptr %fv1152, ptr %$f1604_2.addr
  %freed1153 = call i64 @march_decrc_freed(ptr %ld1145)
  %freed_b1154 = icmp ne i64 %freed1153, 0
  br i1 %freed_b1154, label %br_unique238, label %br_shared239
br_shared239:
  call void @march_incrc(ptr %fv1152)
  call void @march_incrc(ptr %fv1150)
  br label %br_body240
br_unique238:
  br label %br_body240
br_body240:
  %ld1155 = load ptr, ptr %$f1602_2.addr
  %res_slot1156 = alloca ptr
  %tgp1157 = getelementptr i8, ptr %ld1155, i64 8
  %tag1158 = load i32, ptr %tgp1157, align 4
  switch i32 %tag1158, label %case_default242 [
      i32 0, label %case_br243
  ]
case_br243:
  %ld1159 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld1159)
  %ld1160 = load ptr, ptr %$f1604_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld1160, ptr %yn_3.addr
  %ld1161 = load ptr, ptr %$f1603_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld1161, ptr %y_3.addr
  %ld1162 = load ptr, ptr %$f1600.addr
  %xn_3.addr = alloca ptr
  store ptr %ld1162, ptr %xn_3.addr
  %ld1163 = load ptr, ptr %$f1599.addr
  %x_3.addr = alloca ptr
  store ptr %ld1163, ptr %x_3.addr
  %ld1164 = load ptr, ptr %yn_3.addr
  %ld1165 = load ptr, ptr %xn_3.addr
  %cv1168 = ptrtoint ptr %ld1164 to i64
  %cv1169 = ptrtoint ptr %ld1165 to i64
  %cmp1166 = icmp sle i64 %cv1168, %cv1169
  %ar1167 = zext i1 %cmp1166 to i64
  %$t1593_2.addr = alloca i64
  store i64 %ar1167, ptr %$t1593_2.addr
  %ld1170 = load i64, ptr %$t1593_2.addr
  %res_slot1171 = alloca ptr
  %bi1172 = trunc i64 %ld1170 to i1
  br i1 %bi1172, label %case_br246, label %case_default245
case_br246:
  %ld1173 = load ptr, ptr %y_3.addr
  %a_i44.addr = alloca ptr
  store ptr %ld1173, ptr %a_i44.addr
  %ld1174 = load ptr, ptr %x_3.addr
  %b_i45.addr = alloca ptr
  store ptr %ld1174, ptr %b_i45.addr
  %ld1175 = load ptr, ptr %cmp.addr
  %cmp_i46.addr = alloca ptr
  store ptr %ld1175, ptr %cmp_i46.addr
  %ld1176 = load ptr, ptr %a_i44.addr
  %ld1177 = load ptr, ptr %b_i45.addr
  %ld1178 = load ptr, ptr %cmp_i46.addr
  %cr1179 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1176, ptr %ld1177, ptr %ld1178)
  %merged_4.addr = alloca ptr
  store ptr %cr1179, ptr %merged_4.addr
  %ld1180 = load ptr, ptr %xn_3.addr
  %cv1181 = ptrtoint ptr %ld1180 to i64
  %ld1182 = load ptr, ptr %yn_3.addr
  %cv1183 = ptrtoint ptr %ld1182 to i64
  %ar1184 = add i64 %cv1181, %cv1183
  %$t1594_2.addr = alloca i64
  store i64 %ar1184, ptr %$t1594_2.addr
  %hp1185 = call ptr @march_alloc(i64 32)
  %tgp1186 = getelementptr i8, ptr %hp1185, i64 8
  store i32 0, ptr %tgp1186, align 4
  %ld1187 = load ptr, ptr %merged_4.addr
  %fp1188 = getelementptr i8, ptr %hp1185, i64 16
  store ptr %ld1187, ptr %fp1188, align 8
  %ld1189 = load i64, ptr %$t1594_2.addr
  %fp1190 = getelementptr i8, ptr %hp1185, i64 24
  store i64 %ld1189, ptr %fp1190, align 8
  %$t1595_2.addr = alloca ptr
  store ptr %hp1185, ptr %$t1595_2.addr
  %hp1191 = call ptr @march_alloc(i64 16)
  %tgp1192 = getelementptr i8, ptr %hp1191, i64 8
  store i32 0, ptr %tgp1192, align 4
  %$t1596_2.addr = alloca ptr
  store ptr %hp1191, ptr %$t1596_2.addr
  %hp1193 = call ptr @march_alloc(i64 32)
  %tgp1194 = getelementptr i8, ptr %hp1193, i64 8
  store i32 1, ptr %tgp1194, align 4
  %ld1195 = load ptr, ptr %$t1595_2.addr
  %fp1196 = getelementptr i8, ptr %hp1193, i64 16
  store ptr %ld1195, ptr %fp1196, align 8
  %ld1197 = load ptr, ptr %$t1596_2.addr
  %fp1198 = getelementptr i8, ptr %hp1193, i64 24
  store ptr %ld1197, ptr %fp1198, align 8
  store ptr %hp1193, ptr %res_slot1171
  br label %case_merge244
case_default245:
  %ld1199 = load ptr, ptr %stack.addr
  store ptr %ld1199, ptr %res_slot1171
  br label %case_merge244
case_merge244:
  %case_r1200 = load ptr, ptr %res_slot1171
  store ptr %case_r1200, ptr %res_slot1156
  br label %case_merge241
case_default242:
  %ld1201 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld1201)
  %ld1202 = load ptr, ptr %stack.addr
  store ptr %ld1202, ptr %res_slot1156
  br label %case_merge241
case_merge241:
  %case_r1203 = load ptr, ptr %res_slot1156
  store ptr %case_r1203, ptr %res_slot1146
  br label %case_merge235
case_default236:
  %ld1204 = load ptr, ptr %$f1601_2.addr
  call void @march_decrc(ptr %ld1204)
  %ld1205 = load ptr, ptr %stack.addr
  store ptr %ld1205, ptr %res_slot1146
  br label %case_merge235
case_merge235:
  %case_r1206 = load ptr, ptr %res_slot1146
  store ptr %case_r1206, ptr %res_slot1136
  br label %case_merge229
case_default230:
  %ld1207 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1207)
  %ld1208 = load ptr, ptr %stack.addr
  store ptr %ld1208, ptr %res_slot1136
  br label %case_merge229
case_merge229:
  %case_r1209 = load ptr, ptr %res_slot1136
  store ptr %case_r1209, ptr %res_slot841
  br label %case_merge169
case_merge169:
  %case_r1210 = load ptr, ptr %res_slot841
  store ptr %case_r1210, ptr %res_slot833
  br label %case_merge166
case_default167:
  %ld1211 = load ptr, ptr %$f1598.addr
  %res_slot1212 = alloca ptr
  %tgp1213 = getelementptr i8, ptr %ld1211, i64 8
  %tag1214 = load i32, ptr %tgp1213, align 4
  switch i32 %tag1214, label %case_default248 [
      i32 0, label %case_br249
  ]
case_br249:
  %fp1215 = getelementptr i8, ptr %ld1211, i64 16
  %fv1216 = load ptr, ptr %fp1215, align 8
  %$f1601_3.addr = alloca ptr
  store ptr %fv1216, ptr %$f1601_3.addr
  %fp1217 = getelementptr i8, ptr %ld1211, i64 24
  %fv1218 = load ptr, ptr %fp1217, align 8
  %$f1602_3.addr = alloca ptr
  store ptr %fv1218, ptr %$f1602_3.addr
  %freed1219 = call i64 @march_decrc_freed(ptr %ld1211)
  %freed_b1220 = icmp ne i64 %freed1219, 0
  br i1 %freed_b1220, label %br_unique250, label %br_shared251
br_shared251:
  call void @march_incrc(ptr %fv1218)
  call void @march_incrc(ptr %fv1216)
  br label %br_body252
br_unique250:
  br label %br_body252
br_body252:
  %ld1221 = load ptr, ptr %$f1601_3.addr
  %res_slot1222 = alloca ptr
  %tgp1223 = getelementptr i8, ptr %ld1221, i64 8
  %tag1224 = load i32, ptr %tgp1223, align 4
  switch i32 %tag1224, label %case_default254 [
      i32 0, label %case_br255
  ]
case_br255:
  %fp1225 = getelementptr i8, ptr %ld1221, i64 16
  %fv1226 = load ptr, ptr %fp1225, align 8
  %$f1603_3.addr = alloca ptr
  store ptr %fv1226, ptr %$f1603_3.addr
  %fp1227 = getelementptr i8, ptr %ld1221, i64 24
  %fv1228 = load ptr, ptr %fp1227, align 8
  %$f1604_3.addr = alloca ptr
  store ptr %fv1228, ptr %$f1604_3.addr
  %freed1229 = call i64 @march_decrc_freed(ptr %ld1221)
  %freed_b1230 = icmp ne i64 %freed1229, 0
  br i1 %freed_b1230, label %br_unique256, label %br_shared257
br_shared257:
  call void @march_incrc(ptr %fv1228)
  call void @march_incrc(ptr %fv1226)
  br label %br_body258
br_unique256:
  br label %br_body258
br_body258:
  %ld1231 = load ptr, ptr %$f1602_3.addr
  %res_slot1232 = alloca ptr
  %tgp1233 = getelementptr i8, ptr %ld1231, i64 8
  %tag1234 = load i32, ptr %tgp1233, align 4
  switch i32 %tag1234, label %case_default260 [
      i32 0, label %case_br261
  ]
case_br261:
  %ld1235 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld1235)
  %ld1236 = load ptr, ptr %$f1604_3.addr
  %yn_4.addr = alloca ptr
  store ptr %ld1236, ptr %yn_4.addr
  %ld1237 = load ptr, ptr %$f1603_3.addr
  %y_4.addr = alloca ptr
  store ptr %ld1237, ptr %y_4.addr
  %ld1238 = load ptr, ptr %$f1600.addr
  %xn_4.addr = alloca ptr
  store ptr %ld1238, ptr %xn_4.addr
  %ld1239 = load ptr, ptr %$f1599.addr
  %x_4.addr = alloca ptr
  store ptr %ld1239, ptr %x_4.addr
  %ld1240 = load ptr, ptr %yn_4.addr
  %ld1241 = load ptr, ptr %xn_4.addr
  %cv1244 = ptrtoint ptr %ld1240 to i64
  %cv1245 = ptrtoint ptr %ld1241 to i64
  %cmp1242 = icmp sle i64 %cv1244, %cv1245
  %ar1243 = zext i1 %cmp1242 to i64
  %$t1593_3.addr = alloca i64
  store i64 %ar1243, ptr %$t1593_3.addr
  %ld1246 = load i64, ptr %$t1593_3.addr
  %res_slot1247 = alloca ptr
  %bi1248 = trunc i64 %ld1246 to i1
  br i1 %bi1248, label %case_br264, label %case_default263
case_br264:
  %ld1249 = load ptr, ptr %y_4.addr
  %a_i41.addr = alloca ptr
  store ptr %ld1249, ptr %a_i41.addr
  %ld1250 = load ptr, ptr %x_4.addr
  %b_i42.addr = alloca ptr
  store ptr %ld1250, ptr %b_i42.addr
  %ld1251 = load ptr, ptr %cmp.addr
  %cmp_i43.addr = alloca ptr
  store ptr %ld1251, ptr %cmp_i43.addr
  %ld1252 = load ptr, ptr %a_i41.addr
  %ld1253 = load ptr, ptr %b_i42.addr
  %ld1254 = load ptr, ptr %cmp_i43.addr
  %cr1255 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1252, ptr %ld1253, ptr %ld1254)
  %merged_5.addr = alloca ptr
  store ptr %cr1255, ptr %merged_5.addr
  %ld1256 = load ptr, ptr %xn_4.addr
  %cv1257 = ptrtoint ptr %ld1256 to i64
  %ld1258 = load ptr, ptr %yn_4.addr
  %cv1259 = ptrtoint ptr %ld1258 to i64
  %ar1260 = add i64 %cv1257, %cv1259
  %$t1594_3.addr = alloca i64
  store i64 %ar1260, ptr %$t1594_3.addr
  %hp1261 = call ptr @march_alloc(i64 32)
  %tgp1262 = getelementptr i8, ptr %hp1261, i64 8
  store i32 0, ptr %tgp1262, align 4
  %ld1263 = load ptr, ptr %merged_5.addr
  %fp1264 = getelementptr i8, ptr %hp1261, i64 16
  store ptr %ld1263, ptr %fp1264, align 8
  %ld1265 = load i64, ptr %$t1594_3.addr
  %fp1266 = getelementptr i8, ptr %hp1261, i64 24
  store i64 %ld1265, ptr %fp1266, align 8
  %$t1595_3.addr = alloca ptr
  store ptr %hp1261, ptr %$t1595_3.addr
  %hp1267 = call ptr @march_alloc(i64 16)
  %tgp1268 = getelementptr i8, ptr %hp1267, i64 8
  store i32 0, ptr %tgp1268, align 4
  %$t1596_3.addr = alloca ptr
  store ptr %hp1267, ptr %$t1596_3.addr
  %hp1269 = call ptr @march_alloc(i64 32)
  %tgp1270 = getelementptr i8, ptr %hp1269, i64 8
  store i32 1, ptr %tgp1270, align 4
  %ld1271 = load ptr, ptr %$t1595_3.addr
  %fp1272 = getelementptr i8, ptr %hp1269, i64 16
  store ptr %ld1271, ptr %fp1272, align 8
  %ld1273 = load ptr, ptr %$t1596_3.addr
  %fp1274 = getelementptr i8, ptr %hp1269, i64 24
  store ptr %ld1273, ptr %fp1274, align 8
  store ptr %hp1269, ptr %res_slot1247
  br label %case_merge262
case_default263:
  %ld1275 = load ptr, ptr %stack.addr
  store ptr %ld1275, ptr %res_slot1247
  br label %case_merge262
case_merge262:
  %case_r1276 = load ptr, ptr %res_slot1247
  store ptr %case_r1276, ptr %res_slot1232
  br label %case_merge259
case_default260:
  %ld1277 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld1277)
  %ld1278 = load ptr, ptr %stack.addr
  store ptr %ld1278, ptr %res_slot1232
  br label %case_merge259
case_merge259:
  %case_r1279 = load ptr, ptr %res_slot1232
  store ptr %case_r1279, ptr %res_slot1222
  br label %case_merge253
case_default254:
  %ld1280 = load ptr, ptr %$f1601_3.addr
  call void @march_decrc(ptr %ld1280)
  %ld1281 = load ptr, ptr %stack.addr
  store ptr %ld1281, ptr %res_slot1222
  br label %case_merge253
case_merge253:
  %case_r1282 = load ptr, ptr %res_slot1222
  store ptr %case_r1282, ptr %res_slot1212
  br label %case_merge247
case_default248:
  %ld1283 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1283)
  %ld1284 = load ptr, ptr %stack.addr
  store ptr %ld1284, ptr %res_slot1212
  br label %case_merge247
case_merge247:
  %case_r1285 = load ptr, ptr %res_slot1212
  store ptr %case_r1285, ptr %res_slot833
  br label %case_merge166
case_merge166:
  %case_r1286 = load ptr, ptr %res_slot833
  store ptr %case_r1286, ptr %res_slot823
  br label %case_merge160
case_default161:
  %ld1287 = load ptr, ptr %$f1597.addr
  call void @march_decrc(ptr %ld1287)
  %ld1288 = load ptr, ptr %stack.addr
  store ptr %ld1288, ptr %res_slot823
  br label %case_merge160
case_merge160:
  %case_r1289 = load ptr, ptr %res_slot823
  store ptr %case_r1289, ptr %res_slot815
  br label %case_merge157
case_default158:
  %ld1290 = load ptr, ptr %stack.addr
  store ptr %ld1290, ptr %res_slot815
  br label %case_merge157
case_merge157:
  %case_r1291 = load ptr, ptr %res_slot815
  ret ptr %case_r1291
}

define ptr @Sort.reverse_list$List_T_List_V__4971_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1292 = call ptr @march_alloc(i64 24)
  %tgp1293 = getelementptr i8, ptr %hp1292, i64 8
  store i32 0, ptr %tgp1293, align 4
  %fp1294 = getelementptr i8, ptr %hp1292, i64 16
  store ptr @go$apply$35, ptr %fp1294, align 8
  %go.addr = alloca ptr
  store ptr %hp1292, ptr %go.addr
  %hp1295 = call ptr @march_alloc(i64 16)
  %tgp1296 = getelementptr i8, ptr %hp1295, i64 8
  store i32 0, ptr %tgp1296, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp1295, ptr %$t1355.addr
  %ld1297 = load ptr, ptr %go.addr
  %fp1298 = getelementptr i8, ptr %ld1297, i64 16
  %fv1299 = load ptr, ptr %fp1298, align 8
  %ld1300 = load ptr, ptr %xs.addr
  %ld1301 = load ptr, ptr %$t1355.addr
  %cr1302 = call ptr (ptr, ptr, ptr) %fv1299(ptr %ld1297, ptr %ld1300, ptr %ld1301)
  ret ptr %cr1302
}

define ptr @Sort.extend_run$List_V__4971$Int$List_V__4971$Fn_V__4971_Fn_V__4971_Bool(ptr %run.arg, i64 %run_len.arg, ptr %rest.arg, ptr %cmp.arg) {
entry:
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %rest.addr = alloca ptr
  store ptr %rest.arg, ptr %rest.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1303 = load i64, ptr %run_len.addr
  %cmp1304 = icmp sge i64 %ld1303, 16
  %ar1305 = zext i1 %cmp1304 to i64
  %$t1556.addr = alloca i64
  store i64 %ar1305, ptr %$t1556.addr
  %ld1306 = load i64, ptr %$t1556.addr
  %res_slot1307 = alloca ptr
  %bi1308 = trunc i64 %ld1306 to i1
  br i1 %bi1308, label %case_br267, label %case_default266
case_br267:
  %hp1309 = call ptr @march_alloc(i64 40)
  %tgp1310 = getelementptr i8, ptr %hp1309, i64 8
  store i32 0, ptr %tgp1310, align 4
  %ld1311 = load ptr, ptr %run.addr
  %fp1312 = getelementptr i8, ptr %hp1309, i64 16
  store ptr %ld1311, ptr %fp1312, align 8
  %ld1313 = load i64, ptr %run_len.addr
  %fp1314 = getelementptr i8, ptr %hp1309, i64 24
  store i64 %ld1313, ptr %fp1314, align 8
  %ld1315 = load ptr, ptr %rest.addr
  %fp1316 = getelementptr i8, ptr %hp1309, i64 32
  store ptr %ld1315, ptr %fp1316, align 8
  store ptr %hp1309, ptr %res_slot1307
  br label %case_merge265
case_default266:
  %ld1317 = load ptr, ptr %rest.addr
  %res_slot1318 = alloca ptr
  %tgp1319 = getelementptr i8, ptr %ld1317, i64 8
  %tag1320 = load i32, ptr %tgp1319, align 4
  switch i32 %tag1320, label %case_default269 [
      i32 0, label %case_br270
      i32 1, label %case_br271
  ]
case_br270:
  %ld1321 = load ptr, ptr %rest.addr
  %rc1322 = load i64, ptr %ld1321, align 8
  %uniq1323 = icmp eq i64 %rc1322, 1
  %fbip_slot1324 = alloca ptr
  br i1 %uniq1323, label %fbip_reuse272, label %fbip_fresh273
fbip_reuse272:
  %tgp1325 = getelementptr i8, ptr %ld1321, i64 8
  store i32 0, ptr %tgp1325, align 4
  store ptr %ld1321, ptr %fbip_slot1324
  br label %fbip_merge274
fbip_fresh273:
  call void @march_decrc(ptr %ld1321)
  %hp1326 = call ptr @march_alloc(i64 16)
  %tgp1327 = getelementptr i8, ptr %hp1326, i64 8
  store i32 0, ptr %tgp1327, align 4
  store ptr %hp1326, ptr %fbip_slot1324
  br label %fbip_merge274
fbip_merge274:
  %fbip_r1328 = load ptr, ptr %fbip_slot1324
  %$t1557.addr = alloca ptr
  store ptr %fbip_r1328, ptr %$t1557.addr
  %hp1329 = call ptr @march_alloc(i64 40)
  %tgp1330 = getelementptr i8, ptr %hp1329, i64 8
  store i32 0, ptr %tgp1330, align 4
  %ld1331 = load ptr, ptr %run.addr
  %fp1332 = getelementptr i8, ptr %hp1329, i64 16
  store ptr %ld1331, ptr %fp1332, align 8
  %ld1333 = load i64, ptr %run_len.addr
  %fp1334 = getelementptr i8, ptr %hp1329, i64 24
  store i64 %ld1333, ptr %fp1334, align 8
  %ld1335 = load ptr, ptr %$t1557.addr
  %fp1336 = getelementptr i8, ptr %hp1329, i64 32
  store ptr %ld1335, ptr %fp1336, align 8
  store ptr %hp1329, ptr %res_slot1318
  br label %case_merge268
case_br271:
  %fp1337 = getelementptr i8, ptr %ld1317, i64 16
  %fv1338 = load ptr, ptr %fp1337, align 8
  %$f1560.addr = alloca ptr
  store ptr %fv1338, ptr %$f1560.addr
  %fp1339 = getelementptr i8, ptr %ld1317, i64 24
  %fv1340 = load ptr, ptr %fp1339, align 8
  %$f1561.addr = alloca ptr
  store ptr %fv1340, ptr %$f1561.addr
  %freed1341 = call i64 @march_decrc_freed(ptr %ld1317)
  %freed_b1342 = icmp ne i64 %freed1341, 0
  br i1 %freed_b1342, label %br_unique275, label %br_shared276
br_shared276:
  call void @march_incrc(ptr %fv1340)
  call void @march_incrc(ptr %fv1338)
  br label %br_body277
br_unique275:
  br label %br_body277
br_body277:
  %ld1343 = load ptr, ptr %$f1561.addr
  %t.addr = alloca ptr
  store ptr %ld1343, ptr %t.addr
  %ld1344 = load ptr, ptr %$f1560.addr
  %h.addr = alloca ptr
  store ptr %ld1344, ptr %h.addr
  %ld1345 = load ptr, ptr %h.addr
  %ld1346 = load ptr, ptr %run.addr
  %ld1347 = load ptr, ptr %cmp.addr
  %cr1348 = call ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1345, ptr %ld1346, ptr %ld1347)
  %$t1558.addr = alloca ptr
  store ptr %cr1348, ptr %$t1558.addr
  %ld1349 = load i64, ptr %run_len.addr
  %ar1350 = add i64 %ld1349, 1
  %$t1559.addr = alloca i64
  store i64 %ar1350, ptr %$t1559.addr
  %ld1351 = load ptr, ptr %$t1558.addr
  %ld1352 = load i64, ptr %$t1559.addr
  %ld1353 = load ptr, ptr %t.addr
  %ld1354 = load ptr, ptr %cmp.addr
  %cr1355 = call ptr @Sort.extend_run$List_V__4910$Int$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1351, i64 %ld1352, ptr %ld1353, ptr %ld1354)
  store ptr %cr1355, ptr %res_slot1318
  br label %case_merge268
case_default269:
  unreachable
case_merge268:
  %case_r1356 = load ptr, ptr %res_slot1318
  store ptr %case_r1356, ptr %res_slot1307
  br label %case_merge265
case_merge265:
  %case_r1357 = load ptr, ptr %res_slot1307
  ret ptr %case_r1357
}

define ptr @Sort.reverse_list$List_V__4971(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1358 = call ptr @march_alloc(i64 24)
  %tgp1359 = getelementptr i8, ptr %hp1358, i64 8
  store i32 0, ptr %tgp1359, align 4
  %fp1360 = getelementptr i8, ptr %hp1358, i64 16
  store ptr @go$apply$36, ptr %fp1360, align 8
  %go.addr = alloca ptr
  store ptr %hp1358, ptr %go.addr
  %hp1361 = call ptr @march_alloc(i64 16)
  %tgp1362 = getelementptr i8, ptr %hp1361, i64 8
  store i32 0, ptr %tgp1362, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp1361, ptr %$t1355.addr
  %ld1363 = load ptr, ptr %go.addr
  %fp1364 = getelementptr i8, ptr %ld1363, i64 16
  %fv1365 = load ptr, ptr %fp1364, align 8
  %ld1366 = load ptr, ptr %xs.addr
  %ld1367 = load ptr, ptr %$t1355.addr
  %cr1368 = call ptr (ptr, ptr, ptr) %fv1365(ptr %ld1363, ptr %ld1366, ptr %ld1367)
  ret ptr %cr1368
}

define i64 @Sort.cmp2$Fn_V__4971_Fn_V__4971_Bool$V__4971$V__4971(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1369 = load ptr, ptr %cmp.addr
  %fp1370 = getelementptr i8, ptr %ld1369, i64 16
  %fv1371 = load ptr, ptr %fp1370, align 8
  %ld1372 = load ptr, ptr %x.addr
  %cr1373 = call ptr (ptr, ptr) %fv1371(ptr %ld1369, ptr %ld1372)
  %f.addr = alloca ptr
  store ptr %cr1373, ptr %f.addr
  %ld1374 = load ptr, ptr %f.addr
  %fp1375 = getelementptr i8, ptr %ld1374, i64 16
  %fv1376 = load ptr, ptr %fp1375, align 8
  %ld1377 = load ptr, ptr %y.addr
  %cr1378 = call i64 (ptr, ptr) %fv1376(ptr %ld1374, ptr %ld1377)
  ret i64 %cr1378
}

define ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1379 = load ptr, ptr %xs.addr
  %res_slot1380 = alloca ptr
  %tgp1381 = getelementptr i8, ptr %ld1379, i64 8
  %tag1382 = load i32, ptr %tgp1381, align 4
  switch i32 %tag1382, label %case_default279 [
      i32 0, label %case_br280
      i32 1, label %case_br281
  ]
case_br280:
  %ld1383 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld1383)
  %ld1384 = load ptr, ptr %ys.addr
  store ptr %ld1384, ptr %res_slot1380
  br label %case_merge278
case_br281:
  %fp1385 = getelementptr i8, ptr %ld1379, i64 16
  %fv1386 = load ptr, ptr %fp1385, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv1386, ptr %$f1372.addr
  %fp1387 = getelementptr i8, ptr %ld1379, i64 24
  %fv1388 = load ptr, ptr %fp1387, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv1388, ptr %$f1373.addr
  %ld1389 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld1389, ptr %xt.addr
  %ld1390 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld1390, ptr %x.addr
  %ld1391 = load ptr, ptr %ys.addr
  %res_slot1392 = alloca ptr
  %tgp1393 = getelementptr i8, ptr %ld1391, i64 8
  %tag1394 = load i32, ptr %tgp1393, align 4
  switch i32 %tag1394, label %case_default283 [
      i32 0, label %case_br284
      i32 1, label %case_br285
  ]
case_br284:
  %ld1395 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld1395)
  %ld1396 = load ptr, ptr %xs.addr
  store ptr %ld1396, ptr %res_slot1392
  br label %case_merge282
case_br285:
  %fp1397 = getelementptr i8, ptr %ld1391, i64 16
  %fv1398 = load ptr, ptr %fp1397, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv1398, ptr %$f1370.addr
  %fp1399 = getelementptr i8, ptr %ld1391, i64 24
  %fv1400 = load ptr, ptr %fp1399, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv1400, ptr %$f1371.addr
  %ld1401 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld1401, ptr %yt.addr
  %ld1402 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld1402, ptr %y.addr
  %ld1403 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1403)
  %ld1404 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld1404)
  %ld1405 = load ptr, ptr %cmp.addr
  %ld1406 = load ptr, ptr %x.addr
  %ld1407 = load ptr, ptr %y.addr
  %cr1408 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld1405, ptr %ld1406, ptr %ld1407)
  %$t1367.addr = alloca i64
  store i64 %cr1408, ptr %$t1367.addr
  %ld1409 = load i64, ptr %$t1367.addr
  %res_slot1410 = alloca ptr
  %bi1411 = trunc i64 %ld1409 to i1
  br i1 %bi1411, label %case_br288, label %case_default287
case_br288:
  %ld1412 = load ptr, ptr %xt.addr
  %ld1413 = load ptr, ptr %ys.addr
  %ld1414 = load ptr, ptr %cmp.addr
  %cr1415 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1412, ptr %ld1413, ptr %ld1414)
  %$t1368.addr = alloca ptr
  store ptr %cr1415, ptr %$t1368.addr
  %hp1416 = call ptr @march_alloc(i64 32)
  %tgp1417 = getelementptr i8, ptr %hp1416, i64 8
  store i32 1, ptr %tgp1417, align 4
  %ld1418 = load ptr, ptr %x.addr
  %fp1419 = getelementptr i8, ptr %hp1416, i64 16
  store ptr %ld1418, ptr %fp1419, align 8
  %ld1420 = load ptr, ptr %$t1368.addr
  %fp1421 = getelementptr i8, ptr %hp1416, i64 24
  store ptr %ld1420, ptr %fp1421, align 8
  store ptr %hp1416, ptr %res_slot1410
  br label %case_merge286
case_default287:
  %ld1422 = load ptr, ptr %xs.addr
  %ld1423 = load ptr, ptr %yt.addr
  %ld1424 = load ptr, ptr %cmp.addr
  %cr1425 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1422, ptr %ld1423, ptr %ld1424)
  %$t1369.addr = alloca ptr
  store ptr %cr1425, ptr %$t1369.addr
  %hp1426 = call ptr @march_alloc(i64 32)
  %tgp1427 = getelementptr i8, ptr %hp1426, i64 8
  store i32 1, ptr %tgp1427, align 4
  %ld1428 = load ptr, ptr %y.addr
  %fp1429 = getelementptr i8, ptr %hp1426, i64 16
  store ptr %ld1428, ptr %fp1429, align 8
  %ld1430 = load ptr, ptr %$t1369.addr
  %fp1431 = getelementptr i8, ptr %hp1426, i64 24
  store ptr %ld1430, ptr %fp1431, align 8
  store ptr %hp1426, ptr %res_slot1410
  br label %case_merge286
case_merge286:
  %case_r1432 = load ptr, ptr %res_slot1410
  store ptr %case_r1432, ptr %res_slot1392
  br label %case_merge282
case_default283:
  unreachable
case_merge282:
  %case_r1433 = load ptr, ptr %res_slot1392
  store ptr %case_r1433, ptr %res_slot1380
  br label %case_merge278
case_default279:
  unreachable
case_merge278:
  %case_r1434 = load ptr, ptr %res_slot1380
  ret ptr %case_r1434
}

define ptr @Sort.extend_run$List_V__4910$Int$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %run.arg, i64 %run_len.arg, ptr %rest.arg, ptr %cmp.arg) {
entry:
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %rest.addr = alloca ptr
  store ptr %rest.arg, ptr %rest.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1435 = load i64, ptr %run_len.addr
  %cmp1436 = icmp sge i64 %ld1435, 16
  %ar1437 = zext i1 %cmp1436 to i64
  %$t1556.addr = alloca i64
  store i64 %ar1437, ptr %$t1556.addr
  %ld1438 = load i64, ptr %$t1556.addr
  %res_slot1439 = alloca ptr
  %bi1440 = trunc i64 %ld1438 to i1
  br i1 %bi1440, label %case_br291, label %case_default290
case_br291:
  %hp1441 = call ptr @march_alloc(i64 40)
  %tgp1442 = getelementptr i8, ptr %hp1441, i64 8
  store i32 0, ptr %tgp1442, align 4
  %ld1443 = load ptr, ptr %run.addr
  %fp1444 = getelementptr i8, ptr %hp1441, i64 16
  store ptr %ld1443, ptr %fp1444, align 8
  %ld1445 = load i64, ptr %run_len.addr
  %fp1446 = getelementptr i8, ptr %hp1441, i64 24
  store i64 %ld1445, ptr %fp1446, align 8
  %ld1447 = load ptr, ptr %rest.addr
  %fp1448 = getelementptr i8, ptr %hp1441, i64 32
  store ptr %ld1447, ptr %fp1448, align 8
  store ptr %hp1441, ptr %res_slot1439
  br label %case_merge289
case_default290:
  %ld1449 = load ptr, ptr %rest.addr
  %res_slot1450 = alloca ptr
  %tgp1451 = getelementptr i8, ptr %ld1449, i64 8
  %tag1452 = load i32, ptr %tgp1451, align 4
  switch i32 %tag1452, label %case_default293 [
      i32 0, label %case_br294
      i32 1, label %case_br295
  ]
case_br294:
  %ld1453 = load ptr, ptr %rest.addr
  %rc1454 = load i64, ptr %ld1453, align 8
  %uniq1455 = icmp eq i64 %rc1454, 1
  %fbip_slot1456 = alloca ptr
  br i1 %uniq1455, label %fbip_reuse296, label %fbip_fresh297
fbip_reuse296:
  %tgp1457 = getelementptr i8, ptr %ld1453, i64 8
  store i32 0, ptr %tgp1457, align 4
  store ptr %ld1453, ptr %fbip_slot1456
  br label %fbip_merge298
fbip_fresh297:
  call void @march_decrc(ptr %ld1453)
  %hp1458 = call ptr @march_alloc(i64 16)
  %tgp1459 = getelementptr i8, ptr %hp1458, i64 8
  store i32 0, ptr %tgp1459, align 4
  store ptr %hp1458, ptr %fbip_slot1456
  br label %fbip_merge298
fbip_merge298:
  %fbip_r1460 = load ptr, ptr %fbip_slot1456
  %$t1557.addr = alloca ptr
  store ptr %fbip_r1460, ptr %$t1557.addr
  %hp1461 = call ptr @march_alloc(i64 40)
  %tgp1462 = getelementptr i8, ptr %hp1461, i64 8
  store i32 0, ptr %tgp1462, align 4
  %ld1463 = load ptr, ptr %run.addr
  %fp1464 = getelementptr i8, ptr %hp1461, i64 16
  store ptr %ld1463, ptr %fp1464, align 8
  %ld1465 = load i64, ptr %run_len.addr
  %fp1466 = getelementptr i8, ptr %hp1461, i64 24
  store i64 %ld1465, ptr %fp1466, align 8
  %ld1467 = load ptr, ptr %$t1557.addr
  %fp1468 = getelementptr i8, ptr %hp1461, i64 32
  store ptr %ld1467, ptr %fp1468, align 8
  store ptr %hp1461, ptr %res_slot1450
  br label %case_merge292
case_br295:
  %fp1469 = getelementptr i8, ptr %ld1449, i64 16
  %fv1470 = load ptr, ptr %fp1469, align 8
  %$f1560.addr = alloca ptr
  store ptr %fv1470, ptr %$f1560.addr
  %fp1471 = getelementptr i8, ptr %ld1449, i64 24
  %fv1472 = load ptr, ptr %fp1471, align 8
  %$f1561.addr = alloca ptr
  store ptr %fv1472, ptr %$f1561.addr
  %freed1473 = call i64 @march_decrc_freed(ptr %ld1449)
  %freed_b1474 = icmp ne i64 %freed1473, 0
  br i1 %freed_b1474, label %br_unique299, label %br_shared300
br_shared300:
  call void @march_incrc(ptr %fv1472)
  call void @march_incrc(ptr %fv1470)
  br label %br_body301
br_unique299:
  br label %br_body301
br_body301:
  %ld1475 = load ptr, ptr %$f1561.addr
  %t.addr = alloca ptr
  store ptr %ld1475, ptr %t.addr
  %ld1476 = load ptr, ptr %$f1560.addr
  %h.addr = alloca ptr
  store ptr %ld1476, ptr %h.addr
  %ld1477 = load ptr, ptr %h.addr
  %ld1478 = load ptr, ptr %run.addr
  %ld1479 = load ptr, ptr %cmp.addr
  %cr1480 = call ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1477, ptr %ld1478, ptr %ld1479)
  %$t1558.addr = alloca ptr
  store ptr %cr1480, ptr %$t1558.addr
  %ld1481 = load i64, ptr %run_len.addr
  %ar1482 = add i64 %ld1481, 1
  %$t1559.addr = alloca i64
  store i64 %ar1482, ptr %$t1559.addr
  %ld1483 = load ptr, ptr %$t1558.addr
  %ld1484 = load i64, ptr %$t1559.addr
  %ld1485 = load ptr, ptr %t.addr
  %ld1486 = load ptr, ptr %cmp.addr
  %cr1487 = call ptr @Sort.extend_run$List_V__4910$Int$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1483, i64 %ld1484, ptr %ld1485, ptr %ld1486)
  store ptr %cr1487, ptr %res_slot1450
  br label %case_merge292
case_default293:
  unreachable
case_merge292:
  %case_r1488 = load ptr, ptr %res_slot1450
  store ptr %case_r1488, ptr %res_slot1439
  br label %case_merge289
case_merge289:
  %case_r1489 = load ptr, ptr %res_slot1439
  ret ptr %case_r1489
}

define ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1490 = load ptr, ptr %sorted.addr
  %res_slot1491 = alloca ptr
  %tgp1492 = getelementptr i8, ptr %ld1490, i64 8
  %tag1493 = load i32, ptr %tgp1492, align 4
  switch i32 %tag1493, label %case_default303 [
      i32 0, label %case_br304
      i32 1, label %case_br305
  ]
case_br304:
  %ld1494 = load ptr, ptr %sorted.addr
  %rc1495 = load i64, ptr %ld1494, align 8
  %uniq1496 = icmp eq i64 %rc1495, 1
  %fbip_slot1497 = alloca ptr
  br i1 %uniq1496, label %fbip_reuse306, label %fbip_fresh307
fbip_reuse306:
  %tgp1498 = getelementptr i8, ptr %ld1494, i64 8
  store i32 0, ptr %tgp1498, align 4
  store ptr %ld1494, ptr %fbip_slot1497
  br label %fbip_merge308
fbip_fresh307:
  call void @march_decrc(ptr %ld1494)
  %hp1499 = call ptr @march_alloc(i64 16)
  %tgp1500 = getelementptr i8, ptr %hp1499, i64 8
  store i32 0, ptr %tgp1500, align 4
  store ptr %hp1499, ptr %fbip_slot1497
  br label %fbip_merge308
fbip_merge308:
  %fbip_r1501 = load ptr, ptr %fbip_slot1497
  %$t1547.addr = alloca ptr
  store ptr %fbip_r1501, ptr %$t1547.addr
  %hp1502 = call ptr @march_alloc(i64 32)
  %tgp1503 = getelementptr i8, ptr %hp1502, i64 8
  store i32 1, ptr %tgp1503, align 4
  %ld1504 = load ptr, ptr %x.addr
  %fp1505 = getelementptr i8, ptr %hp1502, i64 16
  store ptr %ld1504, ptr %fp1505, align 8
  %ld1506 = load ptr, ptr %$t1547.addr
  %fp1507 = getelementptr i8, ptr %hp1502, i64 24
  store ptr %ld1506, ptr %fp1507, align 8
  store ptr %hp1502, ptr %res_slot1491
  br label %case_merge302
case_br305:
  %fp1508 = getelementptr i8, ptr %ld1490, i64 16
  %fv1509 = load ptr, ptr %fp1508, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv1509, ptr %$f1550.addr
  %fp1510 = getelementptr i8, ptr %ld1490, i64 24
  %fv1511 = load ptr, ptr %fp1510, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv1511, ptr %$f1551.addr
  %ld1512 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld1512, ptr %t.addr
  %ld1513 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld1513, ptr %h.addr
  %ld1514 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1514)
  %ld1515 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1515)
  %ld1516 = load ptr, ptr %cmp.addr
  %ld1517 = load ptr, ptr %x.addr
  %ld1518 = load ptr, ptr %h.addr
  %cr1519 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld1516, ptr %ld1517, ptr %ld1518)
  %$t1548.addr = alloca i64
  store i64 %cr1519, ptr %$t1548.addr
  %ld1520 = load i64, ptr %$t1548.addr
  %res_slot1521 = alloca ptr
  %bi1522 = trunc i64 %ld1520 to i1
  br i1 %bi1522, label %case_br311, label %case_default310
case_br311:
  %hp1523 = call ptr @march_alloc(i64 32)
  %tgp1524 = getelementptr i8, ptr %hp1523, i64 8
  store i32 1, ptr %tgp1524, align 4
  %ld1525 = load ptr, ptr %x.addr
  %fp1526 = getelementptr i8, ptr %hp1523, i64 16
  store ptr %ld1525, ptr %fp1526, align 8
  %ld1527 = load ptr, ptr %sorted.addr
  %fp1528 = getelementptr i8, ptr %hp1523, i64 24
  store ptr %ld1527, ptr %fp1528, align 8
  store ptr %hp1523, ptr %res_slot1521
  br label %case_merge309
case_default310:
  %ld1529 = load ptr, ptr %x.addr
  %ld1530 = load ptr, ptr %t.addr
  %ld1531 = load ptr, ptr %cmp.addr
  %cr1532 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld1529, ptr %ld1530, ptr %ld1531)
  %$t1549.addr = alloca ptr
  store ptr %cr1532, ptr %$t1549.addr
  %hp1533 = call ptr @march_alloc(i64 32)
  %tgp1534 = getelementptr i8, ptr %hp1533, i64 8
  store i32 1, ptr %tgp1534, align 4
  %ld1535 = load ptr, ptr %h.addr
  %fp1536 = getelementptr i8, ptr %hp1533, i64 16
  store ptr %ld1535, ptr %fp1536, align 8
  %ld1537 = load ptr, ptr %$t1549.addr
  %fp1538 = getelementptr i8, ptr %hp1533, i64 24
  store ptr %ld1537, ptr %fp1538, align 8
  store ptr %hp1533, ptr %res_slot1521
  br label %case_merge309
case_merge309:
  %case_r1539 = load ptr, ptr %res_slot1521
  store ptr %case_r1539, ptr %res_slot1491
  br label %case_merge302
case_default303:
  unreachable
case_merge302:
  %case_r1540 = load ptr, ptr %res_slot1491
  ret ptr %case_r1540
}

define ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1541 = load ptr, ptr %sorted.addr
  %res_slot1542 = alloca ptr
  %tgp1543 = getelementptr i8, ptr %ld1541, i64 8
  %tag1544 = load i32, ptr %tgp1543, align 4
  switch i32 %tag1544, label %case_default313 [
      i32 0, label %case_br314
      i32 1, label %case_br315
  ]
case_br314:
  %ld1545 = load ptr, ptr %sorted.addr
  %rc1546 = load i64, ptr %ld1545, align 8
  %uniq1547 = icmp eq i64 %rc1546, 1
  %fbip_slot1548 = alloca ptr
  br i1 %uniq1547, label %fbip_reuse316, label %fbip_fresh317
fbip_reuse316:
  %tgp1549 = getelementptr i8, ptr %ld1545, i64 8
  store i32 0, ptr %tgp1549, align 4
  store ptr %ld1545, ptr %fbip_slot1548
  br label %fbip_merge318
fbip_fresh317:
  call void @march_decrc(ptr %ld1545)
  %hp1550 = call ptr @march_alloc(i64 16)
  %tgp1551 = getelementptr i8, ptr %hp1550, i64 8
  store i32 0, ptr %tgp1551, align 4
  store ptr %hp1550, ptr %fbip_slot1548
  br label %fbip_merge318
fbip_merge318:
  %fbip_r1552 = load ptr, ptr %fbip_slot1548
  %$t1547.addr = alloca ptr
  store ptr %fbip_r1552, ptr %$t1547.addr
  %hp1553 = call ptr @march_alloc(i64 32)
  %tgp1554 = getelementptr i8, ptr %hp1553, i64 8
  store i32 1, ptr %tgp1554, align 4
  %ld1555 = load ptr, ptr %x.addr
  %fp1556 = getelementptr i8, ptr %hp1553, i64 16
  store ptr %ld1555, ptr %fp1556, align 8
  %ld1557 = load ptr, ptr %$t1547.addr
  %fp1558 = getelementptr i8, ptr %hp1553, i64 24
  store ptr %ld1557, ptr %fp1558, align 8
  store ptr %hp1553, ptr %res_slot1542
  br label %case_merge312
case_br315:
  %fp1559 = getelementptr i8, ptr %ld1541, i64 16
  %fv1560 = load ptr, ptr %fp1559, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv1560, ptr %$f1550.addr
  %fp1561 = getelementptr i8, ptr %ld1541, i64 24
  %fv1562 = load ptr, ptr %fp1561, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv1562, ptr %$f1551.addr
  %ld1563 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld1563, ptr %t.addr
  %ld1564 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld1564, ptr %h.addr
  %ld1565 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1565)
  %ld1566 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1566)
  %ld1567 = load ptr, ptr %cmp.addr
  %ld1568 = load ptr, ptr %x.addr
  %ld1569 = load ptr, ptr %h.addr
  %cr1570 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld1567, ptr %ld1568, ptr %ld1569)
  %$t1548.addr = alloca i64
  store i64 %cr1570, ptr %$t1548.addr
  %ld1571 = load i64, ptr %$t1548.addr
  %res_slot1572 = alloca ptr
  %bi1573 = trunc i64 %ld1571 to i1
  br i1 %bi1573, label %case_br321, label %case_default320
case_br321:
  %hp1574 = call ptr @march_alloc(i64 32)
  %tgp1575 = getelementptr i8, ptr %hp1574, i64 8
  store i32 1, ptr %tgp1575, align 4
  %ld1576 = load ptr, ptr %x.addr
  %fp1577 = getelementptr i8, ptr %hp1574, i64 16
  store ptr %ld1576, ptr %fp1577, align 8
  %ld1578 = load ptr, ptr %sorted.addr
  %fp1579 = getelementptr i8, ptr %hp1574, i64 24
  store ptr %ld1578, ptr %fp1579, align 8
  store ptr %hp1574, ptr %res_slot1572
  br label %case_merge319
case_default320:
  %ld1580 = load ptr, ptr %x.addr
  %ld1581 = load ptr, ptr %t.addr
  %ld1582 = load ptr, ptr %cmp.addr
  %cr1583 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld1580, ptr %ld1581, ptr %ld1582)
  %$t1549.addr = alloca ptr
  store ptr %cr1583, ptr %$t1549.addr
  %hp1584 = call ptr @march_alloc(i64 32)
  %tgp1585 = getelementptr i8, ptr %hp1584, i64 8
  store i32 1, ptr %tgp1585, align 4
  %ld1586 = load ptr, ptr %h.addr
  %fp1587 = getelementptr i8, ptr %hp1584, i64 16
  store ptr %ld1586, ptr %fp1587, align 8
  %ld1588 = load ptr, ptr %$t1549.addr
  %fp1589 = getelementptr i8, ptr %hp1584, i64 24
  store ptr %ld1588, ptr %fp1589, align 8
  store ptr %hp1584, ptr %res_slot1572
  br label %case_merge319
case_merge319:
  %case_r1590 = load ptr, ptr %res_slot1572
  store ptr %case_r1590, ptr %res_slot1542
  br label %case_merge312
case_default313:
  unreachable
case_merge312:
  %case_r1591 = load ptr, ptr %res_slot1542
  ret ptr %case_r1591
}

define i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1592 = load ptr, ptr %cmp.addr
  %fp1593 = getelementptr i8, ptr %ld1592, i64 16
  %fv1594 = load ptr, ptr %fp1593, align 8
  %ld1595 = load ptr, ptr %x.addr
  %cr1596 = call ptr (ptr, ptr) %fv1594(ptr %ld1592, ptr %ld1595)
  %f.addr = alloca ptr
  store ptr %cr1596, ptr %f.addr
  %ld1597 = load ptr, ptr %f.addr
  %fp1598 = getelementptr i8, ptr %ld1597, i64 16
  %fv1599 = load ptr, ptr %fp1598, align 8
  %ld1600 = load ptr, ptr %y.addr
  %cr1601 = call i64 (ptr, ptr) %fv1599(ptr %ld1597, ptr %ld1600)
  ret i64 %cr1601
}

define ptr @$lam2016$apply$21(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp1602 = call ptr @march_alloc(i64 32)
  %tgp1603 = getelementptr i8, ptr %hp1602, i64 8
  store i32 0, ptr %tgp1603, align 4
  %fp1604 = getelementptr i8, ptr %hp1602, i64 16
  store ptr @$lam2017$apply$22, ptr %fp1604, align 8
  %ld1605 = load ptr, ptr %x.addr
  %fp1606 = getelementptr i8, ptr %hp1602, i64 24
  store ptr %ld1605, ptr %fp1606, align 8
  ret ptr %hp1602
}

define i64 @$lam2017$apply$22(ptr %$clo.arg, ptr %y.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1607 = load ptr, ptr %$clo.addr
  %fp1608 = getelementptr i8, ptr %ld1607, i64 24
  %fv1609 = load ptr, ptr %fp1608, align 8
  %x.addr = alloca ptr
  store ptr %fv1609, ptr %x.addr
  %ld1610 = load ptr, ptr %x.addr
  %ld1611 = load ptr, ptr %y.addr
  %cv1614 = ptrtoint ptr %ld1610 to i64
  %cv1615 = ptrtoint ptr %ld1611 to i64
  %cmp1612 = icmp sle i64 %cv1614, %cv1615
  %ar1613 = zext i1 %cmp1612 to i64
  ret i64 %ar1613
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
  %ld1616 = load ptr, ptr %$clo.addr
  %take_k.addr = alloca ptr
  store ptr %ld1616, ptr %take_k.addr
  %ld1617 = load i64, ptr %k.addr
  %cmp1618 = icmp eq i64 %ld1617, 0
  %ar1619 = zext i1 %cmp1618 to i64
  %$t1374.addr = alloca i64
  store i64 %ar1619, ptr %$t1374.addr
  %ld1620 = load i64, ptr %$t1374.addr
  %res_slot1621 = alloca ptr
  %bi1622 = trunc i64 %ld1620 to i1
  br i1 %bi1622, label %case_br324, label %case_default323
case_br324:
  %ld1623 = load ptr, ptr %acc.addr
  %cr1624 = call ptr @Sort.reverse_list$List_V__4510(ptr %ld1623)
  %$t1375.addr = alloca ptr
  store ptr %cr1624, ptr %$t1375.addr
  %hp1625 = call ptr @march_alloc(i64 32)
  %tgp1626 = getelementptr i8, ptr %hp1625, i64 8
  store i32 0, ptr %tgp1626, align 4
  %ld1627 = load ptr, ptr %$t1375.addr
  %fp1628 = getelementptr i8, ptr %hp1625, i64 16
  store ptr %ld1627, ptr %fp1628, align 8
  %ld1629 = load ptr, ptr %lst.addr
  %fp1630 = getelementptr i8, ptr %hp1625, i64 24
  store ptr %ld1629, ptr %fp1630, align 8
  store ptr %hp1625, ptr %res_slot1621
  br label %case_merge322
case_default323:
  %ld1631 = load ptr, ptr %lst.addr
  %res_slot1632 = alloca ptr
  %tgp1633 = getelementptr i8, ptr %ld1631, i64 8
  %tag1634 = load i32, ptr %tgp1633, align 4
  switch i32 %tag1634, label %case_default326 [
      i32 0, label %case_br327
      i32 1, label %case_br328
  ]
case_br327:
  %ld1635 = load ptr, ptr %acc.addr
  %cr1636 = call ptr @Sort.reverse_list$List_V__4510(ptr %ld1635)
  %$t1376.addr = alloca ptr
  store ptr %cr1636, ptr %$t1376.addr
  %ld1637 = load ptr, ptr %lst.addr
  %rc1638 = load i64, ptr %ld1637, align 8
  %uniq1639 = icmp eq i64 %rc1638, 1
  %fbip_slot1640 = alloca ptr
  br i1 %uniq1639, label %fbip_reuse329, label %fbip_fresh330
fbip_reuse329:
  %tgp1641 = getelementptr i8, ptr %ld1637, i64 8
  store i32 0, ptr %tgp1641, align 4
  store ptr %ld1637, ptr %fbip_slot1640
  br label %fbip_merge331
fbip_fresh330:
  call void @march_decrc(ptr %ld1637)
  %hp1642 = call ptr @march_alloc(i64 16)
  %tgp1643 = getelementptr i8, ptr %hp1642, i64 8
  store i32 0, ptr %tgp1643, align 4
  store ptr %hp1642, ptr %fbip_slot1640
  br label %fbip_merge331
fbip_merge331:
  %fbip_r1644 = load ptr, ptr %fbip_slot1640
  %$t1377.addr = alloca ptr
  store ptr %fbip_r1644, ptr %$t1377.addr
  %hp1645 = call ptr @march_alloc(i64 32)
  %tgp1646 = getelementptr i8, ptr %hp1645, i64 8
  store i32 0, ptr %tgp1646, align 4
  %ld1647 = load ptr, ptr %$t1376.addr
  %fp1648 = getelementptr i8, ptr %hp1645, i64 16
  store ptr %ld1647, ptr %fp1648, align 8
  %ld1649 = load ptr, ptr %$t1377.addr
  %fp1650 = getelementptr i8, ptr %hp1645, i64 24
  store ptr %ld1649, ptr %fp1650, align 8
  store ptr %hp1645, ptr %res_slot1632
  br label %case_merge325
case_br328:
  %fp1651 = getelementptr i8, ptr %ld1631, i64 16
  %fv1652 = load ptr, ptr %fp1651, align 8
  %$f1380.addr = alloca ptr
  store ptr %fv1652, ptr %$f1380.addr
  %fp1653 = getelementptr i8, ptr %ld1631, i64 24
  %fv1654 = load ptr, ptr %fp1653, align 8
  %$f1381.addr = alloca ptr
  store ptr %fv1654, ptr %$f1381.addr
  %ld1655 = load ptr, ptr %$f1381.addr
  %t.addr = alloca ptr
  store ptr %ld1655, ptr %t.addr
  %ld1656 = load ptr, ptr %$f1380.addr
  %h.addr = alloca ptr
  store ptr %ld1656, ptr %h.addr
  %ld1657 = load i64, ptr %k.addr
  %ar1658 = sub i64 %ld1657, 1
  %$t1378.addr = alloca i64
  store i64 %ar1658, ptr %$t1378.addr
  %ld1659 = load ptr, ptr %lst.addr
  %ld1660 = load ptr, ptr %h.addr
  %ld1661 = load ptr, ptr %acc.addr
  %rc1662 = load i64, ptr %ld1659, align 8
  %uniq1663 = icmp eq i64 %rc1662, 1
  %fbip_slot1664 = alloca ptr
  br i1 %uniq1663, label %fbip_reuse332, label %fbip_fresh333
fbip_reuse332:
  %tgp1665 = getelementptr i8, ptr %ld1659, i64 8
  store i32 1, ptr %tgp1665, align 4
  %fp1666 = getelementptr i8, ptr %ld1659, i64 16
  store ptr %ld1660, ptr %fp1666, align 8
  %fp1667 = getelementptr i8, ptr %ld1659, i64 24
  store ptr %ld1661, ptr %fp1667, align 8
  store ptr %ld1659, ptr %fbip_slot1664
  br label %fbip_merge334
fbip_fresh333:
  call void @march_decrc(ptr %ld1659)
  %hp1668 = call ptr @march_alloc(i64 32)
  %tgp1669 = getelementptr i8, ptr %hp1668, i64 8
  store i32 1, ptr %tgp1669, align 4
  %fp1670 = getelementptr i8, ptr %hp1668, i64 16
  store ptr %ld1660, ptr %fp1670, align 8
  %fp1671 = getelementptr i8, ptr %hp1668, i64 24
  store ptr %ld1661, ptr %fp1671, align 8
  store ptr %hp1668, ptr %fbip_slot1664
  br label %fbip_merge334
fbip_merge334:
  %fbip_r1672 = load ptr, ptr %fbip_slot1664
  %$t1379.addr = alloca ptr
  store ptr %fbip_r1672, ptr %$t1379.addr
  %ld1673 = load ptr, ptr %take_k.addr
  %fp1674 = getelementptr i8, ptr %ld1673, i64 16
  %fv1675 = load ptr, ptr %fp1674, align 8
  %ld1676 = load ptr, ptr %t.addr
  %ld1677 = load i64, ptr %$t1378.addr
  %ld1678 = load ptr, ptr %$t1379.addr
  %cr1679 = call ptr (ptr, ptr, i64, ptr) %fv1675(ptr %ld1673, ptr %ld1676, i64 %ld1677, ptr %ld1678)
  store ptr %cr1679, ptr %res_slot1632
  br label %case_merge325
case_default326:
  unreachable
case_merge325:
  %case_r1680 = load ptr, ptr %res_slot1632
  store ptr %case_r1680, ptr %res_slot1621
  br label %case_merge322
case_merge322:
  %case_r1681 = load ptr, ptr %res_slot1621
  ret ptr %case_r1681
}

define ptr @go$apply$26(ptr %$clo.arg, ptr %lst.arg, i64 %n.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld1682 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1682)
  %ld1683 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1683, ptr %go.addr
  %ld1684 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1684)
  %ld1685 = load ptr, ptr %$clo.addr
  %fp1686 = getelementptr i8, ptr %ld1685, i64 24
  %fv1687 = load ptr, ptr %fp1686, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1687, ptr %cmp.addr
  %ld1688 = load ptr, ptr %$clo.addr
  %fp1689 = getelementptr i8, ptr %ld1688, i64 32
  %fv1690 = load ptr, ptr %fp1689, align 8
  %take_k.addr = alloca ptr
  store ptr %fv1690, ptr %take_k.addr
  %ld1691 = load i64, ptr %n.addr
  %cmp1692 = icmp sle i64 %ld1691, 1
  %ar1693 = zext i1 %cmp1692 to i64
  %$t1382.addr = alloca i64
  store i64 %ar1693, ptr %$t1382.addr
  %ld1694 = load i64, ptr %$t1382.addr
  %res_slot1695 = alloca ptr
  %bi1696 = trunc i64 %ld1694 to i1
  br i1 %bi1696, label %case_br337, label %case_default336
case_br337:
  %ld1697 = load ptr, ptr %lst.addr
  store ptr %ld1697, ptr %res_slot1695
  br label %case_merge335
case_default336:
  %ld1698 = load i64, ptr %n.addr
  %ar1699 = sdiv i64 %ld1698, 2
  %half.addr = alloca i64
  store i64 %ar1699, ptr %half.addr
  %hp1700 = call ptr @march_alloc(i64 16)
  %tgp1701 = getelementptr i8, ptr %hp1700, i64 8
  store i32 0, ptr %tgp1701, align 4
  %$t1383.addr = alloca ptr
  store ptr %hp1700, ptr %$t1383.addr
  %ld1702 = load ptr, ptr %take_k.addr
  %fp1703 = getelementptr i8, ptr %ld1702, i64 16
  %fv1704 = load ptr, ptr %fp1703, align 8
  %ld1705 = load ptr, ptr %lst.addr
  %ld1706 = load i64, ptr %half.addr
  %ld1707 = load ptr, ptr %$t1383.addr
  %cr1708 = call ptr (ptr, ptr, i64, ptr) %fv1704(ptr %ld1702, ptr %ld1705, i64 %ld1706, ptr %ld1707)
  %$p1387.addr = alloca ptr
  store ptr %cr1708, ptr %$p1387.addr
  %ld1709 = load ptr, ptr %$p1387.addr
  %fp1710 = getelementptr i8, ptr %ld1709, i64 16
  %fv1711 = load ptr, ptr %fp1710, align 8
  %l.addr = alloca ptr
  store ptr %fv1711, ptr %l.addr
  %ld1712 = load ptr, ptr %$p1387.addr
  %fp1713 = getelementptr i8, ptr %ld1712, i64 24
  %fv1714 = load ptr, ptr %fp1713, align 8
  %r.addr = alloca ptr
  store ptr %fv1714, ptr %r.addr
  %ld1715 = load ptr, ptr %go.addr
  %fp1716 = getelementptr i8, ptr %ld1715, i64 16
  %fv1717 = load ptr, ptr %fp1716, align 8
  %ld1718 = load ptr, ptr %l.addr
  %ld1719 = load i64, ptr %half.addr
  %cr1720 = call ptr (ptr, ptr, i64) %fv1717(ptr %ld1715, ptr %ld1718, i64 %ld1719)
  %$t1384.addr = alloca ptr
  store ptr %cr1720, ptr %$t1384.addr
  %ld1721 = load i64, ptr %n.addr
  %ld1722 = load i64, ptr %half.addr
  %ar1723 = sub i64 %ld1721, %ld1722
  %$t1385.addr = alloca i64
  store i64 %ar1723, ptr %$t1385.addr
  %ld1724 = load ptr, ptr %go.addr
  %fp1725 = getelementptr i8, ptr %ld1724, i64 16
  %fv1726 = load ptr, ptr %fp1725, align 8
  %ld1727 = load ptr, ptr %r.addr
  %ld1728 = load i64, ptr %$t1385.addr
  %cr1729 = call ptr (ptr, ptr, i64) %fv1726(ptr %ld1724, ptr %ld1727, i64 %ld1728)
  %$t1386.addr = alloca ptr
  store ptr %cr1729, ptr %$t1386.addr
  %ld1730 = load ptr, ptr %$t1384.addr
  %ld1731 = load ptr, ptr %$t1386.addr
  %ld1732 = load ptr, ptr %cmp.addr
  %cr1733 = call ptr @Sort.merge_sorted$List_V__4528$List_V__4528$Fn_V__4528_Fn_V__4528_Bool(ptr %ld1730, ptr %ld1731, ptr %ld1732)
  store ptr %cr1733, ptr %res_slot1695
  br label %case_merge335
case_merge335:
  %case_r1734 = load ptr, ptr %res_slot1695
  ret ptr %case_r1734
}

define ptr @process$apply$27(ptr %$clo.arg, ptr %run_list.arg, ptr %stack.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %run_list.addr = alloca ptr
  store ptr %run_list.arg, ptr %run_list.addr
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld1735 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1735)
  %ld1736 = load ptr, ptr %$clo.addr
  %process.addr = alloca ptr
  store ptr %ld1736, ptr %process.addr
  %ld1737 = load ptr, ptr %$clo.addr
  %fp1738 = getelementptr i8, ptr %ld1737, i64 24
  %fv1739 = load ptr, ptr %fp1738, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1739, ptr %cmp.addr
  %ld1740 = load ptr, ptr %run_list.addr
  %res_slot1741 = alloca ptr
  %tgp1742 = getelementptr i8, ptr %ld1740, i64 8
  %tag1743 = load i32, ptr %tgp1742, align 4
  switch i32 %tag1743, label %case_default339 [
      i32 0, label %case_br340
      i32 1, label %case_br341
  ]
case_br340:
  %ld1744 = load ptr, ptr %run_list.addr
  call void @march_decrc(ptr %ld1744)
  %ld1745 = load ptr, ptr %stack.addr
  store ptr %ld1745, ptr %res_slot1741
  br label %case_merge338
case_br341:
  %fp1746 = getelementptr i8, ptr %ld1740, i64 16
  %fv1747 = load ptr, ptr %fp1746, align 8
  %$f1623.addr = alloca ptr
  store ptr %fv1747, ptr %$f1623.addr
  %fp1748 = getelementptr i8, ptr %ld1740, i64 24
  %fv1749 = load ptr, ptr %fp1748, align 8
  %$f1624.addr = alloca ptr
  store ptr %fv1749, ptr %$f1624.addr
  %freed1750 = call i64 @march_decrc_freed(ptr %ld1740)
  %freed_b1751 = icmp ne i64 %freed1750, 0
  br i1 %freed_b1751, label %br_unique342, label %br_shared343
br_shared343:
  call void @march_incrc(ptr %fv1749)
  call void @march_incrc(ptr %fv1747)
  br label %br_body344
br_unique342:
  br label %br_body344
br_body344:
  %ld1752 = load ptr, ptr %$f1624.addr
  %rest.addr = alloca ptr
  store ptr %ld1752, ptr %rest.addr
  %ld1753 = load ptr, ptr %$f1623.addr
  %run.addr = alloca ptr
  store ptr %ld1753, ptr %run.addr
  %hp1754 = call ptr @march_alloc(i64 32)
  %tgp1755 = getelementptr i8, ptr %hp1754, i64 8
  store i32 1, ptr %tgp1755, align 4
  %ld1756 = load ptr, ptr %run.addr
  %fp1757 = getelementptr i8, ptr %hp1754, i64 16
  store ptr %ld1756, ptr %fp1757, align 8
  %ld1758 = load ptr, ptr %stack.addr
  %fp1759 = getelementptr i8, ptr %hp1754, i64 24
  store ptr %ld1758, ptr %fp1759, align 8
  %$t1622.addr = alloca ptr
  store ptr %hp1754, ptr %$t1622.addr
  %ld1760 = load ptr, ptr %$t1622.addr
  %ld1761 = load ptr, ptr %cmp.addr
  %cr1762 = call ptr @Sort.enforce_invariants$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %ld1760, ptr %ld1761)
  %new_stack.addr = alloca ptr
  store ptr %cr1762, ptr %new_stack.addr
  %ld1763 = load ptr, ptr %process.addr
  %fp1764 = getelementptr i8, ptr %ld1763, i64 16
  %fv1765 = load ptr, ptr %fp1764, align 8
  %ld1766 = load ptr, ptr %rest.addr
  %ld1767 = load ptr, ptr %new_stack.addr
  %cr1768 = call ptr (ptr, ptr, ptr) %fv1765(ptr %ld1763, ptr %ld1766, ptr %ld1767)
  store ptr %cr1768, ptr %res_slot1741
  br label %case_merge338
case_default339:
  unreachable
case_merge338:
  %case_r1769 = load ptr, ptr %res_slot1741
  ret ptr %case_r1769
}

define i64 @go$apply$29(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld1770 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1770, ptr %go.addr
  %ld1771 = load ptr, ptr %lst.addr
  %res_slot1772 = alloca ptr
  %tgp1773 = getelementptr i8, ptr %ld1771, i64 8
  %tag1774 = load i32, ptr %tgp1773, align 4
  switch i32 %tag1774, label %case_default346 [
      i32 0, label %case_br347
      i32 1, label %case_br348
  ]
case_br347:
  %ld1775 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1775)
  %ld1776 = load i64, ptr %acc.addr
  %cv1777 = inttoptr i64 %ld1776 to ptr
  store ptr %cv1777, ptr %res_slot1772
  br label %case_merge345
case_br348:
  %fp1778 = getelementptr i8, ptr %ld1771, i64 16
  %fv1779 = load ptr, ptr %fp1778, align 8
  %$f1360.addr = alloca ptr
  store ptr %fv1779, ptr %$f1360.addr
  %fp1780 = getelementptr i8, ptr %ld1771, i64 24
  %fv1781 = load ptr, ptr %fp1780, align 8
  %$f1361.addr = alloca ptr
  store ptr %fv1781, ptr %$f1361.addr
  %freed1782 = call i64 @march_decrc_freed(ptr %ld1771)
  %freed_b1783 = icmp ne i64 %freed1782, 0
  br i1 %freed_b1783, label %br_unique349, label %br_shared350
br_shared350:
  call void @march_incrc(ptr %fv1781)
  call void @march_incrc(ptr %fv1779)
  br label %br_body351
br_unique349:
  br label %br_body351
br_body351:
  %ld1784 = load ptr, ptr %$f1361.addr
  %t.addr = alloca ptr
  store ptr %ld1784, ptr %t.addr
  %ld1785 = load i64, ptr %acc.addr
  %ar1786 = add i64 %ld1785, 1
  %$t1359.addr = alloca i64
  store i64 %ar1786, ptr %$t1359.addr
  %ld1787 = load ptr, ptr %go.addr
  %fp1788 = getelementptr i8, ptr %ld1787, i64 16
  %fv1789 = load ptr, ptr %fp1788, align 8
  %ld1790 = load ptr, ptr %t.addr
  %ld1791 = load i64, ptr %$t1359.addr
  %cr1792 = call i64 (ptr, ptr, i64) %fv1789(ptr %ld1787, ptr %ld1790, i64 %ld1791)
  %cv1793 = inttoptr i64 %cr1792 to ptr
  store ptr %cv1793, ptr %res_slot1772
  br label %case_merge345
case_default346:
  unreachable
case_merge345:
  %case_r1794 = load ptr, ptr %res_slot1772
  %cv1795 = ptrtoint ptr %case_r1794 to i64
  ret i64 %cv1795
}

define ptr @go$apply$30(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1796 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1796, ptr %go.addr
  %ld1797 = load ptr, ptr %lst.addr
  %res_slot1798 = alloca ptr
  %tgp1799 = getelementptr i8, ptr %ld1797, i64 8
  %tag1800 = load i32, ptr %tgp1799, align 4
  switch i32 %tag1800, label %case_default353 [
      i32 0, label %case_br354
      i32 1, label %case_br355
  ]
case_br354:
  %ld1801 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1801)
  %ld1802 = load ptr, ptr %acc.addr
  store ptr %ld1802, ptr %res_slot1798
  br label %case_merge352
case_br355:
  %fp1803 = getelementptr i8, ptr %ld1797, i64 16
  %fv1804 = load ptr, ptr %fp1803, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv1804, ptr %$f1353.addr
  %fp1805 = getelementptr i8, ptr %ld1797, i64 24
  %fv1806 = load ptr, ptr %fp1805, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv1806, ptr %$f1354.addr
  %ld1807 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld1807, ptr %t.addr
  %ld1808 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld1808, ptr %h.addr
  %ld1809 = load ptr, ptr %lst.addr
  %ld1810 = load ptr, ptr %h.addr
  %ld1811 = load ptr, ptr %acc.addr
  %rc1812 = load i64, ptr %ld1809, align 8
  %uniq1813 = icmp eq i64 %rc1812, 1
  %fbip_slot1814 = alloca ptr
  br i1 %uniq1813, label %fbip_reuse356, label %fbip_fresh357
fbip_reuse356:
  %tgp1815 = getelementptr i8, ptr %ld1809, i64 8
  store i32 1, ptr %tgp1815, align 4
  %fp1816 = getelementptr i8, ptr %ld1809, i64 16
  store ptr %ld1810, ptr %fp1816, align 8
  %fp1817 = getelementptr i8, ptr %ld1809, i64 24
  store ptr %ld1811, ptr %fp1817, align 8
  store ptr %ld1809, ptr %fbip_slot1814
  br label %fbip_merge358
fbip_fresh357:
  call void @march_decrc(ptr %ld1809)
  %hp1818 = call ptr @march_alloc(i64 32)
  %tgp1819 = getelementptr i8, ptr %hp1818, i64 8
  store i32 1, ptr %tgp1819, align 4
  %fp1820 = getelementptr i8, ptr %hp1818, i64 16
  store ptr %ld1810, ptr %fp1820, align 8
  %fp1821 = getelementptr i8, ptr %hp1818, i64 24
  store ptr %ld1811, ptr %fp1821, align 8
  store ptr %hp1818, ptr %fbip_slot1814
  br label %fbip_merge358
fbip_merge358:
  %fbip_r1822 = load ptr, ptr %fbip_slot1814
  %$t1352.addr = alloca ptr
  store ptr %fbip_r1822, ptr %$t1352.addr
  %ld1823 = load ptr, ptr %go.addr
  %fp1824 = getelementptr i8, ptr %ld1823, i64 16
  %fv1825 = load ptr, ptr %fp1824, align 8
  %ld1826 = load ptr, ptr %t.addr
  %ld1827 = load ptr, ptr %$t1352.addr
  %cr1828 = call ptr (ptr, ptr, ptr) %fv1825(ptr %ld1823, ptr %ld1826, ptr %ld1827)
  store ptr %cr1828, ptr %res_slot1798
  br label %case_merge352
case_default353:
  unreachable
case_merge352:
  %case_r1829 = load ptr, ptr %res_slot1798
  ret ptr %case_r1829
}

define ptr @go$apply$31(ptr %$clo.arg, ptr %stk.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %stk.addr = alloca ptr
  store ptr %stk.arg, ptr %stk.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1830 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1830)
  %ld1831 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1831, ptr %go.addr
  %ld1832 = load ptr, ptr %$clo.addr
  %fp1833 = getelementptr i8, ptr %ld1832, i64 24
  %fv1834 = load ptr, ptr %fp1833, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1834, ptr %cmp.addr
  %ld1835 = load ptr, ptr %stk.addr
  %res_slot1836 = alloca ptr
  %tgp1837 = getelementptr i8, ptr %ld1835, i64 8
  %tag1838 = load i32, ptr %tgp1837, align 4
  switch i32 %tag1838, label %case_default360 [
      i32 0, label %case_br361
      i32 1, label %case_br362
  ]
case_br361:
  %ld1839 = load ptr, ptr %stk.addr
  call void @march_decrc(ptr %ld1839)
  %ld1840 = load ptr, ptr %acc.addr
  store ptr %ld1840, ptr %res_slot1836
  br label %case_merge359
case_br362:
  %fp1841 = getelementptr i8, ptr %ld1835, i64 16
  %fv1842 = load ptr, ptr %fp1841, align 8
  %$f1614.addr = alloca ptr
  store ptr %fv1842, ptr %$f1614.addr
  %fp1843 = getelementptr i8, ptr %ld1835, i64 24
  %fv1844 = load ptr, ptr %fp1843, align 8
  %$f1615.addr = alloca ptr
  store ptr %fv1844, ptr %$f1615.addr
  %freed1845 = call i64 @march_decrc_freed(ptr %ld1835)
  %freed_b1846 = icmp ne i64 %freed1845, 0
  br i1 %freed_b1846, label %br_unique363, label %br_shared364
br_shared364:
  call void @march_incrc(ptr %fv1844)
  call void @march_incrc(ptr %fv1842)
  br label %br_body365
br_unique363:
  br label %br_body365
br_body365:
  %ld1847 = load ptr, ptr %$f1614.addr
  %res_slot1848 = alloca ptr
  %tgp1849 = getelementptr i8, ptr %ld1847, i64 8
  %tag1850 = load i32, ptr %tgp1849, align 4
  switch i32 %tag1850, label %case_default367 [
      i32 0, label %case_br368
  ]
case_br368:
  %fp1851 = getelementptr i8, ptr %ld1847, i64 16
  %fv1852 = load ptr, ptr %fp1851, align 8
  %$f1616.addr = alloca ptr
  store ptr %fv1852, ptr %$f1616.addr
  %fp1853 = getelementptr i8, ptr %ld1847, i64 24
  %fv1854 = load ptr, ptr %fp1853, align 8
  %$f1617.addr = alloca ptr
  store ptr %fv1854, ptr %$f1617.addr
  %freed1855 = call i64 @march_decrc_freed(ptr %ld1847)
  %freed_b1856 = icmp ne i64 %freed1855, 0
  br i1 %freed_b1856, label %br_unique369, label %br_shared370
br_shared370:
  call void @march_incrc(ptr %fv1854)
  call void @march_incrc(ptr %fv1852)
  br label %br_body371
br_unique369:
  br label %br_body371
br_body371:
  %ld1857 = load ptr, ptr %$f1615.addr
  %rest.addr = alloca ptr
  store ptr %ld1857, ptr %rest.addr
  %ld1858 = load ptr, ptr %$f1616.addr
  %run.addr = alloca ptr
  store ptr %ld1858, ptr %run.addr
  %ld1859 = load ptr, ptr %acc.addr
  %a_i60.addr = alloca ptr
  store ptr %ld1859, ptr %a_i60.addr
  %ld1860 = load ptr, ptr %run.addr
  %b_i61.addr = alloca ptr
  store ptr %ld1860, ptr %b_i61.addr
  %ld1861 = load ptr, ptr %cmp.addr
  %cmp_i62.addr = alloca ptr
  store ptr %ld1861, ptr %cmp_i62.addr
  %ld1862 = load ptr, ptr %a_i60.addr
  %ld1863 = load ptr, ptr %b_i61.addr
  %ld1864 = load ptr, ptr %cmp_i62.addr
  %cr1865 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1862, ptr %ld1863, ptr %ld1864)
  %$t1613.addr = alloca ptr
  store ptr %cr1865, ptr %$t1613.addr
  %ld1866 = load ptr, ptr %go.addr
  %fp1867 = getelementptr i8, ptr %ld1866, i64 16
  %fv1868 = load ptr, ptr %fp1867, align 8
  %ld1869 = load ptr, ptr %rest.addr
  %ld1870 = load ptr, ptr %$t1613.addr
  %cr1871 = call ptr (ptr, ptr, ptr) %fv1868(ptr %ld1866, ptr %ld1869, ptr %ld1870)
  store ptr %cr1871, ptr %res_slot1848
  br label %case_merge366
case_default367:
  unreachable
case_merge366:
  %case_r1872 = load ptr, ptr %res_slot1848
  store ptr %case_r1872, ptr %res_slot1836
  br label %case_merge359
case_default360:
  unreachable
case_merge359:
  %case_r1873 = load ptr, ptr %res_slot1836
  ret ptr %case_r1873
}

define ptr @scan_run$apply$32(ptr %$clo.arg, ptr %lst.arg, ptr %run.arg, i64 %run_len.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %ld1874 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1874)
  %ld1875 = load ptr, ptr %$clo.addr
  %scan_run.addr = alloca ptr
  store ptr %ld1875, ptr %scan_run.addr
  %ld1876 = load ptr, ptr %$clo.addr
  %fp1877 = getelementptr i8, ptr %ld1876, i64 24
  %fv1878 = load ptr, ptr %fp1877, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1878, ptr %cmp.addr
  %ld1879 = load ptr, ptr %lst.addr
  %res_slot1880 = alloca ptr
  %tgp1881 = getelementptr i8, ptr %ld1879, i64 8
  %tag1882 = load i32, ptr %tgp1881, align 4
  switch i32 %tag1882, label %case_default373 [
      i32 0, label %case_br374
      i32 1, label %case_br375
  ]
case_br374:
  %ld1883 = load ptr, ptr %run.addr
  %cr1884 = call ptr @Sort.reverse_list$List_V__4971(ptr %ld1883)
  %$t1562.addr = alloca ptr
  store ptr %cr1884, ptr %$t1562.addr
  %ld1885 = load ptr, ptr %lst.addr
  %rc1886 = load i64, ptr %ld1885, align 8
  %uniq1887 = icmp eq i64 %rc1886, 1
  %fbip_slot1888 = alloca ptr
  br i1 %uniq1887, label %fbip_reuse376, label %fbip_fresh377
fbip_reuse376:
  %tgp1889 = getelementptr i8, ptr %ld1885, i64 8
  store i32 0, ptr %tgp1889, align 4
  store ptr %ld1885, ptr %fbip_slot1888
  br label %fbip_merge378
fbip_fresh377:
  call void @march_decrc(ptr %ld1885)
  %hp1890 = call ptr @march_alloc(i64 16)
  %tgp1891 = getelementptr i8, ptr %hp1890, i64 8
  store i32 0, ptr %tgp1891, align 4
  store ptr %hp1890, ptr %fbip_slot1888
  br label %fbip_merge378
fbip_merge378:
  %fbip_r1892 = load ptr, ptr %fbip_slot1888
  %$t1563.addr = alloca ptr
  store ptr %fbip_r1892, ptr %$t1563.addr
  %hp1893 = call ptr @march_alloc(i64 40)
  %tgp1894 = getelementptr i8, ptr %hp1893, i64 8
  store i32 0, ptr %tgp1894, align 4
  %ld1895 = load ptr, ptr %$t1562.addr
  %fp1896 = getelementptr i8, ptr %hp1893, i64 16
  store ptr %ld1895, ptr %fp1896, align 8
  %ld1897 = load i64, ptr %run_len.addr
  %fp1898 = getelementptr i8, ptr %hp1893, i64 24
  store i64 %ld1897, ptr %fp1898, align 8
  %ld1899 = load ptr, ptr %$t1563.addr
  %fp1900 = getelementptr i8, ptr %hp1893, i64 32
  store ptr %ld1899, ptr %fp1900, align 8
  store ptr %hp1893, ptr %res_slot1880
  br label %case_merge372
case_br375:
  %fp1901 = getelementptr i8, ptr %ld1879, i64 16
  %fv1902 = load ptr, ptr %fp1901, align 8
  %$f1572.addr = alloca ptr
  store ptr %fv1902, ptr %$f1572.addr
  %fp1903 = getelementptr i8, ptr %ld1879, i64 24
  %fv1904 = load ptr, ptr %fp1903, align 8
  %$f1573.addr = alloca ptr
  store ptr %fv1904, ptr %$f1573.addr
  %ld1905 = load ptr, ptr %$f1573.addr
  %t.addr = alloca ptr
  store ptr %ld1905, ptr %t.addr
  %ld1906 = load ptr, ptr %$f1572.addr
  %h.addr = alloca ptr
  store ptr %ld1906, ptr %h.addr
  %ld1907 = load ptr, ptr %run.addr
  %res_slot1908 = alloca ptr
  %tgp1909 = getelementptr i8, ptr %ld1907, i64 8
  %tag1910 = load i32, ptr %tgp1909, align 4
  switch i32 %tag1910, label %case_default380 [
      i32 0, label %case_br381
      i32 1, label %case_br382
  ]
case_br381:
  %ld1911 = load ptr, ptr %run.addr
  call void @march_decrc(ptr %ld1911)
  %hp1912 = call ptr @march_alloc(i64 16)
  %tgp1913 = getelementptr i8, ptr %hp1912, i64 8
  store i32 0, ptr %tgp1913, align 4
  %$t1564.addr = alloca ptr
  store ptr %hp1912, ptr %$t1564.addr
  %hp1914 = call ptr @march_alloc(i64 32)
  %tgp1915 = getelementptr i8, ptr %hp1914, i64 8
  store i32 1, ptr %tgp1915, align 4
  %ld1916 = load ptr, ptr %h.addr
  %fp1917 = getelementptr i8, ptr %hp1914, i64 16
  store ptr %ld1916, ptr %fp1917, align 8
  %ld1918 = load ptr, ptr %$t1564.addr
  %fp1919 = getelementptr i8, ptr %hp1914, i64 24
  store ptr %ld1918, ptr %fp1919, align 8
  %$t1565.addr = alloca ptr
  store ptr %hp1914, ptr %$t1565.addr
  %ld1920 = load ptr, ptr %scan_run.addr
  %fp1921 = getelementptr i8, ptr %ld1920, i64 16
  %fv1922 = load ptr, ptr %fp1921, align 8
  %ld1923 = load ptr, ptr %t.addr
  %ld1924 = load ptr, ptr %$t1565.addr
  %cr1925 = call ptr (ptr, ptr, ptr, i64) %fv1922(ptr %ld1920, ptr %ld1923, ptr %ld1924, i64 1)
  store ptr %cr1925, ptr %res_slot1908
  br label %case_merge379
case_br382:
  %fp1926 = getelementptr i8, ptr %ld1907, i64 16
  %fv1927 = load ptr, ptr %fp1926, align 8
  %$f1570.addr = alloca ptr
  store ptr %fv1927, ptr %$f1570.addr
  %fp1928 = getelementptr i8, ptr %ld1907, i64 24
  %fv1929 = load ptr, ptr %fp1928, align 8
  %$f1571.addr = alloca ptr
  store ptr %fv1929, ptr %$f1571.addr
  %ld1930 = load ptr, ptr %$f1570.addr
  %prev.addr = alloca ptr
  store ptr %ld1930, ptr %prev.addr
  %ld1931 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1931)
  %ld1932 = load ptr, ptr %cmp.addr
  %ld1933 = load ptr, ptr %prev.addr
  %ld1934 = load ptr, ptr %h.addr
  %cr1935 = call i64 @Sort.cmp2$Fn_V__4971_Fn_V__4971_Bool$V__4971$V__4971(ptr %ld1932, ptr %ld1933, ptr %ld1934)
  %$t1566.addr = alloca i64
  store i64 %cr1935, ptr %$t1566.addr
  %ld1936 = load i64, ptr %$t1566.addr
  %res_slot1937 = alloca ptr
  %bi1938 = trunc i64 %ld1936 to i1
  br i1 %bi1938, label %case_br385, label %case_default384
case_br385:
  %hp1939 = call ptr @march_alloc(i64 32)
  %tgp1940 = getelementptr i8, ptr %hp1939, i64 8
  store i32 1, ptr %tgp1940, align 4
  %ld1941 = load ptr, ptr %h.addr
  %fp1942 = getelementptr i8, ptr %hp1939, i64 16
  store ptr %ld1941, ptr %fp1942, align 8
  %ld1943 = load ptr, ptr %run.addr
  %fp1944 = getelementptr i8, ptr %hp1939, i64 24
  store ptr %ld1943, ptr %fp1944, align 8
  %$t1567.addr = alloca ptr
  store ptr %hp1939, ptr %$t1567.addr
  %ld1945 = load i64, ptr %run_len.addr
  %ar1946 = add i64 %ld1945, 1
  %$t1568.addr = alloca i64
  store i64 %ar1946, ptr %$t1568.addr
  %ld1947 = load ptr, ptr %scan_run.addr
  %fp1948 = getelementptr i8, ptr %ld1947, i64 16
  %fv1949 = load ptr, ptr %fp1948, align 8
  %ld1950 = load ptr, ptr %t.addr
  %ld1951 = load ptr, ptr %$t1567.addr
  %ld1952 = load i64, ptr %$t1568.addr
  %cr1953 = call ptr (ptr, ptr, ptr, i64) %fv1949(ptr %ld1947, ptr %ld1950, ptr %ld1951, i64 %ld1952)
  store ptr %cr1953, ptr %res_slot1937
  br label %case_merge383
case_default384:
  %ld1954 = load ptr, ptr %run.addr
  %cr1955 = call ptr @Sort.reverse_list$List_V__4971(ptr %ld1954)
  %$t1569.addr = alloca ptr
  store ptr %cr1955, ptr %$t1569.addr
  %hp1956 = call ptr @march_alloc(i64 40)
  %tgp1957 = getelementptr i8, ptr %hp1956, i64 8
  store i32 0, ptr %tgp1957, align 4
  %ld1958 = load ptr, ptr %$t1569.addr
  %fp1959 = getelementptr i8, ptr %hp1956, i64 16
  store ptr %ld1958, ptr %fp1959, align 8
  %ld1960 = load i64, ptr %run_len.addr
  %fp1961 = getelementptr i8, ptr %hp1956, i64 24
  store i64 %ld1960, ptr %fp1961, align 8
  %ld1962 = load ptr, ptr %lst.addr
  %fp1963 = getelementptr i8, ptr %hp1956, i64 32
  store ptr %ld1962, ptr %fp1963, align 8
  store ptr %hp1956, ptr %res_slot1937
  br label %case_merge383
case_merge383:
  %case_r1964 = load ptr, ptr %res_slot1937
  store ptr %case_r1964, ptr %res_slot1908
  br label %case_merge379
case_default380:
  unreachable
case_merge379:
  %case_r1965 = load ptr, ptr %res_slot1908
  store ptr %case_r1965, ptr %res_slot1880
  br label %case_merge372
case_default373:
  unreachable
case_merge372:
  %case_r1966 = load ptr, ptr %res_slot1880
  ret ptr %case_r1966
}

define ptr @collect$apply$33(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1967 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1967)
  %ld1968 = load ptr, ptr %$clo.addr
  %collect.addr = alloca ptr
  store ptr %ld1968, ptr %collect.addr
  %ld1969 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1969)
  %ld1970 = load ptr, ptr %$clo.addr
  %fp1971 = getelementptr i8, ptr %ld1970, i64 24
  %fv1972 = load ptr, ptr %fp1971, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1972, ptr %cmp.addr
  %ld1973 = load ptr, ptr %$clo.addr
  %fp1974 = getelementptr i8, ptr %ld1973, i64 32
  %fv1975 = load ptr, ptr %fp1974, align 8
  %scan_run.addr = alloca ptr
  store ptr %fv1975, ptr %scan_run.addr
  %ld1976 = load ptr, ptr %lst.addr
  %res_slot1977 = alloca ptr
  %tgp1978 = getelementptr i8, ptr %ld1976, i64 8
  %tag1979 = load i32, ptr %tgp1978, align 4
  switch i32 %tag1979, label %case_default387 [
      i32 0, label %case_br388
  ]
case_br388:
  %ld1980 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1980)
  %ld1981 = load ptr, ptr %acc.addr
  %cr1982 = call ptr @Sort.reverse_list$List_T_List_V__4971_Int(ptr %ld1981)
  store ptr %cr1982, ptr %res_slot1977
  br label %case_merge386
case_default387:
  %hp1983 = call ptr @march_alloc(i64 16)
  %tgp1984 = getelementptr i8, ptr %hp1983, i64 8
  store i32 0, ptr %tgp1984, align 4
  %$t1574.addr = alloca ptr
  store ptr %hp1983, ptr %$t1574.addr
  %ld1985 = load ptr, ptr %scan_run.addr
  %fp1986 = getelementptr i8, ptr %ld1985, i64 16
  %fv1987 = load ptr, ptr %fp1986, align 8
  %ld1988 = load ptr, ptr %lst.addr
  %ld1989 = load ptr, ptr %$t1574.addr
  %cr1990 = call ptr (ptr, ptr, ptr, i64) %fv1987(ptr %ld1985, ptr %ld1988, ptr %ld1989, i64 0)
  %$p1578.addr = alloca ptr
  store ptr %cr1990, ptr %$p1578.addr
  %ld1991 = load ptr, ptr %$p1578.addr
  %fp1992 = getelementptr i8, ptr %ld1991, i64 16
  %fv1993 = load ptr, ptr %fp1992, align 8
  %run.addr = alloca ptr
  store ptr %fv1993, ptr %run.addr
  %ld1994 = load ptr, ptr %$p1578.addr
  %fp1995 = getelementptr i8, ptr %ld1994, i64 24
  %fv1996 = load ptr, ptr %fp1995, align 8
  %n.addr = alloca ptr
  store ptr %fv1996, ptr %n.addr
  %ld1997 = load ptr, ptr %$p1578.addr
  %fp1998 = getelementptr i8, ptr %ld1997, i64 32
  %fv1999 = load ptr, ptr %fp1998, align 8
  %rest.addr = alloca ptr
  store ptr %fv1999, ptr %rest.addr
  %ld2000 = load ptr, ptr %run.addr
  %ld2001 = load i64, ptr %n.addr
  %ld2002 = load ptr, ptr %rest.addr
  %ld2003 = load ptr, ptr %cmp.addr
  %cr2004 = call ptr @Sort.extend_run$List_V__4971$Int$List_V__4971$Fn_V__4971_Fn_V__4971_Bool(ptr %ld2000, i64 %ld2001, ptr %ld2002, ptr %ld2003)
  %$p1577.addr = alloca ptr
  store ptr %cr2004, ptr %$p1577.addr
  %ld2005 = load ptr, ptr %$p1577.addr
  %fp2006 = getelementptr i8, ptr %ld2005, i64 16
  %fv2007 = load ptr, ptr %fp2006, align 8
  %ext_run.addr = alloca ptr
  store ptr %fv2007, ptr %ext_run.addr
  %ld2008 = load ptr, ptr %$p1577.addr
  %fp2009 = getelementptr i8, ptr %ld2008, i64 24
  %fv2010 = load ptr, ptr %fp2009, align 8
  %ext_n.addr = alloca ptr
  store ptr %fv2010, ptr %ext_n.addr
  %ld2011 = load ptr, ptr %$p1577.addr
  %fp2012 = getelementptr i8, ptr %ld2011, i64 32
  %fv2013 = load ptr, ptr %fp2012, align 8
  %remaining.addr = alloca ptr
  store ptr %fv2013, ptr %remaining.addr
  %hp2014 = call ptr @march_alloc(i64 32)
  %tgp2015 = getelementptr i8, ptr %hp2014, i64 8
  store i32 0, ptr %tgp2015, align 4
  %ld2016 = load ptr, ptr %ext_run.addr
  %fp2017 = getelementptr i8, ptr %hp2014, i64 16
  store ptr %ld2016, ptr %fp2017, align 8
  %ld2018 = load i64, ptr %ext_n.addr
  %fp2019 = getelementptr i8, ptr %hp2014, i64 24
  store i64 %ld2018, ptr %fp2019, align 8
  %$t1575.addr = alloca ptr
  store ptr %hp2014, ptr %$t1575.addr
  %hp2020 = call ptr @march_alloc(i64 32)
  %tgp2021 = getelementptr i8, ptr %hp2020, i64 8
  store i32 1, ptr %tgp2021, align 4
  %ld2022 = load ptr, ptr %$t1575.addr
  %fp2023 = getelementptr i8, ptr %hp2020, i64 16
  store ptr %ld2022, ptr %fp2023, align 8
  %ld2024 = load ptr, ptr %acc.addr
  %fp2025 = getelementptr i8, ptr %hp2020, i64 24
  store ptr %ld2024, ptr %fp2025, align 8
  %$t1576.addr = alloca ptr
  store ptr %hp2020, ptr %$t1576.addr
  %ld2026 = load ptr, ptr %collect.addr
  %fp2027 = getelementptr i8, ptr %ld2026, i64 16
  %fv2028 = load ptr, ptr %fp2027, align 8
  %ld2029 = load ptr, ptr %remaining.addr
  %ld2030 = load ptr, ptr %$t1576.addr
  %cr2031 = call ptr (ptr, ptr, ptr) %fv2028(ptr %ld2026, ptr %ld2029, ptr %ld2030)
  store ptr %cr2031, ptr %res_slot1977
  br label %case_merge386
case_merge386:
  %case_r2032 = load ptr, ptr %res_slot1977
  ret ptr %case_r2032
}

define ptr @go$apply$34(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld2033 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld2033, ptr %go.addr
  %ld2034 = load ptr, ptr %lst.addr
  %res_slot2035 = alloca ptr
  %tgp2036 = getelementptr i8, ptr %ld2034, i64 8
  %tag2037 = load i32, ptr %tgp2036, align 4
  switch i32 %tag2037, label %case_default390 [
      i32 0, label %case_br391
      i32 1, label %case_br392
  ]
case_br391:
  %ld2038 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld2038)
  %ld2039 = load ptr, ptr %acc.addr
  store ptr %ld2039, ptr %res_slot2035
  br label %case_merge389
case_br392:
  %fp2040 = getelementptr i8, ptr %ld2034, i64 16
  %fv2041 = load ptr, ptr %fp2040, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv2041, ptr %$f1353.addr
  %fp2042 = getelementptr i8, ptr %ld2034, i64 24
  %fv2043 = load ptr, ptr %fp2042, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv2043, ptr %$f1354.addr
  %ld2044 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld2044, ptr %t.addr
  %ld2045 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld2045, ptr %h.addr
  %ld2046 = load ptr, ptr %lst.addr
  %ld2047 = load ptr, ptr %h.addr
  %ld2048 = load ptr, ptr %acc.addr
  %rc2049 = load i64, ptr %ld2046, align 8
  %uniq2050 = icmp eq i64 %rc2049, 1
  %fbip_slot2051 = alloca ptr
  br i1 %uniq2050, label %fbip_reuse393, label %fbip_fresh394
fbip_reuse393:
  %tgp2052 = getelementptr i8, ptr %ld2046, i64 8
  store i32 1, ptr %tgp2052, align 4
  %fp2053 = getelementptr i8, ptr %ld2046, i64 16
  store ptr %ld2047, ptr %fp2053, align 8
  %fp2054 = getelementptr i8, ptr %ld2046, i64 24
  store ptr %ld2048, ptr %fp2054, align 8
  store ptr %ld2046, ptr %fbip_slot2051
  br label %fbip_merge395
fbip_fresh394:
  call void @march_decrc(ptr %ld2046)
  %hp2055 = call ptr @march_alloc(i64 32)
  %tgp2056 = getelementptr i8, ptr %hp2055, i64 8
  store i32 1, ptr %tgp2056, align 4
  %fp2057 = getelementptr i8, ptr %hp2055, i64 16
  store ptr %ld2047, ptr %fp2057, align 8
  %fp2058 = getelementptr i8, ptr %hp2055, i64 24
  store ptr %ld2048, ptr %fp2058, align 8
  store ptr %hp2055, ptr %fbip_slot2051
  br label %fbip_merge395
fbip_merge395:
  %fbip_r2059 = load ptr, ptr %fbip_slot2051
  %$t1352.addr = alloca ptr
  store ptr %fbip_r2059, ptr %$t1352.addr
  %ld2060 = load ptr, ptr %go.addr
  %fp2061 = getelementptr i8, ptr %ld2060, i64 16
  %fv2062 = load ptr, ptr %fp2061, align 8
  %ld2063 = load ptr, ptr %t.addr
  %ld2064 = load ptr, ptr %$t1352.addr
  %cr2065 = call ptr (ptr, ptr, ptr) %fv2062(ptr %ld2060, ptr %ld2063, ptr %ld2064)
  store ptr %cr2065, ptr %res_slot2035
  br label %case_merge389
case_default390:
  unreachable
case_merge389:
  %case_r2066 = load ptr, ptr %res_slot2035
  ret ptr %case_r2066
}

define ptr @go$apply$35(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld2067 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld2067, ptr %go.addr
  %ld2068 = load ptr, ptr %lst.addr
  %res_slot2069 = alloca ptr
  %tgp2070 = getelementptr i8, ptr %ld2068, i64 8
  %tag2071 = load i32, ptr %tgp2070, align 4
  switch i32 %tag2071, label %case_default397 [
      i32 0, label %case_br398
      i32 1, label %case_br399
  ]
case_br398:
  %ld2072 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld2072)
  %ld2073 = load ptr, ptr %acc.addr
  store ptr %ld2073, ptr %res_slot2069
  br label %case_merge396
case_br399:
  %fp2074 = getelementptr i8, ptr %ld2068, i64 16
  %fv2075 = load ptr, ptr %fp2074, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv2075, ptr %$f1353.addr
  %fp2076 = getelementptr i8, ptr %ld2068, i64 24
  %fv2077 = load ptr, ptr %fp2076, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv2077, ptr %$f1354.addr
  %ld2078 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld2078, ptr %t.addr
  %ld2079 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld2079, ptr %h.addr
  %ld2080 = load ptr, ptr %lst.addr
  %ld2081 = load ptr, ptr %h.addr
  %ld2082 = load ptr, ptr %acc.addr
  %rc2083 = load i64, ptr %ld2080, align 8
  %uniq2084 = icmp eq i64 %rc2083, 1
  %fbip_slot2085 = alloca ptr
  br i1 %uniq2084, label %fbip_reuse400, label %fbip_fresh401
fbip_reuse400:
  %tgp2086 = getelementptr i8, ptr %ld2080, i64 8
  store i32 1, ptr %tgp2086, align 4
  %fp2087 = getelementptr i8, ptr %ld2080, i64 16
  store ptr %ld2081, ptr %fp2087, align 8
  %fp2088 = getelementptr i8, ptr %ld2080, i64 24
  store ptr %ld2082, ptr %fp2088, align 8
  store ptr %ld2080, ptr %fbip_slot2085
  br label %fbip_merge402
fbip_fresh401:
  call void @march_decrc(ptr %ld2080)
  %hp2089 = call ptr @march_alloc(i64 32)
  %tgp2090 = getelementptr i8, ptr %hp2089, i64 8
  store i32 1, ptr %tgp2090, align 4
  %fp2091 = getelementptr i8, ptr %hp2089, i64 16
  store ptr %ld2081, ptr %fp2091, align 8
  %fp2092 = getelementptr i8, ptr %hp2089, i64 24
  store ptr %ld2082, ptr %fp2092, align 8
  store ptr %hp2089, ptr %fbip_slot2085
  br label %fbip_merge402
fbip_merge402:
  %fbip_r2093 = load ptr, ptr %fbip_slot2085
  %$t1352.addr = alloca ptr
  store ptr %fbip_r2093, ptr %$t1352.addr
  %ld2094 = load ptr, ptr %go.addr
  %fp2095 = getelementptr i8, ptr %ld2094, i64 16
  %fv2096 = load ptr, ptr %fp2095, align 8
  %ld2097 = load ptr, ptr %t.addr
  %ld2098 = load ptr, ptr %$t1352.addr
  %cr2099 = call ptr (ptr, ptr, ptr) %fv2096(ptr %ld2094, ptr %ld2097, ptr %ld2098)
  store ptr %cr2099, ptr %res_slot2069
  br label %case_merge396
case_default397:
  unreachable
case_merge396:
  %case_r2100 = load ptr, ptr %res_slot2069
  ret ptr %case_r2100
}

define ptr @go$apply$36(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld2101 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld2101, ptr %go.addr
  %ld2102 = load ptr, ptr %lst.addr
  %res_slot2103 = alloca ptr
  %tgp2104 = getelementptr i8, ptr %ld2102, i64 8
  %tag2105 = load i32, ptr %tgp2104, align 4
  switch i32 %tag2105, label %case_default404 [
      i32 0, label %case_br405
      i32 1, label %case_br406
  ]
case_br405:
  %ld2106 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld2106)
  %ld2107 = load ptr, ptr %acc.addr
  store ptr %ld2107, ptr %res_slot2103
  br label %case_merge403
case_br406:
  %fp2108 = getelementptr i8, ptr %ld2102, i64 16
  %fv2109 = load ptr, ptr %fp2108, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv2109, ptr %$f1353.addr
  %fp2110 = getelementptr i8, ptr %ld2102, i64 24
  %fv2111 = load ptr, ptr %fp2110, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv2111, ptr %$f1354.addr
  %ld2112 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld2112, ptr %t.addr
  %ld2113 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld2113, ptr %h.addr
  %ld2114 = load ptr, ptr %lst.addr
  %ld2115 = load ptr, ptr %h.addr
  %ld2116 = load ptr, ptr %acc.addr
  %rc2117 = load i64, ptr %ld2114, align 8
  %uniq2118 = icmp eq i64 %rc2117, 1
  %fbip_slot2119 = alloca ptr
  br i1 %uniq2118, label %fbip_reuse407, label %fbip_fresh408
fbip_reuse407:
  %tgp2120 = getelementptr i8, ptr %ld2114, i64 8
  store i32 1, ptr %tgp2120, align 4
  %fp2121 = getelementptr i8, ptr %ld2114, i64 16
  store ptr %ld2115, ptr %fp2121, align 8
  %fp2122 = getelementptr i8, ptr %ld2114, i64 24
  store ptr %ld2116, ptr %fp2122, align 8
  store ptr %ld2114, ptr %fbip_slot2119
  br label %fbip_merge409
fbip_fresh408:
  call void @march_decrc(ptr %ld2114)
  %hp2123 = call ptr @march_alloc(i64 32)
  %tgp2124 = getelementptr i8, ptr %hp2123, i64 8
  store i32 1, ptr %tgp2124, align 4
  %fp2125 = getelementptr i8, ptr %hp2123, i64 16
  store ptr %ld2115, ptr %fp2125, align 8
  %fp2126 = getelementptr i8, ptr %hp2123, i64 24
  store ptr %ld2116, ptr %fp2126, align 8
  store ptr %hp2123, ptr %fbip_slot2119
  br label %fbip_merge409
fbip_merge409:
  %fbip_r2127 = load ptr, ptr %fbip_slot2119
  %$t1352.addr = alloca ptr
  store ptr %fbip_r2127, ptr %$t1352.addr
  %ld2128 = load ptr, ptr %go.addr
  %fp2129 = getelementptr i8, ptr %ld2128, i64 16
  %fv2130 = load ptr, ptr %fp2129, align 8
  %ld2131 = load ptr, ptr %t.addr
  %ld2132 = load ptr, ptr %$t1352.addr
  %cr2133 = call ptr (ptr, ptr, ptr) %fv2130(ptr %ld2128, ptr %ld2131, ptr %ld2132)
  store ptr %cr2133, ptr %res_slot2103
  br label %case_merge403
case_default404:
  unreachable
case_merge403:
  %case_r2134 = load ptr, ptr %res_slot2103
  ret ptr %case_r2134
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
