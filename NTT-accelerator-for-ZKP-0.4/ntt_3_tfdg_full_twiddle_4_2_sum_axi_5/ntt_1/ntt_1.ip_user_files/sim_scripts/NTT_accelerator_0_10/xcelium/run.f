-makelib xcelium_lib/xil_defaultlib \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/twiddle_dyn_gen_NTT/montgomery_pipeline.v" \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/seg_multiplier_64bit.v" \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib -sv \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/src/reconfigurable_3d_pe_top.sv" \
  "../../../../ntt_1.srcs/sources_1/ip/NTT_accelerator_0_10/sim/NTT_accelerator_0.sv" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  glbl.v
-endlib

