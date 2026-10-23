@echo off
rem ===========================================================================
rem build_emu.bat - Compile the HLS C++ model of gen_step into gen_step_emu.dll
rem                 (bit-accurate FPGA emulator for pc_side.py --backend emu)
rem ===========================================================================
set XIL=C:\Xilinx\Vivado\2018.2
set PATH=%XIL%\msys64\mingw64\bin;%PATH%
cd /d %~dp0
g++ -O2 -shared -static -static-libgcc -static-libstdc++ ^
    -I%XIL%\include -I..\hls ^
    ..\hls\gen_step.cpp ..\hls\gen_step_emu.cpp ^
    -o gen_step_emu.dll || exit /b 1
echo Built %~dp0gen_step_emu.dll
