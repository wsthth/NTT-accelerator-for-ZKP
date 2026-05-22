#!/usr/bin/env python3
"""
N=8 Mixed-Radix NTT Golden Model
Computes NTT using the same algorithm as the RTL:
  Level 0: radix-8, stride=4
  Level 1: radix-4, stride=2, 2 passes
  Level 2: radix-2, stride=1, 4 passes

Uses Montgomery arithmetic for 256-bit BN254 prime.
"""

# BN254 prime
P = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
R = 2**256  # Montgomery R
N_bits = 256

# Montgomery constants
# N' = -P^-1 mod R
NP = 0x73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff
R2 = 0x0216d0b17f4e44a58c49833d53bb808553fe3ab1e35c59e31bb8e645ae216da7

# Twiddle factors (Montgomery form)
TW0 = 0x0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb  # w^0
TW1 = 0x30109072cf7ff4b4786ecad8a6b247a5bcfdad1300786ada6f4f7b166ec7ccf3  # w^1
TW2 = 0x298866e143f4a463b5beed36493b127ecbf731de9578d0880379bd02d39ee0b4  # w^2
TW3 = 0x26ed7d8602381c364d8feb78fbf29c1033c6ee92681d797726c525389a48e884  # w^3
TW4 = 0x0fdef1af5fb0c3e3bbf016e34cf3960ad843f2cbb248182c588f1421e35e8209  # w^4

def mont_mul(a, b):
    """Montgomery multiplication: (a * b * R^-1) mod P"""
    t = a * b
    m = (t & (R - 1)) * NP % R
    result = (t + m * P) >> 256
    if result >= P:
        result -= P
    return result

def mont_add(a, b):
    """Montgomery addition: (a + b) mod P (inputs already in Montgomery form)"""
    result = a + b
    if result >= P:
        result -= P
    return result

def mont_sub(a, b):
    """Montgomery subtraction: (a - b) mod P"""
    result = a - b
    if result < 0:
        result += P
    return result

def to_mont(x):
    """Convert standard form to Montgomery form: x * R mod P"""
    return (x * R) % P

def from_mont(x):
    """Convert Montgomery form to standard form: x * R^-1 mod P"""
    return mont_mul(x, 1)

def butterfly(x0, x1, w):
    """
    DIT butterfly:
      y0 = (x0 + x1*w) mod P
      y1 = (x0 - x1*w) mod P
    All values in Montgomery form.
    """
    x1w = mont_mul(x1, w)
    y0 = mont_add(x0, x1w)
    y1 = mont_sub(x0, x1w)
    return y0, y1

# Input data (same as testbench, Montgomery form)
data_in = [
    0x0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffb,
    0x1c14ef83340fbe5eccdd46def0f28c5c6df8ed2b3ec19a53592c68389ffffff6,
    0x2a1f6744ce179d8e334bea4e696bd28aa4f563c0de22677d05c29c54effffff1,
    0x07c5909386eddc93e16a48076063c05bb3bdf20e03c9c4156e76dadd4fffffeb,
    0x15d0085520f5bbc347d8eb76d8dd0689eaba68a3a32a913f1b0d0ef99fffffe6,
    0x23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe1,
    0x0180a96573d3d9f85c65ec9f484e3a89307f6d866832bb013057819e4fffffdb,
    0x0f8b21270ddbb927c2d4900ec0c780b7677be41c0793882adcedb5ba9fffffd6,
]

print("=" * 70)
print("N=8 Mixed-Radix NTT Golden Model")
print("=" * 70)
print(f"Prime P = 0x{P:064x}")
print()

# ========== Level 0: Radix-8, stride=4 ==========
print("--- Level 0 (radix-8, stride=4) ---")
print("Butterfly pairs: (0,4), (1,5), (2,6), (3,7)")
print(f"Twiddle factors: w^0={TW0}, w^1={TW1}, w^2={TW2}, w^3={TW3}")

l0 = [0] * 8
twiddles_l0 = [TW0, TW1, TW2, TW3]

# RTL post-transform interleaves results sequentially:
# data_out[0]=core0_add, data_out[1]=core0_sub,
# data_out[2]=core1_add, data_out[3]=core1_sub, ...
# So we store results by core index, not by input index.
for k in range(4):
    i0 = k       # index of x0
    i1 = k + 4   # index of x1 (stride=4)
    w = twiddles_l0[k]
    y0, y1 = butterfly(data_in[i0], data_in[i1], w)
    l0[k*2] = y0     # core k result_add -> output[2*k]
    l0[k*2+1] = y1   # core k result_sub -> output[2*k+1]
    print(f"  Group {k}: data[{i0}] op data[{i1}] * w^{k}")
    print(f"    x0     = 0x{data_in[i0]:064x}")
    print(f"    x1     = 0x{data_in[i1]:064x}")
    print(f"    x1*w   = 0x{mont_mul(data_in[i1], w):064x}")
    print(f"    y0=x0+x1w = 0x{y0:064x}")
    print(f"    y1=x0-x1w = 0x{y1:064x}")

print("\nLevel 0 output:")
for i in range(8):
    print(f"  [{i}] = 0x{l0[i]:064x}")

# Debug: verify individual Montgomery multiplications
print("\n--- Debug: Montgomery multiplication verification ---")
for k in range(4):
    i0 = k
    i1 = k + 4
    w = twiddles_l0[k]
    x1w = mont_mul(data_in[i1], w)
    # Verify: also compute using standard arithmetic
    x1_std = from_mont(data_in[i1])
    w_std = from_mont(w)
    x1w_std = (x1_std * w_std) % P
    x1w_from_std = to_mont(x1w_std)
    print(f"  Group {k}: mont_mul(data_in[{i1}], w^{k})")
    print(f"    mont_result  = 0x{x1w:064x}")
    print(f"    verify_std   = 0x{x1w_from_std:064x}")
    print(f"    match: {x1w == x1w_from_std}")

# Debug: show ALL possible butterfly results for each input pair
print("\n--- Debug: All possible butterfly results ---")
all_bf = {}
for i in range(8):
    for j in range(8):
        if i != j:
            for tw_idx, tw in enumerate([TW0, TW1, TW2, TW3, TW4]):
                y0, y1 = butterfly(data_in[i], data_in[j], tw)
                key = f"bf({i},{j},w^{tw_idx})"
                all_bf[key] = (y0, y1)

# For each RTL output, find exact matches
print("RTL output vs ALL possible butterfly results:")
for idx, rtl_val in enumerate(rtl_l0):
    matches = []
    for key, (y0, y1) in all_bf.items():
        if rtl_val == y0:
            matches.append(f"{key}_add")
        if rtl_val == y1:
            matches.append(f"{key}_sub")
    if matches:
        print(f"  RTL[{idx}] = 0x{rtl_val:064x}")
        print(f"    EXACT MATCHES: {matches}")
    else:
        # Find closest
        best_key = None
        best_diff = None
        for key, (y0, y1) in all_bf.items():
            d0 = rtl_val - y0
            d1 = rtl_val - y1
            if best_diff is None or (d0 != 0 and abs(d0) < abs(best_diff)):
                best_diff = d0
                best_key = f"{key}_add"
            if best_diff is None or (d1 != 0 and abs(d1) < abs(best_diff)):
                best_diff = d1
                best_key = f"{key}_sub"
        print(f"  RTL[{idx}] = 0x{rtl_val:064x}")
        print(f"    NO EXACT MATCH, closest: {best_key} diff={best_diff}")

# ========== Level 1: Radix-4, stride=2, 2 passes ==========
print("\n--- Level 1 (radix-4, stride=2, 2 passes) ---")

# Pass 0 input: the testbench feeds tmp_buf[0..3] (Level 0 outputs [0..3])
input_pass0 = [l0[0], l0[1], l0[2], l0[3]]
# Pass 1 input: the testbench feeds tmp_buf[4..7] (Level 0 outputs [4..7])
input_pass1 = [l0[4], l0[5], l0[6], l0[7]]

# Radix-4: 2 butterfly cores, stride=2
# Pre-transform pairs: (data[k], data[k+stride]) for k=0..stride-1
# Group 0: (input[0], input[2]), Group 1: (input[1], input[3])
# Post-transform: [core0_add, core0_sub, core1_add, core1_sub]

twiddles_l1 = [TW0, TW4]  # w^0 and w^4 (for radix-4 twiddle)

# Pass 0: elements [0,1,2,3]
print("Pass 0: elements [0,1,2,3]")

# Group 0: (input[0], input[2]) * twiddle[0]
y0_0, y1_0 = butterfly(input_pass0[0], input_pass0[2], twiddles_l1[0])
# Group 1: (input[1], input[3]) * twiddle[1]
y0_1, y1_1 = butterfly(input_pass0[1], input_pass0[3], twiddles_l1[1])

print(f"  Group 0: (in[0], in[2]) * w^0")
print(f"    result_add = 0x{y0_0:064x}")
print(f"    result_sub = 0x{y1_0:064x}")
print(f"  Group 1: (in[1], in[3]) * w^4")
print(f"    result_add = 0x{y0_1:064x}")
print(f"    result_sub = 0x{y1_1:064x}")

# Post-transform sequential: [core0_add, core0_sub, core1_add, core1_sub]
l1_pass0 = [y0_0, y1_0, y0_1, y1_1]
print(f"  Pass 0 output: {[f'0x{v:064x}' for v in l1_pass0]}")

# Pass 1: elements [4,5,6,7]
print("Pass 1: elements [4,5,6,7]")

# Group 0: (input[4], input[6]) * twiddle[0]
y0_2, y1_2 = butterfly(input_pass1[0], input_pass1[2], twiddles_l1[0])
# Group 1: (input[5], input[7]) * twiddle[1]
y0_3, y1_3 = butterfly(input_pass1[1], input_pass1[3], twiddles_l1[1])

print(f"  Group 0: (in[4], in[6]) * w^0")
print(f"    result_add = 0x{y0_2:064x}")
print(f"    result_sub = 0x{y1_2:064x}")
print(f"  Group 1: (in[5], in[7]) * w^4")
print(f"    result_add = 0x{y0_3:064x}")
print(f"    result_sub = 0x{y1_3:064x}")

l1_pass1 = [y0_2, y1_2, y0_3, y1_3]
print(f"  Pass 1 output: {[f'0x{v:064x}' for v in l1_pass1]}")

# Combine
l1 = l1_pass0 + l1_pass1
print("\nLevel 1 output:")
for i in range(8):
    print(f"  [{i}] = 0x{l1[i]:064x}")

# ========== Level 2: Radix-2, stride=1, 4 passes ==========
print("\n--- Level 2 (radix-2, stride=1, 4 passes) ---")

twiddles_l2 = [TW0]  # w^0 only for radix-2

# Level 1 outputs feed into Level 2 as:
# Pass 0: l1[0], l1[1]
# Pass 1: l1[2], l1[3]
# Pass 2: l1[4], l1[5]
# Pass 3: l1[6], l1[7]

l2 = [0] * 8
for pass_num in range(4):
    in0 = l1[pass_num * 2]
    in1 = l1[pass_num * 2 + 1]
    # Core 0: (in0, in1) * w^0
    y0, y1 = butterfly(in0, in1, twiddles_l2[0])
    l2[pass_num * 2] = y0
    l2[pass_num * 2 + 1] = y1
    print(f"  Pass {pass_num}: (0x{in0:064x}, 0x{in1:064x}) * w^0")
    print(f"    result_add = 0x{y0:064x}")
    print(f"    result_sub = 0x{y1:064x}")

print("\nLevel 2 output (NTT result):")
for i in range(8):
    print(f"  [{i}] = 0x{l2[i]:064x}")

# ========== Convert to standard form for verification ==========
print("\n--- Standard form (divide by R) ---")
for i in range(8):
    std = from_mont(l2[i])
    print(f"  [{i}] = 0x{std:064x}")

# ========== Compare with RTL output ==========
print("\n" + "=" * 70)
print("Comparison with RTL output")
print("=" * 70)

rtl_l0 = [
    0x23da8016bafd9af2ae478ee651564cb821b6df39428b5e68c7a34315efffffe2,
    0x289ebddf5a43c395d6e5fdaf211d98017475f63a75efac7bd56b1ab6a0000015,
    0x2000d36c26c56d8fed95fcfc80a13652bb45636b0829ec60a403af92ad6421c8,
    0x18290b9a415a0f2dac2490c16143e26620ac76eb755948460e5520de929bde24,
    0x2bc9db1eacec54cc33e450281447edad2a13a51e39a6135c0b3654c705ceeb72,
    0x2874f36aef42e65032b38474be8fb7681fd72263829ebb9e004ee3e2da311470,
    0x18a946b19205c493d4ccf811c81e73016ac9d7a73d9bd1f2c8e8183a52626eab,
    0x274628e85d0794bda657ddb37a2a661324e5f4bd43b126c957e793143d9d912c,
]

# Also show which Python butterfly output matches each RTL output
all_py = {}
all_py["G0_add"] = l0[0]
all_py["G0_sub"] = l0[1]
all_py["G1_add"] = l0[2]
all_py["G1_sub"] = l0[3]
all_py["G2_add"] = l0[4]
all_py["G2_sub"] = l0[5]
all_py["G3_add"] = l0[6]
all_py["G3_sub"] = l0[7]

print("\nLevel 0:")
for i in range(8):
    # Find closest match
    best_match = None
    best_diff = None
    for name, val in all_py.items():
        d = rtl_l0[i] - val
        if best_diff is None or abs(d) < abs(best_diff):
            best_diff = d
            best_match = name
    match_info = f"closest={best_match} diff={best_diff}" if best_diff != 0 else "EXACT MATCH"
    print(f"  [{i}] RTL=0x{rtl_l0[i]:064x}")
    print(f"       PY =0x{l0[i]:064x}  {match_info}")
