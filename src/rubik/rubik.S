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
    sw   a1, 8(sp)              # out
    sw   a2, 4(sp)              # cap
    mv   s0, a0                 # state pointer (s0 becomes the bound later)


# ---------------------------------------------------------------------------
#   Parse and validate the state; any error jumps to invalid.
#   t0 = pointer into the state string, t1 = character, t2 = bit mask of cubies seen,
#   t3 = orientation sum, t4 = loop counter
# ---------------------------------------------------------------------------
    mv   t0, s0
    li   t2, 0
    li   t4, 7
check_p:                        # characters 0..6 must be '1'..'7', all different
    lbu  t1, 0(t0)
    addi t1, t1, -49            # '1' -> 0
    li   t5, 7
    bgeu t1, t5, invalid        # unsigned compare also rejects chars < '1'
    li   t5, 1
    sll  t5, t5, t1
    and  t6, t2, t5
    bnez t6, invalid            # repeated cubie
    or   t2, t2, t5
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, check_p

    li   t3, 0
    li   t4, 7
check_o:                        # characters 7..13 must be '1'..'3'
    lbu  t1, 0(t0)
    addi t1, t1, -49
    li   t5, 3
    bgeu t1, t5, invalid
    add  t3, t3, t1
    addi t0, t0, 1
    addi t4, t4, -1
    bnez t4, check_o
    lbu  t1, 0(t0)
    bnez t1, invalid            # exactly 14 characters
    li   t5, 0x1249             # bits 0, 3, 6, 9, 12: multiples of 3
    srl  t5, t5, t3
    andi t5, t5, 1
    beqz t5, invalid

# Permutation rank (Lehmer code, Horner form): a0 = a0 * (7 - i) + smaller_i.
# Multiplying by k is k repeated additions; this runs once per input.
    mv   t0, s0
    li   a0, 0
    li   t4, 7                  # t4 = 7 - i = number of characters from i on
rank_p_loop:
    mv   t5, a0                 # a0 = a0 * t4
    li   a0, 0
    mv   t6, t4
mul_loop:
    add  a0, a0, t5
    addi t6, t6, -1
    bnez t6, mul_loop
    lbu  t1, 0(t0)              # value at position i
    li   t3, 0                  # smaller
    addi a2, t0, 1
    add  a3, t0, t4             # one past position 6
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
    add  a1, a1, t5             # a1 * 3
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
    la   s1, frames             # keep the root ranks in frames[0]; every bound restarts from them
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
    li   s2, 0                  # s2 = solution length
    beqz t0, .Lwrite            # h = 0: already solved
    mv   s0, t0                 # s0 = bound

# ---------------------------------------------------------------------------
# Iterative deepening. s0 = bound, s1 = current frame, s2 = g.
# ---------------------------------------------------------------------------
bound_loop:
    la   s1, frames
    li   s2, 0
    lhu  t0, 0(s1)              # t0 = sp, t1 = so: root ranks
    lhu  t1, 2(s1)
    li   t6, 255                # t6 = last face: none at the root
    li   a4, 3                  # a4 = 3 for the whole search (loop limits)
node_enter:                     # a node: t0/t1 = its p/o ranks, s2 = g
    sub  a5, s0, s2
    addi a5, a5, -1             # a5 = bound - (g + 1): the largest h a child may have
    li   t4, 0                  # t4 = face
face_loop:
    beq  t4, t6, next_face      # never turn the same face twice
    jal  ra, sel_tables         # a6 = tp[face], a7 = to[face]
    mv   t2, t0                 # t2 = cp, t3 = co: start from the node's own state
    mv   t3, t1
turn0:                          # turn 1 of this face (unrolled)
    slli a0, t2, 1              # cp = tp[face][cp]
    add  a0, a0, a6
    lhu  t2, 0(a0)
    slli a1, t3, 1              # co = to[face][co]
    add  a1, a1, a7
    lhu  t3, 0(a1)
    add  a2, s9, t2             # h_p = pdb_p[cp]
    lbu  a2, 0(a2)
    bltu a5, a2, turn1
    add  a3, s10, t3            # h = max(h_p, pdb_o[co])
    lbu  a3, 0(a3)
    bgeu a2, a3, 10f
    mv   a2, a3
10:
    bltu a5, a2, turn1          # h > bound - (g + 1): pruned
    li   t5, 0
    j    survive
turn1:                          # turn 2 of this face (unrolled)
    slli a0, t2, 1              # cp = tp[face][cp]
    add  a0, a0, a6
    lhu  t2, 0(a0)
    slli a1, t3, 1              # co = to[face][co]
    add  a1, a1, a7
    lhu  t3, 0(a1)
    add  a2, s9, t2             # h_p = pdb_p[cp]
    lbu  a2, 0(a2)
    bltu a5, a2, turn2
    add  a3, s10, t3            # h = max(h_p, pdb_o[co])
    lbu  a3, 0(a3)
    bgeu a2, a3, 11f
    mv   a2, a3
11:
    bltu a5, a2, turn2          # h > bound - (g + 1): pruned
    li   t5, 1
    j    survive
turn2:                          # turn 3 of this face (unrolled)
    slli a0, t2, 1              # cp = tp[face][cp]
    add  a0, a0, a6
    lhu  t2, 0(a0)
    slli a1, t3, 1              # co = to[face][co]
    add  a1, a1, a7
    lhu  t3, 0(a1)
    add  a2, s9, t2             # h_p = pdb_p[cp]
    lbu  a2, 0(a2)
    bltu a5, a2, next_face
    add  a3, s10, t3            # h = max(h_p, pdb_o[co])
    lbu  a3, 0(a3)
    bgeu a2, a3, 12f
    mv   a2, a3
12:
    bltu a5, a2, next_face      # h > bound - (g + 1): pruned
    li   t5, 2
survive:                        # the child passed the bound; t5 = its turn
    slli a0, t4, 2              # path[g] = (face << 2) | turn
    or   a0, a0, t5
    add  a1, s11, s2
    sb   a0, 0(a1)
    beqz a2, found
    sh   t0, 0(s1)              # push: save this node's registers, descend
    sh   t1, 2(s1)
    sh   t2, 4(s1)
    sh   t3, 6(s1)
    sb   t4, 8(s1)
    sb   t5, 9(s1)
    sb   t6, 10(s1)
    mv   t0, t2                 # the child's p/o are cp/co
    mv   t1, t3
    mv   t6, t4                 # the child's last face is this face
    addi s1, s1, 16
    addi s2, s2, 1
    j    node_enter
next_face:
    addi t4, t4, 1
    blt  t4, a4, face_loop
    beqz s2, next_bound         # backtrack from the root: this bound failed
    addi s2, s2, -1             # pop: restore the parent's registers
    addi s1, s1, -16
    lhu  t0, 0(s1)
    lhu  t1, 2(s1)
    lhu  t2, 4(s1)
    lhu  t3, 6(s1)
    lbu  t4, 8(s1)
    lbu  t5, 9(s1)
    lbu  t6, 10(s1)
    sub  a5, s0, s2
    addi a5, a5, -1
    jal  ra, sel_tables
    beqz t5, turn1              # carry on with the parent's next turn
    li   a0, 1
    beq  t5, a0, turn2
    j    next_face

sel_tables:                     # a6/a7 = the transition tables of face t4
    mv   a6, s3
    mv   a7, s6
    beqz t4, 2f
    mv   a6, s4
    mv   a7, s7
    li   a0, 1
    beq  t4, a0, 2f
    mv   a6, s5
    mv   a7, s8
2:
    ret

next_bound:
    addi s0, s0, 1
    li   t0, 11
    bgeu t0, s0, bound_loop
    li   a0, -1                 # no solution within 11: should not happen
    j    .Lreturn

found:
    addi s2, s2, 1              # solution length = g + 1

# ---- output: write the moves into out; -2 if they do not fit ----
# s2 = len, s11 = path; t0 = cap, t1 = out, t2 = bytes needed, t3 = i
.Lwrite:
    lw   t0, 4(sp)              # cap
    lw   t1, 8(sp)              # out
# need = 2 * len + (moves with a suffix): len letters, the suffixes,
# len - 1 spaces and the NUL. The empty answer needs 1 byte.
    slli t2, s2, 1              # need = 2 * len
    li   t3, 0
.Lcount:
    bgeu t3, s2, .Lcounted
    add  t4, s11, t3
    lbu  t4, 0(t4)
    andi t4, t4, 3              # turn
    snez t4, t4                 # 1 if this move has a suffix
    add  t2, t2, t4
    addi t3, t3, 1
    j    .Lcount
.Lcounted:
    bnez t2, .Lsized
    li   t2, 1                  # len = 0: only the NUL
.Lsized:
    bltu t0, t2, .Lshort        # cap < need, unsigned
    la   a1, face_char
    la   a2, suffix_char
    li   t3, 0
.Lemit:
    bgeu t3, s2, .Lend
    beqz t3, .Lletter           # no space before the first move
    li   t4, 32                 # ' '
    sb   t4, 0(t1)
    addi t1, t1, 1
.Lletter:
    add  t4, s11, t3
    lbu  t4, 0(t4)              # m = (face << 2) | turn
    srli t5, t4, 2              # face
    add  t5, a1, t5
    lbu  t5, 0(t5)
    sb   t5, 0(t1)
    addi t1, t1, 1
    andi t4, t4, 3              # turn
    add  t4, a2, t4
    lbu  t4, 0(t4)
    beqz t4, .Lnext             # a quarter turn has no suffix
    sb   t4, 0(t1)
    addi t1, t1, 1
.Lnext:
    addi t3, t3, 1
    j    .Lemit
.Lend:
    sb   zero, 0(t1)
    mv   a0, s2                 # the number of moves
    j    .Lreturn
.Lshort:
    beqz t0, .Lshort_ret        # cap = 0: write nothing
    sb   zero, 0(t1)            # t1 is still out here
.Lshort_ret:
    li   a0, -2
    j    .Lreturn

invalid:
    li   a0, -1                 # out is never touched on this path
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

    .section .rodata
face_char:   .byte 82, 66, 68   # 'R', 'B', 'D'
suffix_char: .byte 0, 50, 39    # none, '2', '\''
# ---- search state (Assignment 1 lines 10-19, without the input string) ----
    .bss
    .balign 4
frames: .zero 192               # 12 frames x 16 bytes, see the layout in Assignment 1
path:   .zero 16                # path[g] = (face << 2) | turn
