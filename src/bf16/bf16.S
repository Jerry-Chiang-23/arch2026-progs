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
    lui     t0, 0x7F800         # ( f32bits & 0x7F800000) == or != 0x7F800000
    and     t1, a0, t0
    bne     t0, t1, .Lnot_inf_nan
    srli    a0, a0, 16          # return (f32bits >> 16)
    ret
.Lnot_inf_nan:
    srli    t0, a0, 16          # f32bits >> 16
    andi    t0, t0, 1           # (f32bits >> 16) & 1
    add     a0, a0, t0          # f32bits += ((f32bits >> 16) & 1)
    lui     t0, 0x7FFF          # f32bits += ((f32bits >> 16) & 1) + 0x7FFF
    srli    t0, t0, 12
    add     a0, a0, t0
    srli    a0, a0, 16          # return f32bits >> 16
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
bf16_sqrt_asm:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
