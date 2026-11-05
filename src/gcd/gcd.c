#include "gcd.h"
/* Binary GCD: only shifts, subtraction and comparison. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    else if (b == 0)
        return a;

    int k = 0;  // Count how many common factors 2 do a and b have
    while (((a | b) & 1) ==
           0) {  // Both even, same as (a & 1) == 0 && (b & 1) == 0
        a >>= 1;
        b >>= 1;
        k++;
    }
    while ((a & 1) == 0)
        a >>= 1;

    uint32_t tmp;
    while (b != 0) {
        while ((b & 1) == 0)
            b >>= 1;
        if (a > b) {
            tmp = a;
            a = b;
            b = tmp;
        }
        b -= a;  // Because a and b are both odd, so no need to write
                 // "if((a&1)==1 && (b&1)==1)" before b-=a
    }

    return a << k;
}
