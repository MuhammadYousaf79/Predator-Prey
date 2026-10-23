## =============================================================================
## nexys_a7.xdc - rtds_gen_top on Nexys A7-100T (xc7a100tcsg324-1)
## =============================================================================

## 100 MHz system clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }]

## CPU_RESETN (active low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

## USB-UART bridge
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { uart_rx_i }]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { uart_tx_o }]

## LEDs: [0] initialised [1] step toggle [2] UART frame error [3] deadline miss
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led_o[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led_o[1] }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { led_o[2] }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { led_o[3] }]

## Step-done pulse on PMOD JA pin 1 (probe with a scope: one pulse every 1 ms)
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports { done_o }]

## Asynchronous I/O: synchronised inside the design / not timing critical
set_false_path -from [get_ports { uart_rx_i rst_n }]
set_false_path -to   [get_ports { uart_tx_o done_o led_o[*] }]

## Configuration
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
