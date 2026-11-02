#!/usr/bin/env python3
"""Generate compact Rubik tables on the host, never on the RV32I target.

Cube model: sysprog21/minirubik, also used by the HW2 contract.
Search strategy reference: weiso131/minirubik (five-move suffix and
exact-distance-eleven tables). Entries here pack rank and move together.
"""

import argparse
from array import array
from collections import Counter
from itertools import permutations
from pathlib import Path
import re
import time

P_COUNT = 5040
O_COUNT = 729
N_STATES = P_COUNT * O_COUNT
SOURCES = (
    (1, 4, 2, 0, 3, 5, 6),
    (0, 1, 2, 4, 5, 6, 3),
    (0, 2, 5, 3, 1, 4, 6),
)
TWISTS = (
    (1, 2, 0, 2, 1, 0, 0),
    (0, 0, 0, 1, 2, 1, 2),
    (0, 0, 0, 0, 0, 0, 0),
)


def transitions():
    perms = list(permutations(range(7)))
    ranks = {p: i for i, p in enumerate(perms)}
    p_quarter = []
    o_quarter = []
    for face in range(3):
        source = SOURCES[face]
        p_row = array("H", (
            ranks[tuple(p[source[j]] for j in range(7))] for p in perms
        ))
        o_row = array("H")
        for rank in range(O_COUNT):
            ori = [0] * 7
            rest = rank
            for j in range(5, -1, -1):
                rest, ori[j] = divmod(rest, 3)
            ori[6] = (-sum(ori[:6])) % 3
            moved = [(ori[source[j]] + TWISTS[face][j]) % 3
                     for j in range(7)]
            value = 0
            for digit in moved[:6]:
                value = value * 3 + digit
            o_row.append(value)
        assert all(p_row[p_row[p_row[p_row[p]]]] == p for p in range(P_COUNT))
        assert all(o_row[o_row[o_row[o_row[o]]]] == o for o in range(O_COUNT))
        p_quarter.append(p_row)
        o_quarter.append(o_row)

    # Temporary nine-move transitions speed up the host BFS. Only the three
    # quarter-turn rows are exported to the target.
    p_nine, o_nine = [], []
    for face in range(3):
        p = array("H", range(P_COUNT))
        o = array("H", range(O_COUNT))
        for _ in range(3):
            p = array("H", (p_quarter[face][v] for v in p))
            o = array("H", (o_quarter[face][v] for v in o))
            p_nine.append(p)
            o_nine.append(o)
    return p_quarter, o_quarter, p_nine, o_nine


def bfs(p_nine, o_nine):
    distances = bytearray(b"\xff") * N_STATES
    toward = bytearray(b"\x0f") * N_STATES
    queue = array("I", [0]) * N_STATES
    assert queue.itemsize == 4
    distances[0] = 0
    head, tail, level_end = 0, 1, 1
    level = 0
    moves = []
    for move in range(9):
        inverse = (move // 3) * 3 + (2 - move % 3)
        scaled = array("I", (v * O_COUNT for v in p_nine[move]))
        moves.append((scaled, o_nine[move], inverse))
    while head < tail:
        p, o = divmod(queue[head], O_COUNT)
        next_distance = distances[queue[head]] + 1
        head += 1
        for p_row, o_row, inverse in moves:
            child = p_row[p] + o_row[o]
            if distances[child] == 255:
                distances[child] = next_distance
                toward[child] = inverse
                queue[tail] = child
                tail += 1
        if head == level_end:
            print(f"Expanded depth {level}; discovered {tail} states", flush=True)
            level += 1
            level_end = tail
    assert tail == N_STATES, (tail, N_STATES)
    counts = Counter(distances)
    assert max(counts) == 11
    assert sum(counts[d] for d in range(6)) == 12224
    assert counts[11] == 2644

    # Every stored move must reduce the independent BFS distance by one.
    for rank in range(1, N_STATES):
        p, o = divmod(rank, O_COUNT)
        move = toward[rank]
        parent = p_nine[move][p] * O_COUNT + o_nine[move][o]
        assert distances[parent] + 1 == distances[rank]
    return distances, toward, counts


def emit_array(stream, ctype, name, values):
    stream.write(f"static const {ctype} {name}[{len(values)}] = {{\n")
    width = 8 if ctype == "uint32_t" else 12
    for i in range(0, len(values), width):
        stream.write("    " + ", ".join(str(v) for v in values[i:i + width]))
        stream.write(",\n")
    stream.write("};\n\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--asm-output", type=Path,
                        help="also emit private assembly tables from the same data")
    parser.add_argument("--oracle", type=Path, required=True,
                        help="host-only BFS distances; keep outside src and Git")
    parser.add_argument("--check-hw1", type=Path,
                        help="compare every quarter-turn entry with the HW1 tables")
    args = parser.parse_args()
    started = time.monotonic()
    p_q, o_q, p_nine, o_nine = transitions()
    if args.check_hw1:
        text = args.check_hw1.read_text(encoding="utf-8")
        for name, rows in (("permutation_transition", p_q),
                           ("orientation_transition", o_q)):
            match = re.search(rf"\b{name}\s*\[\s*\d+\s*\]\s*=\s*\{{(.*?)\}};",
                              text, flags=re.S)
            if match is None:
                raise SystemExit(f"Missing HW1 table: {name}")
            old = [int(v) for v in re.findall(r"\d+", match.group(1))]
            new = [v for row in rows for v in row]
            if old != new:
                raise SystemExit(f"Quarter-turn table differs from HW1: {name}")
        print("Every quarter-turn transition matches HW1: PASS", flush=True)
    distances, toward, counts = bfs(p_nine, o_nine)
    near = array("I", ((rank << 4) | toward[rank]
                      for rank, d in enumerate(distances) if d <= 5))
    far = array("I", ((rank << 4) | toward[rank]
                     for rank, d in enumerate(distances) if d == 11))
    payload = 2 * (3 * P_COUNT + 3 * O_COUNT) + 4 * (len(near) + len(far))
    assert payload == 94086

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.with_suffix(args.output.suffix + ".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("/* Generated by mytests/gen_rubik_search_tables.py. */\n")
        stream.write("#pragma once\n\n#include <stdint.h>\n\n")
        stream.write("#define RB_NEAR_COUNT 12224u\n#define RB_FAR_COUNT 2644u\n\n")
        emit_array(stream, "uint16_t", "rb_perm_next", array("H", (
            value for row in p_q for value in row
        )))
        emit_array(stream, "uint16_t", "rb_ori_next", array("H", (
            value for row in o_q for value in row
        )))
        emit_array(stream, "uint32_t", "rb_near", near)
        emit_array(stream, "uint32_t", "rb_far", far)
    temp.replace(args.output)
    if args.asm_output:
        args.asm_output.parent.mkdir(parents=True, exist_ok=True)
        asm_temp = args.asm_output.with_suffix(args.asm_output.suffix + ".tmp")
        with asm_temp.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write("# Generated by mytests/gen_rubik_search_tables.py.\n")
            for name, directive, values in (
                (".Lrb_perm_next", ".2byte", [v for row in p_q for v in row]),
                (".Lrb_ori_next", ".2byte", [v for row in o_q for v in row]),
                (".Lrb_near_table", ".4byte", near),
                (".Lrb_far_table", ".4byte", far),
            ):
                stream.write(f"    .balign 4\n{name}:\n")
                for start in range(0, len(values), 12):
                    words = ", ".join(str(v) for v in values[start:start + 12])
                    stream.write(f"    {directive} {words}\n")
        asm_temp.replace(args.asm_output)
        print(f"Assembly tables: {args.asm_output}")
    args.oracle.parent.mkdir(parents=True, exist_ok=True)
    args.oracle.write_bytes(distances)
    print("Distance histogram:", [counts[d] for d in range(12)])
    print(f"Five-move entries: {len(near)}")
    print(f"Distance-eleven entries: {len(far)}")
    print(f"Target table payload: {payload} bytes (code/workspace not included)")
    print(f"Every nonzero state's stored move lowers BFS distance: PASS")
    print(f"Header: {args.output}")
    print(f"Host-only oracle: {args.oracle}")
    print(f"Generator elapsed: {time.monotonic() - started:.2f} s")


if __name__ == "__main__":
    main()
