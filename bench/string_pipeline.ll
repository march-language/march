; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare void @march_free(ptr %p)
declare void @march_print(ptr %s)
declare void @march_println(ptr %s)
declare ptr  @march_string_lit(ptr %s, i64 %len)
declare ptr  @march_int_to_string(i64 %n)
declare ptr  @march_float_to_string(double %f)
declare ptr  @march_bool_to_string(i64 %b)
declare ptr  @march_string_concat(ptr %a, ptr %b)
declare i64  @march_string_eq(ptr %a, ptr %b)
declare i64  @march_string_byte_length(ptr %s)
declare i64  @march_string_is_empty(ptr %s)
declare ptr  @march_string_to_int(ptr %s)
declare ptr  @march_string_join(ptr %list, ptr %sep)
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)

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
  %$t351.addr = alloca i64
  store i64 %ar4, ptr %$t351.addr
  %ld5 = load i64, ptr %$t351.addr
  %res_slot6 = alloca ptr
  switch i64 %ld5, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld7 = load ptr, ptr %acc.addr
  store ptr %ld7, ptr %res_slot6
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %lo.addr
  %ar9 = add i64 %ld8, 1
  %$t352.addr = alloca i64
  store i64 %ar9, ptr %$t352.addr
  %ld10 = load i64, ptr %lo.addr
  %cr11 = call ptr @march_int_to_string(i64 %ld10)
  %$t353.addr = alloca ptr
  store ptr %cr11, ptr %$t353.addr
  %hp12 = call ptr @march_alloc(i64 32)
  %tgp13 = getelementptr i8, ptr %hp12, i64 8
  store i32 1, ptr %tgp13, align 4
  %ld14 = load ptr, ptr %$t353.addr
  %fp15 = getelementptr i8, ptr %hp12, i64 16
  store ptr %ld14, ptr %fp15, align 8
  %ld16 = load ptr, ptr %acc.addr
  %fp17 = getelementptr i8, ptr %hp12, i64 24
  store ptr %ld16, ptr %fp17, align 8
  %$t354.addr = alloca ptr
  store ptr %hp12, ptr %$t354.addr
  %ld18 = load i64, ptr %$t352.addr
  %ld19 = load i64, ptr %hi.addr
  %ld20 = load ptr, ptr %$t354.addr
  %cr21 = call ptr @build_list(i64 %ld18, i64 %ld19, ptr %ld20)
  store ptr %cr21, ptr %res_slot6
  br label %case_merge1
case_merge1:
  %case_r22 = load ptr, ptr %res_slot6
  ret ptr %case_r22
}

define ptr @double_str(ptr %s.arg) {
entry:
  %s.addr = alloca ptr
  store ptr %s.arg, ptr %s.addr
  %ld23 = load ptr, ptr %s.addr
  call void @march_incrc(ptr %ld23)
  %ld24 = load ptr, ptr %s.addr
  %cr25 = call ptr @march_string_to_int(ptr %ld24)
  %$t355.addr = alloca ptr
  store ptr %cr25, ptr %$t355.addr
  %ld26 = load ptr, ptr %$t355.addr
  %res_slot27 = alloca ptr
  %tgp28 = getelementptr i8, ptr %ld26, i64 8
  %tag29 = load i32, ptr %tgp28, align 4
  switch i32 %tag29, label %case_default5 [
      i32 1, label %case_br6
      i32 0, label %case_br7
  ]
case_br6:
  %fp30 = getelementptr i8, ptr %ld26, i64 16
  %fv31 = load ptr, ptr %fp30, align 8
  %n.addr = alloca ptr
  store ptr %fv31, ptr %n.addr
  %ld32 = load ptr, ptr %$t355.addr
  call void @march_decrc(ptr %ld32)
  %ld33 = load i64, ptr %n.addr
  %ld34 = load i64, ptr %n.addr
  %ar35 = add i64 %ld33, %ld34
  %sr_s1.addr = alloca i64
  store i64 %ar35, ptr %sr_s1.addr
  %ld36 = load i64, ptr %sr_s1.addr
  %$t356.addr = alloca i64
  store i64 %ld36, ptr %$t356.addr
  %ld37 = load i64, ptr %$t356.addr
  %cr38 = call ptr @march_int_to_string(i64 %ld37)
  store ptr %cr38, ptr %res_slot27
  br label %case_merge4
case_br7:
  %ld39 = load ptr, ptr %$t355.addr
  call void @march_decrc(ptr %ld39)
  %ld40 = load ptr, ptr %s.addr
  store ptr %ld40, ptr %res_slot27
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r41 = load ptr, ptr %res_slot27
  ret ptr %case_r41
}

define ptr @map_strings(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld42 = load ptr, ptr %xs.addr
  %res_slot43 = alloca ptr
  %tgp44 = getelementptr i8, ptr %ld42, i64 8
  %tag45 = load i32, ptr %tgp44, align 4
  switch i32 %tag45, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %ld46 = load ptr, ptr %xs.addr
  %tgp47 = getelementptr i8, ptr %ld46, i64 8
  store i32 0, ptr %tgp47, align 4
  store ptr %ld46, ptr %res_slot43
  br label %case_merge8
case_br11:
  %fp48 = getelementptr i8, ptr %ld42, i64 16
  %fv49 = load ptr, ptr %fp48, align 8
  %h.addr = alloca ptr
  store ptr %fv49, ptr %h.addr
  %fp50 = getelementptr i8, ptr %ld42, i64 24
  %fv51 = load ptr, ptr %fp50, align 8
  %t.addr = alloca ptr
  store ptr %fv51, ptr %t.addr
  %ld52 = load ptr, ptr %h.addr
  %cr53 = call ptr @double_str(ptr %ld52)
  %$t357.addr = alloca ptr
  store ptr %cr53, ptr %$t357.addr
  %ld54 = load ptr, ptr %t.addr
  %cr55 = call ptr @map_strings(ptr %ld54)
  %$t358.addr = alloca ptr
  store ptr %cr55, ptr %$t358.addr
  %ld56 = load ptr, ptr %xs.addr
  %tgp57 = getelementptr i8, ptr %ld56, i64 8
  store i32 1, ptr %tgp57, align 4
  %ld58 = load ptr, ptr %$t357.addr
  %fp59 = getelementptr i8, ptr %ld56, i64 16
  store ptr %ld58, ptr %fp59, align 8
  %ld60 = load ptr, ptr %$t358.addr
  %fp61 = getelementptr i8, ptr %ld56, i64 24
  store ptr %ld60, ptr %fp61, align 8
  store ptr %ld56, ptr %res_slot43
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r62 = load ptr, ptr %res_slot43
  ret ptr %case_r62
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 100000, ptr %n.addr
  %hp63 = call ptr @march_alloc(i64 16)
  %tgp64 = getelementptr i8, ptr %hp63, i64 8
  store i32 0, ptr %tgp64, align 4
  %$t359.addr = alloca ptr
  store ptr %hp63, ptr %$t359.addr
  %ld65 = load i64, ptr %n.addr
  %ld66 = load ptr, ptr %$t359.addr
  %cr67 = call ptr @build_list(i64 1, i64 %ld65, ptr %ld66)
  %pieces.addr = alloca ptr
  store ptr %cr67, ptr %pieces.addr
  %ld68 = load ptr, ptr %pieces.addr
  %cr69 = call ptr @map_strings(ptr %ld68)
  %doubled.addr = alloca ptr
  store ptr %cr69, ptr %doubled.addr
  %ld70 = load ptr, ptr %doubled.addr
  %sl71 = call ptr @march_string_lit(ptr @.str1, i64 1)
  %cr72 = call ptr @march_string_join(ptr %ld70, ptr %sl71)
  %result.addr = alloca ptr
  store ptr %cr72, ptr %result.addr
  %ld73 = load ptr, ptr %result.addr
  %cr74 = call i64 @march_string_byte_length(ptr %ld73)
  %$t360.addr = alloca i64
  store i64 %cr74, ptr %$t360.addr
  %ld75 = load i64, ptr %$t360.addr
  %cr76 = call ptr @march_int_to_string(i64 %ld75)
  %$t361.addr = alloca ptr
  store ptr %cr76, ptr %$t361.addr
  %ld77 = load ptr, ptr %$t361.addr
  call void @march_println(ptr %ld77)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
