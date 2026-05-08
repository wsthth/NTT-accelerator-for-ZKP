vlib work
vlib riviera

vlib riviera/xil_defaultlib

vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xil_defaultlib  -v2k5 \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/src/twiddle_dyn_gen_NTT/montgomery_pipeline.v" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \

vlog -work xil_defaultlib  -sv2k12 \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/src/PE/Reconfigurable Butterfly Unit/reconfigurable_3d_pe_top.sv" \
"../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_2/sim/NTT_accelerator_0.sv" \

vlog -work xil_defaultlib \
"glbl.v"

