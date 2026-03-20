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


define ptr @reverse_list(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp1 = call ptr @march_alloc(i64 24)
  %tgp2 = getelementptr i8, ptr %hp1, i64 8
  store i32 0, ptr %tgp2, align 4
  %fp3 = getelementptr i8, ptr %hp1, i64 16
  store ptr @go$apply$18, ptr %fp3, align 8
  %go.addr = alloca ptr
  store ptr %hp1, ptr %go.addr
  %hp4 = call ptr @march_alloc(i64 16)
  %tgp5 = getelementptr i8, ptr %hp4, i64 8
  store i32 0, ptr %tgp5, align 4
  %$t973.addr = alloca ptr
  store ptr %hp4, ptr %$t973.addr
  %ld6 = load ptr, ptr %go.addr
  %fp7 = getelementptr i8, ptr %ld6, i64 16
  %fv8 = load ptr, ptr %fp7, align 8
  %ld9 = load ptr, ptr %xs.addr
  %ld10 = load ptr, ptr %$t973.addr
  %cr11 = call ptr (ptr, ptr, ptr) %fv8(ptr %ld6, ptr %ld9, ptr %ld10)
  ret ptr %cr11
}

define ptr @merge(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld12 = load ptr, ptr %xs.addr
  %res_slot13 = alloca ptr
  %tgp14 = getelementptr i8, ptr %ld12, i64 8
  %tag15 = load i32, ptr %tgp14, align 4
  switch i32 %tag15, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld16 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld16)
  %ld17 = load ptr, ptr %ys.addr
  store ptr %ld17, ptr %res_slot13
  br label %case_merge1
case_br4:
  %fp18 = getelementptr i8, ptr %ld12, i64 16
  %fv19 = load ptr, ptr %fp18, align 8
  %$f979.addr = alloca ptr
  store ptr %fv19, ptr %$f979.addr
  %fp20 = getelementptr i8, ptr %ld12, i64 24
  %fv21 = load ptr, ptr %fp20, align 8
  %$f980.addr = alloca ptr
  store ptr %fv21, ptr %$f980.addr
  %ld22 = load ptr, ptr %$f980.addr
  %xt.addr = alloca ptr
  store ptr %ld22, ptr %xt.addr
  %ld23 = load ptr, ptr %$f979.addr
  %x.addr = alloca ptr
  store ptr %ld23, ptr %x.addr
  %ld24 = load ptr, ptr %ys.addr
  %res_slot25 = alloca ptr
  %tgp26 = getelementptr i8, ptr %ld24, i64 8
  %tag27 = load i32, ptr %tgp26, align 4
  switch i32 %tag27, label %case_default6 [
      i32 0, label %case_br7
      i32 1, label %case_br8
  ]
case_br7:
  %ld28 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld28)
  %ld29 = load ptr, ptr %xs.addr
  store ptr %ld29, ptr %res_slot25
  br label %case_merge5
case_br8:
  %fp30 = getelementptr i8, ptr %ld24, i64 16
  %fv31 = load ptr, ptr %fp30, align 8
  %$f977.addr = alloca ptr
  store ptr %fv31, ptr %$f977.addr
  %fp32 = getelementptr i8, ptr %ld24, i64 24
  %fv33 = load ptr, ptr %fp32, align 8
  %$f978.addr = alloca ptr
  store ptr %fv33, ptr %$f978.addr
  %ld34 = load ptr, ptr %$f978.addr
  %yt.addr = alloca ptr
  store ptr %ld34, ptr %yt.addr
  %ld35 = load ptr, ptr %$f977.addr
  %y.addr = alloca ptr
  store ptr %ld35, ptr %y.addr
  %ld36 = load i64, ptr %x.addr
  %ld37 = load i64, ptr %y.addr
  %cmp38 = icmp sle i64 %ld36, %ld37
  %ar39 = zext i1 %cmp38 to i64
  %$t974.addr = alloca i64
  store i64 %ar39, ptr %$t974.addr
  %ld40 = load i64, ptr %$t974.addr
  %res_slot41 = alloca ptr
  switch i64 %ld40, label %case_default10 [
      i64 1, label %case_br11
  ]
case_br11:
  %ld42 = load ptr, ptr %xt.addr
  %ld43 = load ptr, ptr %ys.addr
  %cr44 = call ptr @merge(ptr %ld42, ptr %ld43)
  %$t975.addr = alloca ptr
  store ptr %cr44, ptr %$t975.addr
  %hp45 = call ptr @march_alloc(i64 32)
  %tgp46 = getelementptr i8, ptr %hp45, i64 8
  store i32 1, ptr %tgp46, align 4
  %ld47 = load i64, ptr %x.addr
  %cv48 = inttoptr i64 %ld47 to ptr
  %fp49 = getelementptr i8, ptr %hp45, i64 16
  store ptr %cv48, ptr %fp49, align 8
  %ld50 = load ptr, ptr %$t975.addr
  %fp51 = getelementptr i8, ptr %hp45, i64 24
  store ptr %ld50, ptr %fp51, align 8
  store ptr %hp45, ptr %res_slot41
  br label %case_merge9
case_default10:
  %ld52 = load ptr, ptr %xs.addr
  %ld53 = load ptr, ptr %yt.addr
  %cr54 = call ptr @merge(ptr %ld52, ptr %ld53)
  %$t976.addr = alloca ptr
  store ptr %cr54, ptr %$t976.addr
  %hp55 = call ptr @march_alloc(i64 32)
  %tgp56 = getelementptr i8, ptr %hp55, i64 8
  store i32 1, ptr %tgp56, align 4
  %ld57 = load i64, ptr %y.addr
  %cv58 = inttoptr i64 %ld57 to ptr
  %fp59 = getelementptr i8, ptr %hp55, i64 16
  store ptr %cv58, ptr %fp59, align 8
  %ld60 = load ptr, ptr %$t976.addr
  %fp61 = getelementptr i8, ptr %hp55, i64 24
  store ptr %ld60, ptr %fp61, align 8
  store ptr %hp55, ptr %res_slot41
  br label %case_merge9
case_merge9:
  %case_r62 = load ptr, ptr %res_slot41
  store ptr %case_r62, ptr %res_slot25
  br label %case_merge5
case_default6:
  unreachable
case_merge5:
  %case_r63 = load ptr, ptr %res_slot25
  store ptr %case_r63, ptr %res_slot13
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r64 = load ptr, ptr %res_slot13
  ret ptr %case_r64
}

define ptr @sort4(i64 %a.arg, i64 %b.arg, i64 %c.arg, i64 %d.arg) {
entry:
  %a.addr = alloca i64
  store i64 %a.arg, ptr %a.addr
  %b.addr = alloca i64
  store i64 %b.arg, ptr %b.addr
  %c.addr = alloca i64
  store i64 %c.arg, ptr %c.addr
  %d.addr = alloca i64
  store i64 %d.arg, ptr %d.addr
  %ld65 = load i64, ptr %a.addr
  %a_i16.addr = alloca i64
  store i64 %ld65, ptr %a_i16.addr
  %ld66 = load i64, ptr %b.addr
  %b_i17.addr = alloca i64
  store i64 %ld66, ptr %b_i17.addr
  %ld67 = load i64, ptr %a_i16.addr
  %ld68 = load i64, ptr %b_i17.addr
  %cmp69 = icmp sle i64 %ld67, %ld68
  %ar70 = zext i1 %cmp69 to i64
  %$t981_i18.addr = alloca i64
  store i64 %ar70, ptr %$t981_i18.addr
  %ld71 = load i64, ptr %$t981_i18.addr
  %res_slot72 = alloca ptr
  switch i64 %ld71, label %case_default13 [
      i64 1, label %case_br14
  ]
case_br14:
  %hp73 = call ptr @march_alloc(i64 32)
  %tgp74 = getelementptr i8, ptr %hp73, i64 8
  store i32 0, ptr %tgp74, align 4
  %ld75 = load i64, ptr %a_i16.addr
  %fp76 = getelementptr i8, ptr %hp73, i64 16
  store i64 %ld75, ptr %fp76, align 8
  %ld77 = load i64, ptr %b_i17.addr
  %fp78 = getelementptr i8, ptr %hp73, i64 24
  store i64 %ld77, ptr %fp78, align 8
  store ptr %hp73, ptr %res_slot72
  br label %case_merge12
case_default13:
  %hp79 = call ptr @march_alloc(i64 32)
  %tgp80 = getelementptr i8, ptr %hp79, i64 8
  store i32 0, ptr %tgp80, align 4
  %ld81 = load i64, ptr %b_i17.addr
  %fp82 = getelementptr i8, ptr %hp79, i64 16
  store i64 %ld81, ptr %fp82, align 8
  %ld83 = load i64, ptr %a_i16.addr
  %fp84 = getelementptr i8, ptr %hp79, i64 24
  store i64 %ld83, ptr %fp84, align 8
  store ptr %hp79, ptr %res_slot72
  br label %case_merge12
case_merge12:
  %case_r85 = load ptr, ptr %res_slot72
  %$p990.addr = alloca ptr
  store ptr %case_r85, ptr %$p990.addr
  %ld86 = load ptr, ptr %$p990.addr
  %fp87 = getelementptr i8, ptr %ld86, i64 16
  %fv88 = load ptr, ptr %fp87, align 8
  %a1.addr = alloca ptr
  store ptr %fv88, ptr %a1.addr
  %ld89 = load ptr, ptr %$p990.addr
  %fp90 = getelementptr i8, ptr %ld89, i64 24
  %fv91 = load ptr, ptr %fp90, align 8
  %b1.addr = alloca ptr
  store ptr %fv91, ptr %b1.addr
  %ld92 = load i64, ptr %c.addr
  %a_i13.addr = alloca i64
  store i64 %ld92, ptr %a_i13.addr
  %ld93 = load i64, ptr %d.addr
  %b_i14.addr = alloca i64
  store i64 %ld93, ptr %b_i14.addr
  %ld94 = load i64, ptr %a_i13.addr
  %ld95 = load i64, ptr %b_i14.addr
  %cmp96 = icmp sle i64 %ld94, %ld95
  %ar97 = zext i1 %cmp96 to i64
  %$t981_i15.addr = alloca i64
  store i64 %ar97, ptr %$t981_i15.addr
  %ld98 = load i64, ptr %$t981_i15.addr
  %res_slot99 = alloca ptr
  switch i64 %ld98, label %case_default16 [
      i64 1, label %case_br17
  ]
case_br17:
  %hp100 = call ptr @march_alloc(i64 32)
  %tgp101 = getelementptr i8, ptr %hp100, i64 8
  store i32 0, ptr %tgp101, align 4
  %ld102 = load i64, ptr %a_i13.addr
  %fp103 = getelementptr i8, ptr %hp100, i64 16
  store i64 %ld102, ptr %fp103, align 8
  %ld104 = load i64, ptr %b_i14.addr
  %fp105 = getelementptr i8, ptr %hp100, i64 24
  store i64 %ld104, ptr %fp105, align 8
  store ptr %hp100, ptr %res_slot99
  br label %case_merge15
case_default16:
  %hp106 = call ptr @march_alloc(i64 32)
  %tgp107 = getelementptr i8, ptr %hp106, i64 8
  store i32 0, ptr %tgp107, align 4
  %ld108 = load i64, ptr %b_i14.addr
  %fp109 = getelementptr i8, ptr %hp106, i64 16
  store i64 %ld108, ptr %fp109, align 8
  %ld110 = load i64, ptr %a_i13.addr
  %fp111 = getelementptr i8, ptr %hp106, i64 24
  store i64 %ld110, ptr %fp111, align 8
  store ptr %hp106, ptr %res_slot99
  br label %case_merge15
case_merge15:
  %case_r112 = load ptr, ptr %res_slot99
  %$p989.addr = alloca ptr
  store ptr %case_r112, ptr %$p989.addr
  %ld113 = load ptr, ptr %$p989.addr
  %fp114 = getelementptr i8, ptr %ld113, i64 16
  %fv115 = load ptr, ptr %fp114, align 8
  %c1.addr = alloca ptr
  store ptr %fv115, ptr %c1.addr
  %ld116 = load ptr, ptr %$p989.addr
  %fp117 = getelementptr i8, ptr %ld116, i64 24
  %fv118 = load ptr, ptr %fp117, align 8
  %d1.addr = alloca ptr
  store ptr %fv118, ptr %d1.addr
  %ld119 = load i64, ptr %a1.addr
  %a_i10.addr = alloca i64
  store i64 %ld119, ptr %a_i10.addr
  %ld120 = load i64, ptr %c1.addr
  %b_i11.addr = alloca i64
  store i64 %ld120, ptr %b_i11.addr
  %ld121 = load i64, ptr %a_i10.addr
  %ld122 = load i64, ptr %b_i11.addr
  %cmp123 = icmp sle i64 %ld121, %ld122
  %ar124 = zext i1 %cmp123 to i64
  %$t981_i12.addr = alloca i64
  store i64 %ar124, ptr %$t981_i12.addr
  %ld125 = load i64, ptr %$t981_i12.addr
  %res_slot126 = alloca ptr
  switch i64 %ld125, label %case_default19 [
      i64 1, label %case_br20
  ]
case_br20:
  %hp127 = call ptr @march_alloc(i64 32)
  %tgp128 = getelementptr i8, ptr %hp127, i64 8
  store i32 0, ptr %tgp128, align 4
  %ld129 = load i64, ptr %a_i10.addr
  %fp130 = getelementptr i8, ptr %hp127, i64 16
  store i64 %ld129, ptr %fp130, align 8
  %ld131 = load i64, ptr %b_i11.addr
  %fp132 = getelementptr i8, ptr %hp127, i64 24
  store i64 %ld131, ptr %fp132, align 8
  store ptr %hp127, ptr %res_slot126
  br label %case_merge18
case_default19:
  %hp133 = call ptr @march_alloc(i64 32)
  %tgp134 = getelementptr i8, ptr %hp133, i64 8
  store i32 0, ptr %tgp134, align 4
  %ld135 = load i64, ptr %b_i11.addr
  %fp136 = getelementptr i8, ptr %hp133, i64 16
  store i64 %ld135, ptr %fp136, align 8
  %ld137 = load i64, ptr %a_i10.addr
  %fp138 = getelementptr i8, ptr %hp133, i64 24
  store i64 %ld137, ptr %fp138, align 8
  store ptr %hp133, ptr %res_slot126
  br label %case_merge18
case_merge18:
  %case_r139 = load ptr, ptr %res_slot126
  %$p988.addr = alloca ptr
  store ptr %case_r139, ptr %$p988.addr
  %ld140 = load ptr, ptr %$p988.addr
  %fp141 = getelementptr i8, ptr %ld140, i64 16
  %fv142 = load ptr, ptr %fp141, align 8
  %a2.addr = alloca ptr
  store ptr %fv142, ptr %a2.addr
  %ld143 = load ptr, ptr %$p988.addr
  %fp144 = getelementptr i8, ptr %ld143, i64 24
  %fv145 = load ptr, ptr %fp144, align 8
  %c2.addr = alloca ptr
  store ptr %fv145, ptr %c2.addr
  %ld146 = load i64, ptr %b1.addr
  %a_i7.addr = alloca i64
  store i64 %ld146, ptr %a_i7.addr
  %ld147 = load i64, ptr %d1.addr
  %b_i8.addr = alloca i64
  store i64 %ld147, ptr %b_i8.addr
  %ld148 = load i64, ptr %a_i7.addr
  %ld149 = load i64, ptr %b_i8.addr
  %cmp150 = icmp sle i64 %ld148, %ld149
  %ar151 = zext i1 %cmp150 to i64
  %$t981_i9.addr = alloca i64
  store i64 %ar151, ptr %$t981_i9.addr
  %ld152 = load i64, ptr %$t981_i9.addr
  %res_slot153 = alloca ptr
  switch i64 %ld152, label %case_default22 [
      i64 1, label %case_br23
  ]
case_br23:
  %hp154 = call ptr @march_alloc(i64 32)
  %tgp155 = getelementptr i8, ptr %hp154, i64 8
  store i32 0, ptr %tgp155, align 4
  %ld156 = load i64, ptr %a_i7.addr
  %fp157 = getelementptr i8, ptr %hp154, i64 16
  store i64 %ld156, ptr %fp157, align 8
  %ld158 = load i64, ptr %b_i8.addr
  %fp159 = getelementptr i8, ptr %hp154, i64 24
  store i64 %ld158, ptr %fp159, align 8
  store ptr %hp154, ptr %res_slot153
  br label %case_merge21
case_default22:
  %hp160 = call ptr @march_alloc(i64 32)
  %tgp161 = getelementptr i8, ptr %hp160, i64 8
  store i32 0, ptr %tgp161, align 4
  %ld162 = load i64, ptr %b_i8.addr
  %fp163 = getelementptr i8, ptr %hp160, i64 16
  store i64 %ld162, ptr %fp163, align 8
  %ld164 = load i64, ptr %a_i7.addr
  %fp165 = getelementptr i8, ptr %hp160, i64 24
  store i64 %ld164, ptr %fp165, align 8
  store ptr %hp160, ptr %res_slot153
  br label %case_merge21
case_merge21:
  %case_r166 = load ptr, ptr %res_slot153
  %$p987.addr = alloca ptr
  store ptr %case_r166, ptr %$p987.addr
  %ld167 = load ptr, ptr %$p987.addr
  %fp168 = getelementptr i8, ptr %ld167, i64 16
  %fv169 = load ptr, ptr %fp168, align 8
  %b2.addr = alloca ptr
  store ptr %fv169, ptr %b2.addr
  %ld170 = load ptr, ptr %$p987.addr
  %fp171 = getelementptr i8, ptr %ld170, i64 24
  %fv172 = load ptr, ptr %fp171, align 8
  %d2.addr = alloca ptr
  store ptr %fv172, ptr %d2.addr
  %ld173 = load i64, ptr %b2.addr
  %a_i4.addr = alloca i64
  store i64 %ld173, ptr %a_i4.addr
  %ld174 = load i64, ptr %c2.addr
  %b_i5.addr = alloca i64
  store i64 %ld174, ptr %b_i5.addr
  %ld175 = load i64, ptr %a_i4.addr
  %ld176 = load i64, ptr %b_i5.addr
  %cmp177 = icmp sle i64 %ld175, %ld176
  %ar178 = zext i1 %cmp177 to i64
  %$t981_i6.addr = alloca i64
  store i64 %ar178, ptr %$t981_i6.addr
  %ld179 = load i64, ptr %$t981_i6.addr
  %res_slot180 = alloca ptr
  switch i64 %ld179, label %case_default25 [
      i64 1, label %case_br26
  ]
case_br26:
  %hp181 = call ptr @march_alloc(i64 32)
  %tgp182 = getelementptr i8, ptr %hp181, i64 8
  store i32 0, ptr %tgp182, align 4
  %ld183 = load i64, ptr %a_i4.addr
  %fp184 = getelementptr i8, ptr %hp181, i64 16
  store i64 %ld183, ptr %fp184, align 8
  %ld185 = load i64, ptr %b_i5.addr
  %fp186 = getelementptr i8, ptr %hp181, i64 24
  store i64 %ld185, ptr %fp186, align 8
  store ptr %hp181, ptr %res_slot180
  br label %case_merge24
case_default25:
  %hp187 = call ptr @march_alloc(i64 32)
  %tgp188 = getelementptr i8, ptr %hp187, i64 8
  store i32 0, ptr %tgp188, align 4
  %ld189 = load i64, ptr %b_i5.addr
  %fp190 = getelementptr i8, ptr %hp187, i64 16
  store i64 %ld189, ptr %fp190, align 8
  %ld191 = load i64, ptr %a_i4.addr
  %fp192 = getelementptr i8, ptr %hp187, i64 24
  store i64 %ld191, ptr %fp192, align 8
  store ptr %hp187, ptr %res_slot180
  br label %case_merge24
case_merge24:
  %case_r193 = load ptr, ptr %res_slot180
  %$p986.addr = alloca ptr
  store ptr %case_r193, ptr %$p986.addr
  %ld194 = load ptr, ptr %$p986.addr
  %fp195 = getelementptr i8, ptr %ld194, i64 16
  %fv196 = load ptr, ptr %fp195, align 8
  %b3.addr = alloca ptr
  store ptr %fv196, ptr %b3.addr
  %ld197 = load ptr, ptr %$p986.addr
  %fp198 = getelementptr i8, ptr %ld197, i64 24
  %fv199 = load ptr, ptr %fp198, align 8
  %c3.addr = alloca ptr
  store ptr %fv199, ptr %c3.addr
  %hp200 = call ptr @march_alloc(i64 16)
  %tgp201 = getelementptr i8, ptr %hp200, i64 8
  store i32 0, ptr %tgp201, align 4
  %$t982.addr = alloca ptr
  store ptr %hp200, ptr %$t982.addr
  %hp202 = call ptr @march_alloc(i64 32)
  %tgp203 = getelementptr i8, ptr %hp202, i64 8
  store i32 1, ptr %tgp203, align 4
  %ld204 = load i64, ptr %d2.addr
  %cv205 = inttoptr i64 %ld204 to ptr
  %fp206 = getelementptr i8, ptr %hp202, i64 16
  store ptr %cv205, ptr %fp206, align 8
  %ld207 = load ptr, ptr %$t982.addr
  %fp208 = getelementptr i8, ptr %hp202, i64 24
  store ptr %ld207, ptr %fp208, align 8
  %$t983.addr = alloca ptr
  store ptr %hp202, ptr %$t983.addr
  %hp209 = call ptr @march_alloc(i64 32)
  %tgp210 = getelementptr i8, ptr %hp209, i64 8
  store i32 1, ptr %tgp210, align 4
  %ld211 = load i64, ptr %c3.addr
  %cv212 = inttoptr i64 %ld211 to ptr
  %fp213 = getelementptr i8, ptr %hp209, i64 16
  store ptr %cv212, ptr %fp213, align 8
  %ld214 = load ptr, ptr %$t983.addr
  %fp215 = getelementptr i8, ptr %hp209, i64 24
  store ptr %ld214, ptr %fp215, align 8
  %$t984.addr = alloca ptr
  store ptr %hp209, ptr %$t984.addr
  %hp216 = call ptr @march_alloc(i64 32)
  %tgp217 = getelementptr i8, ptr %hp216, i64 8
  store i32 1, ptr %tgp217, align 4
  %ld218 = load i64, ptr %b3.addr
  %cv219 = inttoptr i64 %ld218 to ptr
  %fp220 = getelementptr i8, ptr %hp216, i64 16
  store ptr %cv219, ptr %fp220, align 8
  %ld221 = load ptr, ptr %$t984.addr
  %fp222 = getelementptr i8, ptr %hp216, i64 24
  store ptr %ld221, ptr %fp222, align 8
  %$t985.addr = alloca ptr
  store ptr %hp216, ptr %$t985.addr
  %hp223 = call ptr @march_alloc(i64 32)
  %tgp224 = getelementptr i8, ptr %hp223, i64 8
  store i32 1, ptr %tgp224, align 4
  %ld225 = load i64, ptr %a2.addr
  %cv226 = inttoptr i64 %ld225 to ptr
  %fp227 = getelementptr i8, ptr %hp223, i64 16
  store ptr %cv226, ptr %fp227, align 8
  %ld228 = load ptr, ptr %$t985.addr
  %fp229 = getelementptr i8, ptr %hp223, i64 24
  store ptr %ld228, ptr %fp229, align 8
  ret ptr %hp223
}

define ptr @sort_group8(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld230 = load ptr, ptr %xs.addr
  %res_slot231 = alloca ptr
  %tgp232 = getelementptr i8, ptr %ld230, i64 8
  %tag233 = load i32, ptr %tgp232, align 4
  switch i32 %tag233, label %case_default28 [
      i32 1, label %case_br29
  ]
case_br29:
  %fp234 = getelementptr i8, ptr %ld230, i64 16
  %fv235 = load ptr, ptr %fp234, align 8
  %$f991.addr = alloca ptr
  store ptr %fv235, ptr %$f991.addr
  %fp236 = getelementptr i8, ptr %ld230, i64 24
  %fv237 = load ptr, ptr %fp236, align 8
  %$f992.addr = alloca ptr
  store ptr %fv237, ptr %$f992.addr
  %ld238 = load ptr, ptr %$f992.addr
  %res_slot239 = alloca ptr
  %tgp240 = getelementptr i8, ptr %ld238, i64 8
  %tag241 = load i32, ptr %tgp240, align 4
  switch i32 %tag241, label %case_default31 [
      i32 1, label %case_br32
  ]
case_br32:
  %fp242 = getelementptr i8, ptr %ld238, i64 16
  %fv243 = load ptr, ptr %fp242, align 8
  %$f993.addr = alloca ptr
  store ptr %fv243, ptr %$f993.addr
  %fp244 = getelementptr i8, ptr %ld238, i64 24
  %fv245 = load ptr, ptr %fp244, align 8
  %$f994.addr = alloca ptr
  store ptr %fv245, ptr %$f994.addr
  %ld246 = load ptr, ptr %$f994.addr
  %res_slot247 = alloca ptr
  %tgp248 = getelementptr i8, ptr %ld246, i64 8
  %tag249 = load i32, ptr %tgp248, align 4
  switch i32 %tag249, label %case_default34 [
      i32 1, label %case_br35
  ]
case_br35:
  %fp250 = getelementptr i8, ptr %ld246, i64 16
  %fv251 = load ptr, ptr %fp250, align 8
  %$f995.addr = alloca ptr
  store ptr %fv251, ptr %$f995.addr
  %fp252 = getelementptr i8, ptr %ld246, i64 24
  %fv253 = load ptr, ptr %fp252, align 8
  %$f996.addr = alloca ptr
  store ptr %fv253, ptr %$f996.addr
  %ld254 = load ptr, ptr %$f996.addr
  %res_slot255 = alloca ptr
  %tgp256 = getelementptr i8, ptr %ld254, i64 8
  %tag257 = load i32, ptr %tgp256, align 4
  switch i32 %tag257, label %case_default37 [
      i32 1, label %case_br38
  ]
case_br38:
  %fp258 = getelementptr i8, ptr %ld254, i64 16
  %fv259 = load ptr, ptr %fp258, align 8
  %$f997.addr = alloca ptr
  store ptr %fv259, ptr %$f997.addr
  %fp260 = getelementptr i8, ptr %ld254, i64 24
  %fv261 = load ptr, ptr %fp260, align 8
  %$f998.addr = alloca ptr
  store ptr %fv261, ptr %$f998.addr
  %ld262 = load ptr, ptr %$f998.addr
  %res_slot263 = alloca ptr
  %tgp264 = getelementptr i8, ptr %ld262, i64 8
  %tag265 = load i32, ptr %tgp264, align 4
  switch i32 %tag265, label %case_default40 [
      i32 1, label %case_br41
  ]
case_br41:
  %fp266 = getelementptr i8, ptr %ld262, i64 16
  %fv267 = load ptr, ptr %fp266, align 8
  %$f999.addr = alloca ptr
  store ptr %fv267, ptr %$f999.addr
  %fp268 = getelementptr i8, ptr %ld262, i64 24
  %fv269 = load ptr, ptr %fp268, align 8
  %$f1000.addr = alloca ptr
  store ptr %fv269, ptr %$f1000.addr
  %ld270 = load ptr, ptr %$f1000.addr
  %res_slot271 = alloca ptr
  %tgp272 = getelementptr i8, ptr %ld270, i64 8
  %tag273 = load i32, ptr %tgp272, align 4
  switch i32 %tag273, label %case_default43 [
      i32 1, label %case_br44
  ]
case_br44:
  %fp274 = getelementptr i8, ptr %ld270, i64 16
  %fv275 = load ptr, ptr %fp274, align 8
  %$f1001.addr = alloca ptr
  store ptr %fv275, ptr %$f1001.addr
  %fp276 = getelementptr i8, ptr %ld270, i64 24
  %fv277 = load ptr, ptr %fp276, align 8
  %$f1002.addr = alloca ptr
  store ptr %fv277, ptr %$f1002.addr
  %ld278 = load ptr, ptr %$f1002.addr
  %res_slot279 = alloca ptr
  %tgp280 = getelementptr i8, ptr %ld278, i64 8
  %tag281 = load i32, ptr %tgp280, align 4
  switch i32 %tag281, label %case_default46 [
      i32 1, label %case_br47
  ]
case_br47:
  %fp282 = getelementptr i8, ptr %ld278, i64 16
  %fv283 = load ptr, ptr %fp282, align 8
  %$f1003.addr = alloca ptr
  store ptr %fv283, ptr %$f1003.addr
  %fp284 = getelementptr i8, ptr %ld278, i64 24
  %fv285 = load ptr, ptr %fp284, align 8
  %$f1004.addr = alloca ptr
  store ptr %fv285, ptr %$f1004.addr
  %ld286 = load ptr, ptr %$f1004.addr
  %res_slot287 = alloca ptr
  %tgp288 = getelementptr i8, ptr %ld286, i64 8
  %tag289 = load i32, ptr %tgp288, align 4
  switch i32 %tag289, label %case_default49 [
      i32 1, label %case_br50
  ]
case_br50:
  %fp290 = getelementptr i8, ptr %ld286, i64 16
  %fv291 = load ptr, ptr %fp290, align 8
  %$f1005.addr = alloca ptr
  store ptr %fv291, ptr %$f1005.addr
  %fp292 = getelementptr i8, ptr %ld286, i64 24
  %fv293 = load ptr, ptr %fp292, align 8
  %$f1006.addr = alloca ptr
  store ptr %fv293, ptr %$f1006.addr
  %ld294 = load ptr, ptr %$f1005.addr
  %h.addr = alloca ptr
  store ptr %ld294, ptr %h.addr
  %ld295 = load ptr, ptr %$f1003.addr
  %g.addr = alloca ptr
  store ptr %ld295, ptr %g.addr
  %ld296 = load ptr, ptr %$f1001.addr
  %f.addr = alloca ptr
  store ptr %ld296, ptr %f.addr
  %ld297 = load ptr, ptr %$f999.addr
  %e.addr = alloca ptr
  store ptr %ld297, ptr %e.addr
  %ld298 = load ptr, ptr %$f997.addr
  %d.addr = alloca ptr
  store ptr %ld298, ptr %d.addr
  %ld299 = load ptr, ptr %$f995.addr
  %c.addr = alloca ptr
  store ptr %ld299, ptr %c.addr
  %ld300 = load ptr, ptr %$f993.addr
  %b.addr = alloca ptr
  store ptr %ld300, ptr %b.addr
  %ld301 = load ptr, ptr %$f991.addr
  %a.addr = alloca ptr
  store ptr %ld301, ptr %a.addr
  %ld302 = load i64, ptr %a.addr
  %a_i19.addr = alloca i64
  store i64 %ld302, ptr %a_i19.addr
  %ld303 = load i64, ptr %b.addr
  %b_i20.addr = alloca i64
  store i64 %ld303, ptr %b_i20.addr
  %ld304 = load i64, ptr %c.addr
  %c_i21.addr = alloca i64
  store i64 %ld304, ptr %c_i21.addr
  %ld305 = load i64, ptr %d.addr
  %d_i22.addr = alloca i64
  store i64 %ld305, ptr %d_i22.addr
  %ld306 = load i64, ptr %e.addr
  %e_i23.addr = alloca i64
  store i64 %ld306, ptr %e_i23.addr
  %ld307 = load i64, ptr %f.addr
  %f_i24.addr = alloca i64
  store i64 %ld307, ptr %f_i24.addr
  %ld308 = load i64, ptr %g.addr
  %g_i25.addr = alloca i64
  store i64 %ld308, ptr %g_i25.addr
  %ld309 = load i64, ptr %h.addr
  %h_i26.addr = alloca i64
  store i64 %ld309, ptr %h_i26.addr
  %ld310 = load i64, ptr %a_i19.addr
  %ld311 = load i64, ptr %b_i20.addr
  %ld312 = load i64, ptr %c_i21.addr
  %ld313 = load i64, ptr %d_i22.addr
  %cr314 = call ptr @sort4(i64 %ld310, i64 %ld311, i64 %ld312, i64 %ld313)
  %left_i27.addr = alloca ptr
  store ptr %cr314, ptr %left_i27.addr
  %ld315 = load i64, ptr %e_i23.addr
  %ld316 = load i64, ptr %f_i24.addr
  %ld317 = load i64, ptr %g_i25.addr
  %ld318 = load i64, ptr %h_i26.addr
  %cr319 = call ptr @sort4(i64 %ld315, i64 %ld316, i64 %ld317, i64 %ld318)
  %right_i28.addr = alloca ptr
  store ptr %cr319, ptr %right_i28.addr
  %ld320 = load ptr, ptr %left_i27.addr
  %ld321 = load ptr, ptr %right_i28.addr
  %cr322 = call ptr @merge(ptr %ld320, ptr %ld321)
  store ptr %cr322, ptr %res_slot287
  br label %case_merge48
case_default49:
  %ld323 = load ptr, ptr %xs.addr
  store ptr %ld323, ptr %res_slot287
  br label %case_merge48
case_merge48:
  %case_r324 = load ptr, ptr %res_slot287
  store ptr %case_r324, ptr %res_slot279
  br label %case_merge45
case_default46:
  %ld325 = load ptr, ptr %xs.addr
  store ptr %ld325, ptr %res_slot279
  br label %case_merge45
case_merge45:
  %case_r326 = load ptr, ptr %res_slot279
  store ptr %case_r326, ptr %res_slot271
  br label %case_merge42
case_default43:
  %ld327 = load ptr, ptr %xs.addr
  store ptr %ld327, ptr %res_slot271
  br label %case_merge42
case_merge42:
  %case_r328 = load ptr, ptr %res_slot271
  store ptr %case_r328, ptr %res_slot263
  br label %case_merge39
case_default40:
  %ld329 = load ptr, ptr %xs.addr
  store ptr %ld329, ptr %res_slot263
  br label %case_merge39
case_merge39:
  %case_r330 = load ptr, ptr %res_slot263
  store ptr %case_r330, ptr %res_slot255
  br label %case_merge36
case_default37:
  %ld331 = load ptr, ptr %xs.addr
  store ptr %ld331, ptr %res_slot255
  br label %case_merge36
case_merge36:
  %case_r332 = load ptr, ptr %res_slot255
  store ptr %case_r332, ptr %res_slot247
  br label %case_merge33
case_default34:
  %ld333 = load ptr, ptr %xs.addr
  store ptr %ld333, ptr %res_slot247
  br label %case_merge33
case_merge33:
  %case_r334 = load ptr, ptr %res_slot247
  store ptr %case_r334, ptr %res_slot239
  br label %case_merge30
case_default31:
  %ld335 = load ptr, ptr %xs.addr
  store ptr %ld335, ptr %res_slot239
  br label %case_merge30
case_merge30:
  %case_r336 = load ptr, ptr %res_slot239
  store ptr %case_r336, ptr %res_slot231
  br label %case_merge27
case_default28:
  %ld337 = load ptr, ptr %xs.addr
  store ptr %ld337, ptr %res_slot231
  br label %case_merge27
case_merge27:
  %case_r338 = load ptr, ptr %res_slot231
  ret ptr %case_r338
}

define ptr @take8(ptr %lst.arg, ptr %acc.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld339 = load ptr, ptr %lst.addr
  %res_slot340 = alloca ptr
  %tgp341 = getelementptr i8, ptr %ld339, i64 8
  %tag342 = load i32, ptr %tgp341, align 4
  switch i32 %tag342, label %case_default52 [
      i32 0, label %case_br53
      i32 1, label %case_br54
  ]
case_br53:
  %ld343 = load ptr, ptr %acc.addr
  %cr344 = call ptr @reverse_list(ptr %ld343)
  %$t1007.addr = alloca ptr
  store ptr %cr344, ptr %$t1007.addr
  %ld345 = load ptr, ptr %lst.addr
  %rc346 = load i64, ptr %ld345, align 8
  %uniq347 = icmp eq i64 %rc346, 1
  %fbip_slot348 = alloca ptr
  br i1 %uniq347, label %fbip_reuse55, label %fbip_fresh56
fbip_reuse55:
  %tgp349 = getelementptr i8, ptr %ld345, i64 8
  store i32 0, ptr %tgp349, align 4
  store ptr %ld345, ptr %fbip_slot348
  br label %fbip_merge57
fbip_fresh56:
  call void @march_decrc(ptr %ld345)
  %hp350 = call ptr @march_alloc(i64 16)
  %tgp351 = getelementptr i8, ptr %hp350, i64 8
  store i32 0, ptr %tgp351, align 4
  store ptr %hp350, ptr %fbip_slot348
  br label %fbip_merge57
fbip_merge57:
  %fbip_r352 = load ptr, ptr %fbip_slot348
  %$t1008.addr = alloca ptr
  store ptr %fbip_r352, ptr %$t1008.addr
  %hp353 = call ptr @march_alloc(i64 32)
  %tgp354 = getelementptr i8, ptr %hp353, i64 8
  store i32 0, ptr %tgp354, align 4
  %ld355 = load ptr, ptr %$t1007.addr
  %fp356 = getelementptr i8, ptr %hp353, i64 16
  store ptr %ld355, ptr %fp356, align 8
  %ld357 = load ptr, ptr %$t1008.addr
  %fp358 = getelementptr i8, ptr %hp353, i64 24
  store ptr %ld357, ptr %fp358, align 8
  store ptr %hp353, ptr %res_slot340
  br label %case_merge51
case_br54:
  %fp359 = getelementptr i8, ptr %ld339, i64 16
  %fv360 = load ptr, ptr %fp359, align 8
  %$f1019.addr = alloca ptr
  store ptr %fv360, ptr %$f1019.addr
  %fp361 = getelementptr i8, ptr %ld339, i64 24
  %fv362 = load ptr, ptr %fp361, align 8
  %$f1020.addr = alloca ptr
  store ptr %fv362, ptr %$f1020.addr
  %ld363 = load ptr, ptr %$f1020.addr
  %res_slot364 = alloca ptr
  %tgp365 = getelementptr i8, ptr %ld363, i64 8
  %tag366 = load i32, ptr %tgp365, align 4
  switch i32 %tag366, label %case_default59 [
      i32 1, label %case_br60
  ]
case_br60:
  %fp367 = getelementptr i8, ptr %ld363, i64 16
  %fv368 = load ptr, ptr %fp367, align 8
  %$f1021.addr = alloca ptr
  store ptr %fv368, ptr %$f1021.addr
  %fp369 = getelementptr i8, ptr %ld363, i64 24
  %fv370 = load ptr, ptr %fp369, align 8
  %$f1022.addr = alloca ptr
  store ptr %fv370, ptr %$f1022.addr
  %ld371 = load ptr, ptr %$f1022.addr
  %res_slot372 = alloca ptr
  %tgp373 = getelementptr i8, ptr %ld371, i64 8
  %tag374 = load i32, ptr %tgp373, align 4
  switch i32 %tag374, label %case_default62 [
      i32 1, label %case_br63
  ]
case_br63:
  %fp375 = getelementptr i8, ptr %ld371, i64 16
  %fv376 = load ptr, ptr %fp375, align 8
  %$f1023.addr = alloca ptr
  store ptr %fv376, ptr %$f1023.addr
  %fp377 = getelementptr i8, ptr %ld371, i64 24
  %fv378 = load ptr, ptr %fp377, align 8
  %$f1024.addr = alloca ptr
  store ptr %fv378, ptr %$f1024.addr
  %ld379 = load ptr, ptr %$f1024.addr
  %res_slot380 = alloca ptr
  %tgp381 = getelementptr i8, ptr %ld379, i64 8
  %tag382 = load i32, ptr %tgp381, align 4
  switch i32 %tag382, label %case_default65 [
      i32 1, label %case_br66
  ]
case_br66:
  %fp383 = getelementptr i8, ptr %ld379, i64 16
  %fv384 = load ptr, ptr %fp383, align 8
  %$f1025.addr = alloca ptr
  store ptr %fv384, ptr %$f1025.addr
  %fp385 = getelementptr i8, ptr %ld379, i64 24
  %fv386 = load ptr, ptr %fp385, align 8
  %$f1026.addr = alloca ptr
  store ptr %fv386, ptr %$f1026.addr
  %ld387 = load ptr, ptr %$f1026.addr
  %res_slot388 = alloca ptr
  %tgp389 = getelementptr i8, ptr %ld387, i64 8
  %tag390 = load i32, ptr %tgp389, align 4
  switch i32 %tag390, label %case_default68 [
      i32 1, label %case_br69
  ]
case_br69:
  %fp391 = getelementptr i8, ptr %ld387, i64 16
  %fv392 = load ptr, ptr %fp391, align 8
  %$f1027.addr = alloca ptr
  store ptr %fv392, ptr %$f1027.addr
  %fp393 = getelementptr i8, ptr %ld387, i64 24
  %fv394 = load ptr, ptr %fp393, align 8
  %$f1028.addr = alloca ptr
  store ptr %fv394, ptr %$f1028.addr
  %ld395 = load ptr, ptr %$f1028.addr
  %res_slot396 = alloca ptr
  %tgp397 = getelementptr i8, ptr %ld395, i64 8
  %tag398 = load i32, ptr %tgp397, align 4
  switch i32 %tag398, label %case_default71 [
      i32 1, label %case_br72
  ]
case_br72:
  %fp399 = getelementptr i8, ptr %ld395, i64 16
  %fv400 = load ptr, ptr %fp399, align 8
  %$f1029.addr = alloca ptr
  store ptr %fv400, ptr %$f1029.addr
  %fp401 = getelementptr i8, ptr %ld395, i64 24
  %fv402 = load ptr, ptr %fp401, align 8
  %$f1030.addr = alloca ptr
  store ptr %fv402, ptr %$f1030.addr
  %ld403 = load ptr, ptr %$f1030.addr
  %res_slot404 = alloca ptr
  %tgp405 = getelementptr i8, ptr %ld403, i64 8
  %tag406 = load i32, ptr %tgp405, align 4
  switch i32 %tag406, label %case_default74 [
      i32 1, label %case_br75
  ]
case_br75:
  %fp407 = getelementptr i8, ptr %ld403, i64 16
  %fv408 = load ptr, ptr %fp407, align 8
  %$f1031.addr = alloca ptr
  store ptr %fv408, ptr %$f1031.addr
  %fp409 = getelementptr i8, ptr %ld403, i64 24
  %fv410 = load ptr, ptr %fp409, align 8
  %$f1032.addr = alloca ptr
  store ptr %fv410, ptr %$f1032.addr
  %ld411 = load ptr, ptr %$f1032.addr
  %res_slot412 = alloca ptr
  %tgp413 = getelementptr i8, ptr %ld411, i64 8
  %tag414 = load i32, ptr %tgp413, align 4
  switch i32 %tag414, label %case_default77 [
      i32 1, label %case_br78
  ]
case_br78:
  %fp415 = getelementptr i8, ptr %ld411, i64 16
  %fv416 = load ptr, ptr %fp415, align 8
  %$f1033.addr = alloca ptr
  store ptr %fv416, ptr %$f1033.addr
  %fp417 = getelementptr i8, ptr %ld411, i64 24
  %fv418 = load ptr, ptr %fp417, align 8
  %$f1034.addr = alloca ptr
  store ptr %fv418, ptr %$f1034.addr
  %ld419 = load ptr, ptr %$f1034.addr
  %rest.addr = alloca ptr
  store ptr %ld419, ptr %rest.addr
  %ld420 = load ptr, ptr %$f1033.addr
  %h.addr = alloca ptr
  store ptr %ld420, ptr %h.addr
  %ld421 = load ptr, ptr %$f1031.addr
  %g.addr = alloca ptr
  store ptr %ld421, ptr %g.addr
  %ld422 = load ptr, ptr %$f1029.addr
  %f.addr = alloca ptr
  store ptr %ld422, ptr %f.addr
  %ld423 = load ptr, ptr %$f1027.addr
  %e.addr = alloca ptr
  store ptr %ld423, ptr %e.addr
  %ld424 = load ptr, ptr %$f1025.addr
  %d.addr = alloca ptr
  store ptr %ld424, ptr %d.addr
  %ld425 = load ptr, ptr %$f1023.addr
  %c.addr = alloca ptr
  store ptr %ld425, ptr %c.addr
  %ld426 = load ptr, ptr %$f1021.addr
  %b.addr = alloca ptr
  store ptr %ld426, ptr %b.addr
  %ld427 = load ptr, ptr %$f1019.addr
  %a.addr = alloca ptr
  store ptr %ld427, ptr %a.addr
  %hp428 = call ptr @march_alloc(i64 16)
  %tgp429 = getelementptr i8, ptr %hp428, i64 8
  store i32 0, ptr %tgp429, align 4
  %$t1009.addr = alloca ptr
  store ptr %hp428, ptr %$t1009.addr
  %hp430 = call ptr @march_alloc(i64 32)
  %tgp431 = getelementptr i8, ptr %hp430, i64 8
  store i32 1, ptr %tgp431, align 4
  %ld432 = load i64, ptr %h.addr
  %cv433 = inttoptr i64 %ld432 to ptr
  %fp434 = getelementptr i8, ptr %hp430, i64 16
  store ptr %cv433, ptr %fp434, align 8
  %ld435 = load ptr, ptr %$t1009.addr
  %fp436 = getelementptr i8, ptr %hp430, i64 24
  store ptr %ld435, ptr %fp436, align 8
  %$t1010.addr = alloca ptr
  store ptr %hp430, ptr %$t1010.addr
  %hp437 = call ptr @march_alloc(i64 32)
  %tgp438 = getelementptr i8, ptr %hp437, i64 8
  store i32 1, ptr %tgp438, align 4
  %ld439 = load i64, ptr %g.addr
  %cv440 = inttoptr i64 %ld439 to ptr
  %fp441 = getelementptr i8, ptr %hp437, i64 16
  store ptr %cv440, ptr %fp441, align 8
  %ld442 = load ptr, ptr %$t1010.addr
  %fp443 = getelementptr i8, ptr %hp437, i64 24
  store ptr %ld442, ptr %fp443, align 8
  %$t1011.addr = alloca ptr
  store ptr %hp437, ptr %$t1011.addr
  %hp444 = call ptr @march_alloc(i64 32)
  %tgp445 = getelementptr i8, ptr %hp444, i64 8
  store i32 1, ptr %tgp445, align 4
  %ld446 = load i64, ptr %f.addr
  %cv447 = inttoptr i64 %ld446 to ptr
  %fp448 = getelementptr i8, ptr %hp444, i64 16
  store ptr %cv447, ptr %fp448, align 8
  %ld449 = load ptr, ptr %$t1011.addr
  %fp450 = getelementptr i8, ptr %hp444, i64 24
  store ptr %ld449, ptr %fp450, align 8
  %$t1012.addr = alloca ptr
  store ptr %hp444, ptr %$t1012.addr
  %hp451 = call ptr @march_alloc(i64 32)
  %tgp452 = getelementptr i8, ptr %hp451, i64 8
  store i32 1, ptr %tgp452, align 4
  %ld453 = load i64, ptr %e.addr
  %cv454 = inttoptr i64 %ld453 to ptr
  %fp455 = getelementptr i8, ptr %hp451, i64 16
  store ptr %cv454, ptr %fp455, align 8
  %ld456 = load ptr, ptr %$t1012.addr
  %fp457 = getelementptr i8, ptr %hp451, i64 24
  store ptr %ld456, ptr %fp457, align 8
  %$t1013.addr = alloca ptr
  store ptr %hp451, ptr %$t1013.addr
  %hp458 = call ptr @march_alloc(i64 32)
  %tgp459 = getelementptr i8, ptr %hp458, i64 8
  store i32 1, ptr %tgp459, align 4
  %ld460 = load i64, ptr %d.addr
  %cv461 = inttoptr i64 %ld460 to ptr
  %fp462 = getelementptr i8, ptr %hp458, i64 16
  store ptr %cv461, ptr %fp462, align 8
  %ld463 = load ptr, ptr %$t1013.addr
  %fp464 = getelementptr i8, ptr %hp458, i64 24
  store ptr %ld463, ptr %fp464, align 8
  %$t1014.addr = alloca ptr
  store ptr %hp458, ptr %$t1014.addr
  %hp465 = call ptr @march_alloc(i64 32)
  %tgp466 = getelementptr i8, ptr %hp465, i64 8
  store i32 1, ptr %tgp466, align 4
  %ld467 = load i64, ptr %c.addr
  %cv468 = inttoptr i64 %ld467 to ptr
  %fp469 = getelementptr i8, ptr %hp465, i64 16
  store ptr %cv468, ptr %fp469, align 8
  %ld470 = load ptr, ptr %$t1014.addr
  %fp471 = getelementptr i8, ptr %hp465, i64 24
  store ptr %ld470, ptr %fp471, align 8
  %$t1015.addr = alloca ptr
  store ptr %hp465, ptr %$t1015.addr
  %hp472 = call ptr @march_alloc(i64 32)
  %tgp473 = getelementptr i8, ptr %hp472, i64 8
  store i32 1, ptr %tgp473, align 4
  %ld474 = load i64, ptr %b.addr
  %cv475 = inttoptr i64 %ld474 to ptr
  %fp476 = getelementptr i8, ptr %hp472, i64 16
  store ptr %cv475, ptr %fp476, align 8
  %ld477 = load ptr, ptr %$t1015.addr
  %fp478 = getelementptr i8, ptr %hp472, i64 24
  store ptr %ld477, ptr %fp478, align 8
  %$t1016.addr = alloca ptr
  store ptr %hp472, ptr %$t1016.addr
  %hp479 = call ptr @march_alloc(i64 32)
  %tgp480 = getelementptr i8, ptr %hp479, i64 8
  store i32 1, ptr %tgp480, align 4
  %ld481 = load i64, ptr %a.addr
  %cv482 = inttoptr i64 %ld481 to ptr
  %fp483 = getelementptr i8, ptr %hp479, i64 16
  store ptr %cv482, ptr %fp483, align 8
  %ld484 = load ptr, ptr %$t1016.addr
  %fp485 = getelementptr i8, ptr %hp479, i64 24
  store ptr %ld484, ptr %fp485, align 8
  %$t1017.addr = alloca ptr
  store ptr %hp479, ptr %$t1017.addr
  %hp486 = call ptr @march_alloc(i64 32)
  %tgp487 = getelementptr i8, ptr %hp486, i64 8
  store i32 0, ptr %tgp487, align 4
  %ld488 = load ptr, ptr %$t1017.addr
  %fp489 = getelementptr i8, ptr %hp486, i64 16
  store ptr %ld488, ptr %fp489, align 8
  %ld490 = load ptr, ptr %rest.addr
  %fp491 = getelementptr i8, ptr %hp486, i64 24
  store ptr %ld490, ptr %fp491, align 8
  store ptr %hp486, ptr %res_slot412
  br label %case_merge76
case_default77:
  %ld492 = load ptr, ptr %acc.addr
  %cr493 = call ptr @reverse_list(ptr %ld492)
  %$t1018.addr = alloca ptr
  store ptr %cr493, ptr %$t1018.addr
  %hp494 = call ptr @march_alloc(i64 32)
  %tgp495 = getelementptr i8, ptr %hp494, i64 8
  store i32 0, ptr %tgp495, align 4
  %ld496 = load ptr, ptr %$t1018.addr
  %fp497 = getelementptr i8, ptr %hp494, i64 16
  store ptr %ld496, ptr %fp497, align 8
  %ld498 = load ptr, ptr %lst.addr
  %fp499 = getelementptr i8, ptr %hp494, i64 24
  store ptr %ld498, ptr %fp499, align 8
  store ptr %hp494, ptr %res_slot412
  br label %case_merge76
case_merge76:
  %case_r500 = load ptr, ptr %res_slot412
  store ptr %case_r500, ptr %res_slot404
  br label %case_merge73
case_default74:
  %ld501 = load ptr, ptr %acc.addr
  %cr502 = call ptr @reverse_list(ptr %ld501)
  %$t1018_1.addr = alloca ptr
  store ptr %cr502, ptr %$t1018_1.addr
  %hp503 = call ptr @march_alloc(i64 32)
  %tgp504 = getelementptr i8, ptr %hp503, i64 8
  store i32 0, ptr %tgp504, align 4
  %ld505 = load ptr, ptr %$t1018_1.addr
  %fp506 = getelementptr i8, ptr %hp503, i64 16
  store ptr %ld505, ptr %fp506, align 8
  %ld507 = load ptr, ptr %lst.addr
  %fp508 = getelementptr i8, ptr %hp503, i64 24
  store ptr %ld507, ptr %fp508, align 8
  store ptr %hp503, ptr %res_slot404
  br label %case_merge73
case_merge73:
  %case_r509 = load ptr, ptr %res_slot404
  store ptr %case_r509, ptr %res_slot396
  br label %case_merge70
case_default71:
  %ld510 = load ptr, ptr %acc.addr
  %cr511 = call ptr @reverse_list(ptr %ld510)
  %$t1018_2.addr = alloca ptr
  store ptr %cr511, ptr %$t1018_2.addr
  %hp512 = call ptr @march_alloc(i64 32)
  %tgp513 = getelementptr i8, ptr %hp512, i64 8
  store i32 0, ptr %tgp513, align 4
  %ld514 = load ptr, ptr %$t1018_2.addr
  %fp515 = getelementptr i8, ptr %hp512, i64 16
  store ptr %ld514, ptr %fp515, align 8
  %ld516 = load ptr, ptr %lst.addr
  %fp517 = getelementptr i8, ptr %hp512, i64 24
  store ptr %ld516, ptr %fp517, align 8
  store ptr %hp512, ptr %res_slot396
  br label %case_merge70
case_merge70:
  %case_r518 = load ptr, ptr %res_slot396
  store ptr %case_r518, ptr %res_slot388
  br label %case_merge67
case_default68:
  %ld519 = load ptr, ptr %acc.addr
  %cr520 = call ptr @reverse_list(ptr %ld519)
  %$t1018_3.addr = alloca ptr
  store ptr %cr520, ptr %$t1018_3.addr
  %hp521 = call ptr @march_alloc(i64 32)
  %tgp522 = getelementptr i8, ptr %hp521, i64 8
  store i32 0, ptr %tgp522, align 4
  %ld523 = load ptr, ptr %$t1018_3.addr
  %fp524 = getelementptr i8, ptr %hp521, i64 16
  store ptr %ld523, ptr %fp524, align 8
  %ld525 = load ptr, ptr %lst.addr
  %fp526 = getelementptr i8, ptr %hp521, i64 24
  store ptr %ld525, ptr %fp526, align 8
  store ptr %hp521, ptr %res_slot388
  br label %case_merge67
case_merge67:
  %case_r527 = load ptr, ptr %res_slot388
  store ptr %case_r527, ptr %res_slot380
  br label %case_merge64
case_default65:
  %ld528 = load ptr, ptr %acc.addr
  %cr529 = call ptr @reverse_list(ptr %ld528)
  %$t1018_4.addr = alloca ptr
  store ptr %cr529, ptr %$t1018_4.addr
  %hp530 = call ptr @march_alloc(i64 32)
  %tgp531 = getelementptr i8, ptr %hp530, i64 8
  store i32 0, ptr %tgp531, align 4
  %ld532 = load ptr, ptr %$t1018_4.addr
  %fp533 = getelementptr i8, ptr %hp530, i64 16
  store ptr %ld532, ptr %fp533, align 8
  %ld534 = load ptr, ptr %lst.addr
  %fp535 = getelementptr i8, ptr %hp530, i64 24
  store ptr %ld534, ptr %fp535, align 8
  store ptr %hp530, ptr %res_slot380
  br label %case_merge64
case_merge64:
  %case_r536 = load ptr, ptr %res_slot380
  store ptr %case_r536, ptr %res_slot372
  br label %case_merge61
case_default62:
  %ld537 = load ptr, ptr %acc.addr
  %cr538 = call ptr @reverse_list(ptr %ld537)
  %$t1018_5.addr = alloca ptr
  store ptr %cr538, ptr %$t1018_5.addr
  %hp539 = call ptr @march_alloc(i64 32)
  %tgp540 = getelementptr i8, ptr %hp539, i64 8
  store i32 0, ptr %tgp540, align 4
  %ld541 = load ptr, ptr %$t1018_5.addr
  %fp542 = getelementptr i8, ptr %hp539, i64 16
  store ptr %ld541, ptr %fp542, align 8
  %ld543 = load ptr, ptr %lst.addr
  %fp544 = getelementptr i8, ptr %hp539, i64 24
  store ptr %ld543, ptr %fp544, align 8
  store ptr %hp539, ptr %res_slot372
  br label %case_merge61
case_merge61:
  %case_r545 = load ptr, ptr %res_slot372
  store ptr %case_r545, ptr %res_slot364
  br label %case_merge58
case_default59:
  %ld546 = load ptr, ptr %acc.addr
  %cr547 = call ptr @reverse_list(ptr %ld546)
  %$t1018_6.addr = alloca ptr
  store ptr %cr547, ptr %$t1018_6.addr
  %hp548 = call ptr @march_alloc(i64 32)
  %tgp549 = getelementptr i8, ptr %hp548, i64 8
  store i32 0, ptr %tgp549, align 4
  %ld550 = load ptr, ptr %$t1018_6.addr
  %fp551 = getelementptr i8, ptr %hp548, i64 16
  store ptr %ld550, ptr %fp551, align 8
  %ld552 = load ptr, ptr %lst.addr
  %fp553 = getelementptr i8, ptr %hp548, i64 24
  store ptr %ld552, ptr %fp553, align 8
  store ptr %hp548, ptr %res_slot364
  br label %case_merge58
case_merge58:
  %case_r554 = load ptr, ptr %res_slot364
  store ptr %case_r554, ptr %res_slot340
  br label %case_merge51
case_default52:
  %ld555 = load ptr, ptr %acc.addr
  %cr556 = call ptr @reverse_list(ptr %ld555)
  %$t1018_7.addr = alloca ptr
  store ptr %cr556, ptr %$t1018_7.addr
  %hp557 = call ptr @march_alloc(i64 32)
  %tgp558 = getelementptr i8, ptr %hp557, i64 8
  store i32 0, ptr %tgp558, align 4
  %ld559 = load ptr, ptr %$t1018_7.addr
  %fp560 = getelementptr i8, ptr %hp557, i64 16
  store ptr %ld559, ptr %fp560, align 8
  %ld561 = load ptr, ptr %lst.addr
  %fp562 = getelementptr i8, ptr %hp557, i64 24
  store ptr %ld561, ptr %fp562, align 8
  store ptr %hp557, ptr %res_slot340
  br label %case_merge51
case_merge51:
  %case_r563 = load ptr, ptr %res_slot340
  ret ptr %case_r563
}

define ptr @sort_groups(ptr %lst.arg, ptr %acc.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld564 = load ptr, ptr %lst.addr
  %res_slot565 = alloca ptr
  %tgp566 = getelementptr i8, ptr %ld564, i64 8
  %tag567 = load i32, ptr %tgp566, align 4
  switch i32 %tag567, label %case_default80 [
      i32 0, label %case_br81
  ]
case_br81:
  %ld568 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld568)
  %ld569 = load ptr, ptr %acc.addr
  %cr570 = call ptr @reverse_list_of_lists(ptr %ld569)
  store ptr %cr570, ptr %res_slot565
  br label %case_merge79
case_default80:
  %hp571 = call ptr @march_alloc(i64 16)
  %tgp572 = getelementptr i8, ptr %hp571, i64 8
  store i32 0, ptr %tgp572, align 4
  %$t1035.addr = alloca ptr
  store ptr %hp571, ptr %$t1035.addr
  %ld573 = load ptr, ptr %lst.addr
  %ld574 = load ptr, ptr %$t1035.addr
  %cr575 = call ptr @take8(ptr %ld573, ptr %ld574)
  %$p1038.addr = alloca ptr
  store ptr %cr575, ptr %$p1038.addr
  %ld576 = load ptr, ptr %$p1038.addr
  %fp577 = getelementptr i8, ptr %ld576, i64 16
  %fv578 = load ptr, ptr %fp577, align 8
  %group.addr = alloca ptr
  store ptr %fv578, ptr %group.addr
  %ld579 = load ptr, ptr %$p1038.addr
  %fp580 = getelementptr i8, ptr %ld579, i64 24
  %fv581 = load ptr, ptr %fp580, align 8
  %rest.addr = alloca ptr
  store ptr %fv581, ptr %rest.addr
  %ld582 = load ptr, ptr %group.addr
  %cr583 = call ptr @sort_group8(ptr %ld582)
  %$t1036.addr = alloca ptr
  store ptr %cr583, ptr %$t1036.addr
  %hp584 = call ptr @march_alloc(i64 32)
  %tgp585 = getelementptr i8, ptr %hp584, i64 8
  store i32 1, ptr %tgp585, align 4
  %ld586 = load ptr, ptr %$t1036.addr
  %fp587 = getelementptr i8, ptr %hp584, i64 16
  store ptr %ld586, ptr %fp587, align 8
  %ld588 = load ptr, ptr %acc.addr
  %fp589 = getelementptr i8, ptr %hp584, i64 24
  store ptr %ld588, ptr %fp589, align 8
  %$t1037.addr = alloca ptr
  store ptr %hp584, ptr %$t1037.addr
  %ld590 = load ptr, ptr %rest.addr
  %ld591 = load ptr, ptr %$t1037.addr
  %cr592 = call ptr @sort_groups(ptr %ld590, ptr %ld591)
  store ptr %cr592, ptr %res_slot565
  br label %case_merge79
case_merge79:
  %case_r593 = load ptr, ptr %res_slot565
  ret ptr %case_r593
}

define ptr @reverse_list_of_lists(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp594 = call ptr @march_alloc(i64 24)
  %tgp595 = getelementptr i8, ptr %hp594, i64 8
  store i32 0, ptr %tgp595, align 4
  %fp596 = getelementptr i8, ptr %hp594, i64 16
  store ptr @go$apply$19, ptr %fp596, align 8
  %go.addr = alloca ptr
  store ptr %hp594, ptr %go.addr
  %hp597 = call ptr @march_alloc(i64 16)
  %tgp598 = getelementptr i8, ptr %hp597, i64 8
  store i32 0, ptr %tgp598, align 4
  %$t1042.addr = alloca ptr
  store ptr %hp597, ptr %$t1042.addr
  %ld599 = load ptr, ptr %go.addr
  %fp600 = getelementptr i8, ptr %ld599, i64 16
  %fv601 = load ptr, ptr %fp600, align 8
  %ld602 = load ptr, ptr %xs.addr
  %ld603 = load ptr, ptr %$t1042.addr
  %cr604 = call ptr (ptr, ptr, ptr) %fv601(ptr %ld599, ptr %ld602, ptr %ld603)
  ret ptr %cr604
}

define ptr @merge_all(ptr %groups.arg) {
entry:
  %groups.addr = alloca ptr
  store ptr %groups.arg, ptr %groups.addr
  %ld605 = load ptr, ptr %groups.addr
  %res_slot606 = alloca ptr
  %tgp607 = getelementptr i8, ptr %ld605, i64 8
  %tag608 = load i32, ptr %tgp607, align 4
  switch i32 %tag608, label %case_default83 [
      i32 0, label %case_br84
      i32 1, label %case_br85
  ]
case_br84:
  %ld609 = load ptr, ptr %groups.addr
  %rc610 = load i64, ptr %ld609, align 8
  %uniq611 = icmp eq i64 %rc610, 1
  %fbip_slot612 = alloca ptr
  br i1 %uniq611, label %fbip_reuse86, label %fbip_fresh87
fbip_reuse86:
  %tgp613 = getelementptr i8, ptr %ld609, i64 8
  store i32 0, ptr %tgp613, align 4
  store ptr %ld609, ptr %fbip_slot612
  br label %fbip_merge88
fbip_fresh87:
  call void @march_decrc(ptr %ld609)
  %hp614 = call ptr @march_alloc(i64 16)
  %tgp615 = getelementptr i8, ptr %hp614, i64 8
  store i32 0, ptr %tgp615, align 4
  store ptr %hp614, ptr %fbip_slot612
  br label %fbip_merge88
fbip_merge88:
  %fbip_r616 = load ptr, ptr %fbip_slot612
  store ptr %fbip_r616, ptr %res_slot606
  br label %case_merge82
case_br85:
  %fp617 = getelementptr i8, ptr %ld605, i64 16
  %fv618 = load ptr, ptr %fp617, align 8
  %$f1044.addr = alloca ptr
  store ptr %fv618, ptr %$f1044.addr
  %fp619 = getelementptr i8, ptr %ld605, i64 24
  %fv620 = load ptr, ptr %fp619, align 8
  %$f1045.addr = alloca ptr
  store ptr %fv620, ptr %$f1045.addr
  %ld621 = load ptr, ptr %$f1045.addr
  %res_slot622 = alloca ptr
  %tgp623 = getelementptr i8, ptr %ld621, i64 8
  %tag624 = load i32, ptr %tgp623, align 4
  switch i32 %tag624, label %case_default90 [
      i32 0, label %case_br91
  ]
case_br91:
  %ld625 = load ptr, ptr %$f1044.addr
  %g.addr = alloca ptr
  store ptr %ld625, ptr %g.addr
  %ld626 = load ptr, ptr %g.addr
  store ptr %ld626, ptr %res_slot622
  br label %case_merge89
case_default90:
  %ld627 = load ptr, ptr %groups.addr
  %cr628 = call ptr @merge_pairs(ptr %ld627)
  %$t1043.addr = alloca ptr
  store ptr %cr628, ptr %$t1043.addr
  %ld629 = load ptr, ptr %$t1043.addr
  %cr630 = call ptr @merge_all(ptr %ld629)
  store ptr %cr630, ptr %res_slot622
  br label %case_merge89
case_merge89:
  %case_r631 = load ptr, ptr %res_slot622
  store ptr %case_r631, ptr %res_slot606
  br label %case_merge82
case_default83:
  %ld632 = load ptr, ptr %groups.addr
  %cr633 = call ptr @merge_pairs(ptr %ld632)
  %$t1043_1.addr = alloca ptr
  store ptr %cr633, ptr %$t1043_1.addr
  %ld634 = load ptr, ptr %$t1043_1.addr
  %cr635 = call ptr @merge_all(ptr %ld634)
  store ptr %cr635, ptr %res_slot606
  br label %case_merge82
case_merge82:
  %case_r636 = load ptr, ptr %res_slot606
  ret ptr %case_r636
}

define ptr @merge_pairs(ptr %groups.arg) {
entry:
  %groups.addr = alloca ptr
  store ptr %groups.arg, ptr %groups.addr
  %ld637 = load ptr, ptr %groups.addr
  %res_slot638 = alloca ptr
  %tgp639 = getelementptr i8, ptr %ld637, i64 8
  %tag640 = load i32, ptr %tgp639, align 4
  switch i32 %tag640, label %case_default93 [
      i32 0, label %case_br94
      i32 1, label %case_br95
  ]
case_br94:
  %ld641 = load ptr, ptr %groups.addr
  %rc642 = load i64, ptr %ld641, align 8
  %uniq643 = icmp eq i64 %rc642, 1
  %fbip_slot644 = alloca ptr
  br i1 %uniq643, label %fbip_reuse96, label %fbip_fresh97
fbip_reuse96:
  %tgp645 = getelementptr i8, ptr %ld641, i64 8
  store i32 0, ptr %tgp645, align 4
  store ptr %ld641, ptr %fbip_slot644
  br label %fbip_merge98
fbip_fresh97:
  call void @march_decrc(ptr %ld641)
  %hp646 = call ptr @march_alloc(i64 16)
  %tgp647 = getelementptr i8, ptr %hp646, i64 8
  store i32 0, ptr %tgp647, align 4
  store ptr %hp646, ptr %fbip_slot644
  br label %fbip_merge98
fbip_merge98:
  %fbip_r648 = load ptr, ptr %fbip_slot644
  store ptr %fbip_r648, ptr %res_slot638
  br label %case_merge92
case_br95:
  %fp649 = getelementptr i8, ptr %ld637, i64 16
  %fv650 = load ptr, ptr %fp649, align 8
  %$f1049.addr = alloca ptr
  store ptr %fv650, ptr %$f1049.addr
  %fp651 = getelementptr i8, ptr %ld637, i64 24
  %fv652 = load ptr, ptr %fp651, align 8
  %$f1050.addr = alloca ptr
  store ptr %fv652, ptr %$f1050.addr
  %freed653 = call i64 @march_decrc_freed(ptr %ld637)
  %freed_b654 = icmp ne i64 %freed653, 0
  br i1 %freed_b654, label %br_unique99, label %br_shared100
br_shared100:
  call void @march_incrc(ptr %fv652)
  call void @march_incrc(ptr %fv650)
  br label %br_body101
br_unique99:
  br label %br_body101
br_body101:
  %ld655 = load ptr, ptr %$f1050.addr
  %res_slot656 = alloca ptr
  %tgp657 = getelementptr i8, ptr %ld655, i64 8
  %tag658 = load i32, ptr %tgp657, align 4
  switch i32 %tag658, label %case_default103 [
      i32 0, label %case_br104
  ]
case_br104:
  %ld659 = load ptr, ptr %$f1049.addr
  %g.addr = alloca ptr
  store ptr %ld659, ptr %g.addr
  %hp660 = call ptr @march_alloc(i64 16)
  %tgp661 = getelementptr i8, ptr %hp660, i64 8
  store i32 0, ptr %tgp661, align 4
  %$t1046.addr = alloca ptr
  store ptr %hp660, ptr %$t1046.addr
  %hp662 = call ptr @march_alloc(i64 32)
  %tgp663 = getelementptr i8, ptr %hp662, i64 8
  store i32 1, ptr %tgp663, align 4
  %ld664 = load ptr, ptr %g.addr
  %fp665 = getelementptr i8, ptr %hp662, i64 16
  store ptr %ld664, ptr %fp665, align 8
  %ld666 = load ptr, ptr %$t1046.addr
  %fp667 = getelementptr i8, ptr %hp662, i64 24
  store ptr %ld666, ptr %fp667, align 8
  store ptr %hp662, ptr %res_slot656
  br label %case_merge102
case_default103:
  %ld668 = load ptr, ptr %$f1050.addr
  %res_slot669 = alloca ptr
  %tgp670 = getelementptr i8, ptr %ld668, i64 8
  %tag671 = load i32, ptr %tgp670, align 4
  switch i32 %tag671, label %case_default106 [
      i32 1, label %case_br107
  ]
case_br107:
  %fp672 = getelementptr i8, ptr %ld668, i64 16
  %fv673 = load ptr, ptr %fp672, align 8
  %$f1051.addr = alloca ptr
  store ptr %fv673, ptr %$f1051.addr
  %fp674 = getelementptr i8, ptr %ld668, i64 24
  %fv675 = load ptr, ptr %fp674, align 8
  %$f1052.addr = alloca ptr
  store ptr %fv675, ptr %$f1052.addr
  %ld676 = load ptr, ptr %$f1052.addr
  %rest.addr = alloca ptr
  store ptr %ld676, ptr %rest.addr
  %ld677 = load ptr, ptr %$f1051.addr
  %g2.addr = alloca ptr
  store ptr %ld677, ptr %g2.addr
  %ld678 = load ptr, ptr %$f1049.addr
  %g1.addr = alloca ptr
  store ptr %ld678, ptr %g1.addr
  %ld679 = load ptr, ptr %g1.addr
  %ld680 = load ptr, ptr %g2.addr
  %cr681 = call ptr @merge(ptr %ld679, ptr %ld680)
  %$t1047.addr = alloca ptr
  store ptr %cr681, ptr %$t1047.addr
  %ld682 = load ptr, ptr %rest.addr
  %cr683 = call ptr @merge_pairs(ptr %ld682)
  %$t1048.addr = alloca ptr
  store ptr %cr683, ptr %$t1048.addr
  %hp684 = call ptr @march_alloc(i64 32)
  %tgp685 = getelementptr i8, ptr %hp684, i64 8
  store i32 1, ptr %tgp685, align 4
  %ld686 = load ptr, ptr %$t1047.addr
  %fp687 = getelementptr i8, ptr %hp684, i64 16
  store ptr %ld686, ptr %fp687, align 8
  %ld688 = load ptr, ptr %$t1048.addr
  %fp689 = getelementptr i8, ptr %hp684, i64 24
  store ptr %ld688, ptr %fp689, align 8
  store ptr %hp684, ptr %res_slot669
  br label %case_merge105
case_default106:
  %cv690 = inttoptr i64 0 to ptr
  store ptr %cv690, ptr %res_slot669
  br label %case_merge105
case_merge105:
  %case_r691 = load ptr, ptr %res_slot669
  store ptr %case_r691, ptr %res_slot656
  br label %case_merge102
case_merge102:
  %case_r692 = load ptr, ptr %res_slot656
  store ptr %case_r692, ptr %res_slot638
  br label %case_merge92
case_default93:
  unreachable
case_merge92:
  %case_r693 = load ptr, ptr %res_slot638
  ret ptr %case_r693
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld694 = load i64, ptr %n.addr
  %cmp695 = icmp eq i64 %ld694, 0
  %ar696 = zext i1 %cmp695 to i64
  %$t1053.addr = alloca i64
  store i64 %ar696, ptr %$t1053.addr
  %ld697 = load i64, ptr %$t1053.addr
  %res_slot698 = alloca ptr
  switch i64 %ld697, label %case_default109 [
      i64 1, label %case_br110
  ]
case_br110:
  %ld699 = load ptr, ptr %acc.addr
  store ptr %ld699, ptr %res_slot698
  br label %case_merge108
case_default109:
  %ld700 = load i64, ptr %seed.addr
  %ar701 = mul i64 %ld700, 1664525
  %$t1054.addr = alloca i64
  store i64 %ar701, ptr %$t1054.addr
  %ld702 = load i64, ptr %$t1054.addr
  %ar703 = add i64 %ld702, 1013904223
  %$t1055.addr = alloca i64
  store i64 %ar703, ptr %$t1055.addr
  %ld704 = load i64, ptr %$t1055.addr
  %ar705 = srem i64 %ld704, 1000000
  %next.addr = alloca i64
  store i64 %ar705, ptr %next.addr
  %ld706 = load i64, ptr %n.addr
  %ar707 = sub i64 %ld706, 1
  %$t1056.addr = alloca i64
  store i64 %ar707, ptr %$t1056.addr
  %ld708 = load i64, ptr %next.addr
  %ar709 = srem i64 %ld708, 100000
  %$t1057.addr = alloca i64
  store i64 %ar709, ptr %$t1057.addr
  %hp710 = call ptr @march_alloc(i64 32)
  %tgp711 = getelementptr i8, ptr %hp710, i64 8
  store i32 1, ptr %tgp711, align 4
  %ld712 = load i64, ptr %$t1057.addr
  %cv713 = inttoptr i64 %ld712 to ptr
  %fp714 = getelementptr i8, ptr %hp710, i64 16
  store ptr %cv713, ptr %fp714, align 8
  %ld715 = load ptr, ptr %acc.addr
  %fp716 = getelementptr i8, ptr %hp710, i64 24
  store ptr %ld715, ptr %fp716, align 8
  %$t1058.addr = alloca ptr
  store ptr %hp710, ptr %$t1058.addr
  %ld717 = load i64, ptr %$t1056.addr
  %ld718 = load i64, ptr %next.addr
  %ld719 = load ptr, ptr %$t1058.addr
  %cr720 = call ptr @gen_list(i64 %ld717, i64 %ld718, ptr %ld719)
  store ptr %cr720, ptr %res_slot698
  br label %case_merge108
case_merge108:
  %case_r721 = load ptr, ptr %res_slot698
  ret ptr %case_r721
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld722 = load ptr, ptr %xs.addr
  %res_slot723 = alloca ptr
  %tgp724 = getelementptr i8, ptr %ld722, i64 8
  %tag725 = load i32, ptr %tgp724, align 4
  switch i32 %tag725, label %case_default112 [
      i32 0, label %case_br113
      i32 1, label %case_br114
  ]
case_br113:
  %ld726 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld726)
  %cv727 = inttoptr i64 0 to ptr
  store ptr %cv727, ptr %res_slot723
  br label %case_merge111
case_br114:
  %fp728 = getelementptr i8, ptr %ld722, i64 16
  %fv729 = load ptr, ptr %fp728, align 8
  %$f1059.addr = alloca ptr
  store ptr %fv729, ptr %$f1059.addr
  %fp730 = getelementptr i8, ptr %ld722, i64 24
  %fv731 = load ptr, ptr %fp730, align 8
  %$f1060.addr = alloca ptr
  store ptr %fv731, ptr %$f1060.addr
  %freed732 = call i64 @march_decrc_freed(ptr %ld722)
  %freed_b733 = icmp ne i64 %freed732, 0
  br i1 %freed_b733, label %br_unique115, label %br_shared116
br_shared116:
  call void @march_incrc(ptr %fv731)
  br label %br_body117
br_unique115:
  br label %br_body117
br_body117:
  %ld734 = load ptr, ptr %$f1059.addr
  %h.addr = alloca ptr
  store ptr %ld734, ptr %h.addr
  %ld735 = load i64, ptr %h.addr
  %cv736 = inttoptr i64 %ld735 to ptr
  store ptr %cv736, ptr %res_slot723
  br label %case_merge111
case_default112:
  unreachable
case_merge111:
  %case_r737 = load ptr, ptr %res_slot723
  %cv738 = ptrtoint ptr %case_r737 to i64
  ret i64 %cv738
}

define void @march_main() {
entry:
  %hp739 = call ptr @march_alloc(i64 16)
  %tgp740 = getelementptr i8, ptr %hp739, i64 8
  store i32 0, ptr %tgp740, align 4
  %$t1061.addr = alloca ptr
  store ptr %hp739, ptr %$t1061.addr
  %ld741 = load ptr, ptr %$t1061.addr
  %cr742 = call ptr @gen_list(i64 10000, i64 42, ptr %ld741)
  %xs.addr = alloca ptr
  store ptr %cr742, ptr %xs.addr
  %hp743 = call ptr @march_alloc(i64 16)
  %tgp744 = getelementptr i8, ptr %hp743, i64 8
  store i32 0, ptr %tgp744, align 4
  %$t1062.addr = alloca ptr
  store ptr %hp743, ptr %$t1062.addr
  %ld745 = load ptr, ptr %xs.addr
  %ld746 = load ptr, ptr %$t1062.addr
  %cr747 = call ptr @sort_groups(ptr %ld745, ptr %ld746)
  %groups.addr = alloca ptr
  store ptr %cr747, ptr %groups.addr
  %ld748 = load ptr, ptr %groups.addr
  %cr749 = call ptr @merge_all(ptr %ld748)
  %sorted.addr = alloca ptr
  store ptr %cr749, ptr %sorted.addr
  %ld750 = load ptr, ptr %sorted.addr
  %cr751 = call i64 @head(ptr %ld750)
  %$t1063.addr = alloca i64
  store i64 %cr751, ptr %$t1063.addr
  %ld752 = load i64, ptr %$t1063.addr
  %cr753 = call ptr @march_int_to_string(i64 %ld752)
  %$t1064.addr = alloca ptr
  store ptr %cr753, ptr %$t1064.addr
  %ld754 = load ptr, ptr %$t1064.addr
  call void @march_println(ptr %ld754)
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
  %ld755 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld755, ptr %go.addr
  %ld756 = load ptr, ptr %lst.addr
  %res_slot757 = alloca ptr
  %tgp758 = getelementptr i8, ptr %ld756, i64 8
  %tag759 = load i32, ptr %tgp758, align 4
  switch i32 %tag759, label %case_default119 [
      i32 0, label %case_br120
      i32 1, label %case_br121
  ]
case_br120:
  %ld760 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld760)
  %ld761 = load ptr, ptr %acc.addr
  store ptr %ld761, ptr %res_slot757
  br label %case_merge118
case_br121:
  %fp762 = getelementptr i8, ptr %ld756, i64 16
  %fv763 = load ptr, ptr %fp762, align 8
  %$f971.addr = alloca ptr
  store ptr %fv763, ptr %$f971.addr
  %fp764 = getelementptr i8, ptr %ld756, i64 24
  %fv765 = load ptr, ptr %fp764, align 8
  %$f972.addr = alloca ptr
  store ptr %fv765, ptr %$f972.addr
  %ld766 = load ptr, ptr %$f972.addr
  %t.addr = alloca ptr
  store ptr %ld766, ptr %t.addr
  %ld767 = load ptr, ptr %$f971.addr
  %h.addr = alloca ptr
  store ptr %ld767, ptr %h.addr
  %ld768 = load ptr, ptr %lst.addr
  %ld769 = load i64, ptr %h.addr
  %cv770 = inttoptr i64 %ld769 to ptr
  %ld771 = load ptr, ptr %acc.addr
  %rc772 = load i64, ptr %ld768, align 8
  %uniq773 = icmp eq i64 %rc772, 1
  %fbip_slot774 = alloca ptr
  br i1 %uniq773, label %fbip_reuse122, label %fbip_fresh123
fbip_reuse122:
  %tgp775 = getelementptr i8, ptr %ld768, i64 8
  store i32 1, ptr %tgp775, align 4
  %fp776 = getelementptr i8, ptr %ld768, i64 16
  store ptr %cv770, ptr %fp776, align 8
  %fp777 = getelementptr i8, ptr %ld768, i64 24
  store ptr %ld771, ptr %fp777, align 8
  store ptr %ld768, ptr %fbip_slot774
  br label %fbip_merge124
fbip_fresh123:
  call void @march_decrc(ptr %ld768)
  %hp778 = call ptr @march_alloc(i64 32)
  %tgp779 = getelementptr i8, ptr %hp778, i64 8
  store i32 1, ptr %tgp779, align 4
  %fp780 = getelementptr i8, ptr %hp778, i64 16
  store ptr %cv770, ptr %fp780, align 8
  %fp781 = getelementptr i8, ptr %hp778, i64 24
  store ptr %ld771, ptr %fp781, align 8
  store ptr %hp778, ptr %fbip_slot774
  br label %fbip_merge124
fbip_merge124:
  %fbip_r782 = load ptr, ptr %fbip_slot774
  %$t970.addr = alloca ptr
  store ptr %fbip_r782, ptr %$t970.addr
  %ld783 = load ptr, ptr %go.addr
  %fp784 = getelementptr i8, ptr %ld783, i64 16
  %fv785 = load ptr, ptr %fp784, align 8
  %ld786 = load ptr, ptr %t.addr
  %ld787 = load ptr, ptr %$t970.addr
  %cr788 = call ptr (ptr, ptr, ptr) %fv785(ptr %ld783, ptr %ld786, ptr %ld787)
  store ptr %cr788, ptr %res_slot757
  br label %case_merge118
case_default119:
  unreachable
case_merge118:
  %case_r789 = load ptr, ptr %res_slot757
  ret ptr %case_r789
}

define ptr @go$apply$19(ptr %$clo.arg, ptr %lst.arg, ptr %acc.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld790 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld790, ptr %go.addr
  %ld791 = load ptr, ptr %lst.addr
  %res_slot792 = alloca ptr
  %tgp793 = getelementptr i8, ptr %ld791, i64 8
  %tag794 = load i32, ptr %tgp793, align 4
  switch i32 %tag794, label %case_default126 [
      i32 0, label %case_br127
      i32 1, label %case_br128
  ]
case_br127:
  %ld795 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld795)
  %ld796 = load ptr, ptr %acc.addr
  store ptr %ld796, ptr %res_slot792
  br label %case_merge125
case_br128:
  %fp797 = getelementptr i8, ptr %ld791, i64 16
  %fv798 = load ptr, ptr %fp797, align 8
  %$f1040.addr = alloca ptr
  store ptr %fv798, ptr %$f1040.addr
  %fp799 = getelementptr i8, ptr %ld791, i64 24
  %fv800 = load ptr, ptr %fp799, align 8
  %$f1041.addr = alloca ptr
  store ptr %fv800, ptr %$f1041.addr
  %ld801 = load ptr, ptr %$f1041.addr
  %t.addr = alloca ptr
  store ptr %ld801, ptr %t.addr
  %ld802 = load ptr, ptr %$f1040.addr
  %h.addr = alloca ptr
  store ptr %ld802, ptr %h.addr
  %ld803 = load ptr, ptr %lst.addr
  %ld804 = load ptr, ptr %h.addr
  %ld805 = load ptr, ptr %acc.addr
  %rc806 = load i64, ptr %ld803, align 8
  %uniq807 = icmp eq i64 %rc806, 1
  %fbip_slot808 = alloca ptr
  br i1 %uniq807, label %fbip_reuse129, label %fbip_fresh130
fbip_reuse129:
  %tgp809 = getelementptr i8, ptr %ld803, i64 8
  store i32 1, ptr %tgp809, align 4
  %fp810 = getelementptr i8, ptr %ld803, i64 16
  store ptr %ld804, ptr %fp810, align 8
  %fp811 = getelementptr i8, ptr %ld803, i64 24
  store ptr %ld805, ptr %fp811, align 8
  store ptr %ld803, ptr %fbip_slot808
  br label %fbip_merge131
fbip_fresh130:
  call void @march_decrc(ptr %ld803)
  %hp812 = call ptr @march_alloc(i64 32)
  %tgp813 = getelementptr i8, ptr %hp812, i64 8
  store i32 1, ptr %tgp813, align 4
  %fp814 = getelementptr i8, ptr %hp812, i64 16
  store ptr %ld804, ptr %fp814, align 8
  %fp815 = getelementptr i8, ptr %hp812, i64 24
  store ptr %ld805, ptr %fp815, align 8
  store ptr %hp812, ptr %fbip_slot808
  br label %fbip_merge131
fbip_merge131:
  %fbip_r816 = load ptr, ptr %fbip_slot808
  %$t1039.addr = alloca ptr
  store ptr %fbip_r816, ptr %$t1039.addr
  %ld817 = load ptr, ptr %go.addr
  %fp818 = getelementptr i8, ptr %ld817, i64 16
  %fv819 = load ptr, ptr %fp818, align 8
  %ld820 = load ptr, ptr %t.addr
  %ld821 = load ptr, ptr %$t1039.addr
  %cr822 = call ptr (ptr, ptr, ptr) %fv819(ptr %ld817, ptr %ld820, ptr %ld821)
  store ptr %cr822, ptr %res_slot792
  br label %case_merge125
case_default126:
  unreachable
case_merge125:
  %case_r823 = load ptr, ptr %res_slot792
  ret ptr %case_r823
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
