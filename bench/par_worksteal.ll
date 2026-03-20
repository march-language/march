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

define i64 @par_fib(ptr %pool.arg, i64 %n.arg, i64 %threshold.arg) {
entry:
  %pool.addr = alloca ptr
  store ptr %pool.arg, ptr %pool.addr
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
  %ld38 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld38)
  %hp39 = call ptr @march_alloc(i64 48)
  %tgp40 = getelementptr i8, ptr %hp39, i64 8
  store i32 0, ptr %tgp40, align 4
  %fp41 = getelementptr i8, ptr %hp39, i64 16
  store ptr @$lam358$apply, ptr %fp41, align 8
  %ld42 = load i64, ptr %n.addr
  %fp43 = getelementptr i8, ptr %hp39, i64 24
  store i64 %ld42, ptr %fp43, align 8
  %ld44 = load ptr, ptr %pool.addr
  %fp45 = getelementptr i8, ptr %hp39, i64 32
  store ptr %ld44, ptr %fp45, align 8
  %ld46 = load i64, ptr %threshold.addr
  %fp47 = getelementptr i8, ptr %hp39, i64 40
  store i64 %ld46, ptr %fp47, align 8
  %$t360.addr = alloca ptr
  store ptr %hp39, ptr %$t360.addr
  %ld48 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld48)
  %ld49 = load ptr, ptr %$t360.addr
  %fp50 = getelementptr i8, ptr %ld49, i64 16
  %fv51 = load ptr, ptr %fp50, align 8
  %tsres52 = call i64 %fv51(ptr %ld49, i64 0)
  %hp53 = call ptr @march_alloc(i64 24)
  %tgp54 = getelementptr i8, ptr %hp53, i64 8
  store i32 0, ptr %tgp54, align 4
  %fp55 = getelementptr i8, ptr %hp53, i64 16
  store i64 %tsres52, ptr %fp55, align 8
  %t1.addr = alloca ptr
  store ptr %hp53, ptr %t1.addr
  %ld56 = load ptr, ptr %pool.addr
  call void @march_incrc(ptr %ld56)
  %hp57 = call ptr @march_alloc(i64 48)
  %tgp58 = getelementptr i8, ptr %hp57, i64 8
  store i32 0, ptr %tgp58, align 4
  %fp59 = getelementptr i8, ptr %hp57, i64 16
  store ptr @$lam361$apply, ptr %fp59, align 8
  %ld60 = load i64, ptr %n.addr
  %fp61 = getelementptr i8, ptr %hp57, i64 24
  store i64 %ld60, ptr %fp61, align 8
  %ld62 = load ptr, ptr %pool.addr
  %fp63 = getelementptr i8, ptr %hp57, i64 32
  store ptr %ld62, ptr %fp63, align 8
  %ld64 = load i64, ptr %threshold.addr
  %fp65 = getelementptr i8, ptr %hp57, i64 40
  store i64 %ld64, ptr %fp65, align 8
  %$t363.addr = alloca ptr
  store ptr %hp57, ptr %$t363.addr
  %ld66 = load ptr, ptr %$t363.addr
  %fp67 = getelementptr i8, ptr %ld66, i64 16
  %fv68 = load ptr, ptr %fp67, align 8
  %tsres69 = call i64 %fv68(ptr %ld66, i64 0)
  %hp70 = call ptr @march_alloc(i64 24)
  %tgp71 = getelementptr i8, ptr %hp70, i64 8
  store i32 0, ptr %tgp71, align 4
  %fp72 = getelementptr i8, ptr %hp70, i64 16
  store i64 %tsres69, ptr %fp72, align 8
  %t2.addr = alloca ptr
  store ptr %hp70, ptr %t2.addr
  %ld73 = load ptr, ptr %t1.addr
  %fp74 = getelementptr i8, ptr %ld73, i64 16
  %fv75 = load i64, ptr %fp74, align 8
  %r1.addr = alloca i64
  store i64 %fv75, ptr %r1.addr
  %ld76 = load ptr, ptr %t2.addr
  %fp77 = getelementptr i8, ptr %ld76, i64 16
  %fv78 = load i64, ptr %fp77, align 8
  %r2.addr = alloca i64
  store i64 %fv78, ptr %r2.addr
  %ld79 = load i64, ptr %r1.addr
  %ld80 = load i64, ptr %r2.addr
  %ar81 = add i64 %ld79, %ld80
  %cv82 = inttoptr i64 %ar81 to ptr
  store ptr %cv82, ptr %res_slot34
  br label %case_merge7
case_merge7:
  %case_r83 = load ptr, ptr %res_slot34
  store ptr %case_r83, ptr %res_slot26
  br label %case_merge4
case_merge4:
  %case_r84 = load ptr, ptr %res_slot26
  %cv85 = ptrtoint ptr %case_r84 to i64
  ret i64 %cv85
}

define void @march_main() {
entry:
  %pool.addr = alloca ptr
  store ptr null, ptr %pool.addr
  %ld86 = load ptr, ptr %pool.addr
  %cr87 = call i64 @par_fib(ptr %ld86, i64 40, i64 20)
  %result.addr = alloca i64
  store i64 %cr87, ptr %result.addr
  %ld88 = load i64, ptr %result.addr
  %cr89 = call ptr @march_int_to_string(i64 %ld88)
  %$t364.addr = alloca ptr
  store ptr %cr89, ptr %$t364.addr
  %ld90 = load ptr, ptr %$t364.addr
  call void @march_println(ptr %ld90)
  ret void
}

define i64 @$lam358$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld91 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld91)
  %ld92 = load ptr, ptr %$clo.addr
  %fp93 = getelementptr i8, ptr %ld92, i64 24
  %fv94 = load ptr, ptr %fp93, align 8
  %cv95 = ptrtoint ptr %fv94 to i64
  %n.addr = alloca i64
  store i64 %cv95, ptr %n.addr
  %ld96 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld96)
  %ld97 = load ptr, ptr %$clo.addr
  %fp98 = getelementptr i8, ptr %ld97, i64 32
  %fv99 = load ptr, ptr %fp98, align 8
  %pool.addr = alloca ptr
  store ptr %fv99, ptr %pool.addr
  %ld100 = load ptr, ptr %$clo.addr
  %fp101 = getelementptr i8, ptr %ld100, i64 40
  %fv102 = load i64, ptr %fp101, align 8
  %threshold.addr = alloca i64
  store i64 %fv102, ptr %threshold.addr
  %ld103 = load i64, ptr %n.addr
  %ar104 = sub i64 %ld103, 1
  %$t359.addr = alloca i64
  store i64 %ar104, ptr %$t359.addr
  %ld105 = load ptr, ptr %pool.addr
  %ld106 = load i64, ptr %$t359.addr
  %ld107 = load i64, ptr %threshold.addr
  %cr108 = call i64 @par_fib(ptr %ld105, i64 %ld106, i64 %ld107)
  ret i64 %cr108
}

define i64 @$lam361$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld109 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld109)
  %ld110 = load ptr, ptr %$clo.addr
  %fp111 = getelementptr i8, ptr %ld110, i64 24
  %fv112 = load ptr, ptr %fp111, align 8
  %cv113 = ptrtoint ptr %fv112 to i64
  %n.addr = alloca i64
  store i64 %cv113, ptr %n.addr
  %ld114 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld114)
  %ld115 = load ptr, ptr %$clo.addr
  %fp116 = getelementptr i8, ptr %ld115, i64 32
  %fv117 = load ptr, ptr %fp116, align 8
  %pool.addr = alloca ptr
  store ptr %fv117, ptr %pool.addr
  %ld118 = load ptr, ptr %$clo.addr
  %fp119 = getelementptr i8, ptr %ld118, i64 40
  %fv120 = load i64, ptr %fp119, align 8
  %threshold.addr = alloca i64
  store i64 %fv120, ptr %threshold.addr
  %ld121 = load i64, ptr %n.addr
  %ar122 = sub i64 %ld121, 2
  %$t362.addr = alloca i64
  store i64 %ar122, ptr %$t362.addr
  %ld123 = load ptr, ptr %pool.addr
  %ld124 = load i64, ptr %$t362.addr
  %ld125 = load i64, ptr %threshold.addr
  %cr126 = call i64 @par_fib(ptr %ld123, i64 %ld124, i64 %ld125)
  ret i64 %cr126
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
