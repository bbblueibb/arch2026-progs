/* Host-only verification against BFS distances and independent move replay.
 * Usage: validate_rubik_search ORACLE [STRIDE]
 * STRIDE=1 checks every state; larger strides provide a quick initial sweep.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "../src/rubik/rubik.h"

enum { VALIDATOR_STATES = 3674160, VALIDATOR_ORI = 729 };

struct check_cube {
    uint8_t p[7], o[7];
};

static const uint8_t check_source[3][7] = {{1, 4, 2, 0, 3, 5, 6},
                                           {0, 1, 2, 4, 5, 6, 3},
                                           {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t check_twist[3][7] = {{1, 2, 0, 2, 1, 0, 0},
                                          {0, 0, 0, 1, 2, 1, 2},
                                          {0, 0, 0, 0, 0, 0, 0}};

static struct check_cube decode(uint32_t rank, char state[15])
{
    static const unsigned factorial[7] = {1, 1, 2, 6, 24, 120, 720};
    uint32_t p = rank / VALIDATOR_ORI, o = rank % VALIDATOR_ORI;
    uint8_t available[7] = {0, 1, 2, 3, 4, 5, 6};
    struct check_cube cube = {{0}, {0}};
    for (unsigned i = 0; i < 7; ++i) {
        unsigned place = factorial[6 - i];
        unsigned digit = p / place;
        p %= place;
        cube.p[i] = available[digit];
        for (unsigned j = digit; j + 1 < 7 - i; ++j)
            available[j] = available[j + 1];
    }
    unsigned sum = 0;
    for (int i = 5; i >= 0; --i) {
        cube.o[i] = (uint8_t) (o % 3);
        sum += cube.o[i];
        o /= 3;
    }
    cube.o[6] = (uint8_t) ((3 - sum % 3) % 3);
    for (unsigned i = 0; i < 7; ++i) {
        state[i] = (char) ('1' + cube.p[i]);
        state[i + 7] = (char) ('1' + cube.o[i]);
    }
    state[14] = '\0';
    return cube;
}

static int replay(struct check_cube cube, const char *text, size_t bytes)
{
    size_t pos = 0;
    int moves = 0;
    while (pos < bytes && text[pos] != '\0') {
        unsigned face;
        if (text[pos] == 'R')
            face = 0;
        else if (text[pos] == 'B')
            face = 1;
        else if (text[pos] == 'D')
            face = 2;
        else
            return -1;
        ++pos;
        unsigned turns = 1;
        if (pos < bytes && text[pos] == '2') {
            turns = 2;
            ++pos;
        } else if (pos < bytes && text[pos] == '\'') {
            turns = 3;
            ++pos;
        }
        for (unsigned t = 0; t < turns; ++t) {
            struct check_cube next;
            for (unsigned i = 0; i < 7; ++i) {
                next.p[i] = cube.p[check_source[face][i]];
                next.o[i] = (uint8_t) ((cube.o[check_source[face][i]] +
                                        check_twist[face][i]) %
                                       3);
            }
            cube = next;
        }
        ++moves;
        if (pos >= bytes)
            return -1;
        if (text[pos] != '\0') {
            if (text[pos] != ' ' || pos + 1 >= bytes || text[pos + 1] == '\0')
                return -1;
            ++pos;
        }
    }
    if (pos == bytes)
        return -1;
    for (unsigned i = 0; i < 7; ++i)
        if (cube.p[i] != i || cube.o[i] != 0)
            return -1;
    return moves;
}

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "usage: %s ORACLE [STRIDE]\n", argv[0]);
        return 2;
    }
    unsigned long stride = argc == 3 ? strtoul(argv[2], NULL, 10) : 1;
    if (stride == 0 || stride > VALIDATOR_STATES) {
        fprintf(stderr, "invalid stride\n");
        return 2;
    }
    FILE *file = fopen(argv[1], "rb");
    if (!file) {
        perror("open oracle");
        return 2;
    }
    uint8_t *distance = malloc(VALIDATOR_STATES);
    if (!distance) {
        fclose(file);
        return 2;
    }
    if (fread(distance, 1, VALIDATOR_STATES, file) != VALIDATOR_STATES ||
        fgetc(file) != EOF) {
        fprintf(stderr, "oracle must contain exactly %u distances\n",
                (unsigned) VALIDATOR_STATES);
        fclose(file);
        free(distance);
        return 2;
    }
    fclose(file);
    uint32_t checked = 0, by_depth[12] = {0};
    clock_t started = clock();
    for (uint32_t rank = 0; rank < VALIDATOR_STATES;
         rank += (uint32_t) stride) {
        char state[15], out[34];
        struct check_cube cube = decode(rank, state);
        for (unsigned i = 0; i < sizeof out; ++i)
            out[i] = '#';
        int count = rubik_solve(state, out, 33);
        int replayed = replay(cube, out, 33);
        if (count != distance[rank] || replayed != count || out[33] != '#') {
            fprintf(stderr,
                    "FAIL rank=%u state=%s expected=%u count=%d replay=%d\n",
                    rank, state, distance[rank], count, replayed);
            free(distance);
            return 1;
        }
        ++checked;
        ++by_depth[count];
        if (checked % 250000 == 0) {
            printf("checked %u states\n", checked);
            fflush(stdout);
        }
    }
    printf("PASS: %u states, stride=%lu, CPU time=%.3f seconds\n", checked,
           stride, (double) (clock() - started) / CLOCKS_PER_SEC);
    printf("By depth:");
    for (unsigned d = 0; d < 12; ++d)
        printf(" %u", by_depth[d]);
    putchar('\n');
    free(distance);
    return 0;
}
