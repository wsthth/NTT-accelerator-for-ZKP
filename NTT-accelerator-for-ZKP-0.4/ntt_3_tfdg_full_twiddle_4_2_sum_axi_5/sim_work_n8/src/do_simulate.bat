@echo off
call F:\XILINX\Vivado\2019.1\settings64.bat
cd /d "%~dp0"
xsim sim_snapshot -t ../run.tcl -log ..\xsim.log
echo XSIM_EXIT_CODE=%ERRORLEVEL%
