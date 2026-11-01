#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;

    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        ++passes;
    }

    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;
    uint32_t a_lo = ua & 0xffffu;
    uint32_t a_hi = ua >> 16;
    uint32_t b_lo = ub & 0xffffu;
    uint32_t b_hi = ub >> 16;

    /* Form the unsigned product as two 32-bit words. */
    uint32_t p = a_lo * b_lo;
    uint32_t cross = a_hi * b_lo + (p >> 16);
    uint32_t hi = a_hi * b_hi + (cross >> 16);

    cross = a_lo * b_hi + (cross & 0xffffu);
    uint32_t lo = (cross << 16) | (p & 0xffffu);
    hi += cross >> 16;

    /* Correct the high word for signed operands. */
    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    uint32_t rounding = 1u << (Q - 1);
    hi += (lo > UINT32_MAX - rounding);
    lo += rounding;

    /* Keep bits 20 through 51 of the rounded product. */
    uint32_t bits = (hi << (32 - Q)) | (lo >> Q);

    if (bits <= (uint32_t) INT32_MAX)
        return (int32_t) bits;
    return -1 - (int32_t) (UINT32_MAX - bits);
}
