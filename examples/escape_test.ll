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


define i64 @sum_pair(i64 %x.arg, i64 %y.arg) {
entry:
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %y.addr = alloca i64
  store i64 %y.arg, ptr %y.addr
  %sp1 = alloca [32 x i8], align 8
  store i64 0, ptr %sp1, align 8
  %tgp2 = getelementptr i8, ptr %sp1, i64 8
  store i32 0, ptr %tgp2, align 4
  %ld3 = load i64, ptr %x.addr
  %fp4 = getelementptr i8, ptr %sp1, i64 16
  store i64 %ld3, ptr %fp4, align 8
  %ld5 = load i64, ptr %y.addr
  %fp6 = getelementptr i8, ptr %sp1, i64 24
  store i64 %ld5, ptr %fp6, align 8
  %p.addr = alloca ptr
  store ptr %sp1, ptr %p.addr
  %ld7 = load ptr, ptr %p.addr
  %res_slot8 = alloca ptr
  %tgp9 = getelementptr i8, ptr %ld7, i64 8
  %tag10 = load i32, ptr %tgp9, align 4
  switch i32 %tag10, label %case_default2 [
      i32 0, label %case_br3
  ]
case_br3:
  %fp11 = getelementptr i8, ptr %ld7, i64 16
  %fv12 = load i64, ptr %fp11, align 8
  %a.addr = alloca i64
  store i64 %fv12, ptr %a.addr
  %fp13 = getelementptr i8, ptr %ld7, i64 24
  %fv14 = load i64, ptr %fp13, align 8
  %b.addr = alloca i64
  store i64 %fv14, ptr %b.addr
  %ld15 = load i64, ptr %a.addr
  %ld16 = load i64, ptr %b.addr
  %ar17 = add i64 %ld15, %ld16
  %cv18 = inttoptr i64 %ar17 to ptr
  store ptr %cv18, ptr %res_slot8
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r19 = load ptr, ptr %res_slot8
  %cv20 = ptrtoint ptr %case_r19 to i64
  ret i64 %cv20
}

define ptr @make_pair(i64 %x.arg, i64 %y.arg) {
entry:
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %y.addr = alloca i64
  store i64 %y.arg, ptr %y.addr
  %hp21 = call ptr @march_alloc(i64 32)
  %tgp22 = getelementptr i8, ptr %hp21, i64 8
  store i32 0, ptr %tgp22, align 4
  %ld23 = load i64, ptr %x.addr
  %fp24 = getelementptr i8, ptr %hp21, i64 16
  store i64 %ld23, ptr %fp24, align 8
  %ld25 = load i64, ptr %y.addr
  %fp26 = getelementptr i8, ptr %hp21, i64 24
  store i64 %ld25, ptr %fp26, align 8
  ret ptr %hp21
}

define ptr @nest(i64 %x.arg) {
entry:
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %hp27 = call ptr @march_alloc(i64 24)
  %tgp28 = getelementptr i8, ptr %hp27, i64 8
  store i32 0, ptr %tgp28, align 4
  %ld29 = load i64, ptr %x.addr
  %fp30 = getelementptr i8, ptr %hp27, i64 16
  store i64 %ld29, ptr %fp30, align 8
  %b.addr = alloca ptr
  store ptr %hp27, ptr %b.addr
  %hp31 = call ptr @march_alloc(i64 24)
  %tgp32 = getelementptr i8, ptr %hp31, i64 8
  store i32 0, ptr %tgp32, align 4
  %ld33 = load ptr, ptr %b.addr
  %fp34 = getelementptr i8, ptr %hp31, i64 16
  store ptr %ld33, ptr %fp34, align 8
  ret ptr %hp31
}

define i64 @discard(i64 %x.arg) {
entry:
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %sp35 = alloca [24 x i8], align 8
  store i64 0, ptr %sp35, align 8
  %tgp36 = getelementptr i8, ptr %sp35, i64 8
  store i32 0, ptr %tgp36, align 4
  %ld37 = load i64, ptr %x.addr
  %fp38 = getelementptr i8, ptr %sp35, i64 16
  store i64 %ld37, ptr %fp38, align 8
  %b.addr = alloca ptr
  store ptr %sp35, ptr %b.addr
  ret i64 42
}

define void @march_main() {
entry:
  %cr39 = call i64 @sum_pair(i64 3, i64 4)
  %s.addr = alloca i64
  store i64 %cr39, ptr %s.addr
  %ld40 = load i64, ptr %s.addr
  %cr41 = call ptr @march_int_to_string(i64 %ld40)
  %$t1.addr = alloca ptr
  store ptr %cr41, ptr %$t1.addr
  %ld42 = load ptr, ptr %$t1.addr
  call void @march_println(ptr %ld42)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
