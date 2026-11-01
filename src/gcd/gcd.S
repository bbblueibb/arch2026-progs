# Binary GCD with direct subtraction and compact shift loops.
# a0 = a, a1 = b; result in a0.
# t0 = common factor-of-two count; t1 = scratch.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, zero, .Lreturn_b
    beq     a1, zero, .Lreturn_a
    li      t0, 0

# Remove common factors of two.
.Lcommon_twos:
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, zero, .Linit_b
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    j       .Lcommon_twos

# Initially make b odd.
.Linit_b:
    andi    t1, a1, 1
    bne     t1, zero, .Linit_a
.Linit_b_shift:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, zero, .Linit_b_shift

# Initially make a odd.
.Linit_a:
    andi    t1, a0, 1
    bne     t1, zero, .Lcompare

# This path receives a positive even value in a0.
.Lshift_a:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, zero, .Lshift_a

# Both operands are positive and odd.
.Lcompare:
    bltu    a0, a1, .Lsubtract_b
    beq     a0, a1, .Ldone
    sub     a0, a0, a1
    j       .Lshift_a

.Lsubtract_b:
    sub     a1, a1, a0

# The difference is positive and even.
.Lshift_b:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, zero, .Lshift_b
    j       .Lcompare

.Ldone:
    sll     a0, a0, t0
    ret

.Lreturn_b:
    mv      a0, a1
.Lreturn_a:
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
