# Ch6 · 优化为什么会出错（UB / poison / undef / nsw）

> 这一章不写新工具，只讲清一件事：**「优化」必须对所有输入都保持语义**，
> 而 IR 里有一堆「陷阱值」让这件事变微妙。它是通往 Ch7（Alive2）的桥。
>
> 一键跑：`scripts/run.sh -- 'bash 06-correctness/demo.sh'`

## 1. 正确的优化 = 对「所有输入」都不改变行为

一个优化（把 IR 从 A 改成 B）正确，**不是**「我跑了几个例子结果一样」，而是：

> 对**任意**输入，B 的可观察行为都和 A 一致（更精确地说是 **refinement 精化**：B 允许比 A *更确定*，但不能*更不确定*，也不能算出不同的结果）。

只要存在**一个**反例输入让 B 与 A 不同，这个优化就是错的。而边界输入（INT_MAX、0、空指针、移位量过大……）正是 bug 的温床。**测试几乎不可能覆盖全部输入**——这就是为什么需要 Ch7 的形式化验证。

## 2. 实例：(x + 1) > x 能不能化简成 true？

数学直觉说「永远成立」。但 i32 会**回绕**：`x = INT_MAX (2147483647)` 时，`x+1` 变成 `INT_MIN`，于是 `x+1 > x` 是 **false**。

看优化器多小心（demo 实跑，[examples/overflow.ll](examples/overflow.ll) 跑 `instcombine`）：

```llvm
; 有 nsw：                            ; 无 nsw：
define i1 @with_nsw(i32 %x) {         define i1 @without_nsw(i32 %x) {
  ret i1 true                           %c = icmp ne i32 %x, 2147483647
}                                         ret i1 %c
                                        }
```

- **`with_nsw`** 折成了 `true`：因为 `add nsw` **承诺**不会溢出。
- **`without_nsw`** 优化器**不敢**折成 `true`，而是精确算出 `x != INT_MAX`——把那个唯一的反例边界保留了下来。

这说明优化器的每一步化简，背后都依赖 IR 上的「承诺」与精确的整数语义。搞错一点就是 miscompile。

## 3. 三个「陷阱值」与几个「承诺标记」

### UB（Undefined Behavior，未定义行为）
程序做了语言禁止的事（有符号溢出、越界访问、除以 0、读未初始化…）。一旦发生 UB，**整个程序**的行为就「随便」了——编译器**假设 UB 永不发生**，并据此优化。这正是 C/C++ 里很多「诡异优化」的根源。

### poison
一种「**延迟的错误值**」。违反某个承诺（见下）不会立刻崩，而是产生 poison；poison 沿数据流**传染**（用 poison 算出来的还是 poison）。如果 poison 最终影响了可观察行为（比如决定一个分支、被 store 出去），那就是 UB。
- 好处：让优化器能「假装乐观」地变换，把真正的炸点推迟到真用到的时候。

### undef
一个「**未指定的值**」，可以是该类型的任意位模式，而且**每次读甚至可以不同**。比 poison 弱。现代 LLVM 正逐步用 poison + `freeze` 取代 undef。

### 承诺标记：nsw / nuw / inbounds / exact …
前端给指令贴的「保证」，优化器据此放手优化；一旦违反，结果是 **poison**：
| 标记 | 贴在 | 含义（违反则 poison） |
|----|----|----|
| `nsw` | add/sub/mul/shl | No Signed Wrap：保证无有符号溢出 |
| `nuw` | add/sub/mul/shl | No Unsigned Wrap：保证无无符号溢出 |
| `inbounds` | getelementptr | 保证地址没越出对象 |
| `exact` | udiv/sdiv/lshr… | 保证除/移没有余数被丢 |

### freeze
`%y = freeze %x`：若 `%x` 是 poison/undef，`freeze` 把它**钉成某个具体（任意但固定）的值**，从此 `%y` 不再传染。用来在需要「确定值」的地方安全地「冻结」不确定性。

## 4. 回看 Ch5 我们写的 Pass

Mul2Shl 把 `mul x, 8` → `shl x, 3` 时，**故意丢掉了 nsw/nuw**。这是**保守且安全**的：去掉承诺只会让结果「更不挑剔」，不会引入新的错误行为（符合精化方向）。

那「图省事」保留、写成 `shl nsw x, 3` 行不行？`mul nsw x, 8` 与 `shl nsw x, 3` 的 poison 条件**真的一样吗**？凭眼睛和几个例子说不准。下一章用 Alive2 给出**确定答案**。

## 5. 小结 / 自检

- [ ] 能说清「正确优化 = 对所有输入保持语义（精化方向）」，一个反例即推翻。
- [ ] 能分别解释 UB / poison / undef，以及它们的强弱关系。
- [ ] 知道 nsw/nuw/inbounds/exact 是「承诺」，违反即产生 poison。
- [ ] 理解 freeze 的作用（钉死不确定值、阻断传染）。
- [ ] 体会到「测试不够、需要形式化验证」——正是 Ch7 的动机。

下一章 [07-alive2](../07-alive2/)：用 **Alive2** 形式化验证优化（含上面 nsw 的悬念、以及我们 Ch5 的 Pass）。
