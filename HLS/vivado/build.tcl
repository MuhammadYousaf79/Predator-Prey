# =============================================================================
# build.tcl - Non-project Vivado 2018.2 flow: synth -> place -> route -> bit
#
#   cd HLS/vivado
#   vivado -mode batch -source build.tcl
#
# Needs the HLS RTL first (HLS/hls: vivado_hls -f run_hls.tcl).
# Outputs in HLS/vivado/out: rtds_gen_top.bit + timing / utilisation reports.
# The script stops with an error if any setup or hold slack is negative.
# =============================================================================
set here   [file normalize [file dirname [info script]]]
set root   [file normalize $here/..]
set outdir $here/out
file mkdir $outdir

set part xc7a100tcsg324-1
set top  rtds_gen_top

set hls_v [glob -nocomplain $root/hls/gen_step_prj/solution1/syn/verilog/*.v]
if {[llength $hls_v] == 0} {
    error "HLS RTL not found - run vivado_hls -f run_hls.tcl in HLS/hls first"
}

read_verilog $hls_v
read_verilog -sv [list \
    $root/rtl/uart_rx.sv \
    $root/rtl/uart_tx.sv \
    $root/rtl/rtds_gen_top.sv]
read_xdc $root/constr/nexys_a7.xdc

synth_design -top $top -part $part
write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $outdir/utilization_synth.rpt

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force $outdir/post_route.dcp

report_timing_summary -max_paths 10 -file $outdir/timing_summary.rpt
report_utilization -file $outdir/utilization.rpt
report_drc -file $outdir/drc.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "=========================================================="
puts " Worst setup slack (WNS) : $wns ns"
puts " Worst hold  slack (WHS) : $whs ns"
puts "=========================================================="
if {$wns < 0 || $whs < 0} {
    error "Timing NOT met - see $outdir/timing_summary.rpt"
}

write_bitstream -force $outdir/$top.bit
puts "Bitstream: $outdir/$top.bit"
