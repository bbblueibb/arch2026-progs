# RV32I optimal cube solver. Move order: R R2 R' B B2 B' D D2 D'.
# The target uses a five-move suffix table and a distance-eleven table.
# Tables are private to this implementation; no calls into the C solver.
#
# a0 = state, a1 = out, a2 = cap; a0 = length or error.
# s0 = out, s1 = cap, s2/s3 = permutation/orientation ranks,
# s4 = path length, s5/s6 = quarter-turn table bases, s7 = near table,
# s8 = current search frame, s9 = path, s10 = bound, s11 = depth.
#
# 240-byte frame: path at 0, permutation scratch at 16,
# root ranks at 40/44, previous face at 48, six 16-byte frames at 64,
# saved ra and s0..s11 at 188..236. Internal helpers are leaf routines.

    .option push
    .option norvc
    .option norelax
    .text
    .balign 4
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
rubik_solve_asm:
    addi sp, sp, -240
    sw ra, 188(sp)
    sw s0, 192(sp)
    sw s1, 196(sp)
    sw s2, 200(sp)
    sw s3, 204(sp)
    sw s4, 208(sp)
    sw s5, 212(sp)
    sw s6, 216(sp)
    sw s7, 220(sp)
    sw s8, 224(sp)
    sw s9, 228(sp)
    sw s10, 232(sp)
    sw s11, 236(sp)
    mv s0, a1
    mv s1, a2
    mv s9, sp

# Reject invalid characters immediately, including an early NUL.
    li t0, 0
    li t1, 0
    li a3, 7
.Lrb_parse_perm:
    lbu t2, 0(a0)
    addi t2, t2, -49
    bgeu t2, a3, .Lrb_invalid
    li t3, 1
    sll t3, t3, t2
    and t4, t1, t3
    bnez t4, .Lrb_invalid
    or t1, t1, t3
    addi t5, sp, 16
    add t5, t5, t0
    sb t2, 0(t5)
    addi a0, a0, 1
    addi t0, t0, 1
    bltu t0, a3, .Lrb_parse_perm

    li t0, 0
    li t1, 0
    li s3, 0
    li a3, 3
    li a4, 6
    li a5, 7
.Lrb_parse_ori:
    lbu t2, 0(a0)
    addi t2, t2, -49
    bgeu t2, a3, .Lrb_invalid
    add t1, t1, t2
    bgeu t0, a4, .Lrb_ori_last
    slli t3, s3, 1
    add s3, s3, t3
    add s3, s3, t2
.Lrb_ori_last:
    addi a0, a0, 1
    addi t0, t0, 1
    bltu t0, a5, .Lrb_parse_ori
    lbu t2, 0(a0)
    bnez t2, .Lrb_invalid
.Lrb_ori_sum:
    bltu t1, a3, .Lrb_ori_checked
    addi t1, t1, -3
    j .Lrb_ori_sum
.Lrb_ori_checked:
    bnez t1, .Lrb_invalid

# Lehmer rank. The small variable factor is multiplied with shifts/adds.
    li s2, 0
    li t0, 0
.Lrb_rank_digit:
    addi t3, sp, 16
    add t3, t3, t0
    lbu t4, 0(t3)
    addi t2, t0, 1
    li t1, 0
    li a3, 7
.Lrb_rank_smaller:
    addi t3, sp, 16
    add t3, t3, t2
    lbu t5, 0(t3)
    sltu t6, t5, t4
    add t1, t1, t6
    addi t2, t2, 1
    bltu t2, a3, .Lrb_rank_smaller
    sub a4, a3, t0
    mv a5, s2
    li s2, 0
.Lrb_rank_multiply:
    andi a6, a4, 1
    beqz a6, .Lrb_rank_skip_add
    add s2, s2, a5
.Lrb_rank_skip_add:
    slli a5, a5, 1
    srli a4, a4, 1
    bnez a4, .Lrb_rank_multiply
    add s2, s2, t1
    addi t0, t0, 1
    li t2, 6
    bltu t0, t2, .Lrb_rank_digit

    beqz s1, .Lrb_no_capacity
    or t0, s2, s3
    beqz t0, .Lrb_solved
    li t0, 1
    beq s1, t0, .Lrb_small
    la s5, .Lrb_perm_next
    la s6, .Lrb_ori_next
    la s7, .Lrb_near_table
    li s4, 0
    call .Lrb_near_lookup
    bgez a0, .Lrb_suffix
    la a1, .Lrb_far_table
    li a2, 2644
    call .Lrb_lookup_key
    li t0, 3
    sw t0, 48(sp)
    bltz a0, .Lrb_search_start
    li t0, 9
    bgeu a0, t0, .Lrb_invalid
    sb a0, 0(s9)
    li s4, 1
    la t0, .Lrb_faces
    add t0, t0, a0
    lbu t0, 0(t0)
    sw t0, 48(sp)
    call .Lrb_apply

.Lrb_search_start:
    sw s2, 40(sp)
    sw s3, 44(sp)
    li s10, 1
.Lrb_search_bound:
    addi s8, sp, 64
    li s11, 0
    lw t0, 40(sp)
    lw t1, 44(sp)
    sh t0, 0(s8)
    sh t1, 2(s8)
    sw zero, 8(s8)
    lw t0, 48(sp)
    sw t0, 12(s8)
.Lrb_search_node:
    lw t0, 8(s8)
    li t1, 9
    bgeu t0, t1, .Lrb_search_pop
    addi t1, t0, 1
    sw t1, 8(s8)
    la t1, .Lrb_faces
    add t1, t1, t0
    lbu t2, 0(t1)
    lw t1, 12(s8)
    beq t2, t1, .Lrb_search_skip_face
    slli t3, t2, 1
    add t3, t3, t2
    bne t0, t3, .Lrb_search_continue_turn
    lhu t3, 0(s8)
    lhu t4, 2(s8)
    sh t3, 4(s8)
    sh t4, 6(s8)
.Lrb_search_continue_turn:
    la t3, .Lrb_face_bases
    slli t4, t2, 3
    add t3, t3, t4
    lw t4, 0(t3)
    lw t5, 4(t3)
    lhu s2, 4(s8)
    lhu s3, 6(s8)
    slli t3, s2, 1
    add t4, t4, t3
    lhu s2, 0(t4)
    slli t3, s3, 1
    add t5, t5, t3
    lhu s3, 0(t5)
    sh s2, 4(s8)
    sh s3, 6(s8)
    add t3, s4, s11
    add t3, s9, t3
    sb t0, 0(t3)
    addi t3, s11, 1
    beq t3, s10, .Lrb_search_leaf
    addi s8, s8, 16
    sh s2, 0(s8)
    sh s3, 2(s8)
    sw zero, 8(s8)
    sw t2, 12(s8)
    addi s11, s11, 1
    j .Lrb_search_node
.Lrb_search_leaf:
    call .Lrb_near_lookup
    bltz a0, .Lrb_search_node
    add s4, s4, s10
    j .Lrb_suffix
.Lrb_search_skip_face:
    addi t0, t0, 3
    sw t0, 8(s8)
    j .Lrb_search_node
.Lrb_search_pop:
    beqz s11, .Lrb_search_next_bound
    addi s8, s8, -16
    addi s11, s11, -1
    j .Lrb_search_node
.Lrb_search_next_bound:
    addi s10, s10, 1
    li t0, 5
    bgeu t0, s10, .Lrb_search_bound
    j .Lrb_invalid

# The near table supplies a move that lowers the remaining distance.
.Lrb_suffix:
    li t0, 9
    bgeu a0, t0, .Lrb_invalid
    li t0, 11
    bgeu s4, t0, .Lrb_invalid
    add t0, s9, s4
    sb a0, 0(t0)
    addi s4, s4, 1
    call .Lrb_apply
    or t0, s2, s3
    beqz t0, .Lrb_text_size
    call .Lrb_near_lookup
    j .Lrb_suffix

# n letters + n-1 spaces + NUL = 2*n, plus optional suffix characters.
.Lrb_text_size:
    slli t0, s4, 1
    li t1, 0
    la t2, .Lrb_suffix_chars
.Lrb_size_loop:
    add t3, s9, t1
    lbu t3, 0(t3)
    add t3, t2, t3
    lbu t3, 0(t3)
    snez t3, t3
    add t0, t0, t3
    addi t1, t1, 1
    bltu t1, s4, .Lrb_size_loop
    bltu s1, t0, .Lrb_small
    mv t0, s0
    li t1, 0
    la t2, .Lrb_face_chars
    la t3, .Lrb_suffix_chars
.Lrb_write_loop:
    beqz t1, .Lrb_write_move
    li t4, 32
    sb t4, 0(t0)
    addi t0, t0, 1
.Lrb_write_move:
    add t4, s9, t1
    lbu t4, 0(t4)
    add t5, t2, t4
    lbu t5, 0(t5)
    sb t5, 0(t0)
    addi t0, t0, 1
    add t4, t3, t4
    lbu t4, 0(t4)
    beqz t4, .Lrb_write_next
    sb t4, 0(t0)
    addi t0, t0, 1
.Lrb_write_next:
    addi t1, t1, 1
    bltu t1, s4, .Lrb_write_loop
    sb zero, 0(t0)
    mv a0, s4
    j .Lrb_return
.Lrb_solved:
    sb zero, 0(s0)
    li a0, 0
    j .Lrb_return
.Lrb_small:
    sb zero, 0(s0)
.Lrb_no_capacity:
    li a0, -2
    j .Lrb_return
.Lrb_invalid:
    li a0, -1
.Lrb_return:
    lw ra, 188(sp)
    lw s0, 192(sp)
    lw s1, 196(sp)
    lw s2, 200(sp)
    lw s3, 204(sp)
    lw s4, 208(sp)
    lw s5, 212(sp)
    lw s6, 216(sp)
    lw s7, 220(sp)
    lw s8, 224(sp)
    lw s9, 228(sp)
    lw s10, 232(sp)
    lw s11, 236(sp)
    addi sp, sp, 240
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

# Internal leaf lookup: s2/s3 are ranks; a1/a2 are base/count.
# Clobbers a0,a3..a6,t0,t1. All s registers are unchanged.
.Lrb_near_lookup:
    mv a1, s7
    li a2, 12224
.Lrb_lookup_key:
    slli t0, s2, 3
    add t0, t0, s2
    slli t1, t0, 3
    add t0, t0, t1
    slli t1, t0, 3
    add t0, t0, t1
    add a0, t0, s3
    slli a0, a0, 4
    li a3, 0
    mv a4, a2
.Lrb_lookup_loop:
    add a5, a3, a4
    srli a5, a5, 1
    slli a6, a5, 2
    add a6, a1, a6
    lw a6, 0(a6)
    bltu a6, a0, .Lrb_lookup_right
    mv a4, a5
    bltu a3, a4, .Lrb_lookup_loop
    j .Lrb_lookup_check
.Lrb_lookup_right:
    addi a3, a5, 1
    bltu a3, a4, .Lrb_lookup_loop
.Lrb_lookup_check:
    bgeu a3, a2, .Lrb_lookup_miss
    slli a5, a3, 2
    add a5, a1, a5
    lw a6, 0(a5)
    srli a5, a6, 4
    slli a5, a5, 4
    bne a5, a0, .Lrb_lookup_miss
    andi a0, a6, 15
    ret
.Lrb_lookup_miss:
    li a0, -1
    ret

# Internal leaf apply: a0 is a valid move, updates s2/s3 deliberately.
# Clobbers t0..t4. It does not allocate another stack frame.
.Lrb_apply:
    mv t0, a0
    mv t1, s5
    mv t2, s6
    li t3, 3
    bltu t0, t3, .Lrb_apply_ready
    addi t0, t0, -3
    li t4, 10080
    add t1, t1, t4
    addi t2, t2, 1458
    bltu t0, t3, .Lrb_apply_ready
    addi t0, t0, -3
    add t1, t1, t4
    addi t2, t2, 1458
.Lrb_apply_ready:
    addi t0, t0, 1
.Lrb_apply_turn:
    slli t3, s2, 1
    add t3, t1, t3
    lhu s2, 0(t3)
    slli t3, s3, 1
    add t3, t2, t3
    lhu s3, 0(t3)
    addi t0, t0, -1
    bnez t0, .Lrb_apply_turn
    ret

    .section .rodata
    .balign 4
.Lrb_face_bases:
    .4byte .Lrb_perm_next, .Lrb_ori_next
    .4byte .Lrb_perm_next + 10080, .Lrb_ori_next + 1458
    .4byte .Lrb_perm_next + 20160, .Lrb_ori_next + 2916
.Lrb_faces:
    .byte 0,0,0,1,1,1,2,2,2
.Lrb_face_chars:
    .ascii "RRRBBBDDD"
.Lrb_suffix_chars:
    .byte 0,50,39,0,50,39,0,50,39

    .include "src/rubik/rubik_search_tables.inc"
    .section .note.GNU-stack,"",@progbits
    .option pop
