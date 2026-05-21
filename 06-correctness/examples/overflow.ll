; overflow.ll —— 同一个表达式 (x + 1) > x，有无 nsw 标记，优化器待遇天差地别。
;
; 数学上 x+1 > x 似乎「永远成立」，但 i32 会回绕：
;   x = 2147483647 (INT_MAX) 时，x+1 回绕成 -2147483648，于是 x+1 > x 是 FALSE。
;
; - with_nsw : add nsw 承诺「不会有符号溢出」(否则结果是 poison)，
;              所以优化器可以放心把它折成 true。
; - without_nsw : 没有承诺，优化器【不能】折成 true（否则 x=INT_MAX 就错了）。

define i1 @with_nsw(i32 %x) {
  %a = add nsw i32 %x, 1
  %c = icmp sgt i32 %a, %x
  ret i1 %c
}

define i1 @without_nsw(i32 %x) {
  %a = add i32 %x, 1
  %c = icmp sgt i32 %a, %x
  ret i1 %c
}
