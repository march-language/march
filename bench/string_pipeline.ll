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

@.str1 = private unnamed_addr constant [2 x i8] c",\00"

define ptr @build_list(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %lo.addr
  %ld2 = load i64, ptr %hi.addr
  %cmp3 = icmp sgt i64 %ld1, %ld2
  %ar4 = zext i1 %cmp3 to i64
  %$t2009.addr = alloca i64
  store i64 %ar4, ptr %$t2009.addr
  %ld5 = load i64, ptr %$t2009.addr
  %res_slot6 = alloca ptr
  %bi7 = trunc i64 %ld5 to i1
  br i1 %bi7, label %case_br3, label %case_default2
case_br3:
  %ld8 = load ptr, ptr %acc.addr
  store ptr %ld8, ptr %res_slot6
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %lo.addr
  %ar10 = add i64 %ld9, 1
  %$t2010.addr = alloca i64
  store i64 %ar10, ptr %$t2010.addr
  %ld11 = load i64, ptr %lo.addr
  %cr12 = call ptr @march_int_to_string(i64 %ld11)
  %$t2011.addr = alloca ptr
  store ptr %cr12, ptr %$t2011.addr
  %hp13 = call ptr @march_alloc(i64 32)
  %tgp14 = getelementptr i8, ptr %hp13, i64 8
  store i32 1, ptr %tgp14, align 4
  %ld15 = load ptr, ptr %$t2011.addr
  %fp16 = getelementptr i8, ptr %hp13, i64 16
  store ptr %ld15, ptr %fp16, align 8
  %ld17 = load ptr, ptr %acc.addr
  %fp18 = getelementptr i8, ptr %hp13, i64 24
  store ptr %ld17, ptr %fp18, align 8
  %$t2012.addr = alloca ptr
  store ptr %hp13, ptr %$t2012.addr
  %ld19 = load i64, ptr %$t2010.addr
  %ld20 = load i64, ptr %hi.addr
  %ld21 = load ptr, ptr %$t2012.addr
  %cr22 = call ptr @build_list(i64 %ld19, i64 %ld20, ptr %ld21)
  store ptr %cr22, ptr %res_slot6
  br label %case_merge1
case_merge1:
  %case_r23 = load ptr, ptr %res_slot6
  ret ptr %case_r23
}

define ptr @double_str(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld24 = load ptr, ptr %s.addr
  call void @march_incrc(ptr %ld24)
  %ld25 = load ptr, ptr %s.addr
  %cr26 = call ptr @march_string_to_int(ptr %ld25)
  %$t2013.addr = alloca ptr
  store ptr %cr26, ptr %$t2013.addr
  %ld27 = load ptr, ptr %$t2013.addr
  %res_slot28 = alloca ptr
  %tgp29 = getelementptr i8, ptr %ld27, i64 8
  %tag30 = load i32, ptr %tgp29, align 4
  switch i32 %tag30, label %case_default5 [
      i32 1, label %case_br6
      i32 0, label %case_br7
  ]
case_br6:
  %fp31 = getelementptr i8, ptr %ld27, i64 16
  %fv32 = load ptr, ptr %fp31, align 8
  %$f2015.addr = alloca ptr
  store ptr %fv32, ptr %$f2015.addr
  %ld33 = load ptr, ptr %$t2013.addr
  call void @march_decrc(ptr %ld33)
  %ld34 = load ptr, ptr %$f2015.addr
  %n.addr = alloca ptr
  store ptr %ld34, ptr %n.addr
  %ld35 = load ptr, ptr %n.addr
  %cv36 = ptrtoint ptr %ld35 to i64
  %ld37 = load ptr, ptr %n.addr
  %cv38 = ptrtoint ptr %ld37 to i64
  %ar39 = add i64 %cv36, %cv38
  %sr_s1.addr = alloca i64
  store i64 %ar39, ptr %sr_s1.addr
  %ld40 = load i64, ptr %sr_s1.addr
  %$t2014.addr = alloca i64
  store i64 %ld40, ptr %$t2014.addr
  %ld41 = load i64, ptr %$t2014.addr
  %cr42 = call ptr @march_int_to_string(i64 %ld41)
  store ptr %cr42, ptr %res_slot28
  br label %case_merge4
case_br7:
  %ld43 = load ptr, ptr %$t2013.addr
  call void @march_decrc(ptr %ld43)
  %ld44 = load ptr, ptr %s.addr
  store ptr %ld44, ptr %res_slot28
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r45 = load ptr, ptr %res_slot28
  ret ptr %case_r45
}

define ptr @map_strings(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld46 = load ptr, ptr %xs.addr
  %res_slot47 = alloca ptr
  %tgp48 = getelementptr i8, ptr %ld46, i64 8
  %tag49 = load i32, ptr %tgp48, align 4
  switch i32 %tag49, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld50 = load ptr, ptr %xs.addr
  %rc51 = load i64, ptr %ld50, align 8
  %uniq52 = icmp eq i64 %rc51, 1
  %fbip_slot53 = alloca ptr
  br i1 %uniq52, label %fbip_reuse12, label %fbip_fresh13
fbip_reuse12:
  %tgp54 = getelementptr i8, ptr %ld50, i64 8
  store i32 0, ptr %tgp54, align 4
  store ptr %ld50, ptr %fbip_slot53
  br label %fbip_merge14
fbip_fresh13:
  call void @march_decrc(ptr %ld50)
  %hp55 = call ptr @march_alloc(i64 16)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 0, ptr %tgp56, align 4
  store ptr %hp55, ptr %fbip_slot53
  br label %fbip_merge14
fbip_merge14:
  %fbip_r57 = load ptr, ptr %fbip_slot53
  store ptr %fbip_r57, ptr %res_slot47
  br label %case_merge8
case_br11:
  %fp58 = getelementptr i8, ptr %ld46, i64 16
  %fv59 = load ptr, ptr %fp58, align 8
  %$f2018.addr = alloca ptr
  store ptr %fv59, ptr %$f2018.addr
  %fp60 = getelementptr i8, ptr %ld46, i64 24
  %fv61 = load ptr, ptr %fp60, align 8
  %$f2019.addr = alloca ptr
  store ptr %fv61, ptr %$f2019.addr
  %ld62 = load ptr, ptr %$f2019.addr
  %t.addr = alloca ptr
  store ptr %ld62, ptr %t.addr
  %ld63 = load ptr, ptr %$f2018.addr
  %h.addr = alloca ptr
  store ptr %ld63, ptr %h.addr
  %ld64 = load ptr, ptr %h.addr
  %cr65 = call ptr @double_str(ptr %ld64)
  %$t2016.addr = alloca ptr
  store ptr %cr65, ptr %$t2016.addr
  %ld66 = load ptr, ptr %t.addr
  %cr67 = call ptr @map_strings(ptr %ld66)
  %$t2017.addr = alloca ptr
  store ptr %cr67, ptr %$t2017.addr
  %ld68 = load ptr, ptr %xs.addr
  %ld69 = load ptr, ptr %$t2016.addr
  %ld70 = load ptr, ptr %$t2017.addr
  %rc71 = load i64, ptr %ld68, align 8
  %uniq72 = icmp eq i64 %rc71, 1
  %fbip_slot73 = alloca ptr
  br i1 %uniq72, label %fbip_reuse15, label %fbip_fresh16
fbip_reuse15:
  %tgp74 = getelementptr i8, ptr %ld68, i64 8
  store i32 1, ptr %tgp74, align 4
  %fp75 = getelementptr i8, ptr %ld68, i64 16
  store ptr %ld69, ptr %fp75, align 8
  %fp76 = getelementptr i8, ptr %ld68, i64 24
  store ptr %ld70, ptr %fp76, align 8
  store ptr %ld68, ptr %fbip_slot73
  br label %fbip_merge17
fbip_fresh16:
  call void @march_decrc(ptr %ld68)
  %hp77 = call ptr @march_alloc(i64 32)
  %tgp78 = getelementptr i8, ptr %hp77, i64 8
  store i32 1, ptr %tgp78, align 4
  %fp79 = getelementptr i8, ptr %hp77, i64 16
  store ptr %ld69, ptr %fp79, align 8
  %fp80 = getelementptr i8, ptr %hp77, i64 24
  store ptr %ld70, ptr %fp80, align 8
  store ptr %hp77, ptr %fbip_slot73
  br label %fbip_merge17
fbip_merge17:
  %fbip_r81 = load ptr, ptr %fbip_slot73
  store ptr %fbip_r81, ptr %res_slot47
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r82 = load ptr, ptr %res_slot47
  ret ptr %case_r82
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 100000, ptr %n.addr
  %hp83 = call ptr @march_alloc(i64 16)
  %tgp84 = getelementptr i8, ptr %hp83, i64 8
  store i32 0, ptr %tgp84, align 4
  %$t2020.addr = alloca ptr
  store ptr %hp83, ptr %$t2020.addr
  %ld85 = load i64, ptr %n.addr
  %ld86 = load ptr, ptr %$t2020.addr
  %cr87 = call ptr @build_list(i64 1, i64 %ld85, ptr %ld86)
  %pieces.addr = alloca ptr
  store ptr %cr87, ptr %pieces.addr
  %ld88 = load ptr, ptr %pieces.addr
  %cr89 = call ptr @map_strings(ptr %ld88)
  %doubled.addr = alloca ptr
  store ptr %cr89, ptr %doubled.addr
  %ld90 = load ptr, ptr %doubled.addr
  %sl91 = call ptr @march_string_lit(ptr @.str1, i64 1)
  %cr92 = call ptr @march_string_join(ptr %ld90, ptr %sl91)
  %result.addr = alloca ptr
  store ptr %cr92, ptr %result.addr
  %ld93 = load ptr, ptr %result.addr
  %cr94 = call i64 @march_string_byte_length(ptr %ld93)
  %$t2021.addr = alloca i64
  store i64 %cr94, ptr %$t2021.addr
  %ld95 = load i64, ptr %$t2021.addr
  %cr96 = call ptr @march_int_to_string(i64 %ld95)
  %$t2022.addr = alloca ptr
  store ptr %cr96, ptr %$t2022.addr
  %ld97 = load ptr, ptr %$t2022.addr
  call void @march_println(ptr %ld97)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
