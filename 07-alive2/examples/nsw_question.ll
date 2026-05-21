; 回答 Ch6 的悬念：mul nsw x, 8  →  shl nsw x, 3   保留 nsw 到底对不对？
; 让 Alive2 给出确定答案（而不是靠猜）。
define i32 @src(i32 %x) {
  %r = mul nsw i32 %x, 8
  ret i32 %r
}
define i32 @tgt(i32 %x) {
  %r = shl nsw i32 %x, 3
  ret i32 %r
}
