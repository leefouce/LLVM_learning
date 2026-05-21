; max_mem.ll — 同样是 max，但用 alloca/load/store（前端 -O0 的朴素风格，不是 SSA）。
; 它在栈上开一个变量 %r，往里写、再读出来——就像普通命令式语言里的局部变量。
;
; 跑 mem2reg 看它如何「升级」成 max.ll 那样的 phi 形式：
;   scripts/run.sh opt -passes=mem2reg -S 02-ir-basics/examples/max_mem.ll -o -

define i32 @max(i32 %a, i32 %b) {
entry:
  %r = alloca i32                  ; 在栈上分配一个 i32 槽位，%r 是它的地址(ptr)
  %cmp = icmp sgt i32 %a, %b
  br i1 %cmp, label %then, label %else

then:
  store i32 %a, ptr %r             ; *r = a
  br label %end

else:
  store i32 %b, ptr %r             ; *r = b
  br label %end

end:
  %v = load i32, ptr %r            ; v = *r
  ret i32 %v
}
