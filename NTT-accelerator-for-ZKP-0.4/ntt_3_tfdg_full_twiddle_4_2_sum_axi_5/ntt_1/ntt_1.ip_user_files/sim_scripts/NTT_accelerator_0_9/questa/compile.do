vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xil_defaultlib

vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/src/twiddle_dyn_gen_NTT/montgomery_pipeline.v" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \

vlog -work xil_defaultlib -64 -sv \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/src/PE/Reconfigurable Butterfly Unit/reconfigurable_3d_pe_top.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_9/sim/NTT_accelerator_0.sv" \

vlog -work xil_defaultlib \
"glbl.v"

