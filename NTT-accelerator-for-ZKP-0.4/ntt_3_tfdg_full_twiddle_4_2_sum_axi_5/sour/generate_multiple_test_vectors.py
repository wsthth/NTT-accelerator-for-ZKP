#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate multiple test vectors for Montgomery pipeline
"""

N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
TOTAL_BITS = 256
R = 1 << TOTAL_BITS

def modinv(a, m):
    if a < 0:
        a = a % m
    g, x, _ = extended_gcd(a, m)
    if g != 1:
        raise ValueError("Modular inverse does not exist")
    return x % m

def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y

def compute_N_prime(N):
    N_inv = modinv(N % R, R)
    N_prime = (-N_inv) % R
    return N_prime

def mont_mult_ref(a_mont, b_mont, N, N_prime):
    t = a_mont * b_mont
    t_low = t & ((1 << TOTAL_BITS) - 1)
    m = (t_low * N_prime) & ((1 << TOTAL_BITS) - 1)
    mN = m * N
    sum_t_mN = t + mN
    result = sum_t_mN >> TOTAL_BITS
    if result >= N:
        result = result - N
    return result, t

def main():
    N_prime = compute_N_prime(N)
    
    test_vectors = []

    # Test vector 1: Small numbers
    a1 = 0x1234
    b1 = 0x5678
    a1_mont = (a1 * R) % N
    b1_mont = (b1 * R) % N
    result1, t1 = mont_mult_ref(a1_mont, b1_mont, N, N_prime)
    test_vectors.append(("Small numbers", a1_mont, b1_mont, t1, result1))

    # Test vector 2: Original test case
    a2_mont = 0x16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313
    b2_mont = 0x087a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6
    result2, t2 = mont_mult_ref(a2_mont, b2_mont, N, N_prime)
    test_vectors.append(("Original", a2_mont, b2_mont, t2, result2))

    # Test vector 3: Large numbers near N
    a3 = N - 1
    b3 = 2
    a3_mont = (a3 * R) % N
    b3_mont = (b3 * R) % N
    result3, t3 = mont_mult_ref(a3_mont, b3_mont, N, N_prime)
    test_vectors.append(("N-1 * 2", a3_mont, b3_mont, t3, result3))

    # Test vector 4: All ones
    a4 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    b4 = 0x1
    a4_mont = (a4 * R) % N
    b4_mont = (b4 * R) % N
    result4, t4 = mont_mult_ref(a4_mont, b4_mont, N, N_prime)
    test_vectors.append(("All ones * 1", a4_mont, b4_mont, t4, result4))

    # Test vector 5: Random test
    a5 = 0xDEADBEEF1234567890ABCDEF00000000FEDCBA9876543210DEADBEEF12345678
    b5 = 0xCAFEBABE9876543210FEDCBA9876543210CAFEBABE9876543210CAFEBABE
    a5_mont = (a5 * R) % N
    b5_mont = (b5 * R) % N
    result5, t5 = mont_mult_ref(a5_mont, b5_mont, N, N_prime)
    test_vectors.append(("Random", a5_mont, b5_mont, t5, result5))

    # Test vector 6: One
    a6 = 1
    b6 = N - 1
    a6_mont = (a6 * R) % N
    b6_mont = (b6 * R) % N
    result6, t6 = mont_mult_ref(a6_mont, b6_mont, N, N_prime)
    test_vectors.append(("1 * (N-1)", a6_mont, b6_mont, t6, result6))

    # Print Verilog format
    print("// =====================================================")
    print("// Test Vectors for Montgomery Pipeline")
    print("// =====================================================")
    print("")
    print(f"localparam [TOTAL_BITS-1:0] TEST_N_PRIME = 256'h{N_prime:064x};")
    print("")
    
    for i, (name, a_m, b_m, t, result) in enumerate(test_vectors):
        print(f"// Test {i+1}: {name}")
        print(f"localparam [TOTAL_BITS-1:0] A_MONT_{i+1} = 256'h{a_m:064x};")
        print(f"localparam [TOTAL_BITS-1:0] B_MONT_{i+1} = 256'h{b_m:064x};")
        print(f"localparam [2*TOTAL_BITS-1:0] T_{i+1}     = 512'h{t:0128x};")
        print(f"localparam [TOTAL_BITS-1:0] EXP_{i+1}    = 256'h{result:064x};")
        print("")

    print(f"localparam NUM_TESTS = {len(test_vectors)};")

if __name__ == "__main__":
    main()