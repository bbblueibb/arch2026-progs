"""Measure the actual BF16 C implementation against binary64 references."""
import bisect
import ctypes
import math
import random
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: bf16_error.py PATH_TO_SHARED_LIBRARY")

print("Python:", sys.version.split()[0],
      "reference mantissa bits:", sys.float_info.mant_dig)
lib = ctypes.CDLL(sys.argv[1])
lib.bf16_from_f32.argtypes = [ctypes.c_uint32]
lib.bf16_from_f32.restype = ctypes.c_uint16
lib.bf16_mul.argtypes = [ctypes.c_uint16, ctypes.c_uint16]
lib.bf16_mul.restype = ctypes.c_uint16
lib.bf16_sqrt.argtypes = [ctypes.c_uint16]
lib.bf16_sqrt.restype = ctypes.c_uint16


def decode(bits, fraction_bits, exponent_bits, bias):
    fraction = bits & ((1 << fraction_bits) - 1)
    exponent = (bits >> fraction_bits) & ((1 << exponent_bits) - 1)
    negative = bits >> (fraction_bits + exponent_bits)
    if exponent == (1 << exponent_bits) - 1:
        value = math.nan if fraction else math.inf
    elif exponent == 0:
        value = math.ldexp(float(fraction), 1 - bias - fraction_bits)
    else:
        value = math.ldexp(float((1 << fraction_bits) + fraction),
                           exponent - bias - fraction_bits)
    return -value if negative else value


values = [decode(x, 7, 8, 127) for x in range(65536)]
positive_finite = values[:0x7f80]
minimum_normal = math.ldexp(1.0, -126)


def new_stats():
    return {"n": 0, "total": 0.0, "maximum": -1.0, "case": None}


def record(stats, actual, reference, case):
    relative = abs(actual - reference) / abs(reference)
    stats["n"] += 1
    stats["total"] += relative
    if relative > stats["maximum"]:
        stats["maximum"] = relative
        stats["case"] = case


def show(label, stats):
    if not stats["n"]:
        print(label + ": no samples")
        return
    print(label)
    print("  samples=%d max_relative=%.9f%% mean_relative=%.9f%%" %
          (stats["n"], 100 * stats["maximum"],
           100 * stats["total"] / stats["n"]))
    print("  worst_input_and_output=" +
          ", ".join("0x%08X" % x for x in stats["case"]))


# Every retained half, with five discarded halves around rounding boundaries.
conversion_normal = new_stats()
conversion_small = new_stats()
conversion_counts = {"samples": 0, "special_inputs": 0, "zero_inputs": 0,
                     "overflow_outputs": 0, "nan_to_infinity": 0}
for high in range(65536):
    for low in (0, 0x7fff, 0x8000, 0x8001, 0xffff):
        bits = (high << 16) | low
        out = lib.bf16_from_f32(bits)
        reference = decode(bits, 23, 8, 127)
        actual = values[out]
        conversion_counts["samples"] += 1
        if not math.isfinite(reference):
            conversion_counts["special_inputs"] += 1
            if math.isnan(reference) and math.isinf(actual):
                conversion_counts["nan_to_infinity"] += 1
        elif reference == 0:
            conversion_counts["zero_inputs"] += 1
        elif math.isinf(actual):
            conversion_counts["overflow_outputs"] += 1
        else:
            if not math.isfinite(actual):
                raise RuntimeError("Unexpected conversion NaN")
            stats = conversion_normal if (out & 0x7f80) else conversion_small
            record(stats, actual, reference, (bits, out))

print("CONVERSION COUNTS:", conversion_counts)
show("F32 conversion: finite normal outputs", conversion_normal)
show("F32 conversion: subnormal or zero outputs", conversion_small)


# Full input columns plus deterministic random pairs; not all 2^32 pairs.
product_normal = new_stats()
product_small = new_stats()
product_counts = {"samples": 0, "special_inputs": 0, "zero_products": 0,
                  "overflow_outputs": 0}


def measure_product(a, b):
    out = lib.bf16_mul(a, b)
    x, y, actual = values[a], values[b], values[out]
    product_counts["samples"] += 1
    if not math.isfinite(x) or not math.isfinite(y):
        product_counts["special_inputs"] += 1
        return
    reference = x * y
    if reference == 0:
        product_counts["zero_products"] += 1
    elif math.isinf(actual):
        product_counts["overflow_outputs"] += 1
    else:
        if not math.isfinite(actual):
            raise RuntimeError("Unexpected product NaN")
        stats = product_small if abs(reference) < minimum_normal else product_normal
        record(stats, actual, reference, (a, b, out))


for b in (0x3f80, 0x4000, 0x3f00, 0xbf80,
          0x3f81, 0x7f7f, 0x0001, 0x7f80):
    for a in range(65536):
        measure_product(a, b)
rng = random.Random(0xb16f)
for _ in range(100000):
    measure_product(rng.randrange(65536), rng.randrange(65536))

print("PRODUCT COUNTS:", product_counts)
show("Product: normal-region finite results", product_normal)
show("Product: underflow-region finite results", product_small)


# Every positive normal BF16 input; binary64 sqrt is the numerical reference.
square_root = new_stats()
different_from_nearest = 0
maximum_ulp = -1.0
ulp_case = None
for bits in range(0x0080, 0x7f80):
    out = lib.bf16_sqrt(bits)
    reference = math.sqrt(values[bits])
    actual = values[out]
    if not math.isfinite(actual) or actual <= 0:
        raise RuntimeError("Unexpected square-root class")
    record(square_root, actual, reference, (bits, out))

    # References here lie strictly inside the normal BF16 range.
    upper = bisect.bisect_left(positive_finite, reference)
    lower = upper - 1
    dl = reference - positive_finite[lower]
    du = positive_finite[upper] - reference
    nearest = lower if dl < du or (dl == du and lower % 2 == 0) else upper
    different_from_nearest += out != nearest

    # One BF16 ulp in the binade containing the reference: 2^(e - 7).
    unit = math.ldexp(1.0, math.frexp(reference)[1] - 8)
    error_ulp = abs(actual - reference) / unit
    if error_ulp > maximum_ulp:
        maximum_ulp = error_ulp
        ulp_case = (bits, out, nearest)

show("Square root: all positive normal inputs", square_root)
print("  different_from_nearest=%d max_ulp=%.9f" %
      (different_from_nearest, maximum_ulp))
print("  worst_ulp_input_output_nearest=" +
      ", ".join("0x%04X" % x for x in ulp_case))
print("References use host binary64 arithmetic, not exact real arithmetic.")
