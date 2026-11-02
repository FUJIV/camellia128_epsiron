#!/usr/bin/env python3
"""
gen_keyrom.py -- regenerate the keyrom_lut function body (in src/cam_ctrl.v)
from tv/keyrom.hex.

tv/keyrom.hex stays the single source of truth for the key-ROM control table
(spec 12.3); this script prints the Verilog `function` text that replaces
the $readmemh-loaded array in src/cam_ctrl.v, so the RTL has no external
file dependency at synthesis or simulation time (same rationale as
cam_s1.v / sim/gen_cam_s1.py).

Unlike cam_s1.v (which is entirely generated), cam_ctrl.v is mostly
hand-written, so this script does NOT overwrite the file -- it only prints
the function body on stdout. Splice it in by hand (between the "key ROM"
comment and the `assign ent = ...` line) if tv/keyrom.hex ever changes.

Usage (from the project root):
    python3 sim/gen_keyrom.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYROM_HEX = os.path.join(ROOT, "tv", "keyrom.hex")


def main():
    with open(KEYROM_HEX) as f:
        vals = [line.strip() for line in f if line.strip()]
    assert len(vals) == 64, "tv/keyrom.hex must have 64 entries, got %d" % len(vals)

    print("    // ---------------- key ROM: keyrom_lut({dec,step}) = {base[5:0], sh[2:0]} --")
    print("    // Generated from tv/keyrom.hex by sim/gen_keyrom.py; do not hand-edit --")
    print("    // regenerate if tv/keyrom.hex changes.")
    print("    function [8:0] keyrom_lut;")
    print("        input [5:0] idx;")
    print("        begin")
    print("            case (idx)")
    for i, v in enumerate(vals):
        print("                6'h%02x: keyrom_lut = 9'h%s;" % (i, v))
    print("                default: keyrom_lut = 9'h000;")
    print("            endcase")
    print("        end")
    print("    endfunction")


if __name__ == "__main__":
    main()
