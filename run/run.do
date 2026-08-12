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
# add wave -r sim:/$TOP/dut/*
add wave -position insertpoint  \
sim:/top_tb/dut/clk \
sim:/top_tb/dut/reset \
sim:/top_tb/dut/tx_out \
sim:/top_tb/dut/tick \
sim:/top_tb/dut/prey \
sim:/top_tb/dut/predator \
sim:/top_tb/dut/data_in \
sim:/top_tb/dut/valid_in \
sim:/top_tb/dut/ready_out \
sim:/top_tb/dut/done \
sim:/top_tb/dut/prey_latched \
sim:/top_tb/dut/predator_latched \
sim:/top_tb/dut/pack_counter \
sim:/top_tb/dut/pack_en
add wave -position insertpoint  \
sim:/top_tb/dut/uart/CTRL/C_state \
sim:/top_tb/dut/uart/CTRL/N_state
add wave -position insertpoint  \
sim:/top_tb/dut/uart/baud_tick

# Run
run -all