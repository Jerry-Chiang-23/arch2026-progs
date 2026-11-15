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

# Permutation rank (Lehmer code, Horner form): a0 = a0 * (7 - i) + smaller_i.
# Multiplying by k is k repeated additions; this runs once per input.
    mv   t0, s0
    li   a0, 0
    li   t4, 7                   # t4 = 7 - i = number of characters from i on
rank_p_loop:
    mv   t5, a0                  # a0 = a0 * t4
    li   a0, 0
    mv   t6, t4
mul_loop:
    add  a0, a0, t5
    addi t6, t6, -1
    bnez t6, mul_loop
    lbu  t1, 0(t0)               # value at position i
    li   t3, 0                   # smaller
    addi a2, t0, 1
    add  a3, t0, t4              # one past position 6
count_loop:
    bgeu a2, a3, count_done
    lbu  a4, 0(a2)
    sltu a5, a4, t1
    add  t3, t3, a5
    addi a2, a2, 1
    j    count_loop
count_done:
    add  a0, a0, t3
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, rank_p_loop

# Orientation rank: base 3 over the first six orientation digits.
    mv   t0, s0
    addi t0, t0, 7
    li   a1, 0
    li   t4, 6
rank_o_loop:
    lbu  t1, 0(t0)
    addi t1, t1, -49
    slli t5, a1, 1
    add  a1, a1, t5              # a1 * 3
    add  a1, a1, t1
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, rank_o_loop

# ---------------------------------------------------------------------------
# Table bases, kept in saved registers for the whole search.
# ---------------------------------------------------------------------------
    la   s3, tp0
    la   s4, tp1
    la   s5, tp2
    la   s6, to0
    la   s7, to1
    la   s8, to2
    la   s9, pdb_p
    la   s10, pdb_o
    la   s11, path
    la   s1, frames              # keep the root ranks in frames[0]; every bound restarts from them
    sh   a0, 0(s1)
    sh   a1, 2(s1)

# h(root) = max(pdb_p[p], pdb_o[o])
    add  t0, s9, a0
    lbu  t0, 0(t0)
    add  t1, s10, a1
    lbu  t1, 0(t1)
    bgeu t0, t1, 1f
    mv   t0, t1
1:
    li   s2, 0                   # s2 = solution length
    beqz t0, .Lwrite             # h = 0: already solved
    li   a0, -1                  # the search is not in place: report other states as errors
    j    .Lreturn

# ---- output: the empty answer of the solved cube; -2 if cap is 0 ----
.Lwrite:
    lw   t0, 4(sp)               # cap
    beqz t0, .Lshort             # no room even for the NUL
    lw   t1, 8(sp)               # out
    sb   zero, 0(t1)
    li   a0, 0
    j    .Lreturn
.Lshort:
    li   a0, -2
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

# ---- search state (Assignment 1 lines 10-19, without the input string) ----
    .bss
    .balign 4
frames: .zero 192                # 12 frames x 16 bytes, see the layout in Assignment 1
path:   .zero 16                 # path[g] = (face << 2) | turn
