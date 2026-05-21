; 验证：把 (x+1) > x  化简成  true   —— 一个【错误】的优化（无 nsw 时）。
; 预期：Alive2 给出反例 x = 2147483647 (INT_MAX)，此时 src 为 false 而 tgt 为 true。
define i1 @src(i32 %x) {
  %a = add i32 %x, 1
  %c = icmp sgt i32 %a, %x
  ret i1 %c
}
define i1 @tgt(i32 %x) {
  ret i1 true
}
