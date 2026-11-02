#!/usr/bin/env bash
# T10: lint (Verilator --lint-only -Wall), run from sim/
set -euo pipefail
cd "$(dirname "$0")/.."
verilator --lint-only -Wall -Wno-DECLFILENAME \
    src/cam_s1.v src/cam_dp.v src/cam_ctrl.v src/camellia128_epsiron.v \
    --top-module camellia128_epsiron
echo "LINT PASS (no warnings)"
