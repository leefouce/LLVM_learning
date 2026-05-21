; 验证：mul x, 8  →  shl x, 3   （Ch5 我们 Pass 做的事，丢掉了 nsw）
; 预期：Alive2 判定 correct（src 被 tgt 精化）。
define i32 @src(i32 %x) {
  %r = mul i32 %x, 8
  ret i32 %r
}
define i32 @tgt(i32 %x) {
  %r = shl i32 %x, 3
  ret i32 %r
}
