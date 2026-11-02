#!/usr/bin/env python3
"""Measure actual host q_mul against exact integer/rational references.

Usage: python3 mytests/fixed_error.py /tmp/hw2-fixed-impl.so
The real product is (a*b)/2**40; the decoded output is result/2**20.
Integer arithmetic keeps reference errors exact. Floats format output only.
"""
import ctypes
from fractions import Fraction
from pathlib import Path
import random
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: fixed_error.py PATH_TO_SHARED_LIBRARY")
    library = ctypes.CDLL(str(Path(sys.argv[1]).resolve()))
    product = library.q_mul
    product.argtypes = [ctypes.c_int32, ctypes.c_int32]
    product.restype = ctypes.c_int32
    q = 20
    lower, upper = -(1 << 31), (1 << 31) - 1
    values = [lower, lower + 1, -(1 << 30), -(1 << 20), -(1 << 19),
              -3, -2, -1, 0, 1, 2, 3, 1 << 19, 1 << 20,
              1 << 30, upper - 1, upper]
    rng = random.Random(20261102)

    def samples():
        for a in values:
            for b in values:
                yield a, b
        for _ in range(100000):
            a, b = rng.getrandbits(32), rng.getrandbits(32)
            yield a - (1 << 32) if a >> 31 else a, b - (1 << 32) if b >> 31 else b
        # All products in this population fit after rounding; this avoids
        # mostly testing wrap-around with full-width random operands.
        for _ in range(100000):
            yield rng.randrange(-(1 << 25), 1 << 25), rng.randrange(-(1 << 25), 1 << 25)

    counts = {"samples": 0, "nonwrapping": 0, "wrapping": 0,
              "contract_mismatches": 0, "nonwrapping_ties": 0}
    max_stored_difference = 0
    max_error_numerator = -1
    worst = None
    minimum_error_numerator = None
    maximum_signed_error_numerator = None
    for a, b in samples():
        exact_product = a * b
        rounded = (exact_product + (1 << (q - 1))) >> q
        expected = ((rounded + (1 << 31)) % (1 << 32)) - (1 << 31)
        actual = int(product(a, b))
        counts["samples"] += 1
        difference = abs(actual - expected)
        max_stored_difference = max(max_stored_difference, difference)
        if difference:
            counts["contract_mismatches"] += 1
            if counts["contract_mismatches"] <= 3:
                print("MISMATCH:", a, b, actual, expected)
        if not lower <= rounded <= upper:
            counts["wrapping"] += 1
            continue
        counts["nonwrapping"] += 1
        if exact_product % (1 << q) == 1 << (q - 1):
            counts["nonwrapping_ties"] += 1
        error = (actual << q) - exact_product
        if abs(error) > max_error_numerator:
            max_error_numerator = abs(error)
            worst = (a, b, actual, expected)
        minimum_error_numerator = error if minimum_error_numerator is None else min(minimum_error_numerator, error)
        maximum_signed_error_numerator = error if maximum_signed_error_numerator is None else max(maximum_signed_error_numerator, error)

    absolute_error = Fraction(max_error_numerator, 1 << (2 * q))
    print("Reference: exact Python integers and rational decoding; no binary64 reference rounding")
    print("Sampling: 17x17 directed grid + 100000 full-width random pairs + 100000 bounded random pairs")
    print("Seed: 20261102")
    print("COUNTS:", counts)
    print("Maximum stored-result difference from wrapped contract:", max_stored_difference)
    print("Nonwrapping maximum absolute real-value error:", absolute_error)
    print("Nonwrapping maximum absolute real-value error (decimal):", format(float(absolute_error), ".15g"))
    print("Nonwrapping maximum error in stored-value units:", Fraction(max_error_numerator, 1 << q))
    print("Worst (stored a, stored b, actual, expected):", worst)
    print("Nonwrapping signed-error range:",
          Fraction(minimum_error_numerator, 1 << (2 * q)),
          Fraction(maximum_signed_error_numerator, 1 << (2 * q)))
    print("Wrapping cases are checked against the wrapped integer contract and excluded from the small real-value error bound.")
    if counts["contract_mismatches"] or max_error_numerator > 1 << (q - 1):
        raise SystemExit("FAIL: contract or nonwrapping error bound")
    print("PASS: tested contract results match; measured nonwrapping errors satisfy 2^-21.")


if __name__ == "__main__":
    main()
