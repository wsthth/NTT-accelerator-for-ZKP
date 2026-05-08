// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.1 (win64) Build 2552052 Fri May 24 14:49:42 MDT 2019
// Date        : Sat Apr 18 16:27:28 2026
// Host        : LAPTOP-96OTIR0P running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ NTT_accelerator_0_stub.v
// Design      : NTT_accelerator_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7v585tffg1157-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "reconfigurable_3d_pe_top,Vivado 2019.1" *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix(clk, rst_n, radix_mode, width_384_mode, 
  parallelism, start, done, result_valid, data_in, twiddle_factors, modulus, N_prime, R2_mod_N, 
  data_out)
/* synthesis syn_black_box black_box_pad_pin="clk,rst_n,radix_mode[1:0],width_384_mode,parallelism[2:0],start,done,result_valid,data_in[2047:0],twiddle_factors[1023:0],modulus[127:0],N_prime[127:0],R2_mod_N[127:0],data_out[2047:0]" */;
  input clk;
  input rst_n;
  input [1:0]radix_mode;
  input width_384_mode;
  input [2:0]parallelism;
  input start;
  output done;
  output result_valid;
  input [2047:0]data_in;
  input [1023:0]twiddle_factors;
  input [127:0]modulus;
  input [127:0]N_prime;
  input [127:0]R2_mod_N;
  output [2047:0]data_out;
endmodule
