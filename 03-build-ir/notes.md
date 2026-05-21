# Ch3 · 用 Python(llvmlite) 以编程方式构造 IR

> Ch2 我们**手写** `.ll`。本章改用 API **搭** IR——这正是编译器/JIT 内部干的事。
>
> 一键跑：`scripts/run.sh -- 'bash 03-build-ir/demo.sh'`
> 代码：[build_ir.py](build_ir.py)

## 1. llvmlite 是什么

**llvmlite** = LLVM 的轻量 Python 绑定（Numba 项目维护）。两部分：

- **`llvmlite.ir`**：纯 Python 的 **IR 构造 API**——用对象和方法搭出 IR，不拼字符串。
- **`llvmlite.binding`**：绑定 LLVM C API，能**解析 IR、跑 Pass、JIT 执行**。

它**自带一份 LLVM**（本机装的是 llvmlite 0.47 → 内置 LLVM 20.1.8），和系统的 LLVM 21 互相独立。

> 这对应 Ch2 说的「IR 第三种形态——内存里的对象」。编译器前端、Numba、各种 DSL 就是这么动态生成 IR 的。

### 环境（已在 VM 配好，一次性）
VM 是 Python 3.14 且无 pip，所以用 `uv` 装了个独立的 3.12 venv：
```bash
~/.local/bin/uv venv --python 3.12 ~/.venvs/llvm-learning
~/.local/bin/uv pip install --python ~/.venvs/llvm-learning/bin/python llvmlite
```
`demo.sh` 会自动用这个 venv 的 Python。

## 2. 核心心智模型：IRBuilder 是「游标」

构造 IR 的套路（看 [build_ir.py](build_ir.py)）：

1. 建**类型**：`i32 = ir.IntType(32)`
2. 建**模块** `ir.Module()`、**函数** `ir.Function(module, fnty, "max")`
3. 给函数 `append_basic_block(...)` 建几个块
4. 用 **`IRBuilder`** 把「游标」定位到某个块，往里 `append` 指令：

```python
builder = ir.IRBuilder(entry)
cmp = builder.icmp_signed(">", a, b, name="cmp")   # %cmp = icmp sgt ...
builder.cbranch(cmp, then_bb, else_bb)             # 条件跳转
...
builder.position_at_end(end_bb)                    # 把游标移到 end 块
phi = builder.phi(i32, name="r")                   # 建 phi
phi.add_incoming(a, then_bb)                        #   [a, then]
phi.add_incoming(b, else_bb)                        #   [b, else]
builder.ret(phi)
```

**关键：全程没拼过一个字符串**。`cmp`、`a`、`then_bb` 都是 Python 对象，指令之间靠对象引用连接，由 builder 负责生成正确的 SSA 文本。这就是 IRBuilder 相对手写 `.ll` 的价值——**不会写错 `%` 名字、不会引用未定义的值**。

生成的 IR（和 Ch2 的 [max.ll](../02-ir-basics/examples/max.ll) 同构，只是 llvmlite 习惯给名字加引号）：

```llvm
define i32 @"max"(i32 %"a", i32 %"b") {
entry:
  %"cmp" = icmp sgt i32 %"a", %"b"
  br i1 %"cmp", label %"then", label %"else"
then:  br label %"end"
else:  br label %"end"
end:
  %"r" = phi i32 [%"a", %"then"], [%"b", %"else"]
  ret i32 %"r"
}
```

## 3. JIT：把刚搭的 IR 当场编译并执行

`llvmlite.binding` 能把内存里的 IR **即时编译成机器码**，再用 `ctypes` 当普通函数调用：

```python
llvm.initialize_native_target()        # codegen 需注册本机 target
llvm.initialize_native_asmprinter()    # （0.47 起通用 initialize() 已弃用，但这两个仍要调）
mod = llvm.parse_assembly(ir_text)
mod.verify()
tm = llvm.Target.from_default_triple().create_target_machine()
with llvm.create_mcjit_compiler(mod, tm) as ee:
    ee.finalize_object()
    c_max = ctypes.CFUNCTYPE(c_int32, c_int32, c_int32)(ee.get_function_address("max"))
    c_max(7, 3)   # → 7
```

实跑结果：
```
max(7, 3) = 7
max(-2, -5) = -2
max(10, 10) = 10
```
**「Python 造了一段 IR，又马上把它编译成机器码跑了一遍」**——这就是 JIT。

> ⚠️ 0.47 的坑：旧教程里的 `llvm.initialize()` 现在会**抛异常**（已自动化）。但 `initialize_native_target()` / `initialize_native_asmprinter()` 仍需手动调，否则报 "no targets are registered"。

## 4. 跨版本兼容：llvmlite(LLVM20) 的产出喂给系统 LLVM 21

demo 第 2、3 步把 llvmlite 生成的 `.ll` 交给**系统 LLVM 21** 的工具：

- `opt -passes=verify` → 通过 ✓（IR 语法跨大版本基本稳定）
- `llc -O2` → 编出干净的 aarch64，连分支都没了（用 `csel` 条件选择）：

```asm
max:
	cmp	w0, w1
	csel	w0, w0, w1, gt   ; w0 = (w0 > w1) ? w0 : w1
	ret
```

> 说明：llvmlite 适合「在 Python 里生成/JIT IR」，但它绑死自带的旧 LLVM。要用 LLVM 21 的最新 Pass/特性，还是回到命令行 `opt`（Ch4）或 C++（Ch5）。

## 5. 小结 / 自检

- [ ] 能说出 llvmlite 两部分（`ir` 构造 / `binding` 解析+JIT）各干什么。
- [ ] 理解 IRBuilder「游标」模型：定位到块 → append 指令，全程用对象不拼字符串。
- [ ] 能讲清 JIT 干了什么（IR → 机器码 → ctypes 调用）。
- [ ] 知道 llvmlite 自带旧 LLVM，与系统 LLVM 21 独立但产物大体兼容。

下一章 [04-opt-passes](../04-opt-passes/) 进入重点：**优化 Pass 与 `opt` 实战**。
