@echo off
echo FULL CLEAN...

rmdir /s /q work 2>nul
del /q *.wlf *.log *.jou *.vstf transcript wlf* 2>nul *.vcd

echo Done.
pause