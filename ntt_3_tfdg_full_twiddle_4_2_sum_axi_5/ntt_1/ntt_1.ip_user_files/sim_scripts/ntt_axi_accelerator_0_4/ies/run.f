-makelib ies_lib/xil_defaultlib \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/montgomery_mutiply_moduli/montgomery_pipeline.v" \
  "../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_4/hdl/ntt_axi_accelerator_v1_0_S00_AXI.v" \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/sub_pe/seg_multiplier_64bit.v" \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/sub_pe/segmented_256bit_full_butterfly.v" \
-endlib
-makelib ies_lib/xil_defaultlib -sv \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/reconfigurable_3d_pe_top.sv" \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/winograd_post_transform.sv" \
  "../../../../ntt_1.srcs/sources_1/ntt_ip/ip/src/PE/Reconfigurable Butterfly Unit/winograd_pre_transform.sv" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_4/hdl/ntt_axi_accelerator_v1_0.v" \
  "../../../../ntt_1.srcs/sources_1/ip/ntt_axi_accelerator_0_4/sim/ntt_axi_accelerator_0.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

