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

@.str1 = private unnamed_addr constant [7 x i8] c"[log] \00"
@.str2 = private unnamed_addr constant [17 x i8] c"--- sum_to(5) = \00"
@.str3 = private unnamed_addr constant [20 x i8] c"--- factorial(6) = \00"
@.str4 = private unnamed_addr constant [25 x i8] c"--- find_large result = \00"
@.str5 = private unnamed_addr constant [23 x i8] c"--- running_sum(10) = \00"
@.str6 = private unnamed_addr constant [22 x i8] c"--- count_down(10) = \00"
@.str7 = private unnamed_addr constant [22 x i8] c"--- build_trace(7) = \00"
@.str8 = private unnamed_addr constant [14 x i8] c"counter += 10\00"
@.str9 = private unnamed_addr constant [13 x i8] c"counter += 5\00"
@.str10 = private unnamed_addr constant [14 x i8] c"counter reset\00"
@.str11 = private unnamed_addr constant [13 x i8] c"counter += 3\00"
@.str12 = private unnamed_addr constant [9 x i8] c"--- done\00"

define i64 @sum_to(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca i64
  store i64 0, ptr %acc.addr
  %i.addr = alloca i64
  store i64 1, ptr %i.addr
  %ld1 = load i64, ptr %acc.addr
  %ld2 = load i64, ptr %i.addr
  %ar3 = add i64 %ld1, %ld2
  %acc_1.addr = alloca i64
  store i64 %ar3, ptr %acc_1.addr
  %ld4 = load i64, ptr %i.addr
  %ar5 = add i64 %ld4, 1
  %$t2009.addr = alloca i64
  store i64 %ar5, ptr %$t2009.addr
  %ld6 = load i64, ptr %acc_1.addr
  %ld7 = load i64, ptr %$t2009.addr
  %ar8 = add i64 %ld6, %ld7
  %acc_2.addr = alloca i64
  store i64 %ar8, ptr %acc_2.addr
  %ld9 = load i64, ptr %i.addr
  %ar10 = add i64 %ld9, 2
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %acc_2.addr
  %ld12 = load i64, ptr %$t2010.addr
  %ar13 = add i64 %ld11, %ld12
  %acc_3.addr = alloca i64
  store i64 %ar13, ptr %acc_3.addr
  %ld14 = load i64, ptr %i.addr
  %ar15 = add i64 %ld14, 3
  %$t2011.addr = alloca i64
  store i64 %ar15, ptr %$t2011.addr
  %ld16 = load i64, ptr %acc_3.addr
  %ld17 = load i64, ptr %$t2011.addr
  %ar18 = add i64 %ld16, %ld17
  %acc_4.addr = alloca i64
  store i64 %ar18, ptr %acc_4.addr
  %ld19 = load i64, ptr %i.addr
  %ar20 = add i64 %ld19, 4
  %$t2012.addr = alloca i64
  store i64 %ar20, ptr %$t2012.addr
  %ld21 = load i64, ptr %acc_4.addr
  %ld22 = load i64, ptr %$t2012.addr
  %ar23 = add i64 %ld21, %ld22
  %acc_5.addr = alloca i64
  store i64 %ar23, ptr %acc_5.addr
  %ld24 = load i64, ptr %acc_5.addr
  ret i64 %ld24
}

define i64 @factorial(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld25 = load i64, ptr %n.addr
  %cmp26 = icmp sle i64 %ld25, 1
  %ar27 = zext i1 %cmp26 to i64
  %$t2013.addr = alloca i64
  store i64 %ar27, ptr %$t2013.addr
  %ld28 = load i64, ptr %$t2013.addr
  %res_slot29 = alloca ptr
  %bi30 = trunc i64 %ld28 to i1
  br i1 %bi30, label %case_br3, label %case_default2
case_br3:
  %cv31 = inttoptr i64 1 to ptr
  store ptr %cv31, ptr %res_slot29
  br label %case_merge1
case_default2:
  %ld32 = load i64, ptr %n.addr
  %$t2014.addr = alloca i64
  store i64 %ld32, ptr %$t2014.addr
  %ld33 = load i64, ptr %n.addr
  %ar34 = sub i64 %ld33, 1
  %$t2015.addr = alloca i64
  store i64 %ar34, ptr %$t2015.addr
  %ld35 = load i64, ptr %$t2015.addr
  %cr36 = call i64 @factorial(i64 %ld35)
  %$t2016.addr = alloca i64
  store i64 %cr36, ptr %$t2016.addr
  %ld37 = load i64, ptr %$t2014.addr
  %ld38 = load i64, ptr %$t2016.addr
  %ar39 = mul i64 %ld37, %ld38
  %cv40 = inttoptr i64 %ar39 to ptr
  store ptr %cv40, ptr %res_slot29
  br label %case_merge1
case_merge1:
  %case_r41 = load ptr, ptr %res_slot29
  %cv42 = ptrtoint ptr %case_r41 to i64
  ret i64 %cv42
}

define i64 @find_large(ptr %lst.arg, i64 %threshold.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld43 = load ptr, ptr %lst.addr
  %res_slot44 = alloca ptr
  %tgp45 = getelementptr i8, ptr %ld43, i64 8
  %tag46 = load i32, ptr %tgp45, align 4
  switch i32 %tag46, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %ld47 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld47)
  %cv48 = inttoptr i64 0 to ptr
  store ptr %cv48, ptr %res_slot44
  br label %case_merge4
case_br7:
  %fp49 = getelementptr i8, ptr %ld43, i64 16
  %fv50 = load i64, ptr %fp49, align 8
  %$f2018.addr = alloca i64
  store i64 %fv50, ptr %$f2018.addr
  %fp51 = getelementptr i8, ptr %ld43, i64 24
  %fv52 = load ptr, ptr %fp51, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv52, ptr %$f2019.addr
  %freed53 = call i64 @march_decrc_freed(ptr %ld43)
  %freed_b54 = icmp ne i64 %freed53, 0
  br i1 %freed_b54, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv52)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld55 = load ptr, ptr %$f2019.addr
  %t.addr = alloca ptr
  store ptr %ld55, ptr %t.addr
  %ld56 = load i64, ptr %$f2018.addr
  %h.addr = alloca i64
  store i64 %ld56, ptr %h.addr
  %ld57 = load i64, ptr %h.addr
  %ld58 = load i64, ptr %threshold.addr
  %cmp59 = icmp sgt i64 %ld57, %ld58
  %ar60 = zext i1 %cmp59 to i64
  %ld61 = load ptr, ptr %t.addr
  %ld62 = load i64, ptr %threshold.addr
  %cr63 = call i64 @find_large(ptr %ld61, i64 %ld62)
  %$t2017.addr = alloca i64
  store i64 %cr63, ptr %$t2017.addr
  %ld64 = load i64, ptr %h.addr
  %ld65 = load i64, ptr %$t2017.addr
  %ar66 = add i64 %ld64, %ld65
  %cv67 = inttoptr i64 %ar66 to ptr
  store ptr %cv67, ptr %res_slot44
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r68 = load ptr, ptr %res_slot44
  %cv69 = ptrtoint ptr %case_r68 to i64
  ret i64 %cv69
}

define i64 @running_sum(i64 %limit.arg) {
entry:
  %limit.addr = alloca i64
  store i64 %limit.arg, ptr %limit.addr
  %a.addr = alloca i64
  store i64 1, ptr %a.addr
  %ld70 = load i64, ptr %a.addr
  %ar71 = add i64 %ld70, 2
  %b.addr = alloca i64
  store i64 %ar71, ptr %b.addr
  %ld72 = load i64, ptr %b.addr
  %ar73 = add i64 %ld72, 3
  %c.addr = alloca i64
  store i64 %ar73, ptr %c.addr
  %ld74 = load i64, ptr %c.addr
  %ar75 = add i64 %ld74, 4
  %d.addr = alloca i64
  store i64 %ar75, ptr %d.addr
  %ld76 = load i64, ptr %a.addr
  %ld77 = load i64, ptr %b.addr
  %ar78 = add i64 %ld76, %ld77
  %$t2020.addr = alloca i64
  store i64 %ar78, ptr %$t2020.addr
  %ld79 = load i64, ptr %$t2020.addr
  %ld80 = load i64, ptr %c.addr
  %ar81 = add i64 %ld79, %ld80
  %$t2021.addr = alloca i64
  store i64 %ar81, ptr %$t2021.addr
  %ld82 = load i64, ptr %$t2021.addr
  %ld83 = load i64, ptr %d.addr
  %ar84 = add i64 %ld82, %ld83
  %acc.addr = alloca i64
  store i64 %ar84, ptr %acc.addr
  %ld85 = load i64, ptr %acc.addr
  ret i64 %ld85
}

define i64 @count_down(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld86 = load i64, ptr %n.addr
  %ar87 = sub i64 %ld86, 1
  %n_1.addr = alloca i64
  store i64 %ar87, ptr %n_1.addr
  %ld88 = load i64, ptr %n_1.addr
  %ar89 = sub i64 %ld88, 1
  %n_2.addr = alloca i64
  store i64 %ar89, ptr %n_2.addr
  %ld90 = load i64, ptr %n_2.addr
  %ar91 = sub i64 %ld90, 1
  %n_3.addr = alloca i64
  store i64 %ar91, ptr %n_3.addr
  %ld92 = load i64, ptr %n_3.addr
  %ar93 = sub i64 %ld92, 1
  %n_4.addr = alloca i64
  store i64 %ar93, ptr %n_4.addr
  %ld94 = load i64, ptr %n_4.addr
  %ar95 = sub i64 %ld94, 1
  %n_5.addr = alloca i64
  store i64 %ar95, ptr %n_5.addr
  %ld96 = load i64, ptr %n_5.addr
  ret i64 %ld96
}

define void @Counter_Add(ptr %$actor.arg, i64 %n.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld97 = load ptr, ptr %$actor.addr
  %fp98 = getelementptr i8, ptr %ld97, i64 16
  %fv99 = load ptr, ptr %fp98, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv99, ptr %$dispatch_v.addr
  %ld100 = load ptr, ptr %$actor.addr
  %fp101 = getelementptr i8, ptr %ld100, i64 24
  %fv102 = load i64, ptr %fp101, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv102, ptr %$alive_v.addr
  %ld103 = load ptr, ptr %$actor.addr
  %fp104 = getelementptr i8, ptr %ld103, i64 32
  %fv105 = load i64, ptr %fp104, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv105, ptr %$sf_value.addr
  %hp106 = call ptr @march_alloc(i64 24)
  %tgp107 = getelementptr i8, ptr %hp106, i64 8
  store i32 0, ptr %tgp107, align 4
  %ld108 = load i64, ptr %$sf_value.addr
  %fp109 = getelementptr i8, ptr %hp106, i64 16
  store i64 %ld108, ptr %fp109, align 8
  %state.addr = alloca ptr
  store ptr %hp106, ptr %state.addr
  %ld110 = load ptr, ptr %state.addr
  %fp111 = getelementptr i8, ptr %ld110, i64 16
  %fv112 = load i64, ptr %fp111, align 8
  %$t2022.addr = alloca i64
  store i64 %fv112, ptr %$t2022.addr
  %ld113 = load i64, ptr %$t2022.addr
  %ld114 = load i64, ptr %n.addr
  %ar115 = add i64 %ld113, %ld114
  %$t2023.addr = alloca i64
  store i64 %ar115, ptr %$t2023.addr
  %ld116 = load ptr, ptr %state.addr
  %hp117 = call ptr @march_alloc(i64 24)
  %tgp118 = getelementptr i8, ptr %hp117, i64 8
  store i32 0, ptr %tgp118, align 4
  %fp119 = getelementptr i8, ptr %ld116, i64 16
  %fv120 = load i64, ptr %fp119, align 8
  %fp121 = getelementptr i8, ptr %hp117, i64 16
  store i64 %fv120, ptr %fp121, align 8
  %ld122 = load i64, ptr %$t2023.addr
  %fp123 = getelementptr i8, ptr %hp117, i64 16
  store i64 %ld122, ptr %fp123, align 8
  %$result.addr = alloca ptr
  store ptr %hp117, ptr %$result.addr
  %ld124 = load ptr, ptr %$result.addr
  %fp125 = getelementptr i8, ptr %ld124, i64 16
  %fv126 = load i64, ptr %fp125, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv126, ptr %$nf_value.addr
  %ld127 = load ptr, ptr %$actor.addr
  %ld128 = load ptr, ptr %$dispatch_v.addr
  %ld129 = load i64, ptr %$alive_v.addr
  %ld130 = load i64, ptr %$nf_value.addr
  %rc131 = load i64, ptr %ld127, align 8
  %uniq132 = icmp eq i64 %rc131, 1
  %fbip_slot133 = alloca ptr
  br i1 %uniq132, label %fbip_reuse11, label %fbip_fresh12
fbip_reuse11:
  %tgp134 = getelementptr i8, ptr %ld127, i64 8
  store i32 0, ptr %tgp134, align 4
  %fp135 = getelementptr i8, ptr %ld127, i64 16
  store ptr %ld128, ptr %fp135, align 8
  %fp136 = getelementptr i8, ptr %ld127, i64 24
  store i64 %ld129, ptr %fp136, align 8
  %fp137 = getelementptr i8, ptr %ld127, i64 32
  store i64 %ld130, ptr %fp137, align 8
  store ptr %ld127, ptr %fbip_slot133
  br label %fbip_merge13
fbip_fresh12:
  call void @march_decrc(ptr %ld127)
  %hp138 = call ptr @march_alloc(i64 40)
  %tgp139 = getelementptr i8, ptr %hp138, i64 8
  store i32 0, ptr %tgp139, align 4
  %fp140 = getelementptr i8, ptr %hp138, i64 16
  store ptr %ld128, ptr %fp140, align 8
  %fp141 = getelementptr i8, ptr %hp138, i64 24
  store i64 %ld129, ptr %fp141, align 8
  %fp142 = getelementptr i8, ptr %hp138, i64 32
  store i64 %ld130, ptr %fp142, align 8
  store ptr %hp138, ptr %fbip_slot133
  br label %fbip_merge13
fbip_merge13:
  %fbip_r143 = load ptr, ptr %fbip_slot133
  ret void
}

define void @Counter_Reset(ptr %$actor.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %ld144 = load ptr, ptr %$actor.addr
  %fp145 = getelementptr i8, ptr %ld144, i64 16
  %fv146 = load ptr, ptr %fp145, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv146, ptr %$dispatch_v.addr
  %ld147 = load ptr, ptr %$actor.addr
  %fp148 = getelementptr i8, ptr %ld147, i64 24
  %fv149 = load i64, ptr %fp148, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv149, ptr %$alive_v.addr
  %ld150 = load ptr, ptr %$actor.addr
  %fp151 = getelementptr i8, ptr %ld150, i64 32
  %fv152 = load i64, ptr %fp151, align 8
  %$sf_value.addr = alloca i64
  store i64 %fv152, ptr %$sf_value.addr
  %hp153 = call ptr @march_alloc(i64 24)
  %tgp154 = getelementptr i8, ptr %hp153, i64 8
  store i32 0, ptr %tgp154, align 4
  %ld155 = load i64, ptr %$sf_value.addr
  %fp156 = getelementptr i8, ptr %hp153, i64 16
  store i64 %ld155, ptr %fp156, align 8
  %state.addr = alloca ptr
  store ptr %hp153, ptr %state.addr
  %ld157 = load ptr, ptr %state.addr
  %hp158 = call ptr @march_alloc(i64 24)
  %tgp159 = getelementptr i8, ptr %hp158, i64 8
  store i32 0, ptr %tgp159, align 4
  %fp160 = getelementptr i8, ptr %ld157, i64 16
  %fv161 = load i64, ptr %fp160, align 8
  %fp162 = getelementptr i8, ptr %hp158, i64 16
  store i64 %fv161, ptr %fp162, align 8
  %fp163 = getelementptr i8, ptr %hp158, i64 16
  store i64 0, ptr %fp163, align 8
  %$result.addr = alloca ptr
  store ptr %hp158, ptr %$result.addr
  %ld164 = load ptr, ptr %$result.addr
  %fp165 = getelementptr i8, ptr %ld164, i64 16
  %fv166 = load i64, ptr %fp165, align 8
  %$nf_value.addr = alloca i64
  store i64 %fv166, ptr %$nf_value.addr
  %ld167 = load ptr, ptr %$actor.addr
  %ld168 = load ptr, ptr %$dispatch_v.addr
  %ld169 = load i64, ptr %$alive_v.addr
  %ld170 = load i64, ptr %$nf_value.addr
  %rc171 = load i64, ptr %ld167, align 8
  %uniq172 = icmp eq i64 %rc171, 1
  %fbip_slot173 = alloca ptr
  br i1 %uniq172, label %fbip_reuse14, label %fbip_fresh15
fbip_reuse14:
  %tgp174 = getelementptr i8, ptr %ld167, i64 8
  store i32 0, ptr %tgp174, align 4
  %fp175 = getelementptr i8, ptr %ld167, i64 16
  store ptr %ld168, ptr %fp175, align 8
  %fp176 = getelementptr i8, ptr %ld167, i64 24
  store i64 %ld169, ptr %fp176, align 8
  %fp177 = getelementptr i8, ptr %ld167, i64 32
  store i64 %ld170, ptr %fp177, align 8
  store ptr %ld167, ptr %fbip_slot173
  br label %fbip_merge16
fbip_fresh15:
  call void @march_decrc(ptr %ld167)
  %hp178 = call ptr @march_alloc(i64 40)
  %tgp179 = getelementptr i8, ptr %hp178, i64 8
  store i32 0, ptr %tgp179, align 4
  %fp180 = getelementptr i8, ptr %hp178, i64 16
  store ptr %ld168, ptr %fp180, align 8
  %fp181 = getelementptr i8, ptr %hp178, i64 24
  store i64 %ld169, ptr %fp181, align 8
  %fp182 = getelementptr i8, ptr %hp178, i64 32
  store i64 %ld170, ptr %fp182, align 8
  store ptr %hp178, ptr %fbip_slot173
  br label %fbip_merge16
fbip_merge16:
  %fbip_r183 = load ptr, ptr %fbip_slot173
  ret void
}

define void @Counter_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld184 = load ptr, ptr %$msg.addr
  %res_slot185 = alloca ptr
  %tgp186 = getelementptr i8, ptr %ld184, i64 8
  %tag187 = load i32, ptr %tgp186, align 4
  switch i32 %tag187, label %case_default18 [
      i32 0, label %case_br19
      i32 1, label %case_br20
  ]
case_br19:
  %fp188 = getelementptr i8, ptr %ld184, i64 16
  %fv189 = load i64, ptr %fp188, align 8
  %$Add_n.addr = alloca i64
  store i64 %fv189, ptr %$Add_n.addr
  %ld190 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld190)
  %ld191 = load ptr, ptr %$actor.addr
  %ld192 = load i64, ptr %$Add_n.addr
  call void @Counter_Add(ptr %ld191, i64 %ld192)
  %cv193 = inttoptr i64 0 to ptr
  store ptr %cv193, ptr %res_slot185
  br label %case_merge17
case_br20:
  %ld194 = load ptr, ptr %$msg.addr
  call void @march_decrc(ptr %ld194)
  %ld195 = load ptr, ptr %$actor.addr
  call void @Counter_Reset(ptr %ld195)
  %cv196 = inttoptr i64 0 to ptr
  store ptr %cv196, ptr %res_slot185
  br label %case_merge17
case_default18:
  unreachable
case_merge17:
  %case_r197 = load ptr, ptr %res_slot185
  ret void
}

define void @Logger_Record(ptr %$actor.arg, ptr %msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %msg.addr = alloca ptr
  store ptr %msg.arg, ptr %msg.addr
  %ld198 = load ptr, ptr %$actor.addr
  %fp199 = getelementptr i8, ptr %ld198, i64 16
  %fv200 = load ptr, ptr %fp199, align 8
  %$dispatch_v.addr = alloca ptr
  store ptr %fv200, ptr %$dispatch_v.addr
  %ld201 = load ptr, ptr %$actor.addr
  %fp202 = getelementptr i8, ptr %ld201, i64 24
  %fv203 = load i64, ptr %fp202, align 8
  %$alive_v.addr = alloca i64
  store i64 %fv203, ptr %$alive_v.addr
  %ld204 = load ptr, ptr %$actor.addr
  %fp205 = getelementptr i8, ptr %ld204, i64 32
  %fv206 = load i64, ptr %fp205, align 8
  %$sf_count.addr = alloca i64
  store i64 %fv206, ptr %$sf_count.addr
  %hp207 = call ptr @march_alloc(i64 24)
  %tgp208 = getelementptr i8, ptr %hp207, i64 8
  store i32 0, ptr %tgp208, align 4
  %ld209 = load i64, ptr %$sf_count.addr
  %fp210 = getelementptr i8, ptr %hp207, i64 16
  store i64 %ld209, ptr %fp210, align 8
  %state.addr = alloca ptr
  store ptr %hp207, ptr %state.addr
  %sl211 = call ptr @march_string_lit(ptr @.str1, i64 6)
  %ld212 = load ptr, ptr %msg.addr
  %cr213 = call ptr @march_string_concat(ptr %sl211, ptr %ld212)
  %$t2024.addr = alloca ptr
  store ptr %cr213, ptr %$t2024.addr
  %ld214 = load ptr, ptr %$t2024.addr
  call void @march_println(ptr %ld214)
  %ld215 = load ptr, ptr %state.addr
  %fp216 = getelementptr i8, ptr %ld215, i64 16
  %fv217 = load i64, ptr %fp216, align 8
  %$t2025.addr = alloca i64
  store i64 %fv217, ptr %$t2025.addr
  %ld218 = load i64, ptr %$t2025.addr
  %ar219 = add i64 %ld218, 1
  %$t2026.addr = alloca i64
  store i64 %ar219, ptr %$t2026.addr
  %ld220 = load ptr, ptr %state.addr
  %hp221 = call ptr @march_alloc(i64 24)
  %tgp222 = getelementptr i8, ptr %hp221, i64 8
  store i32 0, ptr %tgp222, align 4
  %fp223 = getelementptr i8, ptr %ld220, i64 16
  %fv224 = load i64, ptr %fp223, align 8
  %fp225 = getelementptr i8, ptr %hp221, i64 16
  store i64 %fv224, ptr %fp225, align 8
  %ld226 = load i64, ptr %$t2026.addr
  %fp227 = getelementptr i8, ptr %hp221, i64 16
  store i64 %ld226, ptr %fp227, align 8
  %$result.addr = alloca ptr
  store ptr %hp221, ptr %$result.addr
  %ld228 = load ptr, ptr %$result.addr
  %fp229 = getelementptr i8, ptr %ld228, i64 16
  %fv230 = load i64, ptr %fp229, align 8
  %$nf_count.addr = alloca i64
  store i64 %fv230, ptr %$nf_count.addr
  %ld231 = load ptr, ptr %$actor.addr
  %ld232 = load ptr, ptr %$dispatch_v.addr
  %ld233 = load i64, ptr %$alive_v.addr
  %ld234 = load i64, ptr %$nf_count.addr
  %rc235 = load i64, ptr %ld231, align 8
  %uniq236 = icmp eq i64 %rc235, 1
  %fbip_slot237 = alloca ptr
  br i1 %uniq236, label %fbip_reuse21, label %fbip_fresh22
fbip_reuse21:
  %tgp238 = getelementptr i8, ptr %ld231, i64 8
  store i32 0, ptr %tgp238, align 4
  %fp239 = getelementptr i8, ptr %ld231, i64 16
  store ptr %ld232, ptr %fp239, align 8
  %fp240 = getelementptr i8, ptr %ld231, i64 24
  store i64 %ld233, ptr %fp240, align 8
  %fp241 = getelementptr i8, ptr %ld231, i64 32
  store i64 %ld234, ptr %fp241, align 8
  store ptr %ld231, ptr %fbip_slot237
  br label %fbip_merge23
fbip_fresh22:
  call void @march_decrc(ptr %ld231)
  %hp242 = call ptr @march_alloc(i64 40)
  %tgp243 = getelementptr i8, ptr %hp242, i64 8
  store i32 0, ptr %tgp243, align 4
  %fp244 = getelementptr i8, ptr %hp242, i64 16
  store ptr %ld232, ptr %fp244, align 8
  %fp245 = getelementptr i8, ptr %hp242, i64 24
  store i64 %ld233, ptr %fp245, align 8
  %fp246 = getelementptr i8, ptr %hp242, i64 32
  store i64 %ld234, ptr %fp246, align 8
  store ptr %hp242, ptr %fbip_slot237
  br label %fbip_merge23
fbip_merge23:
  %fbip_r247 = load ptr, ptr %fbip_slot237
  ret void
}

define void @Logger_dispatch(ptr %$actor.arg, ptr %$msg.arg) {
entry:
  %$actor.addr = alloca ptr
  store ptr %$actor.arg, ptr %$actor.addr
  %$msg.addr = alloca ptr
  store ptr %$msg.arg, ptr %$msg.addr
  %ld248 = load ptr, ptr %$msg.addr
  %res_slot249 = alloca ptr
  %tgp250 = getelementptr i8, ptr %ld248, i64 8
  %tag251 = load i32, ptr %tgp250, align 4
  switch i32 %tag251, label %case_default25 [
      i32 0, label %case_br26
  ]
case_br26:
  %fp252 = getelementptr i8, ptr %ld248, i64 16
  %fv253 = load ptr, ptr %fp252, align 8
  %$Record_msg.addr = alloca ptr
  store ptr %fv253, ptr %$Record_msg.addr
  %freed254 = call i64 @march_decrc_freed(ptr %ld248)
  %freed_b255 = icmp ne i64 %freed254, 0
  br i1 %freed_b255, label %br_unique27, label %br_shared28
br_shared28:
  call void @march_incrc(ptr %fv253)
  br label %br_body29
br_unique27:
  br label %br_body29
br_body29:
  %ld256 = load ptr, ptr %$actor.addr
  %ld257 = load ptr, ptr %$Record_msg.addr
  call void @Logger_Record(ptr %ld256, ptr %ld257)
  %cv258 = inttoptr i64 0 to ptr
  store ptr %cv258, ptr %res_slot249
  br label %case_merge24
case_default25:
  unreachable
case_merge24:
  %case_r259 = load ptr, ptr %res_slot249
  ret void
}

define void @march_main() {
entry:
  %cr260 = call i64 @sum_to(i64 5)
  %$t2027.addr = alloca i64
  store i64 %cr260, ptr %$t2027.addr
  %ld261 = load i64, ptr %$t2027.addr
  %cr262 = call ptr @march_int_to_string(i64 %ld261)
  %$t2028.addr = alloca ptr
  store ptr %cr262, ptr %$t2028.addr
  %sl263 = call ptr @march_string_lit(ptr @.str2, i64 16)
  %ld264 = load ptr, ptr %$t2028.addr
  %cr265 = call ptr @march_string_concat(ptr %sl263, ptr %ld264)
  %$t2029.addr = alloca ptr
  store ptr %cr265, ptr %$t2029.addr
  %ld266 = load ptr, ptr %$t2029.addr
  call void @march_println(ptr %ld266)
  %cr267 = call i64 @factorial(i64 6)
  %$t2030.addr = alloca i64
  store i64 %cr267, ptr %$t2030.addr
  %ld268 = load i64, ptr %$t2030.addr
  %cr269 = call ptr @march_int_to_string(i64 %ld268)
  %$t2031.addr = alloca ptr
  store ptr %cr269, ptr %$t2031.addr
  %sl270 = call ptr @march_string_lit(ptr @.str3, i64 19)
  %ld271 = load ptr, ptr %$t2031.addr
  %cr272 = call ptr @march_string_concat(ptr %sl270, ptr %ld271)
  %$t2032.addr = alloca ptr
  store ptr %cr272, ptr %$t2032.addr
  %ld273 = load ptr, ptr %$t2032.addr
  call void @march_println(ptr %ld273)
  %hp274 = call ptr @march_alloc(i64 16)
  %tgp275 = getelementptr i8, ptr %hp274, i64 8
  store i32 0, ptr %tgp275, align 4
  %$t2033.addr = alloca ptr
  store ptr %hp274, ptr %$t2033.addr
  %hp276 = call ptr @march_alloc(i64 32)
  %tgp277 = getelementptr i8, ptr %hp276, i64 8
  store i32 1, ptr %tgp277, align 4
  %fp278 = getelementptr i8, ptr %hp276, i64 16
  store i64 2, ptr %fp278, align 8
  %ld279 = load ptr, ptr %$t2033.addr
  %fp280 = getelementptr i8, ptr %hp276, i64 24
  store ptr %ld279, ptr %fp280, align 8
  %$t2034.addr = alloca ptr
  store ptr %hp276, ptr %$t2034.addr
  %hp281 = call ptr @march_alloc(i64 32)
  %tgp282 = getelementptr i8, ptr %hp281, i64 8
  store i32 1, ptr %tgp282, align 4
  %fp283 = getelementptr i8, ptr %hp281, i64 16
  store i64 7, ptr %fp283, align 8
  %ld284 = load ptr, ptr %$t2034.addr
  %fp285 = getelementptr i8, ptr %hp281, i64 24
  store ptr %ld284, ptr %fp285, align 8
  %$t2035.addr = alloca ptr
  store ptr %hp281, ptr %$t2035.addr
  %hp286 = call ptr @march_alloc(i64 32)
  %tgp287 = getelementptr i8, ptr %hp286, i64 8
  store i32 1, ptr %tgp287, align 4
  %fp288 = getelementptr i8, ptr %hp286, i64 16
  store i64 3, ptr %fp288, align 8
  %ld289 = load ptr, ptr %$t2035.addr
  %fp290 = getelementptr i8, ptr %hp286, i64 24
  store ptr %ld289, ptr %fp290, align 8
  %$t2036.addr = alloca ptr
  store ptr %hp286, ptr %$t2036.addr
  %hp291 = call ptr @march_alloc(i64 32)
  %tgp292 = getelementptr i8, ptr %hp291, i64 8
  store i32 1, ptr %tgp292, align 4
  %fp293 = getelementptr i8, ptr %hp291, i64 16
  store i64 1, ptr %fp293, align 8
  %ld294 = load ptr, ptr %$t2036.addr
  %fp295 = getelementptr i8, ptr %hp291, i64 24
  store ptr %ld294, ptr %fp295, align 8
  %lst.addr = alloca ptr
  store ptr %hp291, ptr %lst.addr
  %ld296 = load ptr, ptr %lst.addr
  %cr297 = call i64 @find_large(ptr %ld296, i64 4)
  %$t2037.addr = alloca i64
  store i64 %cr297, ptr %$t2037.addr
  %ld298 = load i64, ptr %$t2037.addr
  %cr299 = call ptr @march_int_to_string(i64 %ld298)
  %$t2038.addr = alloca ptr
  store ptr %cr299, ptr %$t2038.addr
  %sl300 = call ptr @march_string_lit(ptr @.str4, i64 24)
  %ld301 = load ptr, ptr %$t2038.addr
  %cr302 = call ptr @march_string_concat(ptr %sl300, ptr %ld301)
  %$t2039.addr = alloca ptr
  store ptr %cr302, ptr %$t2039.addr
  %ld303 = load ptr, ptr %$t2039.addr
  call void @march_println(ptr %ld303)
  %cr304 = call i64 @running_sum(i64 10)
  %$t2040.addr = alloca i64
  store i64 %cr304, ptr %$t2040.addr
  %ld305 = load i64, ptr %$t2040.addr
  %cr306 = call ptr @march_int_to_string(i64 %ld305)
  %$t2041.addr = alloca ptr
  store ptr %cr306, ptr %$t2041.addr
  %sl307 = call ptr @march_string_lit(ptr @.str5, i64 22)
  %ld308 = load ptr, ptr %$t2041.addr
  %cr309 = call ptr @march_string_concat(ptr %sl307, ptr %ld308)
  %$t2042.addr = alloca ptr
  store ptr %cr309, ptr %$t2042.addr
  %ld310 = load ptr, ptr %$t2042.addr
  call void @march_println(ptr %ld310)
  %cr311 = call i64 @count_down(i64 10)
  %$t2043.addr = alloca i64
  store i64 %cr311, ptr %$t2043.addr
  %ld312 = load i64, ptr %$t2043.addr
  %cr313 = call ptr @march_int_to_string(i64 %ld312)
  %$t2044.addr = alloca ptr
  store ptr %cr313, ptr %$t2044.addr
  %sl314 = call ptr @march_string_lit(ptr @.str6, i64 21)
  %ld315 = load ptr, ptr %$t2044.addr
  %cr316 = call ptr @march_string_concat(ptr %sl314, ptr %ld315)
  %$t2045.addr = alloca ptr
  store ptr %cr316, ptr %$t2045.addr
  %ld317 = load ptr, ptr %$t2045.addr
  call void @march_println(ptr %ld317)
  %n_i29.addr = alloca i64
  store i64 7, ptr %n_i29.addr
  %ld318 = load i64, ptr %n_i29.addr
  %ar319 = add i64 %ld318, 1
  %x_i30.addr = alloca i64
  store i64 %ar319, ptr %x_i30.addr
  %ld320 = load i64, ptr %x_i30.addr
  %ld321 = load i64, ptr %x_i30.addr
  %ar322 = add i64 %ld320, %ld321
  %sr_s2.addr = alloca i64
  store i64 %ar322, ptr %sr_s2.addr
  %ld323 = load i64, ptr %sr_s2.addr
  %y_i31.addr = alloca i64
  store i64 %ld323, ptr %y_i31.addr
  %ld324 = load i64, ptr %y_i31.addr
  %ar325 = sub i64 %ld324, 3
  %z_i32.addr = alloca i64
  store i64 %ar325, ptr %z_i32.addr
  %ld326 = load i64, ptr %z_i32.addr
  %$t2046.addr = alloca i64
  store i64 %ld326, ptr %$t2046.addr
  %ld327 = load i64, ptr %$t2046.addr
  %cr328 = call ptr @march_int_to_string(i64 %ld327)
  %$t2047.addr = alloca ptr
  store ptr %cr328, ptr %$t2047.addr
  %sl329 = call ptr @march_string_lit(ptr @.str7, i64 21)
  %ld330 = load ptr, ptr %$t2047.addr
  %cr331 = call ptr @march_string_concat(ptr %sl329, ptr %ld330)
  %$t2048.addr = alloca ptr
  store ptr %cr331, ptr %$t2048.addr
  %ld332 = load ptr, ptr %$t2048.addr
  call void @march_println(ptr %ld332)
  %hp333 = call ptr @march_alloc(i64 24)
  %tgp334 = getelementptr i8, ptr %hp333, i64 8
  store i32 0, ptr %tgp334, align 4
  %fp335 = getelementptr i8, ptr %hp333, i64 16
  store i64 0, ptr %fp335, align 8
  %$init_state_i26.addr = alloca ptr
  store ptr %hp333, ptr %$init_state_i26.addr
  %ld336 = load ptr, ptr %$init_state_i26.addr
  %fp337 = getelementptr i8, ptr %ld336, i64 16
  %fv338 = load i64, ptr %fp337, align 8
  %$init_value_i27.addr = alloca i64
  store i64 %fv338, ptr %$init_value_i27.addr
  %hp339 = call ptr @march_alloc(i64 40)
  %tgp340 = getelementptr i8, ptr %hp339, i64 8
  store i32 0, ptr %tgp340, align 4
  %cwrap341 = call ptr @march_alloc(i64 24)
  %cwt342 = getelementptr i8, ptr %cwrap341, i64 8
  store i32 0, ptr %cwt342, align 4
  %cwf343 = getelementptr i8, ptr %cwrap341, i64 16
  store ptr @Counter_dispatch$clo_wrap, ptr %cwf343, align 8
  %fp344 = getelementptr i8, ptr %hp339, i64 16
  store ptr %cwrap341, ptr %fp344, align 8
  %fp345 = getelementptr i8, ptr %hp339, i64 24
  store i64 1, ptr %fp345, align 8
  %ld346 = load i64, ptr %$init_value_i27.addr
  %fp347 = getelementptr i8, ptr %hp339, i64 32
  store i64 %ld346, ptr %fp347, align 8
  %$spawned_i28.addr = alloca ptr
  store ptr %hp339, ptr %$spawned_i28.addr
  %ld348 = load ptr, ptr %$spawned_i28.addr
  %$raw_actor.addr = alloca ptr
  store ptr %ld348, ptr %$raw_actor.addr
  %ld349 = load ptr, ptr %$raw_actor.addr
  %cr350 = call ptr @march_spawn(ptr %ld349)
  %c.addr = alloca ptr
  store ptr %cr350, ptr %c.addr
  %hp351 = call ptr @march_alloc(i64 24)
  %tgp352 = getelementptr i8, ptr %hp351, i64 8
  store i32 0, ptr %tgp352, align 4
  %fp353 = getelementptr i8, ptr %hp351, i64 16
  store i64 0, ptr %fp353, align 8
  %$init_state_i23.addr = alloca ptr
  store ptr %hp351, ptr %$init_state_i23.addr
  %ld354 = load ptr, ptr %$init_state_i23.addr
  %fp355 = getelementptr i8, ptr %ld354, i64 16
  %fv356 = load i64, ptr %fp355, align 8
  %$init_count_i24.addr = alloca i64
  store i64 %fv356, ptr %$init_count_i24.addr
  %hp357 = call ptr @march_alloc(i64 40)
  %tgp358 = getelementptr i8, ptr %hp357, i64 8
  store i32 0, ptr %tgp358, align 4
  %cwrap359 = call ptr @march_alloc(i64 24)
  %cwt360 = getelementptr i8, ptr %cwrap359, i64 8
  store i32 0, ptr %cwt360, align 4
  %cwf361 = getelementptr i8, ptr %cwrap359, i64 16
  store ptr @Logger_dispatch$clo_wrap, ptr %cwf361, align 8
  %fp362 = getelementptr i8, ptr %hp357, i64 16
  store ptr %cwrap359, ptr %fp362, align 8
  %fp363 = getelementptr i8, ptr %hp357, i64 24
  store i64 1, ptr %fp363, align 8
  %ld364 = load i64, ptr %$init_count_i24.addr
  %fp365 = getelementptr i8, ptr %hp357, i64 32
  store i64 %ld364, ptr %fp365, align 8
  %$spawned_i25.addr = alloca ptr
  store ptr %hp357, ptr %$spawned_i25.addr
  %ld366 = load ptr, ptr %$spawned_i25.addr
  %$raw_actor_1.addr = alloca ptr
  store ptr %ld366, ptr %$raw_actor_1.addr
  %ld367 = load ptr, ptr %$raw_actor_1.addr
  %cr368 = call ptr @march_spawn(ptr %ld367)
  %l.addr = alloca ptr
  store ptr %cr368, ptr %l.addr
  %hp369 = call ptr @march_alloc(i64 24)
  %tgp370 = getelementptr i8, ptr %hp369, i64 8
  store i32 0, ptr %tgp370, align 4
  %fp371 = getelementptr i8, ptr %hp369, i64 16
  store i64 10, ptr %fp371, align 8
  %$t2049.addr = alloca ptr
  store ptr %hp369, ptr %$t2049.addr
  %ld372 = load ptr, ptr %c.addr
  call void @march_incrc(ptr %ld372)
  %ld373 = load ptr, ptr %c.addr
  %ld374 = load ptr, ptr %$t2049.addr
  %cr375 = call ptr @march_send(ptr %ld373, ptr %ld374)
  %hp376 = call ptr @march_alloc(i64 24)
  %tgp377 = getelementptr i8, ptr %hp376, i64 8
  store i32 0, ptr %tgp377, align 4
  %sl378 = call ptr @march_string_lit(ptr @.str8, i64 13)
  %fp379 = getelementptr i8, ptr %hp376, i64 16
  store ptr %sl378, ptr %fp379, align 8
  %$t2050.addr = alloca ptr
  store ptr %hp376, ptr %$t2050.addr
  %ld380 = load ptr, ptr %l.addr
  call void @march_incrc(ptr %ld380)
  %ld381 = load ptr, ptr %l.addr
  %ld382 = load ptr, ptr %$t2050.addr
  %cr383 = call ptr @march_send(ptr %ld381, ptr %ld382)
  %hp384 = call ptr @march_alloc(i64 24)
  %tgp385 = getelementptr i8, ptr %hp384, i64 8
  store i32 0, ptr %tgp385, align 4
  %fp386 = getelementptr i8, ptr %hp384, i64 16
  store i64 5, ptr %fp386, align 8
  %$t2051.addr = alloca ptr
  store ptr %hp384, ptr %$t2051.addr
  %ld387 = load ptr, ptr %c.addr
  call void @march_incrc(ptr %ld387)
  %ld388 = load ptr, ptr %c.addr
  %ld389 = load ptr, ptr %$t2051.addr
  %cr390 = call ptr @march_send(ptr %ld388, ptr %ld389)
  %hp391 = call ptr @march_alloc(i64 24)
  %tgp392 = getelementptr i8, ptr %hp391, i64 8
  store i32 0, ptr %tgp392, align 4
  %sl393 = call ptr @march_string_lit(ptr @.str9, i64 12)
  %fp394 = getelementptr i8, ptr %hp391, i64 16
  store ptr %sl393, ptr %fp394, align 8
  %$t2052.addr = alloca ptr
  store ptr %hp391, ptr %$t2052.addr
  %ld395 = load ptr, ptr %l.addr
  call void @march_incrc(ptr %ld395)
  %ld396 = load ptr, ptr %l.addr
  %ld397 = load ptr, ptr %$t2052.addr
  %cr398 = call ptr @march_send(ptr %ld396, ptr %ld397)
  %hp399 = call ptr @march_alloc(i64 16)
  %tgp400 = getelementptr i8, ptr %hp399, i64 8
  store i32 1, ptr %tgp400, align 4
  %$t2053.addr = alloca ptr
  store ptr %hp399, ptr %$t2053.addr
  %ld401 = load ptr, ptr %c.addr
  call void @march_incrc(ptr %ld401)
  %ld402 = load ptr, ptr %c.addr
  %ld403 = load ptr, ptr %$t2053.addr
  %cr404 = call ptr @march_send(ptr %ld402, ptr %ld403)
  %hp405 = call ptr @march_alloc(i64 24)
  %tgp406 = getelementptr i8, ptr %hp405, i64 8
  store i32 0, ptr %tgp406, align 4
  %sl407 = call ptr @march_string_lit(ptr @.str10, i64 13)
  %fp408 = getelementptr i8, ptr %hp405, i64 16
  store ptr %sl407, ptr %fp408, align 8
  %$t2054.addr = alloca ptr
  store ptr %hp405, ptr %$t2054.addr
  %ld409 = load ptr, ptr %l.addr
  call void @march_incrc(ptr %ld409)
  %ld410 = load ptr, ptr %l.addr
  %ld411 = load ptr, ptr %$t2054.addr
  %cr412 = call ptr @march_send(ptr %ld410, ptr %ld411)
  %hp413 = call ptr @march_alloc(i64 24)
  %tgp414 = getelementptr i8, ptr %hp413, i64 8
  store i32 0, ptr %tgp414, align 4
  %fp415 = getelementptr i8, ptr %hp413, i64 16
  store i64 3, ptr %fp415, align 8
  %$t2055.addr = alloca ptr
  store ptr %hp413, ptr %$t2055.addr
  %ld416 = load ptr, ptr %c.addr
  %ld417 = load ptr, ptr %$t2055.addr
  %cr418 = call ptr @march_send(ptr %ld416, ptr %ld417)
  %hp419 = call ptr @march_alloc(i64 24)
  %tgp420 = getelementptr i8, ptr %hp419, i64 8
  store i32 0, ptr %tgp420, align 4
  %sl421 = call ptr @march_string_lit(ptr @.str11, i64 12)
  %fp422 = getelementptr i8, ptr %hp419, i64 16
  store ptr %sl421, ptr %fp422, align 8
  %$t2056.addr = alloca ptr
  store ptr %hp419, ptr %$t2056.addr
  %ld423 = load ptr, ptr %l.addr
  %ld424 = load ptr, ptr %$t2056.addr
  %cr425 = call ptr @march_send(ptr %ld423, ptr %ld424)
  %sl426 = call ptr @march_string_lit(ptr @.str12, i64 8)
  call void @march_println(ptr %sl426)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @Counter_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Counter_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

define ptr @Logger_dispatch$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  call void @Logger_dispatch(ptr %a0, ptr %a1)
  ret ptr null
}

