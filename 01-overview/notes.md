# Ch1 · 宏观全链路：源码 → IR → 优化 → 汇编

> 目标：建立一张「地图」。本章只要**看懂每个阶段在干什么**，细节后面章节再钻。
>
> 一键跑：`scripts/run.sh -- 'bash 01-overview/demo.sh'`

## 1. LLVM 是什么

LLVM 不是「一个编译器」，而是一套**编译器基础设施**。它把编译拆成三段，中间用一种统一的中间语言 **LLVM IR** 连接：

```
   C / C++ / Rust / Swift ...        各种语言的「前端」
            │  前端(Clang 等)：词法/语法/语义分析 → 生成 IR
            ▼
       ┌──────────────┐
       │  LLVM IR     │   ← 整个生态的「通用语」。我们重点学它。
       └──────────────┘
            │  中端(opt)：在 IR 上做与语言/硬件无关的优化（一个个 Pass）
            ▼
       ┌──────────────┐
       │  优化后的 IR │
       └──────────────┘
            │  后端(llc)：把 IR 翻译成具体 CPU 的汇编/机器码
            ▼
   x86-64 / ARM64 / RISC-V ...        各种硬件的「后端」
```

**为什么要有 IR？** 假设有 M 种语言、N 种 CPU。没有 IR 就要写 M×N 个编译器；有了 IR，只需 M 个前端 + N 个后端，全部优化都写在 IR 这一层复用。这就是 LLVM 影响力的核心。

> 对照 Python：CPython 也有「字节码」这层中间表示，思路类似。但 LLVM IR 是**静态类型、面向编译期优化**的，且有文本(`.ll`)/二进制(`.bc`)两种形态，可以直接读写。

## 2. 四个阶段实跑

我们的例子 [hello.c](hello.c)：一个极简的 `square`，一个带循环的 `sum_to`。

### 阶段 ②：前端 → 未优化 IR（`-O0`）

```bash
clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone hello.c -o hello.O0.ll
```
- `-emit-llvm`：让 clang 停在 IR，不继续往下编。
- `-S`：输出**文本** `.ll`（不加则输出二进制 `.bc`）。
- `-Xclang -disable-O0-optnone`：去掉 `optnone` 属性，否则 `opt` 会拒绝优化它（O0 默认给函数挂 optnone）。

`square` 的 -O0 IR——注意它**啥都往内存里塞**（`alloca`/`store`/`load`）：

```llvm
define dso_local i32 @square(i32 noundef %0) #0 {
  %2 = alloca i32, align 4        ; 在栈上开一个 int 槽位
  store i32 %0, ptr %2, align 4   ; 把参数 x 存进去
  %3 = load i32, ptr %2, align 4  ; 读出来
  %4 = load i32, ptr %2, align 4  ; 再读一次
  %5 = mul nsw i32 %3, %4         ; x * x   (nsw = 有符号不溢出，见 Ch6)
  ret i32 %5
}
```

这种「读写栈变量」的笨拙写法是前端的固定套路——它不操心优化，把活儿留给中端。

### 阶段 ③：中端优化（`opt -O2`）

```bash
opt -O2 -S hello.O0.ll -o hello.O2.ll
```

`square` 被压扁成一行——`mem2reg` 这个 Pass（Ch2/Ch4 细讲）把栈变量提升成了寄存器值：

```llvm
define dso_local i32 @square(i32 noundef %0) ... {
  %2 = mul nsw i32 %0, %0
  ret i32 %2
}
```

更震撼的是 `sum_to`——**整个循环消失了**。优化器证明了 `1+2+...+n` 等于闭式解，直接用一串算术算出来（中间用 `i33` 这种奇怪位宽防溢出）：

```llvm
define dso_local i32 @sum_to(i32 noundef %0) ... {
  %.not7 = icmp slt i32 %0, 1                 ; n < 1 ?
  br i1 %.not7, label %._crit_edge, label %.lr.ph.preheader
.lr.ph.preheader:
  %2  = shl nuw i32 %0, 1                      ; 2n
  ... 一串算术，本质是 n*(n+1)/2 ...
  br label %._crit_edge
._crit_edge:
  %.06.lcssa = phi i32 [ 0, %1 ], [ %11, %.lr.ph.preheader ]  ; phi：见 Ch2
  ret i32 %.06.lcssa
}
```

> 这就是「优化」的威力：O(n) 的循环变成 O(1) 的算式。**但优化必须保证语义不变**——万一算错了呢？这正是 Ch6/Ch7（Alive2）要回答的问题。

### 阶段 ④：后端 → 汇编（`llc`）

```bash
llc -O2 hello.O2.ll -o hello.s
```

本 VM 是 **ARM64**（Apple 芯片上的 Parallels），所以出的是 aarch64 汇编。`square` 干净利落：

```asm
square:
	mul	w0, w0, w0     ; 入参在 w0，结果也放 w0
	ret
```

`sum_to` 也没有循环跳转，就是几条算术：

```asm
sum_to:
	subs	w8, w0, #1
	b.lt	.LBB1_2        ; n<1 直接返回 0
	sub	w9, w0, #2
	umull	x8, w8, w9     ; 乘法
	lsr	x8, x8, #1     ; 右移 1 = 除以 2
	add	w8, w8, w0, lsl #1
	sub	w0, w8, #1
	ret
```

## 3. 一图总结这条命令链

```
hello.c ──clang -emit-llvm──▶ hello.O0.ll ──opt -O2──▶ hello.O2.ll ──llc──▶ hello.s
 (源码)        前端              (朴素 IR)     中端优化     (精炼 IR)    后端    (汇编)
```

平时 `clang -O2 hello.c -o a.out` 一条命令就全干了；这章只是把中间的 IR 摊开给你看。

## 4. 小结 / 自检

- [ ] 能说出 IR 在三段式架构里的作用，以及「M+N 而非 M×N」是什么意思。
- [ ] 知道 `-emit-llvm`、`-S`、`opt -O2`、`llc` 各自的输入输出。
- [ ] 能指出 -O0 IR 的「alloca/load/store」笨拙在哪，-O2 为什么能去掉。
- [ ] 理解了「优化必须保持语义」这个贯穿后续的主线。

下一章 [02-ir-basics](../02-ir-basics/) 正式精讲 IR 这门语言本身。
