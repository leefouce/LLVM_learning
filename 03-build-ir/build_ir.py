#!/usr/bin/env python3
# build_ir.py — 用 llvmlite 以「编程方式」搭出 Ch2 那个 max 函数，
#               再用 JIT 当场把它编译成机器码执行。
#
# 跑法：scripts/run.sh -- 'bash 03-build-ir/demo.sh'
# (demo.sh 会用 ~/.venvs/llvm-learning 里的 Python 3.12 来运行本文件)

import ctypes
from llvmlite import ir
from llvmlite import binding as llvm

# ─────────────────────────────────────────────────────────────────────────────
# 第一部分：用 llvmlite.ir 这套 API「搭」出 IR（对应 Ch2 手写的 max.ll）
# ─────────────────────────────────────────────────────────────────────────────

i32 = ir.IntType(32)                       # 类型对象：i32

module = ir.Module(name="build_ir_demo")   # 一个模块（≈ 一个 .ll 文件）
module.triple = llvm.get_default_triple()  # 标上本机目标(aarch64-linux)，JIT 需要

fnty = ir.FunctionType(i32, [i32, i32])    # 函数签名：i32 (i32, i32)
fn = ir.Function(module, fnty, name="max")
a, b = fn.args                             # 拿到两个形参
a.name, b.name = "a", "b"                  # 给它们起名，生成的 IR 更好读

# 创建 4 个基本块（和 Ch2 一模一样：entry/then/else/end）
entry = fn.append_basic_block("entry")
then_bb = fn.append_basic_block("then")
else_bb = fn.append_basic_block("else")
end_bb = fn.append_basic_block("end")

# IRBuilder 是「游标」：position 到某个块，然后往里 append 指令。
builder = ir.IRBuilder(entry)
cmp = builder.icmp_signed(">", a, b, name="cmp")  # %cmp = icmp sgt i32 %a, %b
builder.cbranch(cmp, then_bb, else_bb)            # br i1 %cmp, then, else

builder.position_at_end(then_bb)
builder.branch(end_bb)                            # then: br end

builder.position_at_end(else_bb)
builder.branch(end_bb)                            # else: br end

builder.position_at_end(end_bb)
phi = builder.phi(i32, name="r")                  # end: %r = phi i32 ...
phi.add_incoming(a, then_bb)                      #   [ %a, %then ]
phi.add_incoming(b, else_bb)                      #   [ %b, %else ]
builder.ret(phi)                                  # ret i32 %r

# 注意：我们从没拼过字符串。SSA 值、块的引用都是 Python 对象，
# 由 builder 负责生成正确的文本。这就是「IRBuilder API」相对手写 .ll 的价值。

ir_text = str(module)
print("======== llvmlite 生成的 LLVM IR ========")
print(ir_text)

# 顺便存一份，给 demo.sh 用「系统 LLVM 21」的 opt/llc 验证兼容性
with open("/tmp/ch3.built.ll", "w") as f:
    f.write(ir_text)

# ─────────────────────────────────────────────────────────────────────────────
# 第二部分：JIT —— 把刚搭好的 IR 即时编译成机器码，在本进程里调用它
# ─────────────────────────────────────────────────────────────────────────────
# 注：llvmlite 0.47 起通用的 llvm.initialize() 已弃用（自动完成）；
#     但 JIT 要生成机器码，仍需注册本机的 target 和汇编打印器。
llvm.initialize_native_target()
llvm.initialize_native_asmprinter()

mod = llvm.parse_assembly(ir_text)   # 文本 IR → llvmlite 的内存模块
mod.verify()                         # 校验合法性

target_machine = llvm.Target.from_default_triple().create_target_machine()
with llvm.create_mcjit_compiler(mod, target_machine) as ee:
    ee.finalize_object()             # 真正生成机器码
    addr = ee.get_function_address("max")
    # 用 ctypes 把机器码地址包成一个可调用的 Python 函数
    c_max = ctypes.CFUNCTYPE(ctypes.c_int32, ctypes.c_int32, ctypes.c_int32)(addr)

    print("======== JIT 执行（Python 直接调用刚生成的机器码）========")
    for x, y in [(7, 3), (-2, -5), (10, 10)]:
        print(f"  max({x}, {y}) = {c_max(x, y)}")
