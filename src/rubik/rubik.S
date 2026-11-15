# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
# Ported from the Assignment 1 solver (solver_v1.s).

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
# ---- prologue: save ra and s0-s11, keep out and cap on the stack ----
    addi sp, sp, -64
    sw   ra, 60(sp)
    sw   s0, 56(sp)
    sw   s1, 52(sp)
    sw   s2, 48(sp)
    sw   s3, 44(sp)
    sw   s4, 40(sp)
    sw   s5, 36(sp)
    sw   s6, 32(sp)
    sw   s7, 28(sp)
    sw   s8, 24(sp)
    sw   s9, 20(sp)
    sw   s10, 16(sp)
    sw   s11, 12(sp)
    sw   a1, 8(sp)               # out
    sw   a2, 4(sp)               # cap
    mv   s0, a0                  # state pointer (s0 becomes the bound later)


# ---------------------------------------------------------------------------
#   Parse and validate the state; any error jumps to invalid.
#   t0 = pointer into the state string, t1 = character, t2 = bit mask of cubies seen,
#   t3 = orientation sum, t4 = loop counter
# ---------------------------------------------------------------------------
    mv   t0, s0
    li   t2, 0
    li   t4, 7
check_p:                         # characters 0..6 must be '1'..'7', all different
    lbu  t1, 0(t0)
    addi t1, t1, -49             # '1' -> 0
    li   t5, 7
    bgeu t1, t5, invalid         # unsigned compare also rejects chars < '1'
    li   t5, 1
    sll  t5, t5, t1
    and  t6, t2, t5
    bnez t6, invalid             # repeated cubie
    or   t2, t2, t5
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, check_p

    li   t3, 0
    li   t4, 7
check_o:                         # characters 7..13 must be '1'..'3'
    lbu  t1, 0(t0)
    addi t1, t1, -49
    li   t5, 3
    bgeu t1, t5, invalid
    add  t3, t3, t1
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, check_o
    lbu  t1, 0(t0)
    bnez t1, invalid             # exactly 14 characters
    li   t5, 0x1249              # bits 0, 3, 6, 9, 12: multiples of 3
    srl  t5, t5, t3
    andi t5, t5, 1
    beqz t5, invalid
    
    # STEP 1a: valid states are not handled yet
    li   a0, -1
    j    .Lreturn

invalid:
    li   a0, -1                  # out is never touched on this path
# ---- epilogue: restore ra and s0-s11 ----
.Lreturn:
    lw   ra, 60(sp)
    lw   s0, 56(sp)
    lw   s1, 52(sp)
    lw   s2, 48(sp)
    lw   s3, 44(sp)
    lw   s4, 40(sp)
    lw   s5, 36(sp)
    lw   s6, 32(sp)
    lw   s7, 28(sp)
    lw   s8, 24(sp)
    lw   s9, 20(sp)
    lw   s10, 16(sp)
    lw   s11, 12(sp)
    addi sp, sp, 64
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm
