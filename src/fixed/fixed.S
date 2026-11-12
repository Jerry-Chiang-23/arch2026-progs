# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2

op1_asm:
    li      t0, 0               # The value of *n
    beq     a1, x0, .Lop1_ret
.Lop1_loop:
    and     t1, a0, a1          # a & b
    xor     a0, a0, a1          # a = a ^ b
    slli    a1, t1, 1           # (a&b) << 1
    addi    t0, t0, 1
    bnez    a1, .Lop1_loop
.Lop1_ret:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2

op2_asm:
    sub     a0, a0, a1          # a-b
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2

# (a+b)/2|floor = (a&b) + ((a^b)>>1)
op3_asm:
    and     t0, a0, a1
    xor     t1, a0, a1
    srli    t1, t1, 1
    add     a0, t0, t1
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2

q_mul_asm:
    srli    t0, a0, 16              # ah
    slli    t1, a0, 16              # al
    srli    t1, t1, 16
    srli    t2, a1, 16              # bh
    slli    t3, a1, 16              # bl
    srli    t3, t3, 16

# a4: multiplicand; a5: multiplier
# a6: The answer of each round
# a2: Low 32 bits of the unsigned answer
# a3: High 32 bits of the unsigned answer
# a7: carry
# [a3 (32 bits) : a2 (32 bits)] was the unsigned product
# sign fix below makes it signed
.Lal_bl:
    mv      a4, t1
    mv      a5, t3
    jal     t6, .Lmul16
    mv      a2, a6
    li      a3, 0
.Lah_bl:
    mv      a4, t0
    mv      a5, t3
    jal     t6, .Lmul16
    slli    t5, a6, 16
    add     a2, a2, t5
    sltu    a7, a2, t5
    srli    t5, a6, 16
    add     a3, a3, t5
    add     a3, a3, a7
.Lal_bh:
    mv      a4, t1
    mv      a5, t2
    jal     t6, .Lmul16
    slli    t5, a6, 16
    add     a2, a2, t5
    sltu    a7, a2, t5
    srli    t5, a6, 16
    add     a3, a3, t5
    add     a3, a3, a7
.Lah_bh:
    mv      a4, t0
    mv      a5, t2
    jal     t6, .Lmul16
    add     a3, a3, a6

# final count
    bgez    a0, .Lneglect_b
    sub     a3, a3, a1
.Lneglect_b:
    bgez    a1, .Lneglect_a
    sub     a3, a3, a0
.Lneglect_a:
    lui     t5, 0x80            # 0x80000
    add     a2, a2, t5
    sltu    t2, a2, t5
    add     a3, a3, t2
# final answer
    slli    a3, a3, 12
    srli    a2, a2, 20
    or      a0, a3, a2
    ret

.Lmul16:
    li      a6, 0
    beqz    a5, .Lmul16_ret
.Lmul_loop:
    andi    t4, a5, 1               # b & 1
    beqz    t4, .Lab_shift
    add     a6, a6, a4              # r+=a
.Lab_shift:
    slli    a4, a4, 1
    srli    a5, a5, 1
    bnez    a5, .Lmul_loop
.Lmul16_ret:
    jr      t6
    .size   q_mul_asm, .-q_mul_asm
