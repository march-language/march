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


define i64 @collatz_steps(i64 %n.arg, i64 %acc.arg) {
entry:
  %n.addr = alloca i64
  store i64 %n.arg, ptr %n.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld1 = load i64, ptr %n.addr
  %cmp2 = icmp eq i64 %ld1, 1
  %ar3 = zext i1 %cmp2 to i64
  %$t351.addr = alloca i64
  store i64 %ar3, ptr %$t351.addr
  %ld4 = load i64, ptr %$t351.addr
  %res_slot5 = alloca ptr
  switch i64 %ld4, label %case_default2 [
      i64 1, label %case_br3
  ]
case_br3:
  %ld6 = load i64, ptr %acc.addr
  %cv7 = inttoptr i64 %ld6 to ptr
  store ptr %cv7, ptr %res_slot5
  br label %case_merge1
case_default2:
  %ld8 = load i64, ptr %n.addr
  %ar9 = srem i64 %ld8, 2
  %$t352.addr = alloca i64
  store i64 %ar9, ptr %$t352.addr
  %ld10 = load i64, ptr %$t352.addr
  %cmp11 = icmp eq i64 %ld10, 0
  %ar12 = zext i1 %cmp11 to i64
  %$t353.addr = alloca i64
  store i64 %ar12, ptr %$t353.addr
  %ld13 = load i64, ptr %$t353.addr
  %res_slot14 = alloca ptr
  switch i64 %ld13, label %case_default5 [
      i64 1, label %case_br6
  ]
case_br6:
  %ld15 = load i64, ptr %n.addr
  %ar16 = sdiv i64 %ld15, 2
  %$t354.addr = alloca i64
  store i64 %ar16, ptr %$t354.addr
  %ld17 = load i64, ptr %acc.addr
  %ar18 = add i64 %ld17, 1
  %$t355.addr = alloca i64
  store i64 %ar18, ptr %$t355.addr
  %ld19 = load i64, ptr %$t354.addr
  %ld20 = load i64, ptr %$t355.addr
  %cr21 = call i64 @collatz_steps(i64 %ld19, i64 %ld20)
  %cv22 = inttoptr i64 %cr21 to ptr
  store ptr %cv22, ptr %res_slot14
  br label %case_merge4
case_default5:
  %ld23 = load i64, ptr %n.addr
  %ar24 = mul i64 3, %ld23
  %$t356.addr = alloca i64
  store i64 %ar24, ptr %$t356.addr
  %ld25 = load i64, ptr %$t356.addr
  %ar26 = add i64 %ld25, 1
  %$t357.addr = alloca i64
  store i64 %ar26, ptr %$t357.addr
  %ld27 = load i64, ptr %acc.addr
  %ar28 = add i64 %ld27, 1
  %$t358.addr = alloca i64
  store i64 %ar28, ptr %$t358.addr
  %ld29 = load i64, ptr %$t357.addr
  %ld30 = load i64, ptr %$t358.addr
  %cr31 = call i64 @collatz_steps(i64 %ld29, i64 %ld30)
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

define ptr @range_acc(i64 %lo.arg, i64 %hi.arg, ptr %acc.arg) {
entry:
  %lo.addr = alloca i64
  store i64 %lo.arg, ptr %lo.addr
  %hi.addr = alloca i64
  store i64 %hi.arg, ptr %hi.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld36 = load i64, ptr %lo.addr
  %ld37 = load i64, ptr %hi.addr
  %cmp38 = icmp sgt i64 %ld36, %ld37
  %ar39 = zext i1 %cmp38 to i64
  %$t359.addr = alloca i64
  store i64 %ar39, ptr %$t359.addr
  %ld40 = load i64, ptr %$t359.addr
  %res_slot41 = alloca ptr
  switch i64 %ld40, label %case_default8 [
      i64 1, label %case_br9
  ]
case_br9:
  %ld42 = load ptr, ptr %acc.addr
  store ptr %ld42, ptr %res_slot41
  br label %case_merge7
case_default8:
  %ld43 = load i64, ptr %hi.addr
  %ar44 = sub i64 %ld43, 1
  %$t360.addr = alloca i64
  store i64 %ar44, ptr %$t360.addr
  %hp45 = call ptr @march_alloc(i64 32)
  %tgp46 = getelementptr i8, ptr %hp45, i64 8
  store i32 1, ptr %tgp46, align 4
  %ld47 = load i64, ptr %hi.addr
  %cv48 = inttoptr i64 %ld47 to ptr
  %fp49 = getelementptr i8, ptr %hp45, i64 16
  store ptr %cv48, ptr %fp49, align 8
  %ld50 = load ptr, ptr %acc.addr
  %fp51 = getelementptr i8, ptr %hp45, i64 24
  store ptr %ld50, ptr %fp51, align 8
  %$t361.addr = alloca ptr
  store ptr %hp45, ptr %$t361.addr
  %ld52 = load i64, ptr %lo.addr
  %ld53 = load i64, ptr %$t360.addr
  %ld54 = load ptr, ptr %$t361.addr
  %cr55 = call ptr @range_acc(i64 %ld52, i64 %ld53, ptr %ld54)
  store ptr %cr55, ptr %res_slot41
  br label %case_merge7
case_merge7:
  %case_r56 = load ptr, ptr %res_slot41
  ret ptr %case_r56
}

define i64 @sum(ptr %xs.arg, i64 %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca i64
  store i64 %acc.arg, ptr %acc.addr
  %ld57 = load ptr, ptr %xs.addr
  %res_slot58 = alloca ptr
  %tgp59 = getelementptr i8, ptr %ld57, i64 8
  %tag60 = load i32, ptr %tgp59, align 4
  switch i32 %tag60, label %case_default11 [
      i32 0, label %case_br12
      i32 1, label %case_br13
  ]
case_br12:
  %ld61 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld61)
  %ld62 = load i64, ptr %acc.addr
  %cv63 = inttoptr i64 %ld62 to ptr
  store ptr %cv63, ptr %res_slot58
  br label %case_merge10
case_br13:
  %fp64 = getelementptr i8, ptr %ld57, i64 16
  %fv65 = load ptr, ptr %fp64, align 8
  %x.addr = alloca ptr
  store ptr %fv65, ptr %x.addr
  %fp66 = getelementptr i8, ptr %ld57, i64 24
  %fv67 = load ptr, ptr %fp66, align 8
  %rest.addr = alloca ptr
  store ptr %fv67, ptr %rest.addr
  %ld68 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld68)
  %ld69 = load i64, ptr %acc.addr
  %ld70 = load i64, ptr %x.addr
  %ar71 = add i64 %ld69, %ld70
  %$t363.addr = alloca i64
  store i64 %ar71, ptr %$t363.addr
  %ld72 = load ptr, ptr %rest.addr
  %ld73 = load i64, ptr %$t363.addr
  %cr74 = call i64 @sum(ptr %ld72, i64 %ld73)
  %cv75 = inttoptr i64 %cr74 to ptr
  store ptr %cv75, ptr %res_slot58
  br label %case_merge10
case_default11:
  unreachable
case_merge10:
  %case_r76 = load ptr, ptr %res_slot58
  %cv77 = ptrtoint ptr %case_r76 to i64
  ret i64 %cv77
}

define ptr @map_collatz(ptr %xs.arg, ptr %acc.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %acc.addr = alloca ptr
  store ptr %acc.arg, ptr %acc.addr
  %ld78 = load ptr, ptr %xs.addr
  %res_slot79 = alloca ptr
  %tgp80 = getelementptr i8, ptr %ld78, i64 8
  %tag81 = load i32, ptr %tgp80, align 4
  switch i32 %tag81, label %case_default15 [
      i32 0, label %case_br16
      i32 1, label %case_br17
  ]
case_br16:
  %ld82 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld82)
  %ld83 = load ptr, ptr %acc.addr
  store ptr %ld83, ptr %res_slot79
  br label %case_merge14
case_br17:
  %fp84 = getelementptr i8, ptr %ld78, i64 16
  %fv85 = load ptr, ptr %fp84, align 8
  %x.addr = alloca ptr
  store ptr %fv85, ptr %x.addr
  %fp86 = getelementptr i8, ptr %ld78, i64 24
  %fv87 = load ptr, ptr %fp86, align 8
  %rest.addr = alloca ptr
  store ptr %fv87, ptr %rest.addr
  %ld88 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld88)
  %ld89 = load i64, ptr %x.addr
  %cr90 = call i64 @collatz_steps(i64 %ld89, i64 0)
  %$t364.addr = alloca i64
  store i64 %cr90, ptr %$t364.addr
  %hp91 = call ptr @march_alloc(i64 32)
  %tgp92 = getelementptr i8, ptr %hp91, i64 8
  store i32 1, ptr %tgp92, align 4
  %ld93 = load i64, ptr %$t364.addr
  %cv94 = inttoptr i64 %ld93 to ptr
  %fp95 = getelementptr i8, ptr %hp91, i64 16
  store ptr %cv94, ptr %fp95, align 8
  %ld96 = load ptr, ptr %acc.addr
  %fp97 = getelementptr i8, ptr %hp91, i64 24
  store ptr %ld96, ptr %fp97, align 8
  %$t365.addr = alloca ptr
  store ptr %hp91, ptr %$t365.addr
  %ld98 = load ptr, ptr %rest.addr
  %ld99 = load ptr, ptr %$t365.addr
  %cr100 = call ptr @map_collatz(ptr %ld98, ptr %ld99)
  store ptr %cr100, ptr %res_slot79
  br label %case_merge14
case_default15:
  unreachable
case_merge14:
  %case_r101 = load ptr, ptr %res_slot79
  ret ptr %case_r101
}

define i64 @par_map_inner(ptr %xs.arg, i64 %chunk_size.arg, ptr %chunk_acc.arg, i64 %chunk_left.arg) {
entry:
  %xs.addr = alloca ptr
  store ptr %xs.arg, ptr %xs.addr
  %chunk_size.addr = alloca i64
  store i64 %chunk_size.arg, ptr %chunk_size.addr
  %chunk_acc.addr = alloca ptr
  store ptr %chunk_acc.arg, ptr %chunk_acc.addr
  %chunk_left.addr = alloca i64
  store i64 %chunk_left.arg, ptr %chunk_left.addr
  %ld102 = load ptr, ptr %xs.addr
  %res_slot103 = alloca ptr
  %tgp104 = getelementptr i8, ptr %ld102, i64 8
  %tag105 = load i32, ptr %tgp104, align 4
  switch i32 %tag105, label %case_default19 [
      i32 0, label %case_br20
      i32 1, label %case_br21
  ]
case_br20:
  %ld106 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld106)
  %ld107 = load i64, ptr %chunk_left.addr
  %ld108 = load i64, ptr %chunk_size.addr
  %cmp109 = icmp eq i64 %ld107, %ld108
  %ar110 = zext i1 %cmp109 to i64
  %$t366.addr = alloca i64
  store i64 %ar110, ptr %$t366.addr
  %ld111 = load i64, ptr %$t366.addr
  %res_slot112 = alloca ptr
  switch i64 %ld111, label %case_default23 [
      i64 1, label %case_br24
  ]
case_br24:
  %cv113 = inttoptr i64 0 to ptr
  store ptr %cv113, ptr %res_slot112
  br label %case_merge22
case_default23:
  %hp114 = call ptr @march_alloc(i64 32)
  %tgp115 = getelementptr i8, ptr %hp114, i64 8
  store i32 0, ptr %tgp115, align 4
  %fp116 = getelementptr i8, ptr %hp114, i64 16
  store ptr @$lam367$apply, ptr %fp116, align 8
  %ld117 = load ptr, ptr %chunk_acc.addr
  %fp118 = getelementptr i8, ptr %hp114, i64 24
  store ptr %ld117, ptr %fp118, align 8
  %$t370.addr = alloca ptr
  store ptr %hp114, ptr %$t370.addr
  %ld119 = load ptr, ptr %$t370.addr
  %fp120 = getelementptr i8, ptr %ld119, i64 16
  %fv121 = load ptr, ptr %fp120, align 8
  %tsres122 = call i64 %fv121(ptr %ld119, i64 0)
  %hp123 = call ptr @march_alloc(i64 24)
  %tgp124 = getelementptr i8, ptr %hp123, i64 8
  store i32 0, ptr %tgp124, align 4
  %fp125 = getelementptr i8, ptr %hp123, i64 16
  store i64 %tsres122, ptr %fp125, align 8
  %t.addr = alloca ptr
  store ptr %hp123, ptr %t.addr
  %ld126 = load ptr, ptr %t.addr
  %fp127 = getelementptr i8, ptr %ld126, i64 16
  %fv128 = load i64, ptr %fp127, align 8
  %cv129 = inttoptr i64 %fv128 to ptr
  store ptr %cv129, ptr %res_slot112
  br label %case_merge22
case_merge22:
  %case_r130 = load ptr, ptr %res_slot112
  store ptr %case_r130, ptr %res_slot103
  br label %case_merge18
case_br21:
  %fp131 = getelementptr i8, ptr %ld102, i64 16
  %fv132 = load ptr, ptr %fp131, align 8
  %h.addr = alloca ptr
  store ptr %fv132, ptr %h.addr
  %fp133 = getelementptr i8, ptr %ld102, i64 24
  %fv134 = load ptr, ptr %fp133, align 8
  %tl.addr = alloca ptr
  store ptr %fv134, ptr %tl.addr
  %ld135 = load ptr, ptr %xs.addr
  call void @march_decrc(ptr %ld135)
  %ld136 = load i64, ptr %chunk_left.addr
  %cmp137 = icmp eq i64 %ld136, 0
  %ar138 = zext i1 %cmp137 to i64
  %$t371.addr = alloca i64
  store i64 %ar138, ptr %$t371.addr
  %ld139 = load i64, ptr %$t371.addr
  %res_slot140 = alloca ptr
  switch i64 %ld139, label %case_default26 [
      i64 1, label %case_br27
  ]
case_br27:
  %hp141 = call ptr @march_alloc(i64 32)
  %tgp142 = getelementptr i8, ptr %hp141, i64 8
  store i32 0, ptr %tgp142, align 4
  %fp143 = getelementptr i8, ptr %hp141, i64 16
  store ptr @$lam372$apply, ptr %fp143, align 8
  %ld144 = load ptr, ptr %chunk_acc.addr
  %fp145 = getelementptr i8, ptr %hp141, i64 24
  store ptr %ld144, ptr %fp145, align 8
  %$t375.addr = alloca ptr
  store ptr %hp141, ptr %$t375.addr
  %ld146 = load ptr, ptr %$t375.addr
  %fp147 = getelementptr i8, ptr %ld146, i64 16
  %fv148 = load ptr, ptr %fp147, align 8
  %tsres149 = call i64 %fv148(ptr %ld146, i64 0)
  %hp150 = call ptr @march_alloc(i64 24)
  %tgp151 = getelementptr i8, ptr %hp150, i64 8
  store i32 0, ptr %tgp151, align 4
  %fp152 = getelementptr i8, ptr %hp150, i64 16
  store i64 %tsres149, ptr %fp152, align 8
  %t_1.addr = alloca ptr
  store ptr %hp150, ptr %t_1.addr
  %hp153 = call ptr @march_alloc(i64 16)
  %tgp154 = getelementptr i8, ptr %hp153, i64 8
  store i32 0, ptr %tgp154, align 4
  %$t376.addr = alloca ptr
  store ptr %hp153, ptr %$t376.addr
  %hp155 = call ptr @march_alloc(i64 32)
  %tgp156 = getelementptr i8, ptr %hp155, i64 8
  store i32 1, ptr %tgp156, align 4
  %ld157 = load i64, ptr %h.addr
  %cv158 = inttoptr i64 %ld157 to ptr
  %fp159 = getelementptr i8, ptr %hp155, i64 16
  store ptr %cv158, ptr %fp159, align 8
  %ld160 = load ptr, ptr %$t376.addr
  %fp161 = getelementptr i8, ptr %hp155, i64 24
  store ptr %ld160, ptr %fp161, align 8
  %$t377.addr = alloca ptr
  store ptr %hp155, ptr %$t377.addr
  %ld162 = load i64, ptr %chunk_size.addr
  %ar163 = sub i64 %ld162, 1
  %$t378.addr = alloca i64
  store i64 %ar163, ptr %$t378.addr
  %ld164 = load ptr, ptr %tl.addr
  %ld165 = load i64, ptr %chunk_size.addr
  %ld166 = load ptr, ptr %$t377.addr
  %ld167 = load i64, ptr %$t378.addr
  %cr168 = call i64 @par_map_inner(ptr %ld164, i64 %ld165, ptr %ld166, i64 %ld167)
  %rest_sum.addr = alloca i64
  store i64 %cr168, ptr %rest_sum.addr
  %ld169 = load ptr, ptr %t_1.addr
  %fp170 = getelementptr i8, ptr %ld169, i64 16
  %fv171 = load i64, ptr %fp170, align 8
  %chunk_sum.addr = alloca i64
  store i64 %fv171, ptr %chunk_sum.addr
  %ld172 = load i64, ptr %chunk_sum.addr
  %ld173 = load i64, ptr %rest_sum.addr
  %ar174 = add i64 %ld172, %ld173
  %cv175 = inttoptr i64 %ar174 to ptr
  store ptr %cv175, ptr %res_slot140
  br label %case_merge25
case_default26:
  %hp176 = call ptr @march_alloc(i64 32)
  %tgp177 = getelementptr i8, ptr %hp176, i64 8
  store i32 1, ptr %tgp177, align 4
  %ld178 = load i64, ptr %h.addr
  %cv179 = inttoptr i64 %ld178 to ptr
  %fp180 = getelementptr i8, ptr %hp176, i64 16
  store ptr %cv179, ptr %fp180, align 8
  %ld181 = load ptr, ptr %chunk_acc.addr
  %fp182 = getelementptr i8, ptr %hp176, i64 24
  store ptr %ld181, ptr %fp182, align 8
  %$t379.addr = alloca ptr
  store ptr %hp176, ptr %$t379.addr
  %ld183 = load i64, ptr %chunk_left.addr
  %ar184 = sub i64 %ld183, 1
  %$t380.addr = alloca i64
  store i64 %ar184, ptr %$t380.addr
  %ld185 = load ptr, ptr %tl.addr
  %ld186 = load i64, ptr %chunk_size.addr
  %ld187 = load ptr, ptr %$t379.addr
  %ld188 = load i64, ptr %$t380.addr
  %cr189 = call i64 @par_map_inner(ptr %ld185, i64 %ld186, ptr %ld187, i64 %ld188)
  %cv190 = inttoptr i64 %cr189 to ptr
  store ptr %cv190, ptr %res_slot140
  br label %case_merge25
case_merge25:
  %case_r191 = load ptr, ptr %res_slot140
  store ptr %case_r191, ptr %res_slot103
  br label %case_merge18
case_default19:
  unreachable
case_merge18:
  %case_r192 = load ptr, ptr %res_slot103
  %cv193 = ptrtoint ptr %case_r192 to i64
  ret i64 %cv193
}

define void @march_main() {
entry:
  %n.addr = alloca i64
  store i64 10000, ptr %n.addr
  %chunk_size.addr = alloca i64
  store i64 1000, ptr %chunk_size.addr
  %lo_i4.addr = alloca i64
  store i64 1, ptr %lo_i4.addr
  %ld194 = load i64, ptr %n.addr
  %hi_i5.addr = alloca i64
  store i64 %ld194, ptr %hi_i5.addr
  %hp195 = call ptr @march_alloc(i64 16)
  %tgp196 = getelementptr i8, ptr %hp195, i64 8
  store i32 0, ptr %tgp196, align 4
  %$t362_i6.addr = alloca ptr
  store ptr %hp195, ptr %$t362_i6.addr
  %ld197 = load i64, ptr %lo_i4.addr
  %ld198 = load i64, ptr %hi_i5.addr
  %ld199 = load ptr, ptr %$t362_i6.addr
  %cr200 = call ptr @range_acc(i64 %ld197, i64 %ld198, ptr %ld199)
  %xs.addr = alloca ptr
  store ptr %cr200, ptr %xs.addr
  %ld201 = load ptr, ptr %xs.addr
  %xs_i1.addr = alloca ptr
  store ptr %ld201, ptr %xs_i1.addr
  %ld202 = load i64, ptr %chunk_size.addr
  %chunk_size_i2.addr = alloca i64
  store i64 %ld202, ptr %chunk_size_i2.addr
  %hp203 = call ptr @march_alloc(i64 16)
  %tgp204 = getelementptr i8, ptr %hp203, i64 8
  store i32 0, ptr %tgp204, align 4
  %$t381_i3.addr = alloca ptr
  store ptr %hp203, ptr %$t381_i3.addr
  %ld205 = load ptr, ptr %xs_i1.addr
  %ld206 = load i64, ptr %chunk_size_i2.addr
  %ld207 = load ptr, ptr %$t381_i3.addr
  %ld208 = load i64, ptr %chunk_size_i2.addr
  %cr209 = call i64 @par_map_inner(ptr %ld205, i64 %ld206, ptr %ld207, i64 %ld208)
  %total.addr = alloca i64
  store i64 %cr209, ptr %total.addr
  %ld210 = load i64, ptr %total.addr
  %cr211 = call ptr @march_int_to_string(i64 %ld210)
  %$t382.addr = alloca ptr
  store ptr %cr211, ptr %$t382.addr
  %ld212 = load ptr, ptr %$t382.addr
  call void @march_println(ptr %ld212)
  ret void
}

define i64 @$lam367$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld213 = load ptr, ptr %$clo.addr
  %fp214 = getelementptr i8, ptr %ld213, i64 24
  %fv215 = load ptr, ptr %fp214, align 8
  %chunk_acc.addr = alloca ptr
  store ptr %fv215, ptr %chunk_acc.addr
  %hp216 = call ptr @march_alloc(i64 16)
  %tgp217 = getelementptr i8, ptr %hp216, i64 8
  store i32 0, ptr %tgp217, align 4
  %$t368.addr = alloca ptr
  store ptr %hp216, ptr %$t368.addr
  %ld218 = load ptr, ptr %chunk_acc.addr
  %ld219 = load ptr, ptr %$t368.addr
  %cr220 = call ptr @map_collatz(ptr %ld218, ptr %ld219)
  %$t369.addr = alloca ptr
  store ptr %cr220, ptr %$t369.addr
  %ld221 = load ptr, ptr %$t369.addr
  %cr222 = call i64 @sum(ptr %ld221, i64 0)
  ret i64 %cr222
}

define i64 @$lam372$apply(ptr %$clo.arg, i64 %x.arg) {
entry:
  %$clo.addr = alloca ptr
  store ptr %$clo.arg, ptr %$clo.addr
  %x.addr = alloca i64
  store i64 %x.arg, ptr %x.addr
  %ld223 = load ptr, ptr %$clo.addr
  %fp224 = getelementptr i8, ptr %ld223, i64 24
  %fv225 = load ptr, ptr %fp224, align 8
  %chunk_acc.addr = alloca ptr
  store ptr %fv225, ptr %chunk_acc.addr
  %hp226 = call ptr @march_alloc(i64 16)
  %tgp227 = getelementptr i8, ptr %hp226, i64 8
  store i32 0, ptr %tgp227, align 4
  %$t373.addr = alloca ptr
  store ptr %hp226, ptr %$t373.addr
  %ld228 = load ptr, ptr %chunk_acc.addr
  %ld229 = load ptr, ptr %$t373.addr
  %cr230 = call ptr @map_collatz(ptr %ld228, ptr %ld229)
  %$t374.addr = alloca ptr
  store ptr %cr230, ptr %$t374.addr
  %ld231 = load ptr, ptr %$t374.addr
  %cr232 = call i64 @sum(ptr %ld231, i64 0)
  ret i64 %cr232
}

define i32 @main() {
entry:
  call void @march_main()
  ret i32 0
}
