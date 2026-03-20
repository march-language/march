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
  %$t492.addr = alloca i64
  store i64 %ar3, ptr %$t492.addr
  %ld4 = load i64, ptr %$t492.addr
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
  %$t493.addr = alloca i64
  store i64 %ar9, ptr %$t493.addr
  %ld10 = load i64, ptr %$t493.addr
  %cr11 = call i64 @fib(i64 %ld10)
  %$t494.addr = alloca i64
  store i64 %cr11, ptr %$t494.addr
  %ld12 = load i64, ptr %n.addr
  %ar13 = sub i64 %ld12, 2
  %$t495.addr = alloca i64
  store i64 %ar13, ptr %$t495.addr
  %ld14 = load i64, ptr %$t495.addr
  %cr15 = call i64 @fib(i64 %ld14)
  %$t496.addr = alloca i64
  store i64 %cr15, ptr %$t496.addr
  %ld16 = load i64, ptr %$t494.addr
  %ld17 = load i64, ptr %$t496.addr
  %ar18 = add i64 %ld16, %ld17
  %cv19 = inttoptr i64 %ar18 to ptr
  store ptr %cv19, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r20 = load ptr, ptr %res_slot5
  %cv21 = ptrtoint ptr %case_r20 to i64
  ret i64 %cv21
}

define void @march_main() {
entry:
  %cr22 = call i64 @fib(i64 40)
  %$t497.addr = alloca i64
  store i64 %cr22, ptr %$t497.addr
  %ld23 = load i64, ptr %$t497.addr
  %cr24 = call ptr @march_int_to_string(i64 %ld23)
  %$t498.addr = alloca ptr
  store ptr %cr24, ptr %$t498.addr
  %ld25 = load ptr, ptr %$t498.addr
  call void @march_println(ptr %ld25)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
