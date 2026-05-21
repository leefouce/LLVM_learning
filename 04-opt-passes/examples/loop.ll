; loop.ll —— 循环优化素材。
; %inv = x*y 在每次迭代里都一样（循环不变量）。
; licm (Loop Invariant Code Motion) 应把它「提升」到循环外，只算一次。
define i32 @f(i32 %x, i32 %y, i32 %n) {
entry:
  br label %loop
loop:
  %i   = phi i32 [ 0, %entry ], [ %i.next, %loop ]
  %acc = phi i32 [ 0, %entry ], [ %acc.next, %loop ]
  %inv = mul i32 %x, %y                 ; 循环不变 → 应被 licm 提到 entry/preheader
  %acc.next = add i32 %acc, %inv
  %i.next = add i32 %i, 1
  %c = icmp slt i32 %i.next, %n
  br i1 %c, label %loop, label %exit
exit:
  ret i32 %acc
}
