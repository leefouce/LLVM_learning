# Ch4 · 优化 Pass 与 opt 实战 ★

> LLVM 的优化 = 一串 **Pass** 依次作用在 IR 上。本章把它们一个个拆开看。
>
> 一键跑：`scripts/run.sh -- 'bash 04-opt-passes/demo.sh'`
> 例子在 [examples/](examples/)。

## 1. 什么是 Pass

**Pass = 对 IR 做一件事的最小单元。** 分两类：

| 类型 | 干什么 | 改 IR 吗 | 例子 |
|----|----|----|----|
| **Transform（变换）** | 重写 IR 让它更快/更小 | ✅ 改 | instcombine, dce, gvn, licm, mem2reg |
| **Analysis（分析）** | 算出某种信息供别的 Pass 用 | ❌ 不改 | 支配树 domtree, 别名分析 AA, 循环信息 |

demo 最后那段 `print<domtree>` 就是分析型——它打印出支配树（谁支配谁），但 IR 一行没动：
```
Inorder Dominator Tree:
  [1] %entry
    [2] %loop
      [3] %exit
```
> 变换型 Pass 常常**依赖**分析型 Pass 的结果（比如 licm 要先知道循环结构和支配关系）。新 PM 会自动按需运行并缓存分析。

## 2. 新版 Pass Manager 与 `opt -passes=`

LLVM 13+ 起，**新版 Pass Manager (New PM)** 是唯一方式（LLVM 21 已彻底移除旧式 `opt -instcombine` 写法）。语法：

```bash
opt -passes='pass1,pass2,...' -S input.ll -o output.ll
```
- 逗号 = **按顺序**跑。
- 还能按「作用域」嵌套：`function(...)`、`loop(...)`、`cgscc(...)`。比如 O2 流水线里就有 `function<eager-inv>(mem2reg, instcombine, ...)`。

Pass 有**作用域**：module（整个模块）/ cgscc（调用图强连通分量，做内联）/ function（单函数）/ loop（单循环）。

## 3. 经典 Pass 巡礼（均来自 demo 实跑）

### mem2reg —— 优化的「门票」
把 `alloca`/`load`/`store` 提升成 SSA 寄存器值并自动插 `phi`（Ch2 已详讲）。**几乎所有后续优化都建立在 SSA 上**，所以它通常第一个跑。

### instcombine —— 窥孔/代数化简
把局部小模式换成等价更简形式。`2*x - x`：
```llvm
%m = mul i32 %x, 2          ⟶      ret i32 %x
%r = sub i32 %m, %x
ret i32 %r
```

### dce —— 死代码消除
删掉「算了但没人用」的指令。`%dead = mul x, x` 直接消失。

### early-cse / gvn —— 公共子表达式消除
同一个值算两遍只留一次。`(x+y)` 算两次 → 第二次复用：
```llvm
%a = add i32 %x, %y
%b = add i32 %x, %y         ⟶      %a = add i32 %x, %y
%r = mul i32 %a, %b                %r = mul i32 %a, %a   ; %b 被换成 %a
```
> `early-cse` 轻量快速（块内为主），`gvn` 更强（跨块、含值编号）。这里两者效果一样。

### sccp —— 稀疏条件常量传播
边传播常量、边判定哪些分支不可达。`%x` 恒为 1 → `%c` 恒 true → `no:` 块不可达被删：
```llvm
entry: %x=add 0,1; %c=icmp eq %x,1; br %c, yes, no
yes:   ret 42
no:    ret -1            ⟶   entry: br label %yes
                             yes:   ret i32 42
```
再加 `simplifycfg`，连那条多余的跳转都折掉，只剩 `ret i32 42`。

### licm —— 循环不变量外提
把循环里「每次都一样」的计算提到循环外。`%inv = mul x, y` 从 `loop:` 提到了 `entry:`，循环体里就不再每轮重算：
```llvm
loop:  %inv = mul i32 %x, %y    ⟶    entry: %inv = mul i32 %x, %y
       %acc.next = add %acc,%inv         loop:  %acc.next = add %acc, %inv
```
（注意它还顺手补了个 `%acc.lcssa` phi，这是循环优化的规范形式 LCSSA。）

### simplifycfg —— 控制流图清理
合并基本块、删空块/不可达块、把简单 if 变 `select`。

## 4. 组合的威力：1+1 > 2

单个 Pass 往往只搬动一点点，但**串起来**会层层放大。对 Ch2 的 `max_mem.ll` 跑 `mem2reg,simplifycfg,instcombine`：

```llvm
; 8 行 alloca/store/load/分支  ⟶  优化器认出这是「取较大值」惯用法：
define i32 @max(i32 %a, i32 %b) {
  %a.b = call i32 @llvm.smax.i32(i32 %a, i32 %b)
  ret i32 %a.b
}
```
mem2reg 去内存、simplifycfg 把 if 折成 select、instcombine 把 select 模式认成 `@llvm.smax` 内建函数——单独哪个都做不到。

## 5. `-O0/-O1/-O2/-O3` 其实就是预设的 Pass 列表

「优化等级」不是魔法，就是**一串排好序的 Pass**。用 `-print-pipeline-passes` 把 `-O2` 摊开看（节选）：
```
annotation2metadata → forceattrs → inferattrs → ... →
function(... simplifycfg → sroa → early-cse) → ipsccp → globalopt →
function(mem2reg → instcombine → simplifycfg) → inline → ...
```
- 跑预设：`opt -passes='default<O2>' ...`（等价于 `clang -O2` 的中端部分）。
- O0≈不优化，O1/O2/O3 逐级激进，Os/Oz 偏向减小体积。

## 6. 调试/观察 Pass 的实用开关

| 开关 | 作用 |
|----|----|
| `-passes='print<domtree>'` | 跑并打印某个分析（domtree/loops/scalar-evolution…） |
| `-print-pipeline-passes` | 打印某流水线展开后的完整 Pass 序列 |
| `-print-after=PASS` / `-print-before=PASS` | 在某 Pass 前/后 dump IR |
| `-print-changed` | 只在 IR 真被改动时 dump，定位是哪个 Pass 起了作用 |
| `-debug-pass-manager` | 打印 PM 实际调度的每个 Pass |
| `-time-passes` | 各 Pass 耗时统计 |

> 想自己试某段 IR：`scripts/run.sh opt -passes='你想试的pass' -S 路径.ll -o -`

## 7. 小结 / 自检

- [ ] 能区分变换型 vs 分析型 Pass，并举例。
- [ ] 会用 `opt -passes='a,b,c'` 串 Pass，知道逗号=按序、`function(...)`=作用域。
- [ ] 能说出 mem2reg/instcombine/dce/cse/sccp/licm/simplifycfg 各消除/转换了什么。
- [ ] 理解 `-O2` 只是预设 Pass 列表，会用 `-print-pipeline-passes` 看它。
- [ ] 知道几个观察开关（print-after / print-changed / print<analysis>）。

下一章 [05-custom-pass](../05-custom-pass/)：自己写一个 Pass（注释版 C++ 插件），让 `opt` 加载它。
