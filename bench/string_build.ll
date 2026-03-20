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

@.str1 = private unnamed_addr constant [1 x i8] c"\00"

define ptr @build(i64 %n.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %n.addr
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
  %ld6 = load ptr, ptr %acc.addr
  store ptr %ld6, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld7 = load i64, ptr %n.addr
  %ar8 = sub i64 %ld7, 1
  %$t352.addr = alloca i64
  store i64 %ar8, ptr %$t352.addr
  %ld9 = load i64, ptr %n.addr
  %cr10 = call ptr @march_int_to_string(i64 %ld9)
  %$t353.addr = alloca ptr
  store ptr %cr10, ptr %$t353.addr
  %hp11 = call ptr @march_alloc(i64 32)
  %tgp12 = getelementptr i8, ptr %hp11, i64 8
  store i32 1, ptr %tgp12, align 4
  %ld13 = load ptr, ptr %$t353.addr
  %fp14 = getelementptr i8, ptr %hp11, i64 16
  store ptr %ld13, ptr %fp14, align 8
  %ld15 = load ptr, ptr %acc.addr
  %fp16 = getelementptr i8, ptr %hp11, i64 24
  store ptr %ld15, ptr %fp16, align 8
  %$t354.addr = alloca ptr
  store ptr %hp11, ptr %$t354.addr
  %ld17 = load i64, ptr %$t352.addr
  %ld18 = load ptr, ptr %$t354.addr
  %cr19 = call ptr @build(i64 %ld17, ptr %ld18)
  store ptr %cr19, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r20 = load ptr, ptr %res_slot5
  ret ptr %case_r20
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 500000, ptr %n.addr
  %hp21 = call ptr @march_alloc(i64 16)
  %tgp22 = getelementptr i8, ptr %hp21, i64 8
  store i32 0, ptr %tgp22, align 4
  %$t355.addr = alloca ptr
  store ptr %hp21, ptr %$t355.addr
  %ld23 = load i64, ptr %n.addr
  %ld24 = load ptr, ptr %$t355.addr
  %cr25 = call ptr @build(i64 %ld23, ptr %ld24)
  %$t356.addr = alloca ptr
  store ptr %cr25, ptr %$t356.addr
  %ld26 = load ptr, ptr %$t356.addr
  %sl27 = call ptr @march_string_lit(ptr @.str1, i64 0)
  %cr28 = call ptr @march_string_join(ptr %ld26, ptr %sl27)
  %s.addr = alloca ptr
  store ptr %cr28, ptr %s.addr
  %ld29 = load ptr, ptr %s.addr
  %cr30 = call i64 @march_string_byte_length(ptr %ld29)
  %$t357.addr = alloca i64
  store i64 %cr30, ptr %$t357.addr
  %ld31 = load i64, ptr %$t357.addr
  %cr32 = call ptr @march_int_to_string(i64 %ld31)
  %$t358.addr = alloca ptr
  store ptr %cr32, ptr %$t358.addr
  %ld33 = load ptr, ptr %$t358.addr
  call void @march_println(ptr %ld33)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
