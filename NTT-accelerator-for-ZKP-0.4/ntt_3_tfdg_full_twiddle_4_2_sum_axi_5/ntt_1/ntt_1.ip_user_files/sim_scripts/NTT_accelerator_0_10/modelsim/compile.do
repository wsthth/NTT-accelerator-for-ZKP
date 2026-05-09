vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/twiddle_dyn_gen_NTT/montgomery_pipeline.v" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/seg_multiplier_64bit.v" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \

vlog -work xil_defaultlib -64 -incr -sv \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/reconfigurable_3d_pe_top.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/sim/NTT_accelerator_0.sv" \

vlog -work xil_defaultlib \
"glbl.v"

