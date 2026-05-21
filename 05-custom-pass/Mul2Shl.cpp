//===- Mul2Shl.cpp - 一个最简的 LLVM 优化 Pass（新 Pass Manager 插件）------===//
//
// 作用：把   %r = mul %x, C   （C 是 2 的幂）   改写成   %r = shl %x, log2(C)
//   这是真实存在的「强度削减 (strength reduction)」：移位通常比乘法便宜。
//
// 学习目标：一个 out-of-tree 的新 PM 插件长什么样、怎样被 opt 加载运行。
// 你 C++ 较少没关系——重点看「结构」，每行都有注释。
//===----------------------------------------------------------------------===//

#include "llvm/IR/PassManager.h"      // PassInfoMixin, FunctionAnalysisManager
#include "llvm/IR/Function.h"         // Function / BasicBlock / Instruction
#include "llvm/IR/InstrTypes.h"       // BinaryOperator
#include "llvm/IR/Constants.h"        // ConstantInt
#include "llvm/IR/IRBuilder.h"        // IRBuilder（造新指令）
#include "llvm/ADT/SmallVector.h"     // SmallVector
#include "llvm/Passes/PassBuilder.h"  // PassBuilder
#include "llvm/Passes/PassPlugin.h"   // 插件入口相关宏
#include "llvm/Support/raw_ostream.h" // errs()

using namespace llvm;

namespace {

// 一个「函数级」变换 Pass：继承 PassInfoMixin，核心就是一个 run()。
struct Mul2ShlPass : PassInfoMixin<Mul2ShlPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &) {
    unsigned replaced = 0;

    // 先收集待替换指令——不要边遍历边删，否则迭代器会失效。
    SmallVector<BinaryOperator *, 8> worklist;
    for (BasicBlock &BB : F)
      for (Instruction &I : BB)
        if (auto *bin = dyn_cast<BinaryOperator>(&I))          // 是二元运算？
          if (bin->getOpcode() == Instruction::Mul)            // 是乘法？
            if (auto *c = dyn_cast<ConstantInt>(bin->getOperand(1))) // 右操作数是常量？
              if (c->getValue().isPowerOf2())                  // 且是 2 的幂？
                worklist.push_back(bin);

    // 逐个改写：mul x, 2^k  →  shl x, k
    for (BinaryOperator *mul : worklist) {
      auto *c = cast<ConstantInt>(mul->getOperand(1));
      unsigned shiftAmt = c->getValue().logBase2();            // k = log2(C)
      IRBuilder<> B(mul);                                      // 在 mul 处插入新指令
      // 注意：这里【故意不保留】mul 上的 nsw/nuw 标记 —— 保守做法，永远正确。
      //       「保留 nsw 行不行」是个微妙的正确性问题，留到 Ch6/Ch7 用 Alive2 验证。
      Value *shl = B.CreateShl(mul->getOperand(0),
                               ConstantInt::get(c->getType(), shiftAmt));
      mul->replaceAllUsesWith(shl);   // 把所有用到 mul 结果的地方，改成用 shl
      mul->eraseFromParent();         // 删掉原来的 mul
      ++replaced;
    }

    if (replaced)
      errs() << "[Mul2Shl] " << F.getName() << ": 替换了 " << replaced
             << " 处 mul→shl\n";

    // 改了 IR 就声明「已有分析结果失效」；没改就全部保留（让后续 Pass 复用）。
    return replaced ? PreservedAnalyses::none() : PreservedAnalyses::all();
  }
};

} // end anonymous namespace

// ---- 插件信息：告诉 opt「有个名叫 mul2shl 的 pass，在 -passes= 里见到就用我」----
llvm::PassPluginLibraryInfo getMul2ShlPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "Mul2Shl", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (name == "mul2shl") {       // 用户写 -passes=mul2shl 时
                    FPM.addPass(Mul2ShlPass());  // 把我们的 pass 加进流水线
                    return true;
                  }
                  return false;
                });
          }};
}

// opt 用 dlopen 加载插件后，会找这个名字固定的导出函数。
extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return getMul2ShlPluginInfo();
}
