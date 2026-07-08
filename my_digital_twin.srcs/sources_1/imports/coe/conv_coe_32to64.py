#!/usr/bin/env python3
"""
Convert a 32-bit irom COE file to 64-bit packed format for dual-issue IROM.

Input:  one 32-bit instruction per line
Output: two instructions packed per line: {instr[PC+4]}{instr[PC+0]} as 64-bit hex

Usage:  python3 conv_coe_32to64.py <input.coe> [output.coe]
        If output is omitted, writes to <input_basename>_64b.coe in the same directory.
"""

import sys
import os
import re


def parse_coe(path):
    """Parse a COE file, returning (radix_str, [hex_value_strings])."""
    values = []
    radix = "16"

    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Detect radix declaration
            m = re.match(r"memory_initialization_radix\s*=\s*(\d+)\s*;", line)
            if m:
                radix = m.group(1)
                continue

            # Skip the vector header line
            if line.startswith("memory_initialization_vector"):
                continue

            # Stop at trailing semicolon-only line
            if line == ";":
                break

            # Strip trailing comma and extract the value
            val = line.rstrip(",").strip()
            if val and val != ";":
                values.append(val)

    return radix, values


def pack_32to64(values_32):
    """
    Pack pairs of adjacent 32-bit values into 64-bit words.
    Lower 32 bits = word[2n]   (PC+0)
    Upper 32 bits = word[2n+1] (PC+4)
    If odd count, pad last entry with 32'h00000013 (addi x0,x0,0 = RISC-V nop).
    """
    NOP = "00000013"
    packed = []
    for i in range(0, len(values_32), 2):
        lo = values_32[i]                     # instruction at PC+0
        hi = values_32[i + 1] if i + 1 < len(values_32) else NOP
        # Pad to 8 hex digits if needed (COE values may omit leading zeros)
        lo = lo.zfill(8)
        hi = hi.zfill(8)
        packed.append(f"{hi}{lo}")
    return packed


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.coe> [output.coe]")
        sys.exit(1)

    src = sys.argv[1]
    if len(sys.argv) >= 3:
        dst = sys.argv[2]
    else:
        base = os.path.splitext(os.path.basename(src))[0]
        dst = os.path.join(os.path.dirname(src), f"{base}_64b.coe")

    radix, vals_32 = parse_coe(src)
    vals_64 = pack_32to64(vals_32)

    with open(dst, "w") as f:
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")
        for j, w in enumerate(vals_64):
            trailer = "," if j < len(vals_64) - 1 else ";"
            f.write(f"{w}{trailer}\n")

    print(f"  {src} ({len(vals_32)} x 32-bit) -> {dst} ({len(vals_64)} x 64-bit)")


if __name__ == "__main__":
    main()
