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


define i64 @rank(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld1 = load ptr, ptr %h.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld5 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld5)
  %cv6 = inttoptr i64 0 to ptr
  store ptr %cv6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp7 = getelementptr i8, ptr %ld1, i64 16
  %fv8 = load i64, ptr %fp7, align 8
  %$f970.addr = alloca i64
  store i64 %fv8, ptr %$f970.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load i64, ptr %fp9, align 8
  %$f971.addr = alloca i64
  store i64 %fv10, ptr %$f971.addr
  %fp11 = getelementptr i8, ptr %ld1, i64 32
  %fv12 = load ptr, ptr %fp11, align 8
  %$f972.addr = alloca ptr
  store ptr %fv12, ptr %$f972.addr
  %fp13 = getelementptr i8, ptr %ld1, i64 40
  %fv14 = load ptr, ptr %fp13, align 8
  %$f973.addr = alloca ptr
  store ptr %fv14, ptr %$f973.addr
  %freed15 = call i64 @march_decrc_freed(ptr %ld1)
  %freed_b16 = icmp ne i64 %freed15, 0
  br i1 %freed_b16, label %br_unique5, label %br_shared6
br_shared6:
  call void @march_incrc(ptr %fv14)
  call void @march_incrc(ptr %fv12)
  br label %br_body7
br_unique5:
  br label %br_body7
br_body7:
  %ld17 = load ptr, ptr %$f970.addr
  %r.addr = alloca ptr
  store ptr %ld17, ptr %r.addr
  %ld18 = load i64, ptr %r.addr
  %cv19 = inttoptr i64 %ld18 to ptr
  store ptr %cv19, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r20 = load ptr, ptr %res_slot2
  %cv21 = ptrtoint ptr %case_r20 to i64
  ret i64 %cv21
}

define ptr @make_node(i64 %v.arg, ptr %a.arg, ptr %b.arg) {
entry:
  %v.addr = alloca i64
  store i64 %v.arg, ptr %v.addr
  %a.addr = alloca ptr
  store ptr %a.arg, ptr %a.addr
  %b.addr = alloca ptr
  store ptr %b.arg, ptr %b.addr
  %ld22 = load ptr, ptr %a.addr
  call void @march_incrc(ptr %ld22)
  %ld23 = load ptr, ptr %a.addr
  %cr24 = call i64 @rank(ptr %ld23)
  %$t974.addr = alloca i64
  store i64 %cr24, ptr %$t974.addr
  %ld25 = load ptr, ptr %b.addr
  call void @march_incrc(ptr %ld25)
  %ld26 = load ptr, ptr %b.addr
  %cr27 = call i64 @rank(ptr %ld26)
  %$t975.addr = alloca i64
  store i64 %cr27, ptr %$t975.addr
  %ld28 = load i64, ptr %$t974.addr
  %ld29 = load i64, ptr %$t975.addr
  %cmp30 = icmp sge i64 %ld28, %ld29
  %ar31 = zext i1 %cmp30 to i64
  %$t976.addr = alloca i64
  store i64 %ar31, ptr %$t976.addr
  %ld32 = load i64, ptr %$t976.addr
  %res_slot33 = alloca ptr
  switch i64 %ld32, label %case_default9 [
      i64 1, label %case_br10
  ]
case_br10:
  %ld34 = load ptr, ptr %b.addr
  call void @march_incrc(ptr %ld34)
  %ld35 = load ptr, ptr %b.addr
  %cr36 = call i64 @rank(ptr %ld35)
  %$t977.addr = alloca i64
  store i64 %cr36, ptr %$t977.addr
  %ld37 = load i64, ptr %$t977.addr
  %ar38 = add i64 %ld37, 1
  %$t978.addr = alloca i64
  store i64 %ar38, ptr %$t978.addr
  %hp39 = call ptr @march_alloc(i64 48)
  %tgp40 = getelementptr i8, ptr %hp39, i64 8
  store i32 1, ptr %tgp40, align 4
  %ld41 = load i64, ptr %$t978.addr
  %fp42 = getelementptr i8, ptr %hp39, i64 16
  store i64 %ld41, ptr %fp42, align 8
  %ld43 = load i64, ptr %v.addr
  %fp44 = getelementptr i8, ptr %hp39, i64 24
  store i64 %ld43, ptr %fp44, align 8
  %ld45 = load ptr, ptr %a.addr
  %fp46 = getelementptr i8, ptr %hp39, i64 32
  store ptr %ld45, ptr %fp46, align 8
  %ld47 = load ptr, ptr %b.addr
  %fp48 = getelementptr i8, ptr %hp39, i64 40
  store ptr %ld47, ptr %fp48, align 8
  store ptr %hp39, ptr %res_slot33
  br label %case_merge8
case_default9:
  %ld49 = load ptr, ptr %a.addr
  call void @march_incrc(ptr %ld49)
  %ld50 = load ptr, ptr %a.addr
  %cr51 = call i64 @rank(ptr %ld50)
  %$t979.addr = alloca i64
  store i64 %cr51, ptr %$t979.addr
  %ld52 = load i64, ptr %$t979.addr
  %ar53 = add i64 %ld52, 1
  %$t980.addr = alloca i64
  store i64 %ar53, ptr %$t980.addr
  %hp54 = call ptr @march_alloc(i64 48)
  %tgp55 = getelementptr i8, ptr %hp54, i64 8
  store i32 1, ptr %tgp55, align 4
  %ld56 = load i64, ptr %$t980.addr
  %fp57 = getelementptr i8, ptr %hp54, i64 16
  store i64 %ld56, ptr %fp57, align 8
  %ld58 = load i64, ptr %v.addr
  %fp59 = getelementptr i8, ptr %hp54, i64 24
  store i64 %ld58, ptr %fp59, align 8
  %ld60 = load ptr, ptr %b.addr
  %fp61 = getelementptr i8, ptr %hp54, i64 32
  store ptr %ld60, ptr %fp61, align 8
  %ld62 = load ptr, ptr %a.addr
  %fp63 = getelementptr i8, ptr %hp54, i64 40
  store ptr %ld62, ptr %fp63, align 8
  store ptr %hp54, ptr %res_slot33
  br label %case_merge8
case_merge8:
  %case_r64 = load ptr, ptr %res_slot33
  ret ptr %case_r64
}

define ptr @heap_merge(ptr %h1.arg, ptr %h2.arg) {
entry:
  %h1.addr = alloca ptr
  store ptr %h1.arg, ptr %h1.addr
  %h2.addr = alloca ptr
  store ptr %h2.arg, ptr %h2.addr
  %ld65 = load ptr, ptr %h1.addr
  %res_slot66 = alloca ptr
  %tgp67 = getelementptr i8, ptr %ld65, i64 8
  %tag68 = load i32, ptr %tgp67, align 4
  switch i32 %tag68, label %case_default12 [
      i32 0, label %case_br13
      i32 1, label %case_br14
  ]
case_br13:
  %ld69 = load ptr, ptr %h1.addr
  call void @march_decrc(ptr %ld69)
  %ld70 = load ptr, ptr %h2.addr
  store ptr %ld70, ptr %res_slot66
  br label %case_merge11
case_br14:
  %fp71 = getelementptr i8, ptr %ld65, i64 16
  %fv72 = load i64, ptr %fp71, align 8
  %$f988.addr = alloca i64
  store i64 %fv72, ptr %$f988.addr
  %fp73 = getelementptr i8, ptr %ld65, i64 24
  %fv74 = load i64, ptr %fp73, align 8
  %$f989.addr = alloca i64
  store i64 %fv74, ptr %$f989.addr
  %fp75 = getelementptr i8, ptr %ld65, i64 32
  %fv76 = load ptr, ptr %fp75, align 8
  %$f990.addr = alloca ptr
  store ptr %fv76, ptr %$f990.addr
  %fp77 = getelementptr i8, ptr %ld65, i64 40
  %fv78 = load ptr, ptr %fp77, align 8
  %$f991.addr = alloca ptr
  store ptr %fv78, ptr %$f991.addr
  %ld79 = load ptr, ptr %$f991.addr
  %r1.addr = alloca ptr
  store ptr %ld79, ptr %r1.addr
  %ld80 = load ptr, ptr %$f990.addr
  %l1.addr = alloca ptr
  store ptr %ld80, ptr %l1.addr
  %ld81 = load ptr, ptr %$f989.addr
  %x.addr = alloca ptr
  store ptr %ld81, ptr %x.addr
  %ld82 = load ptr, ptr %h2.addr
  %res_slot83 = alloca ptr
  %tgp84 = getelementptr i8, ptr %ld82, i64 8
  %tag85 = load i32, ptr %tgp84, align 4
  switch i32 %tag85, label %case_default16 [
      i32 0, label %case_br17
      i32 1, label %case_br18
  ]
case_br17:
  %ld86 = load ptr, ptr %h2.addr
  call void @march_decrc(ptr %ld86)
  %ld87 = load ptr, ptr %h1.addr
  store ptr %ld87, ptr %res_slot83
  br label %case_merge15
case_br18:
  %fp88 = getelementptr i8, ptr %ld82, i64 16
  %fv89 = load i64, ptr %fp88, align 8
  %$f984.addr = alloca i64
  store i64 %fv89, ptr %$f984.addr
  %fp90 = getelementptr i8, ptr %ld82, i64 24
  %fv91 = load i64, ptr %fp90, align 8
  %$f985.addr = alloca i64
  store i64 %fv91, ptr %$f985.addr
  %fp92 = getelementptr i8, ptr %ld82, i64 32
  %fv93 = load ptr, ptr %fp92, align 8
  %$f986.addr = alloca ptr
  store ptr %fv93, ptr %$f986.addr
  %fp94 = getelementptr i8, ptr %ld82, i64 40
  %fv95 = load ptr, ptr %fp94, align 8
  %$f987.addr = alloca ptr
  store ptr %fv95, ptr %$f987.addr
  %ld96 = load ptr, ptr %$f987.addr
  %r2.addr = alloca ptr
  store ptr %ld96, ptr %r2.addr
  %ld97 = load ptr, ptr %$f986.addr
  %l2.addr = alloca ptr
  store ptr %ld97, ptr %l2.addr
  %ld98 = load ptr, ptr %$f985.addr
  %y.addr = alloca ptr
  store ptr %ld98, ptr %y.addr
  %ld99 = load i64, ptr %x.addr
  %ld100 = load i64, ptr %y.addr
  %cmp101 = icmp sle i64 %ld99, %ld100
  %ar102 = zext i1 %cmp101 to i64
  %$t981.addr = alloca i64
  store i64 %ar102, ptr %$t981.addr
  %ld103 = load i64, ptr %$t981.addr
  %res_slot104 = alloca ptr
  switch i64 %ld103, label %case_default20 [
      i64 1, label %case_br21
  ]
case_br21:
  %ld105 = load ptr, ptr %r1.addr
  %ld106 = load ptr, ptr %h2.addr
  %cr107 = call ptr @heap_merge(ptr %ld105, ptr %ld106)
  %$t982.addr = alloca ptr
  store ptr %cr107, ptr %$t982.addr
  %ld108 = load i64, ptr %x.addr
  %ld109 = load ptr, ptr %l1.addr
  %ld110 = load ptr, ptr %$t982.addr
  %cr111 = call ptr @make_node(i64 %ld108, ptr %ld109, ptr %ld110)
  store ptr %cr111, ptr %res_slot104
  br label %case_merge19
case_default20:
  %ld112 = load ptr, ptr %h1.addr
  %ld113 = load ptr, ptr %r2.addr
  %cr114 = call ptr @heap_merge(ptr %ld112, ptr %ld113)
  %$t983.addr = alloca ptr
  store ptr %cr114, ptr %$t983.addr
  %ld115 = load i64, ptr %y.addr
  %ld116 = load ptr, ptr %l2.addr
  %ld117 = load ptr, ptr %$t983.addr
  %cr118 = call ptr @make_node(i64 %ld115, ptr %ld116, ptr %ld117)
  store ptr %cr118, ptr %res_slot104
  br label %case_merge19
case_merge19:
  %case_r119 = load ptr, ptr %res_slot104
  store ptr %case_r119, ptr %res_slot83
  br label %case_merge15
case_default16:
  unreachable
case_merge15:
  %case_r120 = load ptr, ptr %res_slot83
  store ptr %case_r120, ptr %res_slot66
  br label %case_merge11
case_default12:
  unreachable
case_merge11:
  %case_r121 = load ptr, ptr %res_slot66
  ret ptr %case_r121
}

define i64 @heap_min(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld122 = load ptr, ptr %h.addr
  %res_slot123 = alloca ptr
  %tgp124 = getelementptr i8, ptr %ld122, i64 8
  %tag125 = load i32, ptr %tgp124, align 4
  switch i32 %tag125, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld126 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld126)
  %cv127 = inttoptr i64 0 to ptr
  store ptr %cv127, ptr %res_slot123
  br label %case_merge22
case_br25:
  %fp128 = getelementptr i8, ptr %ld122, i64 16
  %fv129 = load i64, ptr %fp128, align 8
  %$f995.addr = alloca i64
  store i64 %fv129, ptr %$f995.addr
  %fp130 = getelementptr i8, ptr %ld122, i64 24
  %fv131 = load i64, ptr %fp130, align 8
  %$f996.addr = alloca i64
  store i64 %fv131, ptr %$f996.addr
  %fp132 = getelementptr i8, ptr %ld122, i64 32
  %fv133 = load ptr, ptr %fp132, align 8
  %$f997.addr = alloca ptr
  store ptr %fv133, ptr %$f997.addr
  %fp134 = getelementptr i8, ptr %ld122, i64 40
  %fv135 = load ptr, ptr %fp134, align 8
  %$f998.addr = alloca ptr
  store ptr %fv135, ptr %$f998.addr
  %freed136 = call i64 @march_decrc_freed(ptr %ld122)
  %freed_b137 = icmp ne i64 %freed136, 0
  br i1 %freed_b137, label %br_unique26, label %br_shared27
br_shared27:
  call void @march_incrc(ptr %fv135)
  call void @march_incrc(ptr %fv133)
  br label %br_body28
br_unique26:
  br label %br_body28
br_body28:
  %ld138 = load ptr, ptr %$f996.addr
  %v.addr = alloca ptr
  store ptr %ld138, ptr %v.addr
  %ld139 = load i64, ptr %v.addr
  %cv140 = inttoptr i64 %ld139 to ptr
  store ptr %cv140, ptr %res_slot123
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r141 = load ptr, ptr %res_slot123
  %cv142 = ptrtoint ptr %case_r141 to i64
  ret i64 %cv142
}

define ptr @heap_pop(ptr %h.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld143 = load ptr, ptr %h.addr
  %res_slot144 = alloca ptr
  %tgp145 = getelementptr i8, ptr %ld143, i64 8
  %tag146 = load i32, ptr %tgp145, align 4
  switch i32 %tag146, label %case_default30 [
      i32 0, label %case_br31
      i32 1, label %case_br32
  ]
case_br31:
  %ld147 = load ptr, ptr %h.addr
  %rc148 = load i64, ptr %ld147, align 8
  %uniq149 = icmp eq i64 %rc148, 1
  %fbip_slot150 = alloca ptr
  br i1 %uniq149, label %fbip_reuse33, label %fbip_fresh34
fbip_reuse33:
  %tgp151 = getelementptr i8, ptr %ld147, i64 8
  store i32 0, ptr %tgp151, align 4
  store ptr %ld147, ptr %fbip_slot150
  br label %fbip_merge35
fbip_fresh34:
  call void @march_decrc(ptr %ld147)
  %hp152 = call ptr @march_alloc(i64 16)
  %tgp153 = getelementptr i8, ptr %hp152, i64 8
  store i32 0, ptr %tgp153, align 4
  store ptr %hp152, ptr %fbip_slot150
  br label %fbip_merge35
fbip_merge35:
  %fbip_r154 = load ptr, ptr %fbip_slot150
  store ptr %fbip_r154, ptr %res_slot144
  br label %case_merge29
case_br32:
  %fp155 = getelementptr i8, ptr %ld143, i64 16
  %fv156 = load i64, ptr %fp155, align 8
  %$f999.addr = alloca i64
  store i64 %fv156, ptr %$f999.addr
  %fp157 = getelementptr i8, ptr %ld143, i64 24
  %fv158 = load i64, ptr %fp157, align 8
  %$f1000.addr = alloca i64
  store i64 %fv158, ptr %$f1000.addr
  %fp159 = getelementptr i8, ptr %ld143, i64 32
  %fv160 = load ptr, ptr %fp159, align 8
  %$f1001.addr = alloca ptr
  store ptr %fv160, ptr %$f1001.addr
  %fp161 = getelementptr i8, ptr %ld143, i64 40
  %fv162 = load ptr, ptr %fp161, align 8
  %$f1002.addr = alloca ptr
  store ptr %fv162, ptr %$f1002.addr
  %freed163 = call i64 @march_decrc_freed(ptr %ld143)
  %freed_b164 = icmp ne i64 %freed163, 0
  br i1 %freed_b164, label %br_unique36, label %br_shared37
br_shared37:
  call void @march_incrc(ptr %fv162)
  call void @march_incrc(ptr %fv160)
  br label %br_body38
br_unique36:
  br label %br_body38
br_body38:
  %ld165 = load ptr, ptr %$f1002.addr
  %r.addr = alloca ptr
  store ptr %ld165, ptr %r.addr
  %ld166 = load ptr, ptr %$f1001.addr
  %l.addr = alloca ptr
  store ptr %ld166, ptr %l.addr
  %ld167 = load ptr, ptr %l.addr
  %ld168 = load ptr, ptr %r.addr
  %cr169 = call ptr @heap_merge(ptr %ld167, ptr %ld168)
  store ptr %cr169, ptr %res_slot144
  br label %case_merge29
case_default30:
  unreachable
case_merge29:
  %case_r170 = load ptr, ptr %res_slot144
  ret ptr %case_r170
}

define ptr @build_heap(ptr %xs.arg, ptr %h.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %ld171 = load ptr, ptr %xs.addr
  %res_slot172 = alloca ptr
  %tgp173 = getelementptr i8, ptr %ld171, i64 8
  %tag174 = load i32, ptr %tgp173, align 4
  switch i32 %tag174, label %case_default40 [
      i32 0, label %case_br41
      i32 1, label %case_br42
  ]
case_br41:
  %ld175 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld175)
  %ld176 = load ptr, ptr %h.addr
  store ptr %ld176, ptr %res_slot172
  br label %case_merge39
case_br42:
  %fp177 = getelementptr i8, ptr %ld171, i64 16
  %fv178 = load ptr, ptr %fp177, align 8
  %$f1004.addr = alloca ptr
  store ptr %fv178, ptr %$f1004.addr
  %fp179 = getelementptr i8, ptr %ld171, i64 24
  %fv180 = load ptr, ptr %fp179, align 8
  %$f1005.addr = alloca ptr
  store ptr %fv180, ptr %$f1005.addr
  %freed181 = call i64 @march_decrc_freed(ptr %ld171)
  %freed_b182 = icmp ne i64 %freed181, 0
  br i1 %freed_b182, label %br_unique43, label %br_shared44
br_shared44:
  call void @march_incrc(ptr %fv180)
  br label %br_body45
br_unique43:
  br label %br_body45
br_body45:
  %ld183 = load ptr, ptr %$f1005.addr
  %t.addr = alloca ptr
  store ptr %ld183, ptr %t.addr
  %ld184 = load ptr, ptr %$f1004.addr
  %v.addr = alloca ptr
  store ptr %ld184, ptr %v.addr
  %ld185 = load i64, ptr %v.addr
  %v_i1.addr = alloca i64
  store i64 %ld185, ptr %v_i1.addr
  %ld186 = load ptr, ptr %h.addr
  %h_i2.addr = alloca ptr
  store ptr %ld186, ptr %h_i2.addr
  %hp187 = call ptr @march_alloc(i64 16)
  %tgp188 = getelementptr i8, ptr %hp187, i64 8
  store i32 0, ptr %tgp188, align 4
  %$t992_i3.addr = alloca ptr
  store ptr %hp187, ptr %$t992_i3.addr
  %hp189 = call ptr @march_alloc(i64 16)
  %tgp190 = getelementptr i8, ptr %hp189, i64 8
  store i32 0, ptr %tgp190, align 4
  %$t993_i4.addr = alloca ptr
  store ptr %hp189, ptr %$t993_i4.addr
  %hp191 = call ptr @march_alloc(i64 48)
  %tgp192 = getelementptr i8, ptr %hp191, i64 8
  store i32 1, ptr %tgp192, align 4
  %fp193 = getelementptr i8, ptr %hp191, i64 16
  store i64 1, ptr %fp193, align 8
  %ld194 = load i64, ptr %v_i1.addr
  %fp195 = getelementptr i8, ptr %hp191, i64 24
  store i64 %ld194, ptr %fp195, align 8
  %ld196 = load ptr, ptr %$t992_i3.addr
  %fp197 = getelementptr i8, ptr %hp191, i64 32
  store ptr %ld196, ptr %fp197, align 8
  %ld198 = load ptr, ptr %$t993_i4.addr
  %fp199 = getelementptr i8, ptr %hp191, i64 40
  store ptr %ld198, ptr %fp199, align 8
  %$t994_i5.addr = alloca ptr
  store ptr %hp191, ptr %$t994_i5.addr
  %ld200 = load ptr, ptr %$t994_i5.addr
  %ld201 = load ptr, ptr %h_i2.addr
  %cr202 = call ptr @heap_merge(ptr %ld200, ptr %ld201)
  %$t1003.addr = alloca ptr
  store ptr %cr202, ptr %$t1003.addr
  %ld203 = load ptr, ptr %t.addr
  %ld204 = load ptr, ptr %$t1003.addr
  %cr205 = call ptr @build_heap(ptr %ld203, ptr %ld204)
  store ptr %cr205, ptr %res_slot172
  br label %case_merge39
case_default40:
  unreachable
case_merge39:
  %case_r206 = load ptr, ptr %res_slot172
  ret ptr %case_r206
}

define ptr @drain_heap(ptr %h.arg, ptr %acc.arg) {
entry:
  %h.addr = alloca ptr
  store ptr %h.arg, ptr %h.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld207 = load ptr, ptr %h.addr
  %res_slot208 = alloca ptr
  %tgp209 = getelementptr i8, ptr %ld207, i64 8
  %tag210 = load i32, ptr %tgp209, align 4
  switch i32 %tag210, label %case_default47 [
      i32 0, label %case_br48
  ]
case_br48:
  %ld211 = load ptr, ptr %h.addr
  call void @march_decrc(ptr %ld211)
  %ld212 = load ptr, ptr %acc.addr
  %cr213 = call ptr @reverse_list(ptr %ld212)
  store ptr %cr213, ptr %res_slot208
  br label %case_merge46
case_default47:
  %ld214 = load ptr, ptr %h.addr
  call void @march_incrc(ptr %ld214)
  %ld215 = load ptr, ptr %h.addr
  %cr216 = call ptr @heap_pop(ptr %ld215)
  %$t1006.addr = alloca ptr
  store ptr %cr216, ptr %$t1006.addr
  %ld217 = load ptr, ptr %h.addr
  %cr218 = call i64 @heap_min(ptr %ld217)
  %$t1007.addr = alloca i64
  store i64 %cr218, ptr %$t1007.addr
  %hp219 = call ptr @march_alloc(i64 32)
  %tgp220 = getelementptr i8, ptr %hp219, i64 8
  store i32 1, ptr %tgp220, align 4
  %ld221 = load i64, ptr %$t1007.addr
  %cv222 = inttoptr i64 %ld221 to ptr
  %fp223 = getelementptr i8, ptr %hp219, i64 16
  store ptr %cv222, ptr %fp223, align 8
  %ld224 = load ptr, ptr %acc.addr
  %fp225 = getelementptr i8, ptr %hp219, i64 24
  store ptr %ld224, ptr %fp225, align 8
  %$t1008.addr = alloca ptr
  store ptr %hp219, ptr %$t1008.addr
  %ld226 = load ptr, ptr %$t1006.addr
  %ld227 = load ptr, ptr %$t1008.addr
  %cr228 = call ptr @drain_heap(ptr %ld226, ptr %ld227)
  store ptr %cr228, ptr %res_slot208
  br label %case_merge46
case_merge46:
  %case_r229 = load ptr, ptr %res_slot208
  ret ptr %case_r229
}

define ptr @reverse_list(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp230 = call ptr @march_alloc(i64 24)
  %tgp231 = getelementptr i8, ptr %hp230, i64 8
  store i32 0, ptr %tgp231, align 4
  %fp232 = getelementptr i8, ptr %hp230, i64 16
  store ptr @go$apply$18, ptr %fp232, align 8
  %go.addr = alloca ptr
  store ptr %hp230, ptr %go.addr
  %hp233 = call ptr @march_alloc(i64 16)
  %tgp234 = getelementptr i8, ptr %hp233, i64 8
  store i32 0, ptr %tgp234, align 4
  %$t1012.addr = alloca ptr
  store ptr %hp233, ptr %$t1012.addr
  %ld235 = load ptr, ptr %go.addr
  %fp236 = getelementptr i8, ptr %ld235, i64 16
  %fv237 = load ptr, ptr %fp236, align 8
  %ld238 = load ptr, ptr %xs.addr
  %ld239 = load ptr, ptr %$t1012.addr
  %cr240 = call ptr (ptr, ptr, ptr) %fv237(ptr %ld235, ptr %ld238, ptr %ld239)
  ret ptr %cr240
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld241 = load i64, ptr %n.addr
  %cmp242 = icmp eq i64 %ld241, 0
  %ar243 = zext i1 %cmp242 to i64
  %$t1015.addr = alloca i64
  store i64 %ar243, ptr %$t1015.addr
  %ld244 = load i64, ptr %$t1015.addr
  %res_slot245 = alloca ptr
  switch i64 %ld244, label %case_default50 [
      i64 1, label %case_br51
  ]
case_br51:
  %ld246 = load ptr, ptr %acc.addr
  store ptr %ld246, ptr %res_slot245
  br label %case_merge49
case_default50:
  %ld247 = load i64, ptr %seed.addr
  %ar248 = mul i64 %ld247, 1664525
  %$t1016.addr = alloca i64
  store i64 %ar248, ptr %$t1016.addr
  %ld249 = load i64, ptr %$t1016.addr
  %ar250 = add i64 %ld249, 1013904223
  %$t1017.addr = alloca i64
  store i64 %ar250, ptr %$t1017.addr
  %ld251 = load i64, ptr %$t1017.addr
  %ar252 = srem i64 %ld251, 1000000
  %next.addr = alloca i64
  store i64 %ar252, ptr %next.addr
  %ld253 = load i64, ptr %n.addr
  %ar254 = sub i64 %ld253, 1
  %$t1018.addr = alloca i64
  store i64 %ar254, ptr %$t1018.addr
  %ld255 = load i64, ptr %next.addr
  %ar256 = srem i64 %ld255, 100000
  %$t1019.addr = alloca i64
  store i64 %ar256, ptr %$t1019.addr
  %hp257 = call ptr @march_alloc(i64 32)
  %tgp258 = getelementptr i8, ptr %hp257, i64 8
  store i32 1, ptr %tgp258, align 4
  %ld259 = load i64, ptr %$t1019.addr
  %cv260 = inttoptr i64 %ld259 to ptr
  %fp261 = getelementptr i8, ptr %hp257, i64 16
  store ptr %cv260, ptr %fp261, align 8
  %ld262 = load ptr, ptr %acc.addr
  %fp263 = getelementptr i8, ptr %hp257, i64 24
  store ptr %ld262, ptr %fp263, align 8
  %$t1020.addr = alloca ptr
  store ptr %hp257, ptr %$t1020.addr
  %ld264 = load i64, ptr %$t1018.addr
  %ld265 = load i64, ptr %next.addr
  %ld266 = load ptr, ptr %$t1020.addr
  %cr267 = call ptr @gen_list(i64 %ld264, i64 %ld265, ptr %ld266)
  store ptr %cr267, ptr %res_slot245
  br label %case_merge49
case_merge49:
  %case_r268 = load ptr, ptr %res_slot245
  ret ptr %case_r268
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld269 = load ptr, ptr %xs.addr
  %res_slot270 = alloca ptr
  %tgp271 = getelementptr i8, ptr %ld269, i64 8
  %tag272 = load i32, ptr %tgp271, align 4
  switch i32 %tag272, label %case_default53 [
      i32 0, label %case_br54
      i32 1, label %case_br55
  ]
case_br54:
  %ld273 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld273)
  %cv274 = inttoptr i64 0 to ptr
  store ptr %cv274, ptr %res_slot270
  br label %case_merge52
case_br55:
  %fp275 = getelementptr i8, ptr %ld269, i64 16
  %fv276 = load ptr, ptr %fp275, align 8
  %$f1021.addr = alloca ptr
  store ptr %fv276, ptr %$f1021.addr
  %fp277 = getelementptr i8, ptr %ld269, i64 24
  %fv278 = load ptr, ptr %fp277, align 8
  %$f1022.addr = alloca ptr
  store ptr %fv278, ptr %$f1022.addr
  %freed279 = call i64 @march_decrc_freed(ptr %ld269)
  %freed_b280 = icmp ne i64 %freed279, 0
  br i1 %freed_b280, label %br_unique56, label %br_shared57
br_shared57:
  call void @march_incrc(ptr %fv278)
  br label %br_body58
br_unique56:
  br label %br_body58
br_body58:
  %ld281 = load ptr, ptr %$f1021.addr
  %h.addr = alloca ptr
  store ptr %ld281, ptr %h.addr
  %ld282 = load i64, ptr %h.addr
  %cv283 = inttoptr i64 %ld282 to ptr
  store ptr %cv283, ptr %res_slot270
  br label %case_merge52
case_default53:
  unreachable
case_merge52:
  %case_r284 = load ptr, ptr %res_slot270
  %cv285 = ptrtoint ptr %case_r284 to i64
  ret i64 %cv285
}

define void @march_main() {
entry:
  %hp286 = call ptr @march_alloc(i64 16)
  %tgp287 = getelementptr i8, ptr %hp286, i64 8
  store i32 0, ptr %tgp287, align 4
  %$t1023.addr = alloca ptr
  store ptr %hp286, ptr %$t1023.addr
  %ld288 = load ptr, ptr %$t1023.addr
  %cr289 = call ptr @gen_list(i64 10000, i64 42, ptr %ld288)
  %xs.addr = alloca ptr
  store ptr %cr289, ptr %xs.addr
  %ld290 = load ptr, ptr %xs.addr
  %xs_i6.addr = alloca ptr
  store ptr %ld290, ptr %xs_i6.addr
  %hp291 = call ptr @march_alloc(i64 16)
  %tgp292 = getelementptr i8, ptr %hp291, i64 8
  store i32 0, ptr %tgp292, align 4
  %$t1013_i7.addr = alloca ptr
  store ptr %hp291, ptr %$t1013_i7.addr
  %ld293 = load ptr, ptr %xs_i6.addr
  %ld294 = load ptr, ptr %$t1013_i7.addr
  %cr295 = call ptr @build_heap(ptr %ld293, ptr %ld294)
  %h_i8.addr = alloca ptr
  store ptr %cr295, ptr %h_i8.addr
  %hp296 = call ptr @march_alloc(i64 16)
  %tgp297 = getelementptr i8, ptr %hp296, i64 8
  store i32 0, ptr %tgp297, align 4
  %$t1014_i9.addr = alloca ptr
  store ptr %hp296, ptr %$t1014_i9.addr
  %ld298 = load ptr, ptr %h_i8.addr
  %ld299 = load ptr, ptr %$t1014_i9.addr
  %cr300 = call ptr @drain_heap(ptr %ld298, ptr %ld299)
  %sorted.addr = alloca ptr
  store ptr %cr300, ptr %sorted.addr
  %ld301 = load ptr, ptr %sorted.addr
  %cr302 = call i64 @head(ptr %ld301)
  %$t1024.addr = alloca i64
  store i64 %cr302, ptr %$t1024.addr
  %ld303 = load i64, ptr %$t1024.addr
  %cr304 = call ptr @march_int_to_string(i64 %ld303)
  %$t1025.addr = alloca ptr
  store ptr %cr304, ptr %$t1025.addr
  %ld305 = load ptr, ptr %$t1025.addr
  call void @march_println(ptr %ld305)
  ret void
}

define ptr @go$apply$18(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld306 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld306, ptr %go.addr
  %ld307 = load ptr, ptr %lst.addr
  %res_slot308 = alloca ptr
  %tgp309 = getelementptr i8, ptr %ld307, i64 8
  %tag310 = load i32, ptr %tgp309, align 4
  switch i32 %tag310, label %case_default60 [
      i32 0, label %case_br61
      i32 1, label %case_br62
  ]
case_br61:
  %ld311 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld311)
  %ld312 = load ptr, ptr %acc.addr
  store ptr %ld312, ptr %res_slot308
  br label %case_merge59
case_br62:
  %fp313 = getelementptr i8, ptr %ld307, i64 16
  %fv314 = load ptr, ptr %fp313, align 8
  %$f1010.addr = alloca ptr
  store ptr %fv314, ptr %$f1010.addr
  %fp315 = getelementptr i8, ptr %ld307, i64 24
  %fv316 = load ptr, ptr %fp315, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv316, ptr %$f1011.addr
  %ld317 = load ptr, ptr %$f1011.addr
  %t.addr = alloca ptr
  store ptr %ld317, ptr %t.addr
  %ld318 = load ptr, ptr %$f1010.addr
  %h.addr = alloca ptr
  store ptr %ld318, ptr %h.addr
  %ld319 = load ptr, ptr %lst.addr
  %ld320 = load i64, ptr %h.addr
  %cv321 = inttoptr i64 %ld320 to ptr
  %ld322 = load ptr, ptr %acc.addr
  %rc323 = load i64, ptr %ld319, align 8
  %uniq324 = icmp eq i64 %rc323, 1
  %fbip_slot325 = alloca ptr
  br i1 %uniq324, label %fbip_reuse63, label %fbip_fresh64
fbip_reuse63:
  %tgp326 = getelementptr i8, ptr %ld319, i64 8
  store i32 1, ptr %tgp326, align 4
  %fp327 = getelementptr i8, ptr %ld319, i64 16
  store ptr %cv321, ptr %fp327, align 8
  %fp328 = getelementptr i8, ptr %ld319, i64 24
  store ptr %ld322, ptr %fp328, align 8
  store ptr %ld319, ptr %fbip_slot325
  br label %fbip_merge65
fbip_fresh64:
  call void @march_decrc(ptr %ld319)
  %hp329 = call ptr @march_alloc(i64 32)
  %tgp330 = getelementptr i8, ptr %hp329, i64 8
  store i32 1, ptr %tgp330, align 4
  %fp331 = getelementptr i8, ptr %hp329, i64 16
  store ptr %cv321, ptr %fp331, align 8
  %fp332 = getelementptr i8, ptr %hp329, i64 24
  store ptr %ld322, ptr %fp332, align 8
  store ptr %hp329, ptr %fbip_slot325
  br label %fbip_merge65
fbip_merge65:
  %fbip_r333 = load ptr, ptr %fbip_slot325
  %$t1009.addr = alloca ptr
  store ptr %fbip_r333, ptr %$t1009.addr
  %ld334 = load ptr, ptr %go.addr
  %fp335 = getelementptr i8, ptr %ld334, i64 16
  %fv336 = load ptr, ptr %fp335, align 8
  %ld337 = load ptr, ptr %t.addr
  %ld338 = load ptr, ptr %$t1009.addr
  %cr339 = call ptr (ptr, ptr, ptr) %fv336(ptr %ld334, ptr %ld337, ptr %ld338)
  store ptr %cr339, ptr %res_slot308
  br label %case_merge59
case_default60:
  unreachable
case_merge59:
  %case_r340 = load ptr, ptr %res_slot308
  ret ptr %case_r340
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
