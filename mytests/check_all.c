/* Host-side exhaustive check of rubik_solve (not part of the submission).
 *
 *   cc -O2 -Isrc/rubik -o check_all mytests/check_all.c src/rubik/rubik.c
 *   ./check_all
 *
 * 1. BFS over all 3,674,160 states gives the exact distance of each one.
 * 2. For every state: rubik_solve returns that distance, and replaying the
 *    printed moves reaches the solved state.
 * 3. Contract edge cases: invalid inputs (-1, out untouched), small
 *    buffers (-2, out[0] = '\0'), exact-fit buffers.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rubik.h"
#include "rubik_tables.h"

enum { P = 5040, O = 729, STATES = P * O };

static const uint16_t *const TP[3] = {tp0, tp1, tp2};
static const uint16_t *const TO[3] = {to0, to1, to2};

static void unrank(uint32_t rank, char s[15])
{
    uint8_t avail[7] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / O, o = rank % O, f = 720, sum = 0;
    for (int i = 0; i < 7; ++i) {
        uint32_t q = p / f;
        p %= f;
        s[i] = (char) ('1' + avail[q]);
        for (uint32_t j = q; j + 1 < 7u - i; ++j)
            avail[j] = avail[j + 1];
        if (i < 5)
            f /= 6 - i;
    }
    for (int i = 5; i >= 0; --i) {
        s[7 + i] = (char) ('1' + o % 3);
        sum += o % 3;
        o /= 3;
    }
    s[13] = (char) ('1' + (3 - sum % 3) % 3);
    s[14] = '\0';
}

/* Replay "R2 D B'" on (p, o); returns the number of moves or -1. */
static int replay(const char *txt, uint32_t *p, uint32_t *o)
{
    int n = 0;
    while (*txt) {
        int face = *txt == 'R' ? 0 : *txt == 'B' ? 1 : *txt == 'D' ? 2 : -1;
        if (face < 0)
            return -1;
        ++txt;
        int turns = 1;
        if (*txt == '2')
            turns = 2, ++txt;
        else if (*txt == '\'')
            turns = 3, ++txt;
        for (int t = 0; t < turns; ++t)
            *p = TP[face][*p], *o = TO[face][*o];
        ++n;
        if (*txt == ' ')
            ++txt;
    }
    return n;
}

static int fails;
#define CHECK(cond, ...)                      \
    do {                                      \
        if (!(cond)) {                        \
            if (++fails < 20)                 \
                fprintf(stderr, __VA_ARGS__); \
        }                                     \
    } while (0)

static void edge_cases(void)
{
    static const char *bad[] = {
        "",                /* empty */
        "1234567111111",   /* 13 characters */
        "123456711111111", /* 15 characters */
        "12345681111111",  /* cubie digit 8 */
        "02345671111111",  /* cubie digit 0 */
        "11345671111111",  /* repeated cubie */
        "12345671111114",  /* orientation 4 */
        "12345671111110",  /* orientation 0 */
        "12345672111111",  /* orientation sum 1 */
        "12345672211111",  /* orientation sum 2 */
        "1234567111111\n",
    };
    char out[64];
    for (size_t i = 0; i < sizeof bad / sizeof *bad; ++i) {
        memset(out, 'x', sizeof out);
        int r = rubik_solve(bad[i], out, sizeof out);
        CHECK(r == -1, "invalid \"%s\" returned %d\n", bad[i], r);
        CHECK(out[0] == 'x', "invalid \"%s\" touched out\n", bad[i]);
    }

    /* solved cube: "" and 0; needs one byte for the NUL */
    memset(out, 'x', sizeof out);
    CHECK(rubik_solve("12345671111111", out, 1) == 0 && out[0] == '\0',
          "solved cube with cap 1\n");
    CHECK(rubik_solve("12345671111111", out, 0) == -2, "solved cube, cap 0\n");

    /* exact fit and one byte short for some distance-11 state */
    const char *s = NULL;
    char buf[15], full[64];
    for (uint32_t r = 0; r < STATES && !s; ++r) {
        unrank(r, buf);
        int n = rubik_solve(buf, full, sizeof full);
        if (n == 11)
            s = buf;
    }
    size_t len = strlen(full);
    memset(out, 'x', sizeof out);
    CHECK(rubik_solve(s, out, len + 1) == 11 && !strcmp(out, full),
          "exact-fit buffer\n");
    memset(out, 'x', sizeof out);
    CHECK(rubik_solve(s, out, len) == -2 && out[0] == '\0', "one byte short\n");
    CHECK(rubik_solve(s, NULL, 0) == -2, "cap 0 with NULL out\n");
    printf("edge cases done; distance-11 example %s -> %s\n", s, full);
}

int main(int argc, char **argv)
{
    /* optional stride, e.g. ./check_all 97 for a quicker sanitizer run */
    uint32_t step = argc > 1 ? (uint32_t) strtoul(argv[1], NULL, 10) : 1;
    if (step == 0)
        step = 1;
    uint8_t *dist = malloc(STATES);
    uint32_t *queue = malloc(sizeof *queue * STATES);
    if (!dist || !queue)
        return 1;
    memset(dist, 0xff, STATES);
    uint32_t head = 0, tail = 1;
    queue[0] = 0;
    dist[0] = 0;
    while (head < tail) {
        uint32_t s = queue[head++], p = s / O, o = s % O;
        for (int f = 0; f < 3; ++f) {
            uint32_t np = p, no = o;
            for (int t = 0; t < 3; ++t) {
                np = TP[f][np], no = TO[f][no];
                uint32_t n = np * O + no;
                if (dist[n] == 0xff)
                    dist[n] = (uint8_t) (dist[s] + 1), queue[tail++] = n;
            }
        }
    }
    printf("BFS reached %u states\n", tail);

    unsigned long hist[12] = {0};
    char s[15], out[64];
    for (uint32_t r = 0; r < STATES; r += step) {
        unrank(r, s);
        int n = rubik_solve(s, out, sizeof out);
        CHECK(n == dist[r], "%s: returned %d, distance %u\n", s, n, dist[r]);
        uint32_t p = r / O, o = r % O;
        int m = replay(out, &p, &o);
        CHECK(m == n && p == 0 && o == 0, "%s: \"%s\" does not solve it\n", s,
              out);
        if (n >= 0 && n <= 11)
            ++hist[n];
    }
    for (int d = 0; d <= 11; ++d)
        printf("d=%2d %7lu\n", d, hist[d]);

    edge_cases();
    free(dist);
    free(queue);
    printf("%s (%d failures)\n", fails ? "FAILED" : "all checks pass", fails);
    return fails != 0;
}
