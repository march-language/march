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
  store i64 1, ptr %fp8, align 8
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

define i64 @sum(ptr %t.arg) {
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
  %ld30 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld30)
  %ld31 = load i64, ptr %n.addr
  %cv32 = inttoptr i64 %ld31 to ptr
  store ptr %cv32, ptr %res_slot25
  br label %case_merge4
case_br7:
  %fp33 = getelementptr i8, ptr %ld24, i64 16
  %fv34 = load ptr, ptr %fp33, align 8
  %l.addr = alloca ptr
  store ptr %fv34, ptr %l.addr
  %fp35 = getelementptr i8, ptr %ld24, i64 24
  %fv36 = load ptr, ptr %fp35, align 8
  %r.addr = alloca ptr
  store ptr %fv36, ptr %r.addr
  %ld37 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld37)
  %ld38 = load ptr, ptr %l.addr
  %cr39 = call i64 @sum(ptr %ld38)
  %$t356.addr = alloca i64
  store i64 %cr39, ptr %$t356.addr
  %ld40 = load ptr, ptr %r.addr
  %cr41 = call i64 @sum(ptr %ld40)
  %$t357.addr = alloca i64
  store i64 %cr41, ptr %$t357.addr
  %ld42 = load i64, ptr %$t356.addr
  %ld43 = load i64, ptr %$t357.addr
  %ar44 = add i64 %ld42, %ld43
  %cv45 = inttoptr i64 %ar44 to ptr
  store ptr %cv45, ptr %res_slot25
  br label %case_merge4
case_default5:
  unreachable
case_merge4:
  %case_r46 = load ptr, ptr %res_slot25
  %cv47 = ptrtoint ptr %case_r46 to i64
  ret i64 %cv47
}

define i64 @par_sum(ptr %t.arg, i64 %depth.arg, i64 %threshold.arg) {
entry:
  %t.addr = alloca ptr
  store ptr %t.arg, ptr %t.addr
  %depth.addr = alloca i64
  store i64 %depth.arg, ptr %depth.addr
  %threshold.addr = alloca i64
  store i64 %threshold.arg, ptr %threshold.addr
  %ld48 = load ptr, ptr %t.addr
  %res_slot49 = alloca ptr
  %tgp50 = getelementptr i8, ptr %ld48, i64 8
  %tag51 = load i32, ptr %tgp50, align 4
  switch i32 %tag51, label %case_default9 [
      i32 0, label %case_br10
      i32 1, label %case_br11
  ]
case_br10:
  %fp52 = getelementptr i8, ptr %ld48, i64 16
  %fv53 = load i64, ptr %fp52, align 8
  %n.addr = alloca i64
  store i64 %fv53, ptr %n.addr
  %ld54 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld54)
  %ld55 = load i64, ptr %n.addr
  %cv56 = inttoptr i64 %ld55 to ptr
  store ptr %cv56, ptr %res_slot49
  br label %case_merge8
case_br11:
  %fp57 = getelementptr i8, ptr %ld48, i64 16
  %fv58 = load ptr, ptr %fp57, align 8
  %l.addr = alloca ptr
  store ptr %fv58, ptr %l.addr
  %fp59 = getelementptr i8, ptr %ld48, i64 24
  %fv60 = load ptr, ptr %fp59, align 8
  %r.addr = alloca ptr
  store ptr %fv60, ptr %r.addr
  %ld61 = load ptr, ptr %t.addr
  call void @march_decrc(ptr %ld61)
  %ld62 = load i64, ptr %depth.addr
  %ld63 = load i64, ptr %threshold.addr
  %cmp64 = icmp sge i64 %ld62, %ld63
  %ar65 = zext i1 %cmp64 to i64
  %$t358.addr = alloca i64
  store i64 %ar65, ptr %$t358.addr
  %ld66 = load i64, ptr %$t358.addr
  %res_slot67 = alloca ptr
  switch i64 %ld66, label %case_default13 [
      i64 1, label %case_br14
  ]
case_br14:
  %ld68 = load ptr, ptr %l.addr
  %cr69 = call i64 @sum(ptr %ld68)
  %$t359.addr = alloca i64
  store i64 %cr69, ptr %$t359.addr
  %ld70 = load ptr, ptr %r.addr
  %cr71 = call i64 @sum(ptr %ld70)
  %$t360.addr = alloca i64
  store i64 %cr71, ptr %$t360.addr
  %ld72 = load i64, ptr %$t359.addr
  %ld73 = load i64, ptr %$t360.addr
  %ar74 = add i64 %ld72, %ld73
  %cv75 = inttoptr i64 %ar74 to ptr
  store ptr %cv75, ptr %res_slot67
  br label %case_merge12
case_default13:
  %hp76 = call ptr @march_alloc(i64 48)
  %tgp77 = getelementptr i8, ptr %hp76, i64 8
  store i32 0, ptr %tgp77, align 4
  %fp78 = getelementptr i8, ptr %hp76, i64 16
  store ptr @$lam361$apply, ptr %fp78, align 8
  %ld79 = load i64, ptr %depth.addr
  %fp80 = getelementptr i8, ptr %hp76, i64 24
  store i64 %ld79, ptr %fp80, align 8
  %ld81 = load ptr, ptr %l.addr
  %fp82 = getelementptr i8, ptr %hp76, i64 32
  store ptr %ld81, ptr %fp82, align 8
  %ld83 = load i64, ptr %threshold.addr
  %fp84 = getelementptr i8, ptr %hp76, i64 40
  store i64 %ld83, ptr %fp84, align 8
  %$t363.addr = alloca ptr
  store ptr %hp76, ptr %$t363.addr
  %ld85 = load ptr, ptr %$t363.addr
  %fp86 = getelementptr i8, ptr %ld85, i64 16
  %fv87 = load ptr, ptr %fp86, align 8
  %tsres88 = call i64 %fv87(ptr %ld85, i64 0)
  %hp89 = call ptr @march_alloc(i64 24)
  %tgp90 = getelementptr i8, ptr %hp89, i64 8
  store i32 0, ptr %tgp90, align 4
  %fp91 = getelementptr i8, ptr %hp89, i64 16
  store i64 %tsres88, ptr %fp91, align 8
  %tl.addr = alloca ptr
  store ptr %hp89, ptr %tl.addr
  %hp92 = call ptr @march_alloc(i64 48)
  %tgp93 = getelementptr i8, ptr %hp92, i64 8
  store i32 0, ptr %tgp93, align 4
  %fp94 = getelementptr i8, ptr %hp92, i64 16
  store ptr @$lam364$apply, ptr %fp94, align 8
  %ld95 = load i64, ptr %depth.addr
  %fp96 = getelementptr i8, ptr %hp92, i64 24
  store i64 %ld95, ptr %fp96, align 8
  %ld97 = load ptr, ptr %r.addr
  %fp98 = getelementptr i8, ptr %hp92, i64 32
  store ptr %ld97, ptr %fp98, align 8
  %ld99 = load i64, ptr %threshold.addr
  %fp100 = getelementptr i8, ptr %hp92, i64 40
  store i64 %ld99, ptr %fp100, align 8
  %$t366.addr = alloca ptr
  store ptr %hp92, ptr %$t366.addr
  %ld101 = load ptr, ptr %$t366.addr
  %fp102 = getelementptr i8, ptr %ld101, i64 16
  %fv103 = load ptr, ptr %fp102, align 8
  %tsres104 = call i64 %fv103(ptr %ld101, i64 0)
  %hp105 = call ptr @march_alloc(i64 24)
  %tgp106 = getelementptr i8, ptr %hp105, i64 8
  store i32 0, ptr %tgp106, align 4
  %fp107 = getelementptr i8, ptr %hp105, i64 16
  store i64 %tsres104, ptr %fp107, align 8
  %tr.addr = alloca ptr
  store ptr %hp105, ptr %tr.addr
  %ld108 = load ptr, ptr %tl.addr
  %fp109 = getelementptr i8, ptr %ld108, i64 16
  %fv110 = load i64, ptr %fp109, align 8
  %rl.addr = alloca i64
  store i64 %fv110, ptr %rl.addr
  %ld111 = load ptr, ptr %tr.addr
  %fp112 = getelementptr i8, ptr %ld111, i64 16
  %fv113 = load i64, ptr %fp112, align 8
  %rr.addr = alloca i64
  store i64 %fv113, ptr %rr.addr
  %ld114 = load i64, ptr %rl.addr
  %ld115 = load i64, ptr %rr.addr
  %ar116 = add i64 %ld114, %ld115
  %cv117 = inttoptr i64 %ar116 to ptr
  store ptr %cv117, ptr %res_slot67
  br label %case_merge12
case_merge12:
  %case_r118 = load ptr, ptr %res_slot67
  store ptr %case_r118, ptr %res_slot49
  br label %case_merge8
case_default9:
  unreachable
case_merge8:
  %case_r119 = load ptr, ptr %res_slot49
  %cv120 = ptrtoint ptr %case_r119 to i64
  ret i64 %cv120
}

define void @march_main() {
entry:
  %cr121 = call ptr @make(i64 24)
  %t.addr = alloca ptr
  store ptr %cr121, ptr %t.addr
  %ld122 = load ptr, ptr %t.addr
  %cr123 = call i64 @par_sum(ptr %ld122, i64 0, i64 10)
  %total.addr = alloca i64
  store i64 %cr123, ptr %total.addr
  %ld124 = load i64, ptr %total.addr
  %cr125 = call ptr @march_int_to_string(i64 %ld124)
  %$t367.addr = alloca ptr
  store ptr %cr125, ptr %$t367.addr
  %ld126 = load ptr, ptr %$t367.addr
  call void @march_println(ptr %ld126)
  ret void
}

define i64 @$lam361$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld127 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld127)
  %ld128 = load ptr, ptr %$clo.addr
  %fp129 = getelementptr i8, ptr %ld128, i64 24
  %fv130 = load ptr, ptr %fp129, align 8
  %cv131 = ptrtoint ptr %fv130 to i64
  %depth.addr = alloca i64
  store i64 %cv131, ptr %depth.addr
  %ld132 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld132)
  %ld133 = load ptr, ptr %$clo.addr
  %fp134 = getelementptr i8, ptr %ld133, i64 32
  %fv135 = load ptr, ptr %fp134, align 8
  %l.addr = alloca ptr
  store ptr %fv135, ptr %l.addr
  %ld136 = load ptr, ptr %$clo.addr
  %fp137 = getelementptr i8, ptr %ld136, i64 40
  %fv138 = load i64, ptr %fp137, align 8
  %threshold.addr = alloca i64
  store i64 %fv138, ptr %threshold.addr
  %ld139 = load i64, ptr %depth.addr
  %ar140 = add i64 %ld139, 1
  %$t362.addr = alloca i64
  store i64 %ar140, ptr %$t362.addr
  %ld141 = load ptr, ptr %l.addr
  %ld142 = load i64, ptr %$t362.addr
  %ld143 = load i64, ptr %threshold.addr
  %cr144 = call i64 @par_sum(ptr %ld141, i64 %ld142, i64 %ld143)
  ret i64 %cr144
}

define i64 @$lam364$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld145 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld145)
  %ld146 = load ptr, ptr %$clo.addr
  %fp147 = getelementptr i8, ptr %ld146, i64 24
  %fv148 = load ptr, ptr %fp147, align 8
  %cv149 = ptrtoint ptr %fv148 to i64
  %depth.addr = alloca i64
  store i64 %cv149, ptr %depth.addr
  %ld150 = load ptr, ptr %$clo.addr
  call void @march_incrc(ptr %ld150)
  %ld151 = load ptr, ptr %$clo.addr
  %fp152 = getelementptr i8, ptr %ld151, i64 32
  %fv153 = load ptr, ptr %fp152, align 8
  %r.addr = alloca ptr
  store ptr %fv153, ptr %r.addr
  %ld154 = load ptr, ptr %$clo.addr
  %fp155 = getelementptr i8, ptr %ld154, i64 40
  %fv156 = load i64, ptr %fp155, align 8
  %threshold.addr = alloca i64
  store i64 %fv156, ptr %threshold.addr
  %ld157 = load i64, ptr %depth.addr
  %ar158 = add i64 %ld157, 1
  %$t365.addr = alloca i64
  store i64 %ar158, ptr %$t365.addr
  %ld159 = load ptr, ptr %r.addr
  %ld160 = load i64, ptr %$t365.addr
  %ld161 = load i64, ptr %threshold.addr
  %cr162 = call i64 @par_sum(ptr %ld159, i64 %ld160, i64 %ld161)
  ret i64 %cr162
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
