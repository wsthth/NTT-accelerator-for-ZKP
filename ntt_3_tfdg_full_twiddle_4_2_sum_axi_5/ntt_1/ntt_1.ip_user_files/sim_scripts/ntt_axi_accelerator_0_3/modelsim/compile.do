vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr "+incdir+../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/drivers/ntt_axi_accelerator_v1_0/src" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/montgomery_mutiply_moduli/montgomery_pipeline.v" \
"../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/hdl/ntt_axi_accelerator_v1_0_S00_AXI.v" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/sub_pe/seg_multiplier_64bit.v" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \

vlog -work xil_defaultlib -64 -incr -sv "+incdir+../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/drivers/ntt_axi_accelerator_v1_0/src" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/reconfigurable_3d_pe_top.sv" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \

vlog -work xil_defaultlib -64 -incr "+incdir+../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/drivers/ntt_axi_accelerator_v1_0/src" \
"../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/hdl/ntt_axi_accelerator_v1_0.v" \
"../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_3/sim/ntt_axi_accelerator_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

