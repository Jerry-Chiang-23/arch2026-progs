# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, x0, .Lpa_alt        # a0 is zero: the answer is in a1
    beq     a1, x0, .Lpa_end        # a1 is zero: a0 already holds it
    addi    t0, x0, 0               # count of shared twos, starting here

# if (a%2)==0 && (b%2)==0
.Lboth:
    or      t1, a0, a1              # combine a and b
    andi    t1, t1, 1               # keep the parity bit
    bne     t1, x0, .La

# if ((a/2)%2)==0 && ((b/2)%2)==0
.Lboth_loop:
    srli    a0, a0, 1               # a /= 2, with no sign to preserve
    srli    a1, a1, 1               # b /= 2
    addi    t0, t0, 1               # one more shared two
    or      t1, a0, a1              # combine a and b
    andi    t1, t1, 1               # keep the parity bit
    beq     t1, x0, .Lboth_loop  # back to the head of this loop

# if (a%2)==0
.La:
    andi t1, a0, 1
    bne t1, x0, .Lb

# if ((a/2)%2)==0
.La_loop:       
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, .La_loop   # a is even now, go work on a again

# if (b%2)==0
.Lb:
    andi    t1, a1, 1
    bne     t1, x0, .Lpa_order      # if (b&1)!=0 (b is odd)
    srli    a1, a1, 1
    jal     x0, .Lb

.Lpa_order:
    bgeu    a1, a0, .Lpa_step       # skip the swap while b >= a holds
    addi    t2, a0, 0               # swap a and b
    addi    a0, a1, 0
    addi    a1, t2, 0

.Lpa_step:
    sub     a1, a1, a0              # b -= a, and b stays even
    bne     a1, x0, .Lb        # b is not zero yet
    sll     a0, a0, t0              # put the shared twos back
    jalr    x0, ra, 0

.Lpa_alt:
    addi    a0, a1, 0

.Lpa_end:
    jalr    x0, ra, 0
    .size   gcd_u32_asm, .-gcd_u32_asm
