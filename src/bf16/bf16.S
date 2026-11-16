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

bf16_mul_asm:
    li      a0, 0
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
