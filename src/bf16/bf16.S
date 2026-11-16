# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t0, 0x7F800             # ( f32bits & 0x7F800000) == or != 0x7F800000
    and     t1, a0, t0
    bne     t0, t1, .Lnot_inf_nan
    srli    a0, a0, 16              # return (f32bits >> 16)
    ret
.Lnot_inf_nan:
    srli    t0, a0, 16              # f32bits >> 16
    andi    t0, t0, 1               # (f32bits >> 16) & 1
    add     a0, a0, t0              # f32bits += ((f32bits >> 16) & 1)
    lui     t0, 0x7FFF              # f32bits += ((f32bits >> 16) & 1) + 0x7FFF
    srli    t0, t0, 12
    add     a0, a0, t0
    srli    a0, a0, 16              # return f32bits >> 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

# a0 = a, a1 = b (kept until a result is chosen), t0 = sign << 15
# t1, t2 = exponent and fraction of a; t3, t4 = those of b; t5 = product
bf16_mul_asm:
    xor     t0, a0, a1
    srli    t0, t0, 15
    slli    t0, t0, 15              # sign of the result, in place
    srli    t1, a0, 7
    andi    t1, t1, 0xFF
    andi    t2, a0, 0x7F
    srli    t3, a1, 7
    andi    t3, t3, 0xFF
    andi    t4, a1, 0x7F
    li      a7, 0xFF

    bne     t1, a7, .Lmul_a_finite
    bnez    t2, .Lmul_ret_a         # a is NaN
    slli    t5, a1, 17
    beqz    t5, .Lmul_ret_nan       # Inf * 0
    j       .Lmul_ret_inf

.Lmul_a_finite:
    bne     t3, a7, .Lmul_b_finite
    bnez    t4, .Lmul_ret_b         # b is NaN
    slli    t5, a0, 17
    beqz    t5, .Lmul_ret_nan       # 0 * Inf
    j       .Lmul_ret_inf
.Lmul_b_finite:
    slli    t5, a0, 17
    beqz    t5, .Lmul_ret_zero      # a is zero
    slli    t5, a1, 17
    beqz    t5, .Lmul_ret_zero      # b is zero

    bnez    t1, .Lmul_a_normal
    li      t1, 1                   # subnormal a: exponent 1, minus one per shift
.Lmul_a_shift:
    slli    t2, t2, 1
    addi    t1, t1, -1
    andi    t5, t2, 0x80
    beqz    t5, .Lmul_a_shift
    j       .Lmul_a_done
.Lmul_a_normal:
    ori     t2, t2, 0x80
.Lmul_a_done:

    bnez    t3, .Lmul_b_normal
    li      t3, 1                   # subnormal b
.Lmul_b_shift:
    slli    t4, t4, 1
    addi    t3, t3, -1
    andi    t5, t4, 0x80
    beqz    t5, .Lmul_b_shift
    j       .Lmul_b_done
.Lmul_b_normal:
    ori     t4, t4, 0x80
.Lmul_b_done:
    slli    t5, t2, 7               # p = sig_a << 7
    andi    t4, t4, 0x7F            # multiplier = fraction of b
    beqz    t4, .Lmul_prod_done

.Lmul_loop:                         # p += sig_a * fraction of b
    andi    t6, t4, 1
    beqz    t6, .Lmul_skip
    add     t5, t5, t2
.Lmul_skip:
    slli    t2, t2, 1
    srli    t4, t4, 1
    bnez    t4, .Lmul_loop
.Lmul_prod_done:
    add     t1, t1, t3
    addi    t1, t1, -127            # remove one bias
    srli    t6, t5, 15              # 1 if the product reached 2.0
    addi    a2, t6, 7
    srl     t5, t5, a2              # shift by 7 or 8
    add     t1, t1, t6
    andi    t5, t5, 0x7F

    bge     t1, a7, .Lmul_ret_inf   # exponent >= 255
    blez    t1, .Lmul_subnormal     # exponent <= 0
    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, t5
    ret

.Lmul_subnormal:
    li      t6, -6
    blt     t1, t6, .Lmul_ret_zero  # exponent < -6
    li      t6, 1
    sub     t6, t6, t1              # shift by 1 - exponent
    srl     t5, t5, t6
    or      a0, t0, t5
    ret

.Lmul_ret_a:
    ret
.Lmul_ret_b:
    mv      a0, a1                  # return b
    ret
.Lmul_ret_nan:
    li      a0, 0x7FC0
    ret
.Lmul_ret_inf:
    li      t6, 0x7F80
    or      a0, t0, t6
    ret
.Lmul_ret_zero:
    mv      a0, t0                  # signed zero
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

# t0 = sign, t1 = exponent, t2 = fraction; a0 is kept as the input
bf16_sqrt_asm:
    srli    t0, a0, 15              # sign
    srli    t1, a0, 7
    andi    t1, t1, 0xFF            # exponent
    andi    t2, a0, 0x7F            # fraction

    li      a7, 0xFF
    bne     t1, a7, .Lsqrt_neg
    bnez    t2, .Lsqrt_ret_a        # NaN
    beqz    t0, .Lsqrt_ret_a        # +Inf
    j       .Lsqrt_ret_nan          # -Inf

.Lsqrt_neg:
    beqz    t0, .Lsqrt_zero         # positive
    slli    t4, a0, 17              # drop the sign bit
    bnez    t4, .Lsqrt_ret_nan      # negative nonzero
.Lsqrt_zero:
    beqz    t1, .Lsqrt_ret_zero     # zero or subnormal

    addi    t3, t1, -127            # e = exp - 127
    ori     t2, t2, 0x80            # m = 1.fraction
    andi    t4, t3, 1
    beqz    t4, .Lsqrt_even
    slli    t2, t2, 1               # odd e: m *= 2, e -= 1
    addi    t3, t3, -1
.Lsqrt_even:
    srai    t3, t3, 1
    addi    t3, t3, 127             # new exponent

    slli    t5, t2, 7
    addi    t5, t5, 127             # num = 128 * m + 127
    li      t6, 0                   # res
    lui     a1, 4                   # one = 1 << 14
.Lsqrt_loop:                        # bit-by-bit integer square root
    add     a2, t6, a1
    srli    t6, t6, 1
    bltu    t5, a2, .Lsqrt_next
    sub     t5, t5, a2
    add     t6, t6, a1
.Lsqrt_next:
    srli    a1, a1, 2
    bnez    a1, .Lsqrt_loop

    slli    a0, t3, 7
    andi    t6, t6, 0x7F
    or      a0, a0, t6
    ret

.Lsqrt_ret_a:                        # NaN, +Inf: return a
    ret
.Lsqrt_ret_nan:                      # return 0x7FC0
    li      a0, 0x7FC0
    ret
.Lsqrt_ret_zero:                     # return 0
    mv      a0, x0
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
