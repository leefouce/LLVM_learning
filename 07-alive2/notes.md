# Ch7 · Alive2：形式化验证优化的正确性 ★

> Ch6 说「测试覆盖不了所有输入」。Alive2 用 **SMT 求解器**对**所有输入**一次性证明：
> 一个优化到底对不对，错在哪。这是本课程的落脚点，也正是你 final project 用的工具。
>
> 一键跑：`scripts/run.sh -- 'bash 07-alive2/demo.sh'`

## 1. 什么是 Translation Validation（翻译验证）

给定优化前 `src` 和优化后 `tgt` 两段 IR，Alive2 把它们各自编译成一个**逻辑公式**（用 SMT/位向量理论精确刻画整数、poison、UB、内存等语义），然后问求解器 **Z3**：

> 「是否存在某个输入，让 `tgt` 的行为不是 `src` 的合法精化？」

- 找不到这样的输入 → **Transformation seems to be correct!**（对所有输入都成立）
- 找到了 → **doesn't verify!**，并打印一个具体的**反例 (counterexample)**。

「精化 (refinement)」就是 Ch6 那个方向：`tgt` 允许比 `src` 更确定，但不能算出不同结果、也不能更 poison/更 UB。

## 2. alive-tv 的三种用法

VM 上的 `alive-tv`（与系统 LLVM 21 同版本）接受 `.ll`/`.bc`：

1. **单文件，含 `src` 和 `tgt` 两个函数** → 验证 `src` 是否被 `tgt` 精化。（最直观，本章主要用这个，也和在线版一致）
2. **两个文件** → 按**函数名**配对，验证「第二个文件的函数精化第一个的」。（适合「原始 vs Pass 输出」，见压轴）
3. **单文件、没有 src/tgt** → alive-tv 自己跑一遍类 `-O2`，验证优化后是否精化原版。（用来**抓 LLVM 自身的优化 bug**）

> 多对可加后缀：`src1/tgt1`、`src_foo/tgt_foo`……

## 3. 四个实例（demo 实跑结论）

### ① 正确：mul x,8 → shl x,3
```
Transformation seems to be correct!
```
我们 Ch5 Pass 做的事，确认对。

### ② 错误：(x+1) > x ⇒ true
```
Transformation doesn't verify!     ERROR: Value mismatch
Example:  i32 %x = #x7fffffff (2147483647)
Source: ... %c = 0      Target value: 1
```
Alive2 一针见血给出 `x = INT_MAX`：此时 src 算出 `false(0)`，tgt 却是 `true(1)`。**这就是 Ch6 那个边界**，自动找到。

### ③ Ch6 的悬念：mul nsw x,8 → shl nsw x,3 保留 nsw 行不行？
```
Transformation seems to be correct!
```
**确定答案：行。** `mul nsw` 与 `shl nsw` 在这里的 poison 条件等价。（凭眼睛猜不准，Alive2 给了证明级的确定性。）

### ④ 错误：mul x,8（无标记）→ shl nsw x,3（凭空加 nsw）
```
Transformation doesn't verify!     ERROR: Target is more poisonous than source
Example:  i32 %x = #x10000000 (268435456)
Source: %r = 0x80000000      Target: %r = poison
```
src 对所有 x 都有确定值（会回绕）；tgt 在溢出时变 **poison**。tgt「更 poison」→ 违反精化方向。这正是 Ch6 强调的：**加承诺要有依据，否则就是 miscompile**。

> 注意两类失败信息的区别：**Value mismatch**（算出了不同的值）vs **Target is more poisonous than source**（poison/未定义程度变大）。

## 4. 压轴：验证「我自己写的 Pass」

把 Ch5 的插件真实输出丢给 alive-tv（用法②，两文件按 `@f` 配对）：
```bash
opt -load-pass-plugin=05-custom-pass/build/libMul2Shl.so -passes=mul2shl \
    -S 07-alive2/examples/pass_input.ll -o /tmp/after.ll
alive-tv 07-alive2/examples/pass_input.ll /tmp/after.ll
#  → 1 correct transformations
```
这就是 Alive2 在工程上的真正用法：**改完优化器，跑一遍 translation validation，证明没把语义改坏**。LLVM 社区和你的 final project 都是这么用它的。

## 5. 现实的坑：SMT 对「乘法」很吃力

求解器擅长移位/加减/位运算，但**位向量乘法**开销巨大。本章压轴最初想验证两个乘法 `(x*8)+(y*16)`，即便把超时调到 120 秒（`--smt-to=120000`）也证不出来；换成**单个**乘法就秒过。

实用建议：
- **超时 ≠ 错误**。报告里会写 `failed-to-prove`（既非 correct 也非 incorrect）。
- 用 `--smt-to=<毫秒>` 调大 SMT 超时。
- 把例子**拆小/简化**到能证的规模（验证局部模式即可，别堆一大坨乘法）。

## 6. 在线版 alive2.llvm.org（零安装）

打开 **https://alive2.llvm.org/ce/** ——它是 Alive2 + Compiler Explorer：

- 在左边粘贴含 `@src`/`@tgt` 的 IR（和本章单文件用法一样），右边即时显示 correct / 反例。
- 或者写一段函数，让它对比 `-O2` 前后（对应用法③，看官方优化器有没有 bug）。
- 适合**快速试验、分享链接、不想碰 VM** 的场景。把本章 `examples/*.ll` 的内容贴进去会得到一样的结论。

> 在线版用的是较新的官方 LLVM，可能和 VM 的 21.1.6 有细微差别，但对这些小例子结论一致。

## 7. 小结 / 自检

- [ ] 能说清 Alive2 做什么：把 src/tgt 编成公式，让 Z3 对所有输入判定精化。
- [ ] 会三种用法（单文件 src/tgt、双文件按名配对、单文件 -O2 抓 bug）。
- [ ] 能读懂反例：定位反例输入、区分 Value mismatch 与 more poisonous。
- [ ] 会「改 Pass → 跑 alive-tv 验证输出」这条工程闭环。
- [ ] 知道 SMT 对乘法吃力，timeout≠错，会用 `--smt-to` / 简化例子。
- [ ] 会用在线版 alive2.llvm.org/ce 快速验证。

🎉 到此走完「IR → Pass → 验证」主线。回 [README](../README.md) 看如何用 `scripts/run.sh` 测试你自己的任何例子。
