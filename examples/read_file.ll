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

@.str1 = private unnamed_addr constant [25 x i8] c"examples/read_file.march\00"
@.str2 = private unnamed_addr constant [21 x i8] c"Error reading file: \00"
@.str3 = private unnamed_addr constant [27 x i8] c"=== Full file contents ===\00"
@.str4 = private unnamed_addr constant [8 x i8] c"Error: \00"
@.str5 = private unnamed_addr constant [19 x i8] c"=== Line count ===\00"
@.str6 = private unnamed_addr constant [7 x i8] c" lines\00"
@.str7 = private unnamed_addr constant [34 x i8] c"=== First 3 lines (streaming) ===\00"
@.str8 = private unnamed_addr constant [8 x i8] c"Error: \00"
@.str9 = private unnamed_addr constant [1 x i8] c"\00"
@.str10 = private unnamed_addr constant [2 x i8] c"\0A\00"
@.str11 = private unnamed_addr constant [2 x i8] c"\0A\00"
@.str12 = private unnamed_addr constant [1 x i8] c"\00"

define ptr @march_main() {
entry:
  %sl1 = call ptr @march_string_lit(ptr @.str1, i64 24)
  %path.addr = alloca ptr
  store ptr %sl1, ptr %path.addr
  %ld2 = load ptr, ptr %path.addr
  call void @march_incrc(ptr %ld2)
  %ld3 = load ptr, ptr %path.addr
  %cr4 = call ptr @File.read(ptr %ld3)
  %$t2009.addr = alloca ptr
  store ptr %cr4, ptr %$t2009.addr
  %ld5 = load ptr, ptr %$t2009.addr
  %res_slot6 = alloca ptr
  %tgp7 = getelementptr i8, ptr %ld5, i64 8
  %tag8 = load i32, ptr %tgp7, align 4
  switch i32 %tag8, label %case_default2 [
      i32 1, label %case_br3
      i32 0, label %case_br4
  ]
case_br3:
  %fp9 = getelementptr i8, ptr %ld5, i64 16
  %fv10 = load ptr, ptr %fp9, align 8
  %$f2012.addr = alloca ptr
  store ptr %fv10, ptr %$f2012.addr
  %freed11 = call i64 @march_decrc_freed(ptr %ld5)
  %freed_b12 = icmp ne i64 %freed11, 0
  br i1 %freed_b12, label %br_unique5, label %br_shared6
br_shared6:
  call void @march_incrc(ptr %fv10)
  br label %br_body7
br_unique5:
  br label %br_body7
br_body7:
  %ld13 = load ptr, ptr %$f2012.addr
  %e.addr = alloca ptr
  store ptr %ld13, ptr %e.addr
  %ld14 = load ptr, ptr %e.addr
  %cr15 = call ptr @march_value_to_string(ptr %ld14)
  %$t2010.addr = alloca ptr
  store ptr %cr15, ptr %$t2010.addr
  %sl16 = call ptr @march_string_lit(ptr @.str2, i64 20)
  %ld17 = load ptr, ptr %$t2010.addr
  %cr18 = call ptr @march_string_concat(ptr %sl16, ptr %ld17)
  %$t2011.addr = alloca ptr
  store ptr %cr18, ptr %$t2011.addr
  %ld19 = load ptr, ptr %$t2011.addr
  call void @march_println(ptr %ld19)
  %cv20 = inttoptr i64 0 to ptr
  store ptr %cv20, ptr %res_slot6
  br label %case_merge1
case_br4:
  %fp21 = getelementptr i8, ptr %ld5, i64 16
  %fv22 = load ptr, ptr %fp21, align 8
  %$f2013.addr = alloca ptr
  store ptr %fv22, ptr %$f2013.addr
  %freed23 = call i64 @march_decrc_freed(ptr %ld5)
  %freed_b24 = icmp ne i64 %freed23, 0
  br i1 %freed_b24, label %br_unique8, label %br_shared9
br_shared9:
  call void @march_incrc(ptr %fv22)
  br label %br_body10
br_unique8:
  br label %br_body10
br_body10:
  %ld25 = load ptr, ptr %$f2013.addr
  %contents.addr = alloca ptr
  store ptr %ld25, ptr %contents.addr
  %sl26 = call ptr @march_string_lit(ptr @.str3, i64 26)
  call void @march_println(ptr %sl26)
  %ld27 = load ptr, ptr %contents.addr
  call void @march_println(ptr %ld27)
  %cv28 = inttoptr i64 0 to ptr
  store ptr %cv28, ptr %res_slot6
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r29 = load ptr, ptr %res_slot6
  %ld30 = load ptr, ptr %path.addr
  call void @march_incrc(ptr %ld30)
  %ld31 = load ptr, ptr %path.addr
  %cr32 = call ptr @File.read_lines(ptr %ld31)
  %$t2014.addr = alloca ptr
  store ptr %cr32, ptr %$t2014.addr
  %ld33 = load ptr, ptr %$t2014.addr
  %res_slot34 = alloca ptr
  %tgp35 = getelementptr i8, ptr %ld33, i64 8
  %tag36 = load i32, ptr %tgp35, align 4
  switch i32 %tag36, label %case_default12 [
      i32 1, label %case_br13
      i32 0, label %case_br14
  ]
case_br13:
  %fp37 = getelementptr i8, ptr %ld33, i64 16
  %fv38 = load ptr, ptr %fp37, align 8
  %$f2020.addr = alloca ptr
  store ptr %fv38, ptr %$f2020.addr
  %freed39 = call i64 @march_decrc_freed(ptr %ld33)
  %freed_b40 = icmp ne i64 %freed39, 0
  br i1 %freed_b40, label %br_unique15, label %br_shared16
br_shared16:
  call void @march_incrc(ptr %fv38)
  br label %br_body17
br_unique15:
  br label %br_body17
br_body17:
  %ld41 = load ptr, ptr %$f2020.addr
  %e_1.addr = alloca ptr
  store ptr %ld41, ptr %e_1.addr
  %ld42 = load ptr, ptr %e_1.addr
  %cr43 = call ptr @march_value_to_string(ptr %ld42)
  %$t2015.addr = alloca ptr
  store ptr %cr43, ptr %$t2015.addr
  %sl44 = call ptr @march_string_lit(ptr @.str4, i64 7)
  %ld45 = load ptr, ptr %$t2015.addr
  %cr46 = call ptr @march_string_concat(ptr %sl44, ptr %ld45)
  %$t2016.addr = alloca ptr
  store ptr %cr46, ptr %$t2016.addr
  %ld47 = load ptr, ptr %$t2016.addr
  call void @march_println(ptr %ld47)
  %cv48 = inttoptr i64 0 to ptr
  store ptr %cv48, ptr %res_slot34
  br label %case_merge11
case_br14:
  %fp49 = getelementptr i8, ptr %ld33, i64 16
  %fv50 = load ptr, ptr %fp49, align 8
  %$f2021.addr = alloca ptr
  store ptr %fv50, ptr %$f2021.addr
  %freed51 = call i64 @march_decrc_freed(ptr %ld33)
  %freed_b52 = icmp ne i64 %freed51, 0
  br i1 %freed_b52, label %br_unique18, label %br_shared19
br_shared19:
  call void @march_incrc(ptr %fv50)
  br label %br_body20
br_unique18:
  br label %br_body20
br_body20:
  %ld53 = load ptr, ptr %$f2021.addr
  %lines.addr = alloca ptr
  store ptr %ld53, ptr %lines.addr
  %sl54 = call ptr @march_string_lit(ptr @.str5, i64 18)
  call void @march_println(ptr %sl54)
  %ld55 = load ptr, ptr %lines.addr
  %cr56 = call i64 @List.length$List_String(ptr %ld55)
  %$t2017.addr = alloca i64
  store i64 %cr56, ptr %$t2017.addr
  %ld57 = load i64, ptr %$t2017.addr
  %cr58 = call ptr @march_int_to_string(i64 %ld57)
  %$t2018.addr = alloca ptr
  store ptr %cr58, ptr %$t2018.addr
  %ld59 = load ptr, ptr %$t2018.addr
  %sl60 = call ptr @march_string_lit(ptr @.str6, i64 6)
  %cr61 = call ptr @march_string_concat(ptr %ld59, ptr %sl60)
  %$t2019.addr = alloca ptr
  store ptr %cr61, ptr %$t2019.addr
  %ld62 = load ptr, ptr %$t2019.addr
  call void @march_println(ptr %ld62)
  %cv63 = inttoptr i64 0 to ptr
  store ptr %cv63, ptr %res_slot34
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r64 = load ptr, ptr %res_slot34
  %sl65 = call ptr @march_string_lit(ptr @.str7, i64 33)
  call void @march_println(ptr %sl65)
  %hp66 = call ptr @march_alloc(i64 24)
  %tgp67 = getelementptr i8, ptr %hp66, i64 8
  store i32 0, ptr %tgp67, align 4
  %fp68 = getelementptr i8, ptr %hp66, i64 16
  store ptr @$lam2022$apply$22, ptr %fp68, align 8
  %$t2024.addr = alloca ptr
  store ptr %hp66, ptr %$t2024.addr
  %ld69 = load ptr, ptr %path.addr
  %ld70 = load ptr, ptr %$t2024.addr
  %cr71 = call ptr @File.with_lines$String$Fn_Seq_Fn_T_List_String_Int_Fn_T_List_String_Int_String_T_List_String_Int_T_List_String_Int_List_V__6096(ptr %ld69, ptr %ld70)
  %$t2025.addr = alloca ptr
  store ptr %cr71, ptr %$t2025.addr
  %ld72 = load ptr, ptr %$t2025.addr
  %res_slot73 = alloca ptr
  %tgp74 = getelementptr i8, ptr %ld72, i64 8
  %tag75 = load i32, ptr %tgp74, align 4
  switch i32 %tag75, label %case_default22 [
      i32 1, label %case_br23
      i32 0, label %case_br24
  ]
case_br23:
  %fp76 = getelementptr i8, ptr %ld72, i64 16
  %fv77 = load ptr, ptr %fp76, align 8
  %$f2031.addr = alloca ptr
  store ptr %fv77, ptr %$f2031.addr
  %freed78 = call i64 @march_decrc_freed(ptr %ld72)
  %freed_b79 = icmp ne i64 %freed78, 0
  br i1 %freed_b79, label %br_unique25, label %br_shared26
br_shared26:
  call void @march_incrc(ptr %fv77)
  br label %br_body27
br_unique25:
  br label %br_body27
br_body27:
  %ld80 = load ptr, ptr %$f2031.addr
  %e_2.addr = alloca ptr
  store ptr %ld80, ptr %e_2.addr
  %ld81 = load ptr, ptr %e_2.addr
  %cr82 = call ptr @march_value_to_string(ptr %ld81)
  %$t2026.addr = alloca ptr
  store ptr %cr82, ptr %$t2026.addr
  %sl83 = call ptr @march_string_lit(ptr @.str8, i64 7)
  %ld84 = load ptr, ptr %$t2026.addr
  %cr85 = call ptr @march_string_concat(ptr %sl83, ptr %ld84)
  %$t2027.addr = alloca ptr
  store ptr %cr85, ptr %$t2027.addr
  %ld86 = load ptr, ptr %$t2027.addr
  call void @march_println(ptr %ld86)
  %cv87 = inttoptr i64 0 to ptr
  store ptr %cv87, ptr %res_slot73
  br label %case_merge21
case_br24:
  %fp88 = getelementptr i8, ptr %ld72, i64 16
  %fv89 = load ptr, ptr %fp88, align 8
  %$f2032.addr = alloca ptr
  store ptr %fv89, ptr %$f2032.addr
  %freed90 = call i64 @march_decrc_freed(ptr %ld72)
  %freed_b91 = icmp ne i64 %freed90, 0
  br i1 %freed_b91, label %br_unique28, label %br_shared29
br_shared29:
  call void @march_incrc(ptr %fv89)
  br label %br_body30
br_unique28:
  br label %br_body30
br_body30:
  %ld92 = load ptr, ptr %$f2032.addr
  %first3.addr = alloca ptr
  store ptr %ld92, ptr %first3.addr
  %hp93 = call ptr @march_alloc(i64 24)
  %tgp94 = getelementptr i8, ptr %hp93, i64 8
  store i32 0, ptr %tgp94, align 4
  %fp95 = getelementptr i8, ptr %hp93, i64 16
  store ptr @$lam2028$apply$23, ptr %fp95, align 8
  %$t2030.addr = alloca ptr
  store ptr %hp93, ptr %$t2030.addr
  %sl96 = call ptr @march_string_lit(ptr @.str9, i64 0)
  %ld97 = load ptr, ptr %first3.addr
  %ld98 = load ptr, ptr %$t2030.addr
  %cr99 = call ptr @List.fold_left$String$List_String$Fn_String_Fn_String_String(ptr %sl96, ptr %ld97, ptr %ld98)
  %joined.addr = alloca ptr
  store ptr %cr99, ptr %joined.addr
  %ld100 = load ptr, ptr %joined.addr
  call void @march_println(ptr %ld100)
  %cv101 = inttoptr i64 0 to ptr
  store ptr %cv101, ptr %res_slot73
  br label %case_merge21
case_default22:
  unreachable
case_merge21:
  %case_r102 = load ptr, ptr %res_slot73
  ret ptr %case_r102
}

define ptr @List.fold_left$String$List_String$Fn_String_Fn_String_String(ptr %acc.arg, ptr %xs.arg, ptr %f.arg) {
entry:
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld103 = load ptr, ptr %xs.addr
  %res_slot104 = alloca ptr
  %tgp105 = getelementptr i8, ptr %ld103, i64 8
  %tag106 = load i32, ptr %tgp105, align 4
  switch i32 %tag106, label %case_default32 [
      i32 0, label %case_br33
      i32 1, label %case_br34
  ]
case_br33:
  %ld107 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld107)
  %ld108 = load ptr, ptr %acc.addr
  store ptr %ld108, ptr %res_slot104
  br label %case_merge31
case_br34:
  %fp109 = getelementptr i8, ptr %ld103, i64 16
  %fv110 = load ptr, ptr %fp109, align 8
  %$f151.addr = alloca ptr
  store ptr %fv110, ptr %$f151.addr
  %fp111 = getelementptr i8, ptr %ld103, i64 24
  %fv112 = load ptr, ptr %fp111, align 8
  %$f152.addr = alloca ptr
  store ptr %fv112, ptr %$f152.addr
  %freed113 = call i64 @march_decrc_freed(ptr %ld103)
  %freed_b114 = icmp ne i64 %freed113, 0
  br i1 %freed_b114, label %br_unique35, label %br_shared36
br_shared36:
  call void @march_incrc(ptr %fv112)
  call void @march_incrc(ptr %fv110)
  br label %br_body37
br_unique35:
  br label %br_body37
br_body37:
  %ld115 = load ptr, ptr %$f152.addr
  %t.addr = alloca ptr
  store ptr %ld115, ptr %t.addr
  %ld116 = load ptr, ptr %$f151.addr
  %h.addr = alloca ptr
  store ptr %ld116, ptr %h.addr
  %ld117 = load ptr, ptr %f.addr
  %fp118 = getelementptr i8, ptr %ld117, i64 16
  %fv119 = load ptr, ptr %fp118, align 8
  %ld120 = load ptr, ptr %acc.addr
  %ld121 = load ptr, ptr %h.addr
  %cr122 = call ptr (ptr, ptr, ptr) %fv119(ptr %ld117, ptr %ld120, ptr %ld121)
  %$t150.addr = alloca ptr
  store ptr %cr122, ptr %$t150.addr
  %ld123 = load ptr, ptr %$t150.addr
  %ld124 = load ptr, ptr %t.addr
  %ld125 = load ptr, ptr %f.addr
  %cr126 = call ptr @List.fold_left$V__802$List_V__803$Fn_V__802_Fn_V__803_V__802(ptr %ld123, ptr %ld124, ptr %ld125)
  store ptr %cr126, ptr %res_slot104
  br label %case_merge31
case_default32:
  unreachable
case_merge31:
  %case_r127 = load ptr, ptr %res_slot104
  ret ptr %case_r127
}

define ptr @List.reverse$List_String(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp128 = call ptr @march_alloc(i64 24)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  %fp130 = getelementptr i8, ptr %hp128, i64 16
  store ptr @go$apply$25, ptr %fp130, align 8
  %go.addr = alloca ptr
  store ptr %hp128, ptr %go.addr
  %hp131 = call ptr @march_alloc(i64 16)
  %tgp132 = getelementptr i8, ptr %hp131, i64 8
  store i32 0, ptr %tgp132, align 4
  %$t129.addr = alloca ptr
  store ptr %hp131, ptr %$t129.addr
  %ld133 = load ptr, ptr %go.addr
  %fp134 = getelementptr i8, ptr %ld133, i64 16
  %fv135 = load ptr, ptr %fp134, align 8
  %ld136 = load ptr, ptr %xs.addr
  %ld137 = load ptr, ptr %$t129.addr
  %cr138 = call ptr (ptr, ptr, ptr) %fv135(ptr %ld133, ptr %ld136, ptr %ld137)
  ret ptr %cr138
}

define ptr @File.with_lines$String$Fn_Seq_Fn_T_List_String_Int_Fn_T_List_String_Int_String_T_List_String_Int_T_List_String_Int_List_V__6096(ptr %path.arg, ptr %callback.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %callback.addr = alloca ptr
  store ptr %callback.arg, ptr %callback.addr
  %ld139 = load ptr, ptr %file_open.addr
  %fp140 = getelementptr i8, ptr %ld139, i64 16
  %fv141 = load ptr, ptr %fp140, align 8
  %ld142 = load ptr, ptr %path.addr
  %cr143 = call ptr (ptr, ptr) %fv141(ptr %ld139, ptr %ld142)
  %$t1314.addr = alloca ptr
  store ptr %cr143, ptr %$t1314.addr
  %ld144 = load ptr, ptr %$t1314.addr
  %res_slot145 = alloca ptr
  %tgp146 = getelementptr i8, ptr %ld144, i64 8
  %tag147 = load i32, ptr %tgp146, align 4
  switch i32 %tag147, label %case_default39 [
      i32 1, label %case_br40
      i32 0, label %case_br41
  ]
case_br40:
  %fp148 = getelementptr i8, ptr %ld144, i64 16
  %fv149 = load ptr, ptr %fp148, align 8
  %$f1320.addr = alloca ptr
  store ptr %fv149, ptr %$f1320.addr
  %ld150 = load ptr, ptr %$f1320.addr
  %e.addr = alloca ptr
  store ptr %ld150, ptr %e.addr
  %ld151 = load ptr, ptr %$t1314.addr
  %ld152 = load ptr, ptr %e.addr
  %rc153 = load i64, ptr %ld151, align 8
  %uniq154 = icmp eq i64 %rc153, 1
  %fbip_slot155 = alloca ptr
  br i1 %uniq154, label %fbip_reuse42, label %fbip_fresh43
fbip_reuse42:
  %tgp156 = getelementptr i8, ptr %ld151, i64 8
  store i32 1, ptr %tgp156, align 4
  %fp157 = getelementptr i8, ptr %ld151, i64 16
  store ptr %ld152, ptr %fp157, align 8
  store ptr %ld151, ptr %fbip_slot155
  br label %fbip_merge44
fbip_fresh43:
  call void @march_decrc(ptr %ld151)
  %hp158 = call ptr @march_alloc(i64 24)
  %tgp159 = getelementptr i8, ptr %hp158, i64 8
  store i32 1, ptr %tgp159, align 4
  %fp160 = getelementptr i8, ptr %hp158, i64 16
  store ptr %ld152, ptr %fp160, align 8
  store ptr %hp158, ptr %fbip_slot155
  br label %fbip_merge44
fbip_merge44:
  %fbip_r161 = load ptr, ptr %fbip_slot155
  store ptr %fbip_r161, ptr %res_slot145
  br label %case_merge38
case_br41:
  %fp162 = getelementptr i8, ptr %ld144, i64 16
  %fv163 = load ptr, ptr %fp162, align 8
  %$f1321.addr = alloca ptr
  store ptr %fv163, ptr %$f1321.addr
  %ld164 = load ptr, ptr %$t1314.addr
  call void @march_decrc(ptr %ld164)
  %ld165 = load ptr, ptr %$f1321.addr
  %fd.addr = alloca ptr
  store ptr %ld165, ptr %fd.addr
  %hp166 = call ptr @march_alloc(i64 40)
  %tgp167 = getelementptr i8, ptr %hp166, i64 8
  store i32 0, ptr %tgp167, align 4
  %fp168 = getelementptr i8, ptr %hp166, i64 16
  store ptr @do_lines$apply$26, ptr %fp168, align 8
  %ld169 = load ptr, ptr %fd.addr
  %cv170 = ptrtoint ptr %ld169 to i64
  %fp171 = getelementptr i8, ptr %hp166, i64 24
  store i64 %cv170, ptr %fp171, align 8
  %ld172 = load ptr, ptr %file_read_line.addr
  %fp173 = getelementptr i8, ptr %hp166, i64 32
  store ptr %ld172, ptr %fp173, align 8
  %do_lines.addr = alloca ptr
  store ptr %hp166, ptr %do_lines.addr
  %hp174 = call ptr @march_alloc(i64 32)
  %tgp175 = getelementptr i8, ptr %hp174, i64 8
  store i32 0, ptr %tgp175, align 4
  %fp176 = getelementptr i8, ptr %hp174, i64 16
  store ptr @$lam1318$apply$27, ptr %fp176, align 8
  %ld177 = load ptr, ptr %do_lines.addr
  %fp178 = getelementptr i8, ptr %hp174, i64 24
  store ptr %ld177, ptr %fp178, align 8
  %$t1319.addr = alloca ptr
  store ptr %hp174, ptr %$t1319.addr
  %hp179 = call ptr @march_alloc(i64 24)
  %tgp180 = getelementptr i8, ptr %hp179, i64 8
  store i32 0, ptr %tgp180, align 4
  %ld181 = load ptr, ptr %$t1319.addr
  %fp182 = getelementptr i8, ptr %hp179, i64 16
  store ptr %ld181, ptr %fp182, align 8
  %seq.addr = alloca ptr
  store ptr %hp179, ptr %seq.addr
  %ld183 = load ptr, ptr %callback.addr
  %fp184 = getelementptr i8, ptr %ld183, i64 16
  %fv185 = load ptr, ptr %fp184, align 8
  %ld186 = load ptr, ptr %seq.addr
  %cr187 = call ptr (ptr, ptr) %fv185(ptr %ld183, ptr %ld186)
  %result.addr = alloca ptr
  store ptr %cr187, ptr %result.addr
  %ld188 = load ptr, ptr %file_close.addr
  %fp189 = getelementptr i8, ptr %ld188, i64 16
  %fv190 = load ptr, ptr %fp189, align 8
  %ld191 = load ptr, ptr %fd.addr
  %cv192 = ptrtoint ptr %ld191 to i64
  %cr193 = call ptr (ptr, i64) %fv190(ptr %ld188, i64 %cv192)
  %hp194 = call ptr @march_alloc(i64 24)
  %tgp195 = getelementptr i8, ptr %hp194, i64 8
  store i32 0, ptr %tgp195, align 4
  %ld196 = load ptr, ptr %result.addr
  %fp197 = getelementptr i8, ptr %hp194, i64 16
  store ptr %ld196, ptr %fp197, align 8
  store ptr %hp194, ptr %res_slot145
  br label %case_merge38
case_default39:
  unreachable
case_merge38:
  %case_r198 = load ptr, ptr %res_slot145
  ret ptr %case_r198
}

define ptr @Seq.to_list$Seq_Fn_List_String_Fn_List_String_String_List_String_List_V__6096(ptr %seq.arg) {
entry:
  %seq.addr = alloca ptr
  store ptr %seq.arg, ptr %seq.addr
  %ld199 = load ptr, ptr %seq.addr
  %res_slot200 = alloca ptr
  %tgp201 = getelementptr i8, ptr %ld199, i64 8
  %tag202 = load i32, ptr %tgp201, align 4
  switch i32 %tag202, label %case_default46 [
      i32 0, label %case_br47
  ]
case_br47:
  %fp203 = getelementptr i8, ptr %ld199, i64 16
  %fv204 = load ptr, ptr %fp203, align 8
  %$f1247.addr = alloca ptr
  store ptr %fv204, ptr %$f1247.addr
  %freed205 = call i64 @march_decrc_freed(ptr %ld199)
  %freed_b206 = icmp ne i64 %freed205, 0
  br i1 %freed_b206, label %br_unique48, label %br_shared49
br_shared49:
  call void @march_incrc(ptr %fv204)
  br label %br_body50
br_unique48:
  br label %br_body50
br_body50:
  %ld207 = load ptr, ptr %$f1247.addr
  %fold.addr = alloca ptr
  store ptr %ld207, ptr %fold.addr
  %ld208 = load ptr, ptr %fold.addr
  call void @march_decrc(ptr %ld208)
  %hp209 = call ptr @march_alloc(i64 16)
  %tgp210 = getelementptr i8, ptr %hp209, i64 8
  store i32 0, ptr %tgp210, align 4
  %$t1243.addr = alloca ptr
  store ptr %hp209, ptr %$t1243.addr
  %hp211 = call ptr @march_alloc(i64 24)
  %tgp212 = getelementptr i8, ptr %hp211, i64 8
  store i32 0, ptr %tgp212, align 4
  %fp213 = getelementptr i8, ptr %hp211, i64 16
  store ptr @$lam1244$apply$28, ptr %fp213, align 8
  %$t1245.addr = alloca ptr
  store ptr %hp211, ptr %$t1245.addr
  %ld214 = load ptr, ptr %$t1243.addr
  %ld215 = load ptr, ptr %$t1245.addr
  %cr216 = call ptr @Seq.fold(ptr %ld214, ptr %ld215)
  %$t1246.addr = alloca ptr
  store ptr %cr216, ptr %$t1246.addr
  %ld217 = load ptr, ptr %$t1246.addr
  %cr218 = call ptr @Seq.rev$List_V__6096(ptr %ld217)
  store ptr %cr218, ptr %res_slot200
  br label %case_merge45
case_default46:
  unreachable
case_merge45:
  %case_r219 = load ptr, ptr %res_slot200
  ret ptr %case_r219
}

define ptr @Seq.take$Seq_Fn_T_List_String_Int_Fn_T_List_String_Int_String_T_List_String_Int_T_List_String_Int$Int(ptr %seq.arg, i64 %n.arg) {
entry:
  %seq.addr = alloca ptr
  store ptr %seq.arg, ptr %seq.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %hp220 = call ptr @march_alloc(i64 32)
  %tgp221 = getelementptr i8, ptr %hp220, i64 8
  store i32 0, ptr %tgp221, align 4
  %fp222 = getelementptr i8, ptr %hp220, i64 16
  store ptr @step_take$apply$29, ptr %fp222, align 8
  %ld223 = load i64, ptr %n.addr
  %fp224 = getelementptr i8, ptr %hp220, i64 24
  store i64 %ld223, ptr %fp224, align 8
  %step_take.addr = alloca ptr
  store ptr %hp220, ptr %step_take.addr
  %hp225 = call ptr @march_alloc(i64 32)
  %tgp226 = getelementptr i8, ptr %hp225, i64 8
  store i32 0, ptr %tgp226, align 4
  %fp227 = getelementptr i8, ptr %hp225, i64 16
  store ptr @run_take$apply$30, ptr %fp227, align 8
  %ld228 = load ptr, ptr %step_take.addr
  %fp229 = getelementptr i8, ptr %hp225, i64 24
  store ptr %ld228, ptr %fp229, align 8
  %run_take.addr = alloca ptr
  store ptr %hp225, ptr %run_take.addr
  %ld230 = load ptr, ptr %seq.addr
  %res_slot231 = alloca ptr
  %tgp232 = getelementptr i8, ptr %ld230, i64 8
  %tag233 = load i32, ptr %tgp232, align 4
  switch i32 %tag233, label %case_default52 [
      i32 0, label %case_br53
  ]
case_br53:
  %fp234 = getelementptr i8, ptr %ld230, i64 16
  %fv235 = load ptr, ptr %fp234, align 8
  %$f1197.addr = alloca ptr
  store ptr %fv235, ptr %$f1197.addr
  %freed236 = call i64 @march_decrc_freed(ptr %ld230)
  %freed_b237 = icmp ne i64 %freed236, 0
  br i1 %freed_b237, label %br_unique54, label %br_shared55
br_shared55:
  call void @march_incrc(ptr %fv235)
  br label %br_body56
br_unique54:
  br label %br_body56
br_body56:
  %ld238 = load ptr, ptr %$f1197.addr
  %fold.addr = alloca ptr
  store ptr %ld238, ptr %fold.addr
  %ld239 = load ptr, ptr %fold.addr
  call void @march_decrc(ptr %ld239)
  %hp240 = call ptr @march_alloc(i64 32)
  %tgp241 = getelementptr i8, ptr %hp240, i64 8
  store i32 0, ptr %tgp241, align 4
  %fp242 = getelementptr i8, ptr %hp240, i64 16
  store ptr @$lam1195$apply$32, ptr %fp242, align 8
  %ld243 = load ptr, ptr %run_take.addr
  %fp244 = getelementptr i8, ptr %hp240, i64 24
  store ptr %ld243, ptr %fp244, align 8
  %$t1196.addr = alloca ptr
  store ptr %hp240, ptr %$t1196.addr
  %hp245 = call ptr @march_alloc(i64 24)
  %tgp246 = getelementptr i8, ptr %hp245, i64 8
  store i32 0, ptr %tgp246, align 4
  %ld247 = load ptr, ptr %$t1196.addr
  %fp248 = getelementptr i8, ptr %hp245, i64 16
  store ptr %ld247, ptr %fp248, align 8
  store ptr %hp245, ptr %res_slot231
  br label %case_merge51
case_default52:
  unreachable
case_merge51:
  %case_r249 = load ptr, ptr %res_slot231
  ret ptr %case_r249
}

define i64 @List.length$List_String(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp250 = call ptr @march_alloc(i64 24)
  %tgp251 = getelementptr i8, ptr %hp250, i64 8
  store i32 0, ptr %tgp251, align 4
  %fp252 = getelementptr i8, ptr %hp250, i64 16
  store ptr @go$apply$33, ptr %fp252, align 8
  %go.addr = alloca ptr
  store ptr %hp250, ptr %go.addr
  %ld253 = load ptr, ptr %go.addr
  %fp254 = getelementptr i8, ptr %ld253, i64 16
  %fv255 = load ptr, ptr %fp254, align 8
  %ld256 = load ptr, ptr %xs.addr
  %cr257 = call i64 (ptr, ptr, i64) %fv255(ptr %ld253, ptr %ld256, i64 0)
  ret i64 %cr257
}

define ptr @File.read_lines(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %ld258 = load ptr, ptr %file_read.addr
  %fp259 = getelementptr i8, ptr %ld258, i64 16
  %fv260 = load ptr, ptr %fp259, align 8
  %ld261 = load ptr, ptr %path.addr
  %cr262 = call ptr (ptr, ptr) %fv260(ptr %ld258, ptr %ld261)
  %$t1306.addr = alloca ptr
  store ptr %cr262, ptr %$t1306.addr
  %ld263 = load ptr, ptr %$t1306.addr
  %res_slot264 = alloca ptr
  %tgp265 = getelementptr i8, ptr %ld263, i64 8
  %tag266 = load i32, ptr %tgp265, align 4
  switch i32 %tag266, label %case_default58 [
      i32 1, label %case_br59
      i32 0, label %case_br60
  ]
case_br59:
  %fp267 = getelementptr i8, ptr %ld263, i64 16
  %fv268 = load ptr, ptr %fp267, align 8
  %$f1312.addr = alloca ptr
  store ptr %fv268, ptr %$f1312.addr
  %ld269 = load ptr, ptr %$f1312.addr
  %e.addr = alloca ptr
  store ptr %ld269, ptr %e.addr
  %ld270 = load ptr, ptr %$t1306.addr
  %ld271 = load ptr, ptr %e.addr
  %rc272 = load i64, ptr %ld270, align 8
  %uniq273 = icmp eq i64 %rc272, 1
  %fbip_slot274 = alloca ptr
  br i1 %uniq273, label %fbip_reuse61, label %fbip_fresh62
fbip_reuse61:
  %tgp275 = getelementptr i8, ptr %ld270, i64 8
  store i32 1, ptr %tgp275, align 4
  %fp276 = getelementptr i8, ptr %ld270, i64 16
  store ptr %ld271, ptr %fp276, align 8
  store ptr %ld270, ptr %fbip_slot274
  br label %fbip_merge63
fbip_fresh62:
  call void @march_decrc(ptr %ld270)
  %hp277 = call ptr @march_alloc(i64 24)
  %tgp278 = getelementptr i8, ptr %hp277, i64 8
  store i32 1, ptr %tgp278, align 4
  %fp279 = getelementptr i8, ptr %hp277, i64 16
  store ptr %ld271, ptr %fp279, align 8
  store ptr %hp277, ptr %fbip_slot274
  br label %fbip_merge63
fbip_merge63:
  %fbip_r280 = load ptr, ptr %fbip_slot274
  store ptr %fbip_r280, ptr %res_slot264
  br label %case_merge57
case_br60:
  %fp281 = getelementptr i8, ptr %ld263, i64 16
  %fv282 = load ptr, ptr %fp281, align 8
  %$f1313.addr = alloca ptr
  store ptr %fv282, ptr %$f1313.addr
  %ld283 = load ptr, ptr %$f1313.addr
  %s.addr = alloca ptr
  store ptr %ld283, ptr %s.addr
  %ld284 = load ptr, ptr %s.addr
  %s_i23.addr = alloca ptr
  store ptr %ld284, ptr %s_i23.addr
  %sl285 = call ptr @march_string_lit(ptr @.str10, i64 1)
  %sep_i24.addr = alloca ptr
  store ptr %sl285, ptr %sep_i24.addr
  %ld286 = load ptr, ptr %s_i23.addr
  %ld287 = load ptr, ptr %sep_i24.addr
  %cr288 = call ptr @march_string_split(ptr %ld286, ptr %ld287)
  %lines.addr = alloca ptr
  store ptr %cr288, ptr %lines.addr
  %hp289 = call ptr @march_alloc(i64 24)
  %tgp290 = getelementptr i8, ptr %hp289, i64 8
  store i32 0, ptr %tgp290, align 4
  %fp291 = getelementptr i8, ptr %hp289, i64 16
  store ptr @strip_trailing$apply$34, ptr %fp291, align 8
  %strip_trailing.addr = alloca ptr
  store ptr %hp289, ptr %strip_trailing.addr
  %ld292 = load ptr, ptr %strip_trailing.addr
  %fp293 = getelementptr i8, ptr %ld292, i64 16
  %fv294 = load ptr, ptr %fp293, align 8
  %ld295 = load ptr, ptr %lines.addr
  %cr296 = call ptr (ptr, ptr) %fv294(ptr %ld292, ptr %ld295)
  %$t1311.addr = alloca ptr
  store ptr %cr296, ptr %$t1311.addr
  %ld297 = load ptr, ptr %$t1306.addr
  %ld298 = load ptr, ptr %$t1311.addr
  %rc299 = load i64, ptr %ld297, align 8
  %uniq300 = icmp eq i64 %rc299, 1
  %fbip_slot301 = alloca ptr
  br i1 %uniq300, label %fbip_reuse64, label %fbip_fresh65
fbip_reuse64:
  %tgp302 = getelementptr i8, ptr %ld297, i64 8
  store i32 0, ptr %tgp302, align 4
  %fp303 = getelementptr i8, ptr %ld297, i64 16
  store ptr %ld298, ptr %fp303, align 8
  store ptr %ld297, ptr %fbip_slot301
  br label %fbip_merge66
fbip_fresh65:
  call void @march_decrc(ptr %ld297)
  %hp304 = call ptr @march_alloc(i64 24)
  %tgp305 = getelementptr i8, ptr %hp304, i64 8
  store i32 0, ptr %tgp305, align 4
  %fp306 = getelementptr i8, ptr %hp304, i64 16
  store ptr %ld298, ptr %fp306, align 8
  store ptr %hp304, ptr %fbip_slot301
  br label %fbip_merge66
fbip_merge66:
  %fbip_r307 = load ptr, ptr %fbip_slot301
  store ptr %fbip_r307, ptr %res_slot264
  br label %case_merge57
case_default58:
  unreachable
case_merge57:
  %case_r308 = load ptr, ptr %res_slot264
  ret ptr %case_r308
}

define ptr @File.read(ptr %path.arg) {
entry:
  %path.addr = alloca ptr
  store ptr %path.arg, ptr %path.addr
  %ld309 = load ptr, ptr %file_read.addr
  %fp310 = getelementptr i8, ptr %ld309, i64 16
  %fv311 = load ptr, ptr %fp310, align 8
  %ld312 = load ptr, ptr %path.addr
  %cr313 = call ptr (ptr, ptr) %fv311(ptr %ld309, ptr %ld312)
  ret ptr %cr313
}

define ptr @List.fold_left$V__802$List_V__803$Fn_V__802_Fn_V__803_V__802(ptr %acc.arg, ptr %xs.arg, ptr %f.arg) {
entry:
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld314 = load ptr, ptr %xs.addr
  %res_slot315 = alloca ptr
  %tgp316 = getelementptr i8, ptr %ld314, i64 8
  %tag317 = load i32, ptr %tgp316, align 4
  switch i32 %tag317, label %case_default68 [
      i32 0, label %case_br69
      i32 1, label %case_br70
  ]
case_br69:
  %ld318 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld318)
  %ld319 = load ptr, ptr %acc.addr
  store ptr %ld319, ptr %res_slot315
  br label %case_merge67
case_br70:
  %fp320 = getelementptr i8, ptr %ld314, i64 16
  %fv321 = load ptr, ptr %fp320, align 8
  %$f151.addr = alloca ptr
  store ptr %fv321, ptr %$f151.addr
  %fp322 = getelementptr i8, ptr %ld314, i64 24
  %fv323 = load ptr, ptr %fp322, align 8
  %$f152.addr = alloca ptr
  store ptr %fv323, ptr %$f152.addr
  %freed324 = call i64 @march_decrc_freed(ptr %ld314)
  %freed_b325 = icmp ne i64 %freed324, 0
  br i1 %freed_b325, label %br_unique71, label %br_shared72
br_shared72:
  call void @march_incrc(ptr %fv323)
  call void @march_incrc(ptr %fv321)
  br label %br_body73
br_unique71:
  br label %br_body73
br_body73:
  %ld326 = load ptr, ptr %$f152.addr
  %t.addr = alloca ptr
  store ptr %ld326, ptr %t.addr
  %ld327 = load ptr, ptr %$f151.addr
  %h.addr = alloca ptr
  store ptr %ld327, ptr %h.addr
  %ld328 = load ptr, ptr %f.addr
  %fp329 = getelementptr i8, ptr %ld328, i64 16
  %fv330 = load ptr, ptr %fp329, align 8
  %ld331 = load ptr, ptr %acc.addr
  %ld332 = load ptr, ptr %h.addr
  %cr333 = call ptr (ptr, ptr, ptr) %fv330(ptr %ld328, ptr %ld331, ptr %ld332)
  %$t150.addr = alloca ptr
  store ptr %cr333, ptr %$t150.addr
  %ld334 = load ptr, ptr %$t150.addr
  %ld335 = load ptr, ptr %t.addr
  %ld336 = load ptr, ptr %f.addr
  %cr337 = call ptr @List.fold_left$V__802$List_V__803$Fn_V__802_Fn_V__803_V__802(ptr %ld334, ptr %ld335, ptr %ld336)
  store ptr %cr337, ptr %res_slot315
  br label %case_merge67
case_default68:
  unreachable
case_merge67:
  %case_r338 = load ptr, ptr %res_slot315
  ret ptr %case_r338
}

define ptr @Seq.rev$List_V__6096(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp339 = call ptr @march_alloc(i64 24)
  %tgp340 = getelementptr i8, ptr %hp339, i64 8
  store i32 0, ptr %tgp340, align 4
  %fp341 = getelementptr i8, ptr %hp339, i64 16
  store ptr @go$apply$36, ptr %fp341, align 8
  %go.addr = alloca ptr
  store ptr %hp339, ptr %go.addr
  %hp342 = call ptr @march_alloc(i64 16)
  %tgp343 = getelementptr i8, ptr %hp342, i64 8
  store i32 0, ptr %tgp343, align 4
  %$t1150.addr = alloca ptr
  store ptr %hp342, ptr %$t1150.addr
  %ld344 = load ptr, ptr %go.addr
  %fp345 = getelementptr i8, ptr %ld344, i64 16
  %fv346 = load ptr, ptr %fp345, align 8
  %ld347 = load ptr, ptr %xs.addr
  %ld348 = load ptr, ptr %$t1150.addr
  %cr349 = call ptr (ptr, ptr, ptr) %fv346(ptr %ld344, ptr %ld347, ptr %ld348)
  ret ptr %cr349
}

define ptr @Seq.fold(ptr %seq.arg, ptr %start.arg, ptr %f.arg) {
entry:
  %seq.addr = alloca ptr
  store ptr %seq.arg, ptr %seq.addr
  %start.addr = alloca ptr
  store ptr %start.arg, ptr %start.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld350 = load ptr, ptr %seq.addr
  %res_slot351 = alloca ptr
  %tgp352 = getelementptr i8, ptr %ld350, i64 8
  %tag353 = load i32, ptr %tgp352, align 4
  switch i32 %tag353, label %case_default75 [
      i32 0, label %case_br76
  ]
case_br76:
  %fp354 = getelementptr i8, ptr %ld350, i64 16
  %fv355 = load ptr, ptr %fp354, align 8
  %$f1248.addr = alloca ptr
  store ptr %fv355, ptr %$f1248.addr
  %freed356 = call i64 @march_decrc_freed(ptr %ld350)
  %freed_b357 = icmp ne i64 %freed356, 0
  br i1 %freed_b357, label %br_unique77, label %br_shared78
br_shared78:
  call void @march_incrc(ptr %fv355)
  br label %br_body79
br_unique77:
  br label %br_body79
br_body79:
  %ld358 = load ptr, ptr %$f1248.addr
  %folder.addr = alloca ptr
  store ptr %ld358, ptr %folder.addr
  %ld359 = load ptr, ptr %folder.addr
  %fp360 = getelementptr i8, ptr %ld359, i64 16
  %fv361 = load ptr, ptr %fp360, align 8
  %ld362 = load ptr, ptr %start.addr
  %ld363 = load ptr, ptr %f.addr
  %cr364 = call ptr (ptr, ptr, ptr) %fv361(ptr %ld359, ptr %ld362, ptr %ld363)
  store ptr %cr364, ptr %res_slot351
  br label %case_merge74
case_default75:
  unreachable
case_merge74:
  %case_r365 = load ptr, ptr %res_slot351
  ret ptr %case_r365
}

define ptr @Seq.count(ptr %seq.arg) {
entry:
  %seq.addr = alloca ptr
  store ptr %seq.arg, ptr %seq.addr
  %ld366 = load ptr, ptr %seq.addr
  %res_slot367 = alloca ptr
  %tgp368 = getelementptr i8, ptr %ld366, i64 8
  %tag369 = load i32, ptr %tgp368, align 4
  switch i32 %tag369, label %case_default81 [
      i32 0, label %case_br82
  ]
case_br82:
  %fp370 = getelementptr i8, ptr %ld366, i64 16
  %fv371 = load ptr, ptr %fp370, align 8
  %$f1263.addr = alloca ptr
  store ptr %fv371, ptr %$f1263.addr
  %freed372 = call i64 @march_decrc_freed(ptr %ld366)
  %freed_b373 = icmp ne i64 %freed372, 0
  br i1 %freed_b373, label %br_unique83, label %br_shared84
br_shared84:
  call void @march_incrc(ptr %fv371)
  br label %br_body85
br_unique83:
  br label %br_body85
br_body85:
  %ld374 = load ptr, ptr %$f1263.addr
  %folder.addr = alloca ptr
  store ptr %ld374, ptr %folder.addr
  %hp375 = call ptr @march_alloc(i64 24)
  %tgp376 = getelementptr i8, ptr %hp375, i64 8
  store i32 0, ptr %tgp376, align 4
  %fp377 = getelementptr i8, ptr %hp375, i64 16
  store ptr @$lam1261$apply$37, ptr %fp377, align 8
  %$t1262.addr = alloca ptr
  store ptr %hp375, ptr %$t1262.addr
  %ld378 = load ptr, ptr %folder.addr
  %fp379 = getelementptr i8, ptr %ld378, i64 16
  %fv380 = load ptr, ptr %fp379, align 8
  %ld381 = load ptr, ptr %$t1262.addr
  %cr382 = call ptr (ptr, i64, ptr) %fv380(ptr %ld378, i64 0, ptr %ld381)
  store ptr %cr382, ptr %res_slot367
  br label %case_merge80
case_default81:
  unreachable
case_merge80:
  %case_r383 = load ptr, ptr %res_slot367
  ret ptr %case_r383
}

define ptr @$lam2022$apply$22(ptr %$clo.arg, ptr %lines.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lines.addr = alloca ptr
  store ptr %lines.arg, ptr %lines.addr
  %ld384 = load ptr, ptr %lines.addr
  %cr385 = call ptr @Seq.take$Seq_Fn_T_List_String_Int_Fn_T_List_String_Int_String_T_List_String_Int_T_List_String_Int$Int(ptr %ld384, i64 3)
  %$t2023.addr = alloca ptr
  store ptr %cr385, ptr %$t2023.addr
  %ld386 = load ptr, ptr %$t2023.addr
  %cr387 = call ptr @Seq.to_list$Seq_Fn_List_String_Fn_List_String_String_List_String_List_V__6096(ptr %ld386)
  ret ptr %cr387
}

define ptr @$lam2028$apply$23(ptr %$clo.arg, ptr %acc.arg, ptr %line.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %line.addr = alloca ptr
  store ptr %line.arg, ptr %line.addr
  %ld388 = load ptr, ptr %acc.addr
  %ld389 = load ptr, ptr %line.addr
  %cr390 = call ptr @march_string_concat(ptr %ld388, ptr %ld389)
  %$t2029.addr = alloca ptr
  store ptr %cr390, ptr %$t2029.addr
  %ld391 = load ptr, ptr %$t2029.addr
  %sl392 = call ptr @march_string_lit(ptr @.str11, i64 1)
  %cr393 = call ptr @march_string_concat(ptr %ld391, ptr %sl392)
  ret ptr %cr393
}

define ptr @go$apply$25(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld394 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld394, ptr %go.addr
  %ld395 = load ptr, ptr %lst.addr
  %res_slot396 = alloca ptr
  %tgp397 = getelementptr i8, ptr %ld395, i64 8
  %tag398 = load i32, ptr %tgp397, align 4
  switch i32 %tag398, label %case_default87 [
      i32 0, label %case_br88
      i32 1, label %case_br89
  ]
case_br88:
  %ld399 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld399)
  %ld400 = load ptr, ptr %acc.addr
  store ptr %ld400, ptr %res_slot396
  br label %case_merge86
case_br89:
  %fp401 = getelementptr i8, ptr %ld395, i64 16
  %fv402 = load ptr, ptr %fp401, align 8
  %$f127.addr = alloca ptr
  store ptr %fv402, ptr %$f127.addr
  %fp403 = getelementptr i8, ptr %ld395, i64 24
  %fv404 = load ptr, ptr %fp403, align 8
  %$f128.addr = alloca ptr
  store ptr %fv404, ptr %$f128.addr
  %ld405 = load ptr, ptr %$f128.addr
  %t.addr = alloca ptr
  store ptr %ld405, ptr %t.addr
  %ld406 = load ptr, ptr %$f127.addr
  %h.addr = alloca ptr
  store ptr %ld406, ptr %h.addr
  %ld407 = load ptr, ptr %lst.addr
  %ld408 = load ptr, ptr %h.addr
  %ld409 = load ptr, ptr %acc.addr
  %rc410 = load i64, ptr %ld407, align 8
  %uniq411 = icmp eq i64 %rc410, 1
  %fbip_slot412 = alloca ptr
  br i1 %uniq411, label %fbip_reuse90, label %fbip_fresh91
fbip_reuse90:
  %tgp413 = getelementptr i8, ptr %ld407, i64 8
  store i32 1, ptr %tgp413, align 4
  %fp414 = getelementptr i8, ptr %ld407, i64 16
  store ptr %ld408, ptr %fp414, align 8
  %fp415 = getelementptr i8, ptr %ld407, i64 24
  store ptr %ld409, ptr %fp415, align 8
  store ptr %ld407, ptr %fbip_slot412
  br label %fbip_merge92
fbip_fresh91:
  call void @march_decrc(ptr %ld407)
  %hp416 = call ptr @march_alloc(i64 32)
  %tgp417 = getelementptr i8, ptr %hp416, i64 8
  store i32 1, ptr %tgp417, align 4
  %fp418 = getelementptr i8, ptr %hp416, i64 16
  store ptr %ld408, ptr %fp418, align 8
  %fp419 = getelementptr i8, ptr %hp416, i64 24
  store ptr %ld409, ptr %fp419, align 8
  store ptr %hp416, ptr %fbip_slot412
  br label %fbip_merge92
fbip_merge92:
  %fbip_r420 = load ptr, ptr %fbip_slot412
  %$t126.addr = alloca ptr
  store ptr %fbip_r420, ptr %$t126.addr
  %ld421 = load ptr, ptr %go.addr
  %fp422 = getelementptr i8, ptr %ld421, i64 16
  %fv423 = load ptr, ptr %fp422, align 8
  %ld424 = load ptr, ptr %t.addr
  %ld425 = load ptr, ptr %$t126.addr
  %cr426 = call ptr (ptr, ptr, ptr) %fv423(ptr %ld421, ptr %ld424, ptr %ld425)
  store ptr %cr426, ptr %res_slot396
  br label %case_merge86
case_default87:
  unreachable
case_merge86:
  %case_r427 = load ptr, ptr %res_slot396
  ret ptr %case_r427
}

define ptr @do_lines$apply$26(ptr %$clo.arg, ptr %a.arg, ptr %f.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld428 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld428)
  %ld429 = load ptr, ptr %$clo.addr
  %do_lines.addr = alloca ptr
  store ptr %ld429, ptr %do_lines.addr
  %ld430 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld430)
  %ld431 = load ptr, ptr %$clo.addr
  %fp432 = getelementptr i8, ptr %ld431, i64 24
  %fv433 = load ptr, ptr %fp432, align 8
  %cv434 = ptrtoint ptr %fv433 to i64
  %fd.addr = alloca i64
  store i64 %cv434, ptr %fd.addr
  %ld435 = load ptr, ptr %$clo.addr
  %fp436 = getelementptr i8, ptr %ld435, i64 32
  %fv437 = load ptr, ptr %fp436, align 8
  %file_read_line.addr = alloca ptr
  store ptr %fv437, ptr %file_read_line.addr
  %ld438 = load ptr, ptr %file_read_line.addr
  %fp439 = getelementptr i8, ptr %ld438, i64 16
  %fv440 = load ptr, ptr %fp439, align 8
  %ld441 = load i64, ptr %fd.addr
  %cr442 = call ptr (ptr, i64) %fv440(ptr %ld438, i64 %ld441)
  %$t1315.addr = alloca ptr
  store ptr %cr442, ptr %$t1315.addr
  %ld443 = load ptr, ptr %$t1315.addr
  %res_slot444 = alloca ptr
  %tgp445 = getelementptr i8, ptr %ld443, i64 8
  %tag446 = load i32, ptr %tgp445, align 4
  switch i32 %tag446, label %case_default94 [
      i32 0, label %case_br95
      i32 1, label %case_br96
  ]
case_br95:
  %ld447 = load ptr, ptr %$t1315.addr
  call void @march_decrc(ptr %ld447)
  %ld448 = load ptr, ptr %a.addr
  store ptr %ld448, ptr %res_slot444
  br label %case_merge93
case_br96:
  %fp449 = getelementptr i8, ptr %ld443, i64 16
  %fv450 = load ptr, ptr %fp449, align 8
  %$f1317.addr = alloca ptr
  store ptr %fv450, ptr %$f1317.addr
  %freed451 = call i64 @march_decrc_freed(ptr %ld443)
  %freed_b452 = icmp ne i64 %freed451, 0
  br i1 %freed_b452, label %br_unique97, label %br_shared98
br_shared98:
  call void @march_incrc(ptr %fv450)
  br label %br_body99
br_unique97:
  br label %br_body99
br_body99:
  %ld453 = load ptr, ptr %$f1317.addr
  %line.addr = alloca ptr
  store ptr %ld453, ptr %line.addr
  %ld454 = load ptr, ptr %f.addr
  %fp455 = getelementptr i8, ptr %ld454, i64 16
  %fv456 = load ptr, ptr %fp455, align 8
  %ld457 = load ptr, ptr %a.addr
  %ld458 = load ptr, ptr %line.addr
  %cr459 = call ptr (ptr, ptr, ptr) %fv456(ptr %ld454, ptr %ld457, ptr %ld458)
  %$t1316.addr = alloca ptr
  store ptr %cr459, ptr %$t1316.addr
  %ld460 = load ptr, ptr %do_lines.addr
  %fp461 = getelementptr i8, ptr %ld460, i64 16
  %fv462 = load ptr, ptr %fp461, align 8
  %ld463 = load ptr, ptr %$t1316.addr
  %ld464 = load ptr, ptr %f.addr
  %cr465 = call ptr (ptr, ptr, ptr) %fv462(ptr %ld460, ptr %ld463, ptr %ld464)
  store ptr %cr465, ptr %res_slot444
  br label %case_merge93
case_default94:
  unreachable
case_merge93:
  %case_r466 = load ptr, ptr %res_slot444
  ret ptr %case_r466
}

define ptr @$lam1318$apply$27(ptr %$clo.arg, ptr %acc.arg, ptr %f.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld467 = load ptr, ptr %$clo.addr
  %fp468 = getelementptr i8, ptr %ld467, i64 24
  %fv469 = load ptr, ptr %fp468, align 8
  %do_lines.addr = alloca ptr
  store ptr %fv469, ptr %do_lines.addr
  %ld470 = load ptr, ptr %do_lines.addr
  %fp471 = getelementptr i8, ptr %ld470, i64 16
  %fv472 = load ptr, ptr %fp471, align 8
  %ld473 = load ptr, ptr %acc.addr
  %ld474 = load ptr, ptr %f.addr
  %cr475 = call ptr (ptr, ptr, ptr) %fv472(ptr %ld470, ptr %ld473, ptr %ld474)
  ret ptr %cr475
}

define ptr @$lam1244$apply$28(ptr %$clo.arg, ptr %acc.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %hp476 = call ptr @march_alloc(i64 32)
  %tgp477 = getelementptr i8, ptr %hp476, i64 8
  store i32 1, ptr %tgp477, align 4
  %ld478 = load ptr, ptr %x.addr
  %fp479 = getelementptr i8, ptr %hp476, i64 16
  store ptr %ld478, ptr %fp479, align 8
  %ld480 = load ptr, ptr %acc.addr
  %fp481 = getelementptr i8, ptr %hp476, i64 24
  store ptr %ld480, ptr %fp481, align 8
  ret ptr %hp476
}

define ptr @step_take$apply$29(ptr %$clo.arg, ptr %pair.arg, ptr %x.arg, ptr %f.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %pair.addr = alloca ptr
  store ptr %pair.arg, ptr %pair.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld482 = load ptr, ptr %$clo.addr
  %fp483 = getelementptr i8, ptr %ld482, i64 24
  %fv484 = load i64, ptr %fp483, align 8
  %n.addr = alloca i64
  store i64 %fv484, ptr %n.addr
  %ld485 = load ptr, ptr %pair.addr
  %$p1190.addr = alloca ptr
  store ptr %ld485, ptr %$p1190.addr
  %ld486 = load ptr, ptr %$p1190.addr
  %fp487 = getelementptr i8, ptr %ld486, i64 16
  %fv488 = load ptr, ptr %fp487, align 8
  %a.addr = alloca ptr
  store ptr %fv488, ptr %a.addr
  %ld489 = load ptr, ptr %$p1190.addr
  %fp490 = getelementptr i8, ptr %ld489, i64 24
  %fv491 = load ptr, ptr %fp490, align 8
  %count.addr = alloca ptr
  store ptr %fv491, ptr %count.addr
  %ld492 = load ptr, ptr %count.addr
  call void @march_free(ptr %ld492)
  %ld493 = load i64, ptr %n.addr
  %cv496 = ptrtoint ptr @Seq.count to i64
  %cmp494 = icmp sge i64 %cv496, %ld493
  %ar495 = zext i1 %cmp494 to i64
  %$t1187.addr = alloca i64
  store i64 %ar495, ptr %$t1187.addr
  %ld497 = load i64, ptr %$t1187.addr
  %res_slot498 = alloca ptr
  %bi499 = trunc i64 %ld497 to i1
  br i1 %bi499, label %case_br102, label %case_default101
case_br102:
  %hp500 = call ptr @march_alloc(i64 32)
  %tgp501 = getelementptr i8, ptr %hp500, i64 8
  store i32 0, ptr %tgp501, align 4
  %ld502 = load ptr, ptr %a.addr
  %fp503 = getelementptr i8, ptr %hp500, i64 16
  store ptr %ld502, ptr %fp503, align 8
  %fp504 = getelementptr i8, ptr %hp500, i64 24
  store ptr @Seq.count, ptr %fp504, align 8
  store ptr %hp500, ptr %res_slot498
  br label %case_merge100
case_default101:
  %ld505 = load ptr, ptr %f.addr
  %fp506 = getelementptr i8, ptr %ld505, i64 16
  %fv507 = load ptr, ptr %fp506, align 8
  %ld508 = load ptr, ptr %a.addr
  %ld509 = load ptr, ptr %x.addr
  %cr510 = call ptr (ptr, ptr, ptr) %fv507(ptr %ld505, ptr %ld508, ptr %ld509)
  %$t1188.addr = alloca ptr
  store ptr %cr510, ptr %$t1188.addr
  %cv511 = ptrtoint ptr @Seq.count to i64
  %ar512 = add i64 %cv511, 1
  %$t1189.addr = alloca i64
  store i64 %ar512, ptr %$t1189.addr
  %hp513 = call ptr @march_alloc(i64 32)
  %tgp514 = getelementptr i8, ptr %hp513, i64 8
  store i32 0, ptr %tgp514, align 4
  %ld515 = load ptr, ptr %$t1188.addr
  %fp516 = getelementptr i8, ptr %hp513, i64 16
  store ptr %ld515, ptr %fp516, align 8
  %ld517 = load i64, ptr %$t1189.addr
  %fp518 = getelementptr i8, ptr %hp513, i64 24
  store i64 %ld517, ptr %fp518, align 8
  store ptr %hp513, ptr %res_slot498
  br label %case_merge100
case_merge100:
  %case_r519 = load ptr, ptr %res_slot498
  ret ptr %case_r519
}

define ptr @run_take$apply$30(ptr %$clo.arg, ptr %fold.arg, ptr %acc.arg, ptr %f.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %fold.addr = alloca ptr
  store ptr %fold.arg, ptr %fold.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld520 = load ptr, ptr %$clo.addr
  %fp521 = getelementptr i8, ptr %ld520, i64 24
  %fv522 = load ptr, ptr %fp521, align 8
  %step_take.addr = alloca ptr
  store ptr %fv522, ptr %step_take.addr
  %hp523 = call ptr @march_alloc(i64 32)
  %tgp524 = getelementptr i8, ptr %hp523, i64 8
  store i32 0, ptr %tgp524, align 4
  %ld525 = load ptr, ptr %acc.addr
  %fp526 = getelementptr i8, ptr %hp523, i64 16
  store ptr %ld525, ptr %fp526, align 8
  %fp527 = getelementptr i8, ptr %hp523, i64 24
  store i64 0, ptr %fp527, align 8
  %$t1191.addr = alloca ptr
  store ptr %hp523, ptr %$t1191.addr
  %hp528 = call ptr @march_alloc(i64 40)
  %tgp529 = getelementptr i8, ptr %hp528, i64 8
  store i32 0, ptr %tgp529, align 4
  %fp530 = getelementptr i8, ptr %hp528, i64 16
  store ptr @$lam1192$apply$31, ptr %fp530, align 8
  %ld531 = load ptr, ptr %f.addr
  %fp532 = getelementptr i8, ptr %hp528, i64 24
  store ptr %ld531, ptr %fp532, align 8
  %ld533 = load ptr, ptr %step_take.addr
  %fp534 = getelementptr i8, ptr %hp528, i64 32
  store ptr %ld533, ptr %fp534, align 8
  %$t1193.addr = alloca ptr
  store ptr %hp528, ptr %$t1193.addr
  %ld535 = load ptr, ptr %$t1191.addr
  %ld536 = load ptr, ptr %$t1193.addr
  %cr537 = call ptr @Seq.fold(ptr %ld535, ptr %ld536)
  %result.addr = alloca ptr
  store ptr %cr537, ptr %result.addr
  %ld538 = load ptr, ptr %result.addr
  %$p1194.addr = alloca ptr
  store ptr %ld538, ptr %$p1194.addr
  %ld539 = load ptr, ptr %$p1194.addr
  %fp540 = getelementptr i8, ptr %ld539, i64 16
  %fv541 = load ptr, ptr %fp540, align 8
  %a.addr = alloca ptr
  store ptr %fv541, ptr %a.addr
  %ld542 = load ptr, ptr %$p1194.addr
  %fp543 = getelementptr i8, ptr %ld542, i64 24
  %fv544 = load ptr, ptr %fp543, align 8
  %ig.addr = alloca ptr
  store ptr %fv544, ptr %ig.addr
  %ld545 = load ptr, ptr %ig.addr
  call void @march_free(ptr %ld545)
  %ld546 = load ptr, ptr %a.addr
  ret ptr %ld546
}

define ptr @$lam1192$apply$31(ptr %$clo.arg, ptr %pair.arg, ptr %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %pair.addr = alloca ptr
  store ptr %pair.arg, ptr %pair.addr
  %x.addr = alloca ptr
  store ptr %x.arg, ptr %x.addr
  %ld547 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld547)
  %ld548 = load ptr, ptr %$clo.addr
  %fp549 = getelementptr i8, ptr %ld548, i64 24
  %fv550 = load ptr, ptr %fp549, align 8
  %f.addr = alloca ptr
  store ptr %fv550, ptr %f.addr
  %ld551 = load ptr, ptr %$clo.addr
  %fp552 = getelementptr i8, ptr %ld551, i64 32
  %fv553 = load ptr, ptr %fp552, align 8
  %step_take.addr = alloca ptr
  store ptr %fv553, ptr %step_take.addr
  %ld554 = load ptr, ptr %step_take.addr
  %fp555 = getelementptr i8, ptr %ld554, i64 16
  %fv556 = load ptr, ptr %fp555, align 8
  %ld557 = load ptr, ptr %pair.addr
  %ld558 = load ptr, ptr %x.addr
  %ld559 = load ptr, ptr %f.addr
  %cr560 = call ptr (ptr, ptr, ptr, ptr) %fv556(ptr %ld554, ptr %ld557, ptr %ld558, ptr %ld559)
  ret ptr %cr560
}

define ptr @$lam1195$apply$32(ptr %$clo.arg, ptr %acc.arg, ptr %f.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %f.addr = alloca ptr
  store ptr %f.arg, ptr %f.addr
  %ld561 = load ptr, ptr %$clo.addr
  %fp562 = getelementptr i8, ptr %ld561, i64 24
  %fv563 = load ptr, ptr %fp562, align 8
  %run_take.addr = alloca ptr
  store ptr %fv563, ptr %run_take.addr
  %ld564 = load ptr, ptr %run_take.addr
  %fp565 = getelementptr i8, ptr %ld564, i64 16
  %fv566 = load ptr, ptr %fp565, align 8
  %cwrap567 = call ptr @march_alloc(i64 24)
  %cwt568 = getelementptr i8, ptr %cwrap567, i64 8
  store i32 0, ptr %cwt568, align 4
  %cwf569 = getelementptr i8, ptr %cwrap567, i64 16
  store ptr @Seq.fold$clo_wrap, ptr %cwf569, align 8
  %ld570 = load ptr, ptr %acc.addr
  %ld571 = load ptr, ptr %f.addr
  %cr572 = call ptr (ptr, ptr, ptr, ptr) %fv566(ptr %ld564, ptr %cwrap567, ptr %ld570, ptr %ld571)
  ret ptr %cr572
}

define i64 @go$apply$33(ptr %$clo.arg, ptr %lst.arg, i64 %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld573 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld573, ptr %go.addr
  %ld574 = load ptr, ptr %lst.addr
  %res_slot575 = alloca ptr
  %tgp576 = getelementptr i8, ptr %ld574, i64 8
  %tag577 = load i32, ptr %tgp576, align 4
  switch i32 %tag577, label %case_default104 [
      i32 0, label %case_br105
      i32 1, label %case_br106
  ]
case_br105:
  %ld578 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld578)
  %ld579 = load i64, ptr %acc.addr
  %cv580 = inttoptr i64 %ld579 to ptr
  store ptr %cv580, ptr %res_slot575
  br label %case_merge103
case_br106:
  %fp581 = getelementptr i8, ptr %ld574, i64 16
  %fv582 = load ptr, ptr %fp581, align 8
  %$f124.addr = alloca ptr
  store ptr %fv582, ptr %$f124.addr
  %fp583 = getelementptr i8, ptr %ld574, i64 24
  %fv584 = load ptr, ptr %fp583, align 8
  %$f125.addr = alloca ptr
  store ptr %fv584, ptr %$f125.addr
  %freed585 = call i64 @march_decrc_freed(ptr %ld574)
  %freed_b586 = icmp ne i64 %freed585, 0
  br i1 %freed_b586, label %br_unique107, label %br_shared108
br_shared108:
  call void @march_incrc(ptr %fv584)
  call void @march_incrc(ptr %fv582)
  br label %br_body109
br_unique107:
  br label %br_body109
br_body109:
  %ld587 = load ptr, ptr %$f125.addr
  %t.addr = alloca ptr
  store ptr %ld587, ptr %t.addr
  %ld588 = load i64, ptr %acc.addr
  %ar589 = add i64 %ld588, 1
  %$t123.addr = alloca i64
  store i64 %ar589, ptr %$t123.addr
  %ld590 = load ptr, ptr %go.addr
  %fp591 = getelementptr i8, ptr %ld590, i64 16
  %fv592 = load ptr, ptr %fp591, align 8
  %ld593 = load ptr, ptr %t.addr
  %ld594 = load i64, ptr %$t123.addr
  %cr595 = call i64 (ptr, ptr, i64) %fv592(ptr %ld590, ptr %ld593, i64 %ld594)
  %cv596 = inttoptr i64 %cr595 to ptr
  store ptr %cv596, ptr %res_slot575
  br label %case_merge103
case_default104:
  unreachable
case_merge103:
  %case_r597 = load ptr, ptr %res_slot575
  %cv598 = ptrtoint ptr %case_r597 to i64
  ret i64 %cv598
}

define ptr @strip_trailing$apply$34(ptr %$clo.arg, ptr %xs.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld599 = load ptr, ptr %$clo.addr
  %strip_trailing.addr = alloca ptr
  store ptr %ld599, ptr %strip_trailing.addr
  %ld600 = load ptr, ptr %xs.addr
  call void @march_incrc(ptr %ld600)
  %ld601 = load ptr, ptr %xs.addr
  %cr602 = call ptr @List.reverse$List_String(ptr %ld601)
  %$t1307.addr = alloca ptr
  store ptr %cr602, ptr %$t1307.addr
  %ld603 = load ptr, ptr %$t1307.addr
  %res_slot604 = alloca ptr
  %tgp605 = getelementptr i8, ptr %ld603, i64 8
  %tag606 = load i32, ptr %tgp605, align 4
  switch i32 %tag606, label %case_default111 [
      i32 0, label %case_br112
      i32 1, label %case_br113
  ]
case_br112:
  %ld607 = load ptr, ptr %$t1307.addr
  %rc608 = load i64, ptr %ld607, align 8
  %uniq609 = icmp eq i64 %rc608, 1
  %fbip_slot610 = alloca ptr
  br i1 %uniq609, label %fbip_reuse114, label %fbip_fresh115
fbip_reuse114:
  %tgp611 = getelementptr i8, ptr %ld607, i64 8
  store i32 0, ptr %tgp611, align 4
  store ptr %ld607, ptr %fbip_slot610
  br label %fbip_merge116
fbip_fresh115:
  call void @march_decrc(ptr %ld607)
  %hp612 = call ptr @march_alloc(i64 16)
  %tgp613 = getelementptr i8, ptr %hp612, i64 8
  store i32 0, ptr %tgp613, align 4
  store ptr %hp612, ptr %fbip_slot610
  br label %fbip_merge116
fbip_merge116:
  %fbip_r614 = load ptr, ptr %fbip_slot610
  store ptr %fbip_r614, ptr %res_slot604
  br label %case_merge110
case_br113:
  %fp615 = getelementptr i8, ptr %ld603, i64 16
  %fv616 = load ptr, ptr %fp615, align 8
  %$f1309.addr = alloca ptr
  store ptr %fv616, ptr %$f1309.addr
  %fp617 = getelementptr i8, ptr %ld603, i64 24
  %fv618 = load ptr, ptr %fp617, align 8
  %$f1310.addr = alloca ptr
  store ptr %fv618, ptr %$f1310.addr
  %ld619 = load ptr, ptr %$f1309.addr
  %res_slot620 = alloca ptr
  %sl621 = call ptr @march_string_lit(ptr @.str12, i64 0)
  %seq622 = call i64 @march_string_eq(ptr %ld619, ptr %sl621)
  %cmp623 = icmp ne i64 %seq622, 0
  br i1 %cmp623, label %case_br119, label %str_next120
str_next120:
  br label %case_default118
case_br119:
  %ld624 = load ptr, ptr %$f1309.addr
  call void @march_decrc(ptr %ld624)
  %ld625 = load ptr, ptr %$f1310.addr
  %rest.addr = alloca ptr
  store ptr %ld625, ptr %rest.addr
  %ld626 = load ptr, ptr %rest.addr
  %cr627 = call ptr @List.reverse$List_String(ptr %ld626)
  %$t1308.addr = alloca ptr
  store ptr %cr627, ptr %$t1308.addr
  %ld628 = load ptr, ptr %strip_trailing.addr
  %fp629 = getelementptr i8, ptr %ld628, i64 16
  %fv630 = load ptr, ptr %fp629, align 8
  %ld631 = load ptr, ptr %$t1308.addr
  %cr632 = call ptr (ptr, ptr) %fv630(ptr %ld628, ptr %ld631)
  store ptr %cr632, ptr %res_slot620
  br label %case_merge117
case_default118:
  %ld633 = load ptr, ptr %$f1309.addr
  call void @march_decrc(ptr %ld633)
  %ld634 = load ptr, ptr %$t1307.addr
  %ig.addr = alloca ptr
  store ptr %ld634, ptr %ig.addr
  %ld635 = load ptr, ptr %ig.addr
  call void @march_decrc(ptr %ld635)
  %ld636 = load ptr, ptr %xs.addr
  store ptr %ld636, ptr %res_slot620
  br label %case_merge117
case_merge117:
  %case_r637 = load ptr, ptr %res_slot620
  store ptr %case_r637, ptr %res_slot604
  br label %case_merge110
case_default111:
  %ld638 = load ptr, ptr %$t1307.addr
  %ig_1.addr = alloca ptr
  store ptr %ld638, ptr %ig_1.addr
  %ld639 = load ptr, ptr %ig_1.addr
  call void @march_decrc(ptr %ld639)
  %ld640 = load ptr, ptr %xs.addr
  store ptr %ld640, ptr %res_slot604
  br label %case_merge110
case_merge110:
  %case_r641 = load ptr, ptr %res_slot604
  ret ptr %case_r641
}

define ptr @go$apply$36(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld642 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld642, ptr %go.addr
  %ld643 = load ptr, ptr %lst.addr
  %res_slot644 = alloca ptr
  %tgp645 = getelementptr i8, ptr %ld643, i64 8
  %tag646 = load i32, ptr %tgp645, align 4
  switch i32 %tag646, label %case_default122 [
      i32 0, label %case_br123
      i32 1, label %case_br124
  ]
case_br123:
  %ld647 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld647)
  %ld648 = load ptr, ptr %acc.addr
  store ptr %ld648, ptr %res_slot644
  br label %case_merge121
case_br124:
  %fp649 = getelementptr i8, ptr %ld643, i64 16
  %fv650 = load ptr, ptr %fp649, align 8
  %$f1148.addr = alloca ptr
  store ptr %fv650, ptr %$f1148.addr
  %fp651 = getelementptr i8, ptr %ld643, i64 24
  %fv652 = load ptr, ptr %fp651, align 8
  %$f1149.addr = alloca ptr
  store ptr %fv652, ptr %$f1149.addr
  %ld653 = load ptr, ptr %$f1149.addr
  %t.addr = alloca ptr
  store ptr %ld653, ptr %t.addr
  %ld654 = load ptr, ptr %$f1148.addr
  %h.addr = alloca ptr
  store ptr %ld654, ptr %h.addr
  %ld655 = load ptr, ptr %lst.addr
  %ld656 = load ptr, ptr %h.addr
  %ld657 = load ptr, ptr %acc.addr
  %rc658 = load i64, ptr %ld655, align 8
  %uniq659 = icmp eq i64 %rc658, 1
  %fbip_slot660 = alloca ptr
  br i1 %uniq659, label %fbip_reuse125, label %fbip_fresh126
fbip_reuse125:
  %tgp661 = getelementptr i8, ptr %ld655, i64 8
  store i32 1, ptr %tgp661, align 4
  %fp662 = getelementptr i8, ptr %ld655, i64 16
  store ptr %ld656, ptr %fp662, align 8
  %fp663 = getelementptr i8, ptr %ld655, i64 24
  store ptr %ld657, ptr %fp663, align 8
  store ptr %ld655, ptr %fbip_slot660
  br label %fbip_merge127
fbip_fresh126:
  call void @march_decrc(ptr %ld655)
  %hp664 = call ptr @march_alloc(i64 32)
  %tgp665 = getelementptr i8, ptr %hp664, i64 8
  store i32 1, ptr %tgp665, align 4
  %fp666 = getelementptr i8, ptr %hp664, i64 16
  store ptr %ld656, ptr %fp666, align 8
  %fp667 = getelementptr i8, ptr %hp664, i64 24
  store ptr %ld657, ptr %fp667, align 8
  store ptr %hp664, ptr %fbip_slot660
  br label %fbip_merge127
fbip_merge127:
  %fbip_r668 = load ptr, ptr %fbip_slot660
  %$t1147.addr = alloca ptr
  store ptr %fbip_r668, ptr %$t1147.addr
  %ld669 = load ptr, ptr %go.addr
  %fp670 = getelementptr i8, ptr %ld669, i64 16
  %fv671 = load ptr, ptr %fp670, align 8
  %ld672 = load ptr, ptr %t.addr
  %ld673 = load ptr, ptr %$t1147.addr
  %cr674 = call ptr (ptr, ptr, ptr) %fv671(ptr %ld669, ptr %ld672, ptr %ld673)
  store ptr %cr674, ptr %res_slot644
  br label %case_merge121
case_default122:
  unreachable
case_merge121:
  %case_r675 = load ptr, ptr %res_slot644
  ret ptr %case_r675
}

define i64 @$lam1261$apply$37(ptr %$clo.arg, i64 %n.arg, ptr %ig.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ig.addr = alloca ptr
  store ptr %ig.arg, ptr %ig.addr
  %ld676 = load i64, ptr %n.addr
  %ar677 = add i64 %ld676, 1
  ret i64 %ar677
}

define i32 @main() {
entry:
  call void @march_main()
  call void @march_run_scheduler()
  ret i32 0
}
define ptr @Seq.fold$clo_wrap(ptr %_clo, ptr %a0, ptr %a1) {
entry:
  %r = call ptr @Seq.fold(ptr %a0, ptr %a1)
  ret ptr %r
}

