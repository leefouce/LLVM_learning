# Ch2 · LLVM IR 语言精讲 ★

> 本章是地基。读完你应能**看懂、并大致写出**一段 LLVM IR。
>
> 一键跑：`scripts/run.sh -- 'bash 02-ir-basics/demo.sh'`
> 例子在 [examples/](examples/)。

## 1. IR 的三种形态

同一份 IR，三种等价表示，随时互转：

| 形态 | 后缀 | 谁用 | 工具 |
|----|----|----|----|
| 文本（给人读） | `.ll` | 我们学习、调试 | `llvm-dis` 生成 |
| 二进制（给机器） | `.bc` | 工具间传递、省空间 | `llvm-as` 生成 |
| 内存对象 | — | C++/Python API 操作 | Ch3/Ch5 |

demo 里 `llvm-as max.ll -o max.bc`（文本→二进制，1468 字节）再 `llvm-dis` 反汇编回来，内容不变。**本课程只读写 `.ll`**。

## 2. 结构层级：Module ⊃ Function ⊃ BasicBlock ⊃ Instruction

看 [examples/max.ll](examples/max.ll)：

- **Module（模块）**：一个 `.ll` 文件 = 一个模块。装着全局变量、函数、元数据。约等于一个「编译单元」。
- **Function（函数）**：`define i32 @max(i32 %a, i32 %b) { ... }`。`@` 前缀 = 全局符号。
- **BasicBlock（基本块）**：以 label 开头（`entry:`、`then:`…）的一段指令。**关键性质**：执行**只能从第一条进、最后一条出**，中间不会跳进跳出。每个块**必须**以一条「终结指令」结尾（`br` / `ret` / `switch` …）。
- **Instruction（指令）**：每行一条。`%` 前缀 = 局部值（函数内可见）。

```
@max ─┬─ entry:  icmp / br
      ├─ then:   br
      ├─ else:   br
      └─ end:    phi / ret
```

> 把「基本块 + 块间的 br 边」连起来，就是**控制流图 (CFG)**。所有优化分析都围着 CFG 转。

## 3. SSA：每个值只赋值一次

这是 LLVM IR 最核心的设计，也是和 Python 变量最不一样的地方。

**SSA (Static Single Assignment)**：每个 `%x` 在整个函数里**只被赋值一次**。没有「重新赋值」。
- 好处：`%5 = mul %3, %4` 一旦定义，`%5` 的值永远确定 → 优化器不必担心「这变量后来被改了吗」，分析极大简化。
- 代价：遇到分支汇合怎么办？比如 `r` 在 then 里 = a、在 else 里 = b，到 end 该用哪个？

### phi 指令：SSA 处理「分支汇合」的办法

```llvm
end:
  %r = phi i32 [ %a, %then ], [ %b, %else ]
```
读法：**「如果是从 `then` 块跳来的，`%r` 取 `%a`；从 `else` 来的，取 `%b`」**。phi 必须放在基本块**最前面**，是一种「编译期的多路选择」，不对应任何真实机器指令（后端会用寄存器/跳转实现）。

> phi 是初学者最大的坎。记住一句话：**phi = 「看你从哪条边来，我就给哪个值」**。

## 4. SSA 从哪来？mem2reg（本章高潮）

前端（`clang -O0`）才不会费心生成 phi。它的套路是：**每个局部变量都 `alloca` 到栈上，用 `store`/`load` 读写**——见 [examples/max_mem.ll](examples/max_mem.ll)：

```llvm
%r = alloca i32        ; 栈上开个槽
store i32 %a, ptr %r   ; then: *r = a
store i32 %b, ptr %r   ; else: *r = b
%v = load i32, ptr %r  ; end:  v = *r
```

然后交给一个叫 **mem2reg** 的 Pass，把「能放进寄存器的栈变量」提升成 SSA 值，并**自动插入 phi**。demo 第 3 步实跑结果：

```llvm
; opt -passes=mem2reg 之后
entry:
  %cmp = icmp sgt i32 %a, %b
  br i1 %cmp, label %then, label %else
then: br label %end
else: br label %end
end:
  %r.0 = phi i32 [ %a, %then ], [ %b, %else ]   ; ← alloca/store/load 全没了，自动生成 phi
  ret i32 %r.0
```

结果和我们手写的 [max.ll](examples/max.ll) 一模一样。**这就是 Ch1 里 -O2 第一步干的事**——几乎所有后续优化都建立在 SSA 之上，所以 mem2reg 是优化流水线的「门票」。

## 5. 类型系统（够用版）

LLVM IR 是**静态强类型**，但类型里**不区分有/无符号**——符号性体现在「指令」上而非「类型」上。

| 类型 | 写法 | 说明 |
|----|----|----|
| 整数 | `i1` `i8` `i32` `i64` `i33` | `iN` 任意位宽。`i1` 就是布尔。Ch1 见过 `i33`。 |
| 浮点 | `float` `double` | |
| 指针 | `ptr` | **不透明指针**：只是「一个地址」，不带指向类型（LLVM 15+ 起）。 |
| 数组 | `[4 x i32]` | 定长数组 |
| 结构体 | `{ i32, ptr }` | |
| 向量 | `<4 x i32>` | SIMD |
| 空 | `void` | |

> 「有符号」在哪体现？比较用 `icmp sgt`(signed) vs `icmp ugt`(unsigned)；除法用 `sdiv` vs `udiv`。同一个 `i32`，按哪种解释取决于**指令**。

## 6. 指令分类速查

| 类别 | 例子 | 备注 |
|----|----|----|
| 算术 | `add` `sub` `mul` `sdiv` `udiv` `shl` `lshr` | 可带 `nsw`/`nuw` 标记（Ch6） |
| 比较 | `icmp sgt/sle/eq` `fcmp` | 结果是 `i1` |
| 内存 | `alloca` `load` `store` | 栈分配 / 读 / 写 |
| 地址计算 | `getelementptr` (GEP) | **只算地址不访存**，见下 |
| 控制流 | `br` `switch` `ret` | 基本块的终结指令 |
| 汇合 | `phi` | SSA 专用 |
| 调用 | `call` | |
| 类型转换 | `sext` `zext` `trunc` `bitcast` | 位宽/类型转换 |

## 7. getelementptr (GEP)：最绕的一条

见 [examples/gep.ll](examples/gep.ll)。GEP **只做指针算术、不读不写内存**：

```llvm
%p = getelementptr inbounds [4 x i32], ptr @arr, i64 0, i64 %idx
```
- 第 1 个下标 `0`：穿过「指向数组的指针」本身（不移动）。
- 第 2 个下标 `%idx`：在 `[4 x i32]` 里走到第 idx 个元素。
- 结果 `%p` = `&arr[idx]`，是个 `ptr`。要取值还得再 `load`。
- `inbounds`：承诺没越界，越界则结果是 poison（Ch6）。

> 经验法则：**第一个下标永远在「最外层指针」上动，后面的下标逐层钻进聚合类型**。

## 8. 小结 / 自检

- [ ] 能在一段 IR 里指出 module / function / basic block / instruction 四层。
- [ ] 能解释 SSA「只赋值一次」，以及 phi 为什么必要、怎么读。
- [ ] 能说清 mem2reg 把什么变成什么（alloca/load/store → SSA + phi）。
- [ ] 知道类型不带符号性，符号性在指令上（`sgt` vs `ugt`）。
- [ ] 能讲明白 GEP「只算地址」，要配 load/store 才访存。

下一章 [03-build-ir](../03-build-ir/)：不再手写 `.ll`，改用 **Python(llvmlite)** 以编程方式生成 IR。
