#define BF16_EXP_BIAS 127
#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (f32bits >> 16) & 0xFFFF;

    f32bits += ((f32bits >> 16) & 1) + 0x7FFF;
    return f32bits >> 16;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign_a = (a >> 15) & 1;
    uint16_t sign_b = (b >> 15) & 1;
    int16_t exp_a = ((a >> 7) & 0xFF);
    int16_t exp_b = ((b >> 7) & 0xFF);
    uint16_t mant_a = a & 0x7F;
    uint16_t mant_b = b & 0x7F;

    uint16_t result_sign = sign_a ^ sign_b;

    if (exp_a == 0xFF) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return 0x7FC0;
        return (result_sign << 15) | 0x7F80;
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return 0x7FC0;
        return (result_sign << 15) | 0x7F80;
    }

    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return result_sign << 15;

    int16_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else
        mant_a |= 0x80;
    if (!exp_b) {
        while (!(mant_b & 0x80)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else
        mant_b |= 0x80;

    uint32_t result_mant = (uint32_t) mant_a * mant_b;
    int32_t result_exp = (int32_t) exp_a + exp_b - BF16_EXP_BIAS + exp_adjust;

    if (result_mant & 0x8000) {
        result_mant = (result_mant >> 8) & 0x7F;
        result_exp++;
    } else
        result_mant = (result_mant >> 7) & 0x7F;

    if (result_exp >= 0xFF)
        return (result_sign << 15) | 0x7F80;
    if (result_exp <= 0) {
        if (result_exp < -6)
            return result_sign << 15;
        result_mant >>= (1 - result_exp);
        result_exp = 0;
    }

    return (result_sign << 15) | ((result_exp & 0xFF) << 7) |
           (result_mant & 0x7F);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint16_t sign = (a >> 15) & 1;
    int16_t exp = (a >> 7) & 0xFF;
    uint16_t mant = a & 0x7F;

    // Special Case
    if (exp == 0xFF && mant != 0)  // NaN: return unchanged
        return a;
    if (sign == 0 && exp == 0xFF &&
        mant == 0)  // +Inf: return unchanged (0x7F80)
        return a;
    if (sign == 1 &&
        (a & 0x7FFF) !=
            0)  // Negative nonzero values, including -Inf: quiet NaN
        return 0x7FC0;
    if (exp == 0)  // +0, -0 and positive denormals: +0
        return 0x0000;

    // Normal Case
    int32_t e = exp - BF16_EXP_BIAS;
    uint32_t m = 0x80 | mant;
    int32_t new_exp;
    if (e & 1) {
        m <<= 1;
        new_exp = ((e - 1) >> 1) + BF16_EXP_BIAS;
    } else {
        new_exp = (e >> 1) + BF16_EXP_BIAS;
    }

    uint32_t low = 90, high = 256, result = 128;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) / 128;
        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    if (new_exp >= 0xFF)  // +Inf
        return 0x7F80;
    else if (new_exp <= 0)  // +0
        return 0x0000;
    else {
        return ((new_exp << 7) & 0x7F80) | (result & 0x007F);
    }
}
