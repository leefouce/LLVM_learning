// hello.c — Ch1 用来演示「源码 → IR → 优化 → 汇编」整条链路的最小例子。
//
// 选两个函数：
//   square : 极简，方便看清 IR 的基本结构。
//   sum_to : 带一个循环。开 -O2 时 LLVM 会把整个循环优化掉，
//            直接算出闭式解 n*(n+1)/2 —— 用来直观感受「优化」有多强。

int square(int x) {
    return x * x;
}

int sum_to(int n) {
    int s = 0;
    for (int i = 1; i <= n; i++) {
        s += i;
    }
    return s;
}
