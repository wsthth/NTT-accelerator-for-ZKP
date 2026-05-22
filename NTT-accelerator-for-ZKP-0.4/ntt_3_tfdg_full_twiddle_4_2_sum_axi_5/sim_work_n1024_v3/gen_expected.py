#!/usr/bin/env python3
"""
Generate expected values for N=1024 Level 0 (radix-8, stride=4)
Only generate first 4 passes for quick verification.
"""

# BN254 prime
P = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
R = 2**256
NP = 0x73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff

# Twiddle factors (Montgomery form) for Level 0
TW0 = 0x0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb  # w^0
TW1 = 0x30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3  # w^1
TW2 = 0x298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4  # w^2
TW3 = 0x26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884  # w^3

def mont_mul(a, b):
    t = a * b
    m = (t & (R - 1)) * NP % R
    result = (t + m * P) >> 256
    if result >= P:
        result -= P
    return result

def mont_add(a, b):
    result = a + b
    if result >= P:
        result -= P
    return result

def mont_sub(a, b):
    result = a - b
    if result < 0:
        result += P
    return result

def butterfly(x0, x1, w):
    x1w = mont_mul(x1, w)
    y0 = mont_add(x0, x1w)
    y1 = mont_sub(x0, x1w)
    return y0, y1

# Read input data
input_data = []
with open("ntt_input_1024.txt", "r") as f:
    for line in f:
        line = line.strip()
        if line:
            input_data.append(int(line, 16))

print(f"Loaded {len(input_data)} input values")
print(f"Prime P = 0x{P:064x}")
print()

# Level 0: radix-8, stride=4
# Each pass processes 8 elements: (data[k], data[k+4]) for k=0..3
# 4 butterfly cores in parallel
# 128 passes total for N=1024

twiddles = [TW0, TW1, TW2, TW3]

print("=" * 70)
print("N=1024 Level 0: First 4 passes")
print("=" * 70)

# Generate expected values for first 4 passes
for pass_num in range(4):
    base = pass_num * 8
    print(f"\n--- Pass {pass_num} (elements [{base}:{base+7}]) ---")

    # RTL post-transform output order: [core0_add, core0_sub, core1_add, core1_sub, ...]
    for k in range(4):
        i0 = base + k       # x0 index
        i1 = base + k + 4   # x1 index (stride=4)
        w = twiddles[k]

        x0 = input_data[i0]
        x1 = input_data[i1]

        y0, y1 = butterfly(x0, x1, w)

        print(f"  Core {k}: data[{i0}] op data[{i1}] * w^{k}")
        print(f"    result_add = 0x{y0:064x}")
        print(f"    result_sub = 0x{y1:064x}")

print("\n" + "=" * 70)
print("RTL output format (for testbench comparison):")
print("=" * 70)

# Generate expected array in RTL output order
expected = []
for pass_num in range(4):
    base = pass_num * 8
    for k in range(4):
        i0 = base + k
        i1 = base + k + 4
        w = twiddles[k]
        y0, y1 = butterfly(input_data[i0], input_data[i1], w)
        expected.append(y0)
        expected.append(y1)

# Print as Verilog localparam
print("\n// Expected output for first 4 passes (RTL output order)")
for i, val in enumerate(expected):
    pass_num = i // 8
    idx = i % 8
    print(f"localparam [255:0] EXP_{pass_num}_{idx} = 256'h{val:064x};")
