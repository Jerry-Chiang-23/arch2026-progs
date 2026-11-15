/* Host-side table generator for src/rubik/rubik.c.
 *
 * Builds the move-transition tables and the two pattern databases with the
 * same code as Homework 1 (solver_v1.c), then prints them as C arrays.
 *
 *   cc -O2 -o gen_tables tools/gen_tables.c
 *   ./gen_tables > src/rubik/rubik_tables.h          (C, for rubik.c)
 *   ./gen_tables --asm > src/rubik/rubik_tables.S    (for rubik.S)
 *
 * The assembly also gets d5_start and d5_orient, the states at distance
 * exactly 5, which its search uses to cut the last five levels.
 *
 * The assembly and the C version cannot share one copy: an assembly object
 * may not reference a symbol of a C object, so each carries its own tables.
 *
 * This runs on the host (it uses stdio, division and a 10 KB queue on the
 * stack), so it must stay outside src/rubik/.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, PERMUTATIONS = 5040, ORIENTATIONS = 729 };

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static state_t quarter_turn(state_t s, uint8_t face)
{
    state_t r;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t from = source[face][i];
        r.p[i] = s.p[from];
        r.o[i] = (uint8_t) ((s.o[from] + twist[face][i]) % 3U);
    }
    return r;
}

static uint32_t rank_state(const state_t *s)
{
    uint32_t p = 0, o = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j)
            if (s->p[j] < s->p[i])
                ++smaller;
        p = p * (CUBIES - i) + smaller;
    }
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + s->o[i];
    return p * ORIENTATIONS + o;
}

static void unrank_state(uint32_t rank, state_t *s)
{
    uint8_t available[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / ORIENTATIONS, o = rank % ORIENTATIONS, f = 720;
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t q = (uint8_t) (p / f);
        p %= f;
        s->p[i] = available[q];
        for (uint8_t j = q; j + 1U < (unsigned) (CUBIES - i); ++j)
            available[j] = available[j + 1U];
        if (i < 5)
            f /= 6U - i;
    }
    for (uint8_t i = 6; i-- > 0;) {
        s->o[i] = (uint8_t) (o % 3U);
        sum = (uint8_t) (sum + s->o[i]);
        o /= 3U;
    }
    s->o[6] = (uint8_t) ((3U - sum % 3U) % 3U);
}

static uint16_t tp[3][PERMUTATIONS], to[3][ORIENTATIONS];
static uint8_t pdb_p[PERMUTATIONS], pdb_o[ORIENTATIONS];

static void build_transition(void)
{
    state_t s;
    for (uint16_t r = 0; r < PERMUTATIONS; ++r) {
        unrank_state((uint32_t) r * ORIENTATIONS, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            tp[f][r] = (uint16_t) (rank_state(&n) / ORIENTATIONS);
        }
    }
    for (uint16_t r = 0; r < ORIENTATIONS; ++r) {
        unrank_state(r, &s);
        for (uint8_t f = 0; f < 3; ++f) {
            state_t n = quarter_turn(s, f);
            to[f][r] = (uint16_t) (rank_state(&n) % ORIENTATIONS);
        }
    }
}

static int build_pdb(const uint16_t *trans, uint16_t n, uint8_t *dist)
{
    uint16_t queue[PERMUTATIONS];
    uint16_t head = 0, tail = 1;
    memset(dist, UINT8_MAX, n);
    queue[0] = 0;
    dist[0] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        for (uint8_t f = 0; f < 3; ++f) {
            uint16_t next = here;
            for (uint8_t t = 0; t < 3; ++t) {
                next = trans[f * n + next];
                if (dist[next] == UINT8_MAX) {
                    dist[next] = (uint8_t) (dist[here] + 1);
                    queue[tail++] = next;
                }
            }
        }
    }
    return tail == n;
}

static void emit(const char *type,
                 const char *name,
                 const void *v,
                 unsigned n,
                 int wide)
{
    printf("static const %s %s[%u] = {\n", type, name, n);
    for (unsigned i = 0; i < n; ++i) {
        unsigned x =
            wide ? ((const uint16_t *) v)[i] : ((const uint8_t *) v)[i];
        printf("%s%u,%s", i % 16 ? " " : "    ", x,
               (i % 16 == 15 || i + 1 == n) ? "\n" : "");
    }
    puts("};");
}

/* Frontier table of the assembly search: the states at distance exactly 5,
 * grouped by permutation rank. d5_start[p] and d5_start[p + 1] are byte
 * offsets into d5_orient, which holds the orientation ranks of group p.
 * The distances come from a breadth-first search over all 3,674,160 states
 * (the host needs 3.6 MB for it; the target never sees it). */
static uint16_t d5_start[PERMUTATIONS + 1];
static uint16_t d5_orient[10000];

static int build_frontier(void)
{
    const uint32_t n = (uint32_t) PERMUTATIONS * ORIENTATIONS;
    uint8_t *dist = malloc(n);
    uint32_t *queue = malloc(sizeof *queue * n);
    uint32_t head = 0, tail = 1, count = 0;
    if (!dist || !queue) {
        free(dist);
        free(queue);
        return 0;
    }
    memset(dist, UINT8_MAX, n);
    dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint32_t s = queue[head++];
        uint32_t p = s / ORIENTATIONS, o = s % ORIENTATIONS;
        for (uint8_t f = 0; f < 3; ++f) {
            uint32_t np = p, no = o;
            for (uint8_t t = 0; t < 3; ++t) {
                np = tp[f][np];
                no = to[f][no];
                uint32_t next = np * ORIENTATIONS + no;
                if (dist[next] == UINT8_MAX) {
                    dist[next] = (uint8_t) (dist[s] + 1);
                    queue[tail++] = next;
                }
            }
        }
    }
    for (uint32_t p = 0; p < PERMUTATIONS; ++p) {
        d5_start[p] = (uint16_t) (2 * count);
        for (uint32_t o = 0; o < ORIENTATIONS; ++o)
            if (dist[p * ORIENTATIONS + o] == 5 && count < 10000)
                d5_orient[count++] = (uint16_t) o;
    }
    d5_start[PERMUTATIONS] = (uint16_t) (2 * count);
    free(dist);
    free(queue);
    return tail == n && count == 9992;
}

/* Assembly form: global labels in .rodata, so that rubik.S, joined with this
 * file by ld -r into one impl_asm.o, can reach them with la. */
static void emit_asm(const char *dir,
                     const char *name,
                     const void *v,
                     unsigned n,
                     int wide)
{
    printf("\n    .globl %s\n    .balign %d\n%s:\n", name, wide ? 2 : 1, name);
    for (unsigned i = 0; i < n; ++i) {
        unsigned x =
            wide ? ((const uint16_t *) v)[i] : ((const uint8_t *) v)[i];
        printf("%s%u%s", i % 16 ? ", " : dir, x,
               (i % 16 == 15 || i + 1 == n) ? "\n" : "");
    }
}

int main(int argc, char **argv)
{
    int as = argc == 2 && !strcmp(argv[1], "--asm");
    build_transition();
    if (!build_pdb(&tp[0][0], PERMUTATIONS, pdb_p) ||
        !build_pdb(&to[0][0], ORIENTATIONS, pdb_o)) {
        fputs("incomplete pattern database\n", stderr);
        return 1;
    }
    if (as) {
        puts("# Generated by tools/gen_tables.c --asm; do not edit by hand.");
        puts("    .section .rodata");
        emit_asm("    .half ", "tp0", tp[0], PERMUTATIONS, 1);
        emit_asm("    .half ", "tp1", tp[1], PERMUTATIONS, 1);
        emit_asm("    .half ", "tp2", tp[2], PERMUTATIONS, 1);
        emit_asm("    .half ", "to0", to[0], ORIENTATIONS, 1);
        emit_asm("    .half ", "to1", to[1], ORIENTATIONS, 1);
        emit_asm("    .half ", "to2", to[2], ORIENTATIONS, 1);
        emit_asm("    .byte ", "pdb_p", pdb_p, PERMUTATIONS, 0);
        emit_asm("    .byte ", "pdb_o", pdb_o, ORIENTATIONS, 0);
        if (!build_frontier()) {
            fputs("frontier table is incomplete\n", stderr);
            return 1;
        }
        emit_asm("    .half ", "d5_start", d5_start, PERMUTATIONS + 1, 1);
        emit_asm("    .half ", "d5_orient", d5_orient, 9992, 1);
        return ferror(stdout) || fflush(stdout);
    }
    puts("/* Generated by tools/gen_tables.c; do not edit by hand. */");
    puts("#pragma once\n#include <stdint.h>");
    emit("uint16_t", "tp0", tp[0], PERMUTATIONS, 1);
    emit("uint16_t", "tp1", tp[1], PERMUTATIONS, 1);
    emit("uint16_t", "tp2", tp[2], PERMUTATIONS, 1);
    emit("uint16_t", "to0", to[0], ORIENTATIONS, 1);
    emit("uint16_t", "to1", to[1], ORIENTATIONS, 1);
    emit("uint16_t", "to2", to[2], ORIENTATIONS, 1);
    emit("uint8_t", "pdb_p", pdb_p, PERMUTATIONS, 0);
    emit("uint8_t", "pdb_o", pdb_o, ORIENTATIONS, 0);
    return ferror(stdout) || fflush(stdout);
}
