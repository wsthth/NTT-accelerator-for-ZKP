#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Reference implementation of Montgomery modular reduction
This should match the hardware pipeline behavior
"""

import sys

N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
TOTAL_BITS = 256
SEG_BITS = 64
SEG_CNT = TOTAL_BITS // SEG_BITS
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

def mont_reduction_ref(t, N, N_prime):
    """
    Reference implementation of Montgomery reduction
    Computes (t * R^(-1)) mod N
    """
    t_low = t & ((1 << TOTAL_BITS) - 1)
    m = (t_low * N_prime) & ((1 << TOTAL_BITS) - 1)

    mN = m * N
    sum_t_mN = t + mN
    result = sum_t_mN >> TOTAL_BITS

    if result >= N:
        result = result - N

    return result

def mont_mult_ref(a_mont, b_mont, N, N_prime):
    """Montgomery multiplication: a_mont * b_mont * R^(-1) mod N"""
    t = a_mont * b_mont
    return mont_reduction_ref(t, N, N_prime)

def main():
    print("=" * 70)
    print("Montgomery Pipeline Reference Model")
    print("=" * 70)

    N_prime = compute_N_prime(N)
    print(f"N_prime = 0x{N_prime:064x}")

    A_MONT = 0x16db3787c008bbc00870a59497036f7f43e71fc1218341741c7bc7cc0ceb3313
    B_MONT = 0x087a1d2b7448c77d0c5a8c4e7241aa9a40f3f294768bdd2611e3d89374ff16f6
    T_512 = A_MONT * B_MONT

    print(f"A_MONT  = 0x{A_MONT:064x}")
    print(f"B_MONT  = 0x{B_MONT:064x}")
    print(f"T_512   = 0x{T_512:0128x}")

    result = mont_mult_ref(A_MONT, B_MONT, N, N_prime)
    print(f"\nReference result: 0x{result:064x}")

    R_inv = modinv(R % N, N)
    a_orig = (A_MONT * R_inv) % N
    b_orig = (B_MONT * R_inv) % N
    print(f"\nRecovered a: 0x{a_orig:064x}")
    print(f"Recovered b: 0x{b_orig:064x}")

    expected_ab = (a_orig * b_orig) % N
    print(f"\n(a * b) mod N      = 0x{expected_ab:064x}")
    print(f"(a * b * R^(-1))   = 0x{result:064x}")

    if result == expected_ab:
        print("\nNote: For these particular values, R^(-1) = 1 mod N")
    else:
        check = (result * R) % N
        print(f"\nCheck: result * R mod N = 0x{check:064x}")
        if check == expected_ab:
            print("Verified: result * R mod N = a * b mod N")
        else:
            print("Warning: result does not match expected pattern")

if __name__ == "__main__":
    main()