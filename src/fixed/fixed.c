#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int nn = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++nn;
    }
    *n = nn;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

// (a+B)/2|floor = (a&b) + ((a^b)>>1)
uint32_t op3(uint32_t a, uint32_t b)
{
    uint32_t bit_0 = ((a & 1) & (b & 1));  // ((a&1) + (b&1)) >> 1
    return (a >> 1) + (b >> 1) + bit_0;
}

int32_t q_mul(int32_t a, int32_t b)
{
    (void) a;
    (void) b;
    return 0;
}
