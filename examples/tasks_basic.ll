; March compiler output
target triple = "arm64-apple-macosx15.0.0"

; Runtime declarations
declare ptr  @march_alloc(i64 %sz)
declare void @march_incrc(ptr %p)
declare void @march_decrc(ptr %p)
declare i64  @march_decrc_freed(ptr %p)
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

@.str1 = private unnamed_addr constant [20 x i8] c"--- Task basics ---\00"
@.str2 = private unnamed_addr constant [30 x i8] c"collatz(27) + collatz(871) = \00"
@.str3 = private unnamed_addr constant [26 x i8] c"chained: (10 + 20) * 3 = \00"
@.str4 = private unnamed_addr constant [26 x i8] c"sum of collatz(1..100) = \00"

define i64 @collatz(i64 %n.arg, i64 %steps.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %steps.addr = alloca i64
  store i64 %steps.arg, ptr %steps.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp eq i64 %ld1, 1
  %ar3 = zext i1 %cmp2 to i64
  %$t492.addr = alloca i64
  store i64 %ar3, ptr %$t492.addr
  %ld4 = load i64, ptr %$t492.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld6 = load i64, ptr %steps.addr
  %cv7 = inttoptr i64 %ld6 to ptr
  store ptr %cv7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %n.addr
  %ar9 = srem i64 %ld8, 2
  %$t493.addr = alloca i64
  store i64 %ar9, ptr %$t493.addr
  %ld10 = load i64, ptr %$t493.addr
  %cmp11 = icmp eq i64 %ld10, 0
  %ar12 = zext i1 %cmp11 to i64
  %$t494.addr = alloca i64
  store i64 %ar12, ptr %$t494.addr
  %ld13 = load i64, ptr %$t494.addr
  %res_slot14 = alloca ptr
  switch i64 %ld13, label %case_default5 [
      i64 1, label %case_br6
  ]
case_br6:
  %ld15 = load i64, ptr %n.addr
  %ar16 = sdiv i64 %ld15, 2
  %$t495.addr = alloca i64
  store i64 %ar16, ptr %$t495.addr
  %ld17 = load i64, ptr %steps.addr
  %ar18 = add i64 %ld17, 1
  %$t496.addr = alloca i64
  store i64 %ar18, ptr %$t496.addr
  %ld19 = load i64, ptr %$t495.addr
  %ld20 = load i64, ptr %$t496.addr
  %cr21 = call i64 @collatz(i64 %ld19, i64 %ld20)
  %cv22 = inttoptr i64 %cr21 to ptr
  store ptr %cv22, ptr %res_slot14
  br label %case_merge4
case_default5:
  %ld23 = load i64, ptr %n.addr
  %ar24 = mul i64 3, %ld23
  %$t497.addr = alloca i64
  store i64 %ar24, ptr %$t497.addr
  %ld25 = load i64, ptr %$t497.addr
  %ar26 = add i64 %ld25, 1
  %$t498.addr = alloca i64
  store i64 %ar26, ptr %$t498.addr
  %ld27 = load i64, ptr %steps.addr
  %ar28 = add i64 %ld27, 1
  %$t499.addr = alloca i64
  store i64 %ar28, ptr %$t499.addr
  %ld29 = load i64, ptr %$t498.addr
  %ld30 = load i64, ptr %$t499.addr
  %cr31 = call i64 @collatz(i64 %ld29, i64 %ld30)
  %cv32 = inttoptr i64 %cr31 to ptr
  store ptr %cv32, ptr %res_slot14
  br label %case_merge4
case_merge4:
  %case_r33 = load ptr, ptr %res_slot14
  store ptr %case_r33, ptr %res_slot5
  br label %case_merge1
case_merge1:
  %case_r34 = load ptr, ptr %res_slot5
  %cv35 = ptrtoint ptr %case_r34 to i64
  ret i64 %cv35
}

define i64 @two_tasks() {
entry:
  %hp36 = call ptr @march_alloc(i64 24)
  %tgp37 = getelementptr i8, ptr %hp36, i64 8
  store i32 0, ptr %tgp37, align 4
  %fp38 = getelementptr i8, ptr %hp36, i64 16
  store ptr @$lam500$apply, ptr %fp38, align 8
  %$t501.addr = alloca ptr
  store ptr %hp36, ptr %$t501.addr
  %ld39 = load ptr, ptr %$t501.addr
  %fp40 = getelementptr i8, ptr %ld39, i64 16
  %fv41 = load ptr, ptr %fp40, align 8
  %tsres42 = call i64 %fv41(ptr %ld39, i64 0)
  %hp43 = call ptr @march_alloc(i64 24)
  %tgp44 = getelementptr i8, ptr %hp43, i64 8
  store i32 0, ptr %tgp44, align 4
  %fp45 = getelementptr i8, ptr %hp43, i64 16
  store i64 %tsres42, ptr %fp45, align 8
  %t1.addr = alloca ptr
  store ptr %hp43, ptr %t1.addr
  %hp46 = call ptr @march_alloc(i64 24)
  %tgp47 = getelementptr i8, ptr %hp46, i64 8
  store i32 0, ptr %tgp47, align 4
  %fp48 = getelementptr i8, ptr %hp46, i64 16
  store ptr @$lam502$apply, ptr %fp48, align 8
  %$t503.addr = alloca ptr
  store ptr %hp46, ptr %$t503.addr
  %ld49 = load ptr, ptr %$t503.addr
  %fp50 = getelementptr i8, ptr %ld49, i64 16
  %fv51 = load ptr, ptr %fp50, align 8
  %tsres52 = call i64 %fv51(ptr %ld49, i64 0)
  %hp53 = call ptr @march_alloc(i64 24)
  %tgp54 = getelementptr i8, ptr %hp53, i64 8
  store i32 0, ptr %tgp54, align 4
  %fp55 = getelementptr i8, ptr %hp53, i64 16
  store i64 %tsres52, ptr %fp55, align 8
  %t2.addr = alloca ptr
  store ptr %hp53, ptr %t2.addr
  %ld56 = load ptr, ptr %t1.addr
  %fp57 = getelementptr i8, ptr %ld56, i64 16
  %fv58 = load i64, ptr %fp57, align 8
  %r1.addr = alloca i64
  store i64 %fv58, ptr %r1.addr
  %ld59 = load ptr, ptr %t2.addr
  %fp60 = getelementptr i8, ptr %ld59, i64 16
  %fv61 = load i64, ptr %fp60, align 8
  %r2.addr = alloca i64
  store i64 %fv61, ptr %r2.addr
  %ld62 = load i64, ptr %r1.addr
  %ld63 = load i64, ptr %r2.addr
  %ar64 = add i64 %ld62, %ld63
  ret i64 %ar64
}

define i64 @fan_out_inner(i64 %n.arg, i64 %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld65 = load i64, ptr %n.addr
  %cmp66 = icmp eq i64 %ld65, 0
  %ar67 = zext i1 %cmp66 to i64
  %$t508.addr = alloca i64
  store i64 %ar67, ptr %$t508.addr
  %ld68 = load i64, ptr %$t508.addr
  %res_slot69 = alloca ptr
  switch i64 %ld68, label %case_default8 [
      i64 1, label %case_br9
  ]
case_br9:
  %ld70 = load i64, ptr %acc.addr
  %cv71 = inttoptr i64 %ld70 to ptr
  store ptr %cv71, ptr %res_slot69
  br label %case_merge7
case_default8:
  %hp72 = call ptr @march_alloc(i64 32)
  %tgp73 = getelementptr i8, ptr %hp72, i64 8
  store i32 0, ptr %tgp73, align 4
  %fp74 = getelementptr i8, ptr %hp72, i64 16
  store ptr @$lam509$apply, ptr %fp74, align 8
  %ld75 = load i64, ptr %n.addr
  %fp76 = getelementptr i8, ptr %hp72, i64 24
  store i64 %ld75, ptr %fp76, align 8
  %$t510.addr = alloca ptr
  store ptr %hp72, ptr %$t510.addr
  %ld77 = load ptr, ptr %$t510.addr
  %fp78 = getelementptr i8, ptr %ld77, i64 16
  %fv79 = load ptr, ptr %fp78, align 8
  %tsres80 = call i64 %fv79(ptr %ld77, i64 0)
  %hp81 = call ptr @march_alloc(i64 24)
  %tgp82 = getelementptr i8, ptr %hp81, i64 8
  store i32 0, ptr %tgp82, align 4
  %fp83 = getelementptr i8, ptr %hp81, i64 16
  store i64 %tsres80, ptr %fp83, align 8
  %t.addr = alloca ptr
  store ptr %hp81, ptr %t.addr
  %ld84 = load ptr, ptr %t.addr
  %fp85 = getelementptr i8, ptr %ld84, i64 16
  %fv86 = load i64, ptr %fp85, align 8
  %r.addr = alloca i64
  store i64 %fv86, ptr %r.addr
  %ld87 = load i64, ptr %n.addr
  %ar88 = sub i64 %ld87, 1
  %$t511.addr = alloca i64
  store i64 %ar88, ptr %$t511.addr
  %ld89 = load i64, ptr %acc.addr
  %ld90 = load i64, ptr %r.addr
  %ar91 = add i64 %ld89, %ld90
  %$t512.addr = alloca i64
  store i64 %ar91, ptr %$t512.addr
  %ld92 = load i64, ptr %$t511.addr
  %ld93 = load i64, ptr %$t512.addr
  %cr94 = call i64 @fan_out_inner(i64 %ld92, i64 %ld93)
  %cv95 = inttoptr i64 %cr94 to ptr
  store ptr %cv95, ptr %res_slot69
  br label %case_merge7
case_merge7:
  %case_r96 = load ptr, ptr %res_slot69
  %cv97 = ptrtoint ptr %case_r96 to i64
  ret i64 %cv97
}

define void @march_main() {
entry:
  %sl98 = call ptr @march_string_lit(ptr @.str1, i64 19)
  call void @march_println(ptr %sl98)
  %cr99 = call i64 @two_tasks()
  %r.addr = alloca i64
  store i64 %cr99, ptr %r.addr
  %ld100 = load i64, ptr %r.addr
  %cr101 = call ptr @march_int_to_string(i64 %ld100)
  %$t513.addr = alloca ptr
  store ptr %cr101, ptr %$t513.addr
  %sl102 = call ptr @march_string_lit(ptr @.str2, i64 29)
  %ld103 = load ptr, ptr %$t513.addr
  %cr104 = call ptr @march_string_concat(ptr %sl102, ptr %ld103)
  %$t514.addr = alloca ptr
  store ptr %cr104, ptr %$t514.addr
  %ld105 = load ptr, ptr %$t514.addr
  call void @march_println(ptr %ld105)
  %hp106 = call ptr @march_alloc(i64 24)
  %tgp107 = getelementptr i8, ptr %hp106, i64 8
  store i32 0, ptr %tgp107, align 4
  %fp108 = getelementptr i8, ptr %hp106, i64 16
  store ptr @$lam504$apply, ptr %fp108, align 8
  %$t505_i2.addr = alloca ptr
  store ptr %hp106, ptr %$t505_i2.addr
  %ld109 = load ptr, ptr %$t505_i2.addr
  %fp110 = getelementptr i8, ptr %ld109, i64 16
  %fv111 = load ptr, ptr %fp110, align 8
  %tsres112 = call i64 %fv111(ptr %ld109, i64 0)
  %hp113 = call ptr @march_alloc(i64 24)
  %tgp114 = getelementptr i8, ptr %hp113, i64 8
  store i32 0, ptr %tgp114, align 4
  %fp115 = getelementptr i8, ptr %hp113, i64 16
  store i64 %tsres112, ptr %fp115, align 8
  %t1_i3.addr = alloca ptr
  store ptr %hp113, ptr %t1_i3.addr
  %ld116 = load ptr, ptr %t1_i3.addr
  %fp117 = getelementptr i8, ptr %ld116, i64 16
  %fv118 = load i64, ptr %fp117, align 8
  %v1_i4.addr = alloca i64
  store i64 %fv118, ptr %v1_i4.addr
  %hp119 = call ptr @march_alloc(i64 32)
  %tgp120 = getelementptr i8, ptr %hp119, i64 8
  store i32 0, ptr %tgp120, align 4
  %fp121 = getelementptr i8, ptr %hp119, i64 16
  store ptr @$lam506$apply, ptr %fp121, align 8
  %ld122 = load i64, ptr %v1_i4.addr
  %fp123 = getelementptr i8, ptr %hp119, i64 24
  store i64 %ld122, ptr %fp123, align 8
  %$t507_i5.addr = alloca ptr
  store ptr %hp119, ptr %$t507_i5.addr
  %ld124 = load ptr, ptr %$t507_i5.addr
  %fp125 = getelementptr i8, ptr %ld124, i64 16
  %fv126 = load ptr, ptr %fp125, align 8
  %tsres127 = call i64 %fv126(ptr %ld124, i64 0)
  %hp128 = call ptr @march_alloc(i64 24)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  %fp130 = getelementptr i8, ptr %hp128, i64 16
  store i64 %tsres127, ptr %fp130, align 8
  %t2_i6.addr = alloca ptr
  store ptr %hp128, ptr %t2_i6.addr
  %ld131 = load ptr, ptr %t2_i6.addr
  %fp132 = getelementptr i8, ptr %ld131, i64 16
  %fv133 = load i64, ptr %fp132, align 8
  %c.addr = alloca i64
  store i64 %fv133, ptr %c.addr
  %ld134 = load i64, ptr %c.addr
  %cr135 = call ptr @march_int_to_string(i64 %ld134)
  %$t515.addr = alloca ptr
  store ptr %cr135, ptr %$t515.addr
  %sl136 = call ptr @march_string_lit(ptr @.str3, i64 25)
  %ld137 = load ptr, ptr %$t515.addr
  %cr138 = call ptr @march_string_concat(ptr %sl136, ptr %ld137)
  %$t516.addr = alloca ptr
  store ptr %cr138, ptr %$t516.addr
  %ld139 = load ptr, ptr %$t516.addr
  call void @march_println(ptr %ld139)
  %n_i1.addr = alloca i64
  store i64 100, ptr %n_i1.addr
  %ld140 = load i64, ptr %n_i1.addr
  %cr141 = call i64 @fan_out_inner(i64 %ld140, i64 0)
  %f.addr = alloca i64
  store i64 %cr141, ptr %f.addr
  %ld142 = load i64, ptr %f.addr
  %cr143 = call ptr @march_int_to_string(i64 %ld142)
  %$t517.addr = alloca ptr
  store ptr %cr143, ptr %$t517.addr
  %sl144 = call ptr @march_string_lit(ptr @.str4, i64 25)
  %ld145 = load ptr, ptr %$t517.addr
  %cr146 = call ptr @march_string_concat(ptr %sl144, ptr %ld145)
  %$t518.addr = alloca ptr
  store ptr %cr146, ptr %$t518.addr
  %ld147 = load ptr, ptr %$t518.addr
  call void @march_println(ptr %ld147)
  ret void
}

define i64 @$lam500$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %cr148 = call i64 @collatz(i64 27, i64 0)
  ret i64 %cr148
}

define i64 @$lam502$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %cr149 = call i64 @collatz(i64 871, i64 0)
  ret i64 %cr149
}

define i64 @$lam504$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  ret i64 30
}

define i64 @$lam506$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld150 = load ptr, ptr %$clo.addr
  %fp151 = getelementptr i8, ptr %ld150, i64 24
  %fv152 = load i64, ptr %fp151, align 8
  %v1.addr = alloca i64
  store i64 %fv152, ptr %v1.addr
  %ld153 = load i64, ptr %v1.addr
  %ar154 = mul i64 %ld153, 3
  ret i64 %ar154
}

define i64 @$lam509$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld155 = load ptr, ptr %$clo.addr
  %fp156 = getelementptr i8, ptr %ld155, i64 24
  %fv157 = load i64, ptr %fp156, align 8
  %n.addr = alloca i64
  store i64 %fv157, ptr %n.addr
  %ld158 = load i64, ptr %n.addr
  %cr159 = call i64 @collatz(i64 %ld158, i64 0)
  ret i64 %cr159
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
