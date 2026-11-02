# syn/ooc_synth.tcl -- Vivado OOC (out-of-context) synthesis for sizing
#
# Non-project batch-mode synthesis: reads the RTL directly, synthesizes
# camellia128_epsiron in out-of-context mode (no I/O buffers, so the
# resource counts reflect the core only -- spec 8.2), and writes reports.
# No .xpr project is created, so there is nothing project-shaped to track.
#
# Run from the project root:
#   vivado -mode batch -nojournal -nolog -source syn/ooc_synth.tcl
# or:
#   make -C syn
#
# All outputs go to syn/run/ (gitignored -- regenerate by re-running this).

set part   xcsu10p-cmva361-1-e
set outdir syn/run

file mkdir $outdir

read_verilog [list \
    src/cam_s1.v \
    src/cam_dp.v \
    src/cam_ctrl.v \
    src/camellia128_epsiron.v \
]

synth_design -top camellia128_epsiron -part $part -mode out_of_context

create_clock -name clk -period 10.0 [get_ports clk]

write_checkpoint -force $outdir/post_synth.dcp

report_utilization                 -file $outdir/utilization.rpt
report_utilization -hierarchical   -file $outdir/utilization_hier.rpt
report_ram_utilization             -file $outdir/ram_utilization.rpt
report_timing_summary              -file $outdir/timing_summary.rpt
report_timing -max_paths 5         -file $outdir/timing_top5.rpt

puts "=== camellia128_epsiron OOC synthesis complete. Reports in $outdir/ ==="
