; max.ll — 手写的 SSA 形式：求两个有符号 i32 的较大者。
; 这是一个完整的 LLVM IR「模块」，麻雀虽小五脏俱全：
;   module ⊃ function ⊃ basic block ⊃ instruction
;
; 校验：scripts/run.sh opt -passes=verify -disable-output 02-ir-basics/examples/max.ll

define i32 @max(i32 %a, i32 %b) {        ; 一个函数：返回 i32，两个 i32 参数
entry:                                   ; 基本块(basic block) 1，名叫 entry
  %cmp = icmp sgt i32 %a, %b             ; %cmp:i1 = (a > b)，sgt=有符号大于
  br i1 %cmp, label %then, label %else   ; 条件跳转：真去 then，假去 else

then:                                    ; 基本块 2
  br label %end                          ; 无条件跳到 end

else:                                    ; 基本块 3
  br label %end

end:                                     ; 基本块 4：两条路在此汇合
  ; phi：根据「从哪个块跳来」选值。从 then 来取 %a，从 else 来取 %b。
  ; SSA 规定每个变量只赋值一次，所以汇合点必须用 phi 来「合并」不同来路的值。
  %r = phi i32 [ %a, %then ], [ %b, %else ]
  ret i32 %r
}
