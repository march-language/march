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
declare void @march_kill(ptr %actor)
declare i64  @march_is_alive(ptr %actor)
declare ptr  @march_send(ptr %actor, ptr %msg)


define void @march_main() {
entry:
  %x_i1.addr = alloca i64
  store i64 3, ptr %x_i1.addr
  %y_i2.addr = alloca i64
  store i64 4, ptr %y_i2.addr
  %sp1 = alloca [32 x i8], align 8
  store i64 0, ptr %sp1, align 8
  %tgp2 = getelementptr i8, ptr %sp1, i64 8
  store i32 0, ptr %tgp2, align 4
  %ld3 = load i64, ptr %x_i1.addr
  %fp4 = getelementptr i8, ptr %sp1, i64 16
  store i64 %ld3, ptr %fp4, align 8
  %ld5 = load i64, ptr %y_i2.addr
  %fp6 = getelementptr i8, ptr %sp1, i64 24
  store i64 %ld5, ptr %fp6, align 8
  %p_i3.addr = alloca ptr
  store ptr %sp1, ptr %p_i3.addr
  %ld7 = load ptr, ptr %p_i3.addr
  %res_slot8 = alloca ptr
  %tgp9 = getelementptr i8, ptr %ld7, i64 8
  %tag10 = load i32, ptr %tgp9, align 4
  switch i32 %tag10, label %case_default2 [
      i32 0, label %case_br3
  ]
case_br3:
  %fp11 = getelementptr i8, ptr %ld7, i64 16
  %fv12 = load i64, ptr %fp11, align 8
  %a_i4.addr = alloca i64
  store i64 %fv12, ptr %a_i4.addr
  %fp13 = getelementptr i8, ptr %ld7, i64 24
  %fv14 = load i64, ptr %fp13, align 8
  %b_i5.addr = alloca i64
  store i64 %fv14, ptr %b_i5.addr
  %ld15 = load i64, ptr %a_i4.addr
  %ld16 = load i64, ptr %b_i5.addr
  %ar17 = add i64 %ld15, %ld16
  %cv18 = inttoptr i64 %ar17 to ptr
  store ptr %cv18, ptr %res_slot8
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r19 = load ptr, ptr %res_slot8
  %cv20 = ptrtoint ptr %case_r19 to i64
  %s.addr = alloca i64
  store i64 %cv20, ptr %s.addr
  %ld21 = load i64, ptr %s.addr
  %cr22 = call ptr @march_int_to_string(i64 %ld21)
  %$t17.addr = alloca ptr
  store ptr %cr22, ptr %$t17.addr
  %ld23 = load ptr, ptr %$t17.addr
  call void @march_println(ptr %ld23)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
