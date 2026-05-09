#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Montgomery Multiplication Test Vector Generator
Generates correct test vectors for Montgomery modular reduction pipeline
"""

import sys

# BN254 curve modulus
N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
TOTAL_BITS = 256
R = 1 << TOTAL_BITS  # R = 2^256

def modinv(a, m):
    """Compute a^(-1) mod m using extended Euclidean algorithm"""
    if a < 0:
        a = a % m
    g, x, _ = extended_gcd(a, m)
    if g != 1:
        raise ValueError("Modular inverse does not exist")
    return x % m

def extended_gcd(a, b):
    """Extended Euclidean algorithm"""
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y

def compute_N_prime(N):
    """Compute N' = -N^(-1) mod R"""
    N_inv = modinv(N % R, R)
    N_prime = (-N_inv) % R
    return N_prime

def mont_mult(a_mont, b_mont, N, N_prime):
    """
    Montgomery modular multiplication
    Computes a_mont * b_mont * R^(-1) mod N
    where a_mont = a * R mod N, b_mont = b * R mod N
    """
    t = a_mont * b_mont  # 512-bit
    t_low = t & ((1 << TOTAL_BITS) - 1)  # t mod R
    m = (t_low * N_prime) & ((1 << TOTAL_BITS) - 1)  # m mod R
    mN = m * N
    sum_t_mN = t + mN
    result = sum_t_mN >> TOTAL_BITS
    if result >= N:
        result = result - N
    return result, t, m, mN

def compute_expected_result(a, b, N):
    """Compute expected result (a * b) mod N"""
    return (a * b) % N

def compute_a_mont(a, N, R):
    """Compute Montgomery form: a_mont = a * R mod N"""
    return (a * R) % N

def compute_b_mont(b, N, R):
    """Compute Montgomery form: b_mont = b * R mod N"""
    return (b * R) % N

def main():
    print("=" * 70)
    print("Montgomery Multiplication Test Vector Generator")
    print("=" * 70)
    print(f"\nBN254 Prime N (256-bit):")
    print(f"  N = 0x{N:064x}")

    N_prime = compute_N_prime(N)
    print(f"\nN' (precomputed as -N^(-1) mod R):")
    print(f"  N_prime = 0x{N_prime:064x}")

    # Test Vector 2: Original test values from montgomery_top.v
    print("\n" + "=" * 70)
    print("Test Vector 2: Original test values from montgomery_top.v")
    print("=" * 70)

    A_MONT = 0x16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313
    B_MONT = 0x87a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6
    T_512_ORIG = 0xc1c0cf6b3053366c04cc5be157a618a4b05dc32dbba48398976daccbcd6a4bf7692fac951ce65ecc6b353dff255768a7b9b946411649b0e73854861c53b642

    print(f"\nInput values:")
    print(f"  A_MONT = 0x{A_MONT:064x}")
    print(f"  B_MONT = 0x{B_MONT:064x}")

    t_actual = A_MONT * B_MONT
    print(f"\nActual t = A_MONT * B_MONT:")
    print(f"  t_actual = 0x{t_actual:0128x}")

    print(f"\nOriginal T_512 in file:")
    print(f"  T_512    = 0x{T_512_ORIG:0128x}")

    if t_actual == T_512_ORIG:
        print(f"  [OK] T_512 matches!")
    else:
        print(f"  [MISMATCH] T_512 mismatch!")
        print(f"  Should use: 0x{t_actual:0128x}")

    t_low = t_actual & ((1 << TOTAL_BITS) - 1)
    m = (t_low * N_prime) & ((1 << TOTAL_BITS) - 1)
    mN = m * N
    sum_t_mN = t_actual + mN
    result = sum_t_mN >> TOTAL_BITS

    if result >= N:
        result = result - N

    print(f"\nMontgomery reduction result:")
    print(f"  result = 0x{result:064x}")

    R_inv = modinv(R % N, N)
    a_recovered = (A_MONT * R_inv) % N
    b_recovered = (B_MONT * R_inv) % N

    print(f"\nRecovered original values from Montgomery forms:")
    print(f"  a = a_mont * R^(-1) mod N = 0x{a_recovered:064x}")
    print(f"  b = b_mont * R^(-1) mod N = 0x{b_recovered:064x}")

    expected_from_recovered = (a_recovered * b_recovered) % N
    print(f"\nExpected (a * b mod N) = 0x{expected_from_recovered:064x}")
    print(f"Montgomery result      = 0x{result:064x}")

    if expected_from_recovered == result:
        print(f"\n[VERIFIED] Montgomery result matches (a * b mod N)!")
    else:
        print(f"\n[MISMATCH]")

    # Test Vector 3: Small test with full verification
    print("\n" + "=" * 70)
    print("Test Vector 3: Small test with full verification")
    print("=" * 70)

    a_test = 0x1234
    b_test = 0x5678

    a_mont_test = (a_test * R) % N
    b_mont_test = (b_test * R) % N
    t_test = a_mont_test * b_mont_test

    mont_result_test, _, _, _ = mont_mult(a_mont_test, b_mont_test, N, N_prime)
    expected_test = (a_test * b_test) % N

    print(f"\na = 0x{a_test:064x}")
    print(f"b = 0x{b_test:064x}")
    print(f"a_mont = 0x{a_mont_test:064x}")
    print(f"b_mont = 0x{b_mont_test:064x}")
    print(f"t = 0x{t_test:0128x}")
    print(f"mont_result = 0x{mont_result_test:064x}")
    print(f"expected (a*b mod N) = 0x{expected_test:064x}")

    if mont_result_test == expected_test:
        print(f"\n[OK] Small test PASSED")
    else:
        print(f"\n[FAIL] Small test FAILED")

    print("\n" + "=" * 70)
    print("Summary: Correct Values for montgomery_top.v")
    print("=" * 70)

    print(f"""
// Replace these values in montgomery_top.v:

// N' = -N^(-1) mod R
localparam [TOTAL_BITS-1:0] N_prime = 256'h{N_prime:064x};

// For Test Vector 2 (original values):
localparam [TOTAL_BITS-1:0] A_MONT = 256'h{A_MONT:064x};
localparam [TOTAL_BITS-1:0] B_MONT = 256'h{B_MONT:064x};
localparam [2*TOTAL_BITS-1:0] T_512 = 512'h{t_actual:0128x};
localparam [TOTAL_BITS-1:0] EXPECTED_RESULT = 256'h{expected_from_recovered:064x};
""")

if __name__ == "__main__":
    main()