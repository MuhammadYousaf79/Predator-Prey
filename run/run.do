# Configurable Variables
set TOP top_tb
set SRC_DIR ../

# Setup Library
vlib work

# Compile
vlog $SRC_DIR/*.sv

# Simulate
vsim -voptargs=+acc work.$TOP

# Waves (Generic)

# Add all signals automatically
add wave -r sim:/$TOP/dut/*

# Run
run -all