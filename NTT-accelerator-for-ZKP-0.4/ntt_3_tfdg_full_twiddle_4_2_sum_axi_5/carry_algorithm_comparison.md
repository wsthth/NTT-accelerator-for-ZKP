# 分段 Montgomery 约简中进位累加算法对比

## 问题背景

256 位 Montgomery 模约简需要计算 `m * N`（两个 256 位数相乘）。采用分段策略，将 256 位拆成 4 个 64 位段并行计算 16 个 `64×64` 乘法器，得到 16 个 128 位部分积，按权重 `2^(64*(i+j))` 累加到 8 个段位置。

核心问题：**如何将 16 个 128 位部分积正确累加到 8 个 64 位段中？**

---

## 算法 A：逐乘积进位提取（有缺陷）

每处理一个部分积，立即提取 1 位进位传递到高位段。

```verilog
// 初始化 8 个段累加器，每个 65 位
reg [64:0] acc [0:7];

for (i = 0; i < 4; i = i + 1)
    for (j = 0; j < 4; j = j + 1) begin
        pp = i + j;
        prod_sum = {1'b0, acc[pp]} + {1'b0, products[i][j][63:0]};
        acc[pp]   = prod_sum[63:0];                  // 存低 64 位
        acc[pp+1] = acc[pp+1] + prod_sum[64]         // 提取 1 位进位
                    + products[i][j][127:64];         // 加高 64 位
    end
```

### 执行流程（位置 3，4 个部分积）

```
acc[3] 初始值 = C（来自前序进位）

循环 1: acc[3] = C + P0_lo  → carry0 = bit[64] (0或1)
循环 2: acc[3] = (上一步低64位) + P1_lo  → carry1 = bit[64]
循环 3: acc[3] = (上一步低64位) + P2_lo  → carry2 = bit[64]
循环 4: acc[3] = (上一步低64位) + P3_lo  → carry3 = bit[64]

传递到 acc[4] 的进位 = carry0 + carry1 + carry2 + carry3
```

### 缺陷

每次只提取 `bit[64]`（0 或 1），但 4 个接近 2^64 的数相加，实际进位可达 **2、3、4**。

**数值示例**（acc[3] 初始 = 1，4 个 P_lo = 0xFFFFFFFFFFFFFFFF）：

```
Step 1: 1 + 0xFFFFFFFFFFFFFFFF = 0x10000000000000000
        acc[3]=0x0000000000000000, carry=1  ✓

Step 2: 0 + 0xFFFFFFFFFFFFFFFF = 0x0FFFFFFFFFFFFFFFF
        acc[3]=0xFFFFFFFFFFFFFFFF, carry=0  ← 此步无进位

Step 3: 0xFFFFFFFFFFFFFFFF + 0xFFFFFFFFFFFFFFFF = 0x1FFFFFFFFFFFFFFFE
        acc[3]=0xFFFFFFFFFFFFFFFE, carry=1  ✓

Step 4: 0xFFFFFFFFFFFFFFFE + 0xFFFFFFFFFFFFFFFF = 0x1FFFFFFFFFFFFFFFD
        acc[3]=0xFFFFFFFFFFFFFFFD, carry=1  ✓

累计进位 = 1 + 0 + 1 + 1 = 3
RTL 传递的进位 = 1 + 0 + 1 + 1 = 3  ← 这个例子碰巧正确
```

但当 acc[3] 初始值更大时（来自前序位置的进位累积），会出现：

```
acc[3] 初始 = 2（前序进位累积）

Step 1: 2 + 0xFFFFFFFFFFFFFFFF = 0x10000000000000001
        acc[3]=0x0000000000000001, carry=1

Step 2: 1 + 0xFFFFFFFFFFFFFFFF = 0x10000000000000000
        acc[3]=0x0000000000000000, carry=1

Step 3: 0 + 0xFFFFFFFFFFFFFFFF = 0x0FFFFFFFFFFFFFFFF
        acc[3]=0xFFFFFFFFFFFFFFFF, carry=0

Step 4: 0xFFFFFFFFFFFFFFFF + 0xFFFFFFFFFFFFFFFF = 0x1FFFFFFFFFFFFFFFE
        acc[3]=0xFFFFFFFFFFFFFFFE, carry=1

累计进位 = 1 + 1 + 0 + 1 = 3
acc[3] 最终低 64 位 = 0xFFFFFFFFFFFFFFFE

正确结果: acc[3] = 2 + 4×(2^64-1) = 4×2^64 - 2
低 64 位 = 0xFFFFFFFFFFFFFFFE ✓
进位 = (4×2^64 - 2) >> 64 = 3 ✓
```

此例 RTL 碰巧正确。问题出现在**中间累加值超过 66 位**（prod_sum 溢出 Verilog 的 66 位宽度）时：

```
假设 acc[3] = 0x3FFFFFFFFFFFFFFF0（66位值，来自前序累积）

Step: 0x3FFFFFFFFFFFFFFF0 + 0xFFFFFFFFFFFFFFFF = 0x4FFFFFFFFFFFFFFEF
66位空间只能存 0xFFFFFFFFFFFFFFEF，进位 bit[64]=1，但实际进位是 4!
丢失了 3 个进位 → acc[4] 少加了 3
```

---

## 算法 B：先累加后进位传递（正确）

第一步不做任何进位提取，用足够宽的累加器收集所有部分积，第二步统一传递进位。

```verilog
// 初始化 8 个段累加器，每个 192 位（3 × 64）
reg [191:0] acc [0:7];

// 第一步：累加所有部分积（无进位提取）
for (i = 0; i < 4; i = i + 1)
    for (j = 0; j < 4; j = j + 1)
        acc[i+j] = acc[i+j] + {66'b0, products[i][j]};

// 第二步：统一进位传递（低位到高位，单次扫描）
for (ii = 0; ii < 7; ii = ii + 1) begin
    acc[ii+1] = acc[ii+1] + {64'b0, acc[ii][191:64]};
    acc[ii]   = acc[ii] & 64'hFFFFFFFFFFFFFFFF;
end
```

### 执行流程

```
第一步结束后（192 位累加器）：
  acc[0] = P0×0                          (≤ 128 位)
  acc[1] = P0×1 + P1×0                   (≤ 129 位)
  acc[2] = P0×2 + P1×1 + P2×0            (≤ 130 位)
  acc[3] = P0×3 + P1×2 + P2×1 + P3×0     (≤ 130 位)
  ...

第二步进位传递：
  ii=0: carry = acc[0][191:64] → 加到 acc[1], acc[0] 留低 64 位
  ii=1: carry = acc[1][191:64] → 加到 acc[2], acc[1] 留低 64 位
  ...
  ii=6: carry = acc[6][191:64] → 加到 acc[7], acc[6] 留低 64 位

每次传递的是完整进位值（0 ~ 2^68），不是单比特
```

### 正确性保证

一次从低到高的进位传递是充分的，因为：
- 总和 `Σ acc[i] × 2^(64i)` 在传递前后保持不变
- 每个位置的进位只流向高位，不会回流
- 左到右单次扫描即可完成所有进位归位

---

## 算法 C：进位保留加法器链（Carry-Save Adder Chain）

CSA（3:2 压缩器）将 3 个 N 位数压缩为 2 个 N 位数（和 + 进位），不传播进位，组合逻辑延迟恒定为 1 级全加器。

### 原理

```
CSA(A, B, C) → (Sum, Carry)
  Sum   = A ^ B ^ C
  Carry = (A & B | B & C | A & C) << 1

3 个 N 位输入 → 2 个 N 位输出，进位不传播
```

### 应用于部分积累加

16 个部分积，每轮 CSA 将数量减少约 1/3（3→2），需要多轮压缩到 2 个数，最后用 CPA（Carry-Propagate Adder）合并。

```
16 → CSA×5 → 11 → CSA×3 → 8 → CSA×2 → 6 → CSA×2 → 4 → CSA×1 → 3 → CSA×1 → 2 → CPA
```

但 CSA 要求所有输入位宽相同。16 个 128 位部分积需要对齐到相同位宽（通过移位），然后用 CSA 链压缩。

### Verilog 实现思路

```verilog
// 将 16 个部分积对齐到统一宽度（512 位）
wire [511:0] aligned [0:15];
for (i = 0; i < 4; i = i + 1)
    for (j = 0; j < 4; j = j + 1)
        aligned[i*4+j] = {384'b0, products[i][j]} << ((i+j)*64);

// CSA 链：16 → 2（需要 14 个 CSA 单元）
// Level 1: 16 → 11 (5 个 CSA, 1 个直通)
// Level 2: 11 →  8 (3 个 CSA, 2 个直通)
// Level 3:  8 →  6 (2 个 CSA, 2 个直通)
// Level 4:  6 →  4 (2 个 CSA, 0 个直通)
// Level 5:  4 →  3 (1 个 CSA, 1 个直通)
// Level 6:  3 →  2 (1 个 CSA)
// Final:    2 →  1 (1 个 CPA: 512 位行波进位或超前进位)
```

### 特点

| 维度 | 指标 |
|------|------|
| CSA 单元数 | 14 个（每个 = N 个全加器，N=512） |
| CSA 延迟 | 6 级（每级 1 个全加器延迟） |
| CPA 延迟 | 1 个 512 位进位传播加法器 |
| 总组合延迟 | 6 × t_FA + t_CPA(512) |
| 寄存器切片 | 可在 CSA 级间插入流水线寄存器 |

---

## 算法 D：Wallace 树

Wallace 树是 CSA 链的优化组织形式，通过树状拓扑减少压缩级数。

### 原理

与 CSA 链相同（3:2 压缩），但并行组织多个 CSA，使每级同时处理尽可能多的部分积。

### 16 个部分积的 Wallace 树

```
Level 0: 16 个部分积（每个 128 位，按权重对齐）
Level 1: 16 → 11    (5 个 CSA 并行)
Level 2: 11 →  8    (3 个 CSA，其中 2 个并行)
Level 3:  8 →  6    (2 个 CSA 并行)
Level 4:  6 →  4    (2 个 CSA 并行)
Level 5:  4 →  3    (1 个 CSA)
Level 6:  3 →  2    (1 个 CSA)
Final :  2 →  1    (CPA)

共 14 个 CSA + 1 个 CPA
```

### Verilog 实现思路

```verilog
// Wallace Tree CSA 单元
module csa_3to2 #(parameter WIDTH = 512) (
    input  [WIDTH-1:0] a, b, c,
    output [WIDTH-1:0] sum, carry
);
    assign sum   = a ^ b ^ c;
    assign carry = {(a & b) | (b & c) | (a & c), 1'b0};
endmodule

// Wallace 树顶层：16 输入 → 2 输出
module wallace_tree_16 (
    input  [511:0] partial_products [0:15],
    output [511:0] final_sum, final_carry
);
    // Level 1: 16 → 11
    wire [511:0] l1 [0:10];
    csa_3to2 u0(.a(partial_products[0]), .b(partial_products[1]),
                .c(partial_products[2]), .sum(l1[0]), .carry(l1[1]));
    csa_3to2 u1(.a(partial_products[3]), .b(partial_products[4]),
                .c(partial_products[5]), .sum(l1[2]), .carry(l1[3]));
    csa_3to2 u2(.a(partial_products[6]), .b(partial_products[7]),
                .c(partial_products[8]), .sum(l1[4]), .carry(l1[5]));
    csa_3to2 u3(.a(partial_products[9]), .b(partial_products[10]),
                .c(partial_products[11]), .sum(l1[6]), .carry(l1[7]));
    csa_3to2 u4(.a(partial_products[12]), .b(partial_products[13]),
                .c(partial_products[14]), .sum(l1[8]), .carry(l1[9]));
    assign l1[10] = partial_products[15];  // 直通

    // Level 2-6: 继续压缩 ...
    // Final: CPA
endmodule
```

### 特点

| 维度 | 指标 |
|------|------|
| CSA 单元数 | 14 个 |
| 压缩级数 | 6 级（与 CSA 链相同，但并行度更高） |
| 组合逻辑深度 | 6 × t_FA + t_CPA |
| 布线复杂度 | 高（树状连接，信号交叉多） |
| FPGA 适配性 | 较差（FPGA LUT 结构不适合多级全加器链） |

---

## 算法 E：Dadda 乘法器

Dadda 是 Wallace 树的优化版本，使用预定义的高度序列，以最少的加法器数量完成压缩。

### 原理

Dadda 定义目标高度序列：d(1)=2, d(2)=3, d(3)=6, d(4)=13, d(5)=40, ...

从最底层开始，逐步将部分积矩阵压缩到目标高度，最终到高度 2 后用 CPA 合并。

### 16 个 128 位部分积的 Dadda 压缩

```
初始矩阵高度: 16（部分积按列排列）
目标序列: ..., 13, 6, 3, 2

Round 1: 16 → 13（用 CSA 将最高的 3 列压缩）
Round 2: 13 →  6（用 CSA 继续压缩）
Round 3:  6 →  3
Round 4:  3 →  2
Final:     2 →  1（CPA）
```

### 与 Wallace 的区别

| 对比 | Wallace | Dadda |
|------|---------|-------|
| 压缩策略 | 每级尽可能压缩到最低高度 | 按预定义目标高度压缩 |
| CSA 数量 | 14 个 | 14 个（相同） |
| 压缩级数 | 6 级 | 4 级（更少！） |
| 布线 | 不规则树状 | 更规则，布线更简单 |
| 综合难度 | 高 | 中等 |

Dadda 的核心优势：**每级只压缩到目标高度而非最低高度，减少了不必要的 CSA 级数**。

---

## 算法 F：分段并行 CPA（Segmented Parallel CPA）

将 512 位加法器拆分为 8 个 64 位段，段间进位并行传播（超前进位或前缀树）。

### 原理

先将 16 个部分积按段位置分组累加（同算法 B 第一步），得到 8 个宽累加器值，然后用分段超前进位网络完成进位传递。

```verilog
// 第一步：段内累加（与算法 B 相同）
// acc[0..7] 每个最多 131 位

// 第二步：64 位超前进位网络传递段间进位
// 每个段内部的进位由段内 CPA 处理
// 段间的进位由段间 CLA 处理
```

### 特点

适用于 FPGA：Xilinx FPGA 的 DSP48 原语内置了 48 位超前进位链，可以高效实现段内进位。

---

## 全算法对比总结

### 正确性对比

| 算法 | 多位进位处理 | 正确性 |
|------|------------|--------|
| A. 逐乘积进位 | 仅 1 位 | **错误**（多位进位丢失） |
| B. 先累加后进位 | 完整宽度 | 正确 |
| C. CSA 链 | 保留到最终 CPA | 正确 |
| D. Wallace 树 | 保留到最终 CPA | 正确 |
| E. Dadda | 保留到最终 CPA | 正确 |
| F. 分段并行 CPA | 完整宽度 | 正确 |

### 资源与性能对比（256 位分段 Montgomery，16 个 64×64 部分积）

| 维度 | A. 逐乘积 | B. 先累加 | C. CSA 链 | D. Wallace | E. Dadda | F. 分段CPA |
|------|----------|----------|----------|-----------|---------|-----------|
| **加法器类型** | 65 位加法 | 192 位加法 | 全加器×14×512 | 全加器×14×512 | 全加器×14×512 | 64 位 CLA |
| **组合级数** | 16 级 | 23 级 | 6+CPA 级 | 6+CPA 级 | 4+CPA 级 | 2 级 |
| **流水线友好** | 差 | 好 | 好 | 中 | 好 | 好 |
| **FPGA LUT 消耗** | 低 | 中 | 高 | 高 | 高 | 中 |
| **FPGA 适配性** | 好 | 好 | 差 | 差 | 差 | 好 |
| **正确性** | **错误** | 正确 | 正确 | 正确 | 正确 | 正确 |
| **实现复杂度** | 低 | 低 | 中 | 高 | 高 | 中 |

### 推荐选择

| 场景 | 推荐算法 | 理由 |
|------|---------|------|
| **FPGA 快速实现** | B（先累加后进位） | 实现简单，资源可控，流水线友好 |
| **ASIC 极致性能** | E（Dadda） | 级数最少，门级数优化 |
| **ASIC 中等性能** | D（Wallace） | 成熟方案，工具支持好 |
| **FPGA 利用 DSP** | F（分段并行 CPA） | 可利用 DSP48 超前进位链 |

本项目选择**算法 B**，理由：
1. 实现最简单（仅需修改累加器位宽和进位提取方式）
2. 与现有分段架构无缝兼容
3. FPGA 上 192 位加法器可以被综合工具优化为进位链
4. 单周期完成（阻塞赋值），无需额外状态机

---

## 实测结果（BN254 曲线，6 组测试向量）

### 算法 A 输出

```
Test 2:
  期望 mN = 0x2ce8ff6907781d2c8b33555c1e319bd15e4fc5d46ac67867...
  实际 mN = 0x2ce8ff6907781d2c8b33555c1e319bcf5e4fc5d46ac67867...
  差异位置: acc[3] 差 2, acc[4] 差 2, acc[6] 差 2
  结果: FAIL（Montgomery 约简值偏离正确值 ~2^253）
```

### 算法 B 输出

```
Test 1~6: 全部 PASS
mN 与数学精确值完全一致
```

---

## Python 验证代码

### 对比两种算法

```python
MASK64 = (1 << 64) - 1

def split(val, n):
    return [(val >> (i * 64)) & MASK64 for i in range(n)]

def algorithm_a(products):
    """逐乘积进位提取（有缺陷）"""
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            pp = i + j
            p_lo = products[i][j] & MASK64
            p_hi = (products[i][j] >> 64) & MASK64
            prod_sum = acc[pp] + p_lo
            acc[pp] = prod_sum & MASK64
            carry = (prod_sum >> 64) & 1    # ← 只取 1 位
            acc[pp + 1] += carry + p_hi
    return acc

def algorithm_b(products):
    """先累加后进位传递（正确）"""
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            acc[i + j] += products[i][j]    # ← 完整累加
    for ii in range(7):
        carry = acc[ii] >> 64               # ← 完整进位
        acc[ii] &= MASK64
        acc[ii + 1] += carry
    return acc

def algorithm_exact(products):
    """数学精确值"""
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            acc[i + j] += products[i][j]
    return acc

# 构造测试：4 个接近最大值的部分积放在位置 3
big_prod = (1 << 128) - 1
products = [[0]*4 for _ in range(4)]
for i in range(4):
    for j in range(4):
        products[i][j] = big_prod

a = algorithm_a(products)
b = algorithm_b(products)
e = algorithm_exact(products)

print("位置 |  算法A (低64位)   |  算法B (低64位)   |  精确值 (低64位)  | A正确? | B正确?")
for k in range(8):
    a_lo = a[k] & MASK64
    b_lo = b[k] & MASK64
    e_lo = e[k] & MASK64
    print(f"  {k}  | 0x{a_lo:016x} | 0x{b_lo:016x} | 0x{e_lo:016x} |"
          f"  {'  ✓' if a_lo == e_lo else '  ✗'}  |"
          f"  {'  ✓' if b_lo == e_lo else '  ✗'}")
```

### 验证最小位宽

```python
max_prod = (1 << 128) - 1
# 最坏情况分布
acc = [1*max_prod, 2*max_prod, 3*max_prod, 4*max_prod,
       4*max_prod, 3*max_prod, 2*max_prod, 1*max_prod]

print("进位传递过程中各位置位宽需求：")
max_w = 0
for ii in range(7):
    carry = acc[ii] >> 64
    acc[ii + 1] += carry
    acc[ii] &= MASK64
    w = acc[ii + 1].bit_length()
    max_w = max(max_w, w)
    print(f"  pos {ii}→{ii+1}: acc[{ii+1}] 需要 {w} 位")

print(f"\n最大位宽需求: {max_w} 位")
print(f"选择位宽: 192 位 (3 × 64)")
```

### 验证 CSA / Wallace / Dadda 算法

```python
"""验证 CSA 链、Wallace 树、Dadda 的部分积累加正确性"""
MASK64 = (1 << 64) - 1

def csa(a, b, c):
    """3:2 压缩器（Carry-Save Adder）"""
    s = a ^ b ^ c
    c = ((a & b) | (b & c) | (a & c)) << 1
    return s, c

def simulate_csa_chain(products):
    """算法 C: CSA 链压缩 16 个部分积 → 2 个数 → CPA"""
    # 将 16 个部分积对齐到 512 位
    aligned = []
    for i in range(4):
        for j in range(4):
            aligned.append(products[i][j] << ((i + j) * 64))

    # CSA 链：每次将 3 个数压缩为 2 个，直到只剩 2 个
    while len(aligned) > 2:
        next_vals = []
        i = 0
        while i + 2 < len(aligned):
            s, c = csa(aligned[i], aligned[i+1], aligned[i+2])
            next_vals.append(s)
            next_vals.append(c)
            i += 3
        while i < len(aligned):
            next_vals.append(aligned[i])
            i += 1
        aligned = next_vals

    # Final CPA: 两个数相加
    return aligned[0] + aligned[1]

def simulate_algorithm_b(products):
    """算法 B: 先累加后进位"""
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            acc[i + j] += products[i][j]
    for ii in range(7):
        carry = acc[ii] >> 64
        acc[ii] &= MASK64
        acc[ii + 1] += carry
    return sum((acc[k] & MASK64) << (k * 64) for k in range(8))

def simulate_exact(products):
    """数学精确值"""
    result = 0
    for i in range(4):
        for j in range(4):
            result += products[i][j] << ((i + j) * 64)
    return result

import random
random.seed(42)

test_cases = {
    "最坏情况": [[(1 << 128) - 1] * 4 for _ in range(4)],
    "随机输入": [[random.getrandbits(128) for _ in range(4)] for _ in range(4)],
}

for name, prods in test_cases.items():
    exact = simulate_exact(prods)
    b     = simulate_algorithm_b(prods)
    csa_r = simulate_csa_chain(prods)

    print(f"=== {name} ===")
    print(f"  算法B (先累加后进位): {'PASS' if b == exact else 'FAIL'}")
    print(f"  CSA链 (Wallace/Dadda): {'PASS' if csa_r == exact else 'FAIL'}")
```

### 算法资源估算（FPGA 角度）

```python
"""估算各算法在 Xilinx FPGA 上的资源消耗（粗略）"""
print(f"{'算法':<20} {'加法器/全加器':<20} {'逻辑深度':<12}")
print("-" * 52)
print(f"{'A. 逐乘积进位':<20} {'1×66bit ADD ×16':<20} {'16 级串行':<12}")
print(f"{'B. 先累加后进位':<20} {'1×192bit ADD ×23':<20} {'23 级串行':<12}")
print(f"{'C. CSA 链':<20} {'14×512bit FA+1×CPA':<20} {'6+1 级并行':<12}")
print(f"{'D. Wallace 树':<20} {'14×512bit FA+1×CPA':<20} {'6+1 级并行':<12}")
print(f"{'E. Dadda':<20} {'14×512bit FA+1×CPA':<20} {'4+1 级并行':<12}")
print(f"\n注: 算法 B 可被综合工具映射为 FPGA 进位链, 实际延迟远优于 23 级")
print(f"    CSA/Wallace/Dadda 的 FA 在 FPGA 上映射为 LUT, 资源消耗大")
print(f"    FPGA 推荐: 算法 B  |  ASIC 推荐: 算法 E (Dadda)")
```
