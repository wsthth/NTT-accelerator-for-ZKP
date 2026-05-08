-- Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2019.1 (win64) Build 2552052 Fri May 24 14:49:42 MDT 2019
-- Date        : Sat Apr 18 16:27:28 2026
-- Host        : LAPTOP-96OTIR0P running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
--               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ NTT_accelerator_0_stub.vhdl
-- Design      : NTT_accelerator_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7v585tffg1157-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  Port ( 
    clk : in STD_LOGIC;
    rst_n : in STD_LOGIC;
    radix_mode : in STD_LOGIC_VECTOR ( 1 downto 0 );
    width_384_mode : in STD_LOGIC;
    parallelism : in STD_LOGIC_VECTOR ( 2 downto 0 );
    start : in STD_LOGIC;
    done : out STD_LOGIC;
    result_valid : out STD_LOGIC;
    data_in : in STD_LOGIC_VECTOR ( 2047 downto 0 );
    twiddle_factors : in STD_LOGIC_VECTOR ( 1023 downto 0 );
    modulus : in STD_LOGIC_VECTOR ( 127 downto 0 );
    N_prime : in STD_LOGIC_VECTOR ( 127 downto 0 );
    R2_mod_N : in STD_LOGIC_VECTOR ( 127 downto 0 );
    data_out : out STD_LOGIC_VECTOR ( 2047 downto 0 )
  );

end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix;

architecture stub of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,rst_n,radix_mode[1:0],width_384_mode,parallelism[2:0],start,done,result_valid,data_in[2047:0],twiddle_factors[1023:0],modulus[127:0],N_prime[127:0],R2_mod_N[127:0],data_out[2047:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "reconfigurable_3d_pe_top,Vivado 2019.1";
begin
end;
