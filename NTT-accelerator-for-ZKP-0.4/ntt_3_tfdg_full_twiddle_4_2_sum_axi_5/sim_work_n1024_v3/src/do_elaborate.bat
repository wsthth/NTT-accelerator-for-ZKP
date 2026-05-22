@echo off
call F:\XILINX\Vivado\2019.1\settings64.bat
cd /d "%~dp0"
xelab -debug typical pe_e2e_tb_n1024_quick -s sim_snapshot -log ..\xelab.log
echo XELAB_EXIT_CODE=%ERRORLEVEL%
