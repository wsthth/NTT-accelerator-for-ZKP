@echo off
REM Compile all RTL files for N=1024 simulation
set SRC=F:/experiment/python/trae/ntt_axi/NTT-accelerator-for-ZKP-0.4/ntt_3_tfdg_full_twiddle_4_2_sum_axi_5/sour

xvlog -sv^
 %SRC%/PE/Reconfigurable%20Butterfly%20Unit/reconfigurable_3d_pe_top.sv^
 %SRC%/PE/Reconfigurable%20Butterfly%20Unit/winograd_pre_transform.sv^
 %SRC%/PE/Reconfigurable%20Butterfly%20Unit/winograd_post_transform.sv^
 %SRC%/PE/sub_pe/segmented_256bit_full_butterfly.v^
 %SRC%/montgomery_pipeline.v^
 %SRC%/PE/Reconfigurable%20Butterfly%20Unit/pe_e2e_tb_n1024.sv^
 -log xvlog.log

echo Compile done.
