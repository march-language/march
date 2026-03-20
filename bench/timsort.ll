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

define ptr @scan_asc(ptr %lst.arg, ptr %run.arg, i64 %run_len.arg) {
entry:
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %run.addr = alloca ptr
  store ptr %run.arg, ptr %run.addr
  %run_len.addr = alloca i64
  store i64 %run_len.arg, ptr %run_len.addr
  %ld65 = load ptr, ptr %lst.addr
  %res_slot66 = alloca ptr
  %tgp67 = getelementptr i8, ptr %ld65, i64 8
  %tag68 = load i32, ptr %tgp67, align 4
  switch i32 %tag68, label %case_default13 [
      i32 0, label %case_br14
      i32 1, label %case_br15
  ]
case_br14:
  %ld69 = load ptr, ptr %run.addr
  %cr70 = call ptr @reverse_list(ptr %ld69)
  %$t981.addr = alloca ptr
  store ptr %cr70, ptr %$t981.addr
  %ld71 = load ptr, ptr %lst.addr
  %rc72 = load i64, ptr %ld71, align 8
  %uniq73 = icmp eq i64 %rc72, 1
  %fbip_slot74 = alloca ptr
  br i1 %uniq73, label %fbip_reuse16, label %fbip_fresh17
fbip_reuse16:
  %tgp75 = getelementptr i8, ptr %ld71, i64 8
  store i32 0, ptr %tgp75, align 4
  store ptr %ld71, ptr %fbip_slot74
  br label %fbip_merge18
fbip_fresh17:
  call void @march_decrc(ptr %ld71)
  %hp76 = call ptr @march_alloc(i64 16)
  %tgp77 = getelementptr i8, ptr %hp76, i64 8
  store i32 0, ptr %tgp77, align 4
  store ptr %hp76, ptr %fbip_slot74
  br label %fbip_merge18
fbip_merge18:
  %fbip_r78 = load ptr, ptr %fbip_slot74
  %$t982.addr = alloca ptr
  store ptr %fbip_r78, ptr %$t982.addr
  %hp79 = call ptr @march_alloc(i64 40)
  %tgp80 = getelementptr i8, ptr %hp79, i64 8
  store i32 0, ptr %tgp80, align 4
  %ld81 = load ptr, ptr %$t981.addr
  %fp82 = getelementptr i8, ptr %hp79, i64 16
  store ptr %ld81, ptr %fp82, align 8
  %ld83 = load i64, ptr %run_len.addr
  %fp84 = getelementptr i8, ptr %hp79, i64 24
  store i64 %ld83, ptr %fp84, align 8
  %ld85 = load ptr, ptr %$t982.addr
  %fp86 = getelementptr i8, ptr %hp79, i64 32
  store ptr %ld85, ptr %fp86, align 8
  store ptr %hp79, ptr %res_slot66
  br label %case_merge12
case_br15:
  %fp87 = getelementptr i8, ptr %ld65, i64 16
  %fv88 = load ptr, ptr %fp87, align 8
  %$f991.addr = alloca ptr
  store ptr %fv88, ptr %$f991.addr
  %fp89 = getelementptr i8, ptr %ld65, i64 24
  %fv90 = load ptr, ptr %fp89, align 8
  %$f992.addr = alloca ptr
  store ptr %fv90, ptr %$f992.addr
  %ld91 = load ptr, ptr %$f992.addr
  %t.addr = alloca ptr
  store ptr %ld91, ptr %t.addr
  %ld92 = load ptr, ptr %$f991.addr
  %h.addr = alloca ptr
  store ptr %ld92, ptr %h.addr
  %ld93 = load ptr, ptr %run.addr
  %res_slot94 = alloca ptr
  %tgp95 = getelementptr i8, ptr %ld93, i64 8
  %tag96 = load i32, ptr %tgp95, align 4
  switch i32 %tag96, label %case_default20 [
      i32 0, label %case_br21
      i32 1, label %case_br22
  ]
case_br21:
  %ld97 = load ptr, ptr %run.addr
  call void @march_decrc(ptr %ld97)
  %hp98 = call ptr @march_alloc(i64 16)
  %tgp99 = getelementptr i8, ptr %hp98, i64 8
  store i32 0, ptr %tgp99, align 4
  %$t983.addr = alloca ptr
  store ptr %hp98, ptr %$t983.addr
  %hp100 = call ptr @march_alloc(i64 32)
  %tgp101 = getelementptr i8, ptr %hp100, i64 8
  store i32 1, ptr %tgp101, align 4
  %ld102 = load i64, ptr %h.addr
  %cv103 = inttoptr i64 %ld102 to ptr
  %fp104 = getelementptr i8, ptr %hp100, i64 16
  store ptr %cv103, ptr %fp104, align 8
  %ld105 = load ptr, ptr %$t983.addr
  %fp106 = getelementptr i8, ptr %hp100, i64 24
  store ptr %ld105, ptr %fp106, align 8
  %$t984.addr = alloca ptr
  store ptr %hp100, ptr %$t984.addr
  %ld107 = load ptr, ptr %t.addr
  %ld108 = load ptr, ptr %$t984.addr
  %cr109 = call ptr @scan_asc(ptr %ld107, ptr %ld108, i64 1)
  store ptr %cr109, ptr %res_slot94
  br label %case_merge19
case_br22:
  %fp110 = getelementptr i8, ptr %ld93, i64 16
  %fv111 = load ptr, ptr %fp110, align 8
  %$f989.addr = alloca ptr
  store ptr %fv111, ptr %$f989.addr
  %fp112 = getelementptr i8, ptr %ld93, i64 24
  %fv113 = load ptr, ptr %fp112, align 8
  %$f990.addr = alloca ptr
  store ptr %fv113, ptr %$f990.addr
  %ld114 = load ptr, ptr %$f989.addr
  %prev.addr = alloca ptr
  store ptr %ld114, ptr %prev.addr
  %ld115 = load i64, ptr %prev.addr
  %ld116 = load i64, ptr %h.addr
  %cmp117 = icmp sle i64 %ld115, %ld116
  %ar118 = zext i1 %cmp117 to i64
  %$t985.addr = alloca i64
  store i64 %ar118, ptr %$t985.addr
  %ld119 = load i64, ptr %$t985.addr
  %res_slot120 = alloca ptr
  switch i64 %ld119, label %case_default24 [
      i64 1, label %case_br25
  ]
case_br25:
  %hp121 = call ptr @march_alloc(i64 32)
  %tgp122 = getelementptr i8, ptr %hp121, i64 8
  store i32 1, ptr %tgp122, align 4
  %ld123 = load i64, ptr %h.addr
  %cv124 = inttoptr i64 %ld123 to ptr
  %fp125 = getelementptr i8, ptr %hp121, i64 16
  store ptr %cv124, ptr %fp125, align 8
  %ld126 = load ptr, ptr %run.addr
  %fp127 = getelementptr i8, ptr %hp121, i64 24
  store ptr %ld126, ptr %fp127, align 8
  %$t986.addr = alloca ptr
  store ptr %hp121, ptr %$t986.addr
  %ld128 = load i64, ptr %run_len.addr
  %ar129 = add i64 %ld128, 1
  %$t987.addr = alloca i64
  store i64 %ar129, ptr %$t987.addr
  %ld130 = load ptr, ptr %t.addr
  %ld131 = load ptr, ptr %$t986.addr
  %ld132 = load i64, ptr %$t987.addr
  %cr133 = call ptr @scan_asc(ptr %ld130, ptr %ld131, i64 %ld132)
  store ptr %cr133, ptr %res_slot120
  br label %case_merge23
case_default24:
  %ld134 = load ptr, ptr %run.addr
  %cr135 = call ptr @reverse_list(ptr %ld134)
  %$t988.addr = alloca ptr
  store ptr %cr135, ptr %$t988.addr
  %hp136 = call ptr @march_alloc(i64 40)
  %tgp137 = getelementptr i8, ptr %hp136, i64 8
  store i32 0, ptr %tgp137, align 4
  %ld138 = load ptr, ptr %$t988.addr
  %fp139 = getelementptr i8, ptr %hp136, i64 16
  store ptr %ld138, ptr %fp139, align 8
  %ld140 = load i64, ptr %run_len.addr
  %fp141 = getelementptr i8, ptr %hp136, i64 24
  store i64 %ld140, ptr %fp141, align 8
  %ld142 = load ptr, ptr %lst.addr
  %fp143 = getelementptr i8, ptr %hp136, i64 32
  store ptr %ld142, ptr %fp143, align 8
  store ptr %hp136, ptr %res_slot120
  br label %case_merge23
case_merge23:
  %case_r144 = load ptr, ptr %res_slot120
  store ptr %case_r144, ptr %res_slot94
  br label %case_merge19
case_default20:
  unreachable
case_merge19:
  %case_r145 = load ptr, ptr %res_slot94
  store ptr %case_r145, ptr %res_slot66
  br label %case_merge12
case_default13:
  unreachable
case_merge12:
  %case_r146 = load ptr, ptr %res_slot66
  ret ptr %case_r146
}

define ptr @enforce(ptr %stack.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld147 = load ptr, ptr %stack.addr
  %res_slot148 = alloca ptr
  %tgp149 = getelementptr i8, ptr %ld147, i64 8
  %tag150 = load i32, ptr %tgp149, align 4
  switch i32 %tag150, label %case_default27 [
      i32 0, label %case_br28
      i32 1, label %case_br29
  ]
case_br28:
  %ld151 = load ptr, ptr %stack.addr
  %rc152 = load i64, ptr %ld151, align 8
  %uniq153 = icmp eq i64 %rc152, 1
  %fbip_slot154 = alloca ptr
  br i1 %uniq153, label %fbip_reuse30, label %fbip_fresh31
fbip_reuse30:
  %tgp155 = getelementptr i8, ptr %ld151, i64 8
  store i32 0, ptr %tgp155, align 4
  store ptr %ld151, ptr %fbip_slot154
  br label %fbip_merge32
fbip_fresh31:
  call void @march_decrc(ptr %ld151)
  %hp156 = call ptr @march_alloc(i64 16)
  %tgp157 = getelementptr i8, ptr %hp156, i64 8
  store i32 0, ptr %tgp157, align 4
  store ptr %hp156, ptr %fbip_slot154
  br label %fbip_merge32
fbip_merge32:
  %fbip_r158 = load ptr, ptr %fbip_slot154
  store ptr %fbip_r158, ptr %res_slot148
  br label %case_merge26
case_br29:
  %fp159 = getelementptr i8, ptr %ld147, i64 16
  %fv160 = load ptr, ptr %fp159, align 8
  %$f1010.addr = alloca ptr
  store ptr %fv160, ptr %$f1010.addr
  %fp161 = getelementptr i8, ptr %ld147, i64 24
  %fv162 = load ptr, ptr %fp161, align 8
  %$f1011.addr = alloca ptr
  store ptr %fv162, ptr %$f1011.addr
  %ld163 = load ptr, ptr %$f1011.addr
  %res_slot164 = alloca ptr
  %tgp165 = getelementptr i8, ptr %ld163, i64 8
  %tag166 = load i32, ptr %tgp165, align 4
  switch i32 %tag166, label %case_default34 [
      i32 0, label %case_br35
  ]
case_br35:
  %ld167 = load ptr, ptr %stack.addr
  store ptr %ld167, ptr %res_slot164
  br label %case_merge33
case_default34:
  %ld168 = load ptr, ptr %$f1010.addr
  %res_slot169 = alloca ptr
  %tgp170 = getelementptr i8, ptr %ld168, i64 8
  %tag171 = load i32, ptr %tgp170, align 4
  switch i32 %tag171, label %case_default37 [
      i32 0, label %case_br38
  ]
case_br38:
  %fp172 = getelementptr i8, ptr %ld168, i64 16
  %fv173 = load ptr, ptr %fp172, align 8
  %$f1012.addr = alloca ptr
  store ptr %fv173, ptr %$f1012.addr
  %fp174 = getelementptr i8, ptr %ld168, i64 24
  %fv175 = load ptr, ptr %fp174, align 8
  %$f1013.addr = alloca ptr
  store ptr %fv175, ptr %$f1013.addr
  %ld176 = load ptr, ptr %$f1011.addr
  %res_slot177 = alloca ptr
  %tgp178 = getelementptr i8, ptr %ld176, i64 8
  %tag179 = load i32, ptr %tgp178, align 4
  switch i32 %tag179, label %case_default40 [
      i32 1, label %case_br41
  ]
case_br41:
  %fp180 = getelementptr i8, ptr %ld176, i64 16
  %fv181 = load ptr, ptr %fp180, align 8
  %$f1022.addr = alloca ptr
  store ptr %fv181, ptr %$f1022.addr
  %fp182 = getelementptr i8, ptr %ld176, i64 24
  %fv183 = load ptr, ptr %fp182, align 8
  %$f1023.addr = alloca ptr
  store ptr %fv183, ptr %$f1023.addr
  %ld184 = load ptr, ptr %$f1022.addr
  %res_slot185 = alloca ptr
  %tgp186 = getelementptr i8, ptr %ld184, i64 8
  %tag187 = load i32, ptr %tgp186, align 4
  switch i32 %tag187, label %case_default43 [
      i32 0, label %case_br44
  ]
case_br44:
  %fp188 = getelementptr i8, ptr %ld184, i64 16
  %fv189 = load ptr, ptr %fp188, align 8
  %$f1024.addr = alloca ptr
  store ptr %fv189, ptr %$f1024.addr
  %fp190 = getelementptr i8, ptr %ld184, i64 24
  %fv191 = load ptr, ptr %fp190, align 8
  %$f1025.addr = alloca ptr
  store ptr %fv191, ptr %$f1025.addr
  %ld192 = load ptr, ptr %$f1023.addr
  %res_slot193 = alloca ptr
  %tgp194 = getelementptr i8, ptr %ld192, i64 8
  %tag195 = load i32, ptr %tgp194, align 4
  switch i32 %tag195, label %case_default46 [
      i32 0, label %case_br47
  ]
case_br47:
  %ld196 = load ptr, ptr %$f1025.addr
  %yn.addr = alloca ptr
  store ptr %ld196, ptr %yn.addr
  %ld197 = load ptr, ptr %$f1024.addr
  %y.addr = alloca ptr
  store ptr %ld197, ptr %y.addr
  %ld198 = load ptr, ptr %$f1013.addr
  %xn.addr = alloca ptr
  store ptr %ld198, ptr %xn.addr
  %ld199 = load ptr, ptr %$f1012.addr
  %x.addr = alloca ptr
  store ptr %ld199, ptr %x.addr
  %ld200 = load i64, ptr %yn.addr
  %ld201 = load i64, ptr %xn.addr
  %cmp202 = icmp sle i64 %ld200, %ld201
  %ar203 = zext i1 %cmp202 to i64
  %$t993.addr = alloca i64
  store i64 %ar203, ptr %$t993.addr
  %ld204 = load i64, ptr %$t993.addr
  %res_slot205 = alloca ptr
  switch i64 %ld204, label %case_default49 [
      i64 1, label %case_br50
  ]
case_br50:
  %ld206 = load ptr, ptr %y.addr
  %ld207 = load ptr, ptr %x.addr
  %cr208 = call ptr @merge(ptr %ld206, ptr %ld207)
  %m.addr = alloca ptr
  store ptr %cr208, ptr %m.addr
  %ld209 = load i64, ptr %xn.addr
  %ld210 = load i64, ptr %yn.addr
  %ar211 = add i64 %ld209, %ld210
  %$t994.addr = alloca i64
  store i64 %ar211, ptr %$t994.addr
  %hp212 = call ptr @march_alloc(i64 32)
  %tgp213 = getelementptr i8, ptr %hp212, i64 8
  store i32 0, ptr %tgp213, align 4
  %ld214 = load ptr, ptr %m.addr
  %fp215 = getelementptr i8, ptr %hp212, i64 16
  store ptr %ld214, ptr %fp215, align 8
  %ld216 = load i64, ptr %$t994.addr
  %fp217 = getelementptr i8, ptr %hp212, i64 24
  store i64 %ld216, ptr %fp217, align 8
  %$t995.addr = alloca ptr
  store ptr %hp212, ptr %$t995.addr
  %hp218 = call ptr @march_alloc(i64 16)
  %tgp219 = getelementptr i8, ptr %hp218, i64 8
  store i32 0, ptr %tgp219, align 4
  %$t996.addr = alloca ptr
  store ptr %hp218, ptr %$t996.addr
  %hp220 = call ptr @march_alloc(i64 32)
  %tgp221 = getelementptr i8, ptr %hp220, i64 8
  store i32 1, ptr %tgp221, align 4
  %ld222 = load ptr, ptr %$t995.addr
  %fp223 = getelementptr i8, ptr %hp220, i64 16
  store ptr %ld222, ptr %fp223, align 8
  %ld224 = load ptr, ptr %$t996.addr
  %fp225 = getelementptr i8, ptr %hp220, i64 24
  store ptr %ld224, ptr %fp225, align 8
  store ptr %hp220, ptr %res_slot205
  br label %case_merge48
case_default49:
  %ld226 = load ptr, ptr %stack.addr
  store ptr %ld226, ptr %res_slot205
  br label %case_merge48
case_merge48:
  %case_r227 = load ptr, ptr %res_slot205
  store ptr %case_r227, ptr %res_slot193
  br label %case_merge45
case_default46:
  %ld228 = load ptr, ptr %$f1011.addr
  %res_slot229 = alloca ptr
  %tgp230 = getelementptr i8, ptr %ld228, i64 8
  %tag231 = load i32, ptr %tgp230, align 4
  switch i32 %tag231, label %case_default52 [
      i32 1, label %case_br53
  ]
case_br53:
  %fp232 = getelementptr i8, ptr %ld228, i64 16
  %fv233 = load ptr, ptr %fp232, align 8
  %$f1014.addr = alloca ptr
  store ptr %fv233, ptr %$f1014.addr
  %fp234 = getelementptr i8, ptr %ld228, i64 24
  %fv235 = load ptr, ptr %fp234, align 8
  %$f1015.addr = alloca ptr
  store ptr %fv235, ptr %$f1015.addr
  %ld236 = load ptr, ptr %$f1014.addr
  %res_slot237 = alloca ptr
  %tgp238 = getelementptr i8, ptr %ld236, i64 8
  %tag239 = load i32, ptr %tgp238, align 4
  switch i32 %tag239, label %case_default55 [
      i32 0, label %case_br56
  ]
case_br56:
  %fp240 = getelementptr i8, ptr %ld236, i64 16
  %fv241 = load ptr, ptr %fp240, align 8
  %$f1016.addr = alloca ptr
  store ptr %fv241, ptr %$f1016.addr
  %fp242 = getelementptr i8, ptr %ld236, i64 24
  %fv243 = load ptr, ptr %fp242, align 8
  %$f1017.addr = alloca ptr
  store ptr %fv243, ptr %$f1017.addr
  %ld244 = load ptr, ptr %$f1015.addr
  %res_slot245 = alloca ptr
  %tgp246 = getelementptr i8, ptr %ld244, i64 8
  %tag247 = load i32, ptr %tgp246, align 4
  switch i32 %tag247, label %case_default58 [
      i32 1, label %case_br59
  ]
case_br59:
  %fp248 = getelementptr i8, ptr %ld244, i64 16
  %fv249 = load ptr, ptr %fp248, align 8
  %$f1018.addr = alloca ptr
  store ptr %fv249, ptr %$f1018.addr
  %fp250 = getelementptr i8, ptr %ld244, i64 24
  %fv251 = load ptr, ptr %fp250, align 8
  %$f1019.addr = alloca ptr
  store ptr %fv251, ptr %$f1019.addr
  %ld252 = load ptr, ptr %$f1018.addr
  %res_slot253 = alloca ptr
  %tgp254 = getelementptr i8, ptr %ld252, i64 8
  %tag255 = load i32, ptr %tgp254, align 4
  switch i32 %tag255, label %case_default61 [
      i32 0, label %case_br62
  ]
case_br62:
  %fp256 = getelementptr i8, ptr %ld252, i64 16
  %fv257 = load ptr, ptr %fp256, align 8
  %$f1020.addr = alloca ptr
  store ptr %fv257, ptr %$f1020.addr
  %fp258 = getelementptr i8, ptr %ld252, i64 24
  %fv259 = load ptr, ptr %fp258, align 8
  %$f1021.addr = alloca ptr
  store ptr %fv259, ptr %$f1021.addr
  %ld260 = load ptr, ptr %$f1019.addr
  %rest.addr = alloca ptr
  store ptr %ld260, ptr %rest.addr
  %ld261 = load ptr, ptr %$f1021.addr
  %zn.addr = alloca ptr
  store ptr %ld261, ptr %zn.addr
  %ld262 = load ptr, ptr %$f1020.addr
  %z.addr = alloca ptr
  store ptr %ld262, ptr %z.addr
  %ld263 = load ptr, ptr %$f1017.addr
  %yn_1.addr = alloca ptr
  store ptr %ld263, ptr %yn_1.addr
  %ld264 = load ptr, ptr %$f1016.addr
  %y_1.addr = alloca ptr
  store ptr %ld264, ptr %y_1.addr
  %ld265 = load ptr, ptr %$f1013.addr
  %xn_1.addr = alloca ptr
  store ptr %ld265, ptr %xn_1.addr
  %ld266 = load ptr, ptr %$f1012.addr
  %x_1.addr = alloca ptr
  store ptr %ld266, ptr %x_1.addr
  %ld267 = load i64, ptr %yn_1.addr
  %ld268 = load i64, ptr %xn_1.addr
  %cmp269 = icmp sle i64 %ld267, %ld268
  %ar270 = zext i1 %cmp269 to i64
  %$t997.addr = alloca i64
  store i64 %ar270, ptr %$t997.addr
  %ld271 = load i64, ptr %$t997.addr
  %res_slot272 = alloca ptr
  switch i64 %ld271, label %case_default64 [
      i64 1, label %case_br65
  ]
case_br65:
  %ld273 = load ptr, ptr %y_1.addr
  %ld274 = load ptr, ptr %x_1.addr
  %cr275 = call ptr @merge(ptr %ld273, ptr %ld274)
  %m_1.addr = alloca ptr
  store ptr %cr275, ptr %m_1.addr
  %ld276 = load i64, ptr %xn_1.addr
  %ld277 = load i64, ptr %yn_1.addr
  %ar278 = add i64 %ld276, %ld277
  %$t998.addr = alloca i64
  store i64 %ar278, ptr %$t998.addr
  %hp279 = call ptr @march_alloc(i64 32)
  %tgp280 = getelementptr i8, ptr %hp279, i64 8
  store i32 0, ptr %tgp280, align 4
  %ld281 = load ptr, ptr %m_1.addr
  %fp282 = getelementptr i8, ptr %hp279, i64 16
  store ptr %ld281, ptr %fp282, align 8
  %ld283 = load i64, ptr %$t998.addr
  %fp284 = getelementptr i8, ptr %hp279, i64 24
  store i64 %ld283, ptr %fp284, align 8
  %$t999.addr = alloca ptr
  store ptr %hp279, ptr %$t999.addr
  %hp285 = call ptr @march_alloc(i64 32)
  %tgp286 = getelementptr i8, ptr %hp285, i64 8
  store i32 0, ptr %tgp286, align 4
  %ld287 = load ptr, ptr %z.addr
  %fp288 = getelementptr i8, ptr %hp285, i64 16
  store ptr %ld287, ptr %fp288, align 8
  %ld289 = load i64, ptr %zn.addr
  %fp290 = getelementptr i8, ptr %hp285, i64 24
  store i64 %ld289, ptr %fp290, align 8
  %$t1000.addr = alloca ptr
  store ptr %hp285, ptr %$t1000.addr
  %hp291 = call ptr @march_alloc(i64 32)
  %tgp292 = getelementptr i8, ptr %hp291, i64 8
  store i32 1, ptr %tgp292, align 4
  %ld293 = load ptr, ptr %$t1000.addr
  %fp294 = getelementptr i8, ptr %hp291, i64 16
  store ptr %ld293, ptr %fp294, align 8
  %ld295 = load ptr, ptr %rest.addr
  %fp296 = getelementptr i8, ptr %hp291, i64 24
  store ptr %ld295, ptr %fp296, align 8
  %$t1001.addr = alloca ptr
  store ptr %hp291, ptr %$t1001.addr
  %hp297 = call ptr @march_alloc(i64 32)
  %tgp298 = getelementptr i8, ptr %hp297, i64 8
  store i32 1, ptr %tgp298, align 4
  %ld299 = load ptr, ptr %$t999.addr
  %fp300 = getelementptr i8, ptr %hp297, i64 16
  store ptr %ld299, ptr %fp300, align 8
  %ld301 = load ptr, ptr %$t1001.addr
  %fp302 = getelementptr i8, ptr %hp297, i64 24
  store ptr %ld301, ptr %fp302, align 8
  %$t1002.addr = alloca ptr
  store ptr %hp297, ptr %$t1002.addr
  %ld303 = load ptr, ptr %$t1002.addr
  %cr304 = call ptr @enforce(ptr %ld303)
  store ptr %cr304, ptr %res_slot272
  br label %case_merge63
case_default64:
  %ld305 = load i64, ptr %yn_1.addr
  %ld306 = load i64, ptr %xn_1.addr
  %ar307 = add i64 %ld305, %ld306
  %$t1003.addr = alloca i64
  store i64 %ar307, ptr %$t1003.addr
  %ld308 = load i64, ptr %zn.addr
  %ld309 = load i64, ptr %$t1003.addr
  %cmp310 = icmp sle i64 %ld308, %ld309
  %ar311 = zext i1 %cmp310 to i64
  %$t1004.addr = alloca i64
  store i64 %ar311, ptr %$t1004.addr
  %ld312 = load i64, ptr %$t1004.addr
  %res_slot313 = alloca ptr
  switch i64 %ld312, label %case_default67 [
      i64 1, label %case_br68
  ]
case_br68:
  %ld314 = load ptr, ptr %z.addr
  %ld315 = load ptr, ptr %y_1.addr
  %cr316 = call ptr @merge(ptr %ld314, ptr %ld315)
  %m_2.addr = alloca ptr
  store ptr %cr316, ptr %m_2.addr
  %hp317 = call ptr @march_alloc(i64 32)
  %tgp318 = getelementptr i8, ptr %hp317, i64 8
  store i32 0, ptr %tgp318, align 4
  %ld319 = load ptr, ptr %x_1.addr
  %fp320 = getelementptr i8, ptr %hp317, i64 16
  store ptr %ld319, ptr %fp320, align 8
  %ld321 = load i64, ptr %xn_1.addr
  %fp322 = getelementptr i8, ptr %hp317, i64 24
  store i64 %ld321, ptr %fp322, align 8
  %$t1005.addr = alloca ptr
  store ptr %hp317, ptr %$t1005.addr
  %ld323 = load i64, ptr %yn_1.addr
  %ld324 = load i64, ptr %zn.addr
  %ar325 = add i64 %ld323, %ld324
  %$t1006.addr = alloca i64
  store i64 %ar325, ptr %$t1006.addr
  %hp326 = call ptr @march_alloc(i64 32)
  %tgp327 = getelementptr i8, ptr %hp326, i64 8
  store i32 0, ptr %tgp327, align 4
  %ld328 = load ptr, ptr %m_2.addr
  %fp329 = getelementptr i8, ptr %hp326, i64 16
  store ptr %ld328, ptr %fp329, align 8
  %ld330 = load i64, ptr %$t1006.addr
  %fp331 = getelementptr i8, ptr %hp326, i64 24
  store i64 %ld330, ptr %fp331, align 8
  %$t1007.addr = alloca ptr
  store ptr %hp326, ptr %$t1007.addr
  %hp332 = call ptr @march_alloc(i64 32)
  %tgp333 = getelementptr i8, ptr %hp332, i64 8
  store i32 1, ptr %tgp333, align 4
  %ld334 = load ptr, ptr %$t1007.addr
  %fp335 = getelementptr i8, ptr %hp332, i64 16
  store ptr %ld334, ptr %fp335, align 8
  %ld336 = load ptr, ptr %rest.addr
  %fp337 = getelementptr i8, ptr %hp332, i64 24
  store ptr %ld336, ptr %fp337, align 8
  %$t1008.addr = alloca ptr
  store ptr %hp332, ptr %$t1008.addr
  %hp338 = call ptr @march_alloc(i64 32)
  %tgp339 = getelementptr i8, ptr %hp338, i64 8
  store i32 1, ptr %tgp339, align 4
  %ld340 = load ptr, ptr %$t1005.addr
  %fp341 = getelementptr i8, ptr %hp338, i64 16
  store ptr %ld340, ptr %fp341, align 8
  %ld342 = load ptr, ptr %$t1008.addr
  %fp343 = getelementptr i8, ptr %hp338, i64 24
  store ptr %ld342, ptr %fp343, align 8
  %$t1009.addr = alloca ptr
  store ptr %hp338, ptr %$t1009.addr
  %ld344 = load ptr, ptr %$t1009.addr
  %cr345 = call ptr @enforce(ptr %ld344)
  store ptr %cr345, ptr %res_slot313
  br label %case_merge66
case_default67:
  %ld346 = load ptr, ptr %stack.addr
  store ptr %ld346, ptr %res_slot313
  br label %case_merge66
case_merge66:
  %case_r347 = load ptr, ptr %res_slot313
  store ptr %case_r347, ptr %res_slot272
  br label %case_merge63
case_merge63:
  %case_r348 = load ptr, ptr %res_slot272
  store ptr %case_r348, ptr %res_slot253
  br label %case_merge60
case_default61:
  %cv349 = inttoptr i64 0 to ptr
  store ptr %cv349, ptr %res_slot253
  br label %case_merge60
case_merge60:
  %case_r350 = load ptr, ptr %res_slot253
  store ptr %case_r350, ptr %res_slot245
  br label %case_merge57
case_default58:
  %cv351 = inttoptr i64 0 to ptr
  store ptr %cv351, ptr %res_slot245
  br label %case_merge57
case_merge57:
  %case_r352 = load ptr, ptr %res_slot245
  store ptr %case_r352, ptr %res_slot237
  br label %case_merge54
case_default55:
  %cv353 = inttoptr i64 0 to ptr
  store ptr %cv353, ptr %res_slot237
  br label %case_merge54
case_merge54:
  %case_r354 = load ptr, ptr %res_slot237
  store ptr %case_r354, ptr %res_slot229
  br label %case_merge51
case_default52:
  %cv355 = inttoptr i64 0 to ptr
  store ptr %cv355, ptr %res_slot229
  br label %case_merge51
case_merge51:
  %case_r356 = load ptr, ptr %res_slot229
  store ptr %case_r356, ptr %res_slot193
  br label %case_merge45
case_merge45:
  %case_r357 = load ptr, ptr %res_slot193
  store ptr %case_r357, ptr %res_slot185
  br label %case_merge42
case_default43:
  %ld358 = load ptr, ptr %$f1011.addr
  %res_slot359 = alloca ptr
  %tgp360 = getelementptr i8, ptr %ld358, i64 8
  %tag361 = load i32, ptr %tgp360, align 4
  switch i32 %tag361, label %case_default70 [
      i32 1, label %case_br71
  ]
case_br71:
  %fp362 = getelementptr i8, ptr %ld358, i64 16
  %fv363 = load ptr, ptr %fp362, align 8
  %$f1014_1.addr = alloca ptr
  store ptr %fv363, ptr %$f1014_1.addr
  %fp364 = getelementptr i8, ptr %ld358, i64 24
  %fv365 = load ptr, ptr %fp364, align 8
  %$f1015_1.addr = alloca ptr
  store ptr %fv365, ptr %$f1015_1.addr
  %ld366 = load ptr, ptr %$f1014_1.addr
  %res_slot367 = alloca ptr
  %tgp368 = getelementptr i8, ptr %ld366, i64 8
  %tag369 = load i32, ptr %tgp368, align 4
  switch i32 %tag369, label %case_default73 [
      i32 0, label %case_br74
  ]
case_br74:
  %fp370 = getelementptr i8, ptr %ld366, i64 16
  %fv371 = load ptr, ptr %fp370, align 8
  %$f1016_1.addr = alloca ptr
  store ptr %fv371, ptr %$f1016_1.addr
  %fp372 = getelementptr i8, ptr %ld366, i64 24
  %fv373 = load ptr, ptr %fp372, align 8
  %$f1017_1.addr = alloca ptr
  store ptr %fv373, ptr %$f1017_1.addr
  %ld374 = load ptr, ptr %$f1015_1.addr
  %res_slot375 = alloca ptr
  %tgp376 = getelementptr i8, ptr %ld374, i64 8
  %tag377 = load i32, ptr %tgp376, align 4
  switch i32 %tag377, label %case_default76 [
      i32 1, label %case_br77
  ]
case_br77:
  %fp378 = getelementptr i8, ptr %ld374, i64 16
  %fv379 = load ptr, ptr %fp378, align 8
  %$f1018_1.addr = alloca ptr
  store ptr %fv379, ptr %$f1018_1.addr
  %fp380 = getelementptr i8, ptr %ld374, i64 24
  %fv381 = load ptr, ptr %fp380, align 8
  %$f1019_1.addr = alloca ptr
  store ptr %fv381, ptr %$f1019_1.addr
  %ld382 = load ptr, ptr %$f1018_1.addr
  %res_slot383 = alloca ptr
  %tgp384 = getelementptr i8, ptr %ld382, i64 8
  %tag385 = load i32, ptr %tgp384, align 4
  switch i32 %tag385, label %case_default79 [
      i32 0, label %case_br80
  ]
case_br80:
  %fp386 = getelementptr i8, ptr %ld382, i64 16
  %fv387 = load ptr, ptr %fp386, align 8
  %$f1020_1.addr = alloca ptr
  store ptr %fv387, ptr %$f1020_1.addr
  %fp388 = getelementptr i8, ptr %ld382, i64 24
  %fv389 = load ptr, ptr %fp388, align 8
  %$f1021_1.addr = alloca ptr
  store ptr %fv389, ptr %$f1021_1.addr
  %ld390 = load ptr, ptr %$f1019_1.addr
  %rest_1.addr = alloca ptr
  store ptr %ld390, ptr %rest_1.addr
  %ld391 = load ptr, ptr %$f1021_1.addr
  %zn_1.addr = alloca ptr
  store ptr %ld391, ptr %zn_1.addr
  %ld392 = load ptr, ptr %$f1020_1.addr
  %z_1.addr = alloca ptr
  store ptr %ld392, ptr %z_1.addr
  %ld393 = load ptr, ptr %$f1017_1.addr
  %yn_2.addr = alloca ptr
  store ptr %ld393, ptr %yn_2.addr
  %ld394 = load ptr, ptr %$f1016_1.addr
  %y_2.addr = alloca ptr
  store ptr %ld394, ptr %y_2.addr
  %ld395 = load ptr, ptr %$f1013.addr
  %xn_2.addr = alloca ptr
  store ptr %ld395, ptr %xn_2.addr
  %ld396 = load ptr, ptr %$f1012.addr
  %x_2.addr = alloca ptr
  store ptr %ld396, ptr %x_2.addr
  %ld397 = load i64, ptr %yn_2.addr
  %ld398 = load i64, ptr %xn_2.addr
  %cmp399 = icmp sle i64 %ld397, %ld398
  %ar400 = zext i1 %cmp399 to i64
  %$t997_1.addr = alloca i64
  store i64 %ar400, ptr %$t997_1.addr
  %ld401 = load i64, ptr %$t997_1.addr
  %res_slot402 = alloca ptr
  switch i64 %ld401, label %case_default82 [
      i64 1, label %case_br83
  ]
case_br83:
  %ld403 = load ptr, ptr %y_2.addr
  %ld404 = load ptr, ptr %x_2.addr
  %cr405 = call ptr @merge(ptr %ld403, ptr %ld404)
  %m_3.addr = alloca ptr
  store ptr %cr405, ptr %m_3.addr
  %ld406 = load i64, ptr %xn_2.addr
  %ld407 = load i64, ptr %yn_2.addr
  %ar408 = add i64 %ld406, %ld407
  %$t998_1.addr = alloca i64
  store i64 %ar408, ptr %$t998_1.addr
  %hp409 = call ptr @march_alloc(i64 32)
  %tgp410 = getelementptr i8, ptr %hp409, i64 8
  store i32 0, ptr %tgp410, align 4
  %ld411 = load ptr, ptr %m_3.addr
  %fp412 = getelementptr i8, ptr %hp409, i64 16
  store ptr %ld411, ptr %fp412, align 8
  %ld413 = load i64, ptr %$t998_1.addr
  %fp414 = getelementptr i8, ptr %hp409, i64 24
  store i64 %ld413, ptr %fp414, align 8
  %$t999_1.addr = alloca ptr
  store ptr %hp409, ptr %$t999_1.addr
  %hp415 = call ptr @march_alloc(i64 32)
  %tgp416 = getelementptr i8, ptr %hp415, i64 8
  store i32 0, ptr %tgp416, align 4
  %ld417 = load ptr, ptr %z_1.addr
  %fp418 = getelementptr i8, ptr %hp415, i64 16
  store ptr %ld417, ptr %fp418, align 8
  %ld419 = load i64, ptr %zn_1.addr
  %fp420 = getelementptr i8, ptr %hp415, i64 24
  store i64 %ld419, ptr %fp420, align 8
  %$t1000_1.addr = alloca ptr
  store ptr %hp415, ptr %$t1000_1.addr
  %hp421 = call ptr @march_alloc(i64 32)
  %tgp422 = getelementptr i8, ptr %hp421, i64 8
  store i32 1, ptr %tgp422, align 4
  %ld423 = load ptr, ptr %$t1000_1.addr
  %fp424 = getelementptr i8, ptr %hp421, i64 16
  store ptr %ld423, ptr %fp424, align 8
  %ld425 = load ptr, ptr %rest_1.addr
  %fp426 = getelementptr i8, ptr %hp421, i64 24
  store ptr %ld425, ptr %fp426, align 8
  %$t1001_1.addr = alloca ptr
  store ptr %hp421, ptr %$t1001_1.addr
  %hp427 = call ptr @march_alloc(i64 32)
  %tgp428 = getelementptr i8, ptr %hp427, i64 8
  store i32 1, ptr %tgp428, align 4
  %ld429 = load ptr, ptr %$t999_1.addr
  %fp430 = getelementptr i8, ptr %hp427, i64 16
  store ptr %ld429, ptr %fp430, align 8
  %ld431 = load ptr, ptr %$t1001_1.addr
  %fp432 = getelementptr i8, ptr %hp427, i64 24
  store ptr %ld431, ptr %fp432, align 8
  %$t1002_1.addr = alloca ptr
  store ptr %hp427, ptr %$t1002_1.addr
  %ld433 = load ptr, ptr %$t1002_1.addr
  %cr434 = call ptr @enforce(ptr %ld433)
  store ptr %cr434, ptr %res_slot402
  br label %case_merge81
case_default82:
  %ld435 = load i64, ptr %yn_2.addr
  %ld436 = load i64, ptr %xn_2.addr
  %ar437 = add i64 %ld435, %ld436
  %$t1003_1.addr = alloca i64
  store i64 %ar437, ptr %$t1003_1.addr
  %ld438 = load i64, ptr %zn_1.addr
  %ld439 = load i64, ptr %$t1003_1.addr
  %cmp440 = icmp sle i64 %ld438, %ld439
  %ar441 = zext i1 %cmp440 to i64
  %$t1004_1.addr = alloca i64
  store i64 %ar441, ptr %$t1004_1.addr
  %ld442 = load i64, ptr %$t1004_1.addr
  %res_slot443 = alloca ptr
  switch i64 %ld442, label %case_default85 [
      i64 1, label %case_br86
  ]
case_br86:
  %ld444 = load ptr, ptr %z_1.addr
  %ld445 = load ptr, ptr %y_2.addr
  %cr446 = call ptr @merge(ptr %ld444, ptr %ld445)
  %m_4.addr = alloca ptr
  store ptr %cr446, ptr %m_4.addr
  %hp447 = call ptr @march_alloc(i64 32)
  %tgp448 = getelementptr i8, ptr %hp447, i64 8
  store i32 0, ptr %tgp448, align 4
  %ld449 = load ptr, ptr %x_2.addr
  %fp450 = getelementptr i8, ptr %hp447, i64 16
  store ptr %ld449, ptr %fp450, align 8
  %ld451 = load i64, ptr %xn_2.addr
  %fp452 = getelementptr i8, ptr %hp447, i64 24
  store i64 %ld451, ptr %fp452, align 8
  %$t1005_1.addr = alloca ptr
  store ptr %hp447, ptr %$t1005_1.addr
  %ld453 = load i64, ptr %yn_2.addr
  %ld454 = load i64, ptr %zn_1.addr
  %ar455 = add i64 %ld453, %ld454
  %$t1006_1.addr = alloca i64
  store i64 %ar455, ptr %$t1006_1.addr
  %hp456 = call ptr @march_alloc(i64 32)
  %tgp457 = getelementptr i8, ptr %hp456, i64 8
  store i32 0, ptr %tgp457, align 4
  %ld458 = load ptr, ptr %m_4.addr
  %fp459 = getelementptr i8, ptr %hp456, i64 16
  store ptr %ld458, ptr %fp459, align 8
  %ld460 = load i64, ptr %$t1006_1.addr
  %fp461 = getelementptr i8, ptr %hp456, i64 24
  store i64 %ld460, ptr %fp461, align 8
  %$t1007_1.addr = alloca ptr
  store ptr %hp456, ptr %$t1007_1.addr
  %hp462 = call ptr @march_alloc(i64 32)
  %tgp463 = getelementptr i8, ptr %hp462, i64 8
  store i32 1, ptr %tgp463, align 4
  %ld464 = load ptr, ptr %$t1007_1.addr
  %fp465 = getelementptr i8, ptr %hp462, i64 16
  store ptr %ld464, ptr %fp465, align 8
  %ld466 = load ptr, ptr %rest_1.addr
  %fp467 = getelementptr i8, ptr %hp462, i64 24
  store ptr %ld466, ptr %fp467, align 8
  %$t1008_1.addr = alloca ptr
  store ptr %hp462, ptr %$t1008_1.addr
  %hp468 = call ptr @march_alloc(i64 32)
  %tgp469 = getelementptr i8, ptr %hp468, i64 8
  store i32 1, ptr %tgp469, align 4
  %ld470 = load ptr, ptr %$t1005_1.addr
  %fp471 = getelementptr i8, ptr %hp468, i64 16
  store ptr %ld470, ptr %fp471, align 8
  %ld472 = load ptr, ptr %$t1008_1.addr
  %fp473 = getelementptr i8, ptr %hp468, i64 24
  store ptr %ld472, ptr %fp473, align 8
  %$t1009_1.addr = alloca ptr
  store ptr %hp468, ptr %$t1009_1.addr
  %ld474 = load ptr, ptr %$t1009_1.addr
  %cr475 = call ptr @enforce(ptr %ld474)
  store ptr %cr475, ptr %res_slot443
  br label %case_merge84
case_default85:
  %ld476 = load ptr, ptr %stack.addr
  store ptr %ld476, ptr %res_slot443
  br label %case_merge84
case_merge84:
  %case_r477 = load ptr, ptr %res_slot443
  store ptr %case_r477, ptr %res_slot402
  br label %case_merge81
case_merge81:
  %case_r478 = load ptr, ptr %res_slot402
  store ptr %case_r478, ptr %res_slot383
  br label %case_merge78
case_default79:
  %cv479 = inttoptr i64 0 to ptr
  store ptr %cv479, ptr %res_slot383
  br label %case_merge78
case_merge78:
  %case_r480 = load ptr, ptr %res_slot383
  store ptr %case_r480, ptr %res_slot375
  br label %case_merge75
case_default76:
  %cv481 = inttoptr i64 0 to ptr
  store ptr %cv481, ptr %res_slot375
  br label %case_merge75
case_merge75:
  %case_r482 = load ptr, ptr %res_slot375
  store ptr %case_r482, ptr %res_slot367
  br label %case_merge72
case_default73:
  %cv483 = inttoptr i64 0 to ptr
  store ptr %cv483, ptr %res_slot367
  br label %case_merge72
case_merge72:
  %case_r484 = load ptr, ptr %res_slot367
  store ptr %case_r484, ptr %res_slot359
  br label %case_merge69
case_default70:
  %cv485 = inttoptr i64 0 to ptr
  store ptr %cv485, ptr %res_slot359
  br label %case_merge69
case_merge69:
  %case_r486 = load ptr, ptr %res_slot359
  store ptr %case_r486, ptr %res_slot185
  br label %case_merge42
case_merge42:
  %case_r487 = load ptr, ptr %res_slot185
  store ptr %case_r487, ptr %res_slot177
  br label %case_merge39
case_default40:
  %ld488 = load ptr, ptr %$f1011.addr
  %res_slot489 = alloca ptr
  %tgp490 = getelementptr i8, ptr %ld488, i64 8
  %tag491 = load i32, ptr %tgp490, align 4
  switch i32 %tag491, label %case_default88 [
      i32 1, label %case_br89
  ]
case_br89:
  %fp492 = getelementptr i8, ptr %ld488, i64 16
  %fv493 = load ptr, ptr %fp492, align 8
  %$f1014_2.addr = alloca ptr
  store ptr %fv493, ptr %$f1014_2.addr
  %fp494 = getelementptr i8, ptr %ld488, i64 24
  %fv495 = load ptr, ptr %fp494, align 8
  %$f1015_2.addr = alloca ptr
  store ptr %fv495, ptr %$f1015_2.addr
  %ld496 = load ptr, ptr %$f1014_2.addr
  %res_slot497 = alloca ptr
  %tgp498 = getelementptr i8, ptr %ld496, i64 8
  %tag499 = load i32, ptr %tgp498, align 4
  switch i32 %tag499, label %case_default91 [
      i32 0, label %case_br92
  ]
case_br92:
  %fp500 = getelementptr i8, ptr %ld496, i64 16
  %fv501 = load ptr, ptr %fp500, align 8
  %$f1016_2.addr = alloca ptr
  store ptr %fv501, ptr %$f1016_2.addr
  %fp502 = getelementptr i8, ptr %ld496, i64 24
  %fv503 = load ptr, ptr %fp502, align 8
  %$f1017_2.addr = alloca ptr
  store ptr %fv503, ptr %$f1017_2.addr
  %ld504 = load ptr, ptr %$f1015_2.addr
  %res_slot505 = alloca ptr
  %tgp506 = getelementptr i8, ptr %ld504, i64 8
  %tag507 = load i32, ptr %tgp506, align 4
  switch i32 %tag507, label %case_default94 [
      i32 1, label %case_br95
  ]
case_br95:
  %fp508 = getelementptr i8, ptr %ld504, i64 16
  %fv509 = load ptr, ptr %fp508, align 8
  %$f1018_2.addr = alloca ptr
  store ptr %fv509, ptr %$f1018_2.addr
  %fp510 = getelementptr i8, ptr %ld504, i64 24
  %fv511 = load ptr, ptr %fp510, align 8
  %$f1019_2.addr = alloca ptr
  store ptr %fv511, ptr %$f1019_2.addr
  %ld512 = load ptr, ptr %$f1018_2.addr
  %res_slot513 = alloca ptr
  %tgp514 = getelementptr i8, ptr %ld512, i64 8
  %tag515 = load i32, ptr %tgp514, align 4
  switch i32 %tag515, label %case_default97 [
      i32 0, label %case_br98
  ]
case_br98:
  %fp516 = getelementptr i8, ptr %ld512, i64 16
  %fv517 = load ptr, ptr %fp516, align 8
  %$f1020_2.addr = alloca ptr
  store ptr %fv517, ptr %$f1020_2.addr
  %fp518 = getelementptr i8, ptr %ld512, i64 24
  %fv519 = load ptr, ptr %fp518, align 8
  %$f1021_2.addr = alloca ptr
  store ptr %fv519, ptr %$f1021_2.addr
  %ld520 = load ptr, ptr %$f1019_2.addr
  %rest_2.addr = alloca ptr
  store ptr %ld520, ptr %rest_2.addr
  %ld521 = load ptr, ptr %$f1021_2.addr
  %zn_2.addr = alloca ptr
  store ptr %ld521, ptr %zn_2.addr
  %ld522 = load ptr, ptr %$f1020_2.addr
  %z_2.addr = alloca ptr
  store ptr %ld522, ptr %z_2.addr
  %ld523 = load ptr, ptr %$f1017_2.addr
  %yn_3.addr = alloca ptr
  store ptr %ld523, ptr %yn_3.addr
  %ld524 = load ptr, ptr %$f1016_2.addr
  %y_3.addr = alloca ptr
  store ptr %ld524, ptr %y_3.addr
  %ld525 = load ptr, ptr %$f1013.addr
  %xn_3.addr = alloca ptr
  store ptr %ld525, ptr %xn_3.addr
  %ld526 = load ptr, ptr %$f1012.addr
  %x_3.addr = alloca ptr
  store ptr %ld526, ptr %x_3.addr
  %ld527 = load i64, ptr %yn_3.addr
  %ld528 = load i64, ptr %xn_3.addr
  %cmp529 = icmp sle i64 %ld527, %ld528
  %ar530 = zext i1 %cmp529 to i64
  %$t997_2.addr = alloca i64
  store i64 %ar530, ptr %$t997_2.addr
  %ld531 = load i64, ptr %$t997_2.addr
  %res_slot532 = alloca ptr
  switch i64 %ld531, label %case_default100 [
      i64 1, label %case_br101
  ]
case_br101:
  %ld533 = load ptr, ptr %y_3.addr
  %ld534 = load ptr, ptr %x_3.addr
  %cr535 = call ptr @merge(ptr %ld533, ptr %ld534)
  %m_5.addr = alloca ptr
  store ptr %cr535, ptr %m_5.addr
  %ld536 = load i64, ptr %xn_3.addr
  %ld537 = load i64, ptr %yn_3.addr
  %ar538 = add i64 %ld536, %ld537
  %$t998_2.addr = alloca i64
  store i64 %ar538, ptr %$t998_2.addr
  %hp539 = call ptr @march_alloc(i64 32)
  %tgp540 = getelementptr i8, ptr %hp539, i64 8
  store i32 0, ptr %tgp540, align 4
  %ld541 = load ptr, ptr %m_5.addr
  %fp542 = getelementptr i8, ptr %hp539, i64 16
  store ptr %ld541, ptr %fp542, align 8
  %ld543 = load i64, ptr %$t998_2.addr
  %fp544 = getelementptr i8, ptr %hp539, i64 24
  store i64 %ld543, ptr %fp544, align 8
  %$t999_2.addr = alloca ptr
  store ptr %hp539, ptr %$t999_2.addr
  %hp545 = call ptr @march_alloc(i64 32)
  %tgp546 = getelementptr i8, ptr %hp545, i64 8
  store i32 0, ptr %tgp546, align 4
  %ld547 = load ptr, ptr %z_2.addr
  %fp548 = getelementptr i8, ptr %hp545, i64 16
  store ptr %ld547, ptr %fp548, align 8
  %ld549 = load i64, ptr %zn_2.addr
  %fp550 = getelementptr i8, ptr %hp545, i64 24
  store i64 %ld549, ptr %fp550, align 8
  %$t1000_2.addr = alloca ptr
  store ptr %hp545, ptr %$t1000_2.addr
  %hp551 = call ptr @march_alloc(i64 32)
  %tgp552 = getelementptr i8, ptr %hp551, i64 8
  store i32 1, ptr %tgp552, align 4
  %ld553 = load ptr, ptr %$t1000_2.addr
  %fp554 = getelementptr i8, ptr %hp551, i64 16
  store ptr %ld553, ptr %fp554, align 8
  %ld555 = load ptr, ptr %rest_2.addr
  %fp556 = getelementptr i8, ptr %hp551, i64 24
  store ptr %ld555, ptr %fp556, align 8
  %$t1001_2.addr = alloca ptr
  store ptr %hp551, ptr %$t1001_2.addr
  %hp557 = call ptr @march_alloc(i64 32)
  %tgp558 = getelementptr i8, ptr %hp557, i64 8
  store i32 1, ptr %tgp558, align 4
  %ld559 = load ptr, ptr %$t999_2.addr
  %fp560 = getelementptr i8, ptr %hp557, i64 16
  store ptr %ld559, ptr %fp560, align 8
  %ld561 = load ptr, ptr %$t1001_2.addr
  %fp562 = getelementptr i8, ptr %hp557, i64 24
  store ptr %ld561, ptr %fp562, align 8
  %$t1002_2.addr = alloca ptr
  store ptr %hp557, ptr %$t1002_2.addr
  %ld563 = load ptr, ptr %$t1002_2.addr
  %cr564 = call ptr @enforce(ptr %ld563)
  store ptr %cr564, ptr %res_slot532
  br label %case_merge99
case_default100:
  %ld565 = load i64, ptr %yn_3.addr
  %ld566 = load i64, ptr %xn_3.addr
  %ar567 = add i64 %ld565, %ld566
  %$t1003_2.addr = alloca i64
  store i64 %ar567, ptr %$t1003_2.addr
  %ld568 = load i64, ptr %zn_2.addr
  %ld569 = load i64, ptr %$t1003_2.addr
  %cmp570 = icmp sle i64 %ld568, %ld569
  %ar571 = zext i1 %cmp570 to i64
  %$t1004_2.addr = alloca i64
  store i64 %ar571, ptr %$t1004_2.addr
  %ld572 = load i64, ptr %$t1004_2.addr
  %res_slot573 = alloca ptr
  switch i64 %ld572, label %case_default103 [
      i64 1, label %case_br104
  ]
case_br104:
  %ld574 = load ptr, ptr %z_2.addr
  %ld575 = load ptr, ptr %y_3.addr
  %cr576 = call ptr @merge(ptr %ld574, ptr %ld575)
  %m_6.addr = alloca ptr
  store ptr %cr576, ptr %m_6.addr
  %hp577 = call ptr @march_alloc(i64 32)
  %tgp578 = getelementptr i8, ptr %hp577, i64 8
  store i32 0, ptr %tgp578, align 4
  %ld579 = load ptr, ptr %x_3.addr
  %fp580 = getelementptr i8, ptr %hp577, i64 16
  store ptr %ld579, ptr %fp580, align 8
  %ld581 = load i64, ptr %xn_3.addr
  %fp582 = getelementptr i8, ptr %hp577, i64 24
  store i64 %ld581, ptr %fp582, align 8
  %$t1005_2.addr = alloca ptr
  store ptr %hp577, ptr %$t1005_2.addr
  %ld583 = load i64, ptr %yn_3.addr
  %ld584 = load i64, ptr %zn_2.addr
  %ar585 = add i64 %ld583, %ld584
  %$t1006_2.addr = alloca i64
  store i64 %ar585, ptr %$t1006_2.addr
  %hp586 = call ptr @march_alloc(i64 32)
  %tgp587 = getelementptr i8, ptr %hp586, i64 8
  store i32 0, ptr %tgp587, align 4
  %ld588 = load ptr, ptr %m_6.addr
  %fp589 = getelementptr i8, ptr %hp586, i64 16
  store ptr %ld588, ptr %fp589, align 8
  %ld590 = load i64, ptr %$t1006_2.addr
  %fp591 = getelementptr i8, ptr %hp586, i64 24
  store i64 %ld590, ptr %fp591, align 8
  %$t1007_2.addr = alloca ptr
  store ptr %hp586, ptr %$t1007_2.addr
  %hp592 = call ptr @march_alloc(i64 32)
  %tgp593 = getelementptr i8, ptr %hp592, i64 8
  store i32 1, ptr %tgp593, align 4
  %ld594 = load ptr, ptr %$t1007_2.addr
  %fp595 = getelementptr i8, ptr %hp592, i64 16
  store ptr %ld594, ptr %fp595, align 8
  %ld596 = load ptr, ptr %rest_2.addr
  %fp597 = getelementptr i8, ptr %hp592, i64 24
  store ptr %ld596, ptr %fp597, align 8
  %$t1008_2.addr = alloca ptr
  store ptr %hp592, ptr %$t1008_2.addr
  %hp598 = call ptr @march_alloc(i64 32)
  %tgp599 = getelementptr i8, ptr %hp598, i64 8
  store i32 1, ptr %tgp599, align 4
  %ld600 = load ptr, ptr %$t1005_2.addr
  %fp601 = getelementptr i8, ptr %hp598, i64 16
  store ptr %ld600, ptr %fp601, align 8
  %ld602 = load ptr, ptr %$t1008_2.addr
  %fp603 = getelementptr i8, ptr %hp598, i64 24
  store ptr %ld602, ptr %fp603, align 8
  %$t1009_2.addr = alloca ptr
  store ptr %hp598, ptr %$t1009_2.addr
  %ld604 = load ptr, ptr %$t1009_2.addr
  %cr605 = call ptr @enforce(ptr %ld604)
  store ptr %cr605, ptr %res_slot573
  br label %case_merge102
case_default103:
  %ld606 = load ptr, ptr %stack.addr
  store ptr %ld606, ptr %res_slot573
  br label %case_merge102
case_merge102:
  %case_r607 = load ptr, ptr %res_slot573
  store ptr %case_r607, ptr %res_slot532
  br label %case_merge99
case_merge99:
  %case_r608 = load ptr, ptr %res_slot532
  store ptr %case_r608, ptr %res_slot513
  br label %case_merge96
case_default97:
  %cv609 = inttoptr i64 0 to ptr
  store ptr %cv609, ptr %res_slot513
  br label %case_merge96
case_merge96:
  %case_r610 = load ptr, ptr %res_slot513
  store ptr %case_r610, ptr %res_slot505
  br label %case_merge93
case_default94:
  %cv611 = inttoptr i64 0 to ptr
  store ptr %cv611, ptr %res_slot505
  br label %case_merge93
case_merge93:
  %case_r612 = load ptr, ptr %res_slot505
  store ptr %case_r612, ptr %res_slot497
  br label %case_merge90
case_default91:
  %cv613 = inttoptr i64 0 to ptr
  store ptr %cv613, ptr %res_slot497
  br label %case_merge90
case_merge90:
  %case_r614 = load ptr, ptr %res_slot497
  store ptr %case_r614, ptr %res_slot489
  br label %case_merge87
case_default88:
  %cv615 = inttoptr i64 0 to ptr
  store ptr %cv615, ptr %res_slot489
  br label %case_merge87
case_merge87:
  %case_r616 = load ptr, ptr %res_slot489
  store ptr %case_r616, ptr %res_slot177
  br label %case_merge39
case_merge39:
  %case_r617 = load ptr, ptr %res_slot177
  store ptr %case_r617, ptr %res_slot169
  br label %case_merge36
case_default37:
  unreachable
case_merge36:
  %case_r618 = load ptr, ptr %res_slot169
  store ptr %case_r618, ptr %res_slot164
  br label %case_merge33
case_merge33:
  %case_r619 = load ptr, ptr %res_slot164
  store ptr %case_r619, ptr %res_slot148
  br label %case_merge26
case_default27:
  unreachable
case_merge26:
  %case_r620 = load ptr, ptr %res_slot148
  ret ptr %case_r620
}

define ptr @collapse(ptr %stack.arg) {
entry:
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld621 = load ptr, ptr %stack.addr
  %res_slot622 = alloca ptr
  %tgp623 = getelementptr i8, ptr %ld621, i64 8
  %tag624 = load i32, ptr %tgp623, align 4
  switch i32 %tag624, label %case_default106 [
      i32 0, label %case_br107
      i32 1, label %case_br108
  ]
case_br107:
  %ld625 = load ptr, ptr %stack.addr
  %rc626 = load i64, ptr %ld625, align 8
  %uniq627 = icmp eq i64 %rc626, 1
  %fbip_slot628 = alloca ptr
  br i1 %uniq627, label %fbip_reuse109, label %fbip_fresh110
fbip_reuse109:
  %tgp629 = getelementptr i8, ptr %ld625, i64 8
  store i32 0, ptr %tgp629, align 4
  store ptr %ld625, ptr %fbip_slot628
  br label %fbip_merge111
fbip_fresh110:
  call void @march_decrc(ptr %ld625)
  %hp630 = call ptr @march_alloc(i64 16)
  %tgp631 = getelementptr i8, ptr %hp630, i64 8
  store i32 0, ptr %tgp631, align 4
  store ptr %hp630, ptr %fbip_slot628
  br label %fbip_merge111
fbip_merge111:
  %fbip_r632 = load ptr, ptr %fbip_slot628
  store ptr %fbip_r632, ptr %res_slot622
  br label %case_merge105
case_br108:
  %fp633 = getelementptr i8, ptr %ld621, i64 16
  %fv634 = load ptr, ptr %fp633, align 8
  %$f1029.addr = alloca ptr
  store ptr %fv634, ptr %$f1029.addr
  %fp635 = getelementptr i8, ptr %ld621, i64 24
  %fv636 = load ptr, ptr %fp635, align 8
  %$f1030.addr = alloca ptr
  store ptr %fv636, ptr %$f1030.addr
  %freed637 = call i64 @march_decrc_freed(ptr %ld621)
  %freed_b638 = icmp ne i64 %freed637, 0
  br i1 %freed_b638, label %br_unique112, label %br_shared113
br_shared113:
  call void @march_incrc(ptr %fv636)
  call void @march_incrc(ptr %fv634)
  br label %br_body114
br_unique112:
  br label %br_body114
br_body114:
  %ld639 = load ptr, ptr %$f1029.addr
  %res_slot640 = alloca ptr
  %tgp641 = getelementptr i8, ptr %ld639, i64 8
  %tag642 = load i32, ptr %tgp641, align 4
  switch i32 %tag642, label %case_default116 [
      i32 0, label %case_br117
  ]
case_br117:
  %fp643 = getelementptr i8, ptr %ld639, i64 16
  %fv644 = load ptr, ptr %fp643, align 8
  %$f1031.addr = alloca ptr
  store ptr %fv644, ptr %$f1031.addr
  %fp645 = getelementptr i8, ptr %ld639, i64 24
  %fv646 = load ptr, ptr %fp645, align 8
  %$f1032.addr = alloca ptr
  store ptr %fv646, ptr %$f1032.addr
  %ld647 = load ptr, ptr %$f1030.addr
  %res_slot648 = alloca ptr
  %tgp649 = getelementptr i8, ptr %ld647, i64 8
  %tag650 = load i32, ptr %tgp649, align 4
  switch i32 %tag650, label %case_default119 [
      i32 0, label %case_br120
  ]
case_br120:
  %ld651 = load ptr, ptr %$f1031.addr
  %x.addr = alloca ptr
  store ptr %ld651, ptr %x.addr
  %ld652 = load ptr, ptr %x.addr
  store ptr %ld652, ptr %res_slot648
  br label %case_merge118
case_default119:
  %ld653 = load ptr, ptr %$f1030.addr
  %res_slot654 = alloca ptr
  %tgp655 = getelementptr i8, ptr %ld653, i64 8
  %tag656 = load i32, ptr %tgp655, align 4
  switch i32 %tag656, label %case_default122 [
      i32 1, label %case_br123
  ]
case_br123:
  %fp657 = getelementptr i8, ptr %ld653, i64 16
  %fv658 = load ptr, ptr %fp657, align 8
  %$f1033.addr = alloca ptr
  store ptr %fv658, ptr %$f1033.addr
  %fp659 = getelementptr i8, ptr %ld653, i64 24
  %fv660 = load ptr, ptr %fp659, align 8
  %$f1034.addr = alloca ptr
  store ptr %fv660, ptr %$f1034.addr
  %ld661 = load ptr, ptr %$f1033.addr
  %res_slot662 = alloca ptr
  %tgp663 = getelementptr i8, ptr %ld661, i64 8
  %tag664 = load i32, ptr %tgp663, align 4
  switch i32 %tag664, label %case_default125 [
      i32 0, label %case_br126
  ]
case_br126:
  %fp665 = getelementptr i8, ptr %ld661, i64 16
  %fv666 = load ptr, ptr %fp665, align 8
  %$f1035.addr = alloca ptr
  store ptr %fv666, ptr %$f1035.addr
  %fp667 = getelementptr i8, ptr %ld661, i64 24
  %fv668 = load ptr, ptr %fp667, align 8
  %$f1036.addr = alloca ptr
  store ptr %fv668, ptr %$f1036.addr
  %ld669 = load ptr, ptr %$f1034.addr
  %rest.addr = alloca ptr
  store ptr %ld669, ptr %rest.addr
  %ld670 = load ptr, ptr %$f1036.addr
  %yn.addr = alloca ptr
  store ptr %ld670, ptr %yn.addr
  %ld671 = load ptr, ptr %$f1035.addr
  %y.addr = alloca ptr
  store ptr %ld671, ptr %y.addr
  %ld672 = load ptr, ptr %$f1032.addr
  %xn.addr = alloca ptr
  store ptr %ld672, ptr %xn.addr
  %ld673 = load ptr, ptr %$f1031.addr
  %x_1.addr = alloca ptr
  store ptr %ld673, ptr %x_1.addr
  %ld674 = load ptr, ptr %y.addr
  %ld675 = load ptr, ptr %x_1.addr
  %cr676 = call ptr @merge(ptr %ld674, ptr %ld675)
  %m.addr = alloca ptr
  store ptr %cr676, ptr %m.addr
  %ld677 = load i64, ptr %xn.addr
  %ld678 = load i64, ptr %yn.addr
  %ar679 = add i64 %ld677, %ld678
  %$t1026.addr = alloca i64
  store i64 %ar679, ptr %$t1026.addr
  %hp680 = call ptr @march_alloc(i64 32)
  %tgp681 = getelementptr i8, ptr %hp680, i64 8
  store i32 0, ptr %tgp681, align 4
  %ld682 = load ptr, ptr %m.addr
  %fp683 = getelementptr i8, ptr %hp680, i64 16
  store ptr %ld682, ptr %fp683, align 8
  %ld684 = load i64, ptr %$t1026.addr
  %fp685 = getelementptr i8, ptr %hp680, i64 24
  store i64 %ld684, ptr %fp685, align 8
  %$t1027.addr = alloca ptr
  store ptr %hp680, ptr %$t1027.addr
  %hp686 = call ptr @march_alloc(i64 32)
  %tgp687 = getelementptr i8, ptr %hp686, i64 8
  store i32 1, ptr %tgp687, align 4
  %ld688 = load ptr, ptr %$t1027.addr
  %fp689 = getelementptr i8, ptr %hp686, i64 16
  store ptr %ld688, ptr %fp689, align 8
  %ld690 = load ptr, ptr %rest.addr
  %fp691 = getelementptr i8, ptr %hp686, i64 24
  store ptr %ld690, ptr %fp691, align 8
  %$t1028.addr = alloca ptr
  store ptr %hp686, ptr %$t1028.addr
  %ld692 = load ptr, ptr %$t1028.addr
  %cr693 = call ptr @collapse(ptr %ld692)
  store ptr %cr693, ptr %res_slot662
  br label %case_merge124
case_default125:
  %cv694 = inttoptr i64 0 to ptr
  store ptr %cv694, ptr %res_slot662
  br label %case_merge124
case_merge124:
  %case_r695 = load ptr, ptr %res_slot662
  store ptr %case_r695, ptr %res_slot654
  br label %case_merge121
case_default122:
  %cv696 = inttoptr i64 0 to ptr
  store ptr %cv696, ptr %res_slot654
  br label %case_merge121
case_merge121:
  %case_r697 = load ptr, ptr %res_slot654
  store ptr %case_r697, ptr %res_slot648
  br label %case_merge118
case_merge118:
  %case_r698 = load ptr, ptr %res_slot648
  store ptr %case_r698, ptr %res_slot640
  br label %case_merge115
case_default116:
  unreachable
case_merge115:
  %case_r699 = load ptr, ptr %res_slot640
  store ptr %case_r699, ptr %res_slot622
  br label %case_merge105
case_default106:
  unreachable
case_merge105:
  %case_r700 = load ptr, ptr %res_slot622
  ret ptr %case_r700
}

define ptr @timsort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %hp701 = call ptr @march_alloc(i64 24)
  %tgp702 = getelementptr i8, ptr %hp701, i64 8
  store i32 0, ptr %tgp702, align 4
  %fp703 = getelementptr i8, ptr %hp701, i64 16
  store ptr @run_pass$apply$19, ptr %fp703, align 8
  %run_pass.addr = alloca ptr
  store ptr %hp701, ptr %run_pass.addr
  %hp704 = call ptr @march_alloc(i64 16)
  %tgp705 = getelementptr i8, ptr %hp704, i64 8
  store i32 0, ptr %tgp705, align 4
  %$t1041.addr = alloca ptr
  store ptr %hp704, ptr %$t1041.addr
  %ld706 = load ptr, ptr %run_pass.addr
  %fp707 = getelementptr i8, ptr %ld706, i64 16
  %fv708 = load ptr, ptr %fp707, align 8
  %ld709 = load ptr, ptr %xs.addr
  %ld710 = load ptr, ptr %$t1041.addr
  %cr711 = call ptr (ptr, ptr, ptr) %fv708(ptr %ld706, ptr %ld709, ptr %ld710)
  ret ptr %cr711
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld712 = load i64, ptr %n.addr
  %cmp713 = icmp eq i64 %ld712, 0
  %ar714 = zext i1 %cmp713 to i64
  %$t1042.addr = alloca i64
  store i64 %ar714, ptr %$t1042.addr
  %ld715 = load i64, ptr %$t1042.addr
  %res_slot716 = alloca ptr
  switch i64 %ld715, label %case_default128 [
      i64 1, label %case_br129
  ]
case_br129:
  %ld717 = load ptr, ptr %acc.addr
  store ptr %ld717, ptr %res_slot716
  br label %case_merge127
case_default128:
  %ld718 = load i64, ptr %seed.addr
  %ar719 = mul i64 %ld718, 1664525
  %$t1043.addr = alloca i64
  store i64 %ar719, ptr %$t1043.addr
  %ld720 = load i64, ptr %$t1043.addr
  %ar721 = add i64 %ld720, 1013904223
  %$t1044.addr = alloca i64
  store i64 %ar721, ptr %$t1044.addr
  %ld722 = load i64, ptr %$t1044.addr
  %ar723 = srem i64 %ld722, 1000000
  %next.addr = alloca i64
  store i64 %ar723, ptr %next.addr
  %ld724 = load i64, ptr %n.addr
  %ar725 = sub i64 %ld724, 1
  %$t1045.addr = alloca i64
  store i64 %ar725, ptr %$t1045.addr
  %ld726 = load i64, ptr %next.addr
  %ar727 = srem i64 %ld726, 100000
  %$t1046.addr = alloca i64
  store i64 %ar727, ptr %$t1046.addr
  %hp728 = call ptr @march_alloc(i64 32)
  %tgp729 = getelementptr i8, ptr %hp728, i64 8
  store i32 1, ptr %tgp729, align 4
  %ld730 = load i64, ptr %$t1046.addr
  %cv731 = inttoptr i64 %ld730 to ptr
  %fp732 = getelementptr i8, ptr %hp728, i64 16
  store ptr %cv731, ptr %fp732, align 8
  %ld733 = load ptr, ptr %acc.addr
  %fp734 = getelementptr i8, ptr %hp728, i64 24
  store ptr %ld733, ptr %fp734, align 8
  %$t1047.addr = alloca ptr
  store ptr %hp728, ptr %$t1047.addr
  %ld735 = load i64, ptr %$t1045.addr
  %ld736 = load i64, ptr %next.addr
  %ld737 = load ptr, ptr %$t1047.addr
  %cr738 = call ptr @gen_list(i64 %ld735, i64 %ld736, ptr %ld737)
  store ptr %cr738, ptr %res_slot716
  br label %case_merge127
case_merge127:
  %case_r739 = load ptr, ptr %res_slot716
  ret ptr %case_r739
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld740 = load ptr, ptr %xs.addr
  %res_slot741 = alloca ptr
  %tgp742 = getelementptr i8, ptr %ld740, i64 8
  %tag743 = load i32, ptr %tgp742, align 4
  switch i32 %tag743, label %case_default131 [
      i32 0, label %case_br132
      i32 1, label %case_br133
  ]
case_br132:
  %ld744 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld744)
  %cv745 = inttoptr i64 0 to ptr
  store ptr %cv745, ptr %res_slot741
  br label %case_merge130
case_br133:
  %fp746 = getelementptr i8, ptr %ld740, i64 16
  %fv747 = load ptr, ptr %fp746, align 8
  %$f1048.addr = alloca ptr
  store ptr %fv747, ptr %$f1048.addr
  %fp748 = getelementptr i8, ptr %ld740, i64 24
  %fv749 = load ptr, ptr %fp748, align 8
  %$f1049.addr = alloca ptr
  store ptr %fv749, ptr %$f1049.addr
  %freed750 = call i64 @march_decrc_freed(ptr %ld740)
  %freed_b751 = icmp ne i64 %freed750, 0
  br i1 %freed_b751, label %br_unique134, label %br_shared135
br_shared135:
  call void @march_incrc(ptr %fv749)
  br label %br_body136
br_unique134:
  br label %br_body136
br_body136:
  %ld752 = load ptr, ptr %$f1048.addr
  %h.addr = alloca ptr
  store ptr %ld752, ptr %h.addr
  %ld753 = load i64, ptr %h.addr
  %cv754 = inttoptr i64 %ld753 to ptr
  store ptr %cv754, ptr %res_slot741
  br label %case_merge130
case_default131:
  unreachable
case_merge130:
  %case_r755 = load ptr, ptr %res_slot741
  %cv756 = ptrtoint ptr %case_r755 to i64
  ret i64 %cv756
}

define void @march_main() {
entry:
  %hp757 = call ptr @march_alloc(i64 16)
  %tgp758 = getelementptr i8, ptr %hp757, i64 8
  store i32 0, ptr %tgp758, align 4
  %$t1050.addr = alloca ptr
  store ptr %hp757, ptr %$t1050.addr
  %ld759 = load ptr, ptr %$t1050.addr
  %cr760 = call ptr @gen_list(i64 10000, i64 42, ptr %ld759)
  %xs.addr = alloca ptr
  store ptr %cr760, ptr %xs.addr
  %ld761 = load ptr, ptr %xs.addr
  %cr762 = call ptr @timsort(ptr %ld761)
  %sorted.addr = alloca ptr
  store ptr %cr762, ptr %sorted.addr
  %ld763 = load ptr, ptr %sorted.addr
  %cr764 = call i64 @head(ptr %ld763)
  %$t1051.addr = alloca i64
  store i64 %cr764, ptr %$t1051.addr
  %ld765 = load i64, ptr %$t1051.addr
  %cr766 = call ptr @march_int_to_string(i64 %ld765)
  %$t1052.addr = alloca ptr
  store ptr %cr766, ptr %$t1052.addr
  %ld767 = load ptr, ptr %$t1052.addr
  call void @march_println(ptr %ld767)
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
  %ld768 = load ptr, ptr %$clo.addr
  %go.addr = alloca ptr
  store ptr %ld768, ptr %go.addr
  %ld769 = load ptr, ptr %lst.addr
  %res_slot770 = alloca ptr
  %tgp771 = getelementptr i8, ptr %ld769, i64 8
  %tag772 = load i32, ptr %tgp771, align 4
  switch i32 %tag772, label %case_default138 [
      i32 0, label %case_br139
      i32 1, label %case_br140
  ]
case_br139:
  %ld773 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld773)
  %ld774 = load ptr, ptr %acc.addr
  store ptr %ld774, ptr %res_slot770
  br label %case_merge137
case_br140:
  %fp775 = getelementptr i8, ptr %ld769, i64 16
  %fv776 = load ptr, ptr %fp775, align 8
  %$f971.addr = alloca ptr
  store ptr %fv776, ptr %$f971.addr
  %fp777 = getelementptr i8, ptr %ld769, i64 24
  %fv778 = load ptr, ptr %fp777, align 8
  %$f972.addr = alloca ptr
  store ptr %fv778, ptr %$f972.addr
  %ld779 = load ptr, ptr %$f972.addr
  %t.addr = alloca ptr
  store ptr %ld779, ptr %t.addr
  %ld780 = load ptr, ptr %$f971.addr
  %h.addr = alloca ptr
  store ptr %ld780, ptr %h.addr
  %ld781 = load ptr, ptr %lst.addr
  %ld782 = load i64, ptr %h.addr
  %cv783 = inttoptr i64 %ld782 to ptr
  %ld784 = load ptr, ptr %acc.addr
  %rc785 = load i64, ptr %ld781, align 8
  %uniq786 = icmp eq i64 %rc785, 1
  %fbip_slot787 = alloca ptr
  br i1 %uniq786, label %fbip_reuse141, label %fbip_fresh142
fbip_reuse141:
  %tgp788 = getelementptr i8, ptr %ld781, i64 8
  store i32 1, ptr %tgp788, align 4
  %fp789 = getelementptr i8, ptr %ld781, i64 16
  store ptr %cv783, ptr %fp789, align 8
  %fp790 = getelementptr i8, ptr %ld781, i64 24
  store ptr %ld784, ptr %fp790, align 8
  store ptr %ld781, ptr %fbip_slot787
  br label %fbip_merge143
fbip_fresh142:
  call void @march_decrc(ptr %ld781)
  %hp791 = call ptr @march_alloc(i64 32)
  %tgp792 = getelementptr i8, ptr %hp791, i64 8
  store i32 1, ptr %tgp792, align 4
  %fp793 = getelementptr i8, ptr %hp791, i64 16
  store ptr %cv783, ptr %fp793, align 8
  %fp794 = getelementptr i8, ptr %hp791, i64 24
  store ptr %ld784, ptr %fp794, align 8
  store ptr %hp791, ptr %fbip_slot787
  br label %fbip_merge143
fbip_merge143:
  %fbip_r795 = load ptr, ptr %fbip_slot787
  %$t970.addr = alloca ptr
  store ptr %fbip_r795, ptr %$t970.addr
  %ld796 = load ptr, ptr %go.addr
  %fp797 = getelementptr i8, ptr %ld796, i64 16
  %fv798 = load ptr, ptr %fp797, align 8
  %ld799 = load ptr, ptr %t.addr
  %ld800 = load ptr, ptr %$t970.addr
  %cr801 = call ptr (ptr, ptr, ptr) %fv798(ptr %ld796, ptr %ld799, ptr %ld800)
  store ptr %cr801, ptr %res_slot770
  br label %case_merge137
case_default138:
  unreachable
case_merge137:
  %case_r802 = load ptr, ptr %res_slot770
  ret ptr %case_r802
}

define ptr @run_pass$apply$19(ptr %$clo.arg, ptr %lst.arg, ptr %stack.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %lst.addr = alloca ptr
  store ptr %lst.arg, ptr %lst.addr
  %stack.addr = alloca ptr
  store ptr %stack.arg, ptr %stack.addr
  %ld803 = load ptr, ptr %$clo.addr
  %run_pass.addr = alloca ptr
  store ptr %ld803, ptr %run_pass.addr
  %ld804 = load ptr, ptr %lst.addr
  %res_slot805 = alloca ptr
  %tgp806 = getelementptr i8, ptr %ld804, i64 8
  %tag807 = load i32, ptr %tgp806, align 4
  switch i32 %tag807, label %case_default145 [
      i32 0, label %case_br146
  ]
case_br146:
  %ld808 = load ptr, ptr %lst.addr
  call void @march_decrc(ptr %ld808)
  %ld809 = load ptr, ptr %stack.addr
  %cr810 = call ptr @collapse(ptr %ld809)
  store ptr %cr810, ptr %res_slot805
  br label %case_merge144
case_default145:
  %hp811 = call ptr @march_alloc(i64 16)
  %tgp812 = getelementptr i8, ptr %hp811, i64 8
  store i32 0, ptr %tgp812, align 4
  %$t1037.addr = alloca ptr
  store ptr %hp811, ptr %$t1037.addr
  %ld813 = load ptr, ptr %lst.addr
  %ld814 = load ptr, ptr %$t1037.addr
  %cr815 = call ptr @scan_asc(ptr %ld813, ptr %ld814, i64 0)
  %$p1040.addr = alloca ptr
  store ptr %cr815, ptr %$p1040.addr
  %ld816 = load ptr, ptr %$p1040.addr
  %fp817 = getelementptr i8, ptr %ld816, i64 16
  %fv818 = load ptr, ptr %fp817, align 8
  %run.addr = alloca ptr
  store ptr %fv818, ptr %run.addr
  %ld819 = load ptr, ptr %$p1040.addr
  %fp820 = getelementptr i8, ptr %ld819, i64 24
  %fv821 = load ptr, ptr %fp820, align 8
  %rlen.addr = alloca ptr
  store ptr %fv821, ptr %rlen.addr
  %ld822 = load ptr, ptr %$p1040.addr
  %fp823 = getelementptr i8, ptr %ld822, i64 32
  %fv824 = load ptr, ptr %fp823, align 8
  %rest.addr = alloca ptr
  store ptr %fv824, ptr %rest.addr
  %hp825 = call ptr @march_alloc(i64 32)
  %tgp826 = getelementptr i8, ptr %hp825, i64 8
  store i32 0, ptr %tgp826, align 4
  %ld827 = load ptr, ptr %run.addr
  %fp828 = getelementptr i8, ptr %hp825, i64 16
  store ptr %ld827, ptr %fp828, align 8
  %ld829 = load i64, ptr %rlen.addr
  %fp830 = getelementptr i8, ptr %hp825, i64 24
  store i64 %ld829, ptr %fp830, align 8
  %$t1038.addr = alloca ptr
  store ptr %hp825, ptr %$t1038.addr
  %hp831 = call ptr @march_alloc(i64 32)
  %tgp832 = getelementptr i8, ptr %hp831, i64 8
  store i32 1, ptr %tgp832, align 4
  %ld833 = load ptr, ptr %$t1038.addr
  %fp834 = getelementptr i8, ptr %hp831, i64 16
  store ptr %ld833, ptr %fp834, align 8
  %ld835 = load ptr, ptr %stack.addr
  %fp836 = getelementptr i8, ptr %hp831, i64 24
  store ptr %ld835, ptr %fp836, align 8
  %$t1039.addr = alloca ptr
  store ptr %hp831, ptr %$t1039.addr
  %ld837 = load ptr, ptr %$t1039.addr
  %cr838 = call ptr @enforce(ptr %ld837)
  %new_stack.addr = alloca ptr
  store ptr %cr838, ptr %new_stack.addr
  %ld839 = load ptr, ptr %run_pass.addr
  %fp840 = getelementptr i8, ptr %ld839, i64 16
  %fv841 = load ptr, ptr %fp840, align 8
  %ld842 = load ptr, ptr %rest.addr
  %ld843 = load ptr, ptr %new_stack.addr
  %cr844 = call ptr (ptr, ptr, ptr) %fv841(ptr %ld839, ptr %ld842, ptr %ld843)
  store ptr %cr844, ptr %res_slot805
  br label %case_merge144
case_merge144:
  %case_r845 = load ptr, ptr %res_slot805
  ret ptr %case_r845
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
