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


define ptr @merge(ptr %xs.arg, ptr %ys.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ys.addr = alloca ptr
  store ptr %ys.arg, ptr %ys.addr
  %ld1 = load ptr, ptr %xs.addr
  %res_slot2 = alloca ptr
  %tgp3 = getelementptr i8, ptr %ld1, i64 8
  %tag4 = load i32, ptr %tgp3, align 4
  switch i32 %tag4, label %case_default2 [
      i32 0, label %case_br3
      i32 1, label %case_br4
  ]
case_br3:
  %ld5 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld5)
  %ld6 = load ptr, ptr %ys.addr
  store ptr %ld6, ptr %res_slot2
  br label %case_merge1
case_br4:
  %fp7 = getelementptr i8, ptr %ld1, i64 16
  %fv8 = load ptr, ptr %fp7, align 8
  %$f975.addr = alloca ptr
  store ptr %fv8, ptr %$f975.addr
  %fp9 = getelementptr i8, ptr %ld1, i64 24
  %fv10 = load ptr, ptr %fp9, align 8
  %$f976.addr = alloca ptr
  store ptr %fv10, ptr %$f976.addr
  %ld11 = load ptr, ptr %$f976.addr
  %xt.addr = alloca ptr
  store ptr %ld11, ptr %xt.addr
  %ld12 = load ptr, ptr %$f975.addr
  %x.addr = alloca ptr
  store ptr %ld12, ptr %x.addr
  %ld13 = load ptr, ptr %ys.addr
  %res_slot14 = alloca ptr
  %tgp15 = getelementptr i8, ptr %ld13, i64 8
  %tag16 = load i32, ptr %tgp15, align 4
  switch i32 %tag16, label %case_default6 [
      i32 0, label %case_br7
      i32 1, label %case_br8
  ]
case_br7:
  %ld17 = load ptr, ptr %ys.addr
  call void @march_decrc(ptr %ld17)
  %ld18 = load ptr, ptr %xs.addr
  store ptr %ld18, ptr %res_slot14
  br label %case_merge5
case_br8:
  %fp19 = getelementptr i8, ptr %ld13, i64 16
  %fv20 = load ptr, ptr %fp19, align 8
  %$f973.addr = alloca ptr
  store ptr %fv20, ptr %$f973.addr
  %fp21 = getelementptr i8, ptr %ld13, i64 24
  %fv22 = load ptr, ptr %fp21, align 8
  %$f974.addr = alloca ptr
  store ptr %fv22, ptr %$f974.addr
  %ld23 = load ptr, ptr %$f974.addr
  %yt.addr = alloca ptr
  store ptr %ld23, ptr %yt.addr
  %ld24 = load ptr, ptr %$f973.addr
  %y.addr = alloca ptr
  store ptr %ld24, ptr %y.addr
  %ld25 = load i64, ptr %x.addr
  %ld26 = load i64, ptr %y.addr
  %cmp27 = icmp sle i64 %ld25, %ld26
  %ar28 = zext i1 %cmp27 to i64
  %$t970.addr = alloca i64
  store i64 %ar28, ptr %$t970.addr
  %ld29 = load i64, ptr %$t970.addr
  %res_slot30 = alloca ptr
  switch i64 %ld29, label %case_default10 [
      i64 1, label %case_br11
  ]
case_br11:
  %ld31 = load ptr, ptr %xt.addr
  %ld32 = load ptr, ptr %ys.addr
  %cr33 = call ptr @merge(ptr %ld31, ptr %ld32)
  %$t971.addr = alloca ptr
  store ptr %cr33, ptr %$t971.addr
  %hp34 = call ptr @march_alloc(i64 32)
  %tgp35 = getelementptr i8, ptr %hp34, i64 8
  store i32 1, ptr %tgp35, align 4
  %ld36 = load i64, ptr %x.addr
  %cv37 = inttoptr i64 %ld36 to ptr
  %fp38 = getelementptr i8, ptr %hp34, i64 16
  store ptr %cv37, ptr %fp38, align 8
  %ld39 = load ptr, ptr %$t971.addr
  %fp40 = getelementptr i8, ptr %hp34, i64 24
  store ptr %ld39, ptr %fp40, align 8
  store ptr %hp34, ptr %res_slot30
  br label %case_merge9
case_default10:
  %ld41 = load ptr, ptr %xs.addr
  %ld42 = load ptr, ptr %yt.addr
  %cr43 = call ptr @merge(ptr %ld41, ptr %ld42)
  %$t972.addr = alloca ptr
  store ptr %cr43, ptr %$t972.addr
  %hp44 = call ptr @march_alloc(i64 32)
  %tgp45 = getelementptr i8, ptr %hp44, i64 8
  store i32 1, ptr %tgp45, align 4
  %ld46 = load i64, ptr %y.addr
  %cv47 = inttoptr i64 %ld46 to ptr
  %fp48 = getelementptr i8, ptr %hp44, i64 16
  store ptr %cv47, ptr %fp48, align 8
  %ld49 = load ptr, ptr %$t972.addr
  %fp50 = getelementptr i8, ptr %hp44, i64 24
  store ptr %ld49, ptr %fp50, align 8
  store ptr %hp44, ptr %res_slot30
  br label %case_merge9
case_merge9:
  %case_r51 = load ptr, ptr %res_slot30
  store ptr %case_r51, ptr %res_slot14
  br label %case_merge5
case_default6:
  unreachable
case_merge5:
  %case_r52 = load ptr, ptr %res_slot14
  store ptr %case_r52, ptr %res_slot2
  br label %case_merge1
case_default2:
  unreachable
case_merge1:
  %case_r53 = load ptr, ptr %res_slot2
  ret ptr %case_r53
}

define ptr @split(ptr %xs.arg, ptr %left.arg, ptr %right.arg, i64 %toggle.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %left.addr = alloca ptr
  store ptr %left.arg, ptr %left.addr
  %right.addr = alloca ptr
  store ptr %right.arg, ptr %right.addr
  %toggle.addr = alloca i64
  store i64 %toggle.arg, ptr %toggle.addr
  %ld54 = load ptr, ptr %xs.addr
  %res_slot55 = alloca ptr
  %tgp56 = getelementptr i8, ptr %ld54, i64 8
  %tag57 = load i32, ptr %tgp56, align 4
  switch i32 %tag57, label %case_default13 [
      i32 0, label %case_br14
      i32 1, label %case_br15
  ]
case_br14:
  %ld58 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld58)
  %hp59 = call ptr @march_alloc(i64 32)
  %tgp60 = getelementptr i8, ptr %hp59, i64 8
  store i32 0, ptr %tgp60, align 4
  %ld61 = load ptr, ptr %left.addr
  %fp62 = getelementptr i8, ptr %hp59, i64 16
  store ptr %ld61, ptr %fp62, align 8
  %ld63 = load ptr, ptr %right.addr
  %fp64 = getelementptr i8, ptr %hp59, i64 24
  store ptr %ld63, ptr %fp64, align 8
  store ptr %hp59, ptr %res_slot55
  br label %case_merge12
case_br15:
  %fp65 = getelementptr i8, ptr %ld54, i64 16
  %fv66 = load ptr, ptr %fp65, align 8
  %$f979.addr = alloca ptr
  store ptr %fv66, ptr %$f979.addr
  %fp67 = getelementptr i8, ptr %ld54, i64 24
  %fv68 = load ptr, ptr %fp67, align 8
  %$f980.addr = alloca ptr
  store ptr %fv68, ptr %$f980.addr
  %freed69 = call i64 @march_decrc_freed(ptr %ld54)
  %freed_b70 = icmp ne i64 %freed69, 0
  br i1 %freed_b70, label %br_unique16, label %br_shared17
br_shared17:
  call void @march_incrc(ptr %fv68)
  br label %br_body18
br_unique16:
  br label %br_body18
br_body18:
  %ld71 = load ptr, ptr %$f980.addr
  %t.addr = alloca ptr
  store ptr %ld71, ptr %t.addr
  %ld72 = load ptr, ptr %$f979.addr
  %h.addr = alloca ptr
  store ptr %ld72, ptr %h.addr
  %ld73 = load i64, ptr %toggle.addr
  %res_slot74 = alloca ptr
  switch i64 %ld73, label %case_default20 [
      i64 1, label %case_br21
  ]
case_br21:
  %hp75 = call ptr @march_alloc(i64 32)
  %tgp76 = getelementptr i8, ptr %hp75, i64 8
  store i32 1, ptr %tgp76, align 4
  %ld77 = load i64, ptr %h.addr
  %cv78 = inttoptr i64 %ld77 to ptr
  %fp79 = getelementptr i8, ptr %hp75, i64 16
  store ptr %cv78, ptr %fp79, align 8
  %ld80 = load ptr, ptr %left.addr
  %fp81 = getelementptr i8, ptr %hp75, i64 24
  store ptr %ld80, ptr %fp81, align 8
  %$t977.addr = alloca ptr
  store ptr %hp75, ptr %$t977.addr
  %ld82 = load ptr, ptr %t.addr
  %ld83 = load ptr, ptr %$t977.addr
  %ld84 = load ptr, ptr %right.addr
  %cr85 = call ptr @split(ptr %ld82, ptr %ld83, ptr %ld84, i64 0)
  store ptr %cr85, ptr %res_slot74
  br label %case_merge19
case_default20:
  %hp86 = call ptr @march_alloc(i64 32)
  %tgp87 = getelementptr i8, ptr %hp86, i64 8
  store i32 1, ptr %tgp87, align 4
  %ld88 = load i64, ptr %h.addr
  %cv89 = inttoptr i64 %ld88 to ptr
  %fp90 = getelementptr i8, ptr %hp86, i64 16
  store ptr %cv89, ptr %fp90, align 8
  %ld91 = load ptr, ptr %right.addr
  %fp92 = getelementptr i8, ptr %hp86, i64 24
  store ptr %ld91, ptr %fp92, align 8
  %$t978.addr = alloca ptr
  store ptr %hp86, ptr %$t978.addr
  %ld93 = load ptr, ptr %t.addr
  %ld94 = load ptr, ptr %left.addr
  %ld95 = load ptr, ptr %$t978.addr
  %cr96 = call ptr @split(ptr %ld93, ptr %ld94, ptr %ld95, i64 1)
  store ptr %cr96, ptr %res_slot74
  br label %case_merge19
case_merge19:
  %case_r97 = load ptr, ptr %res_slot74
  store ptr %case_r97, ptr %res_slot55
  br label %case_merge12
case_default13:
  unreachable
case_merge12:
  %case_r98 = load ptr, ptr %res_slot55
  ret ptr %case_r98
}

define ptr @mergesort(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld99 = load ptr, ptr %xs.addr
  %res_slot100 = alloca ptr
  %tgp101 = getelementptr i8, ptr %ld99, i64 8
  %tag102 = load i32, ptr %tgp101, align 4
  switch i32 %tag102, label %case_default23 [
      i32 0, label %case_br24
      i32 1, label %case_br25
  ]
case_br24:
  %ld103 = load ptr, ptr %xs.addr
  %rc104 = load i64, ptr %ld103, align 8
  %uniq105 = icmp eq i64 %rc104, 1
  %fbip_slot106 = alloca ptr
  br i1 %uniq105, label %fbip_reuse26, label %fbip_fresh27
fbip_reuse26:
  %tgp107 = getelementptr i8, ptr %ld103, i64 8
  store i32 0, ptr %tgp107, align 4
  store ptr %ld103, ptr %fbip_slot106
  br label %fbip_merge28
fbip_fresh27:
  call void @march_decrc(ptr %ld103)
  %hp108 = call ptr @march_alloc(i64 16)
  %tgp109 = getelementptr i8, ptr %hp108, i64 8
  store i32 0, ptr %tgp109, align 4
  store ptr %hp108, ptr %fbip_slot106
  br label %fbip_merge28
fbip_merge28:
  %fbip_r110 = load ptr, ptr %fbip_slot106
  store ptr %fbip_r110, ptr %res_slot100
  br label %case_merge22
case_br25:
  %fp111 = getelementptr i8, ptr %ld99, i64 16
  %fv112 = load ptr, ptr %fp111, align 8
  %$f987.addr = alloca ptr
  store ptr %fv112, ptr %$f987.addr
  %fp113 = getelementptr i8, ptr %ld99, i64 24
  %fv114 = load ptr, ptr %fp113, align 8
  %$f988.addr = alloca ptr
  store ptr %fv114, ptr %$f988.addr
  %freed115 = call i64 @march_decrc_freed(ptr %ld99)
  %freed_b116 = icmp ne i64 %freed115, 0
  br i1 %freed_b116, label %br_unique29, label %br_shared30
br_shared30:
  call void @march_incrc(ptr %fv114)
  br label %br_body31
br_unique29:
  br label %br_body31
br_body31:
  %ld117 = load ptr, ptr %$f988.addr
  %t.addr = alloca ptr
  store ptr %ld117, ptr %t.addr
  %ld118 = load ptr, ptr %$f987.addr
  %h.addr = alloca ptr
  store ptr %ld118, ptr %h.addr
  %ld119 = load ptr, ptr %t.addr
  %res_slot120 = alloca ptr
  %tgp121 = getelementptr i8, ptr %ld119, i64 8
  %tag122 = load i32, ptr %tgp121, align 4
  switch i32 %tag122, label %case_default33 [
      i32 0, label %case_br34
  ]
case_br34:
  %ld123 = load ptr, ptr %t.addr
  %rc124 = load i64, ptr %ld123, align 8
  %uniq125 = icmp eq i64 %rc124, 1
  %fbip_slot126 = alloca ptr
  br i1 %uniq125, label %fbip_reuse35, label %fbip_fresh36
fbip_reuse35:
  %tgp127 = getelementptr i8, ptr %ld123, i64 8
  store i32 0, ptr %tgp127, align 4
  store ptr %ld123, ptr %fbip_slot126
  br label %fbip_merge37
fbip_fresh36:
  call void @march_decrc(ptr %ld123)
  %hp128 = call ptr @march_alloc(i64 16)
  %tgp129 = getelementptr i8, ptr %hp128, i64 8
  store i32 0, ptr %tgp129, align 4
  store ptr %hp128, ptr %fbip_slot126
  br label %fbip_merge37
fbip_merge37:
  %fbip_r130 = load ptr, ptr %fbip_slot126
  %$t981.addr = alloca ptr
  store ptr %fbip_r130, ptr %$t981.addr
  %hp131 = call ptr @march_alloc(i64 32)
  %tgp132 = getelementptr i8, ptr %hp131, i64 8
  store i32 1, ptr %tgp132, align 4
  %ld133 = load i64, ptr %h.addr
  %cv134 = inttoptr i64 %ld133 to ptr
  %fp135 = getelementptr i8, ptr %hp131, i64 16
  store ptr %cv134, ptr %fp135, align 8
  %ld136 = load ptr, ptr %$t981.addr
  %fp137 = getelementptr i8, ptr %hp131, i64 24
  store ptr %ld136, ptr %fp137, align 8
  store ptr %hp131, ptr %res_slot120
  br label %case_merge32
case_default33:
  %hp138 = call ptr @march_alloc(i64 32)
  %tgp139 = getelementptr i8, ptr %hp138, i64 8
  store i32 1, ptr %tgp139, align 4
  %ld140 = load i64, ptr %h.addr
  %cv141 = inttoptr i64 %ld140 to ptr
  %fp142 = getelementptr i8, ptr %hp138, i64 16
  store ptr %cv141, ptr %fp142, align 8
  %ld143 = load ptr, ptr %t.addr
  %fp144 = getelementptr i8, ptr %hp138, i64 24
  store ptr %ld143, ptr %fp144, align 8
  %xs2.addr = alloca ptr
  store ptr %hp138, ptr %xs2.addr
  %hp145 = call ptr @march_alloc(i64 16)
  %tgp146 = getelementptr i8, ptr %hp145, i64 8
  store i32 0, ptr %tgp146, align 4
  %$t982.addr = alloca ptr
  store ptr %hp145, ptr %$t982.addr
  %hp147 = call ptr @march_alloc(i64 16)
  %tgp148 = getelementptr i8, ptr %hp147, i64 8
  store i32 0, ptr %tgp148, align 4
  %$t983.addr = alloca ptr
  store ptr %hp147, ptr %$t983.addr
  %ld149 = load ptr, ptr %xs2.addr
  %ld150 = load ptr, ptr %$t982.addr
  %ld151 = load ptr, ptr %$t983.addr
  %cr152 = call ptr @split(ptr %ld149, ptr %ld150, ptr %ld151, i64 1)
  %$p986.addr = alloca ptr
  store ptr %cr152, ptr %$p986.addr
  %ld153 = load ptr, ptr %$p986.addr
  %fp154 = getelementptr i8, ptr %ld153, i64 16
  %fv155 = load ptr, ptr %fp154, align 8
  %l.addr = alloca ptr
  store ptr %fv155, ptr %l.addr
  %ld156 = load ptr, ptr %$p986.addr
  %fp157 = getelementptr i8, ptr %ld156, i64 24
  %fv158 = load ptr, ptr %fp157, align 8
  %r.addr = alloca ptr
  store ptr %fv158, ptr %r.addr
  %ld159 = load ptr, ptr %l.addr
  %cr160 = call ptr @mergesort(ptr %ld159)
  %$t984.addr = alloca ptr
  store ptr %cr160, ptr %$t984.addr
  %ld161 = load ptr, ptr %r.addr
  %cr162 = call ptr @mergesort(ptr %ld161)
  %$t985.addr = alloca ptr
  store ptr %cr162, ptr %$t985.addr
  %ld163 = load ptr, ptr %$t984.addr
  %ld164 = load ptr, ptr %$t985.addr
  %cr165 = call ptr @merge(ptr %ld163, ptr %ld164)
  store ptr %cr165, ptr %res_slot120
  br label %case_merge32
case_merge32:
  %case_r166 = load ptr, ptr %res_slot120
  store ptr %case_r166, ptr %res_slot100
  br label %case_merge22
case_default23:
  unreachable
case_merge22:
  %case_r167 = load ptr, ptr %res_slot100
  ret ptr %case_r167
}

define ptr @gen_list(i64 %n.arg, i64 %seed.arg, ptr %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %seed.addr = alloca i64
  store i64 %seed.arg, ptr %seed.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld168 = load i64, ptr %n.addr
  %cmp169 = icmp eq i64 %ld168, 0
  %ar170 = zext i1 %cmp169 to i64
  %$t989.addr = alloca i64
  store i64 %ar170, ptr %$t989.addr
  %ld171 = load i64, ptr %$t989.addr
  %res_slot172 = alloca ptr
  switch i64 %ld171, label %case_default39 [
      i64 1, label %case_br40
  ]
case_br40:
  %ld173 = load ptr, ptr %acc.addr
  store ptr %ld173, ptr %res_slot172
  br label %case_merge38
case_default39:
  %ld174 = load i64, ptr %seed.addr
  %ar175 = mul i64 %ld174, 1664525
  %$t990.addr = alloca i64
  store i64 %ar175, ptr %$t990.addr
  %ld176 = load i64, ptr %$t990.addr
  %ar177 = add i64 %ld176, 1013904223
  %$t991.addr = alloca i64
  store i64 %ar177, ptr %$t991.addr
  %ld178 = load i64, ptr %$t991.addr
  %ar179 = srem i64 %ld178, 1000000
  %next.addr = alloca i64
  store i64 %ar179, ptr %next.addr
  %ld180 = load i64, ptr %n.addr
  %ar181 = sub i64 %ld180, 1
  %$t992.addr = alloca i64
  store i64 %ar181, ptr %$t992.addr
  %ld182 = load i64, ptr %next.addr
  %ar183 = srem i64 %ld182, 100000
  %$t993.addr = alloca i64
  store i64 %ar183, ptr %$t993.addr
  %hp184 = call ptr @march_alloc(i64 32)
  %tgp185 = getelementptr i8, ptr %hp184, i64 8
  store i32 1, ptr %tgp185, align 4
  %ld186 = load i64, ptr %$t993.addr
  %cv187 = inttoptr i64 %ld186 to ptr
  %fp188 = getelementptr i8, ptr %hp184, i64 16
  store ptr %cv187, ptr %fp188, align 8
  %ld189 = load ptr, ptr %acc.addr
  %fp190 = getelementptr i8, ptr %hp184, i64 24
  store ptr %ld189, ptr %fp190, align 8
  %$t994.addr = alloca ptr
  store ptr %hp184, ptr %$t994.addr
  %ld191 = load i64, ptr %$t992.addr
  %ld192 = load i64, ptr %next.addr
  %ld193 = load ptr, ptr %$t994.addr
  %cr194 = call ptr @gen_list(i64 %ld191, i64 %ld192, ptr %ld193)
  store ptr %cr194, ptr %res_slot172
  br label %case_merge38
case_merge38:
  %case_r195 = load ptr, ptr %res_slot172
  ret ptr %case_r195
}

define i64 @head(ptr %xs.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %ld196 = load ptr, ptr %xs.addr
  %res_slot197 = alloca ptr
  %tgp198 = getelementptr i8, ptr %ld196, i64 8
  %tag199 = load i32, ptr %tgp198, align 4
  switch i32 %tag199, label %case_default42 [
      i32 0, label %case_br43
      i32 1, label %case_br44
  ]
case_br43:
  %ld200 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld200)
  %cv201 = inttoptr i64 0 to ptr
  store ptr %cv201, ptr %res_slot197
  br label %case_merge41
case_br44:
  %fp202 = getelementptr i8, ptr %ld196, i64 16
  %fv203 = load ptr, ptr %fp202, align 8
  %$f995.addr = alloca ptr
  store ptr %fv203, ptr %$f995.addr
  %fp204 = getelementptr i8, ptr %ld196, i64 24
  %fv205 = load ptr, ptr %fp204, align 8
  %$f996.addr = alloca ptr
  store ptr %fv205, ptr %$f996.addr
  %freed206 = call i64 @march_decrc_freed(ptr %ld196)
  %freed_b207 = icmp ne i64 %freed206, 0
  br i1 %freed_b207, label %br_unique45, label %br_shared46
br_shared46:
  call void @march_incrc(ptr %fv205)
  br label %br_body47
br_unique45:
  br label %br_body47
br_body47:
  %ld208 = load ptr, ptr %$f995.addr
  %h.addr = alloca ptr
  store ptr %ld208, ptr %h.addr
  %ld209 = load i64, ptr %h.addr
  %cv210 = inttoptr i64 %ld209 to ptr
  store ptr %cv210, ptr %res_slot197
  br label %case_merge41
case_default42:
  unreachable
case_merge41:
  %case_r211 = load ptr, ptr %res_slot197
  %cv212 = ptrtoint ptr %case_r211 to i64
  ret i64 %cv212
}

define void @march_main() {
entry:
  %hp213 = call ptr @march_alloc(i64 16)
  %tgp214 = getelementptr i8, ptr %hp213, i64 8
  store i32 0, ptr %tgp214, align 4
  %$t997.addr = alloca ptr
  store ptr %hp213, ptr %$t997.addr
  %ld215 = load ptr, ptr %$t997.addr
  %cr216 = call ptr @gen_list(i64 10000, i64 42, ptr %ld215)
  %xs.addr = alloca ptr
  store ptr %cr216, ptr %xs.addr
  %ld217 = load ptr, ptr %xs.addr
  %cr218 = call ptr @mergesort(ptr %ld217)
  %sorted.addr = alloca ptr
  store ptr %cr218, ptr %sorted.addr
  %ld219 = load ptr, ptr %sorted.addr
  %cr220 = call i64 @head(ptr %ld219)
  %$t998.addr = alloca i64
  store i64 %cr220, ptr %$t998.addr
  %ld221 = load i64, ptr %$t998.addr
  %cr222 = call ptr @march_int_to_string(i64 %ld221)
  %$t999.addr = alloca ptr
  store ptr %cr222, ptr %$t999.addr
  %ld223 = load ptr, ptr %$t999.addr
  call void @march_println(ptr %ld223)
  ret void
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
