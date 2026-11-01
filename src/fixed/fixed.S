# Logic arithmetic and Q11.20 multiplication, RV32I only.
# Arguments: a0 = a, a1 = b; op1 also receives n in a2.
# Return value: a0. Only caller-saved registers are modified.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0
    beq     a1, zero, .Lop1_done
.Lop1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bne     a1, zero, .Lop1_loop
.Lop1_done:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
# t1:t0 = shifted unsigned multiplicand.
# t3:t2 = accumulated unsigned product.
# t4 = remaining multiplier bits; preserve a0 and a1 for sign correction.
    mv      t0, a0
    li      t1, 0
    li      t2, 0
    li      t3, 0
    mv      t4, a1
    beq     t4, zero, .Lq_product_done

.Lq_loop:
    andi    t5, t4, 1
    beq     t5, zero, .Lq_next
    add     t2, t2, t0
    sltu    t5, t2, t0
    add     t3, t3, t1
    add     t3, t3, t5

.Lq_next:
    srli    t5, t0, 31
    slli    t0, t0, 1
    slli    t1, t1, 1
    or      t1, t1, t5
    srli    t4, t4, 1
    bne     t4, zero, .Lq_loop

.Lq_product_done:
# Convert the unsigned product to the signed product modulo 2^64.
    bge     a0, zero, .Lq_a_nonnegative
    sub     t3, t3, a1
.Lq_a_nonnegative:
    bge     a1, zero, .Lq_round
    sub     t3, t3, a0

.Lq_round:
# Add 2^19 with carry, then keep product bits 20 through 51.
    lui     t0, 0x80
    add     t2, t2, t0
    sltu    t0, t2, t0
    add     t3, t3, t0
    srli    a0, t2, 20
    slli    t3, t3, 12
    or      a0, a0, t3
    ret
    .size   q_mul_asm, .-q_mul_asm
