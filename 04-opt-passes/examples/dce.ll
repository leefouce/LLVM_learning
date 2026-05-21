; dce (Dead Code Elimination) —— 删除「算了但没人用」的指令。
; %dead 的结果从未被使用，应被删掉。
define i32 @f(i32 %x) {
  %dead = mul i32 %x, %x     ; 没人用 → 死代码
  %r = add i32 %x, 1
  ret i32 %r
}
