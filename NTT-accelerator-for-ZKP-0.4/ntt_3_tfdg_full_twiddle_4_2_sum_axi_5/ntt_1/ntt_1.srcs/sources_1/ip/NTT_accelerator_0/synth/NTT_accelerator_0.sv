// (c) Copyright 1995-2026 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.


// IP VLNV: xilinx.com:user:NTT_accelerator:1.0
// IP Revision: 1

(* X_CORE_INFO = "reconfigurable_3d_pe_top,Vivado 2019.1" *)
(* CHECK_LICENSE_TYPE = "NTT_accelerator_0,reconfigurable_3d_pe_top,{}" *)
(* CORE_GENERATION_INFO = "NTT_accelerator_0,reconfigurable_3d_pe_top,{x_ipProduct=Vivado 2019.1,x_ipVendor=xilinx.com,x_ipLibrary=user,x_ipName=NTT_accelerator,x_ipVersion=1.0,x_ipCoreRevision=1,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED,MAX_WIDTH=128,MAX_RADIX=16,NUM_CORES=4}" *)
(* IP_DEFINITION_SOURCE = "package_project" *)
(* DowngradeIPIdentifiedWarnings = "yes" *)
module NTT_accelerator_0 (
  clk,
  rst_n,
  radix_mode,
  width_384_mode,
  parallelism,
  start,
  done,
  result_valid,
  data_in,
  twiddle_factors,
  modulus,
  N_prime,
  R2_mod_N,
  data_out
);

(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, PHASE 0.000, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
input wire clk;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
input wire rst_n;
input wire [1 : 0] radix_mode;
input wire width_384_mode;
input wire [2 : 0] parallelism;
input wire start;
output wire done;
output wire result_valid;
input wire [2047 : 0] data_in;
wire  [127:0] data_in_unpacked [0:15];
assign {>>{data_in_unpacked}} = data_in;
input wire [1023 : 0] twiddle_factors;
wire  [127:0] twiddle_factors_unpacked [0:7];
assign {>>{twiddle_factors_unpacked}} = twiddle_factors;
input wire [127 : 0] modulus;
input wire [127 : 0] N_prime;
input wire [127 : 0] R2_mod_N;
output wire [2047 : 0] data_out;
wire  [127:0] data_out_unpacked [0:15];
assign {>>{data_out}} = data_out_unpacked;

  reconfigurable_3d_pe_top #(
    .MAX_WIDTH(128),
    .MAX_RADIX(16),
    .NUM_CORES(4)
  ) inst (
    .clk(clk),
    .rst_n(rst_n),
    .radix_mode(radix_mode),
    .width_384_mode(width_384_mode),
    .parallelism(parallelism),
    .start(start),
    .done(done),
    .result_valid(result_valid),
    .data_in(data_in_unpacked),
    .twiddle_factors(twiddle_factors_unpacked),
    .modulus(modulus),
    .N_prime(N_prime),
    .R2_mod_N(R2_mod_N),
    .data_out(data_out_unpacked)
  );
endmodule
