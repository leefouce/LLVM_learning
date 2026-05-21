# Ch5 · 写一个自定义 Pass（C++ 新 PM 插件）

> 前面都在「用」别人的 Pass，这章自己写一个，让 `opt` 加载它。
> 你 C++ 较少没关系——代码很短、逐行注释，重点理解**结构**。
>
> 三步走：`scripts/run.sh -- 'bash 05-custom-pass/build.sh'` 编译 →
> 然后 `scripts/run.sh -- 'opt -load-pass-plugin=05-custom-pass/build/libMul2Shl.so -passes=mul2shl -S 05-custom-pass/examples/mul_demo.ll -o -'`

## 1. 这个 Pass 干什么

把 `mul x, C`（C 是 2 的幂）改写成 `shl x, log2(C)`——真实的「强度削减」优化（移位比乘法便宜）。实跑：
```llvm
; 输入                          ; 输出（[Mul2Shl] f: 替换了 2 处 mul→shl）
%a = mul i32 %x, 8     ⟶        %1 = shl i32 %x, 3      ; 8=2^3
%b = mul i32 %y, 16    ⟶        %2 = shl i32 %y, 4      ; 16=2^4
%c = mul i32 %a, 3              %c = mul i32 %1, 3      ; 3 非 2 的幂 → 不动
```

## 2. 插件的解剖（[Mul2Shl.cpp](Mul2Shl.cpp)）

一个新 PM 插件由两部分组成：

### (a) Pass 本体
```cpp
struct Mul2ShlPass : PassInfoMixin<Mul2ShlPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &) {
    ...
    return changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
  }
};
```
- 继承 `PassInfoMixin<...>`，核心是一个 **`run()`**。函数级 Pass 就接收一个 `Function&`。
- 返回 **`PreservedAnalyses`**：告诉 PM「我改了 IR 没」。改了就 `none()`（让缓存的分析失效），没改就 `all()`（后续 Pass 可复用分析结果）。

### (b) 注册入口
```cpp
extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return { ..., [](PassBuilder &PB) {
      PB.registerPipelineParsingCallback(
        [](StringRef name, FunctionPassManager &FPM, ...) {
          if (name == "mul2shl") { FPM.addPass(Mul2ShlPass()); return true; }
          return false;
        });
  }};
}
```
- `opt` 用 `dlopen` 加载 `.so` 后，调用名字固定的 **`llvmGetPassPluginInfo()`**。
- 里面注册一个回调：当 `-passes=` 字符串里出现 `"mul2shl"` 时，把我们的 Pass 加进流水线。这就是 `-passes=mul2shl` 能找到它的原因。

## 3. 改写 IR 的三个套路（务必记住）

```cpp
// ① 先收集再修改：不要边遍历 BB/指令边删，否则迭代器失效
SmallVector<BinaryOperator*,8> worklist;
for (auto &BB : F) for (auto &I : BB) if (符合条件) worklist.push_back(...);

// ② 用 IRBuilder 在某指令处插入新指令
IRBuilder<> B(mul);
Value *shl = B.CreateShl(mul->getOperand(0), ConstantInt::get(ty, k));

// ③ 替换 + 删除
mul->replaceAllUsesWith(shl);  // 把所有「用到旧值的地方」改成用新值
mul->eraseFromParent();        // 删掉旧指令
```
`dyn_cast<T>(v)`：是 T 类型就返回指针、否则 nullptr——LLVM 里到处都是这种「试探转型」。

## 4. 怎么编译（[CMakeLists.txt](CMakeLists.txt) + [build.sh](build.sh)）

关键点：
- `find_package(LLVM REQUIRED CONFIG)`，`LLVM_DIR` 由 `llvm-config --cmakedir` 提供（指向 LLVM 21）。
- `include(HandleLLVMOptions)`：**必须**。它把 `-fno-rtti` 等设置和 LLVM 本体对齐，否则加载时会因 RTTI/ABI 不匹配崩。
- `add_library(Mul2Shl MODULE ...)`：MODULE = 可被 `dlopen` 的插件 `.so`。插件**不**链接 LLVM 库——用到的符号在加载时由 `opt` 进程提供（Linux 默认允许未定义符号）。

产物：`build/libMul2Shl.so`（`build/` 已被 rsync 排除，只留在 VM）。

## 5. 怎么运行

```bash
opt -load-pass-plugin=build/libMul2Shl.so -passes=mul2shl -S input.ll -o -
```
`-load-pass-plugin` 加载 `.so`；`-passes=mul2shl` 触发我们注册的名字。还能和内置 Pass 串起来，比如 `-passes='mul2shl,instcombine'`。

## 6. 埋一个伏笔：我的 Pass 真的对吗？

注意代码里我**故意丢掉了原 `mul` 的 `nsw`/`nuw` 标记**（保守做法）。
那如果「图省事」保留 `nsw`、写成 `shl nsw` 行不行？`mul nsw x, 8` 和 `shl nsw x, 3` 在溢出时的 poison 行为一样吗？

光靠跑几个例子**测不出来**这种边界 bug。下一章 [06-correctness](../06-correctness/) 先讲清 poison/undef/nsw 这些「正确性陷阱」，[07-alive2](../07-alive2/) 再用 Alive2 **形式化证明**我们这个 Pass 到底对不对。

## 7. 小结 / 自检

- [ ] 能说出插件两部分：Pass 本体（`run` + `PreservedAnalyses`）+ 注册入口（`llvmGetPassPluginInfo`）。
- [ ] 记住改 IR 的三套路：先收集后改、IRBuilder 造指令、`replaceAllUsesWith`+`eraseFromParent`。
- [ ] 知道为什么 CMake 要 `HandleLLVMOptions`（RTTI/ABI 对齐）、为什么是 MODULE 库。
- [ ] 会用 `opt -load-pass-plugin=...so -passes=名字` 加载并运行自己的 Pass。
