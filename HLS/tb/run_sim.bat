@echo off
rem ===========================================================================
rem run_sim.bat - RTL system simulation of rtds_gen_top with Vivado xsim
rem   Run ..\hls\run_hls.tcl first (it creates the HLS Verilog and the golden
rem   file gen_step_golden.hex).
rem ===========================================================================
call C:\Xilinx\Vivado\2018.2\settings64.bat
cd /d %~dp0
if not exist work mkdir work
cd work

set HLS_V=..\..\hls\gen_step_prj\solution1\syn\verilog
set GOLD=..\..\hls\gen_step_prj\solution1\csim\build\gen_step_golden.hex

setlocal enabledelayedexpansion
set HLS_FILES=
for %%f in (%HLS_V%\*.v) do set HLS_FILES=!HLS_FILES! %%f
call xvlog !HLS_FILES! || exit /b 1
call xvlog -sv ..\..\rtl\uart_rx.sv ..\..\rtl\uart_tx.sv ..\..\rtl\rtds_gen_top.sv ..\rtds_gen_top_tb.sv || exit /b 1
copy /y %GOLD% gen_step_golden.hex >nul || exit /b 1
call xelab rtds_gen_top_tb -s tb_snap -timescale 1ns/1ps || exit /b 1
call xsim tb_snap -R
