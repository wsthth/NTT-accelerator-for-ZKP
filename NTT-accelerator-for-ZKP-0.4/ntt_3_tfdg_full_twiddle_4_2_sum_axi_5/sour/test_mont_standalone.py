# Generate the 512-bit product for core 3 to use as test input
P = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
R = 1 << 256
R_mod_P = R % P
def to_mont(a): return (a * R_mod_P) % P

x1m = to_mont(8)
wm = to_mont(pow(5, 3*(P-1)//8, P))
full_product = x1m * wm  # 512-bit

# Print as Verilog hex
print(f"// Core 3 Montgomery product test")
print(f"// x1_mont = 0x{x1m:064x}")
print(f"// w_mont  = 0x{wm:064x}")
print(f"// full_product = 0x{full_product:0128x}")
print(f"localparam [511:0] TEST_T = 512'h{full_product:0128x};")
print(f"localparam [255:0] TEST_N = 256'h{P:064x};")
NP = 0x73f82f1d0d8341b2e39a9828990623916586864b4c6911b3c2e1f593efffffff
print(f"localparam [255:0] TEST_NP = 256'h{NP:064x};")

# Expected result
m = (full_product % R) * NP % R
mN = m * P
s = full_product + mN
result = s >> 256
if result >= P: result -= P
print(f"// Expected mont_result = 0x{result:064x}")
