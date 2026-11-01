# BF16 arithmetic using RV32I integer instructions only.
# Arguments and return values use a0 (and a1 for multiplication).
# These leaf functions use only caller-saved registers.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t0, 0x7f800
    and     t1, a0, t0
    slli    t2, a0, 16
    srli    a0, a0, 16
    beq     t1, t0, .Lf32_done
    bge     t2, zero, .Lf32_done
    slli    t2, t2, 1
    bne     t2, zero, .Lf32_increment
    andi    t2, a0, 1
    beq     t2, zero, .Lf32_done
.Lf32_increment:
    addi    a0, a0, 1
.Lf32_done:
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t0, a0, a1
    lui     t6, 0x8
    and     t0, t0, t6
    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t3, a0, 127
    andi    t4, a1, 127
    li      a2, 255
    beq     t1, a2, .Lmul_special_a
    beq     t2, a2, .Lmul_special_b

    or      t5, t1, t3
    beq     t5, zero, .Lmul_zero
    or      t5, t2, t4
    beq     t5, zero, .Lmul_zero

    li      a2, 128
    bne     t1, zero, .Lmul_normal_a
    li      t1, 1
.Lmul_shift_a:
    slli    t3, t3, 1
    addi    t1, t1, -1
    bltu    t3, a2, .Lmul_shift_a
    j       .Lmul_a_ready
.Lmul_normal_a:
    ori     t3, t3, 128
.Lmul_a_ready:
    bne     t2, zero, .Lmul_normal_b
    li      t2, 1
.Lmul_shift_b:
    slli    t4, t4, 1
    addi    t2, t2, -1
    bltu    t4, a2, .Lmul_shift_b
    j       .Lmul_b_ready
.Lmul_normal_b:
    ori     t4, t4, 128
.Lmul_b_ready:
    add     t1, t1, t2
    addi    t1, t1, -127

# Both normalized significands have bit 7 set.
# Account for that bit once, then process the lower seven multiplier bits.
    slli    t5, t3, 7
    .rept   7
    andi    t6, t4, 1
    beq     t6, zero, 1f
    add     t5, t5, t3
1:
    slli    t3, t3, 1
    srli    t4, t4, 1
    .endr

    srli    t2, t5, 15
    beq     t2, zero, .Lmul_scaled
    srli    t5, t5, 1
    addi    t1, t1, 1
.Lmul_scaled:
    srli    t5, t5, 7
    andi    t5, t5, 127
    li      t2, 255
    bge     t1, t2, .Lmul_infinity
    bge     zero, t1, .Lmul_underflow
    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, t5
    ret

.Lmul_underflow:
    li      t2, -6
    blt     t1, t2, .Lmul_zero
    li      t2, 1
    sub     t2, t2, t1
    srl     t5, t5, t2
    or      a0, t0, t5
    ret

.Lmul_special_a:
    bne     t3, zero, .Lmul_return_a
    slli    t6, a1, 17
    beq     t6, zero, .Lmul_nan
    j       .Lmul_infinity
.Lmul_special_b:
    bne     t4, zero, .Lmul_return_b
    slli    t6, a0, 17
    beq     t6, zero, .Lmul_nan
    j       .Lmul_infinity

.Lmul_return_b:
    mv      a0, a1
.Lmul_return_a:
    ret
.Lmul_zero:
    mv      a0, t0
    ret
.Lmul_infinity:
    li      a0, 0x7f80
    or      a0, a0, t0
    ret
.Lmul_nan:
    li      a0, 0x7fc0
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127
    li      t2, 255
    beq     t0, t2, .Lsqrt_special
    slli    t2, a0, 17
    beq     t2, zero, .Lsqrt_zero
    srli    t2, a0, 15
    bne     t2, zero, .Lsqrt_nan
    beq     t0, zero, .Lsqrt_zero

    addi    t0, t0, -127
    ori     t1, t1, 128
    andi    t2, t0, 1
    beq     t2, zero, .Lsqrt_even
    slli    t1, t1, 1
    addi    t0, t0, -1
.Lsqrt_even:
    srai    t0, t0, 1
    addi    t0, t0, 127

# The contract requires floor(sqrt(128 * (m + 1) - 1)).
    addi    t2, t1, 1
    slli    t2, t2, 7
    addi    t2, t2, -1
    li      t3, 0
    li      t4, 0x4000

# Restoring integer square root: one base-four digit per iteration.
.Lsqrt_loop:
    add     t5, t3, t4
    srli    t3, t3, 1
    bltu    t2, t5, .Lsqrt_skip
    sub     t2, t2, t5
    add     t3, t3, t4
.Lsqrt_skip:
    srli    t4, t4, 2
    bne     t4, zero, .Lsqrt_loop

    andi    t3, t3, 127
    slli    t0, t0, 7
    or      a0, t0, t3
    ret

.Lsqrt_special:
    bne     t1, zero, .Lsqrt_return
    srli    t2, a0, 15
    bne     t2, zero, .Lsqrt_nan
.Lsqrt_return:
    ret
.Lsqrt_zero:
    li      a0, 0
    ret
.Lsqrt_nan:
    li      a0, 0x7fc0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
