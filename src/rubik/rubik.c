#include "rubik.h"

#include "rubik_search_tables.h"

/* Rank, move, and face conventions follow the HW1 cube model.
 * Move order: R R2 R' B B2 B' D D2 D'.
 * Search strategy: a five-move suffix table and an exact-distance-eleven table,
 * following the approach of weiso131/minirubik. Transition tables avoid
 * reconstructing and ranking a complete cube at every search node.
 */
static const uint16_t *const rb_perm_face[3] = {
    rb_perm_next, rb_perm_next + 5040, rb_perm_next + 10080};
static const uint16_t *const rb_ori_face[3] = {rb_ori_next, rb_ori_next + 729,
                                               rb_ori_next + 1458};
static const uint8_t rb_face[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t rb_turns[9] = {1, 2, 3, 1, 2, 3, 1, 2, 3};
static const char *const rb_names[9] = {"R",  "R2", "R'", "B", "B2",
                                        "B'", "D",  "D2", "D'"};

struct rb_frame {
    uint16_t p, o;
    uint16_t child_p, child_o;
    uint32_t next_move, previous_face;
};

/* A valid permutation fills every entry before it is ranked. */
static int rb_parse(const char *state, uint16_t *p_out, uint16_t *o_out)
{
    uint8_t permutation[7];
    uint32_t seen = 0, sum = 0, orientation = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned value = (unsigned char) state[i] - (unsigned) '1';
        if (value >= 7 || (seen & (1u << value)))
            return 0;
        seen |= 1u << value;
        permutation[i] = (uint8_t) value;
    }
    for (unsigned i = 0; i < 7; ++i) {
        unsigned value = (unsigned char) state[i + 7] - (unsigned) '1';
        if (value >= 3)
            return 0;
        sum += value;
        if (i < 6)
            orientation = orientation + (orientation << 1) + value;
    }
    if (state[14] != '\0')
        return 0;
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return 0;

    uint32_t rank = 0;
    for (unsigned i = 0; i < 6; ++i) {
        uint32_t smaller = 0;
        for (unsigned j = i + 1; j < 7; ++j)
            smaller += permutation[j] < permutation[i];
        rank = rank * (7u - i) + smaller;
    }
    *p_out = (uint16_t) rank;
    *o_out = (uint16_t) orientation;
    return 1;
}

/* 729 = 9*9*9. The shift/add chain avoids a hot multiply helper. */
static uint32_t rb_rank(uint16_t p, uint16_t o)
{
    uint32_t value = p;
    value += value << 3;
    value += value << 3;
    return value + (value << 3) + o;
}

/* Each sorted entry is (rank << 4) | move. Compare against rank << 4,
 * so a binary-search iteration does not need to unpack the stored rank.
 * Move 15 is used only by the solved entry, which needs no move.
 */
static int rb_lookup(const uint32_t *table, uint32_t count, uint32_t rank)
{
    uint32_t key = rank << 4;
    uint32_t lo = 0, hi = count;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        if (table[mid] < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    if (lo < count && (table[lo] >> 4) == rank)
        return (int) (table[lo] & 15u);
    return -1;
}

static void rb_apply(uint16_t *p, uint16_t *o, unsigned move)
{
    const uint16_t *pt = rb_perm_face[rb_face[move]];
    const uint16_t *ot = rb_ori_face[rb_face[move]];
    for (unsigned turn = 0; turn < rb_turns[move]; ++turn) {
        *p = pt[*p];
        *o = ot[*o];
    }
}

/* At most five prefix moves and six frames. A parent's child rank is retained
 * while descending, so R, R2, R' reuse successive quarter-turn lookups.
 */
static int rb_prefix(uint16_t *p,
                     uint16_t *o,
                     unsigned previous_face,
                     uint8_t *path,
                     unsigned *length)
{
    struct rb_frame stack[6];
    uint16_t root_p = *p, root_o = *o;
    unsigned offset = *length;
    for (unsigned bound = 1; bound <= 5; ++bound) {
        int top = 0;
        stack[0].p = root_p;
        stack[0].o = root_o;
        stack[0].child_p = root_p;
        stack[0].child_o = root_o;
        stack[0].next_move = 0;
        stack[0].previous_face = previous_face;
        while (top >= 0) {
            struct rb_frame *frame = &stack[top];
            if (frame->next_move >= 9) {
                --top;
                continue;
            }
            unsigned move = frame->next_move++;
            unsigned face = rb_face[move];
            if (face == frame->previous_face)
                continue;
            if (move == 0 || move == 3 || move == 6) {
                frame->child_p = frame->p;
                frame->child_o = frame->o;
            }
            frame->child_p = rb_perm_face[face][frame->child_p];
            frame->child_o = rb_ori_face[face][frame->child_o];
            path[offset + (unsigned) top] = (uint8_t) move;
            if ((unsigned) top + 1 == bound) {
                int next = rb_lookup(rb_near, RB_NEAR_COUNT,
                                     rb_rank(frame->child_p, frame->child_o));
                if (next >= 0) {
                    *p = frame->child_p;
                    *o = frame->child_o;
                    *length = offset + bound;
                    return next;
                }
            } else {
                struct rb_frame *child = &stack[top + 1];
                child->p = frame->child_p;
                child->o = frame->child_o;
                child->child_p = frame->child_p;
                child->child_o = frame->child_o;
                child->next_move = 0;
                child->previous_face = face;
                ++top;
            }
        }
    }
    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint16_t p = 0, o = 0;
    if (!rb_parse(state, &p, &o))
        return -1;
    if (cap == 0)
        return -2;
    if (p == 0 && o == 0) {
        out[0] = '\0';
        return 0;
    }
    if (cap == 1) {
        out[0] = '\0';
        return -2;
    }

    uint8_t path[11];
    unsigned length = 0;
    int next = rb_lookup(rb_near, RB_NEAR_COUNT, rb_rank(p, o));
    if (next < 0) {
        unsigned previous_face = 3;
        int first = rb_lookup(rb_far, RB_FAR_COUNT, rb_rank(p, o));
        if (first >= 0) {
            if (first >= 9)
                return -1;
            path[length++] = (uint8_t) first;
            previous_face = rb_face[first];
            rb_apply(&p, &o, (unsigned) first);
        }
        next = rb_prefix(&p, &o, previous_face, path, &length);
        if (next < 0)
            return -1;
    }

    while (p != 0 || o != 0) {
        if (next < 0 || next >= 9 || length >= 11)
            return -1;
        path[length++] = (uint8_t) next;
        rb_apply(&p, &o, (unsigned) next);
        if (p != 0 || o != 0)
            next = rb_lookup(rb_near, RB_NEAR_COUNT, rb_rank(p, o));
    }

    size_t needed = 1;
    for (unsigned i = 0; i < length; ++i) {
        if (i != 0)
            ++needed;
        needed += rb_names[path[i]][1] == '\0' ? 1u : 2u;
    }
    if (needed > cap) {
        out[0] = '\0';
        return -2;
    }
    char *dest = out;
    for (unsigned i = 0; i < length; ++i) {
        if (i != 0)
            *dest++ = ' ';
        const char *name = rb_names[path[i]];
        *dest++ = name[0];
        if (name[1] != '\0')
            *dest++ = name[1];
    }
    *dest = '\0';
    return (int) length;
}
