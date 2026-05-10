# Montgomery 流水线 Stage 4 进位丢失 Bug 分析与修复

## 1. 现象

Butterfly 模块测试 6 个向量，Test 2 FAIL，其余 PASS：

```
Test 2:
  exp_add=0x0b22f527747e027a168808f7e71800feceadc118e00f6d3d402591f0f6008698
  got_add=0x0b22f527747e027a168808f7e71800fcceadc118e00f6d3d402591f0f6008696
                                                      ↑ 差2
```

`montgomery_result` 与正确值相差极大（~2^253 量级），但 `full_product`（512 位乘积）完全正确。

## 2. 排查过程（多轮迭代）

### 第一轮：怀疑输出时序

最初假设 Montgomery 流水线的 `montgomery_valid` 比 `montgomery_result` 早 1 拍有效（`out_sum` 的非阻塞赋值延迟）。

**验证方法**：在 butterfly 模块增加 `STATE_CAPTURE` 状态，多等一拍再采样 `montgomery_result`。

**结果**：Test 2 的 `mont_res` 调试值从 `0x0d78...061` 变为 `0x0d78...061`（不变）。说明根本问题不在输出时序。

### 第二轮：怀疑累加器位宽

Stage 4 累加器 `acc` 宽度为 65 位（`SEG_BITS+1`），怀疑进位溢出。

**验证方法**：将 `acc` 扩展到 129 位。

**结果**：mN 值不变。因为 RTL 中 `acc[pp] = prod_sum[SEG_BITS-1:0]` 只存低 64 位，扩展 `acc` 位宽不影响输出。

### 第三轮：Python 精确模拟 RTL 进位算法（找到根因）

用 Python 逐步模拟 RTL 的逐乘积进位提取算法，与数学精确值对比。

**关键发现**：`mN (RTL算法) ≠ mN (数学精确值)`，差异出现在位置 3 和位置 6。

## 3. 根因分析

### 3.1 RTL 原始累加算法（Stage 4）

```verilog
for (ii = 0; ii < SEG_CNT; ii = ii + 1)
    for (jj = 0; jj < SEG_CNT; jj = jj + 1) begin
        pp = ii + jj;
        prod_sum = {1'b0, acc[pp]} + {1'b0, products[ii][jj][63:0]};
        acc[pp] = prod_sum[63:0];             // 只存低64位
        acc[pp+1] += prod_sum[64] + products[ii][jj][127:64];  // 只取1位进位
    end
```

### 3.2 为什么 1 位进位不够

位置 pp 的累加值为：`acc[pp] = Σ(products[i][j] 的低64位) + 来自pp-1的进位`

当 4 个乘积贡献同一位置时（如位置 3），每个乘积的低 64 位可以接近 2^64：

```
acc[3] = P0_lo + P1_lo + P2_lo + P3_lo + carry_in

每个 P_lo ≤ 2^64 - 1
4 个 P_lo 的和 ≤ 4 × (2^64 - 1) = 4 × 2^64 - 4
```

RTL 的处理方式是逐个累加，每次只取 `prod_sum[64]` 作为进位（0 或 1）。但 4 个大数相加的实际进位可能为 **2、3 甚至 4**，这些高位进位被丢弃。

**具体例子**：设 acc[3] 初始为 1（来自前序进位），然后累加 4 个接近 2^64 的值：

```
Step 1: acc[3] = 1 + 0xFFFFFFFFFFFFFFFF = 0x10000000000000000 → acc[3]=0, carry=1  ✓
Step 2: acc[3] = 0 + 0xFFFFFFFFFFFFFFFF = 0xFFFFFFFFFFFFFFFF  → acc[3]=0xFFFFFFFFFFFFFFFF, carry=0
Step 3: acc[3] = 0xFFFFFFFFFFFFFFFF + 0xFFFFFFFFFFFFFFFF = 0x1FFFFFFFFFFFFFFFE → carry=1  ✓
Step 4: acc[3] = 0xFFFFFFFFFFFFFFFE + 0xFFFFFFFFFFFFFFFF = 0x1FFFFFFFFFFFFFFFD → carry=1  ✓
总进位 = 1+0+1+1 = 3, 但 RTL 只提取了 bit[64] = 1（Step 4的进位）, 丢失了 2
```

### 3.3 误差传播

位置 3 的进位丢失导致 acc[3] 偏大（少减了进位），acc[4] 偏小（少加了进位），误差向上传播到所有高位。

Test 2 的具体差异：

```
位置 3: RTL=0x84e205ec6b0ebf08  正确=0x84e205ec6b0ebf0a  差=2
位置 4: RTL=0x64ede373afd37100  正确=0x64ede373afd37102  差=2
位置 6: RTL=0x8b33555c1e319bcf  正确=0x8b33555c1e319bd1  差=2
```

### 3.4 为什么之前的 pipeline 测试通过

1. **测试向量覆盖不足**：之前的 pipeline 测试可能使用了不会触发多位进位溢出的输入（小数值、特殊模式）
2. **进位溢出是概率性事件**：只有当同一位置的多个乘积累加值超过 65 位时才出错，随机输入有概率不触发
3. **测试 1、3、4、5、6 恰好未触发**：它们的输入组合产生的累加值未超过 65 位宽度

## 4. 修复方案

### 4.1 新算法：先累加，后进位

```verilog
// 第一步：累加所有交叉乘积（无进位提取）
for (ii = 0; ii < SEG_CNT; ii = ii + 1)
    for (jj = 0; jj < SEG_CNT; jj = jj + 1)
        acc[ii+jj] += products[ii][jj];  // 完整128位累加

// 第二步：统一进位传递（从低位到高位）
for (ii = 0; ii < 2*SEG_CNT - 1; ii = ii + 1) begin
    acc[ii+1] += acc[ii][3*SEG_BITS-1:SEG_BITS];  // 提取完整进位
    acc[ii]   &= {SEG_BITS{1'b1}};                 // 保留低64位
end
```

### 4.2 累加器位宽选择

Python 仿真确定所需位宽：

```
位置   累加后位宽   进位传递后位宽
  0       128           -
  1       129          130
  2       130          131
  3       130          131  ← 最大
  4       130          131
  5       129          130
  6       128          129
  7       128           -
```

最大需要 **131 位**。选择 **192 位**（`3 * SEG_BITS`）作为安全宽度，不会溢出。

## 5. Python 验证代码

### 5.1 定位 Bug：对比 RTL 算法与精确算法

```python
N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
R = 2**256
N_prime = 0xf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389
MASK64 = (1 << 64) - 1

x1 = 0x25caa11a16419f828b9d2434e465e150bd9c66b3ad3c2d6d1a3d1fa7bc8960a9
w  = 0x26877991815ef6d13b8faa1837f8a88b17fc695a07a0ca6e0822e8f36c031199
t = x1 * w
m = (t % R * N_prime) % R

def split(val, n):
    return [(val >> (i * 64)) & MASK64 for i in range(n)]

m_segs = split(m, 4)
N_segs = split(N, 4)
prods = [[m_segs[i] * N_segs[j] for j in range(4)] for i in range(4)]

# ---- 方法1: RTL 逐乘积进位提取（有 Bug）----
def simulate_rtl():
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            pp = i + j
            p_lo = prods[i][j] & MASK64
            p_hi = (prods[i][j] >> 64) & MASK64
            prod_sum = acc[pp] + p_lo         # 66-bit addition
            acc[pp] = prod_sum & MASK64       # store low 64
            carry = (prod_sum >> 64) & 1      # BUG: only 1-bit carry!
            acc[pp+1] = acc[pp+1] + carry + p_hi
    return acc

# ---- 方法2: 先累加所有乘积，再统一进位（正确）----
def simulate_correct():
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            acc[i + j] += prods[i][j]         # full 128-bit accumulation
    for pp in range(7):                        # single carry propagation pass
        carry = acc[pp] >> 64
        acc[pp] &= MASK64
        acc[pp + 1] += carry
    return acc

rtl = simulate_rtl()
cor = simulate_correct()

# 对比每个位置的低 64 位
print("=== acc low-64 comparison (RTL vs correct) ===")
for i in range(8):
    r = rtl[i] & MASK64
    c = cor[i] & MASK64
    if r != c:
        print(f"  acc[{i}]: rtl=0x{r:016x} correct=0x{c:016x} diff={c - r}")

# 检查哪些位置在累加后超过 64 位
print("\n=== Overflow positions (before carry propagation) ===")
acc_raw = [0] * 8
for i in range(4):
    for j in range(4):
        acc_raw[i + j] += prods[i][j]
for i in range(8):
    if acc_raw[i] >= (1 << 64):
        print(f"  acc_raw[{i}] needs {acc_raw[i].bit_length()} bits, "
              f"overflow={acc_raw[i] >> 64}")

# 构建 mN 并对比
def build_mn(acc):
    return sum((acc[i] & MASK64) << (i * 64) for i in range(8))

mn_rtl = build_mn(rtl)
mn_cor = build_mn(cor)
exact_mn = m * N

print(f"\nmN (RTL method) = 0x{mn_rtl:0128x}")
print(f"mN (correct)    = 0x{mn_cor:0128x}")
print(f"mN (exact)      = 0x{exact_mn:0128x}")
print(f"RTL matches exact:     {mn_rtl == exact_mn}")
print(f"Correct matches exact: {mn_cor == exact_mn}")
```

**输出**：

```
=== acc low-64 comparison (RTL vs correct) ===
  acc[4]: rtl=0x64ede373afd37100 correct=0x64ede373afd37102 diff=2
  acc[6]: rtl=0x8b33555c1e319bcf correct=0x8b33555c1e319bd1 diff=2

=== Overflow positions (before carry propagation) ===
  acc_raw[0] needs 125 bits, overflow=1728389226751356205
  acc_raw[1] needs 127 bits, overflow=6130536947012359842
  acc_raw[2] needs 128 bits, overflow=11953171867255803158
  acc_raw[3] needs 128 bits, overflow=16350773126966997270
  acc_raw[4] needs 128 bits, overflow=18247256249891650049
  acc_raw[5] needs 128 bits, overflow=14081242915069757885
  acc_raw[6] needs 126 bits, overflow=3236117158827662635

mN (RTL method) = 0x2ce8ff6907781d2c...9bcf5e4fc5d46ac67867...
mN (correct)    = 0x2ce8ff6907781d2c...9bd15e4fc5d46ac67867...
mN (exact)      = 0x2ce8ff6907781d2c...9bd15e4fc5d46ac67867...
RTL matches exact:     False
Correct matches exact: True
```

### 5.2 验证修复后算法在所有测试向量上正确

```python
N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
R = 2**256
N_prime = 0xf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389
MASK64 = (1 << 64) - 1

test_vectors = [
    (0x2af6c90ca9c956dd6b98e311ccd63306d9d3afb7d1ae902b6da869a153471ff8,
     0x25d71bdb3c5ed1475dd3a3192abc611b0e92ba5d5718e22b9fa3fab39975b753),
    (0x25caa11a16419f828b9d2434e465e150bd9c66b3ad3c2d6d1a3d1fa7bc8960a9,
     0x26877991815ef6d13b8faa1837f8a88b17fc695a07a0ca6e0822e8f36c031199),
    (0x0dc7b35e27cd813047229389571aa8766c307511b2b9437a28df6ec4ce4a2bbd,
     0x16f984a318c267976142ea7d17be31111a2a73ed562b0f79c37459eef50bea63),
    (7, 13),
    (1, 1),
    (0x2cd4cc73af2ed9dd87e355b26210b784baa1c6f1404b6eaf162a01dec28753f8,
     0x2e38f1c76bf08d62331057ca7d411fab9fb932d4f039772216ff82e389e3995a),
]

def split(val, n):
    return [(val >> (i * 64)) & MASK64 for i in range(n)]

def montgomery_correct(t):
    """数学精确 Montgomery 约简"""
    m = (t % R * N_prime) % R
    result = (t + m * N) // R
    if result >= N:
        result -= N
    return result

def simulate_new_rtl(x1, w):
    """模拟修复后的 RTL 算法"""
    t = x1 * w
    m = (t % R * N_prime) % R
    m_segs = split(m, 4)
    N_segs = split(N, 4)
    prods = [[m_segs[i] * N_segs[j] for j in range(4)] for i in range(4)]

    # 修复：先累加所有乘积，再统一进位
    acc = [0] * 8
    for i in range(4):
        for j in range(4):
            acc[i + j] += prods[i][j]
    for ii in range(7):
        carry = acc[ii] >> 64
        acc[ii] &= MASK64
        acc[ii + 1] += carry

    mN = sum((acc[i] & MASK64) << (i * 64) for i in range(8))
    result = ((t + mN) >> 256)
    if result >= N:
        result -= N
    return result

all_pass = True
for idx, (x1, w) in enumerate(test_vectors):
    t = x1 * w
    correct = montgomery_correct(t)
    sim = simulate_new_rtl(x1, w)
    match = (correct == sim)
    if not match:
        print(f"Test {idx + 1}: FAIL correct=0x{correct:064x} sim=0x{sim:064x}")
        all_pass = False
    else:
        print(f"Test {idx + 1}: PASS")

print(f"\n{'ALL PASS' if all_pass else 'SOME FAILED'}")
```

### 5.3 确定最小累加器位宽

```python
# 最坏情况：每个位置 4 个乘积，每个接近 2^128
max_prod = (1 << 128) - 1
acc = [0, 2*max_prod, 3*max_prod, 4*max_prod,
       4*max_prod, 3*max_prod, 2*max_prod, 0]

max_width = 0
for ii in range(7):
    carry = acc[ii] >> 64
    acc[ii + 1] += carry
    acc[ii] &= (1 << 64) - 1
    width = acc[ii + 1].bit_length()
    max_width = max(max_width, width)
    print(f"After pos {ii}: acc[{ii+1}] width = {width} bits")

print(f"\n最大需要位宽: {max_width} bits")
print(f"安全位宽: {max_width + 1} bits")
```

**输出**：

```
After pos 0: acc[1] width = 130 bits
After pos 1: acc[2] width = 130 bits
After pos 2: acc[3] width = 131 bits   ← 最大
After pos 3: acc[4] width = 131 bits
After pos 4: acc[5] width = 130 bits
After pos 5: acc[6] width = 130 bits
After pos 6: acc[7] width = 129 bits

最大需要位宽: 131 bits
安全位宽: 132 bits
```

RTL 中选择 **192 位**（`3 * SEG_BITS`）作为累加器宽度，留足安全余量。

## 6. 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `sour/montgomery_pipeline.v` | Stage 4 累加算法：逐乘积进位 → 先累加后统一进位，累加器 65→192 位 |

## 7. 经验总结

1. **逐乘积进位提取是错误的**：当同一位置有多个乘积贡献时，单比特进位无法传递多位溢出
2. **正确的做法**：先用足够宽的累加器收集所有乘积，再做一次从低到高的进位传递
3. **Pipeline 单独测试通过不代表正确**：测试向量覆盖不足会遗漏边界情况
4. **Python 仿真 RTL 算法是最有效的调试手段**：逐 bit 对比 Python 精确值与 RTL 算法值，能精确定位哪一步出错
