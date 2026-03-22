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
  %$f2006.addr = alloca i64
  store i64 %fv8, ptr %$f2006.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load ptr, ptr %fp9, align 8
  %$f2007.addr = alloca ptr
  store ptr %fv10, ptr %$f2007.addr
  %freed11 = call i64 @march_decrc_freed(ptr %ld1)
  %freed_b12 = icmp ne i64 %freed11, 0
  br i1 %freed_b12, label %br_unique5, label %br_shared6
br_shared6:
  call void @march_incrc(ptr %fv10)
  br label %br_body7
br_unique5:
  br label %br_body7
br_body7:
  %ld13 = load ptr, ptr %$f2007.addr
  %t.addr = alloca ptr
  store ptr %ld13, ptr %t.addr
  %ld14 = load i64, ptr %$f2006.addr
  %h.addr = alloca i64
  store i64 %ld14, ptr %h.addr
  %hp15 = call ptr @march_alloc(i64 32)
  %tgp16 = getelementptr i8, ptr %hp15, i64 8
  store i32 1, ptr %tgp16, align 4
  %ld17 = load i64, ptr %h.addr
  %fp18 = getelementptr i8, ptr %hp15, i64 16
  store i64 %ld17, ptr %fp18, align 8
  %ld19 = load ptr, ptr %acc.addr
  %fp20 = getelementptr i8, ptr %hp15, i64 24
  store ptr %ld19, ptr %fp20, align 8
  %$t2005.addr = alloca ptr
  store ptr %hp15, ptr %$t2005.addr
  %ld21 = load ptr, ptr %t.addr
  %ld22 = load ptr, ptr %$t2005.addr
  %cr23 = call ptr @irev(ptr %ld21, ptr %ld22)
  store ptr %cr23, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r24 = load ptr, ptr %res_slot2
  ret ptr %case_r24
}

define ptr @irange_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld25 = load i64, ptr %lo.addr
  %ld26 = load i64, ptr %hi.addr
  %cmp27 = icmp sgt i64 %ld25, %ld26
  %ar28 = zext i1 %cmp27 to i64
  %$t2008.addr = alloca i64
  store i64 %ar28, ptr %$t2008.addr
  %ld29 = load i64, ptr %$t2008.addr
  %res_slot30 = alloca ptr
  switch i64 %ld29, label %case_default9 [
      i64 1, label %case_br10
  ]
case_br10:
  %ld31 = load ptr, ptr %acc.addr
  store ptr %ld31, ptr %res_slot30
  br label %case_merge8
case_default9:
  %ld32 = load i64, ptr %lo.addr
  %ar33 = add i64 %ld32, 1
  %$t2009.addr = alloca i64
  store i64 %ar33, ptr %$t2009.addr
  %hp34 = call ptr @march_alloc(i64 32)
  %tgp35 = getelementptr i8, ptr %hp34, i64 8
  store i32 1, ptr %tgp35, align 4
  %ld36 = load i64, ptr %lo.addr
  %fp37 = getelementptr i8, ptr %hp34, i64 16
  store i64 %ld36, ptr %fp37, align 8
  %ld38 = load ptr, ptr %acc.addr
  %fp39 = getelementptr i8, ptr %hp34, i64 24
  store ptr %ld38, ptr %fp39, align 8
  %$t2010.addr = alloca ptr
  store ptr %hp34, ptr %$t2010.addr
  %ld40 = load i64, ptr %$t2009.addr
  %ld41 = load i64, ptr %hi.addr
  %ld42 = load ptr, ptr %$t2010.addr
  %cr43 = call ptr @irange_acc(i64 %ld40, i64 %ld41, ptr %ld42)
  store ptr %cr43, ptr %res_slot30
  br label %case_merge8
case_merge8:
  %case_r44 = load ptr, ptr %res_slot30
  ret ptr %case_r44
}

define ptr @imap_acc(ptr %xs.arg, ptr %f.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld45 = load ptr, ptr %xs.addr
  %res_slot46 = alloca ptr
  %tgp47 = getelementptr i8, ptr %ld45, i64 8
  %tag48 = load i32, ptr %tgp47, align 4
  switch i32 %tag48, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld49 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld49)
  %ld50 = load ptr, ptr %acc.addr
  store ptr %ld50, ptr %res_slot46
  br label %case_merge11
case_br14:
  %fp51 = getelementptr i8, ptr %ld45, i64 16
  %fv52 = load i64, ptr %fp51, align 8
  %$f2016.addr = alloca i64
  store i64 %fv52, ptr %$f2016.addr
  %fp53 = getelementptr i8, ptr %ld45, i64 24
  %fv54 = load ptr, ptr %fp53, align 8
  %$f2017.addr = alloca ptr
  store ptr %fv54, ptr %$f2017.addr
  %freed55 = call i64 @march_decrc_freed(ptr %ld45)
  %freed_b56 = icmp ne i64 %freed55, 0
  br i1 %freed_b56, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv54)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %ld57 = load ptr, ptr %$f2017.addr
  %t.addr = alloca ptr
  store ptr %ld57, ptr %t.addr
  %ld58 = load i64, ptr %$f2016.addr
  %h.addr = alloca i64
  store i64 %ld58, ptr %h.addr
  %ld59 = load ptr, ptr %f.addr
  %fp60 = getelementptr i8, ptr %ld59, i64 16
  %fv61 = load ptr, ptr %fp60, align 8
  %ld62 = load i64, ptr %h.addr
  %cr63 = call i64 (ptr, i64) %fv61(ptr %ld59, i64 %ld62)
  %$t2014.addr = alloca i64
  store i64 %cr63, ptr %$t2014.addr
  %hp64 = call ptr @march_alloc(i64 32)
  %tgp65 = getelementptr i8, ptr %hp64, i64 8
  store i32 1, ptr %tgp65, align 4
  %ld66 = load i64, ptr %$t2014.addr
  %fp67 = getelementptr i8, ptr %hp64, i64 16
  store i64 %ld66, ptr %fp67, align 8
  %ld68 = load ptr, ptr %acc.addr
  %fp69 = getelementptr i8, ptr %hp64, i64 24
  store ptr %ld68, ptr %fp69, align 8
  %$t2015.addr = alloca ptr
  store ptr %hp64, ptr %$t2015.addr
  %ld70 = load ptr, ptr %t.addr
  %ld71 = load ptr, ptr %f.addr
  %ld72 = load ptr, ptr %$t2015.addr
  %cr73 = call ptr @imap_acc(ptr %ld70, ptr %ld71, ptr %ld72)
  store ptr %cr73, ptr %res_slot46
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r74 = load ptr, ptr %res_slot46
  ret ptr %case_r74
}

define ptr @ifilter_acc(ptr %xs.arg, ptr %pred.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %pred.addr = alloca ptr
  store ptr %pred.arg, ptr %pred.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld75 = load ptr, ptr %xs.addr
  %res_slot76 = alloca ptr
  %tgp77 = getelementptr i8, ptr %ld75, i64 8
  %tag78 = load i32, ptr %tgp77, align 4
  switch i32 %tag78, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld79 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld79)
  %ld80 = load ptr, ptr %acc.addr
  store ptr %ld80, ptr %res_slot76
  br label %case_merge18
case_br21:
  %fp81 = getelementptr i8, ptr %ld75, i64 16
  %fv82 = load i64, ptr %fp81, align 8
  %$f2023.addr = alloca i64
  store i64 %fv82, ptr %$f2023.addr
  %fp83 = getelementptr i8, ptr %ld75, i64 24
  %fv84 = load ptr, ptr %fp83, align 8
  %$f2024.addr = alloca ptr
  store ptr %fv84, ptr %$f2024.addr
  %freed85 = call i64 @march_decrc_freed(ptr %ld75)
  %freed_b86 = icmp ne i64 %freed85, 0
  br i1 %freed_b86, label %br_unique22, label %br_shared23
br_shared23:
  call void @march_incrc(ptr %fv84)
  br label %br_body24
br_unique22:
  br label %br_body24
br_body24:
  %ld87 = load ptr, ptr %$f2024.addr
  %t.addr = alloca ptr
  store ptr %ld87, ptr %t.addr
  %ld88 = load i64, ptr %$f2023.addr
  %h.addr = alloca i64
  store i64 %ld88, ptr %h.addr
  %ld89 = load ptr, ptr %pred.addr
  %fp90 = getelementptr i8, ptr %ld89, i64 16
  %fv91 = load ptr, ptr %fp90, align 8
  %ld92 = load i64, ptr %h.addr
  %cr93 = call i64 (ptr, i64) %fv91(ptr %ld89, i64 %ld92)
  %$t2021.addr = alloca i64
  store i64 %cr93, ptr %$t2021.addr
  %ld94 = load i64, ptr %$t2021.addr
  %res_slot95 = alloca ptr
  switch i64 %ld94, label %case_default26 [
      i64 1, label %case_br27
  ]
case_br27:
  %hp96 = call ptr @march_alloc(i64 32)
  %tgp97 = getelementptr i8, ptr %hp96, i64 8
  store i32 1, ptr %tgp97, align 4
  %ld98 = load i64, ptr %h.addr
  %fp99 = getelementptr i8, ptr %hp96, i64 16
  store i64 %ld98, ptr %fp99, align 8
  %ld100 = load ptr, ptr %acc.addr
  %fp101 = getelementptr i8, ptr %hp96, i64 24
  store ptr %ld100, ptr %fp101, align 8
  %$t2022.addr = alloca ptr
  store ptr %hp96, ptr %$t2022.addr
  %ld102 = load ptr, ptr %t.addr
  %ld103 = load ptr, ptr %pred.addr
  %ld104 = load ptr, ptr %$t2022.addr
  %cr105 = call ptr @ifilter_acc(ptr %ld102, ptr %ld103, ptr %ld104)
  store ptr %cr105, ptr %res_slot95
  br label %case_merge25
case_default26:
  %ld106 = load ptr, ptr %t.addr
  %ld107 = load ptr, ptr %pred.addr
  %ld108 = load ptr, ptr %acc.addr
  %cr109 = call ptr @ifilter_acc(ptr %ld106, ptr %ld107, ptr %ld108)
  store ptr %cr109, ptr %res_slot95
  br label %case_merge25
case_merge25:
  %case_r110 = load ptr, ptr %res_slot95
  store ptr %case_r110, ptr %res_slot76
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r111 = load ptr, ptr %res_slot76
  ret ptr %case_r111
}

define i64 @ifold(ptr %xs.arg, i64 %acc.arg, ptr %f.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld112 = load ptr, ptr %xs.addr
  %res_slot113 = alloca ptr
  %tgp114 = getelementptr i8, ptr %ld112, i64 8
  %tag115 = load i32, ptr %tgp114, align 4
  switch i32 %tag115, label %case_default29 [
      i32 0, label %case_br30
      i32 1, label %case_br31
  ]
case_br30:
  %ld116 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld116)
  %ld117 = load i64, ptr %acc.addr
  %cv118 = inttoptr i64 %ld117 to ptr
  store ptr %cv118, ptr %res_slot113
  br label %case_merge28
case_br31:
  %fp119 = getelementptr i8, ptr %ld112, i64 16
  %fv120 = load i64, ptr %fp119, align 8
  %$f2029.addr = alloca i64
  store i64 %fv120, ptr %$f2029.addr
  %fp121 = getelementptr i8, ptr %ld112, i64 24
  %fv122 = load ptr, ptr %fp121, align 8
  %$f2030.addr = alloca ptr
  store ptr %fv122, ptr %$f2030.addr
  %freed123 = call i64 @march_decrc_freed(ptr %ld112)
  %freed_b124 = icmp ne i64 %freed123, 0
  br i1 %freed_b124, label %br_unique32, label %br_shared33
br_shared33:
  call void @march_incrc(ptr %fv122)
  br label %br_body34
br_unique32:
  br label %br_body34
br_body34:
  %ld125 = load ptr, ptr %$f2030.addr
  %t.addr = alloca ptr
  store ptr %ld125, ptr %t.addr
  %ld126 = load i64, ptr %$f2029.addr
  %h.addr = alloca i64
  store i64 %ld126, ptr %h.addr
  %ld127 = load ptr, ptr %f.addr
  %fp128 = getelementptr i8, ptr %ld127, i64 16
  %fv129 = load ptr, ptr %fp128, align 8
  %ld130 = load i64, ptr %acc.addr
  %ld131 = load i64, ptr %h.addr
  %cr132 = call i64 (ptr, i64, i64) %fv129(ptr %ld127, i64 %ld130, i64 %ld131)
  %$t2028.addr = alloca i64
  store i64 %cr132, ptr %$t2028.addr
  %ld133 = load ptr, ptr %t.addr
  %ld134 = load i64, ptr %$t2028.addr
  %ld135 = load ptr, ptr %f.addr
  %cr136 = call i64 @ifold(ptr %ld133, i64 %ld134, ptr %ld135)
  %cv137 = inttoptr i64 %cr136 to ptr
  store ptr %cv137, ptr %res_slot113
  br label %case_merge28
case_default29:
  unreachable
case_merge28:
  %case_r138 = load ptr, ptr %res_slot113
  %cv139 = ptrtoint ptr %case_r138 to i64
  ret i64 %cv139
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 1000000, ptr %n.addr
  %lo_i33.addr = alloca i64
  store i64 1, ptr %lo_i33.addr
  %ld140 = load i64, ptr %n.addr
  %hi_i34.addr = alloca i64
  store i64 %ld140, ptr %hi_i34.addr
  %hp141 = call ptr @march_alloc(i64 16)
  %tgp142 = getelementptr i8, ptr %hp141, i64 8
  store i32 0, ptr %tgp142, align 4
  %$t2011_i35.addr = alloca ptr
  store ptr %hp141, ptr %$t2011_i35.addr
  %ld143 = load i64, ptr %lo_i33.addr
  %ld144 = load i64, ptr %hi_i34.addr
  %ld145 = load ptr, ptr %$t2011_i35.addr
  %cr146 = call ptr @irange_acc(i64 %ld143, i64 %ld144, ptr %ld145)
  %$t2012_i36.addr = alloca ptr
  store ptr %cr146, ptr %$t2012_i36.addr
  %hp147 = call ptr @march_alloc(i64 16)
  %tgp148 = getelementptr i8, ptr %hp147, i64 8
  store i32 0, ptr %tgp148, align 4
  %$t2013_i37.addr = alloca ptr
  store ptr %hp147, ptr %$t2013_i37.addr
  %ld149 = load ptr, ptr %$t2012_i36.addr
  %ld150 = load ptr, ptr %$t2013_i37.addr
  %cr151 = call ptr @irev(ptr %ld149, ptr %ld150)
  %xs.addr = alloca ptr
  store ptr %cr151, ptr %xs.addr
  %hp152 = call ptr @march_alloc(i64 24)
  %tgp153 = getelementptr i8, ptr %hp152, i64 8
  store i32 0, ptr %tgp153, align 4
  %fp154 = getelementptr i8, ptr %hp152, i64 16
  store ptr @$lam2031$apply$22, ptr %fp154, align 8
  %$t2032.addr = alloca ptr
  store ptr %hp152, ptr %$t2032.addr
  %ld155 = load ptr, ptr %xs.addr
  %xs_i28.addr = alloca ptr
  store ptr %ld155, ptr %xs_i28.addr
  %ld156 = load ptr, ptr %$t2032.addr
  %f_i29.addr = alloca ptr
  store ptr %ld156, ptr %f_i29.addr
  %hp157 = call ptr @march_alloc(i64 16)
  %tgp158 = getelementptr i8, ptr %hp157, i64 8
  store i32 0, ptr %tgp158, align 4
  %$t2018_i30.addr = alloca ptr
  store ptr %hp157, ptr %$t2018_i30.addr
  %ld159 = load ptr, ptr %xs_i28.addr
  %ld160 = load ptr, ptr %f_i29.addr
  %ld161 = load ptr, ptr %$t2018_i30.addr
  %cr162 = call ptr @imap_acc(ptr %ld159, ptr %ld160, ptr %ld161)
  %$t2019_i31.addr = alloca ptr
  store ptr %cr162, ptr %$t2019_i31.addr
  %hp163 = call ptr @march_alloc(i64 16)
  %tgp164 = getelementptr i8, ptr %hp163, i64 8
  store i32 0, ptr %tgp164, align 4
  %$t2020_i32.addr = alloca ptr
  store ptr %hp163, ptr %$t2020_i32.addr
  %ld165 = load ptr, ptr %$t2019_i31.addr
  %ld166 = load ptr, ptr %$t2020_i32.addr
  %cr167 = call ptr @irev(ptr %ld165, ptr %ld166)
  %ys.addr = alloca ptr
  store ptr %cr167, ptr %ys.addr
  %hp168 = call ptr @march_alloc(i64 24)
  %tgp169 = getelementptr i8, ptr %hp168, i64 8
  store i32 0, ptr %tgp169, align 4
  %fp170 = getelementptr i8, ptr %hp168, i64 16
  store ptr @$lam2033$apply$23, ptr %fp170, align 8
  %$t2035.addr = alloca ptr
  store ptr %hp168, ptr %$t2035.addr
  %ld171 = load ptr, ptr %ys.addr
  %xs_i23.addr = alloca ptr
  store ptr %ld171, ptr %xs_i23.addr
  %ld172 = load ptr, ptr %$t2035.addr
  %pred_i24.addr = alloca ptr
  store ptr %ld172, ptr %pred_i24.addr
  %hp173 = call ptr @march_alloc(i64 16)
  %tgp174 = getelementptr i8, ptr %hp173, i64 8
  store i32 0, ptr %tgp174, align 4
  %$t2025_i25.addr = alloca ptr
  store ptr %hp173, ptr %$t2025_i25.addr
  %ld175 = load ptr, ptr %xs_i23.addr
  %ld176 = load ptr, ptr %pred_i24.addr
  %ld177 = load ptr, ptr %$t2025_i25.addr
  %cr178 = call ptr @ifilter_acc(ptr %ld175, ptr %ld176, ptr %ld177)
  %$t2026_i26.addr = alloca ptr
  store ptr %cr178, ptr %$t2026_i26.addr
  %hp179 = call ptr @march_alloc(i64 16)
  %tgp180 = getelementptr i8, ptr %hp179, i64 8
  store i32 0, ptr %tgp180, align 4
  %$t2027_i27.addr = alloca ptr
  store ptr %hp179, ptr %$t2027_i27.addr
  %ld181 = load ptr, ptr %$t2026_i26.addr
  %ld182 = load ptr, ptr %$t2027_i27.addr
  %cr183 = call ptr @irev(ptr %ld181, ptr %ld182)
  %zs.addr = alloca ptr
  store ptr %cr183, ptr %zs.addr
  %hp184 = call ptr @march_alloc(i64 24)
  %tgp185 = getelementptr i8, ptr %hp184, i64 8
  store i32 0, ptr %tgp185, align 4
  %fp186 = getelementptr i8, ptr %hp184, i64 16
  store ptr @$lam2036$apply$24, ptr %fp186, align 8
  %$t2037.addr = alloca ptr
  store ptr %hp184, ptr %$t2037.addr
  %ld187 = load ptr, ptr %zs.addr
  %ld188 = load ptr, ptr %$t2037.addr
  %cr189 = call i64 @ifold(ptr %ld187, i64 0, ptr %ld188)
  %total.addr = alloca i64
  store i64 %cr189, ptr %total.addr
  %ld190 = load i64, ptr %total.addr
  %cr191 = call ptr @march_int_to_string(i64 %ld190)
  %$t2038.addr = alloca ptr
  store ptr %cr191, ptr %$t2038.addr
  %ld192 = load ptr, ptr %$t2038.addr
  call void @march_println(ptr %ld192)
  ret void
}

define i64 @$lam2031$apply$22(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld193 = load i64, ptr %x.addr
  %ld194 = load i64, ptr %x.addr
  %ar195 = add i64 %ld193, %ld194
  %sr_s1.addr = alloca i64
  store i64 %ar195, ptr %sr_s1.addr
  %ld196 = load i64, ptr %sr_s1.addr
  ret i64 %ld196
}

define i64 @$lam2033$apply$23(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld197 = load i64, ptr %x.addr
  %ar198 = srem i64 %ld197, 3
  %$t2034.addr = alloca i64
  store i64 %ar198, ptr %$t2034.addr
  %ld199 = load i64, ptr %$t2034.addr
  %cmp200 = icmp eq i64 %ld199, 0
  %ar201 = zext i1 %cmp200 to i64
  ret i64 %ar201
}

define i64 @$lam2036$apply$24(ptr %$clo.arg, i64 %a.arg, i64 %b.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %ld202 = load i64, ptr %a.addr
  %ld203 = load i64, ptr %b.addr
  %ar204 = add i64 %ld202, %ld203
  ret i64 %ar204
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
