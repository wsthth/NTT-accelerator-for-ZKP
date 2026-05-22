@echo off
call F:/XILINX/Vivado/2019.1/settings64.bat
cd /d "%~dp0"
xvlog -sv "../sour/PE/Reconfigurable Butterfly Unit/reconfigurable_3d_pe_top.sv" "../sour/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" "../sour/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" "../sour/PE/sub_pe/segmented_256bit_full_butterfly.v" "../sour/montgomery_pipeline.v" "../sour/PE/Reconfigurable Butterfly Unit/pe_e2e_tb_n1024.sv" -log xvlog.log
