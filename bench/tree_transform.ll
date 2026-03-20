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


define ptr @make(i64 %d.arg) {
entry:
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld1 = load i64, ptr %d.addr
  %cmp2 = icmp eq i64 %ld1, 0
  %ar3 = zext i1 %cmp2 to i64
  %$t351.addr = alloca i64
  store i64 %ar3, ptr %$t351.addr
  %ld4 = load i64, ptr %$t351.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %hp6 = call ptr @march_alloc(i64 24)
  %tgp7 = getelementptr i8, ptr %hp6, i64 8
  store i32 0, ptr %tgp7, align 4
  %fp8 = getelementptr i8, ptr %hp6, i64 16
  store i64 0, ptr %fp8, align 8
  store ptr %hp6, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld9 = load i64, ptr %d.addr
  %ar10 = sub i64 %ld9, 1
  %$t352.addr = alloca i64
  store i64 %ar10, ptr %$t352.addr
  %ld11 = load i64, ptr %$t352.addr
  %cr12 = call ptr @make(i64 %ld11)
  %$t353.addr = alloca ptr
  store ptr %cr12, ptr %$t353.addr
  %ld13 = load i64, ptr %d.addr
  %ar14 = sub i64 %ld13, 1
  %$t354.addr = alloca i64
  store i64 %ar14, ptr %$t354.addr
  %ld15 = load i64, ptr %$t354.addr
  %cr16 = call ptr @make(i64 %ld15)
  %$t355.addr = alloca ptr
  store ptr %cr16, ptr %$t355.addr
  %hp17 = call ptr @march_alloc(i64 32)
  %tgp18 = getelementptr i8, ptr %hp17, i64 8
  store i32 1, ptr %tgp18, align 4
  %ld19 = load ptr, ptr %$t353.addr
  %fp20 = getelementptr i8, ptr %hp17, i64 16
  store ptr %ld19, ptr %fp20, align 8
  %ld21 = load ptr, ptr %$t355.addr
  %fp22 = getelementptr i8, ptr %hp17, i64 24
  store ptr %ld21, ptr %fp22, align 8
  store ptr %hp17, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r23 = load ptr, ptr %res_slot5
  ret ptr %case_r23
}

define ptr @inc_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld24 = load ptr, ptr %t.addr
  %res_slot25 = alloca ptr
  %tgp26 = getelementptr i8, ptr %ld24, i64 8
  %tag27 = load i32, ptr %tgp26, align 4
  switch i32 %tag27, label %case_default5 [
      i32 0, label %case_br6
      i32 1, label %case_br7
  ]
case_br6:
  %fp28 = getelementptr i8, ptr %ld24, i64 16
  %fv29 = load i64, ptr %fp28, align 8
  %n.addr = alloca i64
  store i64 %fv29, ptr %n.addr
  %ld30 = load i64, ptr %n.addr
  %ar31 = add i64 %ld30, 1
  %$t356.addr = alloca i64
  store i64 %ar31, ptr %$t356.addr
  %ld32 = load ptr, ptr %t.addr
  %tgp33 = getelementptr i8, ptr %ld32, i64 8
  store i32 0, ptr %tgp33, align 4
  %ld34 = load i64, ptr %$t356.addr
  %fp35 = getelementptr i8, ptr %ld32, i64 16
  store i64 %ld34, ptr %fp35, align 8
  store ptr %ld32, ptr %res_slot25
  br label %case_merge4
case_br7:
  %fp36 = getelementptr i8, ptr %ld24, i64 16
  %fv37 = load ptr, ptr %fp36, align 8
  %l.addr = alloca ptr
  store ptr %fv37, ptr %l.addr
  %fp38 = getelementptr i8, ptr %ld24, i64 24
  %fv39 = load ptr, ptr %fp38, align 8
  %r.addr = alloca ptr
  store ptr %fv39, ptr %r.addr
  %ld40 = load ptr, ptr %l.addr
  %cr41 = call ptr @inc_leaves(ptr %ld40)
  %$t357.addr = alloca ptr
  store ptr %cr41, ptr %$t357.addr
  %ld42 = load ptr, ptr %r.addr
  %cr43 = call ptr @inc_leaves(ptr %ld42)
  %$t358.addr = alloca ptr
  store ptr %cr43, ptr %$t358.addr
  %ld44 = load ptr, ptr %t.addr
  %tgp45 = getelementptr i8, ptr %ld44, i64 8
  store i32 1, ptr %tgp45, align 4
  %ld46 = load ptr, ptr %$t357.addr
  %fp47 = getelementptr i8, ptr %ld44, i64 16
  store ptr %ld46, ptr %fp47, align 8
  %ld48 = load ptr, ptr %$t358.addr
  %fp49 = getelementptr i8, ptr %ld44, i64 24
  store ptr %ld48, ptr %fp49, align 8
  store ptr %ld44, ptr %res_slot25
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r50 = load ptr, ptr %res_slot25
  ret ptr %case_r50
}

define i64 @sum_leaves(ptr %t.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %ld51 = load ptr, ptr %t.addr
  %res_slot52 = alloca ptr
  %tgp53 = getelementptr i8, ptr %ld51, i64 8
  %tag54 = load i32, ptr %tgp53, align 4
  switch i32 %tag54, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %fp55 = getelementptr i8, ptr %ld51, i64 16
  %fv56 = load i64, ptr %fp55, align 8
  %n.addr = alloca i64
  store i64 %fv56, ptr %n.addr
  %ld57 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld57)
  %ld58 = load i64, ptr %n.addr
  %cv59 = inttoptr i64 %ld58 to ptr
  store ptr %cv59, ptr %res_slot52
  br label %case_merge8
case_br11:
  %fp60 = getelementptr i8, ptr %ld51, i64 16
  %fv61 = load ptr, ptr %fp60, align 8
  %l.addr = alloca ptr
  store ptr %fv61, ptr %l.addr
  %fp62 = getelementptr i8, ptr %ld51, i64 24
  %fv63 = load ptr, ptr %fp62, align 8
  %r.addr = alloca ptr
  store ptr %fv63, ptr %r.addr
  %ld64 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld64)
  %ld65 = load ptr, ptr %l.addr
  %cr66 = call i64 @sum_leaves(ptr %ld65)
  %$t359.addr = alloca i64
  store i64 %cr66, ptr %$t359.addr
  %ld67 = load ptr, ptr %r.addr
  %cr68 = call i64 @sum_leaves(ptr %ld67)
  %$t360.addr = alloca i64
  store i64 %cr68, ptr %$t360.addr
  %ld69 = load i64, ptr %$t359.addr
  %ld70 = load i64, ptr %$t360.addr
  %ar71 = add i64 %ld69, %ld70
  %cv72 = inttoptr i64 %ar71 to ptr
  store ptr %cv72, ptr %res_slot52
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r73 = load ptr, ptr %res_slot52
  %cv74 = ptrtoint ptr %case_r73 to i64
  ret i64 %cv74
}

define ptr @repeat(ptr %t.arg, i64 %n.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld75 = load i64, ptr %n.addr
  %cmp76 = icmp eq i64 %ld75, 0
  %ar77 = zext i1 %cmp76 to i64
  %$t361.addr = alloca i64
  store i64 %ar77, ptr %$t361.addr
  %ld78 = load i64, ptr %$t361.addr
  %res_slot79 = alloca ptr
  switch i64 %ld78, label %case_default13 [
      i64 1, label %case_br14
  ]
case_br14:
  %ld80 = load ptr, ptr %t.addr
  store ptr %ld80, ptr %res_slot79
  br label %case_merge12
case_default13:
  %ld81 = load ptr, ptr %t.addr
  %cr82 = call ptr @inc_leaves(ptr %ld81)
  %$t362.addr = alloca ptr
  store ptr %cr82, ptr %$t362.addr
  %ld83 = load i64, ptr %n.addr
  %ar84 = sub i64 %ld83, 1
  %$t363.addr = alloca i64
  store i64 %ar84, ptr %$t363.addr
  %ld85 = load ptr, ptr %$t362.addr
  %ld86 = load i64, ptr %$t363.addr
  %cr87 = call ptr @repeat(ptr %ld85, i64 %ld86)
  store ptr %cr87, ptr %res_slot79
  br label %case_merge12
case_merge12:
  %case_r88 = load ptr, ptr %res_slot79
  ret ptr %case_r88
}

define void @march_main() {
entry:
  %depth.addr = alloca i64
  store i64 20, ptr %depth.addr
  %passes.addr = alloca i64
  store i64 100, ptr %passes.addr
  %ld89 = load i64, ptr %depth.addr
  %cr90 = call ptr @make(i64 %ld89)
  %t.addr = alloca ptr
  store ptr %cr90, ptr %t.addr
  %ld91 = load ptr, ptr %t.addr
  %ld92 = load i64, ptr %passes.addr
  %cr93 = call ptr @repeat(ptr %ld91, i64 %ld92)
  %t2.addr = alloca ptr
  store ptr %cr93, ptr %t2.addr
  %ld94 = load ptr, ptr %t2.addr
  %cr95 = call i64 @sum_leaves(ptr %ld94)
  %$t364.addr = alloca i64
  store i64 %cr95, ptr %$t364.addr
  %ld96 = load i64, ptr %$t364.addr
  %cr97 = call ptr @march_int_to_string(i64 %ld96)
  %$t365.addr = alloca ptr
  store ptr %cr97, ptr %$t365.addr
  %ld98 = load ptr, ptr %$t365.addr
  call void @march_println(ptr %ld98)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
