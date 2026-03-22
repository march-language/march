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

@.str1 = private unnamed_addr constant [29 x i8] c"heap_extract_min: empty heap\00"

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
  %xs_i23.addr = alloca ptr
  store ptr %ld53, ptr %xs_i23.addr
  %ld54 = load ptr, ptr %cmp.addr
  %cmp_i24.addr = alloca ptr
  store ptr %ld54, ptr %cmp_i24.addr
  %ld55 = load ptr, ptr %xs_i23.addr
  %ld56 = load ptr, ptr %cmp_i24.addr
  %cr57 = call ptr @Sort.heap_build$List_V__5163$Fn_V__5163_Fn_V__5163_Bool(ptr %ld55, ptr %ld56)
  %$t1662_i25.addr = alloca ptr
  store ptr %cr57, ptr %$t1662_i25.addr
  %hp58 = call ptr @march_alloc(i64 16)
  %tgp59 = getelementptr i8, ptr %hp58, i64 8
  store i32 0, ptr %tgp59, align 4
  %$t1663_i26.addr = alloca ptr
  store ptr %hp58, ptr %$t1663_i26.addr
  %ld60 = load ptr, ptr %$t1662_i25.addr
  %ld61 = load ptr, ptr %cmp_i24.addr
  %ld62 = load ptr, ptr %$t1663_i26.addr
  %cr63 = call ptr @Sort.heap_drain$Heap_V__5163$Fn_V__5163_Fn_V__5163_Bool$List_V__5163(ptr %ld60, ptr %ld61, ptr %ld62)
  %sorted.addr = alloca ptr
  store ptr %cr63, ptr %sorted.addr
  %ld64 = load ptr, ptr %sorted.addr
  %cr65 = call i64 @head(ptr %ld64)
  %$t2020.addr = alloca i64
  store i64 %cr65, ptr %$t2020.addr
  %ld66 = load i64, ptr %$t2020.addr
  %cr67 = call ptr @march_int_to_string(i64 %ld66)
  %$t2021.addr = alloca ptr
  store ptr %cr67, ptr %$t2021.addr
  %ld68 = load ptr, ptr %$t2021.addr
  call void @march_println(ptr %ld68)
  ret void
}

define ptr @Sort.heap_drain$Heap_V__5163$Fn_V__5163_Fn_V__5163_Bool$List_V__5163(ptr %h.arg, ptr %cmp.arg, ptr %acc.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld69 = load ptr, ptr %h.addr
  %res_slot70 = alloca ptr
  %tgp71 = getelementptr i8, ptr %ld69, i64 8
  %tag72 = load i32, ptr %tgp71, align 4
  switch i32 %tag72, label %case_default12 [
      i32 0, label %case_br13
  ]
case_br13:
  %ld73 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld73)
  %ld74 = load ptr, ptr %acc.addr
  %cr75 = call ptr @Sort.reverse_list$List_V__5159(ptr %ld74)
  store ptr %cr75, ptr %res_slot70
  br label %case_merge11
case_default12:
  %ld76 = load ptr, ptr %h.addr
  %ld77 = load ptr, ptr %cmp.addr
  %cr78 = call ptr @Sort.heap_extract_min$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool(ptr %ld76, ptr %ld77)
  %$p1661.addr = alloca ptr
  store ptr %cr78, ptr %$p1661.addr
  %ld79 = load ptr, ptr %$p1661.addr
  %fp80 = getelementptr i8, ptr %ld79, i64 16
  %fv81 = load ptr, ptr %fp80, align 8
  %x.addr = alloca ptr
  store ptr %fv81, ptr %x.addr
  %ld82 = load ptr, ptr %$p1661.addr
  %fp83 = getelementptr i8, ptr %ld82, i64 24
  %fv84 = load ptr, ptr %fp83, align 8
  %h2.addr = alloca ptr
  store ptr %fv84, ptr %h2.addr
  %hp85 = call ptr @march_alloc(i64 32)
  %tgp86 = getelementptr i8, ptr %hp85, i64 8
  store i32 1, ptr %tgp86, align 4
  %ld87 = load ptr, ptr %x.addr
  %fp88 = getelementptr i8, ptr %hp85, i64 16
  store ptr %ld87, ptr %fp88, align 8
  %ld89 = load ptr, ptr %acc.addr
  %fp90 = getelementptr i8, ptr %hp85, i64 24
  store ptr %ld89, ptr %fp90, align 8
  %$t1660.addr = alloca ptr
  store ptr %hp85, ptr %$t1660.addr
  %ld91 = load ptr, ptr %h2.addr
  %ld92 = load ptr, ptr %cmp.addr
  %ld93 = load ptr, ptr %$t1660.addr
  %cr94 = call ptr @Sort.heap_drain$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool$List_V__5159(ptr %ld91, ptr %ld92, ptr %ld93)
  store ptr %cr94, ptr %res_slot70
  br label %case_merge11
case_merge11:
  %case_r95 = load ptr, ptr %res_slot70
  ret ptr %case_r95
}

define ptr @Sort.heap_build$List_V__5163$Fn_V__5163_Fn_V__5163_Bool(ptr %xs.arg, ptr %cmp.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %hp96 = call ptr @march_alloc(i64 32)
  %tgp97 = getelementptr i8, ptr %hp96, i64 8
  store i32 0, ptr %tgp97, align 4
  %fp98 = getelementptr i8, ptr %hp96, i64 16
  store ptr @go$apply$26, ptr %fp98, align 8
  %ld99 = load ptr, ptr %cmp.addr
  %fp100 = getelementptr i8, ptr %hp96, i64 24
  store ptr %ld99, ptr %fp100, align 8
  %go.addr = alloca ptr
  store ptr %hp96, ptr %go.addr
  %hp101 = call ptr @march_alloc(i64 16)
  %tgp102 = getelementptr i8, ptr %hp101, i64 8
  store i32 0, ptr %tgp102, align 4
  %$t1659.addr = alloca ptr
  store ptr %hp101, ptr %$t1659.addr
  %ld103 = load ptr, ptr %go.addr
  %fp104 = getelementptr i8, ptr %ld103, i64 16
  %fv105 = load ptr, ptr %fp104, align 8
  %ld106 = load ptr, ptr %xs.addr
  %ld107 = load ptr, ptr %$t1659.addr
  %cr108 = call ptr (ptr, ptr, ptr) %fv105(ptr %ld103, ptr %ld106, ptr %ld107)
  ret ptr %cr108
}

define ptr @Sort.reverse_list$List_V__5159(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp109 = call ptr @march_alloc(i64 24)
  %tgp110 = getelementptr i8, ptr %hp109, i64 8
  store i32 0, ptr %tgp110, align 4
  %fp111 = getelementptr i8, ptr %hp109, i64 16
  store ptr @go$apply$27, ptr %fp111, align 8
  %go.addr = alloca ptr
  store ptr %hp109, ptr %go.addr
  %hp112 = call ptr @march_alloc(i64 16)
  %tgp113 = getelementptr i8, ptr %hp112, i64 8
  store i32 0, ptr %tgp113, align 4
  %$t1355.addr = alloca ptr
  store ptr %hp112, ptr %$t1355.addr
  %ld114 = load ptr, ptr %go.addr
  %fp115 = getelementptr i8, ptr %ld114, i64 16
  %fv116 = load ptr, ptr %fp115, align 8
  %ld117 = load ptr, ptr %xs.addr
  %ld118 = load ptr, ptr %$t1355.addr
  %cr119 = call ptr (ptr, ptr, ptr) %fv116(ptr %ld114, ptr %ld117, ptr %ld118)
  ret ptr %cr119
}

define ptr @Sort.heap_drain$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool$List_V__5159(ptr %h.arg, ptr %cmp.arg, ptr %acc.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld120 = load ptr, ptr %h.addr
  %res_slot121 = alloca ptr
  %tgp122 = getelementptr i8, ptr %ld120, i64 8
  %tag123 = load i32, ptr %tgp122, align 4
  switch i32 %tag123, label %case_default15 [
      i32 0, label %case_br16
  ]
case_br16:
  %ld124 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld124)
  %ld125 = load ptr, ptr %acc.addr
  %cr126 = call ptr @Sort.reverse_list$List_V__5159(ptr %ld125)
  store ptr %cr126, ptr %res_slot121
  br label %case_merge14
case_default15:
  %ld127 = load ptr, ptr %h.addr
  %ld128 = load ptr, ptr %cmp.addr
  %cr129 = call ptr @Sort.heap_extract_min$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool(ptr %ld127, ptr %ld128)
  %$p1661.addr = alloca ptr
  store ptr %cr129, ptr %$p1661.addr
  %ld130 = load ptr, ptr %$p1661.addr
  %fp131 = getelementptr i8, ptr %ld130, i64 16
  %fv132 = load ptr, ptr %fp131, align 8
  %x.addr = alloca ptr
  store ptr %fv132, ptr %x.addr
  %ld133 = load ptr, ptr %$p1661.addr
  %fp134 = getelementptr i8, ptr %ld133, i64 24
  %fv135 = load ptr, ptr %fp134, align 8
  %h2.addr = alloca ptr
  store ptr %fv135, ptr %h2.addr
  %hp136 = call ptr @march_alloc(i64 32)
  %tgp137 = getelementptr i8, ptr %hp136, i64 8
  store i32 1, ptr %tgp137, align 4
  %ld138 = load ptr, ptr %x.addr
  %fp139 = getelementptr i8, ptr %hp136, i64 16
  store ptr %ld138, ptr %fp139, align 8
  %ld140 = load ptr, ptr %acc.addr
  %fp141 = getelementptr i8, ptr %hp136, i64 24
  store ptr %ld140, ptr %fp141, align 8
  %$t1660.addr = alloca ptr
  store ptr %hp136, ptr %$t1660.addr
  %ld142 = load ptr, ptr %h2.addr
  %ld143 = load ptr, ptr %cmp.addr
  %ld144 = load ptr, ptr %$t1660.addr
  %cr145 = call ptr @Sort.heap_drain$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool$List_V__5159(ptr %ld142, ptr %ld143, ptr %ld144)
  store ptr %cr145, ptr %res_slot121
  br label %case_merge14
case_merge14:
  %case_r146 = load ptr, ptr %res_slot121
  ret ptr %case_r146
}

define ptr @Sort.heap_extract_min$Heap_V__5159$Fn_V__5159_Fn_V__5159_Bool(ptr %h.arg, ptr %cmp.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld147 = load ptr, ptr %h.addr
  %res_slot148 = alloca ptr
  %tgp149 = getelementptr i8, ptr %ld147, i64 8
  %tag150 = load i32, ptr %tgp149, align 4
  switch i32 %tag150, label %case_default18 [
      i32 0, label %case_br19
      i32 1, label %case_br20
  ]
case_br19:
  %ld151 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld151)
  %sl152 = call ptr @march_string_lit(ptr @.str1, i64 28)
  call void @march_panic(ptr %sl152)
  %cv153 = inttoptr i64 0 to ptr
  store ptr %cv153, ptr %res_slot148
  br label %case_merge17
case_br20:
  %fp154 = getelementptr i8, ptr %ld147, i64 16
  %fv155 = load i64, ptr %fp154, align 8
  %$f1652.addr = alloca i64
  store i64 %fv155, ptr %$f1652.addr
  %fp156 = getelementptr i8, ptr %ld147, i64 24
  %fv157 = load ptr, ptr %fp156, align 8
  %$f1653.addr = alloca ptr
  store ptr %fv157, ptr %$f1653.addr
  %fp158 = getelementptr i8, ptr %ld147, i64 32
  %fv159 = load ptr, ptr %fp158, align 8
  %$f1654.addr = alloca ptr
  store ptr %fv159, ptr %$f1654.addr
  %fp160 = getelementptr i8, ptr %ld147, i64 40
  %fv161 = load ptr, ptr %fp160, align 8
  %$f1655.addr = alloca ptr
  store ptr %fv161, ptr %$f1655.addr
  %freed162 = call i64 @march_decrc_freed(ptr %ld147)
  %freed_b163 = icmp ne i64 %freed162, 0
  br i1 %freed_b163, label %br_unique21, label %br_shared22
br_shared22:
  call void @march_incrc(ptr %fv161)
  call void @march_incrc(ptr %fv159)
  call void @march_incrc(ptr %fv157)
  br label %br_body23
br_unique21:
  br label %br_body23
br_body23:
  %ld164 = load ptr, ptr %$f1655.addr
  %r.addr = alloca ptr
  store ptr %ld164, ptr %r.addr
  %ld165 = load ptr, ptr %$f1654.addr
  %l.addr = alloca ptr
  store ptr %ld165, ptr %l.addr
  %ld166 = load ptr, ptr %$f1653.addr
  %x.addr = alloca ptr
  store ptr %ld166, ptr %x.addr
  %ld167 = load ptr, ptr %l.addr
  %ld168 = load ptr, ptr %r.addr
  %ld169 = load ptr, ptr %cmp.addr
  %cr170 = call ptr @Sort.heap_merge_h$Heap_V__5130$Heap_V__5130$Fn_V__5130_Fn_V__5130_Bool(ptr %ld167, ptr %ld168, ptr %ld169)
  %$t1651.addr = alloca ptr
  store ptr %cr170, ptr %$t1651.addr
  %hp171 = call ptr @march_alloc(i64 32)
  %tgp172 = getelementptr i8, ptr %hp171, i64 8
  store i32 0, ptr %tgp172, align 4
  %ld173 = load ptr, ptr %x.addr
  %fp174 = getelementptr i8, ptr %hp171, i64 16
  store ptr %ld173, ptr %fp174, align 8
  %ld175 = load ptr, ptr %$t1651.addr
  %fp176 = getelementptr i8, ptr %hp171, i64 24
  store ptr %ld175, ptr %fp176, align 8
  store ptr %hp171, ptr %res_slot148
  br label %case_merge17
case_default18:
  unreachable
case_merge17:
  %case_r177 = load ptr, ptr %res_slot148
  ret ptr %case_r177
}

define ptr @Sort.heap_merge_h$Heap_V__5130$Heap_V__5130$Fn_V__5130_Fn_V__5130_Bool(ptr %h1.arg, ptr %h2.arg, ptr %cmp.arg) {
entry:
  %h1.addr = alloca ptr
  store ptr %h1.arg, ptr %h1.addr
  %h2.addr = alloca ptr
  store ptr %h2.arg, ptr %h2.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld178 = load ptr, ptr %h1.addr
  %res_slot179 = alloca ptr
  %tgp180 = getelementptr i8, ptr %ld178, i64 8
  %tag181 = load i32, ptr %tgp180, align 4
  switch i32 %tag181, label %case_default25 [
      i32 0, label %case_br26
      i32 1, label %case_br27
  ]
case_br26:
  %ld182 = load ptr, ptr %h1.addr
  call void @march_decrc(ptr %ld182)
  %ld183 = load ptr, ptr %h2.addr
  store ptr %ld183, ptr %res_slot179
  br label %case_merge24
case_br27:
  %fp184 = getelementptr i8, ptr %ld178, i64 16
  %fv185 = load i64, ptr %fp184, align 8
  %$f1644.addr = alloca i64
  store i64 %fv185, ptr %$f1644.addr
  %fp186 = getelementptr i8, ptr %ld178, i64 24
  %fv187 = load ptr, ptr %fp186, align 8
  %$f1645.addr = alloca ptr
  store ptr %fv187, ptr %$f1645.addr
  %fp188 = getelementptr i8, ptr %ld178, i64 32
  %fv189 = load ptr, ptr %fp188, align 8
  %$f1646.addr = alloca ptr
  store ptr %fv189, ptr %$f1646.addr
  %fp190 = getelementptr i8, ptr %ld178, i64 40
  %fv191 = load ptr, ptr %fp190, align 8
  %$f1647.addr = alloca ptr
  store ptr %fv191, ptr %$f1647.addr
  %ld192 = load ptr, ptr %$f1647.addr
  %r1.addr = alloca ptr
  store ptr %ld192, ptr %r1.addr
  %ld193 = load ptr, ptr %$f1646.addr
  %l1.addr = alloca ptr
  store ptr %ld193, ptr %l1.addr
  %ld194 = load ptr, ptr %$f1645.addr
  %x.addr = alloca ptr
  store ptr %ld194, ptr %x.addr
  %ld195 = load ptr, ptr %h2.addr
  %res_slot196 = alloca ptr
  %tgp197 = getelementptr i8, ptr %ld195, i64 8
  %tag198 = load i32, ptr %tgp197, align 4
  switch i32 %tag198, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %ld199 = load ptr, ptr %h2.addr
  call void @march_decrc(ptr %ld199)
  %ld200 = load ptr, ptr %h1.addr
  store ptr %ld200, ptr %res_slot196
  br label %case_merge28
case_br31:
  %fp201 = getelementptr i8, ptr %ld195, i64 16
  %fv202 = load i64, ptr %fp201, align 8
  %$f1640.addr = alloca i64
  store i64 %fv202, ptr %$f1640.addr
  %fp203 = getelementptr i8, ptr %ld195, i64 24
  %fv204 = load ptr, ptr %fp203, align 8
  %$f1641.addr = alloca ptr
  store ptr %fv204, ptr %$f1641.addr
  %fp205 = getelementptr i8, ptr %ld195, i64 32
  %fv206 = load ptr, ptr %fp205, align 8
  %$f1642.addr = alloca ptr
  store ptr %fv206, ptr %$f1642.addr
  %fp207 = getelementptr i8, ptr %ld195, i64 40
  %fv208 = load ptr, ptr %fp207, align 8
  %$f1643.addr = alloca ptr
  store ptr %fv208, ptr %$f1643.addr
  %ld209 = load ptr, ptr %$f1643.addr
  %r2.addr = alloca ptr
  store ptr %ld209, ptr %r2.addr
  %ld210 = load ptr, ptr %$f1642.addr
  %l2.addr = alloca ptr
  store ptr %ld210, ptr %l2.addr
  %ld211 = load ptr, ptr %$f1641.addr
  %y.addr = alloca ptr
  store ptr %ld211, ptr %y.addr
  %ld212 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld212)
  %ld213 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld213)
  %ld214 = load ptr, ptr %cmp.addr
  %ld215 = load ptr, ptr %x.addr
  %ld216 = load ptr, ptr %y.addr
  %cr217 = call i64 @Sort.cmp2$Fn_V__5114_Fn_V__5114_Bool$V__5114$V__5114(ptr %ld214, ptr %ld215, ptr %ld216)
  %$t1637.addr = alloca i64
  store i64 %cr217, ptr %$t1637.addr
  %ld218 = load i64, ptr %$t1637.addr
  %res_slot219 = alloca ptr
  %bi220 = trunc i64 %ld218 to i1
  br i1 %bi220, label %case_br34, label %case_default33
case_br34:
  %ld221 = load ptr, ptr %r1.addr
  %ld222 = load ptr, ptr %h2.addr
  %ld223 = load ptr, ptr %cmp.addr
  %cr224 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld221, ptr %ld222, ptr %ld223)
  %$t1638.addr = alloca ptr
  store ptr %cr224, ptr %$t1638.addr
  %ld225 = load ptr, ptr %x.addr
  %ld226 = load ptr, ptr %l1.addr
  %ld227 = load ptr, ptr %$t1638.addr
  %cr228 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld225, ptr %ld226, ptr %ld227)
  store ptr %cr228, ptr %res_slot219
  br label %case_merge32
case_default33:
  %ld229 = load ptr, ptr %h1.addr
  %ld230 = load ptr, ptr %r2.addr
  %ld231 = load ptr, ptr %cmp.addr
  %cr232 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld229, ptr %ld230, ptr %ld231)
  %$t1639.addr = alloca ptr
  store ptr %cr232, ptr %$t1639.addr
  %ld233 = load ptr, ptr %y.addr
  %ld234 = load ptr, ptr %l2.addr
  %ld235 = load ptr, ptr %$t1639.addr
  %cr236 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld233, ptr %ld234, ptr %ld235)
  store ptr %cr236, ptr %res_slot219
  br label %case_merge32
case_merge32:
  %case_r237 = load ptr, ptr %res_slot219
  store ptr %case_r237, ptr %res_slot196
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r238 = load ptr, ptr %res_slot196
  store ptr %case_r238, ptr %res_slot179
  br label %case_merge24
case_default25:
  unreachable
case_merge24:
  %case_r239 = load ptr, ptr %res_slot179
  ret ptr %case_r239
}

define ptr @Sort.heap_merge_h$Heap_V__5117$Heap_V__5117$Fn_V__5117_Fn_V__5117_Bool(ptr %h1.arg, ptr %h2.arg, ptr %cmp.arg) {
entry:
  %h1.addr = alloca ptr
  store ptr %h1.arg, ptr %h1.addr
  %h2.addr = alloca ptr
  store ptr %h2.arg, ptr %h2.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld240 = load ptr, ptr %h1.addr
  %res_slot241 = alloca ptr
  %tgp242 = getelementptr i8, ptr %ld240, i64 8
  %tag243 = load i32, ptr %tgp242, align 4
  switch i32 %tag243, label %case_default36 [
      i32 0, label %case_br37
      i32 1, label %case_br38
  ]
case_br37:
  %ld244 = load ptr, ptr %h1.addr
  call void @march_decrc(ptr %ld244)
  %ld245 = load ptr, ptr %h2.addr
  store ptr %ld245, ptr %res_slot241
  br label %case_merge35
case_br38:
  %fp246 = getelementptr i8, ptr %ld240, i64 16
  %fv247 = load i64, ptr %fp246, align 8
  %$f1644.addr = alloca i64
  store i64 %fv247, ptr %$f1644.addr
  %fp248 = getelementptr i8, ptr %ld240, i64 24
  %fv249 = load ptr, ptr %fp248, align 8
  %$f1645.addr = alloca ptr
  store ptr %fv249, ptr %$f1645.addr
  %fp250 = getelementptr i8, ptr %ld240, i64 32
  %fv251 = load ptr, ptr %fp250, align 8
  %$f1646.addr = alloca ptr
  store ptr %fv251, ptr %$f1646.addr
  %fp252 = getelementptr i8, ptr %ld240, i64 40
  %fv253 = load ptr, ptr %fp252, align 8
  %$f1647.addr = alloca ptr
  store ptr %fv253, ptr %$f1647.addr
  %ld254 = load ptr, ptr %$f1647.addr
  %r1.addr = alloca ptr
  store ptr %ld254, ptr %r1.addr
  %ld255 = load ptr, ptr %$f1646.addr
  %l1.addr = alloca ptr
  store ptr %ld255, ptr %l1.addr
  %ld256 = load ptr, ptr %$f1645.addr
  %x.addr = alloca ptr
  store ptr %ld256, ptr %x.addr
  %ld257 = load ptr, ptr %h2.addr
  %res_slot258 = alloca ptr
  %tgp259 = getelementptr i8, ptr %ld257, i64 8
  %tag260 = load i32, ptr %tgp259, align 4
  switch i32 %tag260, label %case_default40 [
      i32 0, label %case_br41
      i32 1, label %case_br42
  ]
case_br41:
  %ld261 = load ptr, ptr %h2.addr
  call void @march_decrc(ptr %ld261)
  %ld262 = load ptr, ptr %h1.addr
  store ptr %ld262, ptr %res_slot258
  br label %case_merge39
case_br42:
  %fp263 = getelementptr i8, ptr %ld257, i64 16
  %fv264 = load i64, ptr %fp263, align 8
  %$f1640.addr = alloca i64
  store i64 %fv264, ptr %$f1640.addr
  %fp265 = getelementptr i8, ptr %ld257, i64 24
  %fv266 = load ptr, ptr %fp265, align 8
  %$f1641.addr = alloca ptr
  store ptr %fv266, ptr %$f1641.addr
  %fp267 = getelementptr i8, ptr %ld257, i64 32
  %fv268 = load ptr, ptr %fp267, align 8
  %$f1642.addr = alloca ptr
  store ptr %fv268, ptr %$f1642.addr
  %fp269 = getelementptr i8, ptr %ld257, i64 40
  %fv270 = load ptr, ptr %fp269, align 8
  %$f1643.addr = alloca ptr
  store ptr %fv270, ptr %$f1643.addr
  %ld271 = load ptr, ptr %$f1643.addr
  %r2.addr = alloca ptr
  store ptr %ld271, ptr %r2.addr
  %ld272 = load ptr, ptr %$f1642.addr
  %l2.addr = alloca ptr
  store ptr %ld272, ptr %l2.addr
  %ld273 = load ptr, ptr %$f1641.addr
  %y.addr = alloca ptr
  store ptr %ld273, ptr %y.addr
  %ld274 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld274)
  %ld275 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld275)
  %ld276 = load ptr, ptr %cmp.addr
  %ld277 = load ptr, ptr %x.addr
  %ld278 = load ptr, ptr %y.addr
  %cr279 = call i64 @Sort.cmp2$Fn_V__5114_Fn_V__5114_Bool$V__5114$V__5114(ptr %ld276, ptr %ld277, ptr %ld278)
  %$t1637.addr = alloca i64
  store i64 %cr279, ptr %$t1637.addr
  %ld280 = load i64, ptr %$t1637.addr
  %res_slot281 = alloca ptr
  %bi282 = trunc i64 %ld280 to i1
  br i1 %bi282, label %case_br45, label %case_default44
case_br45:
  %ld283 = load ptr, ptr %r1.addr
  %ld284 = load ptr, ptr %h2.addr
  %ld285 = load ptr, ptr %cmp.addr
  %cr286 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld283, ptr %ld284, ptr %ld285)
  %$t1638.addr = alloca ptr
  store ptr %cr286, ptr %$t1638.addr
  %ld287 = load ptr, ptr %x.addr
  %ld288 = load ptr, ptr %l1.addr
  %ld289 = load ptr, ptr %$t1638.addr
  %cr290 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld287, ptr %ld288, ptr %ld289)
  store ptr %cr290, ptr %res_slot281
  br label %case_merge43
case_default44:
  %ld291 = load ptr, ptr %h1.addr
  %ld292 = load ptr, ptr %r2.addr
  %ld293 = load ptr, ptr %cmp.addr
  %cr294 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld291, ptr %ld292, ptr %ld293)
  %$t1639.addr = alloca ptr
  store ptr %cr294, ptr %$t1639.addr
  %ld295 = load ptr, ptr %y.addr
  %ld296 = load ptr, ptr %l2.addr
  %ld297 = load ptr, ptr %$t1639.addr
  %cr298 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld295, ptr %ld296, ptr %ld297)
  store ptr %cr298, ptr %res_slot281
  br label %case_merge43
case_merge43:
  %case_r299 = load ptr, ptr %res_slot281
  store ptr %case_r299, ptr %res_slot258
  br label %case_merge39
case_default40:
  unreachable
case_merge39:
  %case_r300 = load ptr, ptr %res_slot258
  store ptr %case_r300, ptr %res_slot241
  br label %case_merge35
case_default36:
  unreachable
case_merge35:
  %case_r301 = load ptr, ptr %res_slot241
  ret ptr %case_r301
}

define ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %x.arg, ptr %l.arg, ptr %r.arg) {
entry:
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %l.addr = alloca ptr
  store ptr %l.arg, ptr %l.addr
  %r.addr = alloca ptr
  store ptr %r.arg, ptr %r.addr
  %ld302 = load ptr, ptr %l.addr
  call void @march_incrc(ptr %ld302)
  %ld303 = load ptr, ptr %l.addr
  %cr304 = call i64 @Sort.heap_rank$Heap_V__5092(ptr %ld303)
  %$t1630.addr = alloca i64
  store i64 %cr304, ptr %$t1630.addr
  %ld305 = load ptr, ptr %r.addr
  call void @march_incrc(ptr %ld305)
  %ld306 = load ptr, ptr %r.addr
  %cr307 = call i64 @Sort.heap_rank$Heap_V__5092(ptr %ld306)
  %$t1631.addr = alloca i64
  store i64 %cr307, ptr %$t1631.addr
  %ld308 = load i64, ptr %$t1630.addr
  %ld309 = load i64, ptr %$t1631.addr
  %cmp310 = icmp sge i64 %ld308, %ld309
  %ar311 = zext i1 %cmp310 to i64
  %$t1632.addr = alloca i64
  store i64 %ar311, ptr %$t1632.addr
  %ld312 = load i64, ptr %$t1632.addr
  %res_slot313 = alloca ptr
  %bi314 = trunc i64 %ld312 to i1
  br i1 %bi314, label %case_br48, label %case_default47
case_br48:
  %ld315 = load ptr, ptr %r.addr
  call void @march_incrc(ptr %ld315)
  %ld316 = load ptr, ptr %r.addr
  %cr317 = call i64 @Sort.heap_rank$Heap_V__5092(ptr %ld316)
  %$t1633.addr = alloca i64
  store i64 %cr317, ptr %$t1633.addr
  %ld318 = load i64, ptr %$t1633.addr
  %ar319 = add i64 %ld318, 1
  %$t1634.addr = alloca i64
  store i64 %ar319, ptr %$t1634.addr
  %hp320 = call ptr @march_alloc(i64 48)
  %tgp321 = getelementptr i8, ptr %hp320, i64 8
  store i32 1, ptr %tgp321, align 4
  %ld322 = load i64, ptr %$t1634.addr
  %fp323 = getelementptr i8, ptr %hp320, i64 16
  store i64 %ld322, ptr %fp323, align 8
  %ld324 = load ptr, ptr %x.addr
  %fp325 = getelementptr i8, ptr %hp320, i64 24
  store ptr %ld324, ptr %fp325, align 8
  %ld326 = load ptr, ptr %l.addr
  %fp327 = getelementptr i8, ptr %hp320, i64 32
  store ptr %ld326, ptr %fp327, align 8
  %ld328 = load ptr, ptr %r.addr
  %fp329 = getelementptr i8, ptr %hp320, i64 40
  store ptr %ld328, ptr %fp329, align 8
  store ptr %hp320, ptr %res_slot313
  br label %case_merge46
case_default47:
  %ld330 = load ptr, ptr %l.addr
  call void @march_incrc(ptr %ld330)
  %ld331 = load ptr, ptr %l.addr
  %cr332 = call i64 @Sort.heap_rank$Heap_V__5092(ptr %ld331)
  %$t1635.addr = alloca i64
  store i64 %cr332, ptr %$t1635.addr
  %ld333 = load i64, ptr %$t1635.addr
  %ar334 = add i64 %ld333, 1
  %$t1636.addr = alloca i64
  store i64 %ar334, ptr %$t1636.addr
  %hp335 = call ptr @march_alloc(i64 48)
  %tgp336 = getelementptr i8, ptr %hp335, i64 8
  store i32 1, ptr %tgp336, align 4
  %ld337 = load i64, ptr %$t1636.addr
  %fp338 = getelementptr i8, ptr %hp335, i64 16
  store i64 %ld337, ptr %fp338, align 8
  %ld339 = load ptr, ptr %x.addr
  %fp340 = getelementptr i8, ptr %hp335, i64 24
  store ptr %ld339, ptr %fp340, align 8
  %ld341 = load ptr, ptr %r.addr
  %fp342 = getelementptr i8, ptr %hp335, i64 32
  store ptr %ld341, ptr %fp342, align 8
  %ld343 = load ptr, ptr %l.addr
  %fp344 = getelementptr i8, ptr %hp335, i64 40
  store ptr %ld343, ptr %fp344, align 8
  store ptr %hp335, ptr %res_slot313
  br label %case_merge46
case_merge46:
  %case_r345 = load ptr, ptr %res_slot313
  ret ptr %case_r345
}

define ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %h1.arg, ptr %h2.arg, ptr %cmp.arg) {
entry:
  %h1.addr = alloca ptr
  store ptr %h1.arg, ptr %h1.addr
  %h2.addr = alloca ptr
  store ptr %h2.arg, ptr %h2.addr
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %ld346 = load ptr, ptr %h1.addr
  %res_slot347 = alloca ptr
  %tgp348 = getelementptr i8, ptr %ld346, i64 8
  %tag349 = load i32, ptr %tgp348, align 4
  switch i32 %tag349, label %case_default50 [
      i32 0, label %case_br51
      i32 1, label %case_br52
  ]
case_br51:
  %ld350 = load ptr, ptr %h1.addr
  call void @march_decrc(ptr %ld350)
  %ld351 = load ptr, ptr %h2.addr
  store ptr %ld351, ptr %res_slot347
  br label %case_merge49
case_br52:
  %fp352 = getelementptr i8, ptr %ld346, i64 16
  %fv353 = load i64, ptr %fp352, align 8
  %$f1644.addr = alloca i64
  store i64 %fv353, ptr %$f1644.addr
  %fp354 = getelementptr i8, ptr %ld346, i64 24
  %fv355 = load ptr, ptr %fp354, align 8
  %$f1645.addr = alloca ptr
  store ptr %fv355, ptr %$f1645.addr
  %fp356 = getelementptr i8, ptr %ld346, i64 32
  %fv357 = load ptr, ptr %fp356, align 8
  %$f1646.addr = alloca ptr
  store ptr %fv357, ptr %$f1646.addr
  %fp358 = getelementptr i8, ptr %ld346, i64 40
  %fv359 = load ptr, ptr %fp358, align 8
  %$f1647.addr = alloca ptr
  store ptr %fv359, ptr %$f1647.addr
  %ld360 = load ptr, ptr %$f1647.addr
  %r1.addr = alloca ptr
  store ptr %ld360, ptr %r1.addr
  %ld361 = load ptr, ptr %$f1646.addr
  %l1.addr = alloca ptr
  store ptr %ld361, ptr %l1.addr
  %ld362 = load ptr, ptr %$f1645.addr
  %x.addr = alloca ptr
  store ptr %ld362, ptr %x.addr
  %ld363 = load ptr, ptr %h2.addr
  %res_slot364 = alloca ptr
  %tgp365 = getelementptr i8, ptr %ld363, i64 8
  %tag366 = load i32, ptr %tgp365, align 4
  switch i32 %tag366, label %case_default54 [
      i32 0, label %case_br55
      i32 1, label %case_br56
  ]
case_br55:
  %ld367 = load ptr, ptr %h2.addr
  call void @march_decrc(ptr %ld367)
  %ld368 = load ptr, ptr %h1.addr
  store ptr %ld368, ptr %res_slot364
  br label %case_merge53
case_br56:
  %fp369 = getelementptr i8, ptr %ld363, i64 16
  %fv370 = load i64, ptr %fp369, align 8
  %$f1640.addr = alloca i64
  store i64 %fv370, ptr %$f1640.addr
  %fp371 = getelementptr i8, ptr %ld363, i64 24
  %fv372 = load ptr, ptr %fp371, align 8
  %$f1641.addr = alloca ptr
  store ptr %fv372, ptr %$f1641.addr
  %fp373 = getelementptr i8, ptr %ld363, i64 32
  %fv374 = load ptr, ptr %fp373, align 8
  %$f1642.addr = alloca ptr
  store ptr %fv374, ptr %$f1642.addr
  %fp375 = getelementptr i8, ptr %ld363, i64 40
  %fv376 = load ptr, ptr %fp375, align 8
  %$f1643.addr = alloca ptr
  store ptr %fv376, ptr %$f1643.addr
  %ld377 = load ptr, ptr %$f1643.addr
  %r2.addr = alloca ptr
  store ptr %ld377, ptr %r2.addr
  %ld378 = load ptr, ptr %$f1642.addr
  %l2.addr = alloca ptr
  store ptr %ld378, ptr %l2.addr
  %ld379 = load ptr, ptr %$f1641.addr
  %y.addr = alloca ptr
  store ptr %ld379, ptr %y.addr
  %ld380 = load ptr, ptr %x.addr
  call void @march_incrc(ptr %ld380)
  %ld381 = load ptr, ptr %y.addr
  call void @march_incrc(ptr %ld381)
  %ld382 = load ptr, ptr %cmp.addr
  %ld383 = load ptr, ptr %x.addr
  %ld384 = load ptr, ptr %y.addr
  %cr385 = call i64 @Sort.cmp2$Fn_V__5114_Fn_V__5114_Bool$V__5114$V__5114(ptr %ld382, ptr %ld383, ptr %ld384)
  %$t1637.addr = alloca i64
  store i64 %cr385, ptr %$t1637.addr
  %ld386 = load i64, ptr %$t1637.addr
  %res_slot387 = alloca ptr
  %bi388 = trunc i64 %ld386 to i1
  br i1 %bi388, label %case_br59, label %case_default58
case_br59:
  %ld389 = load ptr, ptr %r1.addr
  %ld390 = load ptr, ptr %h2.addr
  %ld391 = load ptr, ptr %cmp.addr
  %cr392 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld389, ptr %ld390, ptr %ld391)
  %$t1638.addr = alloca ptr
  store ptr %cr392, ptr %$t1638.addr
  %ld393 = load ptr, ptr %x.addr
  %ld394 = load ptr, ptr %l1.addr
  %ld395 = load ptr, ptr %$t1638.addr
  %cr396 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld393, ptr %ld394, ptr %ld395)
  store ptr %cr396, ptr %res_slot387
  br label %case_merge57
case_default58:
  %ld397 = load ptr, ptr %h1.addr
  %ld398 = load ptr, ptr %r2.addr
  %ld399 = load ptr, ptr %cmp.addr
  %cr400 = call ptr @Sort.heap_merge_h$Heap_V__5114$Heap_V__5114$Fn_V__5114_Fn_V__5114_Bool(ptr %ld397, ptr %ld398, ptr %ld399)
  %$t1639.addr = alloca ptr
  store ptr %cr400, ptr %$t1639.addr
  %ld401 = load ptr, ptr %y.addr
  %ld402 = load ptr, ptr %l2.addr
  %ld403 = load ptr, ptr %$t1639.addr
  %cr404 = call ptr @Sort.make_hnode$V__5114$Heap_V__5114$Heap_V__5114(ptr %ld401, ptr %ld402, ptr %ld403)
  store ptr %cr404, ptr %res_slot387
  br label %case_merge57
case_merge57:
  %case_r405 = load ptr, ptr %res_slot387
  store ptr %case_r405, ptr %res_slot364
  br label %case_merge53
case_default54:
  unreachable
case_merge53:
  %case_r406 = load ptr, ptr %res_slot364
  store ptr %case_r406, ptr %res_slot347
  br label %case_merge49
case_default50:
  unreachable
case_merge49:
  %case_r407 = load ptr, ptr %res_slot347
  ret ptr %case_r407
}

define i64 @Sort.cmp2$Fn_V__5114_Fn_V__5114_Bool$V__5114$V__5114(ptr %cmp.arg, ptr %x.arg, ptr %y.arg) {
entry:
  %cmp.addr = alloca ptr
  store ptr %cmp.arg, ptr %cmp.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld408 = load ptr, ptr %cmp.addr
  %fp409 = getelementptr i8, ptr %ld408, i64 16
  %fv410 = load ptr, ptr %fp409, align 8
  %ld411 = load ptr, ptr %x.addr
  %cr412 = call ptr (ptr, ptr) %fv410(ptr %ld408, ptr %ld411)
  %f.addr = alloca ptr
  store ptr %cr412, ptr %f.addr
  %ld413 = load ptr, ptr %f.addr
  %fp414 = getelementptr i8, ptr %ld413, i64 16
  %fv415 = load ptr, ptr %fp414, align 8
  %ld416 = load ptr, ptr %y.addr
  %cr417 = call i64 (ptr, ptr) %fv415(ptr %ld413, ptr %ld416)
  ret i64 %cr417
}

define i64 @Sort.heap_rank$Heap_V__5092(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld418 = load ptr, ptr %h.addr
  %res_slot419 = alloca ptr
  %tgp420 = getelementptr i8, ptr %ld418, i64 8
  %tag421 = load i32, ptr %tgp420, align 4
  switch i32 %tag421, label %case_default61 [
      i32 0, label %case_br62
      i32 1, label %case_br63
  ]
case_br62:
  %ld422 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld422)
  %cv423 = inttoptr i64 0 to ptr
  store ptr %cv423, ptr %res_slot419
  br label %case_merge60
case_br63:
  %fp424 = getelementptr i8, ptr %ld418, i64 16
  %fv425 = load i64, ptr %fp424, align 8
  %$f1626.addr = alloca i64
  store i64 %fv425, ptr %$f1626.addr
  %fp426 = getelementptr i8, ptr %ld418, i64 24
  %fv427 = load ptr, ptr %fp426, align 8
  %$f1627.addr = alloca ptr
  store ptr %fv427, ptr %$f1627.addr
  %fp428 = getelementptr i8, ptr %ld418, i64 32
  %fv429 = load ptr, ptr %fp428, align 8
  %$f1628.addr = alloca ptr
  store ptr %fv429, ptr %$f1628.addr
  %fp430 = getelementptr i8, ptr %ld418, i64 40
  %fv431 = load ptr, ptr %fp430, align 8
  %$f1629.addr = alloca ptr
  store ptr %fv431, ptr %$f1629.addr
  %freed432 = call i64 @march_decrc_freed(ptr %ld418)
  %freed_b433 = icmp ne i64 %freed432, 0
  br i1 %freed_b433, label %br_unique64, label %br_shared65
br_shared65:
  call void @march_incrc(ptr %fv431)
  call void @march_incrc(ptr %fv429)
  call void @march_incrc(ptr %fv427)
  br label %br_body66
br_unique64:
  br label %br_body66
br_body66:
  %ld434 = load i64, ptr %$f1626.addr
  %r.addr = alloca i64
  store i64 %ld434, ptr %r.addr
  %ld435 = load i64, ptr %r.addr
  %cv436 = inttoptr i64 %ld435 to ptr
  store ptr %cv436, ptr %res_slot419
  br label %case_merge60
case_default61:
  unreachable
case_merge60:
  %case_r437 = load ptr, ptr %res_slot419
  %cv438 = ptrtoint ptr %case_r437 to i64
  ret i64 %cv438
}

define ptr @$lam2018$apply$21(ptr %$clo.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp439 = call ptr @march_alloc(i64 32)
  %tgp440 = getelementptr i8, ptr %hp439, i64 8
  store i32 0, ptr %tgp440, align 4
  %fp441 = getelementptr i8, ptr %hp439, i64 16
  store ptr @$lam2019$apply$22, ptr %fp441, align 8
  %ld442 = load ptr, ptr %x.addr
  %fp443 = getelementptr i8, ptr %hp439, i64 24
  store ptr %ld442, ptr %fp443, align 8
  ret ptr %hp439
}

define i64 @$lam2019$apply$22(ptr %$clo.arg, ptr %y.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %y.addr = alloca ptr
  store ptr %y.arg, ptr %y.addr
  %ld444 = load ptr, ptr %$clo.addr
  %fp445 = getelementptr i8, ptr %ld444, i64 24
  %fv446 = load ptr, ptr %fp445, align 8
  %x.addr = alloca ptr
  store ptr %fv446, ptr %x.addr
  %ld447 = load ptr, ptr %x.addr
  %ld448 = load ptr, ptr %y.addr
  %cv451 = ptrtoint ptr %ld447 to i64
  %cv452 = ptrtoint ptr %ld448 to i64
  %cmp449 = icmp sle i64 %cv451, %cv452
  %ar450 = zext i1 %cmp449 to i64
  ret i64 %ar450
}

define ptr @go$apply$26(ptr %$clo.arg, ptr %lst.arg, ptr %h.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld453 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld453)
  %ld454 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld454, ptr %go.addr
  %ld455 = load ptr, ptr %$clo.addr
  %fp456 = getelementptr i8, ptr %ld455, i64 24
  %fv457 = load ptr, ptr %fp456, align 8
  %cmp.addr = alloca ptr
  store ptr %fv457, ptr %cmp.addr
  %ld458 = load ptr, ptr %lst.addr
  %res_slot459 = alloca ptr
  %tgp460 = getelementptr i8, ptr %ld458, i64 8
  %tag461 = load i32, ptr %tgp460, align 4
  switch i32 %tag461, label %case_default68 [
      i32 0, label %case_br69
      i32 1, label %case_br70
  ]
case_br69:
  %ld462 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld462)
  %ld463 = load ptr, ptr %h.addr
  store ptr %ld463, ptr %res_slot459
  br label %case_merge67
case_br70:
  %fp464 = getelementptr i8, ptr %ld458, i64 16
  %fv465 = load ptr, ptr %fp464, align 8
  %$f1657.addr = alloca ptr
  store ptr %fv465, ptr %$f1657.addr
  %fp466 = getelementptr i8, ptr %ld458, i64 24
  %fv467 = load ptr, ptr %fp466, align 8
  %$f1658.addr = alloca ptr
  store ptr %fv467, ptr %$f1658.addr
  %freed468 = call i64 @march_decrc_freed(ptr %ld458)
  %freed_b469 = icmp ne i64 %freed468, 0
  br i1 %freed_b469, label %br_unique71, label %br_shared72
br_shared72:
  call void @march_incrc(ptr %fv467)
  call void @march_incrc(ptr %fv465)
  br label %br_body73
br_unique71:
  br label %br_body73
br_body73:
  %ld470 = load ptr, ptr %$f1658.addr
  %t.addr = alloca ptr
  store ptr %ld470, ptr %t.addr
  %ld471 = load ptr, ptr %$f1657.addr
  %x.addr = alloca ptr
  store ptr %ld471, ptr %x.addr
  %ld472 = load ptr, ptr %x.addr
  %x_i28.addr = alloca ptr
  store ptr %ld472, ptr %x_i28.addr
  %ld473 = load ptr, ptr %h.addr
  %h_i29.addr = alloca ptr
  store ptr %ld473, ptr %h_i29.addr
  %ld474 = load ptr, ptr %cmp.addr
  %cmp_i30.addr = alloca ptr
  store ptr %ld474, ptr %cmp_i30.addr
  %hp475 = call ptr @march_alloc(i64 16)
  %tgp476 = getelementptr i8, ptr %hp475, i64 8
  store i32 0, ptr %tgp476, align 4
  %$t1648_i31.addr = alloca ptr
  store ptr %hp475, ptr %$t1648_i31.addr
  %hp477 = call ptr @march_alloc(i64 16)
  %tgp478 = getelementptr i8, ptr %hp477, i64 8
  store i32 0, ptr %tgp478, align 4
  %$t1649_i32.addr = alloca ptr
  store ptr %hp477, ptr %$t1649_i32.addr
  %hp479 = call ptr @march_alloc(i64 48)
  %tgp480 = getelementptr i8, ptr %hp479, i64 8
  store i32 1, ptr %tgp480, align 4
  %fp481 = getelementptr i8, ptr %hp479, i64 16
  store i64 1, ptr %fp481, align 8
  %ld482 = load ptr, ptr %x_i28.addr
  %fp483 = getelementptr i8, ptr %hp479, i64 24
  store ptr %ld482, ptr %fp483, align 8
  %ld484 = load ptr, ptr %$t1648_i31.addr
  %fp485 = getelementptr i8, ptr %hp479, i64 32
  store ptr %ld484, ptr %fp485, align 8
  %ld486 = load ptr, ptr %$t1649_i32.addr
  %fp487 = getelementptr i8, ptr %hp479, i64 40
  store ptr %ld486, ptr %fp487, align 8
  %$t1650_i33.addr = alloca ptr
  store ptr %hp479, ptr %$t1650_i33.addr
  %ld488 = load ptr, ptr %$t1650_i33.addr
  %ld489 = load ptr, ptr %h_i29.addr
  %ld490 = load ptr, ptr %cmp_i30.addr
  %cr491 = call ptr @Sort.heap_merge_h$Heap_V__5117$Heap_V__5117$Fn_V__5117_Fn_V__5117_Bool(ptr %ld488, ptr %ld489, ptr %ld490)
  %$t1656.addr = alloca ptr
  store ptr %cr491, ptr %$t1656.addr
  %ld492 = load ptr, ptr %go.addr
  %fp493 = getelementptr i8, ptr %ld492, i64 16
  %fv494 = load ptr, ptr %fp493, align 8
  %ld495 = load ptr, ptr %t.addr
  %ld496 = load ptr, ptr %$t1656.addr
  %cr497 = call ptr (ptr, ptr, ptr) %fv494(ptr %ld492, ptr %ld495, ptr %ld496)
  store ptr %cr497, ptr %res_slot459
  br label %case_merge67
case_default68:
  unreachable
case_merge67:
  %case_r498 = load ptr, ptr %res_slot459
  ret ptr %case_r498
}

define ptr @go$apply$27(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld499 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld499, ptr %go.addr
  %ld500 = load ptr, ptr %lst.addr
  %res_slot501 = alloca ptr
  %tgp502 = getelementptr i8, ptr %ld500, i64 8
  %tag503 = load i32, ptr %tgp502, align 4
  switch i32 %tag503, label %case_default75 [
      i32 0, label %case_br76
      i32 1, label %case_br77
  ]
case_br76:
  %ld504 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld504)
  %ld505 = load ptr, ptr %acc.addr
  store ptr %ld505, ptr %res_slot501
  br label %case_merge74
case_br77:
  %fp506 = getelementptr i8, ptr %ld500, i64 16
  %fv507 = load ptr, ptr %fp506, align 8
  %$f1353.addr = alloca ptr
  store ptr %fv507, ptr %$f1353.addr
  %fp508 = getelementptr i8, ptr %ld500, i64 24
  %fv509 = load ptr, ptr %fp508, align 8
  %$f1354.addr = alloca ptr
  store ptr %fv509, ptr %$f1354.addr
  %ld510 = load ptr, ptr %$f1354.addr
  %t.addr = alloca ptr
  store ptr %ld510, ptr %t.addr
  %ld511 = load ptr, ptr %$f1353.addr
  %h.addr = alloca ptr
  store ptr %ld511, ptr %h.addr
  %ld512 = load ptr, ptr %lst.addr
  %ld513 = load ptr, ptr %h.addr
  %ld514 = load ptr, ptr %acc.addr
  %rc515 = load i64, ptr %ld512, align 8
  %uniq516 = icmp eq i64 %rc515, 1
  %fbip_slot517 = alloca ptr
  br i1 %uniq516, label %fbip_reuse78, label %fbip_fresh79
fbip_reuse78:
  %tgp518 = getelementptr i8, ptr %ld512, i64 8
  store i32 1, ptr %tgp518, align 4
  %fp519 = getelementptr i8, ptr %ld512, i64 16
  store ptr %ld513, ptr %fp519, align 8
  %fp520 = getelementptr i8, ptr %ld512, i64 24
  store ptr %ld514, ptr %fp520, align 8
  store ptr %ld512, ptr %fbip_slot517
  br label %fbip_merge80
fbip_fresh79:
  call void @march_decrc(ptr %ld512)
  %hp521 = call ptr @march_alloc(i64 32)
  %tgp522 = getelementptr i8, ptr %hp521, i64 8
  store i32 1, ptr %tgp522, align 4
  %fp523 = getelementptr i8, ptr %hp521, i64 16
  store ptr %ld513, ptr %fp523, align 8
  %fp524 = getelementptr i8, ptr %hp521, i64 24
  store ptr %ld514, ptr %fp524, align 8
  store ptr %hp521, ptr %fbip_slot517
  br label %fbip_merge80
fbip_merge80:
  %fbip_r525 = load ptr, ptr %fbip_slot517
  %$t1352.addr = alloca ptr
  store ptr %fbip_r525, ptr %$t1352.addr
  %ld526 = load ptr, ptr %go.addr
  %fp527 = getelementptr i8, ptr %ld526, i64 16
  %fv528 = load ptr, ptr %fp527, align 8
  %ld529 = load ptr, ptr %t.addr
  %ld530 = load ptr, ptr %$t1352.addr
  %cr531 = call ptr (ptr, ptr, ptr) %fv528(ptr %ld526, ptr %ld529, ptr %ld530)
  store ptr %cr531, ptr %res_slot501
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r532 = load ptr, ptr %res_slot501
  ret ptr %case_r532
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
