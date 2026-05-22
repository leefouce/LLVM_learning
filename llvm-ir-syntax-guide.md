# LLVM IR 语法直观指南

这份笔记的目标很简单：让你看到 `.ll` 文件时不再像看天书。

LLVM IR 可以先理解成：

```text
C/C++/Rust 等源码
  -> 前端 clang/rustc 生成 LLVM IR
  -> opt 在 LLVM IR 上做优化
  -> llc 把 LLVM IR 翻译成某个 CPU 的汇编
```

所以 `.ll` 文件不是 C++，也不是汇编，而是 LLVM 世界里的“中间语言”。

## 1. 从一个 C++ 函数开始

假设有这个 C++ 文件：

```cpp
extern "C" int square(int x) {
    return x * x;
}
```

经过 clang 前端后，优化前的 LLVM IR 可能长这样：

```llvm
define dso_local i32 @square(i32 noundef %0) {
entry:
  %2 = alloca i32, align 4
  store i32 %0, ptr %2, align 4
  %3 = load i32, ptr %2, align 4
  %4 = load i32, ptr %2, align 4
  %5 = mul nsw i32 %3, %4
  ret i32 %5
}
```

优化后可能变成：

```llvm
define dso_local i32 @square(i32 noundef %x) {
entry:
  %r = mul nsw i32 %x, %x
  ret i32 %r
}
```

直观上：

```text
define ... @square(...)  -> 定义一个函数
i32                      -> 32 位整数，也就是类似 C/C++ 的 int
%x / %r / %5             -> LLVM IR 里的临时值
mul                      -> 乘法
ret                      -> 返回
```

## 2. LLVM IR 文件的基本结构

一个 `.ll` 文件通常包含：

```llvm
; 注释，用分号开头

source_filename = "example.cpp"

define i32 @add(i32 %a, i32 %b) {
entry:
  %sum = add i32 %a, %b
  ret i32 %sum
}
```

可以拆成几层看：

```text
module      整个 .ll 文件
function    一个函数，比如 @add
basic block 基本块，比如 entry:
instruction 每一条 IR 指令，比如 %sum = add ...
```

## 3. 函数定义语法

例子：

```llvm
define i32 @add(i32 %a, i32 %b) {
entry:
  %sum = add i32 %a, %b
  ret i32 %sum
}
```

逐段看：

```text
define      定义函数
i32         返回值类型
@add        函数名，全局名字用 @ 开头
i32 %a      第一个参数，类型是 i32，名字是 %a
i32 %b      第二个参数
entry:      基本块标签
ret i32 %sum 返回一个 i32 值
```

LLVM IR 里常见命名规则：

```text
@name       全局符号，比如函数名、全局变量名
%name       局部值，比如参数、临时变量、基本块里的计算结果
```

## 4. 类型怎么看

LLVM IR 是强类型的。每条指令通常都要写清楚操作数类型。

常见类型：

```text
i1      1 位整数，常用于 bool 条件
i8      8 位整数，类似 char / byte
i32     32 位整数，类似 int
i64     64 位整数，类似 long long
float   32 位浮点数
double  64 位浮点数
ptr     指针类型
void    无返回值
```

例子：

```llvm
%a = add i32 %x, %y
```

意思是：

```text
把两个 i32 值 %x 和 %y 相加，结果叫 %a
```

再比如：

```llvm
%p = alloca i32
```

意思是：

```text
在栈上分配一个 i32 的位置，结果 %p 是一个指针 ptr
```

## 5. SSA：为什么变量只能赋值一次

LLVM IR 大多使用 SSA 形式，SSA = Static Single Assignment。

直观意思：

```text
每个 %名字 只被定义一次。
```

例如这是合法的：

```llvm
%a = add i32 %x, 1
%b = add i32 %a, 2
%c = mul i32 %b, 3
```

但你不应该把它想成 C++ 里的变量反复修改：

```cpp
x = x + 1;
x = x + 2;
x = x * 3;
```

LLVM IR 更像是：

```cpp
a = x + 1;
b = a + 2;
c = b * 3;
```

所以看到很多 `%1`、`%2`、`%3` 不要慌，它们只是一步一步计算出来的临时值。

## 6. alloca / store / load：优化前 IR 为什么很啰嗦

优化前的 clang 经常生成这种 IR：

```llvm
%x.addr = alloca i32, align 4
store i32 %x, ptr %x.addr, align 4
%v = load i32, ptr %x.addr, align 4
```

对应直觉：

```text
alloca  在栈上开一个槽位
store   把值写进这个槽位
load    从这个槽位读出值

align 4 表示 这个内存地址按 4 字节对齐
```

像 C++：

```cpp
int x_addr;
x_addr = x;
v = x_addr;
```

为什么这么绕？因为前端 clang 在 `-O0` 时通常先用一种简单、保守的方式表达局部变量，不急着优化。

之后 `opt` 里的 `mem2reg` pass 会把这些内存读写提升成 SSA 值：

```llvm
; 优化前
%x.addr = alloca i32
store i32 %x, ptr %x.addr
%v = load i32, ptr %x.addr
ret i32 %v

; 优化后
ret i32 %x
```

## 7. 常见算术指令

整数运算：

```llvm
%a = add i32 %x, %y    ; x + y
%b = sub i32 %x, %y    ; x - y
%c = mul i32 %x, %y    ; x * y
%d = sdiv i32 %x, %y   ; 有符号除法
%e = udiv i32 %x, %y   ; 无符号除法
%f = srem i32 %x, %y   ; 有符号取余
```

无符号 unsigned：全部用来表示非负数。

```text
范围：0 到 2^32 - 1
也就是 0 到 4294967295
```  

有符号 signed：最高位当作符号位，可以表示负数。

```text
范围：-2^31 到 2^31 - 1
也就是 -2147483648 到 2147483647
```

比如 8 位时更容易看：

```text
二进制: 11111111

unsigned 解释: 255
signed 解释: -1
```

位运算：

```llvm
%a = shl i32 %x, 1     ; 左移，类似 x << 1
%b = lshr i32 %x, 1    ; 逻辑右移
%c = ashr i32 %x, 1    ; 算术右移
%d = and i32 %x, %y
%e = or i32 %x, %y
%f = xor i32 %x, %y
```

浮点运算通常带 `f`：

```llvm
%a = fadd double %x, %y
%b = fmul double %x, %y
```

## 8. nsw / nuw 是什么

你会经常看到：

```llvm
%r = add nsw i32 %a, %b
%s = mul nuw i32 %x, 8
```

这些是优化用的“承诺”：

```text
nsw = no signed wrap    有符号运算不会溢出
nuw = no unsigned wrap  无符号运算不会溢出
```

它们很重要，因为 LLVM 会利用这些信息做更激进的优化。

例如：

```llvm
%r = mul nsw i32 %x, 2
```

表示 LLVM 可以假设这个有符号乘法不溢出。  
如果实际执行时溢出了，LLVM IR 语义里可能产生 poison 值。这也是本项目第 6、7 章要讲“优化正确性”和 Alive2 的原因。

先记住一句话：

```text
nsw/nuw 不是装饰，它们会影响优化是否合法。
```

## 9. 比较和条件分支

C++：

```cpp
int max(int a, int b) {
    if (a > b)
        return a;
    return b;
}
```

LLVM IR 可能像这样：

```llvm
define i32 @max(i32 %a, i32 %b) {
entry:
  %cond = icmp sgt i32 %a, %b
  br i1 %cond, label %then, label %else

then:
  ret i32 %a

else:
  ret i32 %b
}
```

关键语法：

```text
icmp      整数比较
sgt       signed greater than，有符号大于
i1        1 位布尔结果
br i1     条件跳转
label     基本块标签
```

常见 `icmp` 条件：

```text
eq    等于
ne    不等于
sgt   有符号大于
sge   有符号大于等于
slt   有符号小于
sle   有符号小于等于
ugt   无符号大于
ult   无符号小于
```

## 10. 基本块和控制流

LLVM IR 的函数由多个基本块组成。

基本块的特点：

```text
从标签开始
中间是一串普通指令
最后必须以 terminator 结尾，比如 ret 或 br
```

例子：

```llvm
entry:
  %cond = icmp eq i32 %x, 0
  br i1 %cond, label %zero, label %nonzero

zero:
  ret i32 0

nonzero:
  ret i32 1
```

`entry`、`zero`、`nonzero` 都是基本块。

## 11. phi：分支汇合时怎么选值

SSA 有一个问题：如果两个分支产生不同值，汇合后该用哪个？

C++：

```cpp
int abs_like(int x) {
    int y;
    if (x < 0)
        y = -x;
    else
        y = x;
    return y;
}
```

LLVM IR 可能是：

```llvm
define i32 @abs_like(i32 %x) {
entry:
  %cond = icmp slt i32 %x, 0
  br i1 %cond, label %neg, label %pos

neg:
  %nx = sub i32 0, %x
  br label %merge

pos:
  br label %merge

merge:
  %y = phi i32 [ %nx, %neg ], [ %x, %pos ]
  ret i32 %y
}
```

`phi` 的意思：

```text
如果是从 %neg 基本块跳过来的，%y = %nx
如果是从 %pos 基本块跳过来的，%y = %x
```

可以把它想成“根据来路选择值”。

## 12. call：函数调用

C++：

```cpp
extern int helper(int);

int f(int x) {
    return helper(x) + 1;
}
```

LLVM IR：

```llvm
declare i32 @helper(i32)

define i32 @f(i32 %x) {
entry:
  %v = call i32 @helper(i32 %x)
  %r = add i32 %v, 1
  ret i32 %r
}
```

这里：

```text
declare       声明一个外部函数，只有签名，没有函数体
call          调用函数
@helper       被调用的函数名
```

## 13. getelementptr：GEP 是算地址，不是读内存

`getelementptr` 简称 GEP，是 LLVM IR 里非常容易吓人的指令。

先记一句：

```text
GEP 只计算地址，不读取内存。
```

C++：

```cpp
int get_second(int *p) {
    return p[1];
}
```

LLVM IR 可能是：

```llvm
define i32 @get_second(ptr %p) {
entry:
  %addr = getelementptr inbounds i32, ptr %p, i64 1
  %v = load i32, ptr %addr
  ret i32 %v
}
```

分开理解：

```text
%addr = getelementptr ...  计算 p + 1 的地址
从指针 %p 指向的位置开始，
按 i32 的大小往后移动 1 个元素，

inbounds: 承诺这个地址仍然在同一个合法对象范围内。简单理解：编译器可以假设 %p + 1 没有乱跑到不该去的内存。
i32: 表示按 i32 元素大小来移动。也就是每移动 1，实际地址移动 4 字节。
ptr %p: 起始指针。%p 是一个 pointer。
i64 1: 偏移 1 个元素，不是 1 个字节。(这个索引用 i64 类型表示,因为在 64 位机器上，地址/数组索引通常用 64 位整数表示)

得到新地址 %addr。


%v = load ...             从这个地址读取 i32
```

所以 GEP 类似 C/C++ 里的：

```cpp
addr = &p[1];
v = *addr;
```

## 14. select：没有跳转的 if

有些简单条件会被优化成 `select`。

C++：

```cpp
int max2(int a, int b) {
    return a > b ? a : b;
}
```

LLVM IR：

```llvm
define i32 @max2(i32 %a, i32 %b) {
entry:
  %cond = icmp sgt i32 %a, %b
  %r = select i1 %cond, i32 %a, i32 %b
  ret i32 %r
}
```

意思是：

```text
select 可以理解成 LLVM IR 里的 三元表达式： cond ? a : b
如果 %cond 为 true，%r = %a
否则 %r = %b
```

## 15. attributes：函数后面那些标记

真实 clang 生成的 IR 里经常有很多属性：

```llvm
define dso_local i32 @square(i32 noundef %0) #0 {
  ...
}

attributes #0 = { mustprogress noinline nounwind optnone uwtable }
```

初学时可以先这样看：

```text
dso_local       链接/符号相关，暂时可略过
noundef         参数不能是 undef/poison 一类未定义值
noinline        不要内联
nounwind        不抛异常或不 unwind
optnone         不要优化这个函数
attributes #0   把一组属性挂到函数上
```

特别注意 `optnone`：

```text
clang -O0 默认可能给函数加 optnone，导致 opt 不优化它。
```

所以本项目常用：

```bash
scripts/run.sh clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone file.c -o -
```

## 16. opt 和 llc 分别读写什么

可以把三个工具这样记：

```text
clang: C/C++ 源码 -> LLVM IR
opt:   LLVM IR    -> 优化后的 LLVM IR
llc:   LLVM IR    -> 汇编/目标机器代码
```

例子：

```bash
# C/C++ -> LLVM IR
scripts/run.sh clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone input.cpp -o input.ll

# LLVM IR -> 优化后的 LLVM IR
scripts/run.sh opt -passes='mem2reg,instcombine' -S input.ll -o optimized.ll

# LLVM IR -> 汇编
scripts/run.sh llc -O2 optimized.ll -o output.s
```

也可以用管道：

```bash
scripts/run.sh -- 'clang -O0 -emit-llvm -S -Xclang -disable-O0-optnone input.cpp -o - | opt -O2 -S | llc -O2 -o -'
```

## 17. 读 LLVM IR 的推荐顺序

看到一个函数时，建议按这个顺序读：

```text
1. 先看 define 行：函数名、返回值、参数类型。
2. 找基本块标签：entry、then、else、loop、exit。
3. 看每个基本块最后一行：ret 还是 br，先理解控制流。
4. 再看普通指令：add、mul、load、store、call。
5. 遇到 phi 时，回头看它来自哪些前驱基本块。
6. 遇到 getelementptr 时，记住它只是算地址，真正读写是 load/store。
7. 暂时跳过太长的 attributes，等主体逻辑看懂后再回来。
```

## 18. 一张速查表

```text
define                      定义函数
declare                     声明外部函数
@foo                        全局名字，通常是函数/全局变量
%x                          局部值/临时值
i32                         32 位整数
ptr                         指针
alloca                      栈上分配空间
store                       写内存
load                        读内存
add/sub/mul                 加/减/乘
sdiv/udiv                   有符号/无符号除法
icmp                        整数比较
br                          跳转
ret                         返回
phi                         根据控制流来路选择值
select                      条件选择，不一定产生分支
call                        函数调用
getelementptr               计算地址
nsw/nuw                     承诺有符号/无符号不溢出
```

## 19. 最小心智模型

初学 LLVM IR 时，先不用把所有细节都吃透。记住这几句话就能读大部分例子：

```text
LLVM IR 是 clang 生成、opt 优化、llc 消费的中间语言。
@ 开头的是全局名字，% 开头的是局部临时值。
每条指令都很重视类型，比如 i32、i64、ptr。
alloca/store/load 是内存风格，mem2reg 会把它们优化成 SSA 风格。
br/ret 控制程序往哪里走。
phi 用来处理分支汇合后的“值从哪来”。
GEP 只算地址，load/store 才真正读写内存。
```

