@echo off
REM Elaborate N=1024 testbench
xelab -debug typical pe_e2e_tb_n1024 -s sim_snapshot -log xelab.log
echo Elaborate done.
