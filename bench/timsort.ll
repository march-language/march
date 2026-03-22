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
  %cr55 = call ptr @Sort.timsort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %ld53, ptr %ld54)
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

define ptr @Sort.timsort_by$List_Int$Fn_Int_Fn_Int_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld61 = load ptr, ptr %xs.addr
  %ld62 = load ptr, ptr %cmp.addr
  %cr63 = call ptr @Sort.detect_runs$List_V__5074$Fn_V__5074_Fn_V__5074_Bool(ptr %ld61, ptr %ld62)
  %runs.addr = alloca ptr
  store ptr %cr63, ptr %runs.addr
  %hp64 = call ptr @march_alloc(i64 32)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 0, ptr %tgp65, align 4
  %fp66 = getelementptr i8, ptr %hp64, i64 16
  store ptr @process$apply$25, ptr %fp66, align 8
  %ld67 = load ptr, ptr %cmp.addr
  %fp68 = getelementptr i8, ptr %hp64, i64 24
  store ptr %ld67, ptr %fp68, align 8
  %process.addr = alloca ptr
  store ptr %hp64, ptr %process.addr
  %hp69 = call ptr @march_alloc(i64 16)
  %tgp70 = getelementptr i8, ptr %hp69, i64 8
  store i32 0, ptr %tgp70, align 4
  %$t1625.addr = alloca ptr
  store ptr %hp69, ptr %$t1625.addr
  %ld71 = load ptr, ptr %process.addr
  %fp72 = getelementptr i8, ptr %ld71, i64 16
  %fv73 = load ptr, ptr %fp72, align 8
  %ld74 = load ptr, ptr %runs.addr
  %ld75 = load ptr, ptr %$t1625.addr
  %cr76 = call ptr (ptr, ptr, ptr) %fv73(ptr %ld71, ptr %ld74, ptr %ld75)
  %final_stack.addr = alloca ptr
  store ptr %cr76, ptr %final_stack.addr
  %ld77 = load ptr, ptr %final_stack.addr
  %ld78 = load ptr, ptr %cmp.addr
  %cr79 = call ptr @Sort.drain_stack$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %ld77, ptr %ld78)
  ret ptr %cr79
}

define ptr @Sort.drain_stack$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld80 = load ptr, ptr %stack.addr
  %cr81 = call ptr @Sort.reverse_list$List_T_List_V__5042_Int(ptr %ld80)
  %rev.addr = alloca ptr
  store ptr %cr81, ptr %rev.addr
  %hp82 = call ptr @march_alloc(i64 32)
  %tgp83 = getelementptr i8, ptr %hp82, i64 8
  store i32 0, ptr %tgp83, align 4
  %fp84 = getelementptr i8, ptr %hp82, i64 16
  store ptr @go$apply$27, ptr %fp84, align 8
  %ld85 = load ptr, ptr %cmp.addr
  %fp86 = getelementptr i8, ptr %hp82, i64 24
  store ptr %ld85, ptr %fp86, align 8
  %go.addr = alloca ptr
  store ptr %hp82, ptr %go.addr
  %ld87 = load ptr, ptr %rev.addr
  %res_slot88 = alloca ptr
  %tgp89 = getelementptr i8, ptr %ld87, i64 8
  %tag90 = load i32, ptr %tgp89, align 4
  switch i32 %tag90, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld91 = load ptr, ptr %rev.addr
  %rc92 = load i64, ptr %ld91, align 8
  %uniq93 = icmp eq i64 %rc92, 1
  %fbip_slot94 = alloca ptr
  br i1 %uniq93, label %fbip_reuse15, label %fbip_fresh16
fbip_reuse15:
  %tgp95 = getelementptr i8, ptr %ld91, i64 8
  store i32 0, ptr %tgp95, align 4
  store ptr %ld91, ptr %fbip_slot94
  br label %fbip_merge17
fbip_fresh16:
  call void @march_decrc(ptr %ld91)
  %hp96 = call ptr @march_alloc(i64 16)
  %tgp97 = getelementptr i8, ptr %hp96, i64 8
  store i32 0, ptr %tgp97, align 4
  store ptr %hp96, ptr %fbip_slot94
  br label %fbip_merge17
fbip_merge17:
  %fbip_r98 = load ptr, ptr %fbip_slot94
  store ptr %fbip_r98, ptr %res_slot88
  br label %case_merge11
case_br14:
  %fp99 = getelementptr i8, ptr %ld87, i64 16
  %fv100 = load ptr, ptr %fp99, align 8
  %$f1618.addr = alloca ptr
  store ptr %fv100, ptr %$f1618.addr
  %fp101 = getelementptr i8, ptr %ld87, i64 24
  %fv102 = load ptr, ptr %fp101, align 8
  %$f1619.addr = alloca ptr
  store ptr %fv102, ptr %$f1619.addr
  %freed103 = call i64 @march_decrc_freed(ptr %ld87)
  %freed_b104 = icmp ne i64 %freed103, 0
  br i1 %freed_b104, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv102)
  call void @march_incrc(ptr %fv100)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld105 = load ptr, ptr %$f1618.addr
  %res_slot106 = alloca ptr
  %tgp107 = getelementptr i8, ptr %ld105, i64 8
  %tag108 = load i32, ptr %tgp107, align 4
  switch i32 %tag108, label %case_default22 [
      i32 0, label %case_br23
  ]
case_br23:
  %fp109 = getelementptr i8, ptr %ld105, i64 16
  %fv110 = load ptr, ptr %fp109, align 8
  %$f1620.addr = alloca ptr
  store ptr %fv110, ptr %$f1620.addr
  %fp111 = getelementptr i8, ptr %ld105, i64 24
  %fv112 = load ptr, ptr %fp111, align 8
  %$f1621.addr = alloca ptr
  store ptr %fv112, ptr %$f1621.addr
  %freed113 = call i64 @march_decrc_freed(ptr %ld105)
  %freed_b114 = icmp ne i64 %freed113, 0
  br i1 %freed_b114, label %br_unique24, label %br_shared25
br_shared25:
  call void @march_incrc(ptr %fv112)
  call void @march_incrc(ptr %fv110)
  br label %br_body26
br_unique24:
  br label %br_body26
br_body26:
  %ld115 = load ptr, ptr %$f1619.addr
  %rest.addr = alloca ptr
  store ptr %ld115, ptr %rest.addr
  %ld116 = load ptr, ptr %$f1620.addr
  %first.addr = alloca ptr
  store ptr %ld116, ptr %first.addr
  %ld117 = load ptr, ptr %go.addr
  %fp118 = getelementptr i8, ptr %ld117, i64 16
  %fv119 = load ptr, ptr %fp118, align 8
  %ld120 = load ptr, ptr %rest.addr
  %ld121 = load ptr, ptr %first.addr
  %cr122 = call ptr (ptr, ptr, ptr) %fv119(ptr %ld117, ptr %ld120, ptr %ld121)
  store ptr %cr122, ptr %res_slot106
  br label %case_merge21
case_default22:
  unreachable
case_merge21:
  %case_r123 = load ptr, ptr %res_slot106
  store ptr %case_r123, ptr %res_slot88
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r124 = load ptr, ptr %res_slot88
  ret ptr %case_r124
}

define ptr @Sort.enforce_invariants$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld125 = load ptr, ptr %stack.addr
  %res_slot126 = alloca ptr
  %tgp127 = getelementptr i8, ptr %ld125, i64 8
  %tag128 = load i32, ptr %tgp127, align 4
  switch i32 %tag128, label %case_default28 [
      i32 1, label %case_br29
  ]
case_br29:
  %fp129 = getelementptr i8, ptr %ld125, i64 16
  %fv130 = load ptr, ptr %fp129, align 8
  %$f1597.addr = alloca ptr
  store ptr %fv130, ptr %$f1597.addr
  %fp131 = getelementptr i8, ptr %ld125, i64 24
  %fv132 = load ptr, ptr %fp131, align 8
  %$f1598.addr = alloca ptr
  store ptr %fv132, ptr %$f1598.addr
  %ld133 = load ptr, ptr %$f1597.addr
  %res_slot134 = alloca ptr
  %tgp135 = getelementptr i8, ptr %ld133, i64 8
  %tag136 = load i32, ptr %tgp135, align 4
  switch i32 %tag136, label %case_default31 [
      i32 0, label %case_br32
  ]
case_br32:
  %fp137 = getelementptr i8, ptr %ld133, i64 16
  %fv138 = load ptr, ptr %fp137, align 8
  %$f1599.addr = alloca ptr
  store ptr %fv138, ptr %$f1599.addr
  %fp139 = getelementptr i8, ptr %ld133, i64 24
  %fv140 = load ptr, ptr %fp139, align 8
  %$f1600.addr = alloca ptr
  store ptr %fv140, ptr %$f1600.addr
  %freed141 = call i64 @march_decrc_freed(ptr %ld133)
  %freed_b142 = icmp ne i64 %freed141, 0
  br i1 %freed_b142, label %br_unique33, label %br_shared34
br_shared34:
  call void @march_incrc(ptr %fv140)
  call void @march_incrc(ptr %fv138)
  br label %br_body35
br_unique33:
  br label %br_body35
br_body35:
  %ld143 = load ptr, ptr %$f1598.addr
  %res_slot144 = alloca ptr
  %tgp145 = getelementptr i8, ptr %ld143, i64 8
  %tag146 = load i32, ptr %tgp145, align 4
  switch i32 %tag146, label %case_default37 [
      i32 0, label %case_br38
  ]
case_br38:
  %fp147 = getelementptr i8, ptr %ld143, i64 16
  %fv148 = load ptr, ptr %fp147, align 8
  %$f1605.addr = alloca ptr
  store ptr %fv148, ptr %$f1605.addr
  %fp149 = getelementptr i8, ptr %ld143, i64 24
  %fv150 = load ptr, ptr %fp149, align 8
  %$f1606.addr = alloca ptr
  store ptr %fv150, ptr %$f1606.addr
  %ld151 = load ptr, ptr %$f1605.addr
  %res_slot152 = alloca ptr
  %tgp153 = getelementptr i8, ptr %ld151, i64 8
  %tag154 = load i32, ptr %tgp153, align 4
  switch i32 %tag154, label %case_default40 [
      i32 0, label %case_br41
  ]
case_br41:
  %fp155 = getelementptr i8, ptr %ld151, i64 16
  %fv156 = load ptr, ptr %fp155, align 8
  %$f1607.addr = alloca ptr
  store ptr %fv156, ptr %$f1607.addr
  %fp157 = getelementptr i8, ptr %ld151, i64 24
  %fv158 = load ptr, ptr %fp157, align 8
  %$f1608.addr = alloca ptr
  store ptr %fv158, ptr %$f1608.addr
  %freed159 = call i64 @march_decrc_freed(ptr %ld151)
  %freed_b160 = icmp ne i64 %freed159, 0
  br i1 %freed_b160, label %br_unique42, label %br_shared43
br_shared43:
  call void @march_incrc(ptr %fv158)
  call void @march_incrc(ptr %fv156)
  br label %br_body44
br_unique42:
  br label %br_body44
br_body44:
  %ld161 = load ptr, ptr %$f1606.addr
  %res_slot162 = alloca ptr
  %tgp163 = getelementptr i8, ptr %ld161, i64 8
  %tag164 = load i32, ptr %tgp163, align 4
  switch i32 %tag164, label %case_default46 [
      i32 0, label %case_br47
  ]
case_br47:
  %fp165 = getelementptr i8, ptr %ld161, i64 16
  %fv166 = load ptr, ptr %fp165, align 8
  %$f1609.addr = alloca ptr
  store ptr %fv166, ptr %$f1609.addr
  %fp167 = getelementptr i8, ptr %ld161, i64 24
  %fv168 = load ptr, ptr %fp167, align 8
  %$f1610.addr = alloca ptr
  store ptr %fv168, ptr %$f1610.addr
  %freed169 = call i64 @march_decrc_freed(ptr %ld161)
  %freed_b170 = icmp ne i64 %freed169, 0
  br i1 %freed_b170, label %br_unique48, label %br_shared49
br_shared49:
  call void @march_incrc(ptr %fv168)
  call void @march_incrc(ptr %fv166)
  br label %br_body50
br_unique48:
  br label %br_body50
br_body50:
  %ld171 = load ptr, ptr %$f1609.addr
  %res_slot172 = alloca ptr
  %tgp173 = getelementptr i8, ptr %ld171, i64 8
  %tag174 = load i32, ptr %tgp173, align 4
  switch i32 %tag174, label %case_default52 [
      i32 0, label %case_br53
  ]
case_br53:
  %fp175 = getelementptr i8, ptr %ld171, i64 16
  %fv176 = load ptr, ptr %fp175, align 8
  %$f1611.addr = alloca ptr
  store ptr %fv176, ptr %$f1611.addr
  %fp177 = getelementptr i8, ptr %ld171, i64 24
  %fv178 = load ptr, ptr %fp177, align 8
  %$f1612.addr = alloca ptr
  store ptr %fv178, ptr %$f1612.addr
  %freed179 = call i64 @march_decrc_freed(ptr %ld171)
  %freed_b180 = icmp ne i64 %freed179, 0
  br i1 %freed_b180, label %br_unique54, label %br_shared55
br_shared55:
  call void @march_incrc(ptr %fv178)
  call void @march_incrc(ptr %fv176)
  br label %br_body56
br_unique54:
  br label %br_body56
br_body56:
  %ld181 = load ptr, ptr %$f1610.addr
  %rest.addr = alloca ptr
  store ptr %ld181, ptr %rest.addr
  %ld182 = load ptr, ptr %$f1612.addr
  %zn.addr = alloca ptr
  store ptr %ld182, ptr %zn.addr
  %ld183 = load ptr, ptr %$f1611.addr
  %z.addr = alloca ptr
  store ptr %ld183, ptr %z.addr
  %ld184 = load ptr, ptr %$f1608.addr
  %yn.addr = alloca ptr
  store ptr %ld184, ptr %yn.addr
  %ld185 = load ptr, ptr %$f1607.addr
  %y.addr = alloca ptr
  store ptr %ld185, ptr %y.addr
  %ld186 = load ptr, ptr %$f1600.addr
  %xn.addr = alloca ptr
  store ptr %ld186, ptr %xn.addr
  %ld187 = load ptr, ptr %$f1599.addr
  %x.addr = alloca ptr
  store ptr %ld187, ptr %x.addr
  %ld188 = load ptr, ptr %yn.addr
  %ld189 = load ptr, ptr %xn.addr
  %cv192 = ptrtoint ptr %ld188 to i64
  %cv193 = ptrtoint ptr %ld189 to i64
  %cmp190 = icmp sle i64 %cv192, %cv193
  %ar191 = zext i1 %cmp190 to i64
  %$t1580.addr = alloca i64
  store i64 %ar191, ptr %$t1580.addr
  %ld194 = load i64, ptr %$t1580.addr
  %res_slot195 = alloca ptr
  %bi196 = trunc i64 %ld194 to i1
  br i1 %bi196, label %case_br59, label %case_default58
case_br59:
  %ld197 = load ptr, ptr %y.addr
  %a_i38.addr = alloca ptr
  store ptr %ld197, ptr %a_i38.addr
  %ld198 = load ptr, ptr %x.addr
  %b_i39.addr = alloca ptr
  store ptr %ld198, ptr %b_i39.addr
  %ld199 = load ptr, ptr %cmp.addr
  %cmp_i40.addr = alloca ptr
  store ptr %ld199, ptr %cmp_i40.addr
  %ld200 = load ptr, ptr %a_i38.addr
  %ld201 = load ptr, ptr %b_i39.addr
  %ld202 = load ptr, ptr %cmp_i40.addr
  %cr203 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld200, ptr %ld201, ptr %ld202)
  %merged.addr = alloca ptr
  store ptr %cr203, ptr %merged.addr
  %ld204 = load ptr, ptr %xn.addr
  %cv205 = ptrtoint ptr %ld204 to i64
  %ld206 = load ptr, ptr %yn.addr
  %cv207 = ptrtoint ptr %ld206 to i64
  %ar208 = add i64 %cv205, %cv207
  %$t1581.addr = alloca i64
  store i64 %ar208, ptr %$t1581.addr
  %hp209 = call ptr @march_alloc(i64 32)
  %tgp210 = getelementptr i8, ptr %hp209, i64 8
  store i32 0, ptr %tgp210, align 4
  %ld211 = load ptr, ptr %merged.addr
  %fp212 = getelementptr i8, ptr %hp209, i64 16
  store ptr %ld211, ptr %fp212, align 8
  %ld213 = load i64, ptr %$t1581.addr
  %fp214 = getelementptr i8, ptr %hp209, i64 24
  store i64 %ld213, ptr %fp214, align 8
  %$t1582.addr = alloca ptr
  store ptr %hp209, ptr %$t1582.addr
  %hp215 = call ptr @march_alloc(i64 32)
  %tgp216 = getelementptr i8, ptr %hp215, i64 8
  store i32 0, ptr %tgp216, align 4
  %ld217 = load ptr, ptr %z.addr
  %fp218 = getelementptr i8, ptr %hp215, i64 16
  store ptr %ld217, ptr %fp218, align 8
  %ld219 = load ptr, ptr %zn.addr
  %fp220 = getelementptr i8, ptr %hp215, i64 24
  store ptr %ld219, ptr %fp220, align 8
  %$t1583.addr = alloca ptr
  store ptr %hp215, ptr %$t1583.addr
  %hp221 = call ptr @march_alloc(i64 32)
  %tgp222 = getelementptr i8, ptr %hp221, i64 8
  store i32 1, ptr %tgp222, align 4
  %ld223 = load ptr, ptr %$t1583.addr
  %fp224 = getelementptr i8, ptr %hp221, i64 16
  store ptr %ld223, ptr %fp224, align 8
  %ld225 = load ptr, ptr %rest.addr
  %fp226 = getelementptr i8, ptr %hp221, i64 24
  store ptr %ld225, ptr %fp226, align 8
  %$t1584.addr = alloca ptr
  store ptr %hp221, ptr %$t1584.addr
  %hp227 = call ptr @march_alloc(i64 32)
  %tgp228 = getelementptr i8, ptr %hp227, i64 8
  store i32 1, ptr %tgp228, align 4
  %ld229 = load ptr, ptr %$t1582.addr
  %fp230 = getelementptr i8, ptr %hp227, i64 16
  store ptr %ld229, ptr %fp230, align 8
  %ld231 = load ptr, ptr %$t1584.addr
  %fp232 = getelementptr i8, ptr %hp227, i64 24
  store ptr %ld231, ptr %fp232, align 8
  %$t1585.addr = alloca ptr
  store ptr %hp227, ptr %$t1585.addr
  %ld233 = load ptr, ptr %$t1585.addr
  %ld234 = load ptr, ptr %cmp.addr
  %cr235 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld233, ptr %ld234)
  store ptr %cr235, ptr %res_slot195
  br label %case_merge57
case_default58:
  %ld236 = load ptr, ptr %yn.addr
  %cv237 = ptrtoint ptr %ld236 to i64
  %ld238 = load ptr, ptr %xn.addr
  %cv239 = ptrtoint ptr %ld238 to i64
  %ar240 = add i64 %cv237, %cv239
  %$t1586.addr = alloca i64
  store i64 %ar240, ptr %$t1586.addr
  %ld241 = load ptr, ptr %zn.addr
  %ld242 = load i64, ptr %$t1586.addr
  %cv245 = ptrtoint ptr %ld241 to i64
  %cmp243 = icmp sle i64 %cv245, %ld242
  %ar244 = zext i1 %cmp243 to i64
  %$t1587.addr = alloca i64
  store i64 %ar244, ptr %$t1587.addr
  %ld246 = load i64, ptr %$t1587.addr
  %res_slot247 = alloca ptr
  %bi248 = trunc i64 %ld246 to i1
  br i1 %bi248, label %case_br62, label %case_default61
case_br62:
  %ld249 = load ptr, ptr %z.addr
  %a_i35.addr = alloca ptr
  store ptr %ld249, ptr %a_i35.addr
  %ld250 = load ptr, ptr %y.addr
  %b_i36.addr = alloca ptr
  store ptr %ld250, ptr %b_i36.addr
  %ld251 = load ptr, ptr %cmp.addr
  %cmp_i37.addr = alloca ptr
  store ptr %ld251, ptr %cmp_i37.addr
  %ld252 = load ptr, ptr %a_i35.addr
  %ld253 = load ptr, ptr %b_i36.addr
  %ld254 = load ptr, ptr %cmp_i37.addr
  %cr255 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld252, ptr %ld253, ptr %ld254)
  %merged_1.addr = alloca ptr
  store ptr %cr255, ptr %merged_1.addr
  %hp256 = call ptr @march_alloc(i64 32)
  %tgp257 = getelementptr i8, ptr %hp256, i64 8
  store i32 0, ptr %tgp257, align 4
  %ld258 = load ptr, ptr %x.addr
  %fp259 = getelementptr i8, ptr %hp256, i64 16
  store ptr %ld258, ptr %fp259, align 8
  %ld260 = load ptr, ptr %xn.addr
  %fp261 = getelementptr i8, ptr %hp256, i64 24
  store ptr %ld260, ptr %fp261, align 8
  %$t1588.addr = alloca ptr
  store ptr %hp256, ptr %$t1588.addr
  %ld262 = load ptr, ptr %yn.addr
  %cv263 = ptrtoint ptr %ld262 to i64
  %ld264 = load ptr, ptr %zn.addr
  %cv265 = ptrtoint ptr %ld264 to i64
  %ar266 = add i64 %cv263, %cv265
  %$t1589.addr = alloca i64
  store i64 %ar266, ptr %$t1589.addr
  %hp267 = call ptr @march_alloc(i64 32)
  %tgp268 = getelementptr i8, ptr %hp267, i64 8
  store i32 0, ptr %tgp268, align 4
  %ld269 = load ptr, ptr %merged_1.addr
  %fp270 = getelementptr i8, ptr %hp267, i64 16
  store ptr %ld269, ptr %fp270, align 8
  %ld271 = load i64, ptr %$t1589.addr
  %fp272 = getelementptr i8, ptr %hp267, i64 24
  store i64 %ld271, ptr %fp272, align 8
  %$t1590.addr = alloca ptr
  store ptr %hp267, ptr %$t1590.addr
  %hp273 = call ptr @march_alloc(i64 32)
  %tgp274 = getelementptr i8, ptr %hp273, i64 8
  store i32 1, ptr %tgp274, align 4
  %ld275 = load ptr, ptr %$t1590.addr
  %fp276 = getelementptr i8, ptr %hp273, i64 16
  store ptr %ld275, ptr %fp276, align 8
  %ld277 = load ptr, ptr %rest.addr
  %fp278 = getelementptr i8, ptr %hp273, i64 24
  store ptr %ld277, ptr %fp278, align 8
  %$t1591.addr = alloca ptr
  store ptr %hp273, ptr %$t1591.addr
  %hp279 = call ptr @march_alloc(i64 32)
  %tgp280 = getelementptr i8, ptr %hp279, i64 8
  store i32 1, ptr %tgp280, align 4
  %ld281 = load ptr, ptr %$t1588.addr
  %fp282 = getelementptr i8, ptr %hp279, i64 16
  store ptr %ld281, ptr %fp282, align 8
  %ld283 = load ptr, ptr %$t1591.addr
  %fp284 = getelementptr i8, ptr %hp279, i64 24
  store ptr %ld283, ptr %fp284, align 8
  %$t1592.addr = alloca ptr
  store ptr %hp279, ptr %$t1592.addr
  %ld285 = load ptr, ptr %$t1592.addr
  %ld286 = load ptr, ptr %cmp.addr
  %cr287 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld285, ptr %ld286)
  store ptr %cr287, ptr %res_slot247
  br label %case_merge60
case_default61:
  %ld288 = load ptr, ptr %stack.addr
  store ptr %ld288, ptr %res_slot247
  br label %case_merge60
case_merge60:
  %case_r289 = load ptr, ptr %res_slot247
  store ptr %case_r289, ptr %res_slot195
  br label %case_merge57
case_merge57:
  %case_r290 = load ptr, ptr %res_slot195
  store ptr %case_r290, ptr %res_slot172
  br label %case_merge51
case_default52:
  %ld291 = load ptr, ptr %$f1609.addr
  call void @march_decrc(ptr %ld291)
  %ld292 = load ptr, ptr %$f1598.addr
  %res_slot293 = alloca ptr
  %tgp294 = getelementptr i8, ptr %ld292, i64 8
  %tag295 = load i32, ptr %tgp294, align 4
  switch i32 %tag295, label %case_default64 [
      i32 0, label %case_br65
  ]
case_br65:
  %fp296 = getelementptr i8, ptr %ld292, i64 16
  %fv297 = load ptr, ptr %fp296, align 8
  %$f1601.addr = alloca ptr
  store ptr %fv297, ptr %$f1601.addr
  %fp298 = getelementptr i8, ptr %ld292, i64 24
  %fv299 = load ptr, ptr %fp298, align 8
  %$f1602.addr = alloca ptr
  store ptr %fv299, ptr %$f1602.addr
  %freed300 = call i64 @march_decrc_freed(ptr %ld292)
  %freed_b301 = icmp ne i64 %freed300, 0
  br i1 %freed_b301, label %br_unique66, label %br_shared67
br_shared67:
  call void @march_incrc(ptr %fv299)
  call void @march_incrc(ptr %fv297)
  br label %br_body68
br_unique66:
  br label %br_body68
br_body68:
  %ld302 = load ptr, ptr %$f1601.addr
  %res_slot303 = alloca ptr
  %tgp304 = getelementptr i8, ptr %ld302, i64 8
  %tag305 = load i32, ptr %tgp304, align 4
  switch i32 %tag305, label %case_default70 [
      i32 0, label %case_br71
  ]
case_br71:
  %fp306 = getelementptr i8, ptr %ld302, i64 16
  %fv307 = load ptr, ptr %fp306, align 8
  %$f1603.addr = alloca ptr
  store ptr %fv307, ptr %$f1603.addr
  %fp308 = getelementptr i8, ptr %ld302, i64 24
  %fv309 = load ptr, ptr %fp308, align 8
  %$f1604.addr = alloca ptr
  store ptr %fv309, ptr %$f1604.addr
  %freed310 = call i64 @march_decrc_freed(ptr %ld302)
  %freed_b311 = icmp ne i64 %freed310, 0
  br i1 %freed_b311, label %br_unique72, label %br_shared73
br_shared73:
  call void @march_incrc(ptr %fv309)
  call void @march_incrc(ptr %fv307)
  br label %br_body74
br_unique72:
  br label %br_body74
br_body74:
  %ld312 = load ptr, ptr %$f1602.addr
  %res_slot313 = alloca ptr
  %tgp314 = getelementptr i8, ptr %ld312, i64 8
  %tag315 = load i32, ptr %tgp314, align 4
  switch i32 %tag315, label %case_default76 [
      i32 0, label %case_br77
  ]
case_br77:
  %ld316 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld316)
  %ld317 = load ptr, ptr %$f1604.addr
  %yn_1.addr = alloca ptr
  store ptr %ld317, ptr %yn_1.addr
  %ld318 = load ptr, ptr %$f1603.addr
  %y_1.addr = alloca ptr
  store ptr %ld318, ptr %y_1.addr
  %ld319 = load ptr, ptr %$f1600.addr
  %xn_1.addr = alloca ptr
  store ptr %ld319, ptr %xn_1.addr
  %ld320 = load ptr, ptr %$f1599.addr
  %x_1.addr = alloca ptr
  store ptr %ld320, ptr %x_1.addr
  %ld321 = load ptr, ptr %yn_1.addr
  %ld322 = load ptr, ptr %xn_1.addr
  %cv325 = ptrtoint ptr %ld321 to i64
  %cv326 = ptrtoint ptr %ld322 to i64
  %cmp323 = icmp sle i64 %cv325, %cv326
  %ar324 = zext i1 %cmp323 to i64
  %$t1593.addr = alloca i64
  store i64 %ar324, ptr %$t1593.addr
  %ld327 = load i64, ptr %$t1593.addr
  %res_slot328 = alloca ptr
  %bi329 = trunc i64 %ld327 to i1
  br i1 %bi329, label %case_br80, label %case_default79
case_br80:
  %ld330 = load ptr, ptr %y_1.addr
  %a_i32.addr = alloca ptr
  store ptr %ld330, ptr %a_i32.addr
  %ld331 = load ptr, ptr %x_1.addr
  %b_i33.addr = alloca ptr
  store ptr %ld331, ptr %b_i33.addr
  %ld332 = load ptr, ptr %cmp.addr
  %cmp_i34.addr = alloca ptr
  store ptr %ld332, ptr %cmp_i34.addr
  %ld333 = load ptr, ptr %a_i32.addr
  %ld334 = load ptr, ptr %b_i33.addr
  %ld335 = load ptr, ptr %cmp_i34.addr
  %cr336 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld333, ptr %ld334, ptr %ld335)
  %merged_2.addr = alloca ptr
  store ptr %cr336, ptr %merged_2.addr
  %ld337 = load ptr, ptr %xn_1.addr
  %cv338 = ptrtoint ptr %ld337 to i64
  %ld339 = load ptr, ptr %yn_1.addr
  %cv340 = ptrtoint ptr %ld339 to i64
  %ar341 = add i64 %cv338, %cv340
  %$t1594.addr = alloca i64
  store i64 %ar341, ptr %$t1594.addr
  %hp342 = call ptr @march_alloc(i64 32)
  %tgp343 = getelementptr i8, ptr %hp342, i64 8
  store i32 0, ptr %tgp343, align 4
  %ld344 = load ptr, ptr %merged_2.addr
  %fp345 = getelementptr i8, ptr %hp342, i64 16
  store ptr %ld344, ptr %fp345, align 8
  %ld346 = load i64, ptr %$t1594.addr
  %fp347 = getelementptr i8, ptr %hp342, i64 24
  store i64 %ld346, ptr %fp347, align 8
  %$t1595.addr = alloca ptr
  store ptr %hp342, ptr %$t1595.addr
  %hp348 = call ptr @march_alloc(i64 16)
  %tgp349 = getelementptr i8, ptr %hp348, i64 8
  store i32 0, ptr %tgp349, align 4
  %$t1596.addr = alloca ptr
  store ptr %hp348, ptr %$t1596.addr
  %hp350 = call ptr @march_alloc(i64 32)
  %tgp351 = getelementptr i8, ptr %hp350, i64 8
  store i32 1, ptr %tgp351, align 4
  %ld352 = load ptr, ptr %$t1595.addr
  %fp353 = getelementptr i8, ptr %hp350, i64 16
  store ptr %ld352, ptr %fp353, align 8
  %ld354 = load ptr, ptr %$t1596.addr
  %fp355 = getelementptr i8, ptr %hp350, i64 24
  store ptr %ld354, ptr %fp355, align 8
  store ptr %hp350, ptr %res_slot328
  br label %case_merge78
case_default79:
  %ld356 = load ptr, ptr %stack.addr
  store ptr %ld356, ptr %res_slot328
  br label %case_merge78
case_merge78:
  %case_r357 = load ptr, ptr %res_slot328
  store ptr %case_r357, ptr %res_slot313
  br label %case_merge75
case_default76:
  %ld358 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld358)
  %ld359 = load ptr, ptr %stack.addr
  store ptr %ld359, ptr %res_slot313
  br label %case_merge75
case_merge75:
  %case_r360 = load ptr, ptr %res_slot313
  store ptr %case_r360, ptr %res_slot303
  br label %case_merge69
case_default70:
  %ld361 = load ptr, ptr %$f1601.addr
  call void @march_decrc(ptr %ld361)
  %ld362 = load ptr, ptr %stack.addr
  store ptr %ld362, ptr %res_slot303
  br label %case_merge69
case_merge69:
  %case_r363 = load ptr, ptr %res_slot303
  store ptr %case_r363, ptr %res_slot293
  br label %case_merge63
case_default64:
  %ld364 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld364)
  %ld365 = load ptr, ptr %stack.addr
  store ptr %ld365, ptr %res_slot293
  br label %case_merge63
case_merge63:
  %case_r366 = load ptr, ptr %res_slot293
  store ptr %case_r366, ptr %res_slot172
  br label %case_merge51
case_merge51:
  %case_r367 = load ptr, ptr %res_slot172
  store ptr %case_r367, ptr %res_slot162
  br label %case_merge45
case_default46:
  %ld368 = load ptr, ptr %$f1606.addr
  call void @march_decrc(ptr %ld368)
  %ld369 = load ptr, ptr %$f1598.addr
  %res_slot370 = alloca ptr
  %tgp371 = getelementptr i8, ptr %ld369, i64 8
  %tag372 = load i32, ptr %tgp371, align 4
  switch i32 %tag372, label %case_default82 [
      i32 0, label %case_br83
  ]
case_br83:
  %fp373 = getelementptr i8, ptr %ld369, i64 16
  %fv374 = load ptr, ptr %fp373, align 8
  %$f1601_1.addr = alloca ptr
  store ptr %fv374, ptr %$f1601_1.addr
  %fp375 = getelementptr i8, ptr %ld369, i64 24
  %fv376 = load ptr, ptr %fp375, align 8
  %$f1602_1.addr = alloca ptr
  store ptr %fv376, ptr %$f1602_1.addr
  %freed377 = call i64 @march_decrc_freed(ptr %ld369)
  %freed_b378 = icmp ne i64 %freed377, 0
  br i1 %freed_b378, label %br_unique84, label %br_shared85
br_shared85:
  call void @march_incrc(ptr %fv376)
  call void @march_incrc(ptr %fv374)
  br label %br_body86
br_unique84:
  br label %br_body86
br_body86:
  %ld379 = load ptr, ptr %$f1601_1.addr
  %res_slot380 = alloca ptr
  %tgp381 = getelementptr i8, ptr %ld379, i64 8
  %tag382 = load i32, ptr %tgp381, align 4
  switch i32 %tag382, label %case_default88 [
      i32 0, label %case_br89
  ]
case_br89:
  %fp383 = getelementptr i8, ptr %ld379, i64 16
  %fv384 = load ptr, ptr %fp383, align 8
  %$f1603_1.addr = alloca ptr
  store ptr %fv384, ptr %$f1603_1.addr
  %fp385 = getelementptr i8, ptr %ld379, i64 24
  %fv386 = load ptr, ptr %fp385, align 8
  %$f1604_1.addr = alloca ptr
  store ptr %fv386, ptr %$f1604_1.addr
  %freed387 = call i64 @march_decrc_freed(ptr %ld379)
  %freed_b388 = icmp ne i64 %freed387, 0
  br i1 %freed_b388, label %br_unique90, label %br_shared91
br_shared91:
  call void @march_incrc(ptr %fv386)
  call void @march_incrc(ptr %fv384)
  br label %br_body92
br_unique90:
  br label %br_body92
br_body92:
  %ld389 = load ptr, ptr %$f1602_1.addr
  %res_slot390 = alloca ptr
  %tgp391 = getelementptr i8, ptr %ld389, i64 8
  %tag392 = load i32, ptr %tgp391, align 4
  switch i32 %tag392, label %case_default94 [
      i32 0, label %case_br95
  ]
case_br95:
  %ld393 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld393)
  %ld394 = load ptr, ptr %$f1604_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld394, ptr %yn_2.addr
  %ld395 = load ptr, ptr %$f1603_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld395, ptr %y_2.addr
  %ld396 = load ptr, ptr %$f1600.addr
  %xn_2.addr = alloca ptr
  store ptr %ld396, ptr %xn_2.addr
  %ld397 = load ptr, ptr %$f1599.addr
  %x_2.addr = alloca ptr
  store ptr %ld397, ptr %x_2.addr
  %ld398 = load ptr, ptr %yn_2.addr
  %ld399 = load ptr, ptr %xn_2.addr
  %cv402 = ptrtoint ptr %ld398 to i64
  %cv403 = ptrtoint ptr %ld399 to i64
  %cmp400 = icmp sle i64 %cv402, %cv403
  %ar401 = zext i1 %cmp400 to i64
  %$t1593_1.addr = alloca i64
  store i64 %ar401, ptr %$t1593_1.addr
  %ld404 = load i64, ptr %$t1593_1.addr
  %res_slot405 = alloca ptr
  %bi406 = trunc i64 %ld404 to i1
  br i1 %bi406, label %case_br98, label %case_default97
case_br98:
  %ld407 = load ptr, ptr %y_2.addr
  %a_i29.addr = alloca ptr
  store ptr %ld407, ptr %a_i29.addr
  %ld408 = load ptr, ptr %x_2.addr
  %b_i30.addr = alloca ptr
  store ptr %ld408, ptr %b_i30.addr
  %ld409 = load ptr, ptr %cmp.addr
  %cmp_i31.addr = alloca ptr
  store ptr %ld409, ptr %cmp_i31.addr
  %ld410 = load ptr, ptr %a_i29.addr
  %ld411 = load ptr, ptr %b_i30.addr
  %ld412 = load ptr, ptr %cmp_i31.addr
  %cr413 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld410, ptr %ld411, ptr %ld412)
  %merged_3.addr = alloca ptr
  store ptr %cr413, ptr %merged_3.addr
  %ld414 = load ptr, ptr %xn_2.addr
  %cv415 = ptrtoint ptr %ld414 to i64
  %ld416 = load ptr, ptr %yn_2.addr
  %cv417 = ptrtoint ptr %ld416 to i64
  %ar418 = add i64 %cv415, %cv417
  %$t1594_1.addr = alloca i64
  store i64 %ar418, ptr %$t1594_1.addr
  %hp419 = call ptr @march_alloc(i64 32)
  %tgp420 = getelementptr i8, ptr %hp419, i64 8
  store i32 0, ptr %tgp420, align 4
  %ld421 = load ptr, ptr %merged_3.addr
  %fp422 = getelementptr i8, ptr %hp419, i64 16
  store ptr %ld421, ptr %fp422, align 8
  %ld423 = load i64, ptr %$t1594_1.addr
  %fp424 = getelementptr i8, ptr %hp419, i64 24
  store i64 %ld423, ptr %fp424, align 8
  %$t1595_1.addr = alloca ptr
  store ptr %hp419, ptr %$t1595_1.addr
  %hp425 = call ptr @march_alloc(i64 16)
  %tgp426 = getelementptr i8, ptr %hp425, i64 8
  store i32 0, ptr %tgp426, align 4
  %$t1596_1.addr = alloca ptr
  store ptr %hp425, ptr %$t1596_1.addr
  %hp427 = call ptr @march_alloc(i64 32)
  %tgp428 = getelementptr i8, ptr %hp427, i64 8
  store i32 1, ptr %tgp428, align 4
  %ld429 = load ptr, ptr %$t1595_1.addr
  %fp430 = getelementptr i8, ptr %hp427, i64 16
  store ptr %ld429, ptr %fp430, align 8
  %ld431 = load ptr, ptr %$t1596_1.addr
  %fp432 = getelementptr i8, ptr %hp427, i64 24
  store ptr %ld431, ptr %fp432, align 8
  store ptr %hp427, ptr %res_slot405
  br label %case_merge96
case_default97:
  %ld433 = load ptr, ptr %stack.addr
  store ptr %ld433, ptr %res_slot405
  br label %case_merge96
case_merge96:
  %case_r434 = load ptr, ptr %res_slot405
  store ptr %case_r434, ptr %res_slot390
  br label %case_merge93
case_default94:
  %ld435 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld435)
  %ld436 = load ptr, ptr %stack.addr
  store ptr %ld436, ptr %res_slot390
  br label %case_merge93
case_merge93:
  %case_r437 = load ptr, ptr %res_slot390
  store ptr %case_r437, ptr %res_slot380
  br label %case_merge87
case_default88:
  %ld438 = load ptr, ptr %$f1601_1.addr
  call void @march_decrc(ptr %ld438)
  %ld439 = load ptr, ptr %stack.addr
  store ptr %ld439, ptr %res_slot380
  br label %case_merge87
case_merge87:
  %case_r440 = load ptr, ptr %res_slot380
  store ptr %case_r440, ptr %res_slot370
  br label %case_merge81
case_default82:
  %ld441 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld441)
  %ld442 = load ptr, ptr %stack.addr
  store ptr %ld442, ptr %res_slot370
  br label %case_merge81
case_merge81:
  %case_r443 = load ptr, ptr %res_slot370
  store ptr %case_r443, ptr %res_slot162
  br label %case_merge45
case_merge45:
  %case_r444 = load ptr, ptr %res_slot162
  store ptr %case_r444, ptr %res_slot152
  br label %case_merge39
case_default40:
  %ld445 = load ptr, ptr %$f1605.addr
  call void @march_decrc(ptr %ld445)
  %ld446 = load ptr, ptr %$f1598.addr
  %res_slot447 = alloca ptr
  %tgp448 = getelementptr i8, ptr %ld446, i64 8
  %tag449 = load i32, ptr %tgp448, align 4
  switch i32 %tag449, label %case_default100 [
      i32 0, label %case_br101
  ]
case_br101:
  %fp450 = getelementptr i8, ptr %ld446, i64 16
  %fv451 = load ptr, ptr %fp450, align 8
  %$f1601_2.addr = alloca ptr
  store ptr %fv451, ptr %$f1601_2.addr
  %fp452 = getelementptr i8, ptr %ld446, i64 24
  %fv453 = load ptr, ptr %fp452, align 8
  %$f1602_2.addr = alloca ptr
  store ptr %fv453, ptr %$f1602_2.addr
  %freed454 = call i64 @march_decrc_freed(ptr %ld446)
  %freed_b455 = icmp ne i64 %freed454, 0
  br i1 %freed_b455, label %br_unique102, label %br_shared103
br_shared103:
  call void @march_incrc(ptr %fv453)
  call void @march_incrc(ptr %fv451)
  br label %br_body104
br_unique102:
  br label %br_body104
br_body104:
  %ld456 = load ptr, ptr %$f1601_2.addr
  %res_slot457 = alloca ptr
  %tgp458 = getelementptr i8, ptr %ld456, i64 8
  %tag459 = load i32, ptr %tgp458, align 4
  switch i32 %tag459, label %case_default106 [
      i32 0, label %case_br107
  ]
case_br107:
  %fp460 = getelementptr i8, ptr %ld456, i64 16
  %fv461 = load ptr, ptr %fp460, align 8
  %$f1603_2.addr = alloca ptr
  store ptr %fv461, ptr %$f1603_2.addr
  %fp462 = getelementptr i8, ptr %ld456, i64 24
  %fv463 = load ptr, ptr %fp462, align 8
  %$f1604_2.addr = alloca ptr
  store ptr %fv463, ptr %$f1604_2.addr
  %freed464 = call i64 @march_decrc_freed(ptr %ld456)
  %freed_b465 = icmp ne i64 %freed464, 0
  br i1 %freed_b465, label %br_unique108, label %br_shared109
br_shared109:
  call void @march_incrc(ptr %fv463)
  call void @march_incrc(ptr %fv461)
  br label %br_body110
br_unique108:
  br label %br_body110
br_body110:
  %ld466 = load ptr, ptr %$f1602_2.addr
  %res_slot467 = alloca ptr
  %tgp468 = getelementptr i8, ptr %ld466, i64 8
  %tag469 = load i32, ptr %tgp468, align 4
  switch i32 %tag469, label %case_default112 [
      i32 0, label %case_br113
  ]
case_br113:
  %ld470 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld470)
  %ld471 = load ptr, ptr %$f1604_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld471, ptr %yn_3.addr
  %ld472 = load ptr, ptr %$f1603_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld472, ptr %y_3.addr
  %ld473 = load ptr, ptr %$f1600.addr
  %xn_3.addr = alloca ptr
  store ptr %ld473, ptr %xn_3.addr
  %ld474 = load ptr, ptr %$f1599.addr
  %x_3.addr = alloca ptr
  store ptr %ld474, ptr %x_3.addr
  %ld475 = load ptr, ptr %yn_3.addr
  %ld476 = load ptr, ptr %xn_3.addr
  %cv479 = ptrtoint ptr %ld475 to i64
  %cv480 = ptrtoint ptr %ld476 to i64
  %cmp477 = icmp sle i64 %cv479, %cv480
  %ar478 = zext i1 %cmp477 to i64
  %$t1593_2.addr = alloca i64
  store i64 %ar478, ptr %$t1593_2.addr
  %ld481 = load i64, ptr %$t1593_2.addr
  %res_slot482 = alloca ptr
  %bi483 = trunc i64 %ld481 to i1
  br i1 %bi483, label %case_br116, label %case_default115
case_br116:
  %ld484 = load ptr, ptr %y_3.addr
  %a_i26.addr = alloca ptr
  store ptr %ld484, ptr %a_i26.addr
  %ld485 = load ptr, ptr %x_3.addr
  %b_i27.addr = alloca ptr
  store ptr %ld485, ptr %b_i27.addr
  %ld486 = load ptr, ptr %cmp.addr
  %cmp_i28.addr = alloca ptr
  store ptr %ld486, ptr %cmp_i28.addr
  %ld487 = load ptr, ptr %a_i26.addr
  %ld488 = load ptr, ptr %b_i27.addr
  %ld489 = load ptr, ptr %cmp_i28.addr
  %cr490 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld487, ptr %ld488, ptr %ld489)
  %merged_4.addr = alloca ptr
  store ptr %cr490, ptr %merged_4.addr
  %ld491 = load ptr, ptr %xn_3.addr
  %cv492 = ptrtoint ptr %ld491 to i64
  %ld493 = load ptr, ptr %yn_3.addr
  %cv494 = ptrtoint ptr %ld493 to i64
  %ar495 = add i64 %cv492, %cv494
  %$t1594_2.addr = alloca i64
  store i64 %ar495, ptr %$t1594_2.addr
  %hp496 = call ptr @march_alloc(i64 32)
  %tgp497 = getelementptr i8, ptr %hp496, i64 8
  store i32 0, ptr %tgp497, align 4
  %ld498 = load ptr, ptr %merged_4.addr
  %fp499 = getelementptr i8, ptr %hp496, i64 16
  store ptr %ld498, ptr %fp499, align 8
  %ld500 = load i64, ptr %$t1594_2.addr
  %fp501 = getelementptr i8, ptr %hp496, i64 24
  store i64 %ld500, ptr %fp501, align 8
  %$t1595_2.addr = alloca ptr
  store ptr %hp496, ptr %$t1595_2.addr
  %hp502 = call ptr @march_alloc(i64 16)
  %tgp503 = getelementptr i8, ptr %hp502, i64 8
  store i32 0, ptr %tgp503, align 4
  %$t1596_2.addr = alloca ptr
  store ptr %hp502, ptr %$t1596_2.addr
  %hp504 = call ptr @march_alloc(i64 32)
  %tgp505 = getelementptr i8, ptr %hp504, i64 8
  store i32 1, ptr %tgp505, align 4
  %ld506 = load ptr, ptr %$t1595_2.addr
  %fp507 = getelementptr i8, ptr %hp504, i64 16
  store ptr %ld506, ptr %fp507, align 8
  %ld508 = load ptr, ptr %$t1596_2.addr
  %fp509 = getelementptr i8, ptr %hp504, i64 24
  store ptr %ld508, ptr %fp509, align 8
  store ptr %hp504, ptr %res_slot482
  br label %case_merge114
case_default115:
  %ld510 = load ptr, ptr %stack.addr
  store ptr %ld510, ptr %res_slot482
  br label %case_merge114
case_merge114:
  %case_r511 = load ptr, ptr %res_slot482
  store ptr %case_r511, ptr %res_slot467
  br label %case_merge111
case_default112:
  %ld512 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld512)
  %ld513 = load ptr, ptr %stack.addr
  store ptr %ld513, ptr %res_slot467
  br label %case_merge111
case_merge111:
  %case_r514 = load ptr, ptr %res_slot467
  store ptr %case_r514, ptr %res_slot457
  br label %case_merge105
case_default106:
  %ld515 = load ptr, ptr %$f1601_2.addr
  call void @march_decrc(ptr %ld515)
  %ld516 = load ptr, ptr %stack.addr
  store ptr %ld516, ptr %res_slot457
  br label %case_merge105
case_merge105:
  %case_r517 = load ptr, ptr %res_slot457
  store ptr %case_r517, ptr %res_slot447
  br label %case_merge99
case_default100:
  %ld518 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld518)
  %ld519 = load ptr, ptr %stack.addr
  store ptr %ld519, ptr %res_slot447
  br label %case_merge99
case_merge99:
  %case_r520 = load ptr, ptr %res_slot447
  store ptr %case_r520, ptr %res_slot152
  br label %case_merge39
case_merge39:
  %case_r521 = load ptr, ptr %res_slot152
  store ptr %case_r521, ptr %res_slot144
  br label %case_merge36
case_default37:
  %ld522 = load ptr, ptr %$f1598.addr
  %res_slot523 = alloca ptr
  %tgp524 = getelementptr i8, ptr %ld522, i64 8
  %tag525 = load i32, ptr %tgp524, align 4
  switch i32 %tag525, label %case_default118 [
      i32 0, label %case_br119
  ]
case_br119:
  %fp526 = getelementptr i8, ptr %ld522, i64 16
  %fv527 = load ptr, ptr %fp526, align 8
  %$f1601_3.addr = alloca ptr
  store ptr %fv527, ptr %$f1601_3.addr
  %fp528 = getelementptr i8, ptr %ld522, i64 24
  %fv529 = load ptr, ptr %fp528, align 8
  %$f1602_3.addr = alloca ptr
  store ptr %fv529, ptr %$f1602_3.addr
  %freed530 = call i64 @march_decrc_freed(ptr %ld522)
  %freed_b531 = icmp ne i64 %freed530, 0
  br i1 %freed_b531, label %br_unique120, label %br_shared121
br_shared121:
  call void @march_incrc(ptr %fv529)
  call void @march_incrc(ptr %fv527)
  br label %br_body122
br_unique120:
  br label %br_body122
br_body122:
  %ld532 = load ptr, ptr %$f1601_3.addr
  %res_slot533 = alloca ptr
  %tgp534 = getelementptr i8, ptr %ld532, i64 8
  %tag535 = load i32, ptr %tgp534, align 4
  switch i32 %tag535, label %case_default124 [
      i32 0, label %case_br125
  ]
case_br125:
  %fp536 = getelementptr i8, ptr %ld532, i64 16
  %fv537 = load ptr, ptr %fp536, align 8
  %$f1603_3.addr = alloca ptr
  store ptr %fv537, ptr %$f1603_3.addr
  %fp538 = getelementptr i8, ptr %ld532, i64 24
  %fv539 = load ptr, ptr %fp538, align 8
  %$f1604_3.addr = alloca ptr
  store ptr %fv539, ptr %$f1604_3.addr
  %freed540 = call i64 @march_decrc_freed(ptr %ld532)
  %freed_b541 = icmp ne i64 %freed540, 0
  br i1 %freed_b541, label %br_unique126, label %br_shared127
br_shared127:
  call void @march_incrc(ptr %fv539)
  call void @march_incrc(ptr %fv537)
  br label %br_body128
br_unique126:
  br label %br_body128
br_body128:
  %ld542 = load ptr, ptr %$f1602_3.addr
  %res_slot543 = alloca ptr
  %tgp544 = getelementptr i8, ptr %ld542, i64 8
  %tag545 = load i32, ptr %tgp544, align 4
  switch i32 %tag545, label %case_default130 [
      i32 0, label %case_br131
  ]
case_br131:
  %ld546 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld546)
  %ld547 = load ptr, ptr %$f1604_3.addr
  %yn_4.addr = alloca ptr
  store ptr %ld547, ptr %yn_4.addr
  %ld548 = load ptr, ptr %$f1603_3.addr
  %y_4.addr = alloca ptr
  store ptr %ld548, ptr %y_4.addr
  %ld549 = load ptr, ptr %$f1600.addr
  %xn_4.addr = alloca ptr
  store ptr %ld549, ptr %xn_4.addr
  %ld550 = load ptr, ptr %$f1599.addr
  %x_4.addr = alloca ptr
  store ptr %ld550, ptr %x_4.addr
  %ld551 = load ptr, ptr %yn_4.addr
  %ld552 = load ptr, ptr %xn_4.addr
  %cv555 = ptrtoint ptr %ld551 to i64
  %cv556 = ptrtoint ptr %ld552 to i64
  %cmp553 = icmp sle i64 %cv555, %cv556
  %ar554 = zext i1 %cmp553 to i64
  %$t1593_3.addr = alloca i64
  store i64 %ar554, ptr %$t1593_3.addr
  %ld557 = load i64, ptr %$t1593_3.addr
  %res_slot558 = alloca ptr
  %bi559 = trunc i64 %ld557 to i1
  br i1 %bi559, label %case_br134, label %case_default133
case_br134:
  %ld560 = load ptr, ptr %y_4.addr
  %a_i23.addr = alloca ptr
  store ptr %ld560, ptr %a_i23.addr
  %ld561 = load ptr, ptr %x_4.addr
  %b_i24.addr = alloca ptr
  store ptr %ld561, ptr %b_i24.addr
  %ld562 = load ptr, ptr %cmp.addr
  %cmp_i25.addr = alloca ptr
  store ptr %ld562, ptr %cmp_i25.addr
  %ld563 = load ptr, ptr %a_i23.addr
  %ld564 = load ptr, ptr %b_i24.addr
  %ld565 = load ptr, ptr %cmp_i25.addr
  %cr566 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld563, ptr %ld564, ptr %ld565)
  %merged_5.addr = alloca ptr
  store ptr %cr566, ptr %merged_5.addr
  %ld567 = load ptr, ptr %xn_4.addr
  %cv568 = ptrtoint ptr %ld567 to i64
  %ld569 = load ptr, ptr %yn_4.addr
  %cv570 = ptrtoint ptr %ld569 to i64
  %ar571 = add i64 %cv568, %cv570
  %$t1594_3.addr = alloca i64
  store i64 %ar571, ptr %$t1594_3.addr
  %hp572 = call ptr @march_alloc(i64 32)
  %tgp573 = getelementptr i8, ptr %hp572, i64 8
  store i32 0, ptr %tgp573, align 4
  %ld574 = load ptr, ptr %merged_5.addr
  %fp575 = getelementptr i8, ptr %hp572, i64 16
  store ptr %ld574, ptr %fp575, align 8
  %ld576 = load i64, ptr %$t1594_3.addr
  %fp577 = getelementptr i8, ptr %hp572, i64 24
  store i64 %ld576, ptr %fp577, align 8
  %$t1595_3.addr = alloca ptr
  store ptr %hp572, ptr %$t1595_3.addr
  %hp578 = call ptr @march_alloc(i64 16)
  %tgp579 = getelementptr i8, ptr %hp578, i64 8
  store i32 0, ptr %tgp579, align 4
  %$t1596_3.addr = alloca ptr
  store ptr %hp578, ptr %$t1596_3.addr
  %hp580 = call ptr @march_alloc(i64 32)
  %tgp581 = getelementptr i8, ptr %hp580, i64 8
  store i32 1, ptr %tgp581, align 4
  %ld582 = load ptr, ptr %$t1595_3.addr
  %fp583 = getelementptr i8, ptr %hp580, i64 16
  store ptr %ld582, ptr %fp583, align 8
  %ld584 = load ptr, ptr %$t1596_3.addr
  %fp585 = getelementptr i8, ptr %hp580, i64 24
  store ptr %ld584, ptr %fp585, align 8
  store ptr %hp580, ptr %res_slot558
  br label %case_merge132
case_default133:
  %ld586 = load ptr, ptr %stack.addr
  store ptr %ld586, ptr %res_slot558
  br label %case_merge132
case_merge132:
  %case_r587 = load ptr, ptr %res_slot558
  store ptr %case_r587, ptr %res_slot543
  br label %case_merge129
case_default130:
  %ld588 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld588)
  %ld589 = load ptr, ptr %stack.addr
  store ptr %ld589, ptr %res_slot543
  br label %case_merge129
case_merge129:
  %case_r590 = load ptr, ptr %res_slot543
  store ptr %case_r590, ptr %res_slot533
  br label %case_merge123
case_default124:
  %ld591 = load ptr, ptr %$f1601_3.addr
  call void @march_decrc(ptr %ld591)
  %ld592 = load ptr, ptr %stack.addr
  store ptr %ld592, ptr %res_slot533
  br label %case_merge123
case_merge123:
  %case_r593 = load ptr, ptr %res_slot533
  store ptr %case_r593, ptr %res_slot523
  br label %case_merge117
case_default118:
  %ld594 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld594)
  %ld595 = load ptr, ptr %stack.addr
  store ptr %ld595, ptr %res_slot523
  br label %case_merge117
case_merge117:
  %case_r596 = load ptr, ptr %res_slot523
  store ptr %case_r596, ptr %res_slot144
  br label %case_merge36
case_merge36:
  %case_r597 = load ptr, ptr %res_slot144
  store ptr %case_r597, ptr %res_slot134
  br label %case_merge30
case_default31:
  %ld598 = load ptr, ptr %$f1597.addr
  call void @march_decrc(ptr %ld598)
  %ld599 = load ptr, ptr %stack.addr
  store ptr %ld599, ptr %res_slot134
  br label %case_merge30
case_merge30:
  %case_r600 = load ptr, ptr %res_slot134
  store ptr %case_r600, ptr %res_slot126
  br label %case_merge27
case_default28:
  %ld601 = load ptr, ptr %stack.addr
  store ptr %ld601, ptr %res_slot126
  br label %case_merge27
case_merge27:
  %case_r602 = load ptr, ptr %res_slot126
  ret ptr %case_r602
}

define ptr @Sort.detect_runs$List_V__5074$Fn_V__5074_Fn_V__5074_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp603 = call ptr @march_alloc(i64 32)
  %tgp604 = getelementptr i8, ptr %hp603, i64 8
  store i32 0, ptr %tgp604, align 4
  %fp605 = getelementptr i8, ptr %hp603, i64 16
  store ptr @scan_run$apply$28, ptr %fp605, align 8
  %ld606 = load ptr, ptr %cmp.addr
  %fp607 = getelementptr i8, ptr %hp603, i64 24
  store ptr %ld606, ptr %fp607, align 8
  %scan_run.addr = alloca ptr
  store ptr %hp603, ptr %scan_run.addr
  %hp608 = call ptr @march_alloc(i64 40)
  %tgp609 = getelementptr i8, ptr %hp608, i64 8
  store i32 0, ptr %tgp609, align 4
  %fp610 = getelementptr i8, ptr %hp608, i64 16
  store ptr @collect$apply$29, ptr %fp610, align 8
  %ld611 = load ptr, ptr %cmp.addr
  %fp612 = getelementptr i8, ptr %hp608, i64 24
  store ptr %ld611, ptr %fp612, align 8
  %ld613 = load ptr, ptr %scan_run.addr
  %fp614 = getelementptr i8, ptr %hp608, i64 32
  store ptr %ld613, ptr %fp614, align 8
  %collect.addr = alloca ptr
  store ptr %hp608, ptr %collect.addr
  %hp615 = call ptr @march_alloc(i64 16)
  %tgp616 = getelementptr i8, ptr %hp615, i64 8
  store i32 0, ptr %tgp616, align 4
  %$t1579.addr = alloca ptr
  store ptr %hp615, ptr %$t1579.addr
  %ld617 = load ptr, ptr %collect.addr
  %fp618 = getelementptr i8, ptr %ld617, i64 16
  %fv619 = load ptr, ptr %fp618, align 8
  %ld620 = load ptr, ptr %xs.addr
  %ld621 = load ptr, ptr %$t1579.addr
  %cr622 = call ptr (ptr, ptr, ptr) %fv619(ptr %ld617, ptr %ld620, ptr %ld621)
  ret ptr %cr622
}

define ptr @Sort.reverse_list$List_T_List_V__5042_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp623 = call ptr @march_alloc(i64 24)
  %tgp624 = getelementptr i8, ptr %hp623, i64 8
  store i32 0, ptr %tgp624, align 4
  %fp625 = getelementptr i8, ptr %hp623, i64 16
  store ptr @go$apply$30, ptr %fp625, align 8
  %go.addr = alloca ptr
  store ptr %hp623, ptr %go.addr
  %hp626 = call ptr @march_alloc(i64 16)
  %tgp627 = getelementptr i8, ptr %hp626, i64 8
  store i32 0, ptr %tgp627, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp626, ptr %$t1355.addr
  %ld628 = load ptr, ptr %go.addr
  %fp629 = getelementptr i8, ptr %ld628, i64 16
  %fv630 = load ptr, ptr %fp629, align 8
  %ld631 = load ptr, ptr %xs.addr
  %ld632 = load ptr, ptr %$t1355.addr
  %cr633 = call ptr (ptr, ptr, ptr) %fv630(ptr %ld628, ptr %ld631, ptr %ld632)
  ret ptr %cr633
}

define ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %stack.arg, ptr %cmp.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld634 = load ptr, ptr %stack.addr
  %res_slot635 = alloca ptr
  %tgp636 = getelementptr i8, ptr %ld634, i64 8
  %tag637 = load i32, ptr %tgp636, align 4
  switch i32 %tag637, label %case_default136 [
      i32 1, label %case_br137
  ]
case_br137:
  %fp638 = getelementptr i8, ptr %ld634, i64 16
  %fv639 = load ptr, ptr %fp638, align 8
  %$f1597.addr = alloca ptr
  store ptr %fv639, ptr %$f1597.addr
  %fp640 = getelementptr i8, ptr %ld634, i64 24
  %fv641 = load ptr, ptr %fp640, align 8
  %$f1598.addr = alloca ptr
  store ptr %fv641, ptr %$f1598.addr
  %ld642 = load ptr, ptr %$f1597.addr
  %res_slot643 = alloca ptr
  %tgp644 = getelementptr i8, ptr %ld642, i64 8
  %tag645 = load i32, ptr %tgp644, align 4
  switch i32 %tag645, label %case_default139 [
      i32 0, label %case_br140
  ]
case_br140:
  %fp646 = getelementptr i8, ptr %ld642, i64 16
  %fv647 = load ptr, ptr %fp646, align 8
  %$f1599.addr = alloca ptr
  store ptr %fv647, ptr %$f1599.addr
  %fp648 = getelementptr i8, ptr %ld642, i64 24
  %fv649 = load ptr, ptr %fp648, align 8
  %$f1600.addr = alloca ptr
  store ptr %fv649, ptr %$f1600.addr
  %freed650 = call i64 @march_decrc_freed(ptr %ld642)
  %freed_b651 = icmp ne i64 %freed650, 0
  br i1 %freed_b651, label %br_unique141, label %br_shared142
br_shared142:
  call void @march_incrc(ptr %fv649)
  call void @march_incrc(ptr %fv647)
  br label %br_body143
br_unique141:
  br label %br_body143
br_body143:
  %ld652 = load ptr, ptr %$f1598.addr
  %res_slot653 = alloca ptr
  %tgp654 = getelementptr i8, ptr %ld652, i64 8
  %tag655 = load i32, ptr %tgp654, align 4
  switch i32 %tag655, label %case_default145 [
      i32 0, label %case_br146
  ]
case_br146:
  %fp656 = getelementptr i8, ptr %ld652, i64 16
  %fv657 = load ptr, ptr %fp656, align 8
  %$f1605.addr = alloca ptr
  store ptr %fv657, ptr %$f1605.addr
  %fp658 = getelementptr i8, ptr %ld652, i64 24
  %fv659 = load ptr, ptr %fp658, align 8
  %$f1606.addr = alloca ptr
  store ptr %fv659, ptr %$f1606.addr
  %ld660 = load ptr, ptr %$f1605.addr
  %res_slot661 = alloca ptr
  %tgp662 = getelementptr i8, ptr %ld660, i64 8
  %tag663 = load i32, ptr %tgp662, align 4
  switch i32 %tag663, label %case_default148 [
      i32 0, label %case_br149
  ]
case_br149:
  %fp664 = getelementptr i8, ptr %ld660, i64 16
  %fv665 = load ptr, ptr %fp664, align 8
  %$f1607.addr = alloca ptr
  store ptr %fv665, ptr %$f1607.addr
  %fp666 = getelementptr i8, ptr %ld660, i64 24
  %fv667 = load ptr, ptr %fp666, align 8
  %$f1608.addr = alloca ptr
  store ptr %fv667, ptr %$f1608.addr
  %freed668 = call i64 @march_decrc_freed(ptr %ld660)
  %freed_b669 = icmp ne i64 %freed668, 0
  br i1 %freed_b669, label %br_unique150, label %br_shared151
br_shared151:
  call void @march_incrc(ptr %fv667)
  call void @march_incrc(ptr %fv665)
  br label %br_body152
br_unique150:
  br label %br_body152
br_body152:
  %ld670 = load ptr, ptr %$f1606.addr
  %res_slot671 = alloca ptr
  %tgp672 = getelementptr i8, ptr %ld670, i64 8
  %tag673 = load i32, ptr %tgp672, align 4
  switch i32 %tag673, label %case_default154 [
      i32 0, label %case_br155
  ]
case_br155:
  %fp674 = getelementptr i8, ptr %ld670, i64 16
  %fv675 = load ptr, ptr %fp674, align 8
  %$f1609.addr = alloca ptr
  store ptr %fv675, ptr %$f1609.addr
  %fp676 = getelementptr i8, ptr %ld670, i64 24
  %fv677 = load ptr, ptr %fp676, align 8
  %$f1610.addr = alloca ptr
  store ptr %fv677, ptr %$f1610.addr
  %freed678 = call i64 @march_decrc_freed(ptr %ld670)
  %freed_b679 = icmp ne i64 %freed678, 0
  br i1 %freed_b679, label %br_unique156, label %br_shared157
br_shared157:
  call void @march_incrc(ptr %fv677)
  call void @march_incrc(ptr %fv675)
  br label %br_body158
br_unique156:
  br label %br_body158
br_body158:
  %ld680 = load ptr, ptr %$f1609.addr
  %res_slot681 = alloca ptr
  %tgp682 = getelementptr i8, ptr %ld680, i64 8
  %tag683 = load i32, ptr %tgp682, align 4
  switch i32 %tag683, label %case_default160 [
      i32 0, label %case_br161
  ]
case_br161:
  %fp684 = getelementptr i8, ptr %ld680, i64 16
  %fv685 = load ptr, ptr %fp684, align 8
  %$f1611.addr = alloca ptr
  store ptr %fv685, ptr %$f1611.addr
  %fp686 = getelementptr i8, ptr %ld680, i64 24
  %fv687 = load ptr, ptr %fp686, align 8
  %$f1612.addr = alloca ptr
  store ptr %fv687, ptr %$f1612.addr
  %freed688 = call i64 @march_decrc_freed(ptr %ld680)
  %freed_b689 = icmp ne i64 %freed688, 0
  br i1 %freed_b689, label %br_unique162, label %br_shared163
br_shared163:
  call void @march_incrc(ptr %fv687)
  call void @march_incrc(ptr %fv685)
  br label %br_body164
br_unique162:
  br label %br_body164
br_body164:
  %ld690 = load ptr, ptr %$f1610.addr
  %rest.addr = alloca ptr
  store ptr %ld690, ptr %rest.addr
  %ld691 = load ptr, ptr %$f1612.addr
  %zn.addr = alloca ptr
  store ptr %ld691, ptr %zn.addr
  %ld692 = load ptr, ptr %$f1611.addr
  %z.addr = alloca ptr
  store ptr %ld692, ptr %z.addr
  %ld693 = load ptr, ptr %$f1608.addr
  %yn.addr = alloca ptr
  store ptr %ld693, ptr %yn.addr
  %ld694 = load ptr, ptr %$f1607.addr
  %y.addr = alloca ptr
  store ptr %ld694, ptr %y.addr
  %ld695 = load ptr, ptr %$f1600.addr
  %xn.addr = alloca ptr
  store ptr %ld695, ptr %xn.addr
  %ld696 = load ptr, ptr %$f1599.addr
  %x.addr = alloca ptr
  store ptr %ld696, ptr %x.addr
  %ld697 = load ptr, ptr %yn.addr
  %ld698 = load ptr, ptr %xn.addr
  %cv701 = ptrtoint ptr %ld697 to i64
  %cv702 = ptrtoint ptr %ld698 to i64
  %cmp699 = icmp sle i64 %cv701, %cv702
  %ar700 = zext i1 %cmp699 to i64
  %$t1580.addr = alloca i64
  store i64 %ar700, ptr %$t1580.addr
  %ld703 = load i64, ptr %$t1580.addr
  %res_slot704 = alloca ptr
  %bi705 = trunc i64 %ld703 to i1
  br i1 %bi705, label %case_br167, label %case_default166
case_br167:
  %ld706 = load ptr, ptr %y.addr
  %a_i56.addr = alloca ptr
  store ptr %ld706, ptr %a_i56.addr
  %ld707 = load ptr, ptr %x.addr
  %b_i57.addr = alloca ptr
  store ptr %ld707, ptr %b_i57.addr
  %ld708 = load ptr, ptr %cmp.addr
  %cmp_i58.addr = alloca ptr
  store ptr %ld708, ptr %cmp_i58.addr
  %ld709 = load ptr, ptr %a_i56.addr
  %ld710 = load ptr, ptr %b_i57.addr
  %ld711 = load ptr, ptr %cmp_i58.addr
  %cr712 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld709, ptr %ld710, ptr %ld711)
  %merged.addr = alloca ptr
  store ptr %cr712, ptr %merged.addr
  %ld713 = load ptr, ptr %xn.addr
  %cv714 = ptrtoint ptr %ld713 to i64
  %ld715 = load ptr, ptr %yn.addr
  %cv716 = ptrtoint ptr %ld715 to i64
  %ar717 = add i64 %cv714, %cv716
  %$t1581.addr = alloca i64
  store i64 %ar717, ptr %$t1581.addr
  %hp718 = call ptr @march_alloc(i64 32)
  %tgp719 = getelementptr i8, ptr %hp718, i64 8
  store i32 0, ptr %tgp719, align 4
  %ld720 = load ptr, ptr %merged.addr
  %fp721 = getelementptr i8, ptr %hp718, i64 16
  store ptr %ld720, ptr %fp721, align 8
  %ld722 = load i64, ptr %$t1581.addr
  %fp723 = getelementptr i8, ptr %hp718, i64 24
  store i64 %ld722, ptr %fp723, align 8
  %$t1582.addr = alloca ptr
  store ptr %hp718, ptr %$t1582.addr
  %hp724 = call ptr @march_alloc(i64 32)
  %tgp725 = getelementptr i8, ptr %hp724, i64 8
  store i32 0, ptr %tgp725, align 4
  %ld726 = load ptr, ptr %z.addr
  %fp727 = getelementptr i8, ptr %hp724, i64 16
  store ptr %ld726, ptr %fp727, align 8
  %ld728 = load ptr, ptr %zn.addr
  %fp729 = getelementptr i8, ptr %hp724, i64 24
  store ptr %ld728, ptr %fp729, align 8
  %$t1583.addr = alloca ptr
  store ptr %hp724, ptr %$t1583.addr
  %hp730 = call ptr @march_alloc(i64 32)
  %tgp731 = getelementptr i8, ptr %hp730, i64 8
  store i32 1, ptr %tgp731, align 4
  %ld732 = load ptr, ptr %$t1583.addr
  %fp733 = getelementptr i8, ptr %hp730, i64 16
  store ptr %ld732, ptr %fp733, align 8
  %ld734 = load ptr, ptr %rest.addr
  %fp735 = getelementptr i8, ptr %hp730, i64 24
  store ptr %ld734, ptr %fp735, align 8
  %$t1584.addr = alloca ptr
  store ptr %hp730, ptr %$t1584.addr
  %hp736 = call ptr @march_alloc(i64 32)
  %tgp737 = getelementptr i8, ptr %hp736, i64 8
  store i32 1, ptr %tgp737, align 4
  %ld738 = load ptr, ptr %$t1582.addr
  %fp739 = getelementptr i8, ptr %hp736, i64 16
  store ptr %ld738, ptr %fp739, align 8
  %ld740 = load ptr, ptr %$t1584.addr
  %fp741 = getelementptr i8, ptr %hp736, i64 24
  store ptr %ld740, ptr %fp741, align 8
  %$t1585.addr = alloca ptr
  store ptr %hp736, ptr %$t1585.addr
  %ld742 = load ptr, ptr %$t1585.addr
  %ld743 = load ptr, ptr %cmp.addr
  %cr744 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld742, ptr %ld743)
  store ptr %cr744, ptr %res_slot704
  br label %case_merge165
case_default166:
  %ld745 = load ptr, ptr %yn.addr
  %cv746 = ptrtoint ptr %ld745 to i64
  %ld747 = load ptr, ptr %xn.addr
  %cv748 = ptrtoint ptr %ld747 to i64
  %ar749 = add i64 %cv746, %cv748
  %$t1586.addr = alloca i64
  store i64 %ar749, ptr %$t1586.addr
  %ld750 = load ptr, ptr %zn.addr
  %ld751 = load i64, ptr %$t1586.addr
  %cv754 = ptrtoint ptr %ld750 to i64
  %cmp752 = icmp sle i64 %cv754, %ld751
  %ar753 = zext i1 %cmp752 to i64
  %$t1587.addr = alloca i64
  store i64 %ar753, ptr %$t1587.addr
  %ld755 = load i64, ptr %$t1587.addr
  %res_slot756 = alloca ptr
  %bi757 = trunc i64 %ld755 to i1
  br i1 %bi757, label %case_br170, label %case_default169
case_br170:
  %ld758 = load ptr, ptr %z.addr
  %a_i53.addr = alloca ptr
  store ptr %ld758, ptr %a_i53.addr
  %ld759 = load ptr, ptr %y.addr
  %b_i54.addr = alloca ptr
  store ptr %ld759, ptr %b_i54.addr
  %ld760 = load ptr, ptr %cmp.addr
  %cmp_i55.addr = alloca ptr
  store ptr %ld760, ptr %cmp_i55.addr
  %ld761 = load ptr, ptr %a_i53.addr
  %ld762 = load ptr, ptr %b_i54.addr
  %ld763 = load ptr, ptr %cmp_i55.addr
  %cr764 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld761, ptr %ld762, ptr %ld763)
  %merged_1.addr = alloca ptr
  store ptr %cr764, ptr %merged_1.addr
  %hp765 = call ptr @march_alloc(i64 32)
  %tgp766 = getelementptr i8, ptr %hp765, i64 8
  store i32 0, ptr %tgp766, align 4
  %ld767 = load ptr, ptr %x.addr
  %fp768 = getelementptr i8, ptr %hp765, i64 16
  store ptr %ld767, ptr %fp768, align 8
  %ld769 = load ptr, ptr %xn.addr
  %fp770 = getelementptr i8, ptr %hp765, i64 24
  store ptr %ld769, ptr %fp770, align 8
  %$t1588.addr = alloca ptr
  store ptr %hp765, ptr %$t1588.addr
  %ld771 = load ptr, ptr %yn.addr
  %cv772 = ptrtoint ptr %ld771 to i64
  %ld773 = load ptr, ptr %zn.addr
  %cv774 = ptrtoint ptr %ld773 to i64
  %ar775 = add i64 %cv772, %cv774
  %$t1589.addr = alloca i64
  store i64 %ar775, ptr %$t1589.addr
  %hp776 = call ptr @march_alloc(i64 32)
  %tgp777 = getelementptr i8, ptr %hp776, i64 8
  store i32 0, ptr %tgp777, align 4
  %ld778 = load ptr, ptr %merged_1.addr
  %fp779 = getelementptr i8, ptr %hp776, i64 16
  store ptr %ld778, ptr %fp779, align 8
  %ld780 = load i64, ptr %$t1589.addr
  %fp781 = getelementptr i8, ptr %hp776, i64 24
  store i64 %ld780, ptr %fp781, align 8
  %$t1590.addr = alloca ptr
  store ptr %hp776, ptr %$t1590.addr
  %hp782 = call ptr @march_alloc(i64 32)
  %tgp783 = getelementptr i8, ptr %hp782, i64 8
  store i32 1, ptr %tgp783, align 4
  %ld784 = load ptr, ptr %$t1590.addr
  %fp785 = getelementptr i8, ptr %hp782, i64 16
  store ptr %ld784, ptr %fp785, align 8
  %ld786 = load ptr, ptr %rest.addr
  %fp787 = getelementptr i8, ptr %hp782, i64 24
  store ptr %ld786, ptr %fp787, align 8
  %$t1591.addr = alloca ptr
  store ptr %hp782, ptr %$t1591.addr
  %hp788 = call ptr @march_alloc(i64 32)
  %tgp789 = getelementptr i8, ptr %hp788, i64 8
  store i32 1, ptr %tgp789, align 4
  %ld790 = load ptr, ptr %$t1588.addr
  %fp791 = getelementptr i8, ptr %hp788, i64 16
  store ptr %ld790, ptr %fp791, align 8
  %ld792 = load ptr, ptr %$t1591.addr
  %fp793 = getelementptr i8, ptr %hp788, i64 24
  store ptr %ld792, ptr %fp793, align 8
  %$t1592.addr = alloca ptr
  store ptr %hp788, ptr %$t1592.addr
  %ld794 = load ptr, ptr %$t1592.addr
  %ld795 = load ptr, ptr %cmp.addr
  %cr796 = call ptr @Sort.enforce_invariants$List_T_List_V__5013_Int$Fn_V__5013_Fn_V__5013_Bool(ptr %ld794, ptr %ld795)
  store ptr %cr796, ptr %res_slot756
  br label %case_merge168
case_default169:
  %ld797 = load ptr, ptr %stack.addr
  store ptr %ld797, ptr %res_slot756
  br label %case_merge168
case_merge168:
  %case_r798 = load ptr, ptr %res_slot756
  store ptr %case_r798, ptr %res_slot704
  br label %case_merge165
case_merge165:
  %case_r799 = load ptr, ptr %res_slot704
  store ptr %case_r799, ptr %res_slot681
  br label %case_merge159
case_default160:
  %ld800 = load ptr, ptr %$f1609.addr
  call void @march_decrc(ptr %ld800)
  %ld801 = load ptr, ptr %$f1598.addr
  %res_slot802 = alloca ptr
  %tgp803 = getelementptr i8, ptr %ld801, i64 8
  %tag804 = load i32, ptr %tgp803, align 4
  switch i32 %tag804, label %case_default172 [
      i32 0, label %case_br173
  ]
case_br173:
  %fp805 = getelementptr i8, ptr %ld801, i64 16
  %fv806 = load ptr, ptr %fp805, align 8
  %$f1601.addr = alloca ptr
  store ptr %fv806, ptr %$f1601.addr
  %fp807 = getelementptr i8, ptr %ld801, i64 24
  %fv808 = load ptr, ptr %fp807, align 8
  %$f1602.addr = alloca ptr
  store ptr %fv808, ptr %$f1602.addr
  %freed809 = call i64 @march_decrc_freed(ptr %ld801)
  %freed_b810 = icmp ne i64 %freed809, 0
  br i1 %freed_b810, label %br_unique174, label %br_shared175
br_shared175:
  call void @march_incrc(ptr %fv808)
  call void @march_incrc(ptr %fv806)
  br label %br_body176
br_unique174:
  br label %br_body176
br_body176:
  %ld811 = load ptr, ptr %$f1601.addr
  %res_slot812 = alloca ptr
  %tgp813 = getelementptr i8, ptr %ld811, i64 8
  %tag814 = load i32, ptr %tgp813, align 4
  switch i32 %tag814, label %case_default178 [
      i32 0, label %case_br179
  ]
case_br179:
  %fp815 = getelementptr i8, ptr %ld811, i64 16
  %fv816 = load ptr, ptr %fp815, align 8
  %$f1603.addr = alloca ptr
  store ptr %fv816, ptr %$f1603.addr
  %fp817 = getelementptr i8, ptr %ld811, i64 24
  %fv818 = load ptr, ptr %fp817, align 8
  %$f1604.addr = alloca ptr
  store ptr %fv818, ptr %$f1604.addr
  %freed819 = call i64 @march_decrc_freed(ptr %ld811)
  %freed_b820 = icmp ne i64 %freed819, 0
  br i1 %freed_b820, label %br_unique180, label %br_shared181
br_shared181:
  call void @march_incrc(ptr %fv818)
  call void @march_incrc(ptr %fv816)
  br label %br_body182
br_unique180:
  br label %br_body182
br_body182:
  %ld821 = load ptr, ptr %$f1602.addr
  %res_slot822 = alloca ptr
  %tgp823 = getelementptr i8, ptr %ld821, i64 8
  %tag824 = load i32, ptr %tgp823, align 4
  switch i32 %tag824, label %case_default184 [
      i32 0, label %case_br185
  ]
case_br185:
  %ld825 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld825)
  %ld826 = load ptr, ptr %$f1604.addr
  %yn_1.addr = alloca ptr
  store ptr %ld826, ptr %yn_1.addr
  %ld827 = load ptr, ptr %$f1603.addr
  %y_1.addr = alloca ptr
  store ptr %ld827, ptr %y_1.addr
  %ld828 = load ptr, ptr %$f1600.addr
  %xn_1.addr = alloca ptr
  store ptr %ld828, ptr %xn_1.addr
  %ld829 = load ptr, ptr %$f1599.addr
  %x_1.addr = alloca ptr
  store ptr %ld829, ptr %x_1.addr
  %ld830 = load ptr, ptr %yn_1.addr
  %ld831 = load ptr, ptr %xn_1.addr
  %cv834 = ptrtoint ptr %ld830 to i64
  %cv835 = ptrtoint ptr %ld831 to i64
  %cmp832 = icmp sle i64 %cv834, %cv835
  %ar833 = zext i1 %cmp832 to i64
  %$t1593.addr = alloca i64
  store i64 %ar833, ptr %$t1593.addr
  %ld836 = load i64, ptr %$t1593.addr
  %res_slot837 = alloca ptr
  %bi838 = trunc i64 %ld836 to i1
  br i1 %bi838, label %case_br188, label %case_default187
case_br188:
  %ld839 = load ptr, ptr %y_1.addr
  %a_i50.addr = alloca ptr
  store ptr %ld839, ptr %a_i50.addr
  %ld840 = load ptr, ptr %x_1.addr
  %b_i51.addr = alloca ptr
  store ptr %ld840, ptr %b_i51.addr
  %ld841 = load ptr, ptr %cmp.addr
  %cmp_i52.addr = alloca ptr
  store ptr %ld841, ptr %cmp_i52.addr
  %ld842 = load ptr, ptr %a_i50.addr
  %ld843 = load ptr, ptr %b_i51.addr
  %ld844 = load ptr, ptr %cmp_i52.addr
  %cr845 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld842, ptr %ld843, ptr %ld844)
  %merged_2.addr = alloca ptr
  store ptr %cr845, ptr %merged_2.addr
  %ld846 = load ptr, ptr %xn_1.addr
  %cv847 = ptrtoint ptr %ld846 to i64
  %ld848 = load ptr, ptr %yn_1.addr
  %cv849 = ptrtoint ptr %ld848 to i64
  %ar850 = add i64 %cv847, %cv849
  %$t1594.addr = alloca i64
  store i64 %ar850, ptr %$t1594.addr
  %hp851 = call ptr @march_alloc(i64 32)
  %tgp852 = getelementptr i8, ptr %hp851, i64 8
  store i32 0, ptr %tgp852, align 4
  %ld853 = load ptr, ptr %merged_2.addr
  %fp854 = getelementptr i8, ptr %hp851, i64 16
  store ptr %ld853, ptr %fp854, align 8
  %ld855 = load i64, ptr %$t1594.addr
  %fp856 = getelementptr i8, ptr %hp851, i64 24
  store i64 %ld855, ptr %fp856, align 8
  %$t1595.addr = alloca ptr
  store ptr %hp851, ptr %$t1595.addr
  %hp857 = call ptr @march_alloc(i64 16)
  %tgp858 = getelementptr i8, ptr %hp857, i64 8
  store i32 0, ptr %tgp858, align 4
  %$t1596.addr = alloca ptr
  store ptr %hp857, ptr %$t1596.addr
  %hp859 = call ptr @march_alloc(i64 32)
  %tgp860 = getelementptr i8, ptr %hp859, i64 8
  store i32 1, ptr %tgp860, align 4
  %ld861 = load ptr, ptr %$t1595.addr
  %fp862 = getelementptr i8, ptr %hp859, i64 16
  store ptr %ld861, ptr %fp862, align 8
  %ld863 = load ptr, ptr %$t1596.addr
  %fp864 = getelementptr i8, ptr %hp859, i64 24
  store ptr %ld863, ptr %fp864, align 8
  store ptr %hp859, ptr %res_slot837
  br label %case_merge186
case_default187:
  %ld865 = load ptr, ptr %stack.addr
  store ptr %ld865, ptr %res_slot837
  br label %case_merge186
case_merge186:
  %case_r866 = load ptr, ptr %res_slot837
  store ptr %case_r866, ptr %res_slot822
  br label %case_merge183
case_default184:
  %ld867 = load ptr, ptr %$f1602.addr
  call void @march_decrc(ptr %ld867)
  %ld868 = load ptr, ptr %stack.addr
  store ptr %ld868, ptr %res_slot822
  br label %case_merge183
case_merge183:
  %case_r869 = load ptr, ptr %res_slot822
  store ptr %case_r869, ptr %res_slot812
  br label %case_merge177
case_default178:
  %ld870 = load ptr, ptr %$f1601.addr
  call void @march_decrc(ptr %ld870)
  %ld871 = load ptr, ptr %stack.addr
  store ptr %ld871, ptr %res_slot812
  br label %case_merge177
case_merge177:
  %case_r872 = load ptr, ptr %res_slot812
  store ptr %case_r872, ptr %res_slot802
  br label %case_merge171
case_default172:
  %ld873 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld873)
  %ld874 = load ptr, ptr %stack.addr
  store ptr %ld874, ptr %res_slot802
  br label %case_merge171
case_merge171:
  %case_r875 = load ptr, ptr %res_slot802
  store ptr %case_r875, ptr %res_slot681
  br label %case_merge159
case_merge159:
  %case_r876 = load ptr, ptr %res_slot681
  store ptr %case_r876, ptr %res_slot671
  br label %case_merge153
case_default154:
  %ld877 = load ptr, ptr %$f1606.addr
  call void @march_decrc(ptr %ld877)
  %ld878 = load ptr, ptr %$f1598.addr
  %res_slot879 = alloca ptr
  %tgp880 = getelementptr i8, ptr %ld878, i64 8
  %tag881 = load i32, ptr %tgp880, align 4
  switch i32 %tag881, label %case_default190 [
      i32 0, label %case_br191
  ]
case_br191:
  %fp882 = getelementptr i8, ptr %ld878, i64 16
  %fv883 = load ptr, ptr %fp882, align 8
  %$f1601_1.addr = alloca ptr
  store ptr %fv883, ptr %$f1601_1.addr
  %fp884 = getelementptr i8, ptr %ld878, i64 24
  %fv885 = load ptr, ptr %fp884, align 8
  %$f1602_1.addr = alloca ptr
  store ptr %fv885, ptr %$f1602_1.addr
  %freed886 = call i64 @march_decrc_freed(ptr %ld878)
  %freed_b887 = icmp ne i64 %freed886, 0
  br i1 %freed_b887, label %br_unique192, label %br_shared193
br_shared193:
  call void @march_incrc(ptr %fv885)
  call void @march_incrc(ptr %fv883)
  br label %br_body194
br_unique192:
  br label %br_body194
br_body194:
  %ld888 = load ptr, ptr %$f1601_1.addr
  %res_slot889 = alloca ptr
  %tgp890 = getelementptr i8, ptr %ld888, i64 8
  %tag891 = load i32, ptr %tgp890, align 4
  switch i32 %tag891, label %case_default196 [
      i32 0, label %case_br197
  ]
case_br197:
  %fp892 = getelementptr i8, ptr %ld888, i64 16
  %fv893 = load ptr, ptr %fp892, align 8
  %$f1603_1.addr = alloca ptr
  store ptr %fv893, ptr %$f1603_1.addr
  %fp894 = getelementptr i8, ptr %ld888, i64 24
  %fv895 = load ptr, ptr %fp894, align 8
  %$f1604_1.addr = alloca ptr
  store ptr %fv895, ptr %$f1604_1.addr
  %freed896 = call i64 @march_decrc_freed(ptr %ld888)
  %freed_b897 = icmp ne i64 %freed896, 0
  br i1 %freed_b897, label %br_unique198, label %br_shared199
br_shared199:
  call void @march_incrc(ptr %fv895)
  call void @march_incrc(ptr %fv893)
  br label %br_body200
br_unique198:
  br label %br_body200
br_body200:
  %ld898 = load ptr, ptr %$f1602_1.addr
  %res_slot899 = alloca ptr
  %tgp900 = getelementptr i8, ptr %ld898, i64 8
  %tag901 = load i32, ptr %tgp900, align 4
  switch i32 %tag901, label %case_default202 [
      i32 0, label %case_br203
  ]
case_br203:
  %ld902 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld902)
  %ld903 = load ptr, ptr %$f1604_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld903, ptr %yn_2.addr
  %ld904 = load ptr, ptr %$f1603_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld904, ptr %y_2.addr
  %ld905 = load ptr, ptr %$f1600.addr
  %xn_2.addr = alloca ptr
  store ptr %ld905, ptr %xn_2.addr
  %ld906 = load ptr, ptr %$f1599.addr
  %x_2.addr = alloca ptr
  store ptr %ld906, ptr %x_2.addr
  %ld907 = load ptr, ptr %yn_2.addr
  %ld908 = load ptr, ptr %xn_2.addr
  %cv911 = ptrtoint ptr %ld907 to i64
  %cv912 = ptrtoint ptr %ld908 to i64
  %cmp909 = icmp sle i64 %cv911, %cv912
  %ar910 = zext i1 %cmp909 to i64
  %$t1593_1.addr = alloca i64
  store i64 %ar910, ptr %$t1593_1.addr
  %ld913 = load i64, ptr %$t1593_1.addr
  %res_slot914 = alloca ptr
  %bi915 = trunc i64 %ld913 to i1
  br i1 %bi915, label %case_br206, label %case_default205
case_br206:
  %ld916 = load ptr, ptr %y_2.addr
  %a_i47.addr = alloca ptr
  store ptr %ld916, ptr %a_i47.addr
  %ld917 = load ptr, ptr %x_2.addr
  %b_i48.addr = alloca ptr
  store ptr %ld917, ptr %b_i48.addr
  %ld918 = load ptr, ptr %cmp.addr
  %cmp_i49.addr = alloca ptr
  store ptr %ld918, ptr %cmp_i49.addr
  %ld919 = load ptr, ptr %a_i47.addr
  %ld920 = load ptr, ptr %b_i48.addr
  %ld921 = load ptr, ptr %cmp_i49.addr
  %cr922 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld919, ptr %ld920, ptr %ld921)
  %merged_3.addr = alloca ptr
  store ptr %cr922, ptr %merged_3.addr
  %ld923 = load ptr, ptr %xn_2.addr
  %cv924 = ptrtoint ptr %ld923 to i64
  %ld925 = load ptr, ptr %yn_2.addr
  %cv926 = ptrtoint ptr %ld925 to i64
  %ar927 = add i64 %cv924, %cv926
  %$t1594_1.addr = alloca i64
  store i64 %ar927, ptr %$t1594_1.addr
  %hp928 = call ptr @march_alloc(i64 32)
  %tgp929 = getelementptr i8, ptr %hp928, i64 8
  store i32 0, ptr %tgp929, align 4
  %ld930 = load ptr, ptr %merged_3.addr
  %fp931 = getelementptr i8, ptr %hp928, i64 16
  store ptr %ld930, ptr %fp931, align 8
  %ld932 = load i64, ptr %$t1594_1.addr
  %fp933 = getelementptr i8, ptr %hp928, i64 24
  store i64 %ld932, ptr %fp933, align 8
  %$t1595_1.addr = alloca ptr
  store ptr %hp928, ptr %$t1595_1.addr
  %hp934 = call ptr @march_alloc(i64 16)
  %tgp935 = getelementptr i8, ptr %hp934, i64 8
  store i32 0, ptr %tgp935, align 4
  %$t1596_1.addr = alloca ptr
  store ptr %hp934, ptr %$t1596_1.addr
  %hp936 = call ptr @march_alloc(i64 32)
  %tgp937 = getelementptr i8, ptr %hp936, i64 8
  store i32 1, ptr %tgp937, align 4
  %ld938 = load ptr, ptr %$t1595_1.addr
  %fp939 = getelementptr i8, ptr %hp936, i64 16
  store ptr %ld938, ptr %fp939, align 8
  %ld940 = load ptr, ptr %$t1596_1.addr
  %fp941 = getelementptr i8, ptr %hp936, i64 24
  store ptr %ld940, ptr %fp941, align 8
  store ptr %hp936, ptr %res_slot914
  br label %case_merge204
case_default205:
  %ld942 = load ptr, ptr %stack.addr
  store ptr %ld942, ptr %res_slot914
  br label %case_merge204
case_merge204:
  %case_r943 = load ptr, ptr %res_slot914
  store ptr %case_r943, ptr %res_slot899
  br label %case_merge201
case_default202:
  %ld944 = load ptr, ptr %$f1602_1.addr
  call void @march_decrc(ptr %ld944)
  %ld945 = load ptr, ptr %stack.addr
  store ptr %ld945, ptr %res_slot899
  br label %case_merge201
case_merge201:
  %case_r946 = load ptr, ptr %res_slot899
  store ptr %case_r946, ptr %res_slot889
  br label %case_merge195
case_default196:
  %ld947 = load ptr, ptr %$f1601_1.addr
  call void @march_decrc(ptr %ld947)
  %ld948 = load ptr, ptr %stack.addr
  store ptr %ld948, ptr %res_slot889
  br label %case_merge195
case_merge195:
  %case_r949 = load ptr, ptr %res_slot889
  store ptr %case_r949, ptr %res_slot879
  br label %case_merge189
case_default190:
  %ld950 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld950)
  %ld951 = load ptr, ptr %stack.addr
  store ptr %ld951, ptr %res_slot879
  br label %case_merge189
case_merge189:
  %case_r952 = load ptr, ptr %res_slot879
  store ptr %case_r952, ptr %res_slot671
  br label %case_merge153
case_merge153:
  %case_r953 = load ptr, ptr %res_slot671
  store ptr %case_r953, ptr %res_slot661
  br label %case_merge147
case_default148:
  %ld954 = load ptr, ptr %$f1605.addr
  call void @march_decrc(ptr %ld954)
  %ld955 = load ptr, ptr %$f1598.addr
  %res_slot956 = alloca ptr
  %tgp957 = getelementptr i8, ptr %ld955, i64 8
  %tag958 = load i32, ptr %tgp957, align 4
  switch i32 %tag958, label %case_default208 [
      i32 0, label %case_br209
  ]
case_br209:
  %fp959 = getelementptr i8, ptr %ld955, i64 16
  %fv960 = load ptr, ptr %fp959, align 8
  %$f1601_2.addr = alloca ptr
  store ptr %fv960, ptr %$f1601_2.addr
  %fp961 = getelementptr i8, ptr %ld955, i64 24
  %fv962 = load ptr, ptr %fp961, align 8
  %$f1602_2.addr = alloca ptr
  store ptr %fv962, ptr %$f1602_2.addr
  %freed963 = call i64 @march_decrc_freed(ptr %ld955)
  %freed_b964 = icmp ne i64 %freed963, 0
  br i1 %freed_b964, label %br_unique210, label %br_shared211
br_shared211:
  call void @march_incrc(ptr %fv962)
  call void @march_incrc(ptr %fv960)
  br label %br_body212
br_unique210:
  br label %br_body212
br_body212:
  %ld965 = load ptr, ptr %$f1601_2.addr
  %res_slot966 = alloca ptr
  %tgp967 = getelementptr i8, ptr %ld965, i64 8
  %tag968 = load i32, ptr %tgp967, align 4
  switch i32 %tag968, label %case_default214 [
      i32 0, label %case_br215
  ]
case_br215:
  %fp969 = getelementptr i8, ptr %ld965, i64 16
  %fv970 = load ptr, ptr %fp969, align 8
  %$f1603_2.addr = alloca ptr
  store ptr %fv970, ptr %$f1603_2.addr
  %fp971 = getelementptr i8, ptr %ld965, i64 24
  %fv972 = load ptr, ptr %fp971, align 8
  %$f1604_2.addr = alloca ptr
  store ptr %fv972, ptr %$f1604_2.addr
  %freed973 = call i64 @march_decrc_freed(ptr %ld965)
  %freed_b974 = icmp ne i64 %freed973, 0
  br i1 %freed_b974, label %br_unique216, label %br_shared217
br_shared217:
  call void @march_incrc(ptr %fv972)
  call void @march_incrc(ptr %fv970)
  br label %br_body218
br_unique216:
  br label %br_body218
br_body218:
  %ld975 = load ptr, ptr %$f1602_2.addr
  %res_slot976 = alloca ptr
  %tgp977 = getelementptr i8, ptr %ld975, i64 8
  %tag978 = load i32, ptr %tgp977, align 4
  switch i32 %tag978, label %case_default220 [
      i32 0, label %case_br221
  ]
case_br221:
  %ld979 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld979)
  %ld980 = load ptr, ptr %$f1604_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld980, ptr %yn_3.addr
  %ld981 = load ptr, ptr %$f1603_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld981, ptr %y_3.addr
  %ld982 = load ptr, ptr %$f1600.addr
  %xn_3.addr = alloca ptr
  store ptr %ld982, ptr %xn_3.addr
  %ld983 = load ptr, ptr %$f1599.addr
  %x_3.addr = alloca ptr
  store ptr %ld983, ptr %x_3.addr
  %ld984 = load ptr, ptr %yn_3.addr
  %ld985 = load ptr, ptr %xn_3.addr
  %cv988 = ptrtoint ptr %ld984 to i64
  %cv989 = ptrtoint ptr %ld985 to i64
  %cmp986 = icmp sle i64 %cv988, %cv989
  %ar987 = zext i1 %cmp986 to i64
  %$t1593_2.addr = alloca i64
  store i64 %ar987, ptr %$t1593_2.addr
  %ld990 = load i64, ptr %$t1593_2.addr
  %res_slot991 = alloca ptr
  %bi992 = trunc i64 %ld990 to i1
  br i1 %bi992, label %case_br224, label %case_default223
case_br224:
  %ld993 = load ptr, ptr %y_3.addr
  %a_i44.addr = alloca ptr
  store ptr %ld993, ptr %a_i44.addr
  %ld994 = load ptr, ptr %x_3.addr
  %b_i45.addr = alloca ptr
  store ptr %ld994, ptr %b_i45.addr
  %ld995 = load ptr, ptr %cmp.addr
  %cmp_i46.addr = alloca ptr
  store ptr %ld995, ptr %cmp_i46.addr
  %ld996 = load ptr, ptr %a_i44.addr
  %ld997 = load ptr, ptr %b_i45.addr
  %ld998 = load ptr, ptr %cmp_i46.addr
  %cr999 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld996, ptr %ld997, ptr %ld998)
  %merged_4.addr = alloca ptr
  store ptr %cr999, ptr %merged_4.addr
  %ld1000 = load ptr, ptr %xn_3.addr
  %cv1001 = ptrtoint ptr %ld1000 to i64
  %ld1002 = load ptr, ptr %yn_3.addr
  %cv1003 = ptrtoint ptr %ld1002 to i64
  %ar1004 = add i64 %cv1001, %cv1003
  %$t1594_2.addr = alloca i64
  store i64 %ar1004, ptr %$t1594_2.addr
  %hp1005 = call ptr @march_alloc(i64 32)
  %tgp1006 = getelementptr i8, ptr %hp1005, i64 8
  store i32 0, ptr %tgp1006, align 4
  %ld1007 = load ptr, ptr %merged_4.addr
  %fp1008 = getelementptr i8, ptr %hp1005, i64 16
  store ptr %ld1007, ptr %fp1008, align 8
  %ld1009 = load i64, ptr %$t1594_2.addr
  %fp1010 = getelementptr i8, ptr %hp1005, i64 24
  store i64 %ld1009, ptr %fp1010, align 8
  %$t1595_2.addr = alloca ptr
  store ptr %hp1005, ptr %$t1595_2.addr
  %hp1011 = call ptr @march_alloc(i64 16)
  %tgp1012 = getelementptr i8, ptr %hp1011, i64 8
  store i32 0, ptr %tgp1012, align 4
  %$t1596_2.addr = alloca ptr
  store ptr %hp1011, ptr %$t1596_2.addr
  %hp1013 = call ptr @march_alloc(i64 32)
  %tgp1014 = getelementptr i8, ptr %hp1013, i64 8
  store i32 1, ptr %tgp1014, align 4
  %ld1015 = load ptr, ptr %$t1595_2.addr
  %fp1016 = getelementptr i8, ptr %hp1013, i64 16
  store ptr %ld1015, ptr %fp1016, align 8
  %ld1017 = load ptr, ptr %$t1596_2.addr
  %fp1018 = getelementptr i8, ptr %hp1013, i64 24
  store ptr %ld1017, ptr %fp1018, align 8
  store ptr %hp1013, ptr %res_slot991
  br label %case_merge222
case_default223:
  %ld1019 = load ptr, ptr %stack.addr
  store ptr %ld1019, ptr %res_slot991
  br label %case_merge222
case_merge222:
  %case_r1020 = load ptr, ptr %res_slot991
  store ptr %case_r1020, ptr %res_slot976
  br label %case_merge219
case_default220:
  %ld1021 = load ptr, ptr %$f1602_2.addr
  call void @march_decrc(ptr %ld1021)
  %ld1022 = load ptr, ptr %stack.addr
  store ptr %ld1022, ptr %res_slot976
  br label %case_merge219
case_merge219:
  %case_r1023 = load ptr, ptr %res_slot976
  store ptr %case_r1023, ptr %res_slot966
  br label %case_merge213
case_default214:
  %ld1024 = load ptr, ptr %$f1601_2.addr
  call void @march_decrc(ptr %ld1024)
  %ld1025 = load ptr, ptr %stack.addr
  store ptr %ld1025, ptr %res_slot966
  br label %case_merge213
case_merge213:
  %case_r1026 = load ptr, ptr %res_slot966
  store ptr %case_r1026, ptr %res_slot956
  br label %case_merge207
case_default208:
  %ld1027 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1027)
  %ld1028 = load ptr, ptr %stack.addr
  store ptr %ld1028, ptr %res_slot956
  br label %case_merge207
case_merge207:
  %case_r1029 = load ptr, ptr %res_slot956
  store ptr %case_r1029, ptr %res_slot661
  br label %case_merge147
case_merge147:
  %case_r1030 = load ptr, ptr %res_slot661
  store ptr %case_r1030, ptr %res_slot653
  br label %case_merge144
case_default145:
  %ld1031 = load ptr, ptr %$f1598.addr
  %res_slot1032 = alloca ptr
  %tgp1033 = getelementptr i8, ptr %ld1031, i64 8
  %tag1034 = load i32, ptr %tgp1033, align 4
  switch i32 %tag1034, label %case_default226 [
      i32 0, label %case_br227
  ]
case_br227:
  %fp1035 = getelementptr i8, ptr %ld1031, i64 16
  %fv1036 = load ptr, ptr %fp1035, align 8
  %$f1601_3.addr = alloca ptr
  store ptr %fv1036, ptr %$f1601_3.addr
  %fp1037 = getelementptr i8, ptr %ld1031, i64 24
  %fv1038 = load ptr, ptr %fp1037, align 8
  %$f1602_3.addr = alloca ptr
  store ptr %fv1038, ptr %$f1602_3.addr
  %freed1039 = call i64 @march_decrc_freed(ptr %ld1031)
  %freed_b1040 = icmp ne i64 %freed1039, 0
  br i1 %freed_b1040, label %br_unique228, label %br_shared229
br_shared229:
  call void @march_incrc(ptr %fv1038)
  call void @march_incrc(ptr %fv1036)
  br label %br_body230
br_unique228:
  br label %br_body230
br_body230:
  %ld1041 = load ptr, ptr %$f1601_3.addr
  %res_slot1042 = alloca ptr
  %tgp1043 = getelementptr i8, ptr %ld1041, i64 8
  %tag1044 = load i32, ptr %tgp1043, align 4
  switch i32 %tag1044, label %case_default232 [
      i32 0, label %case_br233
  ]
case_br233:
  %fp1045 = getelementptr i8, ptr %ld1041, i64 16
  %fv1046 = load ptr, ptr %fp1045, align 8
  %$f1603_3.addr = alloca ptr
  store ptr %fv1046, ptr %$f1603_3.addr
  %fp1047 = getelementptr i8, ptr %ld1041, i64 24
  %fv1048 = load ptr, ptr %fp1047, align 8
  %$f1604_3.addr = alloca ptr
  store ptr %fv1048, ptr %$f1604_3.addr
  %freed1049 = call i64 @march_decrc_freed(ptr %ld1041)
  %freed_b1050 = icmp ne i64 %freed1049, 0
  br i1 %freed_b1050, label %br_unique234, label %br_shared235
br_shared235:
  call void @march_incrc(ptr %fv1048)
  call void @march_incrc(ptr %fv1046)
  br label %br_body236
br_unique234:
  br label %br_body236
br_body236:
  %ld1051 = load ptr, ptr %$f1602_3.addr
  %res_slot1052 = alloca ptr
  %tgp1053 = getelementptr i8, ptr %ld1051, i64 8
  %tag1054 = load i32, ptr %tgp1053, align 4
  switch i32 %tag1054, label %case_default238 [
      i32 0, label %case_br239
  ]
case_br239:
  %ld1055 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld1055)
  %ld1056 = load ptr, ptr %$f1604_3.addr
  %yn_4.addr = alloca ptr
  store ptr %ld1056, ptr %yn_4.addr
  %ld1057 = load ptr, ptr %$f1603_3.addr
  %y_4.addr = alloca ptr
  store ptr %ld1057, ptr %y_4.addr
  %ld1058 = load ptr, ptr %$f1600.addr
  %xn_4.addr = alloca ptr
  store ptr %ld1058, ptr %xn_4.addr
  %ld1059 = load ptr, ptr %$f1599.addr
  %x_4.addr = alloca ptr
  store ptr %ld1059, ptr %x_4.addr
  %ld1060 = load ptr, ptr %yn_4.addr
  %ld1061 = load ptr, ptr %xn_4.addr
  %cv1064 = ptrtoint ptr %ld1060 to i64
  %cv1065 = ptrtoint ptr %ld1061 to i64
  %cmp1062 = icmp sle i64 %cv1064, %cv1065
  %ar1063 = zext i1 %cmp1062 to i64
  %$t1593_3.addr = alloca i64
  store i64 %ar1063, ptr %$t1593_3.addr
  %ld1066 = load i64, ptr %$t1593_3.addr
  %res_slot1067 = alloca ptr
  %bi1068 = trunc i64 %ld1066 to i1
  br i1 %bi1068, label %case_br242, label %case_default241
case_br242:
  %ld1069 = load ptr, ptr %y_4.addr
  %a_i41.addr = alloca ptr
  store ptr %ld1069, ptr %a_i41.addr
  %ld1070 = load ptr, ptr %x_4.addr
  %b_i42.addr = alloca ptr
  store ptr %ld1070, ptr %b_i42.addr
  %ld1071 = load ptr, ptr %cmp.addr
  %cmp_i43.addr = alloca ptr
  store ptr %ld1071, ptr %cmp_i43.addr
  %ld1072 = load ptr, ptr %a_i41.addr
  %ld1073 = load ptr, ptr %b_i42.addr
  %ld1074 = load ptr, ptr %cmp_i43.addr
  %cr1075 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1072, ptr %ld1073, ptr %ld1074)
  %merged_5.addr = alloca ptr
  store ptr %cr1075, ptr %merged_5.addr
  %ld1076 = load ptr, ptr %xn_4.addr
  %cv1077 = ptrtoint ptr %ld1076 to i64
  %ld1078 = load ptr, ptr %yn_4.addr
  %cv1079 = ptrtoint ptr %ld1078 to i64
  %ar1080 = add i64 %cv1077, %cv1079
  %$t1594_3.addr = alloca i64
  store i64 %ar1080, ptr %$t1594_3.addr
  %hp1081 = call ptr @march_alloc(i64 32)
  %tgp1082 = getelementptr i8, ptr %hp1081, i64 8
  store i32 0, ptr %tgp1082, align 4
  %ld1083 = load ptr, ptr %merged_5.addr
  %fp1084 = getelementptr i8, ptr %hp1081, i64 16
  store ptr %ld1083, ptr %fp1084, align 8
  %ld1085 = load i64, ptr %$t1594_3.addr
  %fp1086 = getelementptr i8, ptr %hp1081, i64 24
  store i64 %ld1085, ptr %fp1086, align 8
  %$t1595_3.addr = alloca ptr
  store ptr %hp1081, ptr %$t1595_3.addr
  %hp1087 = call ptr @march_alloc(i64 16)
  %tgp1088 = getelementptr i8, ptr %hp1087, i64 8
  store i32 0, ptr %tgp1088, align 4
  %$t1596_3.addr = alloca ptr
  store ptr %hp1087, ptr %$t1596_3.addr
  %hp1089 = call ptr @march_alloc(i64 32)
  %tgp1090 = getelementptr i8, ptr %hp1089, i64 8
  store i32 1, ptr %tgp1090, align 4
  %ld1091 = load ptr, ptr %$t1595_3.addr
  %fp1092 = getelementptr i8, ptr %hp1089, i64 16
  store ptr %ld1091, ptr %fp1092, align 8
  %ld1093 = load ptr, ptr %$t1596_3.addr
  %fp1094 = getelementptr i8, ptr %hp1089, i64 24
  store ptr %ld1093, ptr %fp1094, align 8
  store ptr %hp1089, ptr %res_slot1067
  br label %case_merge240
case_default241:
  %ld1095 = load ptr, ptr %stack.addr
  store ptr %ld1095, ptr %res_slot1067
  br label %case_merge240
case_merge240:
  %case_r1096 = load ptr, ptr %res_slot1067
  store ptr %case_r1096, ptr %res_slot1052
  br label %case_merge237
case_default238:
  %ld1097 = load ptr, ptr %$f1602_3.addr
  call void @march_decrc(ptr %ld1097)
  %ld1098 = load ptr, ptr %stack.addr
  store ptr %ld1098, ptr %res_slot1052
  br label %case_merge237
case_merge237:
  %case_r1099 = load ptr, ptr %res_slot1052
  store ptr %case_r1099, ptr %res_slot1042
  br label %case_merge231
case_default232:
  %ld1100 = load ptr, ptr %$f1601_3.addr
  call void @march_decrc(ptr %ld1100)
  %ld1101 = load ptr, ptr %stack.addr
  store ptr %ld1101, ptr %res_slot1042
  br label %case_merge231
case_merge231:
  %case_r1102 = load ptr, ptr %res_slot1042
  store ptr %case_r1102, ptr %res_slot1032
  br label %case_merge225
case_default226:
  %ld1103 = load ptr, ptr %$f1598.addr
  call void @march_decrc(ptr %ld1103)
  %ld1104 = load ptr, ptr %stack.addr
  store ptr %ld1104, ptr %res_slot1032
  br label %case_merge225
case_merge225:
  %case_r1105 = load ptr, ptr %res_slot1032
  store ptr %case_r1105, ptr %res_slot653
  br label %case_merge144
case_merge144:
  %case_r1106 = load ptr, ptr %res_slot653
  store ptr %case_r1106, ptr %res_slot643
  br label %case_merge138
case_default139:
  %ld1107 = load ptr, ptr %$f1597.addr
  call void @march_decrc(ptr %ld1107)
  %ld1108 = load ptr, ptr %stack.addr
  store ptr %ld1108, ptr %res_slot643
  br label %case_merge138
case_merge138:
  %case_r1109 = load ptr, ptr %res_slot643
  store ptr %case_r1109, ptr %res_slot635
  br label %case_merge135
case_default136:
  %ld1110 = load ptr, ptr %stack.addr
  store ptr %ld1110, ptr %res_slot635
  br label %case_merge135
case_merge135:
  %case_r1111 = load ptr, ptr %res_slot635
  ret ptr %case_r1111
}

define ptr @Sort.reverse_list$List_T_List_V__4971_Int(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1112 = call ptr @march_alloc(i64 24)
  %tgp1113 = getelementptr i8, ptr %hp1112, i64 8
  store i32 0, ptr %tgp1113, align 4
  %fp1114 = getelementptr i8, ptr %hp1112, i64 16
  store ptr @go$apply$31, ptr %fp1114, align 8
  %go.addr = alloca ptr
  store ptr %hp1112, ptr %go.addr
  %hp1115 = call ptr @march_alloc(i64 16)
  %tgp1116 = getelementptr i8, ptr %hp1115, i64 8
  store i32 0, ptr %tgp1116, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp1115, ptr %$t1355.addr
  %ld1117 = load ptr, ptr %go.addr
  %fp1118 = getelementptr i8, ptr %ld1117, i64 16
  %fv1119 = load ptr, ptr %fp1118, align 8
  %ld1120 = load ptr, ptr %xs.addr
  %ld1121 = load ptr, ptr %$t1355.addr
  %cr1122 = call ptr (ptr, ptr, ptr) %fv1119(ptr %ld1117, ptr %ld1120, ptr %ld1121)
  ret ptr %cr1122
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
  %ld1123 = load i64, ptr %run_len.addr
  %cmp1124 = icmp sge i64 %ld1123, 16
  %ar1125 = zext i1 %cmp1124 to i64
  %$t1556.addr = alloca i64
  store i64 %ar1125, ptr %$t1556.addr
  %ld1126 = load i64, ptr %$t1556.addr
  %res_slot1127 = alloca ptr
  %bi1128 = trunc i64 %ld1126 to i1
  br i1 %bi1128, label %case_br245, label %case_default244
case_br245:
  %hp1129 = call ptr @march_alloc(i64 40)
  %tgp1130 = getelementptr i8, ptr %hp1129, i64 8
  store i32 0, ptr %tgp1130, align 4
  %ld1131 = load ptr, ptr %run.addr
  %fp1132 = getelementptr i8, ptr %hp1129, i64 16
  store ptr %ld1131, ptr %fp1132, align 8
  %ld1133 = load i64, ptr %run_len.addr
  %fp1134 = getelementptr i8, ptr %hp1129, i64 24
  store i64 %ld1133, ptr %fp1134, align 8
  %ld1135 = load ptr, ptr %rest.addr
  %fp1136 = getelementptr i8, ptr %hp1129, i64 32
  store ptr %ld1135, ptr %fp1136, align 8
  store ptr %hp1129, ptr %res_slot1127
  br label %case_merge243
case_default244:
  %ld1137 = load ptr, ptr %rest.addr
  %res_slot1138 = alloca ptr
  %tgp1139 = getelementptr i8, ptr %ld1137, i64 8
  %tag1140 = load i32, ptr %tgp1139, align 4
  switch i32 %tag1140, label %case_default247 [
      i32 0, label %case_br248
      i32 1, label %case_br249
  ]
case_br248:
  %ld1141 = load ptr, ptr %rest.addr
  %rc1142 = load i64, ptr %ld1141, align 8
  %uniq1143 = icmp eq i64 %rc1142, 1
  %fbip_slot1144 = alloca ptr
  br i1 %uniq1143, label %fbip_reuse250, label %fbip_fresh251
fbip_reuse250:
  %tgp1145 = getelementptr i8, ptr %ld1141, i64 8
  store i32 0, ptr %tgp1145, align 4
  store ptr %ld1141, ptr %fbip_slot1144
  br label %fbip_merge252
fbip_fresh251:
  call void @march_decrc(ptr %ld1141)
  %hp1146 = call ptr @march_alloc(i64 16)
  %tgp1147 = getelementptr i8, ptr %hp1146, i64 8
  store i32 0, ptr %tgp1147, align 4
  store ptr %hp1146, ptr %fbip_slot1144
  br label %fbip_merge252
fbip_merge252:
  %fbip_r1148 = load ptr, ptr %fbip_slot1144
  %$t1557.addr = alloca ptr
  store ptr %fbip_r1148, ptr %$t1557.addr
  %hp1149 = call ptr @march_alloc(i64 40)
  %tgp1150 = getelementptr i8, ptr %hp1149, i64 8
  store i32 0, ptr %tgp1150, align 4
  %ld1151 = load ptr, ptr %run.addr
  %fp1152 = getelementptr i8, ptr %hp1149, i64 16
  store ptr %ld1151, ptr %fp1152, align 8
  %ld1153 = load i64, ptr %run_len.addr
  %fp1154 = getelementptr i8, ptr %hp1149, i64 24
  store i64 %ld1153, ptr %fp1154, align 8
  %ld1155 = load ptr, ptr %$t1557.addr
  %fp1156 = getelementptr i8, ptr %hp1149, i64 32
  store ptr %ld1155, ptr %fp1156, align 8
  store ptr %hp1149, ptr %res_slot1138
  br label %case_merge246
case_br249:
  %fp1157 = getelementptr i8, ptr %ld1137, i64 16
  %fv1158 = load ptr, ptr %fp1157, align 8
  %$f1560.addr = alloca ptr
  store ptr %fv1158, ptr %$f1560.addr
  %fp1159 = getelementptr i8, ptr %ld1137, i64 24
  %fv1160 = load ptr, ptr %fp1159, align 8
  %$f1561.addr = alloca ptr
  store ptr %fv1160, ptr %$f1561.addr
  %freed1161 = call i64 @march_decrc_freed(ptr %ld1137)
  %freed_b1162 = icmp ne i64 %freed1161, 0
  br i1 %freed_b1162, label %br_unique253, label %br_shared254
br_shared254:
  call void @march_incrc(ptr %fv1160)
  call void @march_incrc(ptr %fv1158)
  br label %br_body255
br_unique253:
  br label %br_body255
br_body255:
  %ld1163 = load ptr, ptr %$f1561.addr
  %t.addr = alloca ptr
  store ptr %ld1163, ptr %t.addr
  %ld1164 = load ptr, ptr %$f1560.addr
  %h.addr = alloca ptr
  store ptr %ld1164, ptr %h.addr
  %ld1165 = load ptr, ptr %h.addr
  %ld1166 = load ptr, ptr %run.addr
  %ld1167 = load ptr, ptr %cmp.addr
  %cr1168 = call ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1165, ptr %ld1166, ptr %ld1167)
  %$t1558.addr = alloca ptr
  store ptr %cr1168, ptr %$t1558.addr
  %ld1169 = load i64, ptr %run_len.addr
  %ar1170 = add i64 %ld1169, 1
  %$t1559.addr = alloca i64
  store i64 %ar1170, ptr %$t1559.addr
  %ld1171 = load ptr, ptr %$t1558.addr
  %ld1172 = load i64, ptr %$t1559.addr
  %ld1173 = load ptr, ptr %t.addr
  %ld1174 = load ptr, ptr %cmp.addr
  %cr1175 = call ptr @Sort.extend_run$List_V__4910$Int$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1171, i64 %ld1172, ptr %ld1173, ptr %ld1174)
  store ptr %cr1175, ptr %res_slot1138
  br label %case_merge246
case_default247:
  unreachable
case_merge246:
  %case_r1176 = load ptr, ptr %res_slot1138
  store ptr %case_r1176, ptr %res_slot1127
  br label %case_merge243
case_merge243:
  %case_r1177 = load ptr, ptr %res_slot1127
  ret ptr %case_r1177
}

define ptr @Sort.reverse_list$List_V__4971(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1178 = call ptr @march_alloc(i64 24)
  %tgp1179 = getelementptr i8, ptr %hp1178, i64 8
  store i32 0, ptr %tgp1179, align 4
  %fp1180 = getelementptr i8, ptr %hp1178, i64 16
  store ptr @go$apply$32, ptr %fp1180, align 8
  %go.addr = alloca ptr
  store ptr %hp1178, ptr %go.addr
  %hp1181 = call ptr @march_alloc(i64 16)
  %tgp1182 = getelementptr i8, ptr %hp1181, i64 8
  store i32 0, ptr %tgp1182, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp1181, ptr %$t1355.addr
  %ld1183 = load ptr, ptr %go.addr
  %fp1184 = getelementptr i8, ptr %ld1183, i64 16
  %fv1185 = load ptr, ptr %fp1184, align 8
  %ld1186 = load ptr, ptr %xs.addr
  %ld1187 = load ptr, ptr %$t1355.addr
  %cr1188 = call ptr (ptr, ptr, ptr) %fv1185(ptr %ld1183, ptr %ld1186, ptr %ld1187)
  ret ptr %cr1188
}

define i64 @Sort.cmp2$Fn_V__4971_Fn_V__4971_Bool$V__4971$V__4971(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1189 = load ptr, ptr %cmp.addr
  %fp1190 = getelementptr i8, ptr %ld1189, i64 16
  %fv1191 = load ptr, ptr %fp1190, align 8
  %ld1192 = load ptr, ptr %x.addr
  %cr1193 = call ptr (ptr, ptr) %fv1191(ptr %ld1189, ptr %ld1192)
  %f.addr = alloca ptr
  store ptr %cr1193, ptr %f.addr
  %ld1194 = load ptr, ptr %f.addr
  %fp1195 = getelementptr i8, ptr %ld1194, i64 16
  %fv1196 = load ptr, ptr %fp1195, align 8
  %ld1197 = load ptr, ptr %y.addr
  %cr1198 = call i64 (ptr, ptr) %fv1196(ptr %ld1194, ptr %ld1197)
  ret i64 %cr1198
}

define ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1199 = load ptr, ptr %xs.addr
  %res_slot1200 = alloca ptr
  %tgp1201 = getelementptr i8, ptr %ld1199, i64 8
  %tag1202 = load i32, ptr %tgp1201, align 4
  switch i32 %tag1202, label %case_default257 [
      i32 0, label %case_br258
      i32 1, label %case_br259
  ]
case_br258:
  %ld1203 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld1203)
  %ld1204 = load ptr, ptr %ys.addr
  store ptr %ld1204, ptr %res_slot1200
  br label %case_merge256
case_br259:
  %fp1205 = getelementptr i8, ptr %ld1199, i64 16
  %fv1206 = load ptr, ptr %fp1205, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv1206, ptr %$f1372.addr
  %fp1207 = getelementptr i8, ptr %ld1199, i64 24
  %fv1208 = load ptr, ptr %fp1207, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv1208, ptr %$f1373.addr
  %ld1209 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld1209, ptr %xt.addr
  %ld1210 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld1210, ptr %x.addr
  %ld1211 = load ptr, ptr %ys.addr
  %res_slot1212 = alloca ptr
  %tgp1213 = getelementptr i8, ptr %ld1211, i64 8
  %tag1214 = load i32, ptr %tgp1213, align 4
  switch i32 %tag1214, label %case_default261 [
      i32 0, label %case_br262
      i32 1, label %case_br263
  ]
case_br262:
  %ld1215 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld1215)
  %ld1216 = load ptr, ptr %xs.addr
  store ptr %ld1216, ptr %res_slot1212
  br label %case_merge260
case_br263:
  %fp1217 = getelementptr i8, ptr %ld1211, i64 16
  %fv1218 = load ptr, ptr %fp1217, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv1218, ptr %$f1370.addr
  %fp1219 = getelementptr i8, ptr %ld1211, i64 24
  %fv1220 = load ptr, ptr %fp1219, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv1220, ptr %$f1371.addr
  %ld1221 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld1221, ptr %yt.addr
  %ld1222 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld1222, ptr %y.addr
  %ld1223 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1223)
  %ld1224 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld1224)
  %ld1225 = load ptr, ptr %cmp.addr
  %ld1226 = load ptr, ptr %x.addr
  %ld1227 = load ptr, ptr %y.addr
  %cr1228 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld1225, ptr %ld1226, ptr %ld1227)
  %$t1367.addr = alloca i64
  store i64 %cr1228, ptr %$t1367.addr
  %ld1229 = load i64, ptr %$t1367.addr
  %res_slot1230 = alloca ptr
  %bi1231 = trunc i64 %ld1229 to i1
  br i1 %bi1231, label %case_br266, label %case_default265
case_br266:
  %ld1232 = load ptr, ptr %xt.addr
  %ld1233 = load ptr, ptr %ys.addr
  %ld1234 = load ptr, ptr %cmp.addr
  %cr1235 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1232, ptr %ld1233, ptr %ld1234)
  %$t1368.addr = alloca ptr
  store ptr %cr1235, ptr %$t1368.addr
  %hp1236 = call ptr @march_alloc(i64 32)
  %tgp1237 = getelementptr i8, ptr %hp1236, i64 8
  store i32 1, ptr %tgp1237, align 4
  %ld1238 = load ptr, ptr %x.addr
  %fp1239 = getelementptr i8, ptr %hp1236, i64 16
  store ptr %ld1238, ptr %fp1239, align 8
  %ld1240 = load ptr, ptr %$t1368.addr
  %fp1241 = getelementptr i8, ptr %hp1236, i64 24
  store ptr %ld1240, ptr %fp1241, align 8
  store ptr %hp1236, ptr %res_slot1230
  br label %case_merge264
case_default265:
  %ld1242 = load ptr, ptr %xs.addr
  %ld1243 = load ptr, ptr %yt.addr
  %ld1244 = load ptr, ptr %cmp.addr
  %cr1245 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1242, ptr %ld1243, ptr %ld1244)
  %$t1369.addr = alloca ptr
  store ptr %cr1245, ptr %$t1369.addr
  %hp1246 = call ptr @march_alloc(i64 32)
  %tgp1247 = getelementptr i8, ptr %hp1246, i64 8
  store i32 1, ptr %tgp1247, align 4
  %ld1248 = load ptr, ptr %y.addr
  %fp1249 = getelementptr i8, ptr %hp1246, i64 16
  store ptr %ld1248, ptr %fp1249, align 8
  %ld1250 = load ptr, ptr %$t1369.addr
  %fp1251 = getelementptr i8, ptr %hp1246, i64 24
  store ptr %ld1250, ptr %fp1251, align 8
  store ptr %hp1246, ptr %res_slot1230
  br label %case_merge264
case_merge264:
  %case_r1252 = load ptr, ptr %res_slot1230
  store ptr %case_r1252, ptr %res_slot1212
  br label %case_merge260
case_default261:
  unreachable
case_merge260:
  %case_r1253 = load ptr, ptr %res_slot1212
  store ptr %case_r1253, ptr %res_slot1200
  br label %case_merge256
case_default257:
  unreachable
case_merge256:
  %case_r1254 = load ptr, ptr %res_slot1200
  ret ptr %case_r1254
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
  %ld1255 = load i64, ptr %run_len.addr
  %cmp1256 = icmp sge i64 %ld1255, 16
  %ar1257 = zext i1 %cmp1256 to i64
  %$t1556.addr = alloca i64
  store i64 %ar1257, ptr %$t1556.addr
  %ld1258 = load i64, ptr %$t1556.addr
  %res_slot1259 = alloca ptr
  %bi1260 = trunc i64 %ld1258 to i1
  br i1 %bi1260, label %case_br269, label %case_default268
case_br269:
  %hp1261 = call ptr @march_alloc(i64 40)
  %tgp1262 = getelementptr i8, ptr %hp1261, i64 8
  store i32 0, ptr %tgp1262, align 4
  %ld1263 = load ptr, ptr %run.addr
  %fp1264 = getelementptr i8, ptr %hp1261, i64 16
  store ptr %ld1263, ptr %fp1264, align 8
  %ld1265 = load i64, ptr %run_len.addr
  %fp1266 = getelementptr i8, ptr %hp1261, i64 24
  store i64 %ld1265, ptr %fp1266, align 8
  %ld1267 = load ptr, ptr %rest.addr
  %fp1268 = getelementptr i8, ptr %hp1261, i64 32
  store ptr %ld1267, ptr %fp1268, align 8
  store ptr %hp1261, ptr %res_slot1259
  br label %case_merge267
case_default268:
  %ld1269 = load ptr, ptr %rest.addr
  %res_slot1270 = alloca ptr
  %tgp1271 = getelementptr i8, ptr %ld1269, i64 8
  %tag1272 = load i32, ptr %tgp1271, align 4
  switch i32 %tag1272, label %case_default271 [
      i32 0, label %case_br272
      i32 1, label %case_br273
  ]
case_br272:
  %ld1273 = load ptr, ptr %rest.addr
  %rc1274 = load i64, ptr %ld1273, align 8
  %uniq1275 = icmp eq i64 %rc1274, 1
  %fbip_slot1276 = alloca ptr
  br i1 %uniq1275, label %fbip_reuse274, label %fbip_fresh275
fbip_reuse274:
  %tgp1277 = getelementptr i8, ptr %ld1273, i64 8
  store i32 0, ptr %tgp1277, align 4
  store ptr %ld1273, ptr %fbip_slot1276
  br label %fbip_merge276
fbip_fresh275:
  call void @march_decrc(ptr %ld1273)
  %hp1278 = call ptr @march_alloc(i64 16)
  %tgp1279 = getelementptr i8, ptr %hp1278, i64 8
  store i32 0, ptr %tgp1279, align 4
  store ptr %hp1278, ptr %fbip_slot1276
  br label %fbip_merge276
fbip_merge276:
  %fbip_r1280 = load ptr, ptr %fbip_slot1276
  %$t1557.addr = alloca ptr
  store ptr %fbip_r1280, ptr %$t1557.addr
  %hp1281 = call ptr @march_alloc(i64 40)
  %tgp1282 = getelementptr i8, ptr %hp1281, i64 8
  store i32 0, ptr %tgp1282, align 4
  %ld1283 = load ptr, ptr %run.addr
  %fp1284 = getelementptr i8, ptr %hp1281, i64 16
  store ptr %ld1283, ptr %fp1284, align 8
  %ld1285 = load i64, ptr %run_len.addr
  %fp1286 = getelementptr i8, ptr %hp1281, i64 24
  store i64 %ld1285, ptr %fp1286, align 8
  %ld1287 = load ptr, ptr %$t1557.addr
  %fp1288 = getelementptr i8, ptr %hp1281, i64 32
  store ptr %ld1287, ptr %fp1288, align 8
  store ptr %hp1281, ptr %res_slot1270
  br label %case_merge270
case_br273:
  %fp1289 = getelementptr i8, ptr %ld1269, i64 16
  %fv1290 = load ptr, ptr %fp1289, align 8
  %$f1560.addr = alloca ptr
  store ptr %fv1290, ptr %$f1560.addr
  %fp1291 = getelementptr i8, ptr %ld1269, i64 24
  %fv1292 = load ptr, ptr %fp1291, align 8
  %$f1561.addr = alloca ptr
  store ptr %fv1292, ptr %$f1561.addr
  %freed1293 = call i64 @march_decrc_freed(ptr %ld1269)
  %freed_b1294 = icmp ne i64 %freed1293, 0
  br i1 %freed_b1294, label %br_unique277, label %br_shared278
br_shared278:
  call void @march_incrc(ptr %fv1292)
  call void @march_incrc(ptr %fv1290)
  br label %br_body279
br_unique277:
  br label %br_body279
br_body279:
  %ld1295 = load ptr, ptr %$f1561.addr
  %t.addr = alloca ptr
  store ptr %ld1295, ptr %t.addr
  %ld1296 = load ptr, ptr %$f1560.addr
  %h.addr = alloca ptr
  store ptr %ld1296, ptr %h.addr
  %ld1297 = load ptr, ptr %h.addr
  %ld1298 = load ptr, ptr %run.addr
  %ld1299 = load ptr, ptr %cmp.addr
  %cr1300 = call ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1297, ptr %ld1298, ptr %ld1299)
  %$t1558.addr = alloca ptr
  store ptr %cr1300, ptr %$t1558.addr
  %ld1301 = load i64, ptr %run_len.addr
  %ar1302 = add i64 %ld1301, 1
  %$t1559.addr = alloca i64
  store i64 %ar1302, ptr %$t1559.addr
  %ld1303 = load ptr, ptr %$t1558.addr
  %ld1304 = load i64, ptr %$t1559.addr
  %ld1305 = load ptr, ptr %t.addr
  %ld1306 = load ptr, ptr %cmp.addr
  %cr1307 = call ptr @Sort.extend_run$List_V__4910$Int$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %ld1303, i64 %ld1304, ptr %ld1305, ptr %ld1306)
  store ptr %cr1307, ptr %res_slot1270
  br label %case_merge270
case_default271:
  unreachable
case_merge270:
  %case_r1308 = load ptr, ptr %res_slot1270
  store ptr %case_r1308, ptr %res_slot1259
  br label %case_merge267
case_merge267:
  %case_r1309 = load ptr, ptr %res_slot1259
  ret ptr %case_r1309
}

define ptr @Sort.insert_sorted$V__4910$List_V__4910$Fn_V__4910_Fn_V__4910_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1310 = load ptr, ptr %sorted.addr
  %res_slot1311 = alloca ptr
  %tgp1312 = getelementptr i8, ptr %ld1310, i64 8
  %tag1313 = load i32, ptr %tgp1312, align 4
  switch i32 %tag1313, label %case_default281 [
      i32 0, label %case_br282
      i32 1, label %case_br283
  ]
case_br282:
  %ld1314 = load ptr, ptr %sorted.addr
  %rc1315 = load i64, ptr %ld1314, align 8
  %uniq1316 = icmp eq i64 %rc1315, 1
  %fbip_slot1317 = alloca ptr
  br i1 %uniq1316, label %fbip_reuse284, label %fbip_fresh285
fbip_reuse284:
  %tgp1318 = getelementptr i8, ptr %ld1314, i64 8
  store i32 0, ptr %tgp1318, align 4
  store ptr %ld1314, ptr %fbip_slot1317
  br label %fbip_merge286
fbip_fresh285:
  call void @march_decrc(ptr %ld1314)
  %hp1319 = call ptr @march_alloc(i64 16)
  %tgp1320 = getelementptr i8, ptr %hp1319, i64 8
  store i32 0, ptr %tgp1320, align 4
  store ptr %hp1319, ptr %fbip_slot1317
  br label %fbip_merge286
fbip_merge286:
  %fbip_r1321 = load ptr, ptr %fbip_slot1317
  %$t1547.addr = alloca ptr
  store ptr %fbip_r1321, ptr %$t1547.addr
  %hp1322 = call ptr @march_alloc(i64 32)
  %tgp1323 = getelementptr i8, ptr %hp1322, i64 8
  store i32 1, ptr %tgp1323, align 4
  %ld1324 = load ptr, ptr %x.addr
  %fp1325 = getelementptr i8, ptr %hp1322, i64 16
  store ptr %ld1324, ptr %fp1325, align 8
  %ld1326 = load ptr, ptr %$t1547.addr
  %fp1327 = getelementptr i8, ptr %hp1322, i64 24
  store ptr %ld1326, ptr %fp1327, align 8
  store ptr %hp1322, ptr %res_slot1311
  br label %case_merge280
case_br283:
  %fp1328 = getelementptr i8, ptr %ld1310, i64 16
  %fv1329 = load ptr, ptr %fp1328, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv1329, ptr %$f1550.addr
  %fp1330 = getelementptr i8, ptr %ld1310, i64 24
  %fv1331 = load ptr, ptr %fp1330, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv1331, ptr %$f1551.addr
  %ld1332 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld1332, ptr %t.addr
  %ld1333 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld1333, ptr %h.addr
  %ld1334 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1334)
  %ld1335 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1335)
  %ld1336 = load ptr, ptr %cmp.addr
  %ld1337 = load ptr, ptr %x.addr
  %ld1338 = load ptr, ptr %h.addr
  %cr1339 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld1336, ptr %ld1337, ptr %ld1338)
  %$t1548.addr = alloca i64
  store i64 %cr1339, ptr %$t1548.addr
  %ld1340 = load i64, ptr %$t1548.addr
  %res_slot1341 = alloca ptr
  %bi1342 = trunc i64 %ld1340 to i1
  br i1 %bi1342, label %case_br289, label %case_default288
case_br289:
  %hp1343 = call ptr @march_alloc(i64 32)
  %tgp1344 = getelementptr i8, ptr %hp1343, i64 8
  store i32 1, ptr %tgp1344, align 4
  %ld1345 = load ptr, ptr %x.addr
  %fp1346 = getelementptr i8, ptr %hp1343, i64 16
  store ptr %ld1345, ptr %fp1346, align 8
  %ld1347 = load ptr, ptr %sorted.addr
  %fp1348 = getelementptr i8, ptr %hp1343, i64 24
  store ptr %ld1347, ptr %fp1348, align 8
  store ptr %hp1343, ptr %res_slot1341
  br label %case_merge287
case_default288:
  %ld1349 = load ptr, ptr %x.addr
  %ld1350 = load ptr, ptr %t.addr
  %ld1351 = load ptr, ptr %cmp.addr
  %cr1352 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld1349, ptr %ld1350, ptr %ld1351)
  %$t1549.addr = alloca ptr
  store ptr %cr1352, ptr %$t1549.addr
  %hp1353 = call ptr @march_alloc(i64 32)
  %tgp1354 = getelementptr i8, ptr %hp1353, i64 8
  store i32 1, ptr %tgp1354, align 4
  %ld1355 = load ptr, ptr %h.addr
  %fp1356 = getelementptr i8, ptr %hp1353, i64 16
  store ptr %ld1355, ptr %fp1356, align 8
  %ld1357 = load ptr, ptr %$t1549.addr
  %fp1358 = getelementptr i8, ptr %hp1353, i64 24
  store ptr %ld1357, ptr %fp1358, align 8
  store ptr %hp1353, ptr %res_slot1341
  br label %case_merge287
case_merge287:
  %case_r1359 = load ptr, ptr %res_slot1341
  store ptr %case_r1359, ptr %res_slot1311
  br label %case_merge280
case_default281:
  unreachable
case_merge280:
  %case_r1360 = load ptr, ptr %res_slot1311
  ret ptr %case_r1360
}

define ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %xs.arg, ptr %ys.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1361 = load ptr, ptr %xs.addr
  %res_slot1362 = alloca ptr
  %tgp1363 = getelementptr i8, ptr %ld1361, i64 8
  %tag1364 = load i32, ptr %tgp1363, align 4
  switch i32 %tag1364, label %case_default291 [
      i32 0, label %case_br292
      i32 1, label %case_br293
  ]
case_br292:
  %ld1365 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld1365)
  %ld1366 = load ptr, ptr %ys.addr
  store ptr %ld1366, ptr %res_slot1362
  br label %case_merge290
case_br293:
  %fp1367 = getelementptr i8, ptr %ld1361, i64 16
  %fv1368 = load ptr, ptr %fp1367, align 8
  %$f1372.addr = alloca ptr
  store ptr %fv1368, ptr %$f1372.addr
  %fp1369 = getelementptr i8, ptr %ld1361, i64 24
  %fv1370 = load ptr, ptr %fp1369, align 8
  %$f1373.addr = alloca ptr
  store ptr %fv1370, ptr %$f1373.addr
  %ld1371 = load ptr, ptr %$f1373.addr
  %xt.addr = alloca ptr
  store ptr %ld1371, ptr %xt.addr
  %ld1372 = load ptr, ptr %$f1372.addr
  %x.addr = alloca ptr
  store ptr %ld1372, ptr %x.addr
  %ld1373 = load ptr, ptr %ys.addr
  %res_slot1374 = alloca ptr
  %tgp1375 = getelementptr i8, ptr %ld1373, i64 8
  %tag1376 = load i32, ptr %tgp1375, align 4
  switch i32 %tag1376, label %case_default295 [
      i32 0, label %case_br296
      i32 1, label %case_br297
  ]
case_br296:
  %ld1377 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld1377)
  %ld1378 = load ptr, ptr %xs.addr
  store ptr %ld1378, ptr %res_slot1374
  br label %case_merge294
case_br297:
  %fp1379 = getelementptr i8, ptr %ld1373, i64 16
  %fv1380 = load ptr, ptr %fp1379, align 8
  %$f1370.addr = alloca ptr
  store ptr %fv1380, ptr %$f1370.addr
  %fp1381 = getelementptr i8, ptr %ld1373, i64 24
  %fv1382 = load ptr, ptr %fp1381, align 8
  %$f1371.addr = alloca ptr
  store ptr %fv1382, ptr %$f1371.addr
  %ld1383 = load ptr, ptr %$f1371.addr
  %yt.addr = alloca ptr
  store ptr %ld1383, ptr %yt.addr
  %ld1384 = load ptr, ptr %$f1370.addr
  %y.addr = alloca ptr
  store ptr %ld1384, ptr %y.addr
  %ld1385 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1385)
  %ld1386 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld1386)
  %ld1387 = load ptr, ptr %cmp.addr
  %ld1388 = load ptr, ptr %x.addr
  %ld1389 = load ptr, ptr %y.addr
  %cr1390 = call i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %ld1387, ptr %ld1388, ptr %ld1389)
  %$t1367.addr = alloca i64
  store i64 %cr1390, ptr %$t1367.addr
  %ld1391 = load i64, ptr %$t1367.addr
  %res_slot1392 = alloca ptr
  %bi1393 = trunc i64 %ld1391 to i1
  br i1 %bi1393, label %case_br300, label %case_default299
case_br300:
  %ld1394 = load ptr, ptr %xt.addr
  %ld1395 = load ptr, ptr %ys.addr
  %ld1396 = load ptr, ptr %cmp.addr
  %cr1397 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1394, ptr %ld1395, ptr %ld1396)
  %$t1368.addr = alloca ptr
  store ptr %cr1397, ptr %$t1368.addr
  %hp1398 = call ptr @march_alloc(i64 32)
  %tgp1399 = getelementptr i8, ptr %hp1398, i64 8
  store i32 1, ptr %tgp1399, align 4
  %ld1400 = load ptr, ptr %x.addr
  %fp1401 = getelementptr i8, ptr %hp1398, i64 16
  store ptr %ld1400, ptr %fp1401, align 8
  %ld1402 = load ptr, ptr %$t1368.addr
  %fp1403 = getelementptr i8, ptr %hp1398, i64 24
  store ptr %ld1402, ptr %fp1403, align 8
  store ptr %hp1398, ptr %res_slot1392
  br label %case_merge298
case_default299:
  %ld1404 = load ptr, ptr %xs.addr
  %ld1405 = load ptr, ptr %yt.addr
  %ld1406 = load ptr, ptr %cmp.addr
  %cr1407 = call ptr @Sort.merge_sorted$List_V__4487$List_V__4487$Fn_V__4487_Fn_V__4487_Bool(ptr %ld1404, ptr %ld1405, ptr %ld1406)
  %$t1369.addr = alloca ptr
  store ptr %cr1407, ptr %$t1369.addr
  %hp1408 = call ptr @march_alloc(i64 32)
  %tgp1409 = getelementptr i8, ptr %hp1408, i64 8
  store i32 1, ptr %tgp1409, align 4
  %ld1410 = load ptr, ptr %y.addr
  %fp1411 = getelementptr i8, ptr %hp1408, i64 16
  store ptr %ld1410, ptr %fp1411, align 8
  %ld1412 = load ptr, ptr %$t1369.addr
  %fp1413 = getelementptr i8, ptr %hp1408, i64 24
  store ptr %ld1412, ptr %fp1413, align 8
  store ptr %hp1408, ptr %res_slot1392
  br label %case_merge298
case_merge298:
  %case_r1414 = load ptr, ptr %res_slot1392
  store ptr %case_r1414, ptr %res_slot1374
  br label %case_merge294
case_default295:
  unreachable
case_merge294:
  %case_r1415 = load ptr, ptr %res_slot1374
  store ptr %case_r1415, ptr %res_slot1362
  br label %case_merge290
case_default291:
  unreachable
case_merge290:
  %case_r1416 = load ptr, ptr %res_slot1362
  ret ptr %case_r1416
}

define i64 @Sort.cmp2$Fn_V__4487_Fn_V__4487_Bool$V__4487$V__4487(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1417 = load ptr, ptr %cmp.addr
  %fp1418 = getelementptr i8, ptr %ld1417, i64 16
  %fv1419 = load ptr, ptr %fp1418, align 8
  %ld1420 = load ptr, ptr %x.addr
  %cr1421 = call ptr (ptr, ptr) %fv1419(ptr %ld1417, ptr %ld1420)
  %f.addr = alloca ptr
  store ptr %cr1421, ptr %f.addr
  %ld1422 = load ptr, ptr %f.addr
  %fp1423 = getelementptr i8, ptr %ld1422, i64 16
  %fv1424 = load ptr, ptr %fp1423, align 8
  %ld1425 = load ptr, ptr %y.addr
  %cr1426 = call i64 (ptr, ptr) %fv1424(ptr %ld1422, ptr %ld1425)
  ret i64 %cr1426
}

define ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %x.arg, ptr %sorted.arg, ptr %cmp.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %sorted.addr = alloca ptr
  store ptr %sorted.arg, ptr %sorted.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld1427 = load ptr, ptr %sorted.addr
  %res_slot1428 = alloca ptr
  %tgp1429 = getelementptr i8, ptr %ld1427, i64 8
  %tag1430 = load i32, ptr %tgp1429, align 4
  switch i32 %tag1430, label %case_default302 [
      i32 0, label %case_br303
      i32 1, label %case_br304
  ]
case_br303:
  %ld1431 = load ptr, ptr %sorted.addr
  %rc1432 = load i64, ptr %ld1431, align 8
  %uniq1433 = icmp eq i64 %rc1432, 1
  %fbip_slot1434 = alloca ptr
  br i1 %uniq1433, label %fbip_reuse305, label %fbip_fresh306
fbip_reuse305:
  %tgp1435 = getelementptr i8, ptr %ld1431, i64 8
  store i32 0, ptr %tgp1435, align 4
  store ptr %ld1431, ptr %fbip_slot1434
  br label %fbip_merge307
fbip_fresh306:
  call void @march_decrc(ptr %ld1431)
  %hp1436 = call ptr @march_alloc(i64 16)
  %tgp1437 = getelementptr i8, ptr %hp1436, i64 8
  store i32 0, ptr %tgp1437, align 4
  store ptr %hp1436, ptr %fbip_slot1434
  br label %fbip_merge307
fbip_merge307:
  %fbip_r1438 = load ptr, ptr %fbip_slot1434
  %$t1547.addr = alloca ptr
  store ptr %fbip_r1438, ptr %$t1547.addr
  %hp1439 = call ptr @march_alloc(i64 32)
  %tgp1440 = getelementptr i8, ptr %hp1439, i64 8
  store i32 1, ptr %tgp1440, align 4
  %ld1441 = load ptr, ptr %x.addr
  %fp1442 = getelementptr i8, ptr %hp1439, i64 16
  store ptr %ld1441, ptr %fp1442, align 8
  %ld1443 = load ptr, ptr %$t1547.addr
  %fp1444 = getelementptr i8, ptr %hp1439, i64 24
  store ptr %ld1443, ptr %fp1444, align 8
  store ptr %hp1439, ptr %res_slot1428
  br label %case_merge301
case_br304:
  %fp1445 = getelementptr i8, ptr %ld1427, i64 16
  %fv1446 = load ptr, ptr %fp1445, align 8
  %$f1550.addr = alloca ptr
  store ptr %fv1446, ptr %$f1550.addr
  %fp1447 = getelementptr i8, ptr %ld1427, i64 24
  %fv1448 = load ptr, ptr %fp1447, align 8
  %$f1551.addr = alloca ptr
  store ptr %fv1448, ptr %$f1551.addr
  %ld1449 = load ptr, ptr %$f1551.addr
  %t.addr = alloca ptr
  store ptr %ld1449, ptr %t.addr
  %ld1450 = load ptr, ptr %$f1550.addr
  %h.addr = alloca ptr
  store ptr %ld1450, ptr %h.addr
  %ld1451 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld1451)
  %ld1452 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1452)
  %ld1453 = load ptr, ptr %cmp.addr
  %ld1454 = load ptr, ptr %x.addr
  %ld1455 = load ptr, ptr %h.addr
  %cr1456 = call i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %ld1453, ptr %ld1454, ptr %ld1455)
  %$t1548.addr = alloca i64
  store i64 %cr1456, ptr %$t1548.addr
  %ld1457 = load i64, ptr %$t1548.addr
  %res_slot1458 = alloca ptr
  %bi1459 = trunc i64 %ld1457 to i1
  br i1 %bi1459, label %case_br310, label %case_default309
case_br310:
  %hp1460 = call ptr @march_alloc(i64 32)
  %tgp1461 = getelementptr i8, ptr %hp1460, i64 8
  store i32 1, ptr %tgp1461, align 4
  %ld1462 = load ptr, ptr %x.addr
  %fp1463 = getelementptr i8, ptr %hp1460, i64 16
  store ptr %ld1462, ptr %fp1463, align 8
  %ld1464 = load ptr, ptr %sorted.addr
  %fp1465 = getelementptr i8, ptr %hp1460, i64 24
  store ptr %ld1464, ptr %fp1465, align 8
  store ptr %hp1460, ptr %res_slot1458
  br label %case_merge308
case_default309:
  %ld1466 = load ptr, ptr %x.addr
  %ld1467 = load ptr, ptr %t.addr
  %ld1468 = load ptr, ptr %cmp.addr
  %cr1469 = call ptr @Sort.insert_sorted$V__4883$List_V__4883$Fn_V__4883_Fn_V__4883_Bool(ptr %ld1466, ptr %ld1467, ptr %ld1468)
  %$t1549.addr = alloca ptr
  store ptr %cr1469, ptr %$t1549.addr
  %hp1470 = call ptr @march_alloc(i64 32)
  %tgp1471 = getelementptr i8, ptr %hp1470, i64 8
  store i32 1, ptr %tgp1471, align 4
  %ld1472 = load ptr, ptr %h.addr
  %fp1473 = getelementptr i8, ptr %hp1470, i64 16
  store ptr %ld1472, ptr %fp1473, align 8
  %ld1474 = load ptr, ptr %$t1549.addr
  %fp1475 = getelementptr i8, ptr %hp1470, i64 24
  store ptr %ld1474, ptr %fp1475, align 8
  store ptr %hp1470, ptr %res_slot1458
  br label %case_merge308
case_merge308:
  %case_r1476 = load ptr, ptr %res_slot1458
  store ptr %case_r1476, ptr %res_slot1428
  br label %case_merge301
case_default302:
  unreachable
case_merge301:
  %case_r1477 = load ptr, ptr %res_slot1428
  ret ptr %case_r1477
}

define i64 @Sort.cmp2$Fn_V__4883_Fn_V__4883_Bool$V__4883$V__4883(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1478 = load ptr, ptr %cmp.addr
  %fp1479 = getelementptr i8, ptr %ld1478, i64 16
  %fv1480 = load ptr, ptr %fp1479, align 8
  %ld1481 = load ptr, ptr %x.addr
  %cr1482 = call ptr (ptr, ptr) %fv1480(ptr %ld1478, ptr %ld1481)
  %f.addr = alloca ptr
  store ptr %cr1482, ptr %f.addr
  %ld1483 = load ptr, ptr %f.addr
  %fp1484 = getelementptr i8, ptr %ld1483, i64 16
  %fv1485 = load ptr, ptr %fp1484, align 8
  %ld1486 = load ptr, ptr %y.addr
  %cr1487 = call i64 (ptr, ptr) %fv1485(ptr %ld1483, ptr %ld1486)
  ret i64 %cr1487
}

define ptr @$lam2018$apply$21(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp1488 = call ptr @march_alloc(i64 32)
  %tgp1489 = getelementptr i8, ptr %hp1488, i64 8
  store i32 0, ptr %tgp1489, align 4
  %fp1490 = getelementptr i8, ptr %hp1488, i64 16
  store ptr @$lam2019$apply$22, ptr %fp1490, align 8
  %ld1491 = load ptr, ptr %x.addr
  %fp1492 = getelementptr i8, ptr %hp1488, i64 24
  store ptr %ld1491, ptr %fp1492, align 8
  ret ptr %hp1488
}

define i64 @$lam2019$apply$22(ptr %$clo.arg, ptr %y.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld1493 = load ptr, ptr %$clo.addr
  %fp1494 = getelementptr i8, ptr %ld1493, i64 24
  %fv1495 = load ptr, ptr %fp1494, align 8
  %x.addr = alloca ptr
  store ptr %fv1495, ptr %x.addr
  %ld1496 = load ptr, ptr %x.addr
  %ld1497 = load ptr, ptr %y.addr
  %cv1500 = ptrtoint ptr %ld1496 to i64
  %cv1501 = ptrtoint ptr %ld1497 to i64
  %cmp1498 = icmp sle i64 %cv1500, %cv1501
  %ar1499 = zext i1 %cmp1498 to i64
  ret i64 %ar1499
}

define ptr @process$apply$25(ptr %$clo.arg, ptr %run_list.arg, ptr %stack.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %run_list.addr = alloca ptr
  store ptr %run_list.arg, ptr %run_list.addr
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld1502 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1502)
  %ld1503 = load ptr, ptr %$clo.addr
  %process.addr = alloca ptr
  store ptr %ld1503, ptr %process.addr
  %ld1504 = load ptr, ptr %$clo.addr
  %fp1505 = getelementptr i8, ptr %ld1504, i64 24
  %fv1506 = load ptr, ptr %fp1505, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1506, ptr %cmp.addr
  %ld1507 = load ptr, ptr %run_list.addr
  %res_slot1508 = alloca ptr
  %tgp1509 = getelementptr i8, ptr %ld1507, i64 8
  %tag1510 = load i32, ptr %tgp1509, align 4
  switch i32 %tag1510, label %case_default312 [
      i32 0, label %case_br313
      i32 1, label %case_br314
  ]
case_br313:
  %ld1511 = load ptr, ptr %run_list.addr
  call void @march_decrc(ptr %ld1511)
  %ld1512 = load ptr, ptr %stack.addr
  store ptr %ld1512, ptr %res_slot1508
  br label %case_merge311
case_br314:
  %fp1513 = getelementptr i8, ptr %ld1507, i64 16
  %fv1514 = load ptr, ptr %fp1513, align 8
  %$f1623.addr = alloca ptr
  store ptr %fv1514, ptr %$f1623.addr
  %fp1515 = getelementptr i8, ptr %ld1507, i64 24
  %fv1516 = load ptr, ptr %fp1515, align 8
  %$f1624.addr = alloca ptr
  store ptr %fv1516, ptr %$f1624.addr
  %freed1517 = call i64 @march_decrc_freed(ptr %ld1507)
  %freed_b1518 = icmp ne i64 %freed1517, 0
  br i1 %freed_b1518, label %br_unique315, label %br_shared316
br_shared316:
  call void @march_incrc(ptr %fv1516)
  call void @march_incrc(ptr %fv1514)
  br label %br_body317
br_unique315:
  br label %br_body317
br_body317:
  %ld1519 = load ptr, ptr %$f1624.addr
  %rest.addr = alloca ptr
  store ptr %ld1519, ptr %rest.addr
  %ld1520 = load ptr, ptr %$f1623.addr
  %run.addr = alloca ptr
  store ptr %ld1520, ptr %run.addr
  %hp1521 = call ptr @march_alloc(i64 32)
  %tgp1522 = getelementptr i8, ptr %hp1521, i64 8
  store i32 1, ptr %tgp1522, align 4
  %ld1523 = load ptr, ptr %run.addr
  %fp1524 = getelementptr i8, ptr %hp1521, i64 16
  store ptr %ld1523, ptr %fp1524, align 8
  %ld1525 = load ptr, ptr %stack.addr
  %fp1526 = getelementptr i8, ptr %hp1521, i64 24
  store ptr %ld1525, ptr %fp1526, align 8
  %$t1622.addr = alloca ptr
  store ptr %hp1521, ptr %$t1622.addr
  %ld1527 = load ptr, ptr %$t1622.addr
  %ld1528 = load ptr, ptr %cmp.addr
  %cr1529 = call ptr @Sort.enforce_invariants$List_T_List_V__5074_Int$Fn_V__5074_Fn_V__5074_Bool(ptr %ld1527, ptr %ld1528)
  %new_stack.addr = alloca ptr
  store ptr %cr1529, ptr %new_stack.addr
  %ld1530 = load ptr, ptr %process.addr
  %fp1531 = getelementptr i8, ptr %ld1530, i64 16
  %fv1532 = load ptr, ptr %fp1531, align 8
  %ld1533 = load ptr, ptr %rest.addr
  %ld1534 = load ptr, ptr %new_stack.addr
  %cr1535 = call ptr (ptr, ptr, ptr) %fv1532(ptr %ld1530, ptr %ld1533, ptr %ld1534)
  store ptr %cr1535, ptr %res_slot1508
  br label %case_merge311
case_default312:
  unreachable
case_merge311:
  %case_r1536 = load ptr, ptr %res_slot1508
  ret ptr %case_r1536
}

define ptr @go$apply$27(ptr %$clo.arg, ptr %stk.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %stk.addr = alloca ptr
  store ptr %stk.arg, ptr %stk.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1537 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1537)
  %ld1538 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1538, ptr %go.addr
  %ld1539 = load ptr, ptr %$clo.addr
  %fp1540 = getelementptr i8, ptr %ld1539, i64 24
  %fv1541 = load ptr, ptr %fp1540, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1541, ptr %cmp.addr
  %ld1542 = load ptr, ptr %stk.addr
  %res_slot1543 = alloca ptr
  %tgp1544 = getelementptr i8, ptr %ld1542, i64 8
  %tag1545 = load i32, ptr %tgp1544, align 4
  switch i32 %tag1545, label %case_default319 [
      i32 0, label %case_br320
      i32 1, label %case_br321
  ]
case_br320:
  %ld1546 = load ptr, ptr %stk.addr
  call void @march_decrc(ptr %ld1546)
  %ld1547 = load ptr, ptr %acc.addr
  store ptr %ld1547, ptr %res_slot1543
  br label %case_merge318
case_br321:
  %fp1548 = getelementptr i8, ptr %ld1542, i64 16
  %fv1549 = load ptr, ptr %fp1548, align 8
  %$f1614.addr = alloca ptr
  store ptr %fv1549, ptr %$f1614.addr
  %fp1550 = getelementptr i8, ptr %ld1542, i64 24
  %fv1551 = load ptr, ptr %fp1550, align 8
  %$f1615.addr = alloca ptr
  store ptr %fv1551, ptr %$f1615.addr
  %freed1552 = call i64 @march_decrc_freed(ptr %ld1542)
  %freed_b1553 = icmp ne i64 %freed1552, 0
  br i1 %freed_b1553, label %br_unique322, label %br_shared323
br_shared323:
  call void @march_incrc(ptr %fv1551)
  call void @march_incrc(ptr %fv1549)
  br label %br_body324
br_unique322:
  br label %br_body324
br_body324:
  %ld1554 = load ptr, ptr %$f1614.addr
  %res_slot1555 = alloca ptr
  %tgp1556 = getelementptr i8, ptr %ld1554, i64 8
  %tag1557 = load i32, ptr %tgp1556, align 4
  switch i32 %tag1557, label %case_default326 [
      i32 0, label %case_br327
  ]
case_br327:
  %fp1558 = getelementptr i8, ptr %ld1554, i64 16
  %fv1559 = load ptr, ptr %fp1558, align 8
  %$f1616.addr = alloca ptr
  store ptr %fv1559, ptr %$f1616.addr
  %fp1560 = getelementptr i8, ptr %ld1554, i64 24
  %fv1561 = load ptr, ptr %fp1560, align 8
  %$f1617.addr = alloca ptr
  store ptr %fv1561, ptr %$f1617.addr
  %freed1562 = call i64 @march_decrc_freed(ptr %ld1554)
  %freed_b1563 = icmp ne i64 %freed1562, 0
  br i1 %freed_b1563, label %br_unique328, label %br_shared329
br_shared329:
  call void @march_incrc(ptr %fv1561)
  call void @march_incrc(ptr %fv1559)
  br label %br_body330
br_unique328:
  br label %br_body330
br_body330:
  %ld1564 = load ptr, ptr %$f1615.addr
  %rest.addr = alloca ptr
  store ptr %ld1564, ptr %rest.addr
  %ld1565 = load ptr, ptr %$f1616.addr
  %run.addr = alloca ptr
  store ptr %ld1565, ptr %run.addr
  %ld1566 = load ptr, ptr %acc.addr
  %a_i60.addr = alloca ptr
  store ptr %ld1566, ptr %a_i60.addr
  %ld1567 = load ptr, ptr %run.addr
  %b_i61.addr = alloca ptr
  store ptr %ld1567, ptr %b_i61.addr
  %ld1568 = load ptr, ptr %cmp.addr
  %cmp_i62.addr = alloca ptr
  store ptr %ld1568, ptr %cmp_i62.addr
  %ld1569 = load ptr, ptr %a_i60.addr
  %ld1570 = load ptr, ptr %b_i61.addr
  %ld1571 = load ptr, ptr %cmp_i62.addr
  %cr1572 = call ptr @Sort.merge_sorted$List_V__4975$List_V__4975$Fn_V__4975_Fn_V__4975_Bool(ptr %ld1569, ptr %ld1570, ptr %ld1571)
  %$t1613.addr = alloca ptr
  store ptr %cr1572, ptr %$t1613.addr
  %ld1573 = load ptr, ptr %go.addr
  %fp1574 = getelementptr i8, ptr %ld1573, i64 16
  %fv1575 = load ptr, ptr %fp1574, align 8
  %ld1576 = load ptr, ptr %rest.addr
  %ld1577 = load ptr, ptr %$t1613.addr
  %cr1578 = call ptr (ptr, ptr, ptr) %fv1575(ptr %ld1573, ptr %ld1576, ptr %ld1577)
  store ptr %cr1578, ptr %res_slot1555
  br label %case_merge325
case_default326:
  unreachable
case_merge325:
  %case_r1579 = load ptr, ptr %res_slot1555
  store ptr %case_r1579, ptr %res_slot1543
  br label %case_merge318
case_default319:
  unreachable
case_merge318:
  %case_r1580 = load ptr, ptr %res_slot1543
  ret ptr %case_r1580
}

define ptr @scan_run$apply$28(ptr %$clo.arg, ptr %lst.arg, ptr %run.arg, i64 %run_len.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %ld1581 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1581)
  %ld1582 = load ptr, ptr %$clo.addr
  %scan_run.addr = alloca ptr
  store ptr %ld1582, ptr %scan_run.addr
  %ld1583 = load ptr, ptr %$clo.addr
  %fp1584 = getelementptr i8, ptr %ld1583, i64 24
  %fv1585 = load ptr, ptr %fp1584, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1585, ptr %cmp.addr
  %ld1586 = load ptr, ptr %lst.addr
  %res_slot1587 = alloca ptr
  %tgp1588 = getelementptr i8, ptr %ld1586, i64 8
  %tag1589 = load i32, ptr %tgp1588, align 4
  switch i32 %tag1589, label %case_default332 [
      i32 0, label %case_br333
      i32 1, label %case_br334
  ]
case_br333:
  %ld1590 = load ptr, ptr %run.addr
  %cr1591 = call ptr @Sort.reverse_list$List_V__4971(ptr %ld1590)
  %$t1562.addr = alloca ptr
  store ptr %cr1591, ptr %$t1562.addr
  %ld1592 = load ptr, ptr %lst.addr
  %rc1593 = load i64, ptr %ld1592, align 8
  %uniq1594 = icmp eq i64 %rc1593, 1
  %fbip_slot1595 = alloca ptr
  br i1 %uniq1594, label %fbip_reuse335, label %fbip_fresh336
fbip_reuse335:
  %tgp1596 = getelementptr i8, ptr %ld1592, i64 8
  store i32 0, ptr %tgp1596, align 4
  store ptr %ld1592, ptr %fbip_slot1595
  br label %fbip_merge337
fbip_fresh336:
  call void @march_decrc(ptr %ld1592)
  %hp1597 = call ptr @march_alloc(i64 16)
  %tgp1598 = getelementptr i8, ptr %hp1597, i64 8
  store i32 0, ptr %tgp1598, align 4
  store ptr %hp1597, ptr %fbip_slot1595
  br label %fbip_merge337
fbip_merge337:
  %fbip_r1599 = load ptr, ptr %fbip_slot1595
  %$t1563.addr = alloca ptr
  store ptr %fbip_r1599, ptr %$t1563.addr
  %hp1600 = call ptr @march_alloc(i64 40)
  %tgp1601 = getelementptr i8, ptr %hp1600, i64 8
  store i32 0, ptr %tgp1601, align 4
  %ld1602 = load ptr, ptr %$t1562.addr
  %fp1603 = getelementptr i8, ptr %hp1600, i64 16
  store ptr %ld1602, ptr %fp1603, align 8
  %ld1604 = load i64, ptr %run_len.addr
  %fp1605 = getelementptr i8, ptr %hp1600, i64 24
  store i64 %ld1604, ptr %fp1605, align 8
  %ld1606 = load ptr, ptr %$t1563.addr
  %fp1607 = getelementptr i8, ptr %hp1600, i64 32
  store ptr %ld1606, ptr %fp1607, align 8
  store ptr %hp1600, ptr %res_slot1587
  br label %case_merge331
case_br334:
  %fp1608 = getelementptr i8, ptr %ld1586, i64 16
  %fv1609 = load ptr, ptr %fp1608, align 8
  %$f1572.addr = alloca ptr
  store ptr %fv1609, ptr %$f1572.addr
  %fp1610 = getelementptr i8, ptr %ld1586, i64 24
  %fv1611 = load ptr, ptr %fp1610, align 8
  %$f1573.addr = alloca ptr
  store ptr %fv1611, ptr %$f1573.addr
  %ld1612 = load ptr, ptr %$f1573.addr
  %t.addr = alloca ptr
  store ptr %ld1612, ptr %t.addr
  %ld1613 = load ptr, ptr %$f1572.addr
  %h.addr = alloca ptr
  store ptr %ld1613, ptr %h.addr
  %ld1614 = load ptr, ptr %run.addr
  %res_slot1615 = alloca ptr
  %tgp1616 = getelementptr i8, ptr %ld1614, i64 8
  %tag1617 = load i32, ptr %tgp1616, align 4
  switch i32 %tag1617, label %case_default339 [
      i32 0, label %case_br340
      i32 1, label %case_br341
  ]
case_br340:
  %ld1618 = load ptr, ptr %run.addr
  call void @march_decrc(ptr %ld1618)
  %hp1619 = call ptr @march_alloc(i64 16)
  %tgp1620 = getelementptr i8, ptr %hp1619, i64 8
  store i32 0, ptr %tgp1620, align 4
  %$t1564.addr = alloca ptr
  store ptr %hp1619, ptr %$t1564.addr
  %hp1621 = call ptr @march_alloc(i64 32)
  %tgp1622 = getelementptr i8, ptr %hp1621, i64 8
  store i32 1, ptr %tgp1622, align 4
  %ld1623 = load ptr, ptr %h.addr
  %fp1624 = getelementptr i8, ptr %hp1621, i64 16
  store ptr %ld1623, ptr %fp1624, align 8
  %ld1625 = load ptr, ptr %$t1564.addr
  %fp1626 = getelementptr i8, ptr %hp1621, i64 24
  store ptr %ld1625, ptr %fp1626, align 8
  %$t1565.addr = alloca ptr
  store ptr %hp1621, ptr %$t1565.addr
  %ld1627 = load ptr, ptr %scan_run.addr
  %fp1628 = getelementptr i8, ptr %ld1627, i64 16
  %fv1629 = load ptr, ptr %fp1628, align 8
  %ld1630 = load ptr, ptr %t.addr
  %ld1631 = load ptr, ptr %$t1565.addr
  %cr1632 = call ptr (ptr, ptr, ptr, i64) %fv1629(ptr %ld1627, ptr %ld1630, ptr %ld1631, i64 1)
  store ptr %cr1632, ptr %res_slot1615
  br label %case_merge338
case_br341:
  %fp1633 = getelementptr i8, ptr %ld1614, i64 16
  %fv1634 = load ptr, ptr %fp1633, align 8
  %$f1570.addr = alloca ptr
  store ptr %fv1634, ptr %$f1570.addr
  %fp1635 = getelementptr i8, ptr %ld1614, i64 24
  %fv1636 = load ptr, ptr %fp1635, align 8
  %$f1571.addr = alloca ptr
  store ptr %fv1636, ptr %$f1571.addr
  %ld1637 = load ptr, ptr %$f1570.addr
  %prev.addr = alloca ptr
  store ptr %ld1637, ptr %prev.addr
  %ld1638 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld1638)
  %ld1639 = load ptr, ptr %cmp.addr
  %ld1640 = load ptr, ptr %prev.addr
  %ld1641 = load ptr, ptr %h.addr
  %cr1642 = call i64 @Sort.cmp2$Fn_V__4971_Fn_V__4971_Bool$V__4971$V__4971(ptr %ld1639, ptr %ld1640, ptr %ld1641)
  %$t1566.addr = alloca i64
  store i64 %cr1642, ptr %$t1566.addr
  %ld1643 = load i64, ptr %$t1566.addr
  %res_slot1644 = alloca ptr
  %bi1645 = trunc i64 %ld1643 to i1
  br i1 %bi1645, label %case_br344, label %case_default343
case_br344:
  %hp1646 = call ptr @march_alloc(i64 32)
  %tgp1647 = getelementptr i8, ptr %hp1646, i64 8
  store i32 1, ptr %tgp1647, align 4
  %ld1648 = load ptr, ptr %h.addr
  %fp1649 = getelementptr i8, ptr %hp1646, i64 16
  store ptr %ld1648, ptr %fp1649, align 8
  %ld1650 = load ptr, ptr %run.addr
  %fp1651 = getelementptr i8, ptr %hp1646, i64 24
  store ptr %ld1650, ptr %fp1651, align 8
  %$t1567.addr = alloca ptr
  store ptr %hp1646, ptr %$t1567.addr
  %ld1652 = load i64, ptr %run_len.addr
  %ar1653 = add i64 %ld1652, 1
  %$t1568.addr = alloca i64
  store i64 %ar1653, ptr %$t1568.addr
  %ld1654 = load ptr, ptr %scan_run.addr
  %fp1655 = getelementptr i8, ptr %ld1654, i64 16
  %fv1656 = load ptr, ptr %fp1655, align 8
  %ld1657 = load ptr, ptr %t.addr
  %ld1658 = load ptr, ptr %$t1567.addr
  %ld1659 = load i64, ptr %$t1568.addr
  %cr1660 = call ptr (ptr, ptr, ptr, i64) %fv1656(ptr %ld1654, ptr %ld1657, ptr %ld1658, i64 %ld1659)
  store ptr %cr1660, ptr %res_slot1644
  br label %case_merge342
case_default343:
  %ld1661 = load ptr, ptr %run.addr
  %cr1662 = call ptr @Sort.reverse_list$List_V__4971(ptr %ld1661)
  %$t1569.addr = alloca ptr
  store ptr %cr1662, ptr %$t1569.addr
  %hp1663 = call ptr @march_alloc(i64 40)
  %tgp1664 = getelementptr i8, ptr %hp1663, i64 8
  store i32 0, ptr %tgp1664, align 4
  %ld1665 = load ptr, ptr %$t1569.addr
  %fp1666 = getelementptr i8, ptr %hp1663, i64 16
  store ptr %ld1665, ptr %fp1666, align 8
  %ld1667 = load i64, ptr %run_len.addr
  %fp1668 = getelementptr i8, ptr %hp1663, i64 24
  store i64 %ld1667, ptr %fp1668, align 8
  %ld1669 = load ptr, ptr %lst.addr
  %fp1670 = getelementptr i8, ptr %hp1663, i64 32
  store ptr %ld1669, ptr %fp1670, align 8
  store ptr %hp1663, ptr %res_slot1644
  br label %case_merge342
case_merge342:
  %case_r1671 = load ptr, ptr %res_slot1644
  store ptr %case_r1671, ptr %res_slot1615
  br label %case_merge338
case_default339:
  unreachable
case_merge338:
  %case_r1672 = load ptr, ptr %res_slot1615
  store ptr %case_r1672, ptr %res_slot1587
  br label %case_merge331
case_default332:
  unreachable
case_merge331:
  %case_r1673 = load ptr, ptr %res_slot1587
  ret ptr %case_r1673
}

define ptr @collect$apply$29(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1674 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1674)
  %ld1675 = load ptr, ptr %$clo.addr
  %collect.addr = alloca ptr
  store ptr %ld1675, ptr %collect.addr
  %ld1676 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld1676)
  %ld1677 = load ptr, ptr %$clo.addr
  %fp1678 = getelementptr i8, ptr %ld1677, i64 24
  %fv1679 = load ptr, ptr %fp1678, align 8
  %cmp.addr = alloca ptr
  store ptr %fv1679, ptr %cmp.addr
  %ld1680 = load ptr, ptr %$clo.addr
  %fp1681 = getelementptr i8, ptr %ld1680, i64 32
  %fv1682 = load ptr, ptr %fp1681, align 8
  %scan_run.addr = alloca ptr
  store ptr %fv1682, ptr %scan_run.addr
  %ld1683 = load ptr, ptr %lst.addr
  %res_slot1684 = alloca ptr
  %tgp1685 = getelementptr i8, ptr %ld1683, i64 8
  %tag1686 = load i32, ptr %tgp1685, align 4
  switch i32 %tag1686, label %case_default346 [
      i32 0, label %case_br347
  ]
case_br347:
  %ld1687 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1687)
  %ld1688 = load ptr, ptr %acc.addr
  %cr1689 = call ptr @Sort.reverse_list$List_T_List_V__4971_Int(ptr %ld1688)
  store ptr %cr1689, ptr %res_slot1684
  br label %case_merge345
case_default346:
  %hp1690 = call ptr @march_alloc(i64 16)
  %tgp1691 = getelementptr i8, ptr %hp1690, i64 8
  store i32 0, ptr %tgp1691, align 4
  %$t1574.addr = alloca ptr
  store ptr %hp1690, ptr %$t1574.addr
  %ld1692 = load ptr, ptr %scan_run.addr
  %fp1693 = getelementptr i8, ptr %ld1692, i64 16
  %fv1694 = load ptr, ptr %fp1693, align 8
  %ld1695 = load ptr, ptr %lst.addr
  %ld1696 = load ptr, ptr %$t1574.addr
  %cr1697 = call ptr (ptr, ptr, ptr, i64) %fv1694(ptr %ld1692, ptr %ld1695, ptr %ld1696, i64 0)
  %$p1578.addr = alloca ptr
  store ptr %cr1697, ptr %$p1578.addr
  %ld1698 = load ptr, ptr %$p1578.addr
  %fp1699 = getelementptr i8, ptr %ld1698, i64 16
  %fv1700 = load ptr, ptr %fp1699, align 8
  %run.addr = alloca ptr
  store ptr %fv1700, ptr %run.addr
  %ld1701 = load ptr, ptr %$p1578.addr
  %fp1702 = getelementptr i8, ptr %ld1701, i64 24
  %fv1703 = load ptr, ptr %fp1702, align 8
  %n.addr = alloca ptr
  store ptr %fv1703, ptr %n.addr
  %ld1704 = load ptr, ptr %$p1578.addr
  %fp1705 = getelementptr i8, ptr %ld1704, i64 32
  %fv1706 = load ptr, ptr %fp1705, align 8
  %rest.addr = alloca ptr
  store ptr %fv1706, ptr %rest.addr
  %ld1707 = load ptr, ptr %run.addr
  %ld1708 = load i64, ptr %n.addr
  %ld1709 = load ptr, ptr %rest.addr
  %ld1710 = load ptr, ptr %cmp.addr
  %cr1711 = call ptr @Sort.extend_run$List_V__4971$Int$List_V__4971$Fn_V__4971_Fn_V__4971_Bool(ptr %ld1707, i64 %ld1708, ptr %ld1709, ptr %ld1710)
  %$p1577.addr = alloca ptr
  store ptr %cr1711, ptr %$p1577.addr
  %ld1712 = load ptr, ptr %$p1577.addr
  %fp1713 = getelementptr i8, ptr %ld1712, i64 16
  %fv1714 = load ptr, ptr %fp1713, align 8
  %ext_run.addr = alloca ptr
  store ptr %fv1714, ptr %ext_run.addr
  %ld1715 = load ptr, ptr %$p1577.addr
  %fp1716 = getelementptr i8, ptr %ld1715, i64 24
  %fv1717 = load ptr, ptr %fp1716, align 8
  %ext_n.addr = alloca ptr
  store ptr %fv1717, ptr %ext_n.addr
  %ld1718 = load ptr, ptr %$p1577.addr
  %fp1719 = getelementptr i8, ptr %ld1718, i64 32
  %fv1720 = load ptr, ptr %fp1719, align 8
  %remaining.addr = alloca ptr
  store ptr %fv1720, ptr %remaining.addr
  %hp1721 = call ptr @march_alloc(i64 32)
  %tgp1722 = getelementptr i8, ptr %hp1721, i64 8
  store i32 0, ptr %tgp1722, align 4
  %ld1723 = load ptr, ptr %ext_run.addr
  %fp1724 = getelementptr i8, ptr %hp1721, i64 16
  store ptr %ld1723, ptr %fp1724, align 8
  %ld1725 = load i64, ptr %ext_n.addr
  %fp1726 = getelementptr i8, ptr %hp1721, i64 24
  store i64 %ld1725, ptr %fp1726, align 8
  %$t1575.addr = alloca ptr
  store ptr %hp1721, ptr %$t1575.addr
  %hp1727 = call ptr @march_alloc(i64 32)
  %tgp1728 = getelementptr i8, ptr %hp1727, i64 8
  store i32 1, ptr %tgp1728, align 4
  %ld1729 = load ptr, ptr %$t1575.addr
  %fp1730 = getelementptr i8, ptr %hp1727, i64 16
  store ptr %ld1729, ptr %fp1730, align 8
  %ld1731 = load ptr, ptr %acc.addr
  %fp1732 = getelementptr i8, ptr %hp1727, i64 24
  store ptr %ld1731, ptr %fp1732, align 8
  %$t1576.addr = alloca ptr
  store ptr %hp1727, ptr %$t1576.addr
  %ld1733 = load ptr, ptr %collect.addr
  %fp1734 = getelementptr i8, ptr %ld1733, i64 16
  %fv1735 = load ptr, ptr %fp1734, align 8
  %ld1736 = load ptr, ptr %remaining.addr
  %ld1737 = load ptr, ptr %$t1576.addr
  %cr1738 = call ptr (ptr, ptr, ptr) %fv1735(ptr %ld1733, ptr %ld1736, ptr %ld1737)
  store ptr %cr1738, ptr %res_slot1684
  br label %case_merge345
case_merge345:
  %case_r1739 = load ptr, ptr %res_slot1684
  ret ptr %case_r1739
}

define ptr @go$apply$30(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1740 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1740, ptr %go.addr
  %ld1741 = load ptr, ptr %lst.addr
  %res_slot1742 = alloca ptr
  %tgp1743 = getelementptr i8, ptr %ld1741, i64 8
  %tag1744 = load i32, ptr %tgp1743, align 4
  switch i32 %tag1744, label %case_default349 [
      i32 0, label %case_br350
      i32 1, label %case_br351
  ]
case_br350:
  %ld1745 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1745)
  %ld1746 = load ptr, ptr %acc.addr
  store ptr %ld1746, ptr %res_slot1742
  br label %case_merge348
case_br351:
  %fp1747 = getelementptr i8, ptr %ld1741, i64 16
  %fv1748 = load ptr, ptr %fp1747, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv1748, ptr %$f1353.addr
  %fp1749 = getelementptr i8, ptr %ld1741, i64 24
  %fv1750 = load ptr, ptr %fp1749, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv1750, ptr %$f1354.addr
  %ld1751 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld1751, ptr %t.addr
  %ld1752 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld1752, ptr %h.addr
  %ld1753 = load ptr, ptr %lst.addr
  %ld1754 = load ptr, ptr %h.addr
  %ld1755 = load ptr, ptr %acc.addr
  %rc1756 = load i64, ptr %ld1753, align 8
  %uniq1757 = icmp eq i64 %rc1756, 1
  %fbip_slot1758 = alloca ptr
  br i1 %uniq1757, label %fbip_reuse352, label %fbip_fresh353
fbip_reuse352:
  %tgp1759 = getelementptr i8, ptr %ld1753, i64 8
  store i32 1, ptr %tgp1759, align 4
  %fp1760 = getelementptr i8, ptr %ld1753, i64 16
  store ptr %ld1754, ptr %fp1760, align 8
  %fp1761 = getelementptr i8, ptr %ld1753, i64 24
  store ptr %ld1755, ptr %fp1761, align 8
  store ptr %ld1753, ptr %fbip_slot1758
  br label %fbip_merge354
fbip_fresh353:
  call void @march_decrc(ptr %ld1753)
  %hp1762 = call ptr @march_alloc(i64 32)
  %tgp1763 = getelementptr i8, ptr %hp1762, i64 8
  store i32 1, ptr %tgp1763, align 4
  %fp1764 = getelementptr i8, ptr %hp1762, i64 16
  store ptr %ld1754, ptr %fp1764, align 8
  %fp1765 = getelementptr i8, ptr %hp1762, i64 24
  store ptr %ld1755, ptr %fp1765, align 8
  store ptr %hp1762, ptr %fbip_slot1758
  br label %fbip_merge354
fbip_merge354:
  %fbip_r1766 = load ptr, ptr %fbip_slot1758
  %$t1352.addr = alloca ptr
  store ptr %fbip_r1766, ptr %$t1352.addr
  %ld1767 = load ptr, ptr %go.addr
  %fp1768 = getelementptr i8, ptr %ld1767, i64 16
  %fv1769 = load ptr, ptr %fp1768, align 8
  %ld1770 = load ptr, ptr %t.addr
  %ld1771 = load ptr, ptr %$t1352.addr
  %cr1772 = call ptr (ptr, ptr, ptr) %fv1769(ptr %ld1767, ptr %ld1770, ptr %ld1771)
  store ptr %cr1772, ptr %res_slot1742
  br label %case_merge348
case_default349:
  unreachable
case_merge348:
  %case_r1773 = load ptr, ptr %res_slot1742
  ret ptr %case_r1773
}

define ptr @go$apply$31(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1774 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1774, ptr %go.addr
  %ld1775 = load ptr, ptr %lst.addr
  %res_slot1776 = alloca ptr
  %tgp1777 = getelementptr i8, ptr %ld1775, i64 8
  %tag1778 = load i32, ptr %tgp1777, align 4
  switch i32 %tag1778, label %case_default356 [
      i32 0, label %case_br357
      i32 1, label %case_br358
  ]
case_br357:
  %ld1779 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1779)
  %ld1780 = load ptr, ptr %acc.addr
  store ptr %ld1780, ptr %res_slot1776
  br label %case_merge355
case_br358:
  %fp1781 = getelementptr i8, ptr %ld1775, i64 16
  %fv1782 = load ptr, ptr %fp1781, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv1782, ptr %$f1353.addr
  %fp1783 = getelementptr i8, ptr %ld1775, i64 24
  %fv1784 = load ptr, ptr %fp1783, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv1784, ptr %$f1354.addr
  %ld1785 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld1785, ptr %t.addr
  %ld1786 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld1786, ptr %h.addr
  %ld1787 = load ptr, ptr %lst.addr
  %ld1788 = load ptr, ptr %h.addr
  %ld1789 = load ptr, ptr %acc.addr
  %rc1790 = load i64, ptr %ld1787, align 8
  %uniq1791 = icmp eq i64 %rc1790, 1
  %fbip_slot1792 = alloca ptr
  br i1 %uniq1791, label %fbip_reuse359, label %fbip_fresh360
fbip_reuse359:
  %tgp1793 = getelementptr i8, ptr %ld1787, i64 8
  store i32 1, ptr %tgp1793, align 4
  %fp1794 = getelementptr i8, ptr %ld1787, i64 16
  store ptr %ld1788, ptr %fp1794, align 8
  %fp1795 = getelementptr i8, ptr %ld1787, i64 24
  store ptr %ld1789, ptr %fp1795, align 8
  store ptr %ld1787, ptr %fbip_slot1792
  br label %fbip_merge361
fbip_fresh360:
  call void @march_decrc(ptr %ld1787)
  %hp1796 = call ptr @march_alloc(i64 32)
  %tgp1797 = getelementptr i8, ptr %hp1796, i64 8
  store i32 1, ptr %tgp1797, align 4
  %fp1798 = getelementptr i8, ptr %hp1796, i64 16
  store ptr %ld1788, ptr %fp1798, align 8
  %fp1799 = getelementptr i8, ptr %hp1796, i64 24
  store ptr %ld1789, ptr %fp1799, align 8
  store ptr %hp1796, ptr %fbip_slot1792
  br label %fbip_merge361
fbip_merge361:
  %fbip_r1800 = load ptr, ptr %fbip_slot1792
  %$t1352.addr = alloca ptr
  store ptr %fbip_r1800, ptr %$t1352.addr
  %ld1801 = load ptr, ptr %go.addr
  %fp1802 = getelementptr i8, ptr %ld1801, i64 16
  %fv1803 = load ptr, ptr %fp1802, align 8
  %ld1804 = load ptr, ptr %t.addr
  %ld1805 = load ptr, ptr %$t1352.addr
  %cr1806 = call ptr (ptr, ptr, ptr) %fv1803(ptr %ld1801, ptr %ld1804, ptr %ld1805)
  store ptr %cr1806, ptr %res_slot1776
  br label %case_merge355
case_default356:
  unreachable
case_merge355:
  %case_r1807 = load ptr, ptr %res_slot1776
  ret ptr %case_r1807
}

define ptr @go$apply$32(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1808 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld1808, ptr %go.addr
  %ld1809 = load ptr, ptr %lst.addr
  %res_slot1810 = alloca ptr
  %tgp1811 = getelementptr i8, ptr %ld1809, i64 8
  %tag1812 = load i32, ptr %tgp1811, align 4
  switch i32 %tag1812, label %case_default363 [
      i32 0, label %case_br364
      i32 1, label %case_br365
  ]
case_br364:
  %ld1813 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld1813)
  %ld1814 = load ptr, ptr %acc.addr
  store ptr %ld1814, ptr %res_slot1810
  br label %case_merge362
case_br365:
  %fp1815 = getelementptr i8, ptr %ld1809, i64 16
  %fv1816 = load ptr, ptr %fp1815, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv1816, ptr %$f1353.addr
  %fp1817 = getelementptr i8, ptr %ld1809, i64 24
  %fv1818 = load ptr, ptr %fp1817, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv1818, ptr %$f1354.addr
  %ld1819 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld1819, ptr %t.addr
  %ld1820 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld1820, ptr %h.addr
  %ld1821 = load ptr, ptr %lst.addr
  %ld1822 = load ptr, ptr %h.addr
  %ld1823 = load ptr, ptr %acc.addr
  %rc1824 = load i64, ptr %ld1821, align 8
  %uniq1825 = icmp eq i64 %rc1824, 1
  %fbip_slot1826 = alloca ptr
  br i1 %uniq1825, label %fbip_reuse366, label %fbip_fresh367
fbip_reuse366:
  %tgp1827 = getelementptr i8, ptr %ld1821, i64 8
  store i32 1, ptr %tgp1827, align 4
  %fp1828 = getelementptr i8, ptr %ld1821, i64 16
  store ptr %ld1822, ptr %fp1828, align 8
  %fp1829 = getelementptr i8, ptr %ld1821, i64 24
  store ptr %ld1823, ptr %fp1829, align 8
  store ptr %ld1821, ptr %fbip_slot1826
  br label %fbip_merge368
fbip_fresh367:
  call void @march_decrc(ptr %ld1821)
  %hp1830 = call ptr @march_alloc(i64 32)
  %tgp1831 = getelementptr i8, ptr %hp1830, i64 8
  store i32 1, ptr %tgp1831, align 4
  %fp1832 = getelementptr i8, ptr %hp1830, i64 16
  store ptr %ld1822, ptr %fp1832, align 8
  %fp1833 = getelementptr i8, ptr %hp1830, i64 24
  store ptr %ld1823, ptr %fp1833, align 8
  store ptr %hp1830, ptr %fbip_slot1826
  br label %fbip_merge368
fbip_merge368:
  %fbip_r1834 = load ptr, ptr %fbip_slot1826
  %$t1352.addr = alloca ptr
  store ptr %fbip_r1834, ptr %$t1352.addr
  %ld1835 = load ptr, ptr %go.addr
  %fp1836 = getelementptr i8, ptr %ld1835, i64 16
  %fv1837 = load ptr, ptr %fp1836, align 8
  %ld1838 = load ptr, ptr %t.addr
  %ld1839 = load ptr, ptr %$t1352.addr
  %cr1840 = call ptr (ptr, ptr, ptr) %fv1837(ptr %ld1835, ptr %ld1838, ptr %ld1839)
  store ptr %cr1840, ptr %res_slot1810
  br label %case_merge362
case_default363:
  unreachable
case_merge362:
  %case_r1841 = load ptr, ptr %res_slot1810
  ret ptr %case_r1841
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
