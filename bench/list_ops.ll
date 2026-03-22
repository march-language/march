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


define ptr @irev(ptr %xs.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load ptr, ptr %xs.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld5 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld5)
  %ld6 = load ptr, ptr %acc.addr
  store ptr %ld6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp7 = getelementptr i8, ptr %ld1, i64 16
  %fv8 = load i64, ptr %fp7, align 8
  %$f2010.addr = alloca i64
  store i64 %fv8, ptr %$f2010.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load ptr, ptr %fp9, align 8
  %$f2011.addr = alloca ptr
  store ptr %fv10, ptr %$f2011.addr
  %ld11 = load ptr, ptr %$f2011.addr
  %t.addr = alloca ptr
  store ptr %ld11, ptr %t.addr
  %ld12 = load i64, ptr %$f2010.addr
  %h.addr = alloca i64
  store i64 %ld12, ptr %h.addr
  %ld13 = load ptr, ptr %xs.addr
  %ld14 = load i64, ptr %h.addr
  %ld15 = load ptr, ptr %acc.addr
  %rc16 = load i64, ptr %ld13, align 8
  %uniq17 = icmp eq i64 %rc16, 1
  %fbip_slot18 = alloca ptr
  br i1 %uniq17, label %fbip_reuse5, label %fbip_fresh6
fbip_reuse5:
  %tgp19 = getelementptr i8, ptr %ld13, i64 8
  store i32 1, ptr %tgp19, align 4
  %fp20 = getelementptr i8, ptr %ld13, i64 16
  store i64 %ld14, ptr %fp20, align 8
  %fp21 = getelementptr i8, ptr %ld13, i64 24
  store ptr %ld15, ptr %fp21, align 8
  store ptr %ld13, ptr %fbip_slot18
  br label %fbip_merge7
fbip_fresh6:
  call void @march_decrc(ptr %ld13)
  %hp22 = call ptr @march_alloc(i64 32)
  %tgp23 = getelementptr i8, ptr %hp22, i64 8
  store i32 1, ptr %tgp23, align 4
  %fp24 = getelementptr i8, ptr %hp22, i64 16
  store i64 %ld14, ptr %fp24, align 8
  %fp25 = getelementptr i8, ptr %hp22, i64 24
  store ptr %ld15, ptr %fp25, align 8
  store ptr %hp22, ptr %fbip_slot18
  br label %fbip_merge7
fbip_merge7:
  %fbip_r26 = load ptr, ptr %fbip_slot18
  %$t2009.addr = alloca ptr
  store ptr %fbip_r26, ptr %$t2009.addr
  %ld27 = load ptr, ptr %t.addr
  %ld28 = load ptr, ptr %$t2009.addr
  %cr29 = call ptr @irev(ptr %ld27, ptr %ld28)
  store ptr %cr29, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r30 = load ptr, ptr %res_slot2
  ret ptr %case_r30
}

define ptr @irange_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld31 = load i64, ptr %lo.addr
  %ld32 = load i64, ptr %hi.addr
  %cmp33 = icmp sgt i64 %ld31, %ld32
  %ar34 = zext i1 %cmp33 to i64
  %$t2012.addr = alloca i64
  store i64 %ar34, ptr %$t2012.addr
  %ld35 = load i64, ptr %$t2012.addr
  %res_slot36 = alloca ptr
  %bi37 = trunc i64 %ld35 to i1
  br i1 %bi37, label %case_br10, label %case_default9
case_br10:
  %ld38 = load ptr, ptr %acc.addr
  store ptr %ld38, ptr %res_slot36
  br label %case_merge8
case_default9:
  %ld39 = load i64, ptr %lo.addr
  %ar40 = add i64 %ld39, 1
  %$t2013.addr = alloca i64
  store i64 %ar40, ptr %$t2013.addr
  %hp41 = call ptr @march_alloc(i64 32)
  %tgp42 = getelementptr i8, ptr %hp41, i64 8
  store i32 1, ptr %tgp42, align 4
  %ld43 = load i64, ptr %lo.addr
  %fp44 = getelementptr i8, ptr %hp41, i64 16
  store i64 %ld43, ptr %fp44, align 8
  %ld45 = load ptr, ptr %acc.addr
  %fp46 = getelementptr i8, ptr %hp41, i64 24
  store ptr %ld45, ptr %fp46, align 8
  %$t2014.addr = alloca ptr
  store ptr %hp41, ptr %$t2014.addr
  %ld47 = load i64, ptr %$t2013.addr
  %ld48 = load i64, ptr %hi.addr
  %ld49 = load ptr, ptr %$t2014.addr
  %cr50 = call ptr @irange_acc(i64 %ld47, i64 %ld48, ptr %ld49)
  store ptr %cr50, ptr %res_slot36
  br label %case_merge8
case_merge8:
  %case_r51 = load ptr, ptr %res_slot36
  ret ptr %case_r51
}

define ptr @imap_acc(ptr %xs.arg, ptr %f.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld52 = load ptr, ptr %xs.addr
  %res_slot53 = alloca ptr
  %tgp54 = getelementptr i8, ptr %ld52, i64 8
  %tag55 = load i32, ptr %tgp54, align 4
  switch i32 %tag55, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld56 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld56)
  %ld57 = load ptr, ptr %acc.addr
  store ptr %ld57, ptr %res_slot53
  br label %case_merge11
case_br14:
  %fp58 = getelementptr i8, ptr %ld52, i64 16
  %fv59 = load i64, ptr %fp58, align 8
  %$f2020.addr = alloca i64
  store i64 %fv59, ptr %$f2020.addr
  %fp60 = getelementptr i8, ptr %ld52, i64 24
  %fv61 = load ptr, ptr %fp60, align 8
  %$f2021.addr = alloca ptr
  store ptr %fv61, ptr %$f2021.addr
  %freed62 = call i64 @march_decrc_freed(ptr %ld52)
  %freed_b63 = icmp ne i64 %freed62, 0
  br i1 %freed_b63, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv61)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %ld64 = load ptr, ptr %$f2021.addr
  %t.addr = alloca ptr
  store ptr %ld64, ptr %t.addr
  %ld65 = load i64, ptr %$f2020.addr
  %h.addr = alloca i64
  store i64 %ld65, ptr %h.addr
  %ld66 = load ptr, ptr %f.addr
  %fp67 = getelementptr i8, ptr %ld66, i64 16
  %fv68 = load ptr, ptr %fp67, align 8
  %ld69 = load i64, ptr %h.addr
  %cr70 = call i64 (ptr, i64) %fv68(ptr %ld66, i64 %ld69)
  %$t2018.addr = alloca i64
  store i64 %cr70, ptr %$t2018.addr
  %hp71 = call ptr @march_alloc(i64 32)
  %tgp72 = getelementptr i8, ptr %hp71, i64 8
  store i32 1, ptr %tgp72, align 4
  %ld73 = load i64, ptr %$t2018.addr
  %fp74 = getelementptr i8, ptr %hp71, i64 16
  store i64 %ld73, ptr %fp74, align 8
  %ld75 = load ptr, ptr %acc.addr
  %fp76 = getelementptr i8, ptr %hp71, i64 24
  store ptr %ld75, ptr %fp76, align 8
  %$t2019.addr = alloca ptr
  store ptr %hp71, ptr %$t2019.addr
  %ld77 = load ptr, ptr %t.addr
  %ld78 = load ptr, ptr %f.addr
  %ld79 = load ptr, ptr %$t2019.addr
  %cr80 = call ptr @imap_acc(ptr %ld77, ptr %ld78, ptr %ld79)
  store ptr %cr80, ptr %res_slot53
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r81 = load ptr, ptr %res_slot53
  ret ptr %case_r81
}

define ptr @ifilter_acc(ptr %xs.arg, ptr %pred.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld82 = load ptr, ptr %xs.addr
  %res_slot83 = alloca ptr
  %tgp84 = getelementptr i8, ptr %ld82, i64 8
  %tag85 = load i32, ptr %tgp84, align 4
  switch i32 %tag85, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld86 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld86)
  %ld87 = load ptr, ptr %acc.addr
  store ptr %ld87, ptr %res_slot83
  br label %case_merge18
case_br21:
  %fp88 = getelementptr i8, ptr %ld82, i64 16
  %fv89 = load i64, ptr %fp88, align 8
  %$f2027.addr = alloca i64
  store i64 %fv89, ptr %$f2027.addr
  %fp90 = getelementptr i8, ptr %ld82, i64 24
  %fv91 = load ptr, ptr %fp90, align 8
  %$f2028.addr = alloca ptr
  store ptr %fv91, ptr %$f2028.addr
  %freed92 = call i64 @march_decrc_freed(ptr %ld82)
  %freed_b93 = icmp ne i64 %freed92, 0
  br i1 %freed_b93, label %br_unique22, label %br_shared23
br_shared23:
  call void @march_incrc(ptr %fv91)
  br label %br_body24
br_unique22:
  br label %br_body24
br_body24:
  %ld94 = load ptr, ptr %$f2028.addr
  %t.addr = alloca ptr
  store ptr %ld94, ptr %t.addr
  %ld95 = load i64, ptr %$f2027.addr
  %h.addr = alloca i64
  store i64 %ld95, ptr %h.addr
  %ld96 = load ptr, ptr %pred.addr
  %fp97 = getelementptr i8, ptr %ld96, i64 16
  %fv98 = load ptr, ptr %fp97, align 8
  %ld99 = load i64, ptr %h.addr
  %cr100 = call i64 (ptr, i64) %fv98(ptr %ld96, i64 %ld99)
  %$t2025.addr = alloca i64
  store i64 %cr100, ptr %$t2025.addr
  %ld101 = load i64, ptr %$t2025.addr
  %res_slot102 = alloca ptr
  %bi103 = trunc i64 %ld101 to i1
  br i1 %bi103, label %case_br27, label %case_default26
case_br27:
  %hp104 = call ptr @march_alloc(i64 32)
  %tgp105 = getelementptr i8, ptr %hp104, i64 8
  store i32 1, ptr %tgp105, align 4
  %ld106 = load i64, ptr %h.addr
  %fp107 = getelementptr i8, ptr %hp104, i64 16
  store i64 %ld106, ptr %fp107, align 8
  %ld108 = load ptr, ptr %acc.addr
  %fp109 = getelementptr i8, ptr %hp104, i64 24
  store ptr %ld108, ptr %fp109, align 8
  %$t2026.addr = alloca ptr
  store ptr %hp104, ptr %$t2026.addr
  %ld110 = load ptr, ptr %t.addr
  %ld111 = load ptr, ptr %pred.addr
  %ld112 = load ptr, ptr %$t2026.addr
  %cr113 = call ptr @ifilter_acc(ptr %ld110, ptr %ld111, ptr %ld112)
  store ptr %cr113, ptr %res_slot102
  br label %case_merge25
case_default26:
  %ld114 = load ptr, ptr %t.addr
  %ld115 = load ptr, ptr %pred.addr
  %ld116 = load ptr, ptr %acc.addr
  %cr117 = call ptr @ifilter_acc(ptr %ld114, ptr %ld115, ptr %ld116)
  store ptr %cr117, ptr %res_slot102
  br label %case_merge25
case_merge25:
  %case_r118 = load ptr, ptr %res_slot102
  store ptr %case_r118, ptr %res_slot83
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r119 = load ptr, ptr %res_slot83
  ret ptr %case_r119
}

define i64 @ifold(ptr %xs.arg, i64 %acc.arg, ptr %f.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld120 = load ptr, ptr %xs.addr
  %res_slot121 = alloca ptr
  %tgp122 = getelementptr i8, ptr %ld120, i64 8
  %tag123 = load i32, ptr %tgp122, align 4
  switch i32 %tag123, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %ld124 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld124)
  %ld125 = load i64, ptr %acc.addr
  %cv126 = inttoptr i64 %ld125 to ptr
  store ptr %cv126, ptr %res_slot121
  br label %case_merge28
case_br31:
  %fp127 = getelementptr i8, ptr %ld120, i64 16
  %fv128 = load i64, ptr %fp127, align 8
  %$f2033.addr = alloca i64
  store i64 %fv128, ptr %$f2033.addr
  %fp129 = getelementptr i8, ptr %ld120, i64 24
  %fv130 = load ptr, ptr %fp129, align 8
  %$f2034.addr = alloca ptr
  store ptr %fv130, ptr %$f2034.addr
  %freed131 = call i64 @march_decrc_freed(ptr %ld120)
  %freed_b132 = icmp ne i64 %freed131, 0
  br i1 %freed_b132, label %br_unique32, label %br_shared33
br_shared33:
  call void @march_incrc(ptr %fv130)
  br label %br_body34
br_unique32:
  br label %br_body34
br_body34:
  %ld133 = load ptr, ptr %$f2034.addr
  %t.addr = alloca ptr
  store ptr %ld133, ptr %t.addr
  %ld134 = load i64, ptr %$f2033.addr
  %h.addr = alloca i64
  store i64 %ld134, ptr %h.addr
  %ld135 = load ptr, ptr %f.addr
  %fp136 = getelementptr i8, ptr %ld135, i64 16
  %fv137 = load ptr, ptr %fp136, align 8
  %ld138 = load i64, ptr %acc.addr
  %ld139 = load i64, ptr %h.addr
  %cr140 = call i64 (ptr, i64, i64) %fv137(ptr %ld135, i64 %ld138, i64 %ld139)
  %$t2032.addr = alloca i64
  store i64 %cr140, ptr %$t2032.addr
  %ld141 = load ptr, ptr %t.addr
  %ld142 = load i64, ptr %$t2032.addr
  %ld143 = load ptr, ptr %f.addr
  %cr144 = call i64 @ifold(ptr %ld141, i64 %ld142, ptr %ld143)
  %cv145 = inttoptr i64 %cr144 to ptr
  store ptr %cv145, ptr %res_slot121
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r146 = load ptr, ptr %res_slot121
  %cv147 = ptrtoint ptr %case_r146 to i64
  ret i64 %cv147
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 1000000, ptr %n.addr
  %lo_i33.addr = alloca i64
  store i64 1, ptr %lo_i33.addr
  %ld148 = load i64, ptr %n.addr
  %hi_i34.addr = alloca i64
  store i64 %ld148, ptr %hi_i34.addr
  %hp149 = call ptr @march_alloc(i64 16)
  %tgp150 = getelementptr i8, ptr %hp149, i64 8
  store i32 0, ptr %tgp150, align 4
  %$t2015_i35.addr = alloca ptr
  store ptr %hp149, ptr %$t2015_i35.addr
  %ld151 = load i64, ptr %lo_i33.addr
  %ld152 = load i64, ptr %hi_i34.addr
  %ld153 = load ptr, ptr %$t2015_i35.addr
  %cr154 = call ptr @irange_acc(i64 %ld151, i64 %ld152, ptr %ld153)
  %$t2016_i36.addr = alloca ptr
  store ptr %cr154, ptr %$t2016_i36.addr
  %hp155 = call ptr @march_alloc(i64 16)
  %tgp156 = getelementptr i8, ptr %hp155, i64 8
  store i32 0, ptr %tgp156, align 4
  %$t2017_i37.addr = alloca ptr
  store ptr %hp155, ptr %$t2017_i37.addr
  %ld157 = load ptr, ptr %$t2016_i36.addr
  %ld158 = load ptr, ptr %$t2017_i37.addr
  %cr159 = call ptr @irev(ptr %ld157, ptr %ld158)
  %xs.addr = alloca ptr
  store ptr %cr159, ptr %xs.addr
  %hp160 = call ptr @march_alloc(i64 24)
  %tgp161 = getelementptr i8, ptr %hp160, i64 8
  store i32 0, ptr %tgp161, align 4
  %fp162 = getelementptr i8, ptr %hp160, i64 16
  store ptr @$lam2035$apply$21, ptr %fp162, align 8
  %$t2036.addr = alloca ptr
  store ptr %hp160, ptr %$t2036.addr
  %ld163 = load ptr, ptr %xs.addr
  %xs_i28.addr = alloca ptr
  store ptr %ld163, ptr %xs_i28.addr
  %ld164 = load ptr, ptr %$t2036.addr
  %f_i29.addr = alloca ptr
  store ptr %ld164, ptr %f_i29.addr
  %hp165 = call ptr @march_alloc(i64 16)
  %tgp166 = getelementptr i8, ptr %hp165, i64 8
  store i32 0, ptr %tgp166, align 4
  %$t2022_i30.addr = alloca ptr
  store ptr %hp165, ptr %$t2022_i30.addr
  %ld167 = load ptr, ptr %xs_i28.addr
  %ld168 = load ptr, ptr %f_i29.addr
  %ld169 = load ptr, ptr %$t2022_i30.addr
  %cr170 = call ptr @imap_acc(ptr %ld167, ptr %ld168, ptr %ld169)
  %$t2023_i31.addr = alloca ptr
  store ptr %cr170, ptr %$t2023_i31.addr
  %hp171 = call ptr @march_alloc(i64 16)
  %tgp172 = getelementptr i8, ptr %hp171, i64 8
  store i32 0, ptr %tgp172, align 4
  %$t2024_i32.addr = alloca ptr
  store ptr %hp171, ptr %$t2024_i32.addr
  %ld173 = load ptr, ptr %$t2023_i31.addr
  %ld174 = load ptr, ptr %$t2024_i32.addr
  %cr175 = call ptr @irev(ptr %ld173, ptr %ld174)
  %ys.addr = alloca ptr
  store ptr %cr175, ptr %ys.addr
  %hp176 = call ptr @march_alloc(i64 24)
  %tgp177 = getelementptr i8, ptr %hp176, i64 8
  store i32 0, ptr %tgp177, align 4
  %fp178 = getelementptr i8, ptr %hp176, i64 16
  store ptr @$lam2037$apply$22, ptr %fp178, align 8
  %$t2039.addr = alloca ptr
  store ptr %hp176, ptr %$t2039.addr
  %ld179 = load ptr, ptr %ys.addr
  %xs_i23.addr = alloca ptr
  store ptr %ld179, ptr %xs_i23.addr
  %ld180 = load ptr, ptr %$t2039.addr
  %pred_i24.addr = alloca ptr
  store ptr %ld180, ptr %pred_i24.addr
  %hp181 = call ptr @march_alloc(i64 16)
  %tgp182 = getelementptr i8, ptr %hp181, i64 8
  store i32 0, ptr %tgp182, align 4
  %$t2029_i25.addr = alloca ptr
  store ptr %hp181, ptr %$t2029_i25.addr
  %ld183 = load ptr, ptr %xs_i23.addr
  %ld184 = load ptr, ptr %pred_i24.addr
  %ld185 = load ptr, ptr %$t2029_i25.addr
  %cr186 = call ptr @ifilter_acc(ptr %ld183, ptr %ld184, ptr %ld185)
  %$t2030_i26.addr = alloca ptr
  store ptr %cr186, ptr %$t2030_i26.addr
  %hp187 = call ptr @march_alloc(i64 16)
  %tgp188 = getelementptr i8, ptr %hp187, i64 8
  store i32 0, ptr %tgp188, align 4
  %$t2031_i27.addr = alloca ptr
  store ptr %hp187, ptr %$t2031_i27.addr
  %ld189 = load ptr, ptr %$t2030_i26.addr
  %ld190 = load ptr, ptr %$t2031_i27.addr
  %cr191 = call ptr @irev(ptr %ld189, ptr %ld190)
  %zs.addr = alloca ptr
  store ptr %cr191, ptr %zs.addr
  %hp192 = call ptr @march_alloc(i64 24)
  %tgp193 = getelementptr i8, ptr %hp192, i64 8
  store i32 0, ptr %tgp193, align 4
  %fp194 = getelementptr i8, ptr %hp192, i64 16
  store ptr @$lam2040$apply$23, ptr %fp194, align 8
  %$t2041.addr = alloca ptr
  store ptr %hp192, ptr %$t2041.addr
  %ld195 = load ptr, ptr %zs.addr
  %ld196 = load ptr, ptr %$t2041.addr
  %cr197 = call i64 @ifold(ptr %ld195, i64 0, ptr %ld196)
  %total.addr = alloca i64
  store i64 %cr197, ptr %total.addr
  %ld198 = load i64, ptr %total.addr
  %cr199 = call ptr @march_int_to_string(i64 %ld198)
  %$t2042.addr = alloca ptr
  store ptr %cr199, ptr %$t2042.addr
  %ld200 = load ptr, ptr %$t2042.addr
  call void @march_println(ptr %ld200)
  ret void
}

define i64 @$lam2035$apply$21(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld201 = load i64, ptr %x.addr
  %ld202 = load i64, ptr %x.addr
  %ar203 = add i64 %ld201, %ld202
  %sr_s1.addr = alloca i64
  store i64 %ar203, ptr %sr_s1.addr
  %ld204 = load i64, ptr %sr_s1.addr
  ret i64 %ld204
}

define i64 @$lam2037$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld205 = load i64, ptr %x.addr
  %ar206 = srem i64 %ld205, 3
  %$t2038.addr = alloca i64
  store i64 %ar206, ptr %$t2038.addr
  %ld207 = load i64, ptr %$t2038.addr
  %cmp208 = icmp eq i64 %ld207, 0
  %ar209 = zext i1 %cmp208 to i64
  ret i64 %ar209
}

define i64 @$lam2040$apply$23(ptr %$clo.arg, i64 %a.arg, i64 %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %ld210 = load i64, ptr %a.addr
  %ld211 = load i64, ptr %b.addr
  %ar212 = add i64 %ld210, %ld211
  ret i64 %ar212
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
