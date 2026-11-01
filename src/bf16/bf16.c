#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits & 0x7f800000u) == 0x7f800000u)
        return (uint16_t) (f32bits >> 16);

    uint32_t tie = (f32bits >> 16) & 1u;
    return (uint16_t) ((f32bits + 0x7fffu + tie) >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;
    int ea = (a >> 7) & 0xff;
    int eb = (b >> 7) & 0xff;
    uint32_t ma = a & 0x7fu;
    uint32_t mb = b & 0x7fu;

    /* The contract examines a before b. */
    if (ea == 0xff) {
        if (ma != 0)
            return a;
        if ((b & 0x7fffu) == 0)
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }
    if (eb == 0xff) {
        if (mb != 0)
            return b;
        if ((a & 0x7fffu) == 0)
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }
    if ((a & 0x7fffu) == 0 || (b & 0x7fffu) == 0)
        return (uint16_t) sign;

    /* Normalize finite nonzero significands to [128, 255]. */
    if (ea == 0) {
        ea = 1;
        while (ma < 0x80u) {
            ma <<= 1;
            --ea;
        }
    } else {
        ma |= 0x80u;
    }
    if (eb == 0) {
        eb = 1;
        while (mb < 0x80u) {
            mb <<= 1;
            --eb;
        }
    } else {
        mb |= 0x80u;
    }

    int exponent = ea + eb - 127;
    uint32_t product = ma * mb;
    if ((product & 0x8000u) != 0) {
        product >>= 1;
        ++exponent;
    }

    uint32_t significand = product >> 7;
    if (exponent >= 0xff)
        return (uint16_t) (sign | 0x7f80u);
    if (exponent <= 0) {
        if (exponent < -6)
            return (uint16_t) sign;

        significand &= 0x7fu;
        significand >>= (unsigned) (1 - exponent);
        return (uint16_t) (sign | significand);
    }
    return (uint16_t) (sign | ((uint32_t) exponent << 7) |
                       (significand & 0x7fu));
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exponent = (a >> 7) & 0xffu;
    uint32_t fraction = a & 0x7fu;

    if (exponent == 0xffu) {
        if (fraction != 0)
            return a;
        return (a & 0x8000u) != 0 ? 0x7fc0u : a;
    }
    if ((a & 0x7fffu) == 0)
        return 0;
    if ((a & 0x8000u) != 0)
        return 0x7fc0u;
    if (exponent == 0)
        return 0;

    int e = (int) exponent - 127;
    uint32_t m = 0x80u | fraction;
    /* An even biased exponent means an odd unbiased exponent. */
    if ((exponent & 1u) == 0) {
        m <<= 1;
        --e;
    }

    uint32_t low = 90;
    uint32_t high = 256;
    uint32_t root = 0;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if (((mid * mid) >> 7) <= m) {
            root = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* Positive normals give root in [128, 255] and exponent in [64, 190]. */
    int result_exponent = e / 2 + 127;
    return (uint16_t) (((uint32_t) result_exponent << 7) | (root & 0x7fu));
}
