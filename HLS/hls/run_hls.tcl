# =============================================================================
# run_hls.tcl - Vivado HLS 2018.2 flow for gen_step
#
#   cd HLS/hls
#   vivado_hls -f run_hls.tcl
#
# Steps: C simulation -> C synthesis -> C/RTL co-simulation.
# Set HLS_STEPS to a subset to skip some, e.g.  set HLS_STEPS="csim csynth"
# The generated Verilog lands in gen_step_prj/solution1/syn/verilog and is
# picked up directly by ../vivado/build.tcl.
#
# "export" (IP catalog packaging) is NOT run by default: Vivado HLS 2018.x
# fails it after 2021 because the date-based IP revision overflows. The raw
# Verilog in syn/verilog is all the top-level design needs.
# =============================================================================
set steps {csim csynth cosim}
if {[info exists ::env(HLS_STEPS)]} {
    set steps $::env(HLS_STEPS)
}

open_project -reset gen_step_prj
set_top gen_step
add_files gen_step.cpp
add_files -tb gen_step_tb.cpp

open_solution -reset solution1
set_part {xc7a100tcsg324-1}
# Board clock is 100 MHz; synthesise for 8 ns to leave margin for routing.
create_clock -period 8 -name default
set_clock_uncertainty 1.0

if {[lsearch $steps csim] >= 0} {
    csim_design
}
if {[lsearch $steps csynth] >= 0} {
    csynth_design
}
if {[lsearch $steps cosim] >= 0} {
    cosim_design -rtl verilog
}
if {[lsearch $steps export] >= 0} {
    export_design -rtl verilog -format ip_catalog
}
exit
