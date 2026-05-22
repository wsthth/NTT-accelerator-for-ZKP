@echo off
call F:\XILINX\Vivado\2019.1\settings64.bat
cd /d "%~dp0"
xvlog -sv reconfigurable_3d_pe_top.sv winograd_pre_transform.sv winograd_post_transform.sv segmented_256bit_full_butterfly.v montgomery_pipeline.v pe_e2e_tb.sv -log ..\xvlog.log
echo XVLOG_EXIT_CODE=%ERRORLEVEL%
