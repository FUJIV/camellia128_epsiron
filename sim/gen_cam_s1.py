#!/usr/bin/env python3
"""
gen_cam_s1.py -- regenerate src/cam_s1.v (explicit 256-entry case statement)
from tv/s1.hex.

tv/s1.hex stays the single source of truth for the s1 table (spec 12.1);
this script is how changes to it get carried into the self-contained RTL
(no $readmemh / external file dependency at synthesis or simulation time).

Usage (from the project root):
    python3 sim/gen_cam_s1.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S1_HEX = os.path.join(ROOT, "tv", "s1.hex")
OUT = os.path.join(ROOT, "src", "cam_s1.v")


def main():
    with open(S1_HEX) as f:
        vals = [line.strip() for line in f if line.strip()]
    assert len(vals) == 256, "tv/s1.hex must have 256 entries, got %d" % len(vals)

    lines = [
        "`default_nettype none",
        "//",
        "// cam_s1 -- Camellia s1 S-box (256-entry lookup, from tv/s1.hex)",
        "//",
        "// Physically the only S-box in the design. s2/s3/s4 are realised around this",
        "// single table by rotating the input (handled by cam_dp's ALU XORR mode) and/or",
        "// the output (handled by cam_dp's output-rotation mux). See spec section 6.7.",
        "//",
        "// Implemented as an explicit combinational case statement (no $readmemh / no",
        "// external file dependency at synthesis or simulation time -- the RTL is",
        "// self-contained). Generated from tv/s1.hex by sim/gen_cam_s1.py; do not",
        "// hand-edit -- regenerate if tv/s1.hex changes.",
        "//",
        "module cam_s1 (",
        "    input  wire [7:0] a,",
        "    output reg  [7:0] d",
        ");",
        "",
        "    always @* begin",
        "        case (a)",
    ]
    for i, v in enumerate(vals):
        lines.append("            8'h%02x: d = 8'h%s;" % (i, v))
    lines += [
        "            default: d = 8'h00;",
        "        endcase",
        "    end",
        "",
        "endmodule",
        "",
    ]

    with open(OUT, "w") as f:
        f.write("\n".join(lines))
    print("wrote %s (%d case items)" % (OUT, len(vals)))


if __name__ == "__main__":
    main()
