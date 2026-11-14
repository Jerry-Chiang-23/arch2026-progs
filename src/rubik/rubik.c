/* Optimal 2x2x2 solver, the C step of Homework 2 (ported from Homework 1).
 *
 * Iterative deepening A* over (permutation rank, orientation rank) with
 * h = max(pdb_p[p], pdb_o[o]). All tables are precomputed on the host by
 * tools/gen_tables.c and live in .rodata, so nothing is built at run time.
 *
 * Bare-metal constraints this file respects:
 *   - no libc beyond what the compiler may emit as memcpy/memset;
 *   - no multiplication, division or remainder: RV32I has no M extension,
 *     and those would become calls to libgcc (__mulsi3, __udivsi3, ...),
 *     so every product the solver needs comes from a small table;
 *   - only a few hundred bytes of stack (the target has 4 KiB);
 *   - no recursion and no allocator.
 */
#include <stddef.h>
#include <stdint.h>

#include "rubik.h"
#include "rubik_tables.h"

enum { CUBIES = 7, MAX_DEPTH = 11 };

static const uint16_t *const tp[3] = {tp0, tp1, tp2};
static const uint16_t *const to[3] = {to0, to1, to2};

/* Move m = face * 3 + turn, turn 0..2 meaning one, two or three quarter turns.
 */
static const char move_text[9][2] = {
    {'R', 0},    {'R', '2'}, {'R', '\''}, {'B', 0},    {'B', '2'},
    {'B', '\''}, {'D', 0},   {'D', '2'},  {'D', '\''},
};

/* Parse PPPPPPPOOOOOOO into 0-based digits. Returns 1 for a valid state.
 * The checks stop at the first bad character, so a short string is never
 * read past its NUL. */
static int parse_state(const char *s, uint8_t p[CUBIES], uint8_t o[CUBIES])
{
    unsigned seen = 0, sum = 0;
    for (int i = 0; i < CUBIES; ++i) {
        char c = s[i];
        if (c < '1' || c > '7')
            return 0;
        unsigned d = (unsigned) (c - '1');
        if (seen & (1u << d)) /* repeated cubie */
            return 0;
        seen |= 1u << d;
        p[i] = (uint8_t) d;
    }
    for (int i = 0; i < CUBIES; ++i) {
        char c = s[CUBIES + i];
        if (c < '1' || c > '3')
            return 0;
        o[i] = (uint8_t) (c - '1');
        sum += o[i];
    }
    if (s[2 * CUBIES] != '\0') /* longer than 14 characters */
        return 0;
    /* sum <= 14; bits 0, 3, 6, 9, 12 of 0x1249 mark the multiples of 3. */
    return (int) ((0x1249u >> sum) & 1u);
}

/* Products looked up instead of computed. Shift-and-add code such as
 * (r << 2) + (r << 1) is not enough: the compiler folds it back into r * 6,
 * which on RV32I becomes a call to __mulsi3. */

/* lehmer_weight[i][k] = k * (6 - i)!, for digit i of the Lehmer code.
 * Rows are padded to 8 entries (and orient_weight to 4) so that the row
 * address is i << 4 (i << 3) rather than i * 14 (i * 6), which would again
 * be a multiplication. */
static const uint16_t lehmer_weight[CUBIES - 1][8] = {
    {0, 720, 1440, 2160, 2880, 3600, 4320},
    {0, 120, 240, 360, 480, 600, 0},
    {0, 24, 48, 72, 96, 0, 0},
    {0, 6, 12, 18, 0, 0, 0},
    {0, 2, 4, 0, 0, 0, 0},
    {0, 1, 0, 0, 0, 0, 0},
};

/* orient_weight[i][v] = v * 3^(5 - i), for the first six orientations. */
static const uint16_t orient_weight[CUBIES - 1][4] = {
    {0, 243, 486}, {0, 81, 162}, {0, 27, 54}, {0, 9, 18}, {0, 3, 6}, {0, 1, 2},
};

/* Lehmer code of the permutation: p = sum smaller[i] * (6 - i)!, which is
 * the same rank as Homework 1's p = p * (7 - i) + smaller. The last digit
 * is always 0, so only six are needed. */
static uint16_t rank_p(const uint8_t p[CUBIES])
{
    unsigned r = 0;
    for (int i = 0; i < CUBIES - 1; ++i) {
        unsigned smaller = 0;
        for (int j = i + 1; j < CUBIES; ++j)
            smaller += p[j] < p[i];
        r += lehmer_weight[i][smaller];
    }
    return (uint16_t) r;
}

/* Base-3 number of the first six orientations; the seventh is implied. */
static uint16_t rank_o(const uint8_t o[CUBIES])
{
    unsigned r = 0;
    for (int i = 0; i < CUBIES - 1; ++i)
        r += orient_weight[i][o[i]];
    return (uint16_t) r;
}

/* First move index of each face: move = face * 3 + turn. */
static const uint8_t face_base[3] = {0, 3, 6};

static unsigned h(unsigned p, unsigned o)
{
    unsigned hp = pdb_p[p], ho = pdb_o[o];
    return hp > ho ? hp : ho;
}

/* One depth-first pass with the given bound, the iterative search of
 * Homework 1. On success path[0..bound-1] holds the moves. */
static int search(unsigned p, unsigned o, unsigned bound, uint8_t *path)
{
    uint16_t sp[MAX_DEPTH], so[MAX_DEPTH]; /* state expanded at depth g */
    uint16_t cp[MAX_DEPTH], co[MAX_DEPTH]; /* after the turns tried so far */
    uint8_t face_at[MAX_DEPTH], turn_at[MAX_DEPTH], last_at[MAX_DEPTH];
    unsigned g = 0;

    sp[0] = cp[0] = (uint16_t) p;
    so[0] = co[0] = (uint16_t) o;
    face_at[0] = 0;
    turn_at[0] = 0;
    last_at[0] = 3; /* no previous face at the root */
    for (;;) {
        if (turn_at[g] == 3 || face_at[g] == last_at[g]) {
            /* this face is used up, or it was turned by the parent */
            ++face_at[g];
            turn_at[g] = 0;
            cp[g] = sp[g];
            co[g] = so[g];
            if (face_at[g] == last_at[g]) {
                ++face_at[g];
            }
        }
        if (face_at[g] >= 3) { /* no children left: backtrack */
            if (g == 0)
                return 0;
            --g;
            continue;
        }
        unsigned face = face_at[g];
        unsigned turn = turn_at[g]++;
        cp[g] = tp[face][cp[g]];
        co[g] = to[face][co[g]];
        unsigned hh = h(cp[g], co[g]);
        if (g + 1 + hh > bound)
            continue; /* pruned */
        path[g] = (uint8_t) (face_base[face] + turn);
        if (hh == 0) /* only the solved state has h = 0 */
            return 1;
        sp[g + 1] = cp[g + 1] = cp[g];
        so[g + 1] = co[g + 1] = co[g];
        face_at[g + 1] = 0;
        turn_at[g + 1] = 0;
        last_at[g + 1] = (uint8_t) face;
        ++g;
    }
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t p[CUBIES], o[CUBIES], path[MAX_DEPTH];
    int len = -1;

    if (!state || !parse_state(state, p, o))
        return -1; /* out untouched */

    unsigned rp = rank_p(p), ro = rank_o(o);
    unsigned h0 = h(rp, ro);
    if (h0 == 0) {
        len = 0;
    } else {
        for (unsigned bound = h0; bound <= MAX_DEPTH; ++bound)
            if (search(rp, ro, bound, path)) {
                len = (int) bound;
                break;
            }
    }
    if (len < 0) /* unreachable for a valid state: the diameter is 11 */
        return -1;

    /* Bytes needed: each name is 1 or 2 characters, len - 1 spaces, a NUL. */
    size_t need = 1;
    for (int i = 0; i < len; ++i)
        need += (size_t) (i > 0) + 1 + (move_text[path[i]][1] != 0);
    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }

    char *w = out;
    for (int i = 0; i < len; ++i) {
        const char *m = move_text[path[i]];
        if (i > 0)
            *w++ = ' ';
        *w++ = m[0];
        if (m[1])
            *w++ = m[1];
    }
    *w = '\0';
    return len;
}
