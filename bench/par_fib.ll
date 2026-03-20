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


define i64 @fib(i64 %n.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp slt i64 %ld1, 2
  %ar3 = zext i1 %cmp2 to i64
  %$t351.addr = alloca i64
  store i64 %ar3, ptr %$t351.addr
  %ld4 = load i64, ptr %$t351.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld6 = load i64, ptr %n.addr
  %cv7 = inttoptr i64 %ld6 to ptr
  store ptr %cv7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %n.addr
  %ar9 = sub i64 %ld8, 1
  %$t352.addr = alloca i64
  store i64 %ar9, ptr %$t352.addr
  %ld10 = load i64, ptr %$t352.addr
  %cr11 = call i64 @fib(i64 %ld10)
  %$t353.addr = alloca i64
  store i64 %cr11, ptr %$t353.addr
  %ld12 = load i64, ptr %n.addr
  %ar13 = sub i64 %ld12, 2
  %$t354.addr = alloca i64
  store i64 %ar13, ptr %$t354.addr
  %ld14 = load i64, ptr %$t354.addr
  %cr15 = call i64 @fib(i64 %ld14)
  %$t355.addr = alloca i64
  store i64 %cr15, ptr %$t355.addr
  %ld16 = load i64, ptr %$t353.addr
  %ld17 = load i64, ptr %$t355.addr
  %ar18 = add i64 %ld16, %ld17
  %cv19 = inttoptr i64 %ar18 to ptr
  store ptr %cv19, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r20 = load ptr, ptr %res_slot5
  %cv21 = ptrtoint ptr %case_r20 to i64
  ret i64 %cv21
}

define i64 @par_fib(i64 %n.arg, i64 %threshold.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld22 = load i64, ptr %n.addr
  %cmp23 = icmp slt i64 %ld22, 2
  %ar24 = zext i1 %cmp23 to i64
  %$t356.addr = alloca i64
  store i64 %ar24, ptr %$t356.addr
  %ld25 = load i64, ptr %$t356.addr
  %res_slot26 = alloca ptr
  switch i64 %ld25, label %case_default5 [
      i64 1, label %case_br6
  ]
case_br6:
  %ld27 = load i64, ptr %n.addr
  %cv28 = inttoptr i64 %ld27 to ptr
  store ptr %cv28, ptr %res_slot26
  br label %case_merge4
case_default5:
  %ld29 = load i64, ptr %n.addr
  %ld30 = load i64, ptr %threshold.addr
  %cmp31 = icmp sle i64 %ld29, %ld30
  %ar32 = zext i1 %cmp31 to i64
  %$t357.addr = alloca i64
  store i64 %ar32, ptr %$t357.addr
  %ld33 = load i64, ptr %$t357.addr
  %res_slot34 = alloca ptr
  switch i64 %ld33, label %case_default8 [
      i64 1, label %case_br9
  ]
case_br9:
  %ld35 = load i64, ptr %n.addr
  %cr36 = call i64 @fib(i64 %ld35)
  %cv37 = inttoptr i64 %cr36 to ptr
  store ptr %cv37, ptr %res_slot34
  br label %case_merge7
case_default8:
  %hp38 = call ptr @march_alloc(i64 40)
  %tgp39 = getelementptr i8, ptr %hp38, i64 8
  store i32 0, ptr %tgp39, align 4
  %fp40 = getelementptr i8, ptr %hp38, i64 16
  store ptr @$lam358$apply, ptr %fp40, align 8
  %ld41 = load i64, ptr %n.addr
  %fp42 = getelementptr i8, ptr %hp38, i64 24
  store i64 %ld41, ptr %fp42, align 8
  %ld43 = load i64, ptr %threshold.addr
  %fp44 = getelementptr i8, ptr %hp38, i64 32
  store i64 %ld43, ptr %fp44, align 8
  %$t360.addr = alloca ptr
  store ptr %hp38, ptr %$t360.addr
  %ld45 = load ptr, ptr %$t360.addr
  %fp46 = getelementptr i8, ptr %ld45, i64 16
  %fv47 = load ptr, ptr %fp46, align 8
  %tsres48 = call i64 %fv47(ptr %ld45, i64 0)
  %hp49 = call ptr @march_alloc(i64 24)
  %tgp50 = getelementptr i8, ptr %hp49, i64 8
  store i32 0, ptr %tgp50, align 4
  %fp51 = getelementptr i8, ptr %hp49, i64 16
  store i64 %tsres48, ptr %fp51, align 8
  %t1.addr = alloca ptr
  store ptr %hp49, ptr %t1.addr
  %hp52 = call ptr @march_alloc(i64 40)
  %tgp53 = getelementptr i8, ptr %hp52, i64 8
  store i32 0, ptr %tgp53, align 4
  %fp54 = getelementptr i8, ptr %hp52, i64 16
  store ptr @$lam361$apply, ptr %fp54, align 8
  %ld55 = load i64, ptr %n.addr
  %fp56 = getelementptr i8, ptr %hp52, i64 24
  store i64 %ld55, ptr %fp56, align 8
  %ld57 = load i64, ptr %threshold.addr
  %fp58 = getelementptr i8, ptr %hp52, i64 32
  store i64 %ld57, ptr %fp58, align 8
  %$t363.addr = alloca ptr
  store ptr %hp52, ptr %$t363.addr
  %ld59 = load ptr, ptr %$t363.addr
  %fp60 = getelementptr i8, ptr %ld59, i64 16
  %fv61 = load ptr, ptr %fp60, align 8
  %tsres62 = call i64 %fv61(ptr %ld59, i64 0)
  %hp63 = call ptr @march_alloc(i64 24)
  %tgp64 = getelementptr i8, ptr %hp63, i64 8
  store i32 0, ptr %tgp64, align 4
  %fp65 = getelementptr i8, ptr %hp63, i64 16
  store i64 %tsres62, ptr %fp65, align 8
  %t2.addr = alloca ptr
  store ptr %hp63, ptr %t2.addr
  %ld66 = load ptr, ptr %t1.addr
  %fp67 = getelementptr i8, ptr %ld66, i64 16
  %fv68 = load i64, ptr %fp67, align 8
  %r1.addr = alloca i64
  store i64 %fv68, ptr %r1.addr
  %ld69 = load ptr, ptr %t2.addr
  %fp70 = getelementptr i8, ptr %ld69, i64 16
  %fv71 = load i64, ptr %fp70, align 8
  %r2.addr = alloca i64
  store i64 %fv71, ptr %r2.addr
  %ld72 = load i64, ptr %r1.addr
  %ld73 = load i64, ptr %r2.addr
  %ar74 = add i64 %ld72, %ld73
  %cv75 = inttoptr i64 %ar74 to ptr
  store ptr %cv75, ptr %res_slot34
  br label %case_merge7
case_merge7:
  %case_r76 = load ptr, ptr %res_slot34
  store ptr %case_r76, ptr %res_slot26
  br label %case_merge4
case_merge4:
  %case_r77 = load ptr, ptr %res_slot26
  %cv78 = ptrtoint ptr %case_r77 to i64
  ret i64 %cv78
}

define void @march_main() {
entry:
  %cr79 = call i64 @par_fib(i64 40, i64 20)
  %result.addr = alloca i64
  store i64 %cr79, ptr %result.addr
  %ld80 = load i64, ptr %result.addr
  %cr81 = call ptr @march_int_to_string(i64 %ld80)
  %$t364.addr = alloca ptr
  store ptr %cr81, ptr %$t364.addr
  %ld82 = load ptr, ptr %$t364.addr
  call void @march_println(ptr %ld82)
  ret void
}

define i64 @$lam358$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld83 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld83)
  %ld84 = load ptr, ptr %$clo.addr
  %fp85 = getelementptr i8, ptr %ld84, i64 24
  %fv86 = load ptr, ptr %fp85, align 8
  %cv87 = ptrtoint ptr %fv86 to i64
  %n.addr = alloca i64
  store i64 %cv87, ptr %n.addr
  %ld88 = load ptr, ptr %$clo.addr
  %fp89 = getelementptr i8, ptr %ld88, i64 32
  %fv90 = load i64, ptr %fp89, align 8
  %threshold.addr = alloca i64
  store i64 %fv90, ptr %threshold.addr
  %ld91 = load i64, ptr %n.addr
  %ar92 = sub i64 %ld91, 1
  %$t359.addr = alloca i64
  store i64 %ar92, ptr %$t359.addr
  %ld93 = load i64, ptr %$t359.addr
  %ld94 = load i64, ptr %threshold.addr
  %cr95 = call i64 @par_fib(i64 %ld93, i64 %ld94)
  ret i64 %cr95
}

define i64 @$lam361$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld96 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld96)
  %ld97 = load ptr, ptr %$clo.addr
  %fp98 = getelementptr i8, ptr %ld97, i64 24
  %fv99 = load ptr, ptr %fp98, align 8
  %cv100 = ptrtoint ptr %fv99 to i64
  %n.addr = alloca i64
  store i64 %cv100, ptr %n.addr
  %ld101 = load ptr, ptr %$clo.addr
  %fp102 = getelementptr i8, ptr %ld101, i64 32
  %fv103 = load i64, ptr %fp102, align 8
  %threshold.addr = alloca i64
  store i64 %fv103, ptr %threshold.addr
  %ld104 = load i64, ptr %n.addr
  %ar105 = sub i64 %ld104, 2
  %$t362.addr = alloca i64
  store i64 %ar105, ptr %$t362.addr
  %ld106 = load i64, ptr %$t362.addr
  %ld107 = load i64, ptr %threshold.addr
  %cr108 = call i64 @par_fib(i64 %ld106, i64 %ld107)
  ret i64 %cr108
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
