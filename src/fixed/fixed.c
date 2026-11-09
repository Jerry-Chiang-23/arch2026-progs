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

/*
au = a + 2^{32} sa,  bu = b + 2^{32} sb
au*bu = ab + 2^{32}(sa*b + sb*a) + 2^{64} sa sb
a*b = au bu - 2^{32}(sa*b + sb*a) mod{2^{64}}
*/
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ah = (a & 0xFFFF0000) >> 16;
    uint32_t al = (a & 0xFFFF);
    uint32_t bh = (b & 0xFFFF0000) >> 16;
    uint32_t bl = (b & 0xFFFF);
    uint64_t ans = ((uint64_t) (ah * bh) << 32) +
                   (((uint64_t) (ah * bl) + (uint64_t) (al * bh)) << 16) +
                   (uint64_t) (al * bl);

    ans -= ((uint64_t) ((a < 0 ? (uint32_t) (b) : 0) +
                        (b < 0 ? (uint32_t) (a) : 0))
            << 32);
    ans = ((ans + (1 << 19)) >> 20) & 0xFFFFFFFF;
    return (int32_t) (uint32_t) ans;
}
