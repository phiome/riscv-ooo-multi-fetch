#!/usr/bin/env python3

import sys
import re
from collections import defaultdict


def categorize(instr_hex):
    instr  = int(instr_hex, 16)
    opcode = instr & 0x7F
    f3     = (instr >> 12) & 0x7
    f7     = (instr >> 25) & 0x7F

    if opcode == 0x33:
        if   f7 == 0x00: names = {0:'ADD',1:'SLL',2:'SLT',3:'SLTU',4:'XOR',5:'SRL',6:'OR',7:'AND'}
        elif f7 == 0x20: names = {0:'SUB', 5:'SRA'}
        elif f7 == 0x04: names = {1:'CLZ', 2:'CTZ', 3:'CPOP'}
        else:            names = {}
        return f"R-type::{names.get(f3, f'R?f7={f7}f3={f3}')}"
    elif opcode == 0x13:
        names = {0:'ADDI',1:'SLLI',2:'SLTI',3:'SLTIU',4:'XORI',5:'SRLI/SRAI',6:'ORI',7:'ANDI'}
        return f"I-ALU::{names.get(f3,'?')}"
    elif opcode == 0x03:
        names = {0:'LB',1:'LH',2:'LW',4:'LBU',5:'LHU'}
        return f"Load::{names.get(f3,'?')}"
    elif opcode == 0x23:
        names = {0:'SB',1:'SH',2:'SW'}
        return f"Store::{names.get(f3,'?')}"
    elif opcode == 0x63:
        names = {0:'BEQ',1:'BNE',4:'BLT',5:'BGE',6:'BLTU',7:'BGEU'}
        return f"Branch::{names.get(f3,'?')}"
    elif opcode == 0x6F: return "Jump::JAL"
    elif opcode == 0x67: return "Jump::JALR"
    elif opcode == 0x37: return "Upper::LUI"
    elif opcode == 0x17: return "Upper::AUIPC"
    return f"Other::op={hex(opcode)}"


def parse_log(path):
    entries = []

    pat_store = re.compile(
        r'0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)'
        r'\s+mem\s+0x([0-9a-fA-F]+)\s+0x([0-9a-fA-F]+)'
    )
    pat_load = re.compile(
        r'0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)'
        r'\s+x(\d+)\s+0x([0-9a-fA-F]+)'
        r'\s+mem\s+0x([0-9a-fA-F]+)'
    )
    pat_reg = re.compile(
        r'0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)'
        r'\s+x(\d+)\s+0x([0-9a-fA-F]+)'
    )
    pat_base = re.compile(
        r'0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)'
    )

    try:
        with open(path) as f:
            for line in f:
                s = line.strip()
                m = pat_store.match(s)
                if m:
                    entries.append((m.group(1), m.group(2), None, None, m.group(3), m.group(4)))
                    continue
                m = pat_load.match(s)
                if m:
                    entries.append((m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), None))
                    continue
                m = pat_reg.match(s)
                if m:
                    entries.append((m.group(1), m.group(2), m.group(3), m.group(4), None, None))
                    continue
                m = pat_base.match(s)
                if m:
                    entries.append((m.group(1), m.group(2), None, None, None, None))
    except FileNotFoundError:
        print(f"[ERROR] File not found: {path}")
        sys.exit(1)
    return entries


def compare(golden, student):
    stats   = defaultdict(lambda: {'pass': 0, 'fail': 0, 'errors': []})
    missing = 0

    for i, g_entry in enumerate(golden):
        pc_g, instr_g, rd_g, val_g, maddr_g, mval_g = g_entry
        cat = categorize(instr_g)
        cat_is_branch = cat.startswith('Branch')
        cat_is_jump   = cat.startswith('Jump')

        if i >= len(student):
            missing += 1
            stats[cat]['fail'] += 1
            if rd_g:
                stats[cat]['errors'].append(
                    f"  PC=0x{pc_g}  [{instr_g}]  expected x{rd_g}=0x{val_g}  -> not in log"
                )
            elif maddr_g:
                stats[cat]['errors'].append(
                    f"  PC=0x{pc_g}  [{instr_g}]  expected mem[0x{maddr_g}]=0x{mval_g}  -> not in log"
                )
            continue

        pc_s, instr_s, rd_s, val_s, maddr_s, mval_s = student[i]

        pc_ok = (pc_g == pc_s)
        op_ok = False

        # Store
        if mval_g is not None:
            op_ok = (maddr_g == maddr_s and mval_g == mval_s)
            if pc_ok and op_ok:
                stats[cat]['pass'] += 1
            else:
                stats[cat]['fail'] += 1
                if len(stats[cat]['errors']) < 3:
                    if not pc_ok:
                        stats[cat]['errors'].append(
                            f"  PC expected=0x{pc_g}  got=0x{pc_s}"
                        )
                    if not op_ok:
                        if maddr_g != maddr_s:
                            stats[cat]['errors'].append(
                                f"  PC=0x{pc_g}  expected addr=0x{maddr_g}  got addr=0x{maddr_s or '?'}  |  expected val=0x{mval_g}  got val=0x{mval_s or '?'}"
                            )
                        else:
                            stats[cat]['errors'].append(
                                f"  PC=0x{pc_g}  mem[0x{maddr_g}]: expected=0x{mval_g}  got=0x{mval_s or '?'}"
                            )
            continue

        # Branch
        if rd_g is None:
            if cat_is_branch and i + 1 < len(golden) and i + 1 < len(student):
                next_pc_g = golden[i + 1][0]
                next_pc_s = student[i + 1][0]
                op_ok = (next_pc_g == next_pc_s)
            elif cat_is_jump and i + 1 < len(golden) and i + 1 < len(student):
                next_pc_g = golden[i + 1][0]
                next_pc_s = student[i + 1][0]
                op_ok = (next_pc_g == next_pc_s)
            else:
                op_ok = True

            if pc_ok and op_ok:
                stats[cat]['pass'] += 1
            else:
                stats[cat]['fail'] += 1
                if len(stats[cat]['errors']) < 3:
                    if not pc_ok:
                        stats[cat]['errors'].append(
                            f"  PC expected=0x{pc_g}  got=0x{pc_s}"
                        )
                    if not op_ok:
                        kind = "branch" if cat_is_branch else "jump"
                        stats[cat]['errors'].append(
                            f"  PC=0x{pc_g}  wrong {kind} target: expected next PC=0x{next_pc_g}  got=0x{next_pc_s}"
                        )
            continue

        # Register write (ALU, load, jump)
        op_ok = (rd_g == rd_s and val_g == val_s)

        if cat_is_jump and i + 1 < len(golden) and i + 1 < len(student):
            next_pc_g = golden[i + 1][0]
            next_pc_s = student[i + 1][0]
            jump_target_ok = (next_pc_g == next_pc_s)
        else:
            jump_target_ok = True

        if pc_ok and op_ok and jump_target_ok:
            stats[cat]['pass'] += 1
        else:
            stats[cat]['fail'] += 1
            if len(stats[cat]['errors']) < 3:
                if not pc_ok:
                    stats[cat]['errors'].append(
                        f"  PC expected=0x{pc_g}  got=0x{pc_s}"
                    )
                if not op_ok:
                    stats[cat]['errors'].append(
                        f"  PC=0x{pc_g}  x{rd_g}: expected=0x{val_g}  got=0x{val_s or '?'}"
                    )
                if not jump_target_ok:
                    stats[cat]['errors'].append(
                        f"  PC=0x{pc_g}  wrong jump target: expected next PC=0x{next_pc_g}  got=0x{next_pc_s}"
                    )

    return stats, missing


COLORS = {
    'green':  '\033[92m',
    'red':    '\033[91m',
    'yellow': '\033[93m',
    'bold':   '\033[1m',
    'reset':  '\033[0m',
}

def color(text, *keys):
    return ''.join(COLORS[k] for k in keys) + text + COLORS['reset']

def print_report(stats, missing, total_golden):
    groups = defaultdict(dict)
    for key, val in stats.items():
        group, name = key.split('::')
        groups[group][name] = val

    total_pass = total_fail = 0

    print()
    print(color("═" * 60, 'bold'))
    print(color("  RISC-V Processor Test Report", 'bold'))
    print(color("═" * 60, 'bold'))

    group_order = ['R-type', 'I-ALU', 'Load', 'Store', 'Branch', 'Jump', 'Upper', 'Other']

    for group in group_order:
        if group not in groups:
            continue

        g_pass = sum(v['pass'] for v in groups[group].values())
        g_fail = sum(v['fail'] for v in groups[group].values())
        g_total = g_pass + g_fail
        total_pass += g_pass
        total_fail += g_fail

        status = color("PASS", 'green', 'bold') if g_fail == 0 else color("FAIL", 'red', 'bold')
        pct = int(100 * g_pass / g_total) if g_total else 0

        print(f"\n  [{status}] {color(group, 'bold')}  ({g_pass}/{g_total}  %{pct})")

        for name, v in sorted(groups[group].items()):
            t = v['pass'] + v['fail']
            if t == 0:
                continue
            mark = color("✓", 'green') if v['fail'] == 0 else color("✗", 'red')
            print(f"         {mark}  {name:<12} {v['pass']}/{t}")

            for err in v['errors']:
                print(color(err, 'yellow'))
            if v['fail'] > 3:
                print(color(f"         ... and {v['fail']-3} more errors", 'yellow'))

    grand_total = total_pass + total_fail
    pct_grand   = int(100 * total_pass / grand_total) if grand_total else 0

    print()
    print(color("─" * 60, 'bold'))
    if total_fail == 0:
        print(color(f"  TOTAL: {total_pass}/{grand_total} (%{pct_grand}) — All tests passed!", 'green', 'bold'))
    else:
        print(color(f"  TOTAL: {total_pass}/{grand_total} (%{pct_grand})", 'bold'))
    if missing:
        print(color(f"  WARNING: {missing} lines missing from student log (simulation may have ended early)", 'yellow'))
    print(color("─" * 60, 'bold'))
    print()


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("[ERROR] Usage: python3 check_result.py <student_log> <golden_log>")
        sys.exit(1)
    student_log = sys.argv[1]
    golden_log  = sys.argv[2]

    print(f"Golden : {golden_log}")
    print(f"Student: {student_log}")

    golden  = parse_log(golden_log)
    student = parse_log(student_log)

    stats, missing = compare(golden, student)
    print_report(stats, missing, len(golden))